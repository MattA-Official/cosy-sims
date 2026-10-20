class_name PreviewShapes
extends RefCounted
## The see-through shapes the build tools show under the mouse: tile
## highlights, wall outlines, objects, stairs and brush rings. The build
## controller decides what to show; this collects the shapes and draws them
## into one ImmediateMesh.

## The map being previewed on, for checking edges are on the grid.
var map: BuildingMap
var cell_size := 1.0
## The floor or ground height at a point in tile units.
var ground_at: Callable
## How tall wall previews stand.
var wall_height := 1.0

var _boxes: Array[Array] = [] ## [centre, half, colour] or [centre, half_a, colour, half_b, half_height].
var _polygons: Array[Array] = [] ## [points, colour] per flat polygon.


func clear() -> void:
	_boxes.clear()
	_polygons.clear()


func is_empty() -> bool:
	return _boxes.is_empty() and _polygons.is_empty()


func draw(mesh: ImmediateMesh, material: Material) -> void:
	if is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for polygon in _polygons:
		var points: PackedVector3Array = polygon[0]
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_set_color(polygon[1])
		# Both windings, so the slab shows whichever way the outline runs.
		for i in range(1, points.size() - 1):
			for vertex in [points[0], points[i], points[i + 1], points[0], points[i + 1], points[i]]:
				mesh.surface_add_vertex(vertex)
	for box in _boxes:
		if box.size() > 3:
			MeshShapes.add_oriented_box_immediate(mesh, box[0], box[1], box[3], box[4], box[2])
		else:
			MeshShapes.add_box_immediate(mesh, box[0], box[1], box[2])
	mesh.surface_end()


## Thin slabs over pieces of tiles, following angled walls. `base` sets one
## height for them all; by default each follows the ground.
func pieces(chosen: Array[TilePiece], colour: Color, base := NAN) -> void:
	for piece in chosen:
		var ground: float = base if not is_nan(base) else ground_at.call(piece.centre())
		var points := PackedVector3Array()
		for point in piece.polygon:
			var inset := point.lerp(piece.centre(), 0.04)
			points.append(Vector3(inset.x * cell_size, ground + 0.06, inset.y * cell_size))
		_polygons.append([points, colour])


## Tile highlights. `base` sets one height for them all; by default each
## follows the ground.
func cells(chosen: Array[Vector2i], colour: Color, base := NAN, height := 0.06) -> void:
	for cell in chosen:
		var ground: float = base if not is_nan(base) else ground_at.call(Vector2(cell) + Vector2(0.5, 0.5))
		var centre := Vector3(cell.x + 0.5, ground, cell.y + 0.5) * Vector3(cell_size, 1.0, cell_size)
		_boxes.append([centre + Vector3.UP * height * 0.5,
				Vector3(cell_size * 0.48, height * 0.5, cell_size * 0.48), colour])


## The stairs a click would leave: each tread at its height, standing on
## the floor at the foot.
func stairs(flight: Staircase, colour: Color) -> void:
	var base: float = ground_at.call(Vector2(flight.cells[0]) + Vector2(0.5, 0.5))
	for tread: Array in flight.treads():
		var points := PackedVector3Array()
		for p: Vector2 in tread[0]:
			points.append(Vector3(p.x * cell_size, base + tread[1] + 0.04, p.y * cell_size))
		_polygons.append([points, colour])


## A ring of small markers on the ground showing a brush's reach.
func ring(centre: Vector2, radius: float, colour: Color) -> void:
	var count := maxi(16, ceili(radius * 10.0))
	for i in count:
		var point := centre + Vector2.from_angle(TAU * i / count) * radius
		_boxes.append([Vector3(point.x * cell_size, ground_at.call(point) + 0.05, point.y * cell_size),
				Vector3(0.07, 0.05, 0.07), colour])


func rect(area: Rect2, colour: Color, height: float) -> void:
	var centre := area.get_center() * cell_size
	var ground: float = ground_at.call(area.get_center())
	_boxes.append([Vector3(centre.x, ground + height * 0.5, centre.y),
			Vector3(area.size.x * cell_size * 0.5, height * 0.5, area.size.y * cell_size * 0.5), colour])


## An object being placed, turned as it will go.
func object(def: ObjectDef, angle: float, centre: Vector2, colour: Color) -> void:
	var half := def.size * 0.5 * cell_size
	var along := Vector2(1, 0).rotated(angle)
	var height := def.height
	_boxes.append([Vector3(centre.x * cell_size, ground_at.call(centre) + height * 0.5, centre.y * cell_size),
			Vector3(along.x, 0.0, along.y) * half.x, colour,
			Vector3(-along.y, 0.0, along.x) * half.y, height * 0.5])


## An angled wall piece, standing on the floor or ground at its middle.
func slant(key: Vector4i, colour: Color) -> void:
	var ends := BuildingMap.slant_ends(key)
	var a := Vector2(ends[0])
	var b := Vector2(ends[1])
	var ground: float = ground_at.call((a + b) * 0.5)
	var flat := (b - a).normalized()
	var middle := (a + b) * 0.5 * cell_size
	_boxes.append([Vector3(middle.x, ground + wall_height * 0.5, middle.y),
			Vector3(flat.x, 0.0, flat.y) * a.distance_to(b) * cell_size * 0.5, colour,
			Vector3(-flat.y, 0.0, flat.x) * 0.1, wall_height * 0.5])


## A wall on an edge. `base` sets the height it stands at; by default it
## stands on the floor or ground beside it. Kept below full wall height so
## a big drag does not hide what is behind it.
func edge(on: Vector3i, colour: Color, base := NAN) -> void:
	if not map.edge_in_bounds(on):
		return
	var along := Vector3.RIGHT if on.z == BuildingMap.EDGE_X else Vector3.BACK
	var across := Vector3.BACK if on.z == BuildingMap.EDGE_X else Vector3.RIGHT
	var ground := base
	if is_nan(ground):
		ground = -INF
		for cell in BuildingMap.edge_cells(on):
			ground = maxf(ground, ground_at.call(Vector2(cell) + Vector2(0.5, 0.5)))
	var centre := Vector3(on.x, 0.0, on.y) * cell_size + along * cell_size * 0.5 \
			+ Vector3.UP * (ground + wall_height * 0.5)
	_boxes.append([centre, along * cell_size * 0.5 + across * 0.1 + Vector3.UP * wall_height * 0.5,
			colour])


## One side of a wall, for painting: a sheet standing just off that side.
func wall_side(wall: Variant, side: int, colour: Color) -> void:
	var ends := BuildingMap.wall_ends(wall)
	var flat := (ends[1] - ends[0]).normalized()
	var across := Vector2(-flat.y, flat.x) * (1.0 if side == 0 else -1.0)
	var middle := (ends[0] + ends[1]) * 0.5
	var ground: float = ground_at.call(middle + across * 0.25)
	var at := (middle * cell_size + across * 0.12)
	_boxes.append([Vector3(at.x, ground + wall_height * 0.5, at.y),
			Vector3(flat.x, 0.0, flat.y) * ends[0].distance_to(ends[1]) * cell_size * 0.5, colour,
			Vector3(across.x, 0.0, across.y) * 0.03, wall_height * 0.5])


func corner(at: Vector2i, colour: Color) -> void:
	var ground: float = ground_at.call(Vector2(at))
	_boxes.append([Vector3(at.x * cell_size, ground + 0.5, at.y * cell_size), Vector3(0.12, 0.5, 0.12),
			colour])
