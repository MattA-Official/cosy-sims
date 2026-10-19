class_name BuildController
extends Node3D
## The build tools: turns mouse input into changes to a BuildingMap, and
## shows a see-through preview of what will happen before you commit.
##
## Drag tools (room, floor, wall, demolish) act when you let go of the left
## mouse button. Click tools (openings, object, room type) act on click. Brush
## tools (terrain, plants) act for as long as the button is held.

signal tool_changed(tool: Tool)
## The hint text has changed without the tool changing.
signal hint_changed

enum Tool { NONE, ROOM, FLOOR, WALL, OPENING, OBJECT, ROOM_TYPE, DEMOLISH, TERRAIN, PLANTS, PATH }
enum WaterMode { NONE, ADD, REMOVE }
## What the floor tool does: lay floor, or nudge existing floor up or down.
enum FloorMode { LAY, RAISE, LOWER, RAMP, STAIRS }

## How far one floor nudge moves, in metres.
const NUDGE_STEP := 0.25
## How far floors may be nudged from their storey's height, below and above.
const NUDGE_DOWN := 0.5
const NUDGE_UP := 0.75

const HINTS := {
	Tool.NONE: "",
	Tool.ROOM: "Drag to build a walled room.",
	Tool.FLOOR: "Drag to lay or restyle floor on this side of any walls. Shift-click for the whole room, Ctrl to remove.",
	Tool.WALL: "Drag between corners to build or restyle walls. Hold Alt for any angle, Ctrl to remove.",
	Tool.OPENING: "Click a wall to put in a door or window. Click it again to fill it in.",
	Tool.OBJECT: "Click to place. R turns it by %s°; [ and ] change the step. Hold F to turn it freely, Alt to place freely.",
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
	FloorMode.RAMP: "Drag over floor from the low side to the high side to lay a ramp between them.",
	FloorMode.STAIRS: "Click the foot of the stairs and move the way they climb. Click short of the top for a landing, at the top to build. Esc starts again, Ctrl-click removes stairs.",
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
## The stair builder's own state: the landing style and the stairs being drawn.
var stair_tool := StairTool.new()
var tool := Tool.NONE:
	set(value):
		tool = value
		_dragging = false
		path_tool.cancel()
		stair_tool.cancel()
		tool_changed.emit(tool)
var object_def: ObjectDef
## Styles used by the room, floor and wall tools.
var floor_style: StringName = BuildingMap.DEFAULT_FLOOR
var wall_style: StringName = BuildingMap.DEFAULT_WALL
## How far placed objects are turned, in radians.
var object_angle := 0.0
## How far R turns an object, in degrees; [ and ] step through ROTATION_STEPS.
var rotation_step := 45.0
## The room type the room type tool applies. Null clears a room's type.
var room_type: RoomTypeDef
## What the opening tool puts in: Wall.DOOR or Wall.WINDOW, and which kind
## of window.
var opening := BuildingMap.Wall.DOOR
var window_kind := BuildingMap.WINDOW_GLASS
var terrain_brush := Terrain.Brush.RAISE
## When not NONE, the terrain tool adds or removes water instead of sculpting.
var water_mode := WaterMode.NONE
var floor_mode := FloorMode.LAY:
	set(value):
		floor_mode = value
		stair_tool.cancel()
## Walls go at any angle between corners, not just straight or 45°.
var any_angle := false
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
## [centre, half extents, colour] per box, or [centre, half along, colour,
## half across, half height] for a box at an angle.
var _preview_boxes: Array[Array] = []
var _preview_polygons: Array[Array] = [] ## [points, colour] per flat polygon.
var _drag_start_point := Vector2.ZERO
var _free_rotating := false
var _rotate_anchor := Vector2.ZERO
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
	_update_free_rotate()
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
		elif tool == Tool.FLOOR and stair_tool.cancel():
			pass
		else:
			tool = Tool.NONE
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_rotate") and tool == Tool.OBJECT:
		object_angle = wrapf(snappedf(object_angle + deg_to_rad(rotation_step), deg_to_rad(rotation_step)),
				0.0, TAU)
		get_viewport().set_input_as_handled()
	elif tool == Tool.OBJECT and (event.is_action_pressed("build_brush_smaller")
			or event.is_action_pressed("build_brush_bigger")):
		var index := ROTATION_STEPS.find(rotation_step)
		index += 1 if event.is_action_pressed("build_brush_smaller") else -1
		rotation_step = ROTATION_STEPS[clampi(index, 0, ROTATION_STEPS.size() - 1)]
		hint_changed.emit()
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
		Tool.FLOOR when floor_mode == FloorMode.STAIRS:
			_press_stairs()
		Tool.ROOM, Tool.FLOOR, Tool.DEMOLISH:
			_dragging = true
			_drag_start_cell = _hover_cell()
			_drag_start_point = _hover_point
		Tool.WALL:
			_dragging = true
			_drag_start_corner = _hover_corner()
		Tool.OPENING:
			var slant := _hover_slant()
			if slant != NO_SLANT:
				if _has_chosen_slant_opening(slant):
					map.set_slant_opening(slant, BuildingMap.Wall.WALL)
				else:
					map.set_slant_opening(slant, opening, window_kind)
				return
			var edge := _hover_edge()
			if _has_chosen_opening(edge):
				map.set_opening(edge, BuildingMap.Wall.WALL)
			else:
				map.set_opening(edge, opening, window_kind)
		Tool.OBJECT:
			if object_def != null and _can_place(_object_centre()):
				map.place_object_at(object_def, _object_centre(), object_angle)
		Tool.ROOM_TYPE:
			var room := map.room_at_point(_hover_point)
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
	var ramp := planned_ramp()
	var chosen := planned_floor() if tool == Tool.FLOOR else ([] as Array[TilePiece])
	_dragging = false
	var erase := _erasing()
	match tool:
		Tool.ROOM:
			var height := build_height(rect)
			if can_build_floor(rect):
				map.build_room(rect, floor_style, wall_style, height)
				settle_ground(rect)
		Tool.FLOOR when floor_mode == FloorMode.RAMP:
			if ramp != null:
				map.add_ramp(ramp.rect, ramp.rise, ramp.low, ramp.high)
		Tool.FLOOR when floor_mode != FloorMode.LAY:
			nudge_floors(rect, NUDGE_STEP if floor_mode == FloorMode.RAISE else -NUDGE_STEP)
		Tool.FLOOR:
			if erase:
				map.set_piece_floors(chosen, &"")
			elif not chosen.is_empty():
				var area := _pieces_bounds(chosen)
				map.set_piece_floors(chosen, floor_style, build_height(area))
				settle_ground(area)
		Tool.WALL:
			var end := _wall_end_corner()
			var edges := BuildingMap.edges_on_line(_drag_start_corner, end)
			var keys := BuildingMap.slants_on_line(_drag_start_corner, end)
			if erase:
				map.remove_walls(edges)
				map.remove_slants(keys)
			else:
				map.build_walls(edges, wall_style)
				map.build_slants(keys, wall_style)
		Tool.DEMOLISH:
			if rect.size != Vector2i.ONE:
				map.demolish(rect)
				return
			# A click takes the most specific thing under the mouse.
			var placed := map.object_at(_hover_point)
			var edge := _hover_edge()
			var slant := _hover_slant()
			var flight := map.stairs_at(_hover_cell())
			if placed != null:
				map.remove_object(placed.id)
			elif flight != null:
				map.remove_stairs(flight.id)
			elif slant != NO_SLANT:
				map.remove_slants([slant])
			elif map.wall_at(edge) != BuildingMap.Wall.NONE and _edge_distance() < 0.25:
				map.remove_walls([edge])
			else:
				map.demolish(rect)


## A click with the stair builder: Ctrl removes the stairs under the mouse;
## otherwise it sets the foot, adds a landing or builds the stairs.
func _press_stairs() -> void:
	if _erasing():
		stair_tool.cancel()
		var flight := map.stairs_at(_hover_cell())
		if flight != null:
			map.remove_stairs(flight.id)
		return
	var planned := stair_tool.plan(_hover_cell())
	if stair_tool.is_drawing() and not _stairs_fit(planned[0]):
		return
	var flight := stair_tool.press(_hover_cell())
	if flight != null:
		flight.style = floor_style
		map.add_stairs(flight)


## Can stairs go along this route on the level being built?
func _stairs_fit(route: Array[Vector2i]) -> bool:
	if building != null:
		return building.can_add_stairs(_level(), route)
	return map.can_add_stairs(route)


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
	if tool == Tool.OBJECT:
		return HINTS[tool] % String.num(rotation_step)
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


## The pieces of floor the current drag would lay, restyle or take up: those
## on the same side of any walls as where the drag began, inside the drag.
## With Shift, the whole walled-in area under the mouse, or the room there if
## it is not walled in. Pieces that can't take floor are left out.
func planned_floor() -> Array[TilePiece]:
	var chosen: Array[TilePiece] = []
	if Input.is_action_pressed("build_whole_room"):
		chosen = map.pieces_within_walls(_hover_point, Rect2i(), WHOLE_ROOM_LIMIT)
		var room := map.room_at_point(_hover_point)
		if chosen.is_empty() and room != null:
			for id in room.pieces:
				chosen.append(map.pieces(Vector2i(id.x, id.y))[id.z])
	elif _dragging:
		chosen = map.pieces_within_walls(_drag_start_point, _drag_rect())
	else:
		chosen = map.pieces_within_walls(_hover_point, _drag_rect())
	if _erasing():
		return chosen
	return chosen.filter(func(piece: TilePiece) -> bool:
		return can_build_floor(Rect2i(piece.cell, Vector2i.ONE)))


func _pieces_bounds(chosen: Array[TilePiece]) -> Rect2i:
	var bounds := Rect2i(chosen[0].cell, Vector2i.ONE)
	for piece in chosen:
		bounds = bounds.expand(piece.cell).merge(Rect2i(piece.cell, Vector2i.ONE))
	return bounds


## The ramp the current drag would lay: climbing from where the drag began
## towards where it is now, from the floor before its foot to the floor past
## its top. Null when it cannot go there.
func planned_ramp() -> BuildingMap.Ramp:
	if not _dragging:
		return null
	var rect := _drag_rect()
	var start := _drag_start_cell
	var end := _hover_cell().clamp(rect.position, rect.end - Vector2i.ONE)
	var d := end - start
	if d == Vector2i.ZERO or not map.can_add_ramp(rect):
		return null
	var ramp := BuildingMap.Ramp.new()
	ramp.rect = rect
	ramp.rise = Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	ramp.low = _ramp_end_height(start, -ramp.rise)
	ramp.high = _ramp_end_height(end, ramp.rise)
	if is_equal_approx(ramp.low, ramp.high):
		return null
	return ramp


## The height a ramp should meet at one end: the floor just beyond it, or
## the tile itself when nothing is there.
func _ramp_end_height(cell: Vector2i, outward: Vector2i) -> float:
	var beyond := cell + outward
	if map.has_floor(beyond):
		return map.edge_height(beyond, -outward)
	return map.floor_height(cell)


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


func _can_place(position: Vector2) -> bool:
	if building != null:
		return building.can_place(_level(), object_def, position, object_angle)
	return map.can_place_at(object_def, position, object_angle)


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


## Where the middle of the object being placed would go: under the mouse,
## snapped as the object likes. Square-on objects line up with tiles; turned
## ones snap their middle to half or quarter tiles. While F is held the
## object stays put and turns to face the mouse instead.
func _object_centre() -> Vector2:
	if _free_rotating:
		return _rotate_anchor
	var snap := object_def.snap
	if Input.is_action_pressed("build_free_place"):
		snap = ObjectDef.Snap.FREE
	var quarter := object_angle / (PI * 0.5)
	if is_equal_approx(quarter, roundf(quarter)):
		var turns := posmod(roundi(quarter), 4)
		var corner := BuildingMap.snapped_position(object_def, _hover_point, turns, snap)
		return BuildingMap.object_rect(object_def, corner, turns).get_center()
	match snap:
		ObjectDef.Snap.TILE:
			return _hover_point.snapped(Vector2(0.5, 0.5))
		ObjectDef.Snap.QUARTER:
			return _hover_point.snapped(Vector2(0.25, 0.25))
	return _hover_point


## Holding F pins the object where it is and turns it to face the mouse.
func _update_free_rotate() -> void:
	var held := tool == Tool.OBJECT and object_def != null \
			and Input.is_action_pressed("build_free_rotate")
	if held and not _free_rotating:
		_rotate_anchor = _object_centre()
	_free_rotating = held
	if held and _hover_point.distance_to(_rotate_anchor) > 0.3:
		# Point the object's length (its +Z side) at the mouse.
		object_angle = wrapf((_hover_point - _rotate_anchor).angle() - PI * 0.5, 0.0, TAU)


## Walls go in straight lines, so snap to whichever axis the drag follows most.
## Where a wall being dragged ends: straight along X or Z or at 45°, or at
## any angle while Alt is held.
func _wall_end_corner() -> Vector2i:
	var corner := _hover_corner()
	if any_angle or Input.is_action_pressed("build_free_place"):
		return corner
	var delta := corner - _drag_start_corner
	var size := maxi(absi(delta.x), absi(delta.y))
	var best := _drag_start_corner
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		for sign in [1, -1]:
			var reach := mini(size, roundi(Vector2(delta).dot(Vector2(dir * sign)) / Vector2(dir).length_squared()))
			var candidate: Vector2i = _drag_start_corner + dir * sign * maxi(reach, 0)
			if Vector2(candidate).distance_to(corner) < Vector2(best).distance_to(corner):
				best = candidate
	return best


const NO_SLANT := Vector4i(-1, -1, -1, -1)
## Steps R can turn objects by, in degrees, from coarse to fine.
const ROTATION_STEPS: Array[float] = [90.0, 45.0, 22.5, 15.0, 5.0, 1.0]
## The most pieces Shift-click floors at once; bigger areas are not rooms.
const WHOLE_ROOM_LIMIT := 4000

## The angled wall nearest the mouse, if one is close enough to pick.
func _hover_slant() -> Vector4i:
	var best := NO_SLANT
	var best_distance := 0.3
	var cell := _hover_cell()
	for offset in BuildingMap.cells_in(Rect2i(cell - Vector2i.ONE, Vector2i(3, 3))):
		for key: Vector4i in map.slants_through(offset):
			var ends := BuildingMap.slant_ends(key)
			var closest := Geometry2D.get_closest_point_to_segment(_hover_point, Vector2(ends[0]),
					Vector2(ends[1]))
			var distance := closest.distance_to(_hover_point)
			if distance < best_distance:
				best = key
				best_distance = distance
	return best


func _has_chosen_slant_opening(key: Vector4i) -> bool:
	if map.slant_at(key) != opening:
		return false
	return opening != BuildingMap.Wall.WINDOW or map.slant_window_kind(key) == window_kind

#endregion

#region Preview

func _draw_preview() -> void:
	_preview_mesh.clear_surfaces()
	_preview_boxes.clear()
	_preview_polygons.clear()
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
		Tool.FLOOR when floor_mode == FloorMode.STAIRS:
			var planned := stair_tool.plan(_hover_cell())
			if _erasing():
				var flight := map.stairs_at(_hover_cell())
				if flight != null:
					_preview_cells(flight.cells, demolish_colour)
			else:
				_preview_stairs(planned, ok_colour if _stairs_fit(planned[0]) else bad_colour)
		Tool.FLOOR when floor_mode == FloorMode.RAMP:
			var ramp := planned_ramp()
			_preview_cells(BuildingMap.cells_in(_drag_rect()), ok_colour if ramp != null else bad_colour)
		Tool.FLOOR when floor_mode != FloorMode.LAY:
			var cells: Array[Vector2i] = []
			for cell in BuildingMap.cells_in(_drag_rect()):
				if map.has_floor(cell):
					cells.append(cell)
			_preview_cells(cells, ok_colour)
		Tool.FLOOR:
			var chosen := planned_floor()
			if chosen.is_empty():
				_preview_cells([_hover_cell()], bad_colour)
			else:
				var height := NAN if _erasing() else _preview_height(_pieces_bounds(chosen))
				_preview_pieces(chosen, demolish_colour if _erasing() else ok_colour, height)
		Tool.TERRAIN when water_mode != WaterMode.NONE:
			_preview_water()
		Tool.TERRAIN, Tool.PLANTS:
			var colour := demolish_colour if tool == Tool.PLANTS and _erasing() else ok_colour
			_preview_ring(_hover_point, brush_radius, colour)
		Tool.DEMOLISH:
			var placed := map.object_at(_hover_point)
			var flight := map.stairs_at(_hover_cell())
			if _dragging:
				_preview_cells(BuildingMap.cells_in(_drag_rect()), demolish_colour)
			elif placed != null:
				_preview_rect(placed.rect, demolish_colour, placed.def.height + 0.05)
			elif flight != null:
				_preview_cells(flight.cells, demolish_colour, NAN, Building.STOREY * 0.5)
			elif _hover_slant() != NO_SLANT:
				_preview_slant(_hover_slant(), demolish_colour)
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
				for key in BuildingMap.slants_on_line(_drag_start_corner, _wall_end_corner()):
					if _erasing():
						_preview_slant(key, demolish_colour)
					else:
						_preview_slant(key, ok_colour if map.can_build_slant(key) else bad_colour)
			else:
				_preview_corner(_hover_corner(), ok_colour)
		Tool.OPENING when _hover_slant() != NO_SLANT:
			var key := _hover_slant()
			var ok := not (opening == BuildingMap.Wall.WINDOW and map.is_outdoor_slant(key))
			_preview_slant(key, ok_colour if ok else bad_colour)
		Tool.OPENING:
			var edge := _hover_edge()
			var ok := map.wall_at(edge) != BuildingMap.Wall.NONE
			if opening == BuildingMap.Wall.WINDOW and map.is_outdoor_wall(edge):
				ok = false
			_preview_edge(edge, ok_colour if ok else bad_colour)
		Tool.OBJECT:
			if object_def != null:
				var centre := _object_centre()
				var ok := _can_place(centre)
				_preview_object(centre, ok_colour if ok else bad_colour)
		Tool.ROOM_TYPE:
			var room := map.room_at_point(_hover_point)
			if room != null:
				var colour := room_type.colour if room_type != null else Color.WHITE
				colour.a = 0.45
				_preview_cells(room.cells, colour)
	if _preview_boxes.is_empty() and _preview_polygons.is_empty():
		return
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _preview_material)
	for polygon in _preview_polygons:
		var points: PackedVector3Array = polygon[0]
		_preview_mesh.surface_set_normal(Vector3.UP)
		_preview_mesh.surface_set_color(polygon[1])
		# Both windings, so the slab shows whichever way the outline runs.
		for i in range(1, points.size() - 1):
			for vertex in [points[0], points[i], points[i + 1], points[0], points[i + 1], points[i]]:
				_preview_mesh.surface_add_vertex(vertex)
	for box in _preview_boxes:
		if box.size() > 3:
			MeshShapes.add_oriented_box_immediate(_preview_mesh, box[0], box[1], box[3], box[4], box[2])
		else:
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
## Thin slabs over pieces of tiles, following angled walls.
func _preview_pieces(chosen: Array[TilePiece], colour: Color, base := NAN) -> void:
	var cs := grid.cell_size
	for piece in chosen:
		var ground := base if not is_nan(base) else _ground_at(piece.centre())
		var points := PackedVector3Array()
		for point in piece.polygon:
			var inset := point.lerp(piece.centre(), 0.04)
			points.append(Vector3(inset.x * cs, ground + 0.06, inset.y * cs))
		_preview_polygons.append([points, colour])


func _preview_cells(cells: Array[Vector2i], colour: Color, base := NAN, height := 0.06) -> void:
	var cs := grid.cell_size
	for cell in cells:
		var ground := base if not is_nan(base) else _ground_at(Vector2(cell) + Vector2(0.5, 0.5))
		var centre := Vector3(cell.x + 0.5, ground, cell.y + 0.5) * Vector3(cs, 1.0, cs)
		_preview_boxes.append([centre + Vector3.UP * height * 0.5,
				Vector3(cs * 0.48, height * 0.5, cs * 0.48), colour])


## The stairs a click would leave: each tread at its height, standing on
## the floor at the foot.
func _preview_stairs(planned: Array, colour: Color) -> void:
	var route: Array[Vector2i] = planned[0]
	var flags: Array[bool] = planned[1]
	var flight := Staircase.create(route, flags, stair_tool.rounded)
	var cs := grid.cell_size
	var base := _ground_at(Vector2(route[0]) + Vector2(0.5, 0.5))
	for tread: Array in flight.treads():
		var points := PackedVector3Array()
		for p: Vector2 in tread[0]:
			points.append(Vector3(p.x * cs, base + tread[1] + 0.04, p.y * cs))
		_preview_polygons.append([points, colour])


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


## The object being placed, turned as it will go.
func _preview_object(centre: Vector2, colour: Color) -> void:
	var cs := grid.cell_size
	var half := object_def.size * 0.5 * cs
	var along := Vector2(1, 0).rotated(object_angle)
	var height := object_def.height
	_preview_boxes.append([Vector3(centre.x * cs, _ground_at(centre) + height * 0.5, centre.y * cs),
			Vector3(along.x, 0.0, along.y) * half.x, colour,
			Vector3(-along.y, 0.0, along.x) * half.y, height * 0.5])


## A wall preview. `base` sets the height it stands at; by default it
## stands on the floor or ground beside it. Kept below full wall height so
## a big drag does not hide what is behind it.
func _preview_slant(key: Vector4i, colour: Color) -> void:
	var cs := grid.cell_size
	var ends := BuildingMap.slant_ends(key)
	var a := Vector2(ends[0])
	var b := Vector2(ends[1])
	var height := view.low_wall_height if view.walls_low else preview_wall_height
	var ground := _ground_at((a + b) * 0.5)
	var flat := (b - a).normalized()
	var middle := (a + b) * 0.5 * cs
	_preview_boxes.append([Vector3(middle.x, ground + height * 0.5, middle.y),
			Vector3(flat.x, 0.0, flat.y) * a.distance_to(b) * cs * 0.5, colour,
			Vector3(-flat.y, 0.0, flat.x) * 0.1, height * 0.5])


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
