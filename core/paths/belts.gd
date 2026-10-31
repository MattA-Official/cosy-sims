class_name Belts
extends RefCounted
## Conveyor belts, laid tile by tile like a path: each piece sits on one
## tile of floor (or open ground) on a level and carries things on to the
## tile it points at. Runs are dragged out as an L, along and then across,
## each piece pointing to the next; a run that ends on another belt feeds
## into it, which makes a merge. Pieces are worked out as straights,
## corners, merges, starts and ends from their neighbours, for drawing.
##
## Belts stand at waist height, so people walk round them, not over them.
## Bags and what moves along them come later; for now this is the track.
## Kept with the Building so they save and undo with everything else.

signal changed

## How high a belt's top is above the floor, in metres.
const HEIGHT := 0.45

## Each piece, as (x, y, level): the index into BuildingMap.DIRECTIONS it
## carries things towards.
var pieces: Dictionary[Vector3i, int] = {}


static func key(level: int, cell: Vector2i) -> Vector3i:
	return Vector3i(cell.x, cell.y, level)


func has(level: int, cell: Vector2i) -> bool:
	return pieces.has(key(level, cell))


## Which way the piece on a tile carries things, or Vector2i.ZERO if none.
func direction(level: int, cell: Vector2i) -> Vector2i:
	var k := key(level, cell)
	return BuildingMap.DIRECTIONS[pieces[k]] if pieces.has(k) else Vector2i.ZERO


## The tile the piece on `cell` hands on to, if a belt is there.
func next_cell(level: int, cell: Vector2i) -> Variant:
	var d := direction(level, cell)
	if d == Vector2i.ZERO or not has(level, cell + d):
		return null
	return cell + d


## The pieces that hand on to `cell`.
func feeds(level: int, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in BuildingMap.DIRECTIONS:
		var from: Vector2i = cell - d
		if direction(level, from) == d:
			out.append(from)
	return out


## What a piece is, for drawing: &"start" (nothing feeds it), &"end"
## (it feeds nothing), &"corner", &"merge" (more than one feeds it) or
## &"straight".
func kind_at(level: int, cell: Vector2i) -> StringName:
	if not has(level, cell):
		return &""
	var inputs := feeds(level, cell)
	if inputs.size() > 1:
		return &"merge"
	if next_cell(level, cell) == null:
		return &"end"
	if inputs.is_empty():
		return &"start"
	if cell - inputs[0] != direction(level, cell):
		return &"corner"
	return &"straight"


## The tiles a run from `start` to `end` covers: along, then across.
static func route(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var at := start
	var out: Array[Vector2i] = [at]
	while at.x != end.x:
		at.x += signi(end.x - at.x)
		out.append(at)
	while at.y != end.y:
		at.y += signi(end.y - at.y)
		out.append(at)
	return out


## Could a run go down along these tiles on a level? Each tile needs floor,
## or open ground you own on the ground level, with no wall or window
## between it and the next and no object in the way.
func can_lay(building: Building, level: int, cells: Array[Vector2i]) -> bool:
	var map: BuildingMap = building.levels.get(level)
	if map == null or cells.is_empty():
		return false
	for i in cells.size():
		var cell := cells[i]
		if not map.owns(cell) or map.holes.has(cell) or map.stairs_at(cell) != null:
			return false
		if not map.has_floor(cell) and level != 0:
			return false
		if map.blocks_at(Vector2(cell) + Vector2(0.5, 0.5)):
			return false
		if i > 0 and not map.passable(BuildingMap.edge_between(cells[i - 1], cell)):
			return false
	return true


## Lays a run along `cells`, each piece pointing to the next. The last
## points on in the run's last direction, so a run ending against another
## belt feeds into it. Returns how many pieces changed, or 0 if it can't go.
func lay(building: Building, level: int, cells: Array[Vector2i]) -> int:
	if not can_lay(building, level, cells):
		return 0
	var count := 0
	var heading := Vector2i.DOWN
	for i in cells.size():
		if i + 1 < cells.size():
			heading = cells[i + 1] - cells[i]
		elif i > 0:
			heading = cells[i] - cells[i - 1]
		var index := BuildingMap.DIRECTIONS.find(heading)
		var k := key(level, cells[i])
		if pieces.get(k, -1) != index:
			pieces[k] = index
			count += 1
	if count > 0:
		changed.emit()
	return count


## Takes up the pieces on these tiles. Returns how many went.
func remove(level: int, cells: Array[Vector2i]) -> int:
	var count := 0
	for cell in cells:
		if pieces.erase(key(level, cell)):
			count += 1
	if count > 0:
		changed.emit()
	return count


## Turns a piece round to carry things the other way.
func reverse(level: int, cell: Vector2i) -> bool:
	var k := key(level, cell)
	if not pieces.has(k):
		return false
	pieces[k] = BuildingMap.DIRECTIONS.find(-BuildingMap.DIRECTIONS[pieces[k]])
	changed.emit()
	return true


## Tiles with a belt on a level.
func cells_on(level: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: Vector3i in pieces:
		if k.z == level:
			out.append(Vector2i(k.x, k.y))
	return out


func to_data() -> Dictionary:
	return {"pieces": pieces.duplicate()}


func load_data(data: Dictionary) -> void:
	pieces.assign(data.get("pieces", {}))
	changed.emit()
