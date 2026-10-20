class_name BuildingView
extends Node3D
## Draws a BuildingMap: floors and walls built in code (each style's colour
## with its texture over it), doors and objects from their models (or boxes
## where they have none), a floating label over each room that has a type,
## and flat roofs over indoor rooms with no floor above them.
## Rebuilds everything whenever the map changes, which is plenty fast at
## prototype sizes.

@export var grid: BuildGrid
## Optional: buildings sit on the terrain's height instead of y = 0.
@export var terrain: Terrain
@export var room_types: Array[RoomTypeDef] = []
## Which storey this view draws. Off the ground, floors are slabs of
## `slab_depth` rather than foundations reaching into the terrain.
@export var level := 0
@export var slab_depth := 0.28
## Room labels show only on the level being built on.
@export var show_labels := true:
	set(value):
		show_labels = value
		queue_rebuild()

@export_group("Walls")
@export var wall_height := 1.5
@export var low_wall_height := 0.25 ## Height when walls are cut away.
@export var wall_thickness := 0.15
@export var door_height := 1.15
@export var window_sill := 0.5
@export var window_head := 1.15
## Drawn in each doorway when walls are up. Without one doors are a slab of
## `door_colour`.
@export var door_model: PackedScene
## Models for doors of a kind (see DoorKindDef), such as a security gate,
## in place of `door_model`.
@export var door_models: Dictionary[StringName, PackedScene] = {}
@export var walls_low := false:
	set(value):
		walls_low = value
		queue_rebuild()
## Cutaway: like The Sims, only walls with floor behind them (as the camera
## looks) drop low, so you see into rooms but the far walls stay up.
@export var cutaway := false:
	set(value):
		cutaway = value
		queue_rebuild()
## Which way the camera looks across the ground, for cutaway. Snapped to
## eighths of a turn so walls only change as you rotate past each one.
var cut_direction := Vector2(1, 1).normalized():
	set(value):
		if value.is_zero_approx():
			return
		var snapped := Vector2.RIGHT.rotated(snappedf(value.angle(), PI / 4.0))
		if snapped.is_equal_approx(cut_direction):
			return
		cut_direction = snapped
		if cutaway:
			queue_rebuild()

@export_group("Roofs")
## Roofs show when looking from a level above this one (see Building
## views in main.gd). Toggling this is cheap: the roof is always built.
@export var show_roof := false:
	set(value):
		show_roof = value
		_roof_mesh.visible = value
@export var roof_thickness := 0.12
@export var roof_colour := Color(0.5, 0.47, 0.45)

@export_group("Colours")
## Used for floors and walls whose style the map does not know.
@export var floor_colour := Color(0.74, 0.72, 0.68)
@export var wall_colour := Color(0.93, 0.88, 0.8)
@export var wall_top_colour := Color(0.36, 0.32, 0.3)
@export var door_colour := Color(0.5, 0.61, 0.6)
## Stairs whose floor style is missing.
@export var stairs_colour := Color(0.72, 0.56, 0.4)
@export var glass_colour := Color(0.7, 0.88, 1.0, 0.35)
@export var bars_colour := Color(0.3, 0.32, 0.36)
@export var problem_colour := Color(1.0, 0.55, 0.45)
@export var land_edge_colour := Color(0.36, 0.5, 0.3)
@export var foundation_colour := Color(0.62, 0.6, 0.57)

## How far floors and walls reach down into the ground, so they never
## float above a slope.
const FOUNDATION_DEPTH := 0.6

var map: BuildingMap:
	set(value):
		if map != null:
			map.changed.disconnect(queue_rebuild)
			map.dressing_changed.disconnect(_queue_objects)
		map = value
		if map != null:
			map.changed.connect(queue_rebuild)
			map.dressing_changed.connect(_queue_objects)
		queue_rebuild()

## The level above, if any: roofs leave out tiles it has floor on.
var above: BuildingMap:
	set(value):
		if above != null:
			above.changed.disconnect(queue_rebuild)
		above = value
		if above != null:
			above.changed.connect(queue_rebuild)
		queue_rebuild()

var _roof_mesh := MeshInstance3D.new()
var _floor_mesh := MeshInstance3D.new()
var _wall_mesh := MeshInstance3D.new()
var _glass_mesh := MeshInstance3D.new()
var _objects := Node3D.new()
var _objects_queued := false
var _stairs_material := MeshShapes.vertex_colour_material()
var _labels := Node3D.new()
## What the labels were last decluttered for (camera, screen size and the
## labels themselves), so it only happens again when one of them changes.
var _declutter_key: Array = []
## The labels most important first, each with its rough size on a 900 px
## high screen: [label, size].
var _ranked: Array[Array] = []
var _material := MeshShapes.vertex_colour_material()
var _glass_material := _make_glass_material()
var _object_materials := {} # Color -> StandardMaterial3D
## Vertex-coloured materials with a texture over the colour, shared by
## every level.
static var _textured_materials := {} # Texture2D -> StandardMaterial3D
var _doors := Node3D.new()
var _rebuild_queued := false
## Shared by every level's labels.
static var _label_font := CosyTheme.bold_font()
## While walls are being built: their surfaces by texture, the glass, and
## the corners that already have a fence post.
var _surfaces := {} # Texture2D -> SurfaceTool
var _glass: SurfaceTool
var _has_glass := false
var _posts := {} # Vector2i -> true


## How one side of a wall looks: its colour, texture and dado.
class Finish:
	var colour := Color.WHITE
	var texture: Texture2D
	var dado := Color(0, 0, 0, 0)
	var dado_height := 0.0


## One wall piece being drawn. Lengths along it are in metres from `start`,
## and side 0 is the side `across` points to (see BuildingMap.wall_side).
class WallRun:
	var wall: Variant
	var corners: Array[Vector2i] = []
	var start := Vector2.ZERO
	var along := Vector2.RIGHT
	var across := Vector2.DOWN
	var length := 1.0
	var half := 0.075 ## Half the thickness.
	var def: WallDef
	var kind := 0
	var window: StringName
	var base := 0.0
	var drop := 0.0
	var low := false
	var height := 1.5 ## As drawn: low when cut away.
	var full_height := 1.5
	var top_colour := Color.BLACK
	var own: Finish
	var finishes: Array[Finish] = []
	## Where each side's face starts and ends, after joining the walls at
	## each corner: [side 0, side 1].
	var side_from: Array[float] = [0.0, 0.0]
	var side_to: Array[float] = [0.0, 0.0]

	func solid() -> bool:
		return def == null or not def.see_through

	## The way the wall leaves one of its corners.
	func leaving(at_start: bool) -> Vector2:
		return along if at_start else -along

	## Where a side's face stops at one end, as a distance from that corner
	## going into the wall. `left` is the side to the left going in.
	func set_end(at_start: bool, left: bool, distance: float) -> void:
		var side := 0 if left == at_start else 1
		if at_start:
			side_from[side] = distance
		else:
			side_to[side] = length - distance

	## A point on one side of the wall, `distance` along it. `width` moves
	## it in towards the middle.
	func side_point(side: int, distance: float, width := 1.0) -> Vector2:
		return start + along * distance + across * half * width * (1.0 if side == 0 else -1.0)


func _ready() -> void:
	for child: Node in [_floor_mesh, _wall_mesh, _glass_mesh, _doors, _objects, _labels, _roof_mesh]:
		add_child(child)
	_roof_mesh.material_override = _material
	_roof_mesh.visible = show_roof
	_glass_mesh.material_override = _glass_material
	_glass_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if terrain != null:
		terrain.changed.connect(_on_terrain_changed)


func _on_terrain_changed() -> void:
	if map == null or map.has_build_near(terrain.last_changed):
		queue_rebuild()


func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


## Redraws only the objects, for dressing that changed.
func _queue_objects() -> void:
	if _rebuild_queued or _objects_queued:
		return
	_objects_queued = true
	(func() -> void:
		_objects_queued = false
		if map != null and is_inside_tree():
			_build_objects()).call_deferred()


func room_type(id: StringName) -> RoomTypeDef:
	for def in room_types:
		if def.id == id:
			return def
	return null


func rebuild() -> void:
	_rebuild_queued = false
	if map == null or not is_inside_tree():
		return
	_build_floors()
	_build_walls()
	_build_objects()
	_build_labels()
	_build_roof()


## Flat roofs at the top of the walls, over every piece of an indoor room
## that has no floor above it. Stairs going up are left open, and the top
## of a stairwell coming up from below is roofed over.
func _build_roof() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cs := grid.cell_size
	var any := false
	for cell: Vector2i in map.holes:
		var height := _stairwell_roof(cell)
		if not is_nan(height):
			var square := PackedVector2Array([Vector2(cell), Vector2(cell) + Vector2(1, 0),
					Vector2(cell) + Vector2.ONE, Vector2(cell) + Vector2(0, 1)])
			for i in square.size():
				square[i] *= cs
			MeshShapes.add_prism(st, square, height - roof_thickness, height + 0.01,
					roof_colour.darkened(0.2), roof_colour)
			any = true
	for cell: Vector2i in map.floors:
		if above != null and (above.has_floor(cell) or above.holes.has(cell)):
			continue
		for piece: TilePiece in map.pieces(cell):
			if not map.piece_has_floor(piece):
				continue
			var middle := Vector2.ZERO
			for point in piece.polygon:
				middle += point
			middle /= maxi(piece.polygon.size(), 1)
			var room := map.room_at_point(middle)
			if room == null or not room.indoor:
				continue
			var scaled := PackedVector2Array()
			for point in piece.polygon:
				scaled.append(point * cs)
			var top := map.floor_height(cell) + wall_height
			MeshShapes.add_prism(st, scaled, top - roof_thickness, top + 0.01, roof_colour.darkened(0.2),
					roof_colour.lightened(0.04 * ((cell.x + cell.y) % 2)))
			any = true
	_roof_mesh.mesh = st.commit() if any else null


## Is there a roof over this tile? For tests and the debug view.
func has_roof(cell: Vector2i) -> bool:
	if map.holes.has(cell):
		return not is_nan(_stairwell_roof(cell))
	if not map.has_floor(cell) or (above != null and (above.has_floor(cell) or above.holes.has(cell))):
		return false
	var room := map.room_at(cell)
	return room != null and room.indoor


## The roof height over a stairwell's top on this level, from the indoor
## floor beside it, or NAN if it has none (or the floor above covers it).
func _stairwell_roof(cell: Vector2i) -> float:
	if above != null and above.has_floor(cell):
		return NAN
	for side in BuildingMap.DIRECTIONS:
		var next: Vector2i = cell + side
		var room := map.room_at(next) if map.has_floor(next) else null
		if room != null and room.indoor:
			return map.floor_height(next) + wall_height
	return NAN


func _build_floors() -> void:
	var surfaces := {} # Texture2D -> SurfaceTool
	var cs := grid.cell_size
	for room in map.rooms():
		var type := room_type(room.type)
		for id in room.pieces:
			var cell := Vector2i(id.x, id.y)
			var piece: TilePiece = map.pieces(cell)[id.z]
			var def := map.floor_def(map.piece_floor(piece))
			var colour := def.colour if def != null else floor_colour
			var st := _surface(surfaces, def.texture if def != null else null)
			if type != null:
				colour = colour.lerp(type.colour, 0.35)
			# A faint checkerboard makes floors read as tiles.
			var shade := 1.0 if (cell.x + cell.y) % 2 == 0 else 0.95
			var top_y := map.floor_height(cell) + 0.03
			var bottom := _lowest_ground(cell) - FOUNDATION_DEPTH if level == 0 \
					else top_y - slab_depth
			var centre := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * cs
			# The top face takes the floor colour; the sides show as foundations
			# reaching down into the ground.
			if not piece.is_whole():
				_add_floor_piece(st, piece, top_y, bottom, colour * shade)
				continue
			var ramp := map.ramp_at(cell)
			if ramp != null:
				_add_ramp_tile(st, cell, ramp, bottom, colour * shade)
				continue
			var depth := top_y - bottom
			MeshShapes.add_box(st, centre + Vector3.UP * (top_y - depth * 0.5),
					Vector3(0.5 * cs, depth * 0.5, 0.5 * cs), foundation_colour, colour * shade)
			_add_split_steps(st, cell, top_y, colour * shade)
	if level == 0:
		_add_land_edge(_surface(surfaces, null))
	elif map.floors.is_empty():
		_floor_mesh.mesh = null
		return
	_floor_mesh.mesh = _commit(surfaces)


## The SurfaceTool for geometry wearing `texture` (or none), started the
## first time it is asked for.
func _surface(surfaces: Dictionary, texture: Texture2D) -> SurfaceTool:
	if not surfaces.has(texture):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[texture] = st
	return surfaces[texture]


## One mesh with a surface for each texture, each with its own material.
func _commit(surfaces: Dictionary) -> ArrayMesh:
	if surfaces.is_empty():
		return null
	var mesh := ArrayMesh.new()
	for texture: Texture2D in surfaces:
		(surfaces[texture] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _textured_material(texture))
	return mesh


func _textured_material(texture: Texture2D) -> StandardMaterial3D:
	if texture == null:
		return _material
	if not _textured_materials.has(texture):
		var material := MeshShapes.vertex_colour_material()
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_textured_materials[texture] = material
	return _textured_materials[texture]


## Where a neighbouring floor is up to MAX_STEP higher, with nothing in
## between, a half-height step on this tile makes the climb read as two
## easy steps rather than one tall one.
func _add_split_steps(st: SurfaceTool, cell: Vector2i, top_y: float, colour: Color) -> void:
	var cs := grid.cell_size
	for step in BuildingMap.DIRECTIONS:
		var next := cell + step
		if not map.has_floor(next) or not map.can_walk_between(cell, next) \
				or map.ramp_at(next) != null:
			continue
		var rise := map.floor_height(next) - map.floor_height(cell)
		if rise <= BuildingMap.MAX_STEP * 0.5:
			continue
		var tread := 0.3 * cs
		var dir := Vector3(step.x, 0.0, step.y)
		var across := Vector3(absf(step.y), 0.0, absf(step.x))
		var centre := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * cs + dir * (0.5 * cs - tread * 0.5)
		var half_rise := rise * 0.25
		MeshShapes.add_box(st, centre + Vector3.UP * (top_y + half_rise),
				across * 0.5 * cs + dir * tread * 0.5 + Vector3.UP * half_rise, colour.darkened(0.1),
				colour)


## Part of a tile cut by an angled wall: its outline as a flat top, with
## sides reaching down to `bottom`.
func _add_floor_piece(st: SurfaceTool, piece: TilePiece, top_y: float, bottom: float,
		colour: Color) -> void:
	var cs := grid.cell_size
	var top: Array[Vector3] = []
	for point in piece.polygon:
		top.append(Vector3(point.x * cs, top_y, point.y * cs))
	MeshShapes.add_polygon(st, top, Vector3.UP, colour)
	var centre := piece.centre()
	for i in top.size():
		var a := top[i]
		var b := top[(i + 1) % top.size()]
		var outward := Vector3((a.x + b.x) * 0.5 - centre.x * cs, 0.0, (a.z + b.z) * 0.5 - centre.y * cs)
		MeshShapes.add_quad(st, a, b, Vector3(b.x, bottom, b.z), Vector3(a.x, bottom, a.z),
				outward.normalized(), foundation_colour)


## One tile of a ramp: a sloped top over sides reaching down to `bottom`.
func _add_ramp_tile(st: SurfaceTool, cell: Vector2i, ramp: BuildingMap.Ramp, bottom: float,
		colour: Color) -> void:
	var cs := grid.cell_size
	var corners: Array[Vector3] = []
	for offset: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var point := Vector2(cell) + offset
		corners.append(Vector3(point.x * cs, ramp.height_at(point) + 0.03, point.y * cs))
	var centre := (Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * cs)
	MeshShapes.add_quad(st, corners[0], corners[1], corners[2], corners[3], Vector3.UP, colour)
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var outward := ((a + b) * 0.5 - centre)
		outward.y = 0.0
		MeshShapes.add_quad(st, a, b, Vector3(b.x, bottom, b.z), Vector3(a.x, bottom, a.z), outward.normalized(),
				foundation_colour)


## A low kerb around the land you own, so you can see where you may build.
func _add_land_edge(st: SurfaceTool) -> void:
	var cs := grid.cell_size
	var bounds := map.land_bounds().grow(1)
	for edge in BuildingMap.rect_edges(bounds):
		var sides := BuildingMap.edge_cells(edge)
		if map.owns(sides[0]) == map.owns(sides[1]):
			continue
		var along := Vector3.RIGHT if edge.z == BuildingMap.EDGE_X else Vector3.BACK
		var across := Vector3.BACK if edge.z == BuildingMap.EDGE_X else Vector3.RIGHT
		var middle := Vector3(edge.x, 0.0, edge.y) * cs + along * cs * 0.5
		middle.y = _height_at(Vector2(middle.x, middle.z) / cs)
		MeshShapes.add_box(st, middle + Vector3.UP * 0.03,
				along * cs * 0.5 + across * 0.06 + Vector3.UP * 0.03, land_edge_colour)


func _build_walls() -> void:
	for child in _doors.get_children():
		child.queue_free()
	_surfaces = {}
	_glass = SurfaceTool.new()
	_glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	_has_glass = false
	_posts = {}
	var runs: Array[WallRun] = []
	for edge: Vector3i in map.walls:
		var ends := BuildingMap.edge_ends(edge)
		var base := _wall_base(edge)
		# Foundations reach below the lowest ground at either end; upstairs
		# walls reach the underside of the floor slab, so they look whole from
		# a stairwell.
		var drop := base - minf(_height_at(ends[0]), _height_at(ends[1])) + FOUNDATION_DEPTH \
				if level == 0 else base - _lowest_floor_beside(edge) + slab_depth
		runs.append(_make_run(edge, base, drop, map.wall_at(edge), map.window_kind(edge)))
	for key: Vector4i in map.slants:
		var ends := BuildingMap.wall_ends(key)
		var highest := -INF
		var lowest := INF
		for cell in BuildingMap.slant_crossings(key):
			if map.has_floor(cell):
				highest = maxf(highest, map.floor_height(cell))
				lowest = minf(lowest, map.floor_height(cell))
		var base := highest if highest > -INF else _height_at((ends[0] + ends[1]) * 0.5)
		var drop := base - minf(_height_at(ends[0]), _height_at(ends[1])) + FOUNDATION_DEPTH \
				if level == 0 else base - (lowest if lowest < INF else base) + slab_depth
		runs.append(_make_run(key, base, drop, map.slant_at(key), map.slant_window_kind(key)))
	var hubs := _join_walls(runs)
	for run in runs:
		_add_wall_run(run)
	for hub: Array in hubs:
		_add_hub(hub[0], hub[1])
	_wall_mesh.mesh = _commit(_surfaces)
	_glass_mesh.mesh = _glass.commit() if _has_glass else null
	_surfaces = {}


## Does a wall stand in front of floor, as the camera looks? Then cutaway
## drops it. Walls running along the line of sight stay up.
func _cut_away(start: Vector2, end: Vector2) -> bool:
	var flat := (end - start).normalized()
	var normal := Vector2(-flat.y, flat.x)
	var facing := normal.dot(cut_direction)
	if absf(facing) < 0.2:
		return false
	var behind := (start + end) * 0.5 + normal * signf(facing) * 0.5
	return map.has_floor(Vector2i(behind.floor()))


## Is this stretch of wall drawn low, in the current view? For tests.
func is_cut(start: Vector2, end: Vector2) -> bool:
	return walls_low or (cutaway and _cut_away(start, end))


func _make_run(wall: Variant, base: float, drop: float, kind: int, window: StringName) -> WallRun:
	var cs := grid.cell_size
	var ends := BuildingMap.wall_ends(wall)
	var run := WallRun.new()
	run.wall = wall
	run.corners = [Vector2i(ends[0]), Vector2i(ends[1])]
	run.start = ends[0] * cs
	run.along = (ends[1] - ends[0]).normalized()
	run.across = Vector2(-run.along.y, run.along.x)
	run.length = ends[0].distance_to(ends[1]) * cs
	run.def = map.wall_def(map.style_of(wall))
	run.kind = kind
	run.window = window
	run.base = base
	run.drop = drop
	run.low = walls_low or (cutaway and _cut_away(ends[0], ends[1]))
	run.full_height = run.def.height if run.def != null else wall_height
	run.height = minf(low_wall_height, run.full_height) if run.low else run.full_height
	run.half = (run.def.thickness if run.def != null else wall_thickness) * 0.5
	run.top_colour = run.def.top_colour if run.def != null else wall_top_colour
	run.own = _finish(run.def)
	for side in 2:
		run.finishes.append(_finish(map.wall_def(map.side_style(wall, side))))
	run.side_to = [run.length, run.length]
	return run


func _finish(def: WallDef) -> Finish:
	var finish := Finish.new()
	if def != null:
		finish.colour = def.colour
		finish.texture = def.texture
		finish.dado = def.dado_colour
		finish.dado_height = def.dado_height
	else:
		finish.colour = wall_colour
	return finish


## Works out where each solid wall's sides start and end, so walls meeting
## at a corner join at a mitre instead of overlapping (which flickers) or
## leaving gaps. Lone ends reach half a thickness past their corner.
## Returns the joins that need a post to fill the middle, such as
## T-junctions and crossings: [outline, the runs meeting there] for each.
func _join_walls(runs: Array[WallRun]) -> Array:
	var at := {} # Vector2i corner -> [[run, starts here], ...]
	for run in runs:
		if not run.solid():
			continue
		for i in 2:
			if not at.has(run.corners[i]):
				at[run.corners[i]] = []
			at[run.corners[i]].append([run, i == 0])
	var hubs := []
	for corner: Vector2i in at:
		var ends: Array = at[corner]
		if ends.size() == 1:
			var run: WallRun = ends[0][0]
			for side in 2:
				if ends[0][1]:
					run.side_from[side] = -run.half
				else:
					run.side_to[side] = run.length + run.half
			continue
		# Round the corner by the direction each wall leaves it.
		ends.sort_custom(func(p: Array, q: Array) -> bool:
			return (p[0] as WallRun).leaving(p[1]).angle() < (q[0] as WallRun).leaving(q[1]).angle())
		var needs_hub := ends.size() > 2
		for i in ends.size():
			var a: WallRun = ends[i][0]
			var b: WallRun = ends[(i + 1) % ends.size()][0]
			var da: Vector2 = a.leaving(ends[i][1])
			var db: Vector2 = b.leaving(ends[(i + 1) % ends.size()][1])
			var na := Vector2(-da.y, da.x)
			var nb := Vector2(-db.y, db.x)
			# Where a's left side meets b's right side, as distances along each.
			var offset := na * a.half + nb * b.half
			var turn := da.cross(db)
			var ta := 0.0
			var tb := 0.0
			if absf(turn) > 0.02:
				ta = (-offset).cross(db) / turn
				tb = offset.cross(da) / -turn
			var limit := 5.0 * maxf(a.half, b.half)
			if absf(ta) > limit or absf(tb) > limit:
				# Too sharp to mitre neatly: square ends, and a post between.
				ta = 0.0
				tb = 0.0
				needs_hub = true
			a.set_end(ends[i][1], true, ta)
			b.set_end(ends[(i + 1) % ends.size()][1], false, tb)
		if not needs_hub:
			continue
		var points := PackedVector2Array([Vector2(corner) * grid.cell_size])
		var meeting: Array[WallRun] = []
		for end: Array in ends:
			var run: WallRun = end[0]
			meeting.append(run)
			for side in 2:
				points.append(run.side_point(side, run.side_from[side] if end[1] else run.side_to[side]))
		var outline := Geometry2D.convex_hull(points)
		outline.remove_at(outline.size() - 1)
		if outline.size() >= 3:
			hubs.append([outline, meeting])
	return hubs


## The middle of a join: a post as tall as the tallest wall there.
func _add_hub(outline: PackedVector2Array, meeting: Array[WallRun]) -> void:
	var tallest := meeting[0]
	var bottom := INF
	for run in meeting:
		if run.base + run.height > tallest.base + tallest.height:
			tallest = run
		bottom = minf(bottom, run.base - run.drop)
	MeshShapes.add_prism(_surface(_surfaces, tallest.own.texture), outline, bottom,
			tallest.base + tallest.height, tallest.own.colour, tallest.top_colour)


## One stretch of wall between two corners, as a plain wall, door, window or
## fence.
func _add_wall_run(run: WallRun) -> void:
	var cs := grid.cell_size
	var from := 0.0
	var to := run.length
	var opening := run.kind == BuildingMap.Wall.DOOR or run.kind == BuildingMap.Wall.WINDOW
	if opening and run.length > cs + 0.01:
		# Doors and windows keep their size in long angled walls: plain wall
		# fills the rest either side.
		from = (run.length - cs) * 0.5
		to = from + cs
		_add_slab(run, 0.0, from, -run.drop, run.height)
		_add_slab(run, to, run.length, -run.drop, run.height)
	if run.kind == BuildingMap.Wall.DOOR:
		_add_door(run, from, to)
	elif run.kind == BuildingMap.Wall.WINDOW:
		_add_window(run, from, to)
	elif run.def != null and run.def.see_through and not run.low:
		_add_fence(run)
	else:
		_add_slab(run, 0.0, run.length, -run.drop, run.height)


## A block of wall from `from` to `to` metres along the run, `bottom` to
## `top` metres above its base. Without a colour, each side shows its
## finish (paint, texture and dado) and the ends and top the wall's own;
## with one, it is that colour all over. `width` is a share of the wall's
## thickness: full-width blocks at an end of the run follow its mitres.
func _add_slab(run: WallRun, from: float, to: float, bottom: float, top: float,
		colour := Color(0, 0, 0, 0), top_colour := Color(0, 0, 0, 0), width := 1.0,
		st: SurfaceTool = null) -> void:
	var corners: Array[Vector2] = [] # Side 0 from, side 0 to, side 1 to, side 1 from.
	for side: int in [0, 1]:
		# A mitre never reaches past the block's other end.
		var start := minf(run.side_from[side], to) if from <= 0.0 and width == 1.0 else from
		var end := maxf(run.side_to[side], from) if to >= run.length and width == 1.0 else to
		var a := run.side_point(side, start, width)
		var b := run.side_point(side, end, width)
		corners.append_array([a, b] if side == 0 else [b, a])
	var low_y := run.base + bottom
	var high_y := run.base + top
	var centre := Vector2.ZERO
	for p in corners:
		centre += p * 0.25
	var plain := colour.a > 0.0
	var own := _surface(_surfaces, run.own.texture) if st == null else st
	var cap: Array[Vector3] = []
	var floor_cap: Array[Vector3] = []
	for p in corners:
		cap.append(Vector3(p.x, high_y, p.y))
		floor_cap.append(Vector3(p.x, low_y, p.y))
	MeshShapes.add_polygon(own, cap, Vector3.UP, top_colour if top_colour.a > 0.0 else
			(colour if plain else run.top_colour))
	MeshShapes.add_polygon(own, floor_cap, Vector3.DOWN, colour if plain else run.own.colour)
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		# Faces 0 and 2 are the wall's sides; 1 and 3 its ends.
		var finish := run.own if i % 2 == 1 else run.finishes[0 if i == 0 else 1]
		var face_st := own if plain or st != null else _surface(_surfaces, finish.texture)
		var outward := (a + b) * 0.5 - centre
		_add_wall_face(face_st, a, b, low_y, high_y, Vector3(outward.x, 0.0, outward.y),
				colour if plain else finish.colour, null if plain else finish, run.base)


## One upright face of a wall block, with its finish's dado along the
## bottom when it has one.
func _add_wall_face(st: SurfaceTool, a: Vector2, b: Vector2, low_y: float, high_y: float,
		outward: Vector3, colour: Color, finish: Finish, base: float) -> void:
	if finish != null and finish.dado.a > 0.0:
		var line := base + finish.dado_height
		if high_y <= line:
			colour = finish.dado
		elif low_y < line:
			_add_wall_face(st, a, b, low_y, line, outward, finish.dado, null, base)
			low_y = line
	MeshShapes.add_quad(st, Vector3(a.x, high_y, a.y), Vector3(b.x, high_y, b.y),
			Vector3(b.x, low_y, b.y), Vector3(a.x, low_y, a.y), outward, colour)


func _add_door(run: WallRun, from: float, to: float) -> void:
	if run.low or run.full_height <= door_height:
		_add_slab(run, from, to, 0.0, minf(run.height, low_wall_height) * 0.5, door_colour)
		return
	_add_slab(run, from, to, door_height, run.full_height)
	var width := to - from
	var kind := map.door_kind_at(run.wall) if run.wall is Vector3i else &""
	var model: PackedScene = door_models.get(kind, door_model)
	if model == null:
		_add_slab(run, from + width * 0.1, to - width * 0.1, 0.0, door_height, door_colour,
				door_colour, 0.4)
		return
	# The model fills a one-metre doorway along its x, facing along z.
	var door := model.instantiate() as Node3D
	var middle := run.start + run.along * (from + to) * 0.5
	door.transform = Transform3D(Basis(Vector3(run.along.x, 0.0, run.along.y) * width, Vector3.UP,
			Vector3(run.across.x, 0.0, run.across.y)), Vector3(middle.x, run.base, middle.y))
	_doors.add_child(door)


## Wall below the sill and above the head, with glass or bars between.
## Cut-away walls show the window as a coloured top so it is still easy
## to spot.
func _add_window(run: WallRun, from: float, to: float) -> void:
	var accent := bars_colour if run.window == BuildingMap.WINDOW_BARS else glass_colour
	accent.a = 1.0
	if run.low or run.full_height <= window_head:
		_add_slab(run, from, to, -run.drop, run.height, Color(0, 0, 0, 0), accent)
		return
	_add_slab(run, from, to, -run.drop, window_sill)
	_add_slab(run, from, to, window_head, run.full_height)
	# Narrow pillars at each end make a frame and keep corners solid.
	_add_slab(run, from, from + 0.15, window_sill, window_head)
	_add_slab(run, to - 0.15, to, window_sill, window_head)
	var length := to - from
	if run.window == BuildingMap.WINDOW_BARS:
		var count := maxi(roundi(6 * length), 2)
		for i in count:
			var middle := from + length * (0.5 + ((float(i) + 0.5) / count - 0.5) * 0.8)
			_add_slab(run, middle - 0.025, middle + 0.025, window_sill, window_head, bars_colour,
					bars_colour, 0.025 / run.half)
	elif run.window == BuildingMap.WINDOW_GLASS:
		_add_slab(run, from + 0.15, to - 0.15, window_sill, window_head, glass_colour, glass_colour,
				0.25, _glass)
		_has_glass = true


static func _make_glass_material() -> StandardMaterial3D:
	var material := MeshShapes.vertex_colour_material()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Posts at each end and two rails between them. Fences meeting at a corner
## share its post.
func _add_fence(run: WallRun) -> void:
	for i in 2:
		if _posts.has(run.corners[i]):
			continue
		_posts[run.corners[i]] = true
		var at := run.length * i
		_add_slab(run, at - 0.06, at + 0.06, -run.drop, run.height, Color(0, 0, 0, 0),
				Color(0, 0, 0, 0), 0.06 / run.half)
	for rail_y in [run.height * 0.45, run.height * 0.85]:
		_add_slab(run, 0.0, run.length, rail_y - 0.05, rail_y + 0.05, Color(0, 0, 0, 0),
				Color(0, 0, 0, 0), 0.6)


func _build_objects() -> void:
	for child in _objects.get_children():
		child.queue_free()
	var cs := grid.cell_size
	for flight: Staircase in map.stairs.values():
		_add_stairs(flight)
	var stepped := map.door_steps()
	for edge: Vector3i in stepped:
		_add_door_steps(edge, stepped[edge])
	for placed: BuildingMap.PlacedObject in map.objects.values():
		var centre := placed.centre * cs
		var ground := map.floor_height(Vector2i(placed.centre.floor()))
		var surface: BuildingMap.PlacedObject = map.objects.get(placed.on)
		if surface != null:
			ground = map.floor_height(Vector2i(surface.centre.floor())) + surface.def.height
		var scene := placed.def.model_for(placed.look)
		if scene != null:
			var model := scene.instantiate() as Node3D
			model.position = Vector3(centre.x, ground + 0.03, centre.y)
			model.rotation.y = -placed.angle
			_objects.add_child(model)
			_add_dressing(placed, ground + 0.03)
			continue
		# Shrink a touch so neighbours and walls do not look fused together.
		var size := placed.def.size
		var margin := minf(0.1, minf(size.x, size.y) * 0.1)
		var box := BoxMesh.new()
		box.size = Vector3((size.x - margin * 2.0) * cs, placed.def.height, (size.y - margin * 2.0) * cs)
		var instance := MeshInstance3D.new()
		instance.mesh = box
		instance.material_override = _object_material(placed.def.colour)
		instance.position = Vector3(centre.x, ground + 0.03 + placed.def.height * 0.5, centre.y)
		# Turning about Y goes the other way to turning a Vector2 on the ground.
		instance.rotation.y = -placed.angle
		_objects.add_child(instance)
		_add_dressing(placed, ground + 0.03)


## Things set out on a surface's free spots for whoever has claimed it
## (see BuildingMap.dressing). Only for show.
func _add_dressing(placed: BuildingMap.PlacedObject, ground: float) -> void:
	var dressing: Array = map.dressing.get(placed.id, [])
	if dressing.is_empty():
		return
	var cs := grid.cell_size
	var free: Array[int] = []
	for i in placed.def.spots.size():
		if not map.spot_taken(placed.id, i):
			free.append(i)
	for i in mini(free.size(), dressing.size()):
		var entry: Array = dressing[i]
		var def: ObjectDef = entry[0]
		var at := map.spot_point(placed, free[i]) * cs
		var node: Node3D
		if def.model != null:
			node = def.model.instantiate() as Node3D
		else:
			var box := BoxMesh.new()
			box.size = Vector3(def.size.x * cs, def.height, def.size.y * cs)
			var instance := MeshInstance3D.new()
			instance.mesh = box
			instance.material_override = _object_material(def.colour)
			instance.position.y = def.height * 0.5
			node = Node3D.new()
			node.add_child(instance)
		node.position = Vector3(at.x, ground + placed.def.height, at.y)
		node.rotation.y = -(placed.angle + float(entry[1]))
		_objects.add_child(node)


## A staircase as a stepped solid: each tread and landing stands on the
## floor at the foot.
func _add_stairs(flight: Staircase) -> void:
	var cs := grid.cell_size
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := map.floor_height(flight.cells[0])
	var def := map.floor_def(flight.style)
	var colour := def.colour if def != null else stairs_colour
	var treads := flight.treads()
	for i in treads.size():
		var outline: PackedVector2Array = treads[i][0]
		var scaled := PackedVector2Array()
		for p in outline:
			scaled.append(p * cs)
		var top: float = base + 0.03 + treads[i][1]
		MeshShapes.add_prism(st, scaled, base, top, colour.darkened(0.25),
				colour.lightened(0.06 * (i % 2)))
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = _stairs_material
	_objects.add_child(instance)


## A few steps on the low side of a door, climbing to the floor beyond it.
## Each riser is at most a quarter of a metre; the treads share the tile.
func _add_door_steps(edge: Vector3i, low: Vector2i) -> void:
	var cs := grid.cell_size
	var sides := BuildingMap.edge_cells(edge)
	var high := sides[0] if sides[1] == low else sides[1]
	var d := Vector2(high - low)
	var across := Vector2(-d.y, d.x)
	var base := map.floor_height(low)
	var rise := map.door_rise(edge)
	var count := ceili(rise / BuildingMap.MAX_STEP - BuildingMap.EPSILON)
	var def := map.floor_def(map.floors[low])
	var colour := def.colour if def != null else stairs_colour
	var centre := Vector2(low) + Vector2(0.5, 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tread k of count - 1, highest against the door.
	for k in range(1, count):
		var near := float(count - 1 - k) / count
		var far := float(count - k) / count
		var outline := PackedVector2Array()
		for corner: Vector2 in [Vector2(near, 0.1), Vector2(far, 0.1), Vector2(far, 0.9), Vector2(near, 0.9)]:
			outline.append((centre + d * (0.5 - corner.x) + across * (corner.y - 0.5)) * cs)
		MeshShapes.add_prism(st, outline, base, base + 0.03 + rise * k / count,
				colour.darkened(0.25), colour.lightened(0.06 * (k % 2)))
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = _stairs_material
	_objects.add_child(instance)


func _build_labels() -> void:
	_declutter_key.clear()
	_ranked.clear()
	for child in _labels.get_children():
		child.queue_free()
	if not show_labels:
		return
	var cs := grid.cell_size
	for room in map.rooms():
		var def := room_type(room.type)
		if def == null:
			continue
		var problems := def.problems(room, map)
		var label := _label(def.display_name)
		if not problems.is_empty():
			label.text += "\n" + "\n".join(problems)
			label.modulate = problem_colour
		var centre := room.centre() * cs
		var lift := low_wall_height + 0.6 if walls_low else wall_height + 0.6
		lift += map.floor_height(room.cells[0])
		label.position = Vector3(centre.x, lift, centre.y)
		# Rooms with problems win when labels crowd, then bigger rooms.
		label.set_meta(&"priority", (1000 if not problems.is_empty() else 0) + room.cells.size())
		_labels.add_child(label)
	# Doors whose floors no longer line up say so, above the doorway.
	for edge in map.unusable_doors():
		var label := _label("Can't use this door:\nfloors %s m apart" % String.num(map.door_rise(edge), 2))
		label.modulate = problem_colour
		var ends := BuildingMap.edge_ends(edge)
		var middle := (ends[0] + ends[1]) * 0.5
		label.position = Vector3(middle.x * cs, _wall_base(edge) + door_height + 0.3, middle.y * cs)
		label.set_meta(&"priority", 2000)
		_labels.add_child(label)
	_rank_labels()


## Sorts the labels for decluttering, most important first, and estimates
## each one's size on screen from its longest line and number of lines.
func _rank_labels() -> void:
	for child in _labels.get_children():
		if child is Label3D and not child.is_queued_for_deletion():
			var lines: PackedStringArray = child.text.split("\n")
			var widest := 0
			for line in lines:
				widest = maxi(widest, line.length())
			_ranked.append([child, Vector2(widest * 19.0, lines.size() * 40.0)])
	_ranked.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0].get_meta(&"priority", 0)) > int(b[0].get_meta(&"priority", 0)))


func _label(text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 22
	label.outline_size = 10
	label.font = _label_font
	label.outline_modulate = CosyTheme.WORLD_OUTLINE
	return label


func _process(_delta: float) -> void:
	if show_labels and _ranked.size() > 1:
		_declutter_labels()


## Hides labels that would overlap one already shown, most important first,
## so crowded rooms show one clear label each; zoom in and the rest return.
func _declutter_labels() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var key := [camera.global_transform, camera.fov, camera.size, get_viewport().get_visible_rect().size,
			global_transform]
	if key == _declutter_key:
		return
	_declutter_key = key
	var scale := get_viewport().get_visible_rect().size.y / 900.0
	var taken: Array[Rect2] = []
	for entry in _ranked:
		var label: Label3D = entry[0]
		var at := label.global_position
		label.visible = false
		if camera.is_position_behind(at):
			continue
		var size: Vector2 = entry[1] * scale
		var rect := Rect2(camera.unproject_position(at) - size * 0.5, size)
		var free := true
		for other in taken:
			if other.intersects(rect):
				free = false
				break
		if free:
			label.visible = true
			taken.append(rect)


## How many labels are shown right now, for tests.
func visible_labels() -> int:
	var count := 0
	for child in _labels.get_children():
		if child is Label3D and child.visible and not child.is_queued_for_deletion():
			count += 1
	return count


## Ground height at a point in tile units.
func _height_at(point: Vector2) -> float:
	return terrain.height_at(point) if terrain != null else 0.0


func _lowest_floor_beside(edge: Vector3i) -> float:
	var lowest := INF
	for cell in BuildingMap.edge_cells(edge):
		if map.has_floor(cell):
			lowest = minf(lowest, map.floor_height(cell))
	return lowest if lowest < INF else _wall_base(edge)


func _lowest_ground(cell: Vector2i) -> float:
	var lowest := INF
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i.ONE]:
		lowest = minf(lowest, _height_at(Vector2(cell + offset)))
	return lowest


## Walls stand on the higher floor beside them, or on the lower end of the ground.
func _wall_base(edge: Vector3i) -> float:
	var best := -INF
	for cell in BuildingMap.edge_cells(edge):
		if map.has_floor(cell):
			best = maxf(best, map.floor_height(cell))
	if best > -INF:
		return best
	var start := Vector2(edge.x, edge.y)
	var end := start + (Vector2.RIGHT if edge.z == BuildingMap.EDGE_X else Vector2.DOWN)
	return minf(_height_at(start), _height_at(end))


func _object_material(colour: Color) -> StandardMaterial3D:
	if not _object_materials.has(colour):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.8
		_object_materials[colour] = material
	return _object_materials[colour]
