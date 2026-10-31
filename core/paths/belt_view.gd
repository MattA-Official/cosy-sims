class_name BeltView
extends Node3D
## Draws the conveyor belts (see Belts): a frame on legs at waist height on
## each tile, reaching across to the pieces it joins, with a dark running
## surface and chevrons the way it carries things. Levels above
## `top_level` are hidden, as the building's are.

const WIDTH := 0.7 ## Of the running surface, in tiles.
const FRAME := 0.06 ## The rim either side of it.
const BELT_COLOUR := Color(0.24, 0.25, 0.27)
const FRAME_COLOUR := Color(0.62, 0.66, 0.7)
const ARROW_COLOUR := Color(0.95, 0.78, 0.32)

var building: Building:
	set(value):
		if building != null and building.belts.changed.is_connected(queue_rebuild):
			building.belts.changed.disconnect(queue_rebuild)
		building = value
		if building != null:
			building.belts.changed.connect(queue_rebuild)
			building.changed.connect(queue_rebuild)
		queue_rebuild()
var terrain: Terrain
var cell_size := 1.0
## The highest level drawn; belts on levels above are hidden.
var top_level := 99:
	set(value):
		if value != top_level:
			top_level = value
			queue_rebuild()

var _mesh := MeshInstance3D.new()
var _queued := false


func _init() -> void:
	_mesh.material_override = MeshShapes.vertex_colour_material()
	add_child(_mesh)


func queue_rebuild() -> void:
	if _queued:
		return
	_queued = true
	(func() -> void:
		_queued = false
		rebuild()).call_deferred()


func rebuild() -> void:
	if building == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var belts := building.belts
	for k: Vector3i in belts.pieces:
		var level := k.z
		if level > top_level or not building.levels.has(level):
			continue
		var cell := Vector2i(k.x, k.y)
		var floor_y := _floor_at(level, cell)
		var out := belts.direction(level, cell)
		var sides: Array[Vector2i] = [out]
		sides.append_array(belts.feeds(level, cell).map(func(from: Vector2i) -> Vector2i: return from - cell))
		var middle := (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
		var top := floor_y + Belts.HEIGHT
		var half := WIDTH * 0.5 * cell_size
		# The middle square, and a half-tile reach to each joined side.
		_add_deck(st, middle, Vector2(half, half), top)
		for side in sides:
			var reach := Vector2(side) * 0.25 * cell_size
			var size := Vector2(absf(side.x) * 0.25 * cell_size if side.x != 0 else half,
					absf(side.y) * 0.25 * cell_size if side.y != 0 else half)
			_add_deck(st, middle + reach, size, top)
		# Legs under it.
		MeshShapes.add_box(st, Vector3(middle.x, (floor_y + top) * 0.5 - 0.04, middle.y),
				Vector3(0.05, (top - floor_y) * 0.5 - 0.04, 0.05) * Vector3(cell_size, 1.0, cell_size), FRAME_COLOUR)
		# A chevron the way it runs.
		var ahead := Vector2(out) * cell_size
		var across := Vector2(-ahead.y, ahead.x)
		var y := top + 0.012
		var tip := middle + ahead * 0.28
		var left := middle - ahead * 0.12 + across * 0.22
		var right := middle - ahead * 0.12 - across * 0.22
		var notch := middle + ahead * 0.02
		st.set_normal(Vector3.UP)
		st.set_color(ARROW_COLOUR)
		for tri: Array in [[left, tip, notch], [notch, tip, right]]:
			for point: Vector2 in tri + [tri[0], tri[2], tri[1]]:
				st.add_vertex(Vector3(point.x, y, point.y))
		any = true
	_mesh.mesh = st.commit() if any else null


## A stretch of deck: the dark running surface with a pale rim and sides.
func _add_deck(st: SurfaceTool, centre: Vector2, half: Vector2, top: float) -> void:
	MeshShapes.add_box(st, Vector3(centre.x, top - 0.08, centre.y), Vector3(half.x, 0.08, half.y),
			FRAME_COLOUR, BELT_COLOUR)


func _floor_at(level: int, cell: Vector2i) -> float:
	var map: BuildingMap = building.levels[level]
	if map.has_floor(cell):
		return map.floor_height(cell)
	if terrain != null:
		return terrain.height_at(Vector2(cell) + Vector2(0.5, 0.5))
	return 0.0
