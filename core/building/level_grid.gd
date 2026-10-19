class_name LevelGrid
extends Node3D
## Grid lines over your land at the height of the level being built on,
## so upstairs and in basements you can see where tiles are without the
## ground's own grid. Tiles with floor show at that floor's height; open
## tiles show on one flat sheet at the level's usual height, so the grid
## stays tidy over hills instead of stepping with the ground below.

@export var grid: BuildGrid
@export var colour := Color(1.0, 1.0, 1.0, 0.35)

var building: Building:
	set(value):
		building = value
		if building != null:
			building.changed.connect(queue_rebuild)
			building.active_changed.connect(func(_level: int) -> void: queue_rebuild())
		queue_rebuild()
## The height of a tile on the level being built on.
var height_at: Callable

var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
var _queued := false


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	queue_rebuild()


func queue_rebuild() -> void:
	if not _queued:
		_queued = true
		rebuild.call_deferred()


func rebuild() -> void:
	_queued = false
	_mesh.clear_surfaces()
	if building == null or building.active == 0 or not height_at.is_valid():
		return
	var cs := grid.cell_size if grid != null else 1.0
	var level_map := building.current()
	var sheet := sheet_height()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	_mesh.surface_set_color(colour)
	for rect in building.land:
		for cell in BuildingMap.cells_in(rect):
			var h: float = height_at.call(cell) if level_map.has_floor(cell) else sheet
			var y := h + 0.02
			var a := Vector3(cell.x, y, cell.y) * Vector3(cs, 1.0, cs)
			var corners := [a, a + Vector3(cs, 0, 0), a + Vector3(cs, 0, cs), a + Vector3(0, 0, cs)]
			for i in 4:
				_mesh.surface_add_vertex(corners[i])
				_mesh.surface_add_vertex(corners[(i + 1) % 4])
	_mesh.surface_end()


## The usual height of the level being built on: the commonest floor height
## on it, else the commonest height over the floors next to it towards the
## ground, else the commonest height over the land.
func sheet_height() -> float:
	var active := building.active
	var toward := active - signi(active)
	var sources: Array[BuildingMap] = []
	for n in [active, toward]:
		var map := building.levels.get(n) as BuildingMap
		if map != null:
			sources.append(map)
	for map in sources:
		var counts: Dictionary[float, int] = {}
		for rect in building.land:
			for cell in BuildingMap.cells_in(rect):
				if map.has_floor(cell):
					var h := snappedf(height_at.call(cell), 0.25)
					counts[h] = counts.get(h, 0) + 1
		if not counts.is_empty():
			return _commonest(counts)
	var all: Dictionary[float, int] = {}
	for rect in building.land:
		for cell in BuildingMap.cells_in(rect):
			var h := snappedf(height_at.call(cell), 0.25)
			all[h] = all.get(h, 0) + 1
	return _commonest(all)


static func _commonest(counts: Dictionary[float, int]) -> float:
	var best := 0.0
	var best_count := -1
	for h: float in counts:
		if counts[h] > best_count or (counts[h] == best_count and h < best):
			best = h
			best_count = counts[h]
	return best
