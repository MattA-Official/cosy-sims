class_name Building
extends RefCounted
## Every storey of the build, one BuildingMap per level. Level 0 is the
## ground; 1 and up are upper storeys; -1 and down are basements. Each
## level has its own floors, walls, objects and rooms; they share the land.
##
## Storeys are STOREY metres apart. A floor upstairs sits STOREY above the
## floor below it, and a basement floor STOREY below the ground or floor
## above it. Any floor can then be nudged up or down within its storey for
## split levels.

signal level_added(level: int, map: BuildingMap)
signal active_changed(level: int)
## Something changed on any level.
signal changed

const STOREY := 1.75

## Split levels: floors nudged up or down within their storey, and ramps
## drawn between them. Off for now to keep levels simple: every floor then
## sits a whole storey above the one below. Turn it on from the Main node
## (Split Levels) or by setting this.
static var split_levels := false
## Door steps: a door between floors at different heights (up to
## BuildingMap.DOOR_STEPS_MAX apart) gets a small set of steps on the low
## side. Off for now, so such doors are refused instead. Turn it on from
## the Main node (Door Steps) or by setting this.
static var door_steps := false
const MIN_LEVEL := -2
const MAX_LEVEL := 4

var land: Array[Rect2i] = []
var levels: Dictionary[int, BuildingMap] = {}
## The level the player is looking at and building on.
var active := 0:
	set(value):
		value = clampi(value, MIN_LEVEL, MAX_LEVEL)
		if value == active:
			return
		active = value
		level(value)
		active_changed.emit(value)

## A way between two levels: the tile you set off from and the tile you
## arrive on.
class Link:
	enum Kind { STAIRS, LIFT }
	var kind: Kind
	var from_level: int
	var from_cell: Vector2i
	var to_level: int
	var to_cell: Vector2i


var _floor_defs: Array[FloorDef] = []
var _syncing := false
var _wall_defs: Array[WallDef] = []


func _init(starting_land: Rect2i, floor_list: Array[FloorDef] = [],
		wall_list: Array[WallDef] = []) -> void:
	land.append(starting_land)
	_floor_defs = floor_list
	_wall_defs = wall_list
	level(0)


## The map for a level, made the first time it is asked for.
func level(n: int) -> BuildingMap:
	if levels.has(n):
		return levels[n]
	var map := BuildingMap.new(land[0])
	for rect in land.slice(1):
		map.land.append(rect)
	map.register_styles(_floor_defs, _wall_defs)
	map.changed.connect(_on_level_changed)
	levels[n] = map
	level_added.emit(n, map)
	return map


func ground() -> BuildingMap:
	return levels[0]


func current() -> BuildingMap:
	return level(active)


func add_land(rect: Rect2i) -> void:
	land.append(rect)
	for map: BuildingMap in levels.values():
		map.add_land(rect)


## Levels in order from the lowest basement up.
func sorted_levels() -> Array[int]:
	var out: Array[int] = []
	out.assign(levels.keys())
	out.sort()
	return out


## Whether a tile on a level has something to stand on: upper floors need
## floor on the level below; the ground and basements always do.
func is_supported(n: int, cell: Vector2i) -> bool:
	if n <= 0:
		return true
	return levels.has(n - 1) and levels[n - 1].has_floor(cell)


## The height new floor on level `n` would go in at, over a tile: a storey
## above the floor below, or a storey below the floor above (or the ground,
## for the top basement). NAN on the ground level, where the terrain decides.
func storey_height(n: int, cell: Vector2i, ground_height: float) -> float:
	if n == 0:
		return NAN
	var step := -1 if n > 0 else 1
	var next := n + step # The neighbouring level towards the ground.
	var base := ground_height
	if levels.has(next) and levels[next].has_floor(cell):
		base = levels[next].floor_height(cell)
	elif next != 0:
		base = storey_height(next, cell, ground_height)
	return base - step * STOREY


## Is anything built at this terrain corner, on the ground or below it?
## Stops sculpting under buildings and over basements.
func corner_in_use(corner: Vector2i) -> bool:
	for n: int in levels:
		if n <= 0 and levels[n].corner_in_use(corner):
			return true
	return false


## Can an object go on a level?
func can_place(n: int, def: ObjectDef, centre: Vector2, angle: float) -> bool:
	if def.connects != ObjectDef.Connects.NONE:
		angle = snappedf(angle, PI * 0.5)
	return level(n).can_place_at(def, centre, angle)


## Can stairs run along a route on a level? They need a level above.
func can_add_stairs(n: int, route: Array[Vector2i]) -> bool:
	return n < MAX_LEVEL and level(n).can_add_stairs(route)


## Every stair and lift link, both ways for stairs and lifts alike.
func links() -> Array[Link]:
	var out: Array[Link] = []
	for n: int in levels:
		for placed: BuildingMap.PlacedObject in levels[n].objects.values():
			if placed.def.connects == ObjectDef.Connects.LIFT and _lift_above(n, placed) != null:
				var cell := Vector2i(placed.rect.get_center().floor())
				_add_link(out, Link.Kind.LIFT, n, cell, n + 1, cell)
		for flight: Staircase in levels[n].stairs.values():
			_add_link(out, Link.Kind.STAIRS, n, flight.entry(), n + 1, flight.exit())
	return out


## A friendly name for a level.
static func level_name(n: int) -> String:
	if n == 0:
		return "Ground floor"
	if n < 0:
		return "Basement %d" % -n
	return "Floor %d" % n


func _add_link(out: Array[Link], kind: Link.Kind, from_level: int, from_cell: Vector2i,
		to_level: int, to_cell: Vector2i) -> Link:
	for way in 2:
		var link := Link.new()
		link.kind = kind
		link.from_level = from_level if way == 0 else to_level
		link.from_cell = from_cell if way == 0 else to_cell
		link.to_level = to_level if way == 0 else from_level
		link.to_cell = to_cell if way == 0 else from_cell
		out.append(link)
	return out[-1]


func _lift_above(n: int, lift: BuildingMap.PlacedObject) -> BuildingMap.PlacedObject:
	if not levels.has(n + 1):
		return null
	for placed: BuildingMap.PlacedObject in levels[n + 1].objects.values():
		if placed.def.connects == ObjectDef.Connects.LIFT and placed.rect.is_equal_approx(lift.rect):
			return placed
	return null


func _on_level_changed() -> void:
	if not _syncing:
		_sync_holes()
	changed.emit()


## Cuts the floor above every flight of stairs. Where stairs have gone, the
## tiles above are free for floor again.
func _sync_holes() -> void:
	_syncing = true
	var holes: Dictionary[int, Dictionary] = {}
	for n: int in levels.keys():
		if n >= MAX_LEVEL:
			continue
		for flight: Staircase in levels[n].stairs.values():
			var cells: Dictionary = holes.get_or_add(n + 1, {})
			for cell in flight.cells:
				cells[cell] = true
	for n: int in holes:
		level(n)
	for n: int in levels.keys():
		var cells: Dictionary[Vector2i, bool] = {}
		cells.assign(holes.get(n, {}))
		levels[n].set_holes(cells)
	_syncing = false
