class_name BuildController
extends Node3D
## The build tools: turns mouse input into changes to a BuildingMap, and
## shows a see-through preview of what will happen before you commit.
##
## Drag tools (room, floor, wall, demolish) act when you let go of the left
## mouse button. Click tools (openings, object, room type) act on click. Brush
## tools (terrain, plants) act for as long as the button is held.

signal tool_changed(tool: Tool)

enum Tool { NONE, ROOM, FLOOR, WALL, OPENING, OBJECT, ROOM_TYPE, DEMOLISH, TERRAIN, PLANTS, PATH }
enum WaterMode { NONE, ADD, REMOVE }
## What the floor tool does: lay floor, or nudge existing floor up or down.
enum FloorMode { LAY, RAISE, LOWER }

## How far one floor nudge moves, in metres.
const NUDGE_STEP := 0.25
## How far floors may be nudged from their storey's height, below and above.
const NUDGE_DOWN := 0.5
const NUDGE_UP := 1.5

const HINTS := {
	Tool.NONE: "",
	Tool.ROOM: "Drag to build a walled room.",
	Tool.FLOOR: "Drag to lay or restyle floor. Hold Ctrl to remove floor.",
	Tool.WALL: "Drag between corners to build or restyle walls. Hold Ctrl to remove them.",
	Tool.OPENING: "Click a wall to put in a door or window. Click it again to fill it in.",
	Tool.OBJECT: "Click to place. R rotates. Hold Alt to place freely.",
	Tool.ROOM_TYPE: "Click a room to mark it.",
	Tool.DEMOLISH: "Click an object or wall to remove it, or drag to clear an area.",
	Tool.TERRAIN: "Hold the mouse to shape your land. [ and ] change the brush size.",
	Tool.PLANTS: "Hold the mouse to plant. Hold Ctrl to clear plants. [ and ] change the brush size.",
	Tool.PATH: "",
}

const PATH_HINTS := {
	PathTool.Mode.STRAIGHT: "Click to start a path and click again to end it. Esc stops. Ctrl-click removes a path.",
	PathTool.Mode.CURVED: "Click the start, then a bend point, then the end. Esc stops. Ctrl-click removes a path.",
	PathTool.Mode.FREEHAND: "Drag to draw a path; it is smoothed when you let go. Ctrl-click removes a path.",
}

const FLOOR_HINTS := {
	FloorMode.RAISE: "Drag over floor to raise it a step, for split levels.",
	FloorMode.LOWER: "Drag over floor to lower it a step, for split levels.",
}

const WATER_HINTS := {
	WaterMode.ADD: "Click a hollow to fill it with water. Digging deeper or cutting the rim moves the water.",
	WaterMode.REMOVE: "Click a pond or lake to drain it.",
}

@export var grid: BuildGrid
@export var camera_rig: CameraRig
@export var view: BuildingView
## Optional: the ground to sculpt and build on.
@export var terrain: Terrain
## Optional: the plants to paint and clear.
@export var foliage: FoliageLayer
## Optional: ponds and lakes for the terrain tool's water modes.
@export var water: WaterLayer
## Optional: draws paths, for the path tool.
@export var path_view: PathView

@export_group("Brushes")
## Metres per second at the middle of the brush when raising or lowering.
@export var sculpt_speed := 1.5
## How quickly flatten and smooth pull the ground into shape.
@export var blend_speed := 4.0
@export var min_brush_radius := 1.0
@export var max_brush_radius := 12.0

@export_group("Preview colours")
@export var ok_colour := Color(0.45, 0.95, 0.55, 0.45)
@export var bad_colour := Color(1.0, 0.4, 0.4, 0.45)
@export var demolish_colour := Color(1.0, 0.3, 0.25, 0.4)
@export var preview_wall_height := 1.0

## The level being built on. Follows `building` when that is set.
var map: BuildingMap:
	set(value):
		map = value
		if building == null:
			path_tool.map = value
## All the storeys. Optional: without it, the controller works on `map` alone.
var building: Building:
	set(value):
		building = value
		map = building.current()
		path_tool.map = building.ground()
		building.active_changed.connect(func(_level: int) -> void:
			_dragging = false
			_brushing = false
			path_tool.cancel()
			map = building.current())
## The paths the path tool edits. Set together with `map`.
var paths: PathNetwork:
	set(value):
		paths = value
		path_tool.network = value
## The path tool's own state: its mode, style and the path being drawn.
var path_tool := PathTool.new()
var tool := Tool.NONE:
	set(value):
		tool = value
		_dragging = false
		path_tool.cancel()
		tool_changed.emit(tool)
var object_def: ObjectDef
## Styles used by the room, floor and wall tools.
var floor_style: StringName = BuildingMap.DEFAULT_FLOOR
var wall_style: StringName = BuildingMap.DEFAULT_WALL
var object_rotation := 0
## The room type the room type tool applies. Null clears a room's type.
var room_type: RoomTypeDef
## What the opening tool puts in: Wall.DOOR or Wall.WINDOW, and which kind
## of window.
var opening := BuildingMap.Wall.DOOR
var window_kind := BuildingMap.WINDOW_GLASS
var terrain_brush := Terrain.Brush.RAISE
## When not NONE, the terrain tool adds or removes water instead of sculpting.
var water_mode := WaterMode.NONE
var floor_mode := FloorMode.LAY
var plant_def: FoliageDef
## Brush radius in tiles, for the terrain and plant tools.
var brush_radius := 3.0

## Makes the floor and wall tools remove instead of build, as if Ctrl were
## held. Mainly for tests.
var force_erase := false

var _dragging := false
var _drag_start_cell := Vector2i.ZERO
var _drag_start_corner := Vector2i.ZERO
var _hover_point := Vector2.ZERO ## Mouse position on the ground, in cell units.
var _has_hover := false
var _preview_mesh := ImmediateMesh.new()
var _preview_material := MeshShapes.vertex_colour_material(true)
var _preview_boxes: Array[Array] = [] ## [centre, half extents, colour] per box.
var _path_preview := MeshInstance3D.new()
var _brushing := false
var _flatten_target := 0.0
var _plant_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _basin: WaterLayer.Body
var _basin_cell := Vector2i(-1, -1)
var _basin_dirty := true


func _ready() -> void:
	path_tool.view = path_view
	path_tool.terrain = terrain
	path_tool.foliage = foliage
	_path_preview.material_override = _preview_material
	_path_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_path_preview)
	for source: Node in [terrain, water]:
		if source != null:
			source.changed.connect(func() -> void: _basin_dirty = true)
	var preview := MeshInstance3D.new()
	preview.mesh = _preview_mesh
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)


func _process(delta: float) -> void:
	_update_hover()
	if _brushing and _has_hover:
		_apply_brush(delta)
	if tool == Tool.PATH and _has_hover:
		path_tool.extend_trail(_hover_point)
	_draw_preview()


func _input(event: InputEvent) -> void:
	# Finish a drag even if the button is let go over the toolbar.
	if event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_brushing = false
		if _dragging:
			_on_release()
		if tool == Tool.PATH and path_tool.mode == PathTool.Mode.FREEHAND and _has_hover:
			path_tool.end_trail(_hover_point)


func _unhandled_input(event: InputEvent) -> void:
	if map == null:
		return
	if event.is_action_pressed("build_cancel"):
		if _dragging:
			_dragging = false
		elif tool == Tool.PATH and path_tool.cancel():
			pass
		else:
			tool = Tool.NONE
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_rotate") and tool == Tool.OBJECT:
		object_rotation = (object_rotation + 1) % 4
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_brush_smaller") and _uses_brush():
		brush_radius = maxf(brush_radius - 1.0, min_brush_radius)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_brush_bigger") and _uses_brush():
		brush_radius = minf(brush_radius + 1.0, max_brush_radius)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_toggle_walls"):
		view.walls_low = not view.walls_low
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and tool != Tool.NONE and _has_hover:
			_on_press()
			get_viewport().set_input_as_handled()


func _on_press() -> void:
	if _ground_only(tool) and _level() != 0:
		return
	match tool:
		Tool.ROOM, Tool.FLOOR, Tool.DEMOLISH:
			_dragging = true
			_drag_start_cell = _hover_cell()
		Tool.WALL:
			_dragging = true
			_drag_start_corner = _hover_corner()
		Tool.OPENING:
			var edge := _hover_edge()
			if _has_chosen_opening(edge):
				map.set_opening(edge, BuildingMap.Wall.WALL)
			else:
				map.set_opening(edge, opening, window_kind)
		Tool.OBJECT:
			if object_def != null:
				map.place_object(object_def, _object_position(), object_rotation)
		Tool.ROOM_TYPE:
			var room := map.room_at(_hover_cell())
			if room != null:
				map.set_room_type(room, room_type.id if room_type != null else &"")
		Tool.PATH:
			if paths == null:
				return
			if path_tool.mode == PathTool.Mode.FREEHAND and not _erasing():
				path_tool.begin_trail(_hover_point)
			else:
				path_tool.press(_hover_point, _erasing())
		Tool.TERRAIN when water_mode != WaterMode.NONE:
			if water != null and water_mode == WaterMode.ADD:
				water.fill_at(_hover_cell())
			elif water != null:
				water.remove_at(_hover_cell())
		Tool.TERRAIN, Tool.PLANTS:
			_brushing = true
			_flatten_target = terrain.height_at(_hover_point) if terrain != null else 0.0
			_plant_cooldown = 0.0


func _on_release() -> void:
	if not _dragging:
		return
	var rect := _drag_rect()
	_dragging = false
	var erase := _erasing()
	match tool:
		Tool.ROOM:
			var height := build_height(rect)
			if can_build_floor(rect):
				map.build_room(rect, floor_style, wall_style, height)
				settle_ground(rect)
		Tool.FLOOR when floor_mode != FloorMode.LAY:
			nudge_floors(rect, NUDGE_STEP if floor_mode == FloorMode.RAISE else -NUDGE_STEP)
		Tool.FLOOR:
			if erase:
				map.clear_floor(rect)
			elif can_build_floor(rect):
				map.fill_floor(rect, floor_style, build_height(rect))
				settle_ground(rect)
		Tool.WALL:
			var edges := BuildingMap.edges_on_line(_drag_start_corner, _wall_end_corner())
			if erase:
				map.remove_walls(edges)
			else:
				map.build_walls(edges, wall_style)
		Tool.DEMOLISH:
			if rect.size != Vector2i.ONE:
				map.demolish(rect)
				return
			# A click takes the most specific thing under the mouse.
			var placed := map.object_at(_hover_point)
			var edge := _hover_edge()
			if placed != null:
				map.remove_object(placed.id)
			elif map.wall_at(edge) != BuildingMap.Wall.NONE and _edge_distance() < 0.25:
				map.remove_walls([edge])
			else:
				map.demolish(rect)


#region Ground and brushes

## What the current tool does, for the toolbar.
func hint() -> String:
	if tool == Tool.FLOOR and floor_mode != FloorMode.LAY:
		return FLOOR_HINTS[floor_mode]
	if _ground_only(tool) and _level() != 0:
		return "This tool works on the ground floor. Page Down to go back to it."
	if tool == Tool.TERRAIN and water_mode != WaterMode.NONE:
		return WATER_HINTS[water_mode]
	if tool == Tool.PATH:
		return PATH_HINTS[path_tool.mode]
	return HINTS[tool]


## Fits the ground to the floor just laid in a rectangle, and clears plants.
## Each corner under a floor drops to the lowest floor touching it, so the
## ground never pokes through a floor; higher floors stand on foundations.
func settle_ground(rect: Rect2i) -> void:
	if _level() != 0:
		return
	if foliage != null:
		foliage.remove_in_rect(Rect2(rect))
	if paths != null:
		paths.remove_in_rect(Rect2(rect))
	if terrain == null:
		return
	var heights := {}
	for cell in BuildingMap.cells_in(rect):
		if not map.has_floor(cell):
			continue
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i.ONE]:
			var corner := cell + offset
			if heights.has(corner):
				continue
			var lowest := INF
			for touch: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
				if map.has_floor(corner + touch):
					lowest = minf(lowest, map.floor_height(corner + touch))
			heights[corner] = lowest
	terrain.set_corners(heights)


## The height new floor over this rectangle would go in at: the same as
## any floor already in or beside it, so rooms line up, or else the ground
## where the drag started.
func build_height(rect: Rect2i) -> float:
	var near := map.floor_height_near(rect)
	if not is_nan(near):
		return near
	var start := _drag_start_cell if rect.has_point(_drag_start_cell) else rect.position
	var ground := snappedf(terrain.cell_height(start), 0.25) if terrain != null else 0.0
	if _level() != 0:
		return building.storey_height(_level(), start, ground)
	return ground


## Moves the floor in a rectangle up or down, for split levels. Upstairs
## and in basements floors stay near their storey's height; on the ground
## they stay out of the water, and the ground is refitted underneath.
## Returns how many tiles moved.
func nudge_floors(rect: Rect2i, amount: float) -> int:
	var heights := {}
	for cell in BuildingMap.cells_in(rect):
		if not map.has_floor(cell):
			continue
		var height := map.floor_height(cell) + amount
		var ground := terrain.cell_height(cell) if terrain != null else 0.0
		if _level() != 0:
			var base := building.storey_height(_level(), cell, ground)
			height = clampf(height, base - NUDGE_DOWN, base + NUDGE_UP)
		elif terrain != null and terrain.water_surface(Vector2(cell) + Vector2(0.5, 0.5)) > height:
			continue
		heights[cell] = height
	var count := map.set_floor_heights(heights)
	if count > 0:
		settle_ground(rect)
	return count


## Whether floor can go over a rectangle: out of the water on the ground,
## and over floor on the level below when upstairs.
func can_build_floor(rect: Rect2i) -> bool:
	if not _is_dry(rect):
		return false
	if building != null and _level() > 0:
		for cell in BuildingMap.cells_in(rect):
			if map.owns(cell) and not building.is_supported(_level(), cell):
				return false
	return true


## The level being built on: 0 without a building.
func _level() -> int:
	return building.active if building != null else 0


## Tools that only make sense on the ground level.
func _ground_only(t: Tool) -> bool:
	return t == Tool.TERRAIN or t == Tool.PLANTS or t == Tool.PATH


## Does this edge already have the opening the tool would put in?
func _has_chosen_opening(edge: Vector3i) -> bool:
	if map.wall_at(edge) != opening:
		return false
	return opening != BuildingMap.Wall.WINDOW or map.window_kind(edge) == window_kind


func _uses_brush() -> bool:
	return tool == Tool.TERRAIN or tool == Tool.PLANTS


func _apply_brush(delta: float) -> void:
	if _level() != 0:
		return
	match tool:
		Tool.TERRAIN:
			if terrain == null:
				return
			var strength := sculpt_speed * delta
			if terrain_brush == Terrain.Brush.FLATTEN or terrain_brush == Terrain.Brush.SMOOTH:
				strength = clampf(blend_speed * delta, 0.0, 1.0)
			terrain.sculpt(terrain_brush, _hover_point, brush_radius, strength, _flatten_target,
					can_sculpt)
		Tool.PLANTS:
			if foliage == null:
				return
			if _erasing():
				foliage.remove_in_circle(_hover_point, brush_radius)
				return
			_plant_cooldown -= delta
			if plant_def == null or _plant_cooldown > 0.0:
				return
			_plant_cooldown = 0.08
			foliage.paint(plant_def, _hover_point, brush_radius, 3, _rng, can_grow)


## Sculpting stays on your own land: every tile touching the corner must be owned.
func can_sculpt(corner: Vector2i) -> bool:
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		if not map.owns(corner + offset):
			return false
	return true


## Plants grow on your own land, off floors and out of the water.
func can_grow(position: Vector2) -> bool:
	var cell := Vector2i(position.floor())
	if not map.owns(cell) or map.has_floor(cell):
		return false
	return terrain == null or not terrain.is_underwater(position)

#endregion

#region Picking

func _update_hover() -> void:
	var hit: Variant = camera_rig.ground_point_at(get_viewport().get_mouse_position())
	_has_hover = hit != null
	if _has_hover:
		var local := grid.to_local(hit) / grid.cell_size
		_hover_point = Vector2(local.x, local.z)


func _hover_cell() -> Vector2i:
	return Vector2i(_hover_point.floor())


func _hover_corner() -> Vector2i:
	var bounds := map.land_bounds()
	return Vector2i(_hover_point.round()).clamp(bounds.position, bounds.end)


func _erasing() -> bool:
	return Input.is_action_pressed("build_erase") or force_erase


## How far the mouse is from the nearest edge, in tiles.
func _edge_distance() -> float:
	var f := _hover_point - _hover_point.floor()
	return minf(minf(f.x, 1.0 - f.x), minf(f.y, 1.0 - f.y))


## The wall edge nearest the mouse.
func _hover_edge() -> Vector3i:
	var cell := _hover_cell()
	var f := _hover_point - Vector2(cell)
	var nearest := minf(minf(f.x, 1.0 - f.x), minf(f.y, 1.0 - f.y))
	if nearest == f.x:
		return Vector3i(cell.x, cell.y, BuildingMap.EDGE_Z)
	if nearest == 1.0 - f.x:
		return Vector3i(cell.x + 1, cell.y, BuildingMap.EDGE_Z)
	if nearest == f.y:
		return Vector3i(cell.x, cell.y, BuildingMap.EDGE_X)
	return Vector3i(cell.x, cell.y + 1, BuildingMap.EDGE_X)


func _drag_rect() -> Rect2i:
	var bounds := map.land_bounds()
	var end := _hover_cell().clamp(bounds.position, bounds.end - Vector2i.ONE)
	var start := _drag_start_cell if _dragging else end
	return BuildingMap.rect_between(start, end)


## Where the object being placed would go, centred on the mouse.
func _object_position() -> Vector2:
	var snap := object_def.snap
	if Input.is_action_pressed("build_free_place"):
		snap = ObjectDef.Snap.FREE
	return BuildingMap.snapped_position(object_def, _hover_point, object_rotation, snap)


## Walls go in straight lines, so snap to whichever axis the drag follows most.
func _wall_end_corner() -> Vector2i:
	var corner := _hover_corner()
	var delta := corner - _drag_start_corner
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(corner.x, _drag_start_corner.y)
	return Vector2i(_drag_start_corner.x, corner.y)

#endregion

#region Preview

func _draw_preview() -> void:
	_preview_mesh.clear_surfaces()
	_preview_boxes.clear()
	_draw_path_preview()
	if map == null or tool == Tool.NONE or not _has_hover:
		return
	if _ground_only(tool) and _level() != 0:
		return
	match tool:
		Tool.ROOM:
			var rect := _drag_rect()
			var dry := can_build_floor(rect)
			_preview_cells(BuildingMap.cells_in(rect), ok_colour if dry else bad_colour,
					_preview_height(rect))
			for edge in BuildingMap.rect_perimeter(rect):
				_preview_edge(edge, ok_colour if dry and map.can_build_wall(edge) else bad_colour,
						_preview_height(rect))
		Tool.FLOOR when floor_mode != FloorMode.LAY:
			var cells: Array[Vector2i] = []
			for cell in BuildingMap.cells_in(_drag_rect()):
				if map.has_floor(cell):
					cells.append(cell)
			_preview_cells(cells, ok_colour)
		Tool.FLOOR:
			var rect := _drag_rect()
			if _erasing():
				_preview_cells(BuildingMap.cells_in(rect), demolish_colour)
			else:
				_preview_cells(BuildingMap.cells_in(rect),
						ok_colour if can_build_floor(rect) else bad_colour, _preview_height(rect))
		Tool.TERRAIN when water_mode != WaterMode.NONE:
			_preview_water()
		Tool.TERRAIN, Tool.PLANTS:
			var colour := demolish_colour if tool == Tool.PLANTS and _erasing() else ok_colour
			_preview_ring(_hover_point, brush_radius, colour)
		Tool.DEMOLISH:
			var placed := map.object_at(_hover_point)
			if _dragging:
				_preview_cells(BuildingMap.cells_in(_drag_rect()), demolish_colour)
			elif placed != null:
				_preview_rect(placed.rect, demolish_colour, placed.def.height + 0.05)
			elif map.wall_at(_hover_edge()) != BuildingMap.Wall.NONE and _edge_distance() < 0.25:
				_preview_edge(_hover_edge(), demolish_colour)
			else:
				_preview_cells(BuildingMap.cells_in(_drag_rect()), demolish_colour)
		Tool.WALL:
			if _dragging:
				for edge in BuildingMap.edges_on_line(_drag_start_corner, _wall_end_corner()):
					if _erasing():
						_preview_edge(edge, demolish_colour)
					else:
						_preview_edge(edge, ok_colour if map.can_build_wall(edge) else bad_colour)
			else:
				_preview_corner(_hover_corner(), ok_colour)
		Tool.OPENING:
			var edge := _hover_edge()
			var ok := map.wall_at(edge) != BuildingMap.Wall.NONE
			if opening == BuildingMap.Wall.WINDOW and map.is_outdoor_wall(edge):
				ok = false
			_preview_edge(edge, ok_colour if ok else bad_colour)
		Tool.OBJECT:
			if object_def != null:
				var position := _object_position()
				var ok := map.can_place(object_def, position, object_rotation)
				_preview_rect(BuildingMap.object_rect(object_def, position, object_rotation),
						ok_colour if ok else bad_colour, object_def.height)
		Tool.ROOM_TYPE:
			var room := map.room_at(_hover_cell())
			if room != null:
				var colour := room_type.colour if room_type != null else Color.WHITE
				colour.a = 0.45
				_preview_cells(room.cells, colour)
	if _preview_boxes.is_empty():
		return
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _preview_material)
	for box in _preview_boxes:
		MeshShapes.add_box_immediate(_preview_mesh, box[0], box[1], box[2])
	_preview_mesh.surface_end()


## Would a new building here stay out of the water?
func _is_dry(rect: Rect2i) -> bool:
	if terrain == null or _level() != 0:
		return true
	var height := build_height(rect)
	for cell in BuildingMap.cells_in(rect):
		if terrain.water_surface(Vector2(cell) + Vector2(0.5, 0.5)) > height:
			return false
	return true


## Shows the water a click would add (or a red tile if there is no hollow),
## or the body a click would drain.
func _preview_water() -> void:
	if water == null:
		return
	var cell := _hover_cell()
	var existing := water.body_at(cell)
	if water_mode == WaterMode.REMOVE:
		if existing != null:
			_preview_cells(existing.cells.keys(), demolish_colour, existing.level)
		else:
			_preview_cells([cell], bad_colour)
		return
	if existing != null:
		_preview_cells([cell], bad_colour, existing.level)
		return
	# Working a basin out can take a while on open ground, so only redo it
	# when the tile under the mouse or the ground changes.
	if cell != _basin_cell or _basin_dirty:
		_basin_cell = cell
		_basin_dirty = false
		_basin = water.find_basin(cell)
	if _basin != null:
		_preview_cells(_basin.cells.keys(), ok_colour, _basin.level)
	else:
		_preview_cells([cell], bad_colour)


func _preview_height(rect: Rect2i) -> float:
	return build_height(rect)


## The floor height where there is floor, otherwise the ground (or, off
## the ground level, where a new floor would go).
func _ground_at(point: Vector2) -> float:
	var cell := Vector2i(point.floor())
	if map.has_floor(cell):
		return map.floor_height(cell)
	var ground := terrain.height_at(point) if terrain != null else 0.0
	if _level() != 0:
		return building.storey_height(_level(), cell, ground)
	return ground


func _draw_path_preview() -> void:
	_path_preview.mesh = null
	if tool == Tool.PATH and _has_hover and paths != null and path_view != null and map != null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		path_tool.preview(st, _hover_point, ok_colour, bad_colour)
		_path_preview.mesh = st.commit()


## Tile highlights. `base` sets one height for them all; by default each
## follows the ground.
func _preview_cells(cells: Array[Vector2i], colour: Color, base := NAN, height := 0.06) -> void:
	var cs := grid.cell_size
	for cell in cells:
		var ground := base if not is_nan(base) else _ground_at(Vector2(cell) + Vector2(0.5, 0.5))
		var centre := Vector3(cell.x + 0.5, ground, cell.y + 0.5) * Vector3(cs, 1.0, cs)
		_preview_boxes.append([centre + Vector3.UP * height * 0.5,
				Vector3(cs * 0.48, height * 0.5, cs * 0.48), colour])


## A ring of small markers on the ground showing a brush's reach.
func _preview_ring(centre: Vector2, radius: float, colour: Color) -> void:
	var cs := grid.cell_size
	var count := maxi(16, ceili(radius * 10.0))
	for i in count:
		var point := centre + Vector2.from_angle(TAU * i / count) * radius
		_preview_boxes.append([Vector3(point.x * cs, _ground_at(point) + 0.05, point.y * cs),
				Vector3(0.07, 0.05, 0.07), colour])


func _preview_rect(rect: Rect2, colour: Color, height: float) -> void:
	var cs := grid.cell_size
	var centre := rect.get_center() * cs
	var ground := _ground_at(rect.get_center())
	_preview_boxes.append([Vector3(centre.x, ground + height * 0.5, centre.y),
			Vector3(rect.size.x * cs * 0.5, height * 0.5, rect.size.y * cs * 0.5), colour])


## A wall preview. `base` sets the height it stands at; by default it
## stands on the floor or ground beside it. Kept below full wall height so
## a big drag does not hide what is behind it.
func _preview_edge(edge: Vector3i, colour: Color, base := NAN) -> void:
	if not map.edge_in_bounds(edge):
		return
	var cs := grid.cell_size
	var along := Vector3.RIGHT if edge.z == BuildingMap.EDGE_X else Vector3.BACK
	var across := Vector3.BACK if edge.z == BuildingMap.EDGE_X else Vector3.RIGHT
	var height := view.low_wall_height if view.walls_low else preview_wall_height
	var middle := Vector2(edge.x, edge.y) + Vector2(along.x, along.z) * 0.5
	var ground := base
	if is_nan(ground):
		ground = -INF
		for cell in BuildingMap.edge_cells(edge):
			ground = maxf(ground, _ground_at(Vector2(cell) + Vector2(0.5, 0.5)))
	var centre := Vector3(edge.x, 0.0, edge.y) * cs + along * cs * 0.5 \
			+ Vector3.UP * (ground + height * 0.5)
	_preview_boxes.append([centre, along * cs * 0.5 + across * 0.1 + Vector3.UP * height * 0.5,
			colour])


func _preview_corner(corner: Vector2i, colour: Color) -> void:
	var cs := grid.cell_size
	var ground := _ground_at(Vector2(corner))
	_preview_boxes.append([Vector3(corner.x * cs, ground + 0.5, corner.y * cs), Vector3(0.12, 0.5, 0.12),
			colour])

#endregion
