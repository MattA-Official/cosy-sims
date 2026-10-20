class_name SecureArea
extends RefCounted
## Which ground is inside a perimeter: walls whose style is `secure` (a
## prison's perimeter fence, an airport's airside fence) enclose it, and a
## door or gate in one counts as shut. Flood-fills the ground level from
## the edge of your land; every tile it can't reach is secure. Angled walls
## don't count as perimeter.

var building: Building
## Ground tiles inside the perimeter.
var secure: Dictionary[Vector2i, bool] = {}
## Whether any perimeter is built at all.
var has_perimeter := false


func _init(on: Building = null) -> void:
	building = on


## Works it out again, after the build changes.
func refresh() -> void:
	secure.clear()
	has_perimeter = false
	var map := building.ground() if building != null else null
	if map == null or map.land.is_empty():
		return
	for edge: Vector3i in map.walls:
		if _blocks(map, edge):
			has_perimeter = true
			break
	if not has_perimeter:
		return
	var bounds := map.land_bounds()
	var reached: Dictionary[Vector2i, bool] = {}
	var queue: Array[Vector2i] = []
	for cell in BuildingMap.cells_in(bounds):
		if map.owns(cell) and _open_to_outside(map, cell):
			reached[cell] = true
			queue.append(cell)
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in BuildingMap.DIRECTIONS:
			var next: Vector2i = cell + step
			if reached.has(next) or not map.owns(next):
				continue
			if _blocks(map, BuildingMap.edge_between(cell, next)):
				continue
			reached[next] = true
			queue.append(next)
	for cell in BuildingMap.cells_in(bounds):
		if map.owns(cell) and not reached.has(cell):
			secure[cell] = true


func is_secure(cell: Vector2i) -> bool:
	return secure.has(cell)


## Whether a wall here is part of a perimeter.
static func _blocks(map: BuildingMap, edge: Vector3i) -> bool:
	if not map.walls.has(edge):
		return false
	var def := map.wall_def(map.wall_style(edge))
	return def != null and def.secure


## Whether a tile at the edge of your land opens straight onto land beyond
## it, with no perimeter in between.
static func _open_to_outside(map: BuildingMap, cell: Vector2i) -> bool:
	for step in BuildingMap.DIRECTIONS:
		if not map.owns(cell + step) and not _blocks(map, BuildingMap.edge_between(cell, cell + step)):
			return true
	return false
