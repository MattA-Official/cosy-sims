class_name BuildController
extends Node3D
## The build tools: turns mouse input into changes to a BuildingMap, and
## shows a see-through preview of what will happen before you commit.
##
## Drag tools (room, floor, wall, demolish) act when you let go of the left
## mouse button. Click tools (openings, object, room type, zones) act on
## click. Brush
## tools (terrain, plants) act for as long as the button is held.

signal tool_changed(tool: Tool)
## The hint text has changed without the tool changing.
signal hint_changed
## A click would have bought land you can't afford.
signal land_refused
## The brush size or plant density changed.
signal brush_changed
signal wall_view_changed(mode: WallView)
## The zones tool clicked a door, to lock or unlock it by hand; with `pin`
## (Shift held) it stays that way past the block.
signal door_lock_clicked(level: int, edge: Vector3i, pin: bool)
## The route tool clicked a point (in tile units) on a level; with `erase`
## (Ctrl held), to remove the route there.
signal route_clicked(level: int, point: Vector2, erase: bool)
## A click would have built something, but spending_allowed said no.
signal spending_refused
## A move or paste couldn't go down, and why.
signal drop_refused(reason: String)
## Something was copied, with a word on what.
signal copied(what: String)

## What Tab loops through, like The Sims: walls up; cutaway (walls in front
## of rooms drop, as the camera looks); every wall down; and roofs on, for
## a look at the whole building from outside.
enum WallView { UP, CUTAWAY, DOWN, ROOFS }
const WALL_VIEW_NAMES: Array[String] = ["Walls up", "Cutaway", "Walls down", "Roofs on"]

## Whether building things that cost money is allowed now. Unset allows it.
var spending_allowed: Callable

var wall_view := WallView.UP:
	set(value):
		if value == wall_view:
			return
		wall_view = value
		wall_view_changed.emit(value)

enum Tool { NONE, ROOM, FLOOR, WALL, OPENING, OBJECT, ROOM_TYPE, DEMOLISH, TERRAIN, PLANTS, PATH, ZONE, ROUTE, MOVE }
enum WaterMode { NONE, ADD, REMOVE, RIVER }
## What the floor tool does: lay floor, or nudge existing floor up or down.
enum FloorMode { LAY, RAISE, LOWER, RAMP, STAIRS }
## What the wall tool does: build whole walls, or paint one side of them.
enum WallMode { BUILD, PAINT }

## How far one floor nudge moves, in metres.
const NUDGE_STEP := 0.25
## How many tiles of ground round a new building slope to meet it.
const GROUND_SKIRT := 2
## How far floors may be nudged from their storey's height, below and above.
const NUDGE_DOWN := 0.5
const NUDGE_UP := 0.75

const HINTS := {
	Tool.NONE: "",
	Tool.ROOM: "Drag to build a walled room.",
	Tool.FLOOR: "Drag to lay or restyle floor on this side of any walls. Shift-click for the whole room, Ctrl to remove.",
	Tool.WALL: "Drag between corners to build or restyle walls. Hold Alt for any angle, Ctrl to remove.",
	Tool.OPENING: "Click a wall to put in a door or window. Click it again to fill it in.",
	Tool.OBJECT: "Click to place. R turns it by %s°; [ and ] change the step. Hold F to turn it freely, Alt to place freely. V changes the look.",
	Tool.ROOM_TYPE: "Click a room to mark it.",
	Tool.DEMOLISH: "Click an object or wall to remove it, or drag to clear an area.",
	Tool.MOVE: "Click an object or room to pick it up, or drag a box round what to move. Click again to put it down.",
	Tool.TERRAIN: "Hold the mouse to shape your land. [ and ] change the brush size.",
	Tool.PLANTS: "Hold the mouse to plant, or click to place one at the smallest size. Hold Ctrl to clear. [ and ] change the size.",
	Tool.PATH: "",
	Tool.ZONE: "Click a room to say who may be in it. Click a door to lock or unlock it until the next block; Shift-click to keep it so.",
	Tool.ROUTE: "Click to add points to a patrol route; click the first point or press Enter to close the loop. Esc stops drawing; Ctrl-click a route to remove it.",
}

const PATH_HINTS := {
	PathTool.Mode.STRAIGHT: "Click to start a path and click again to end it. Page Up or Down for stairs or a bridge, Alt to place off the grid. Esc stops, Ctrl-click removes.",
	PathTool.Mode.CURVED: "Click the start, a bend point, then the end. Page Up or Down for stairs or a bridge, Alt to snap or free a point. Esc stops, Ctrl-click removes.",
	PathTool.Mode.FREEHAND: "Drag to draw a path; it is smoothed when you let go. Ctrl-click removes a path.",
}

const FLOOR_HINTS := {
	FloorMode.RAISE: "Drag over floor to raise it a step, for split levels.",
	FloorMode.LOWER: "Drag over floor to lower it a step, for split levels.",
	FloorMode.RAMP: "Drag over floor from the low side to the high side to lay a ramp between them.",
	FloorMode.STAIRS: "Click the foot of the stairs and move the way they climb. Click short of the top for a landing, at the top to build. Esc starts again, Ctrl-click removes stairs.",
}

const WALL_PAINT_HINT := "Click or drag along walls to paint the side you can see. Shift-click paints every wall round the room, Ctrl takes paint off."

const LAND_HINT := "Click a plot next to your land to buy it, or drag across several. Ctrl+Z gives it back for a full refund until the hour is up."
const SELL_HINT := "Click or drag across your empty plots to sell them back for half what they cost."

const WATER_HINTS := {
	WaterMode.ADD: "Click a hollow to fill it with water. Digging deeper or cutting the rim moves the water.",
	WaterMode.REMOVE: "Click a pond, lake or river to drain it.",
	WaterMode.RIVER: "Click along where the river runs, from its source; click the last point again to finish. [ and ] set its width. Esc to start again.",
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

const MIN_PLANT_DENSITY := 0.25

@export_group("Preview colours")
@export var ok_colour := Color(0.45, 0.95, 0.55, 0.45)
@export var bad_colour := Color(1.0, 0.4, 0.4, 0.45)
## Outlines plots of land for sale.
@export var land_colour := Color(1.0, 0.85, 0.4, 0.5)
## Land paid for but waiting on planning permission.
@export var pending_colour := Color(0.55, 0.7, 1.0, 0.3)
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
		_carried = null
		path_tool.cancel()
		stair_tool.cancel()
		tool_changed.emit(tool)
var object_def: ObjectDef
## Styles used by the room, floor and wall tools.
var floor_style: StringName = BuildingMap.DEFAULT_FLOOR
var wall_style: StringName = BuildingMap.DEFAULT_WALL
## How far placed objects are turned, in radians.
var object_angle := 0.0
## Which look placed objects wear (see ObjectDef.looks); one past the last
## mixes them at random.
var object_look := 0
## How far R turns an object, in degrees; [ and ] step through ROTATION_STEPS.
var rotation_step := 45.0
## The room type the room type tool applies. Null clears a room's type.
var room_type: RoomTypeDef
## What the opening tool puts in: Wall.DOOR or Wall.WINDOW, and which kind
## of window.
var opening := BuildingMap.Wall.DOOR
var window_kind := BuildingMap.WINDOW_GLASS
## The kind of door the opening tool puts in, such as &"staff", or empty
## for a plain door.
var door_kind: StringName = &""
## The zone the zones tool paints. Null goes back to the room type's.
var zone: ZoneDef
var terrain_brush := Terrain.Brush.RAISE
## When not NONE, the terrain tool adds or removes water instead of sculpting.
var water_mode := WaterMode.NONE
## Rivers being drawn: their width in tiles, and the points so far.
var river_width := 3.0
var _river_points := PackedVector2Array()
## Plots of land for sale, or null where land can't be bought.
var land_plots: LandPlots
## The terrain tool buys land instead of sculpting, flattening it if asked.
var buying_land := false
## In the land mode, selling back rather than buying.
var selling_land := false
var flatten_land := false
var floor_mode := FloorMode.LAY:
	set(value):
		if not Building.split_levels and value in [FloorMode.RAISE, FloorMode.LOWER, FloorMode.RAMP]:
			value = FloorMode.LAY
		floor_mode = value
		stair_tool.cancel()
var wall_mode := WallMode.BUILD:
	set(value):
		wall_mode = value
		_painting = false
## Walls go at any angle between corners, not just straight or 45°.
var any_angle := false
var plant_def: FoliageDef
## Brush radius in tiles, for the terrain and plant tools. Plants can go
## down to 0, which places one plant per click.
var brush_radius := 3.0:
	set(value):
		brush_radius = value
		brush_changed.emit()
## How closely plants of one kind are painted, from 0.25 (four times their
## spacing apart) to 1 (as close as their spacing allows).
## How hard the terrain brush works, from 0.1 to 1. 0.5 is the speeds
## above; 1 is twice as fast.
var terrain_strength := 0.5:
	set(value):
		terrain_strength = clampf(value, 0.1, 1.0)
		brush_changed.emit()
var plant_density := 1.0:
	set(value):
		plant_density = clampf(value, MIN_PLANT_DENSITY, 1.0)
		brush_changed.emit()

## () -> int: money to hand, so readouts can say when you can't afford
## something. Optional.
var balance: Callable
## Charges for what's built. Optional: a move charges its walls and floor
## in full through it, and a paste checks the price first.
var build_costs: BuildCosts
## (StringName) -> ObjectDef, for putting the map back when a move doesn't
## fit.
var find_object: Callable
## Building over time. Optional: without it everything goes up at once.
var blueprints: Blueprints
## Templates to take up with the move tool. Optional.
var templates: TemplateStore
## What Ctrl+C copied last, shared by every game in the session.
static var clipboard: BuildClip
## What the move tool is carrying, and whether it's a paste (which goes
## down again and again) rather than a move.
var _carried: BuildClip
var _pasting := false
## Where the mouse holds what's carried, from its top-left.
var _grab := Vector2.ZERO

## Makes the floor and wall tools remove instead of build, as if Ctrl were
## held. Mainly for tests.
var force_erase := false

var _dragging := false
## The wall tool is painting sides for as long as the button is held.
var _painting := false
var _drag_start_cell := Vector2i.ZERO
var _drag_start_corner := Vector2i.ZERO
var _hover_point := Vector2.ZERO ## Mouse position on the ground, in cell units.
var _has_hover := false
var _preview_mesh := ImmediateMesh.new()
var _preview_material := MeshShapes.vertex_colour_material(true)
var _shapes := PreviewShapes.new()
var _drag_start_point := Vector2.ZERO
var _free_rotating := false
var _middle_from := Vector2.INF
var _rotate_anchor := Vector2.ZERO
var _path_preview := MeshInstance3D.new()
var _path_status := ""
var _door_status_shown := ""
var _land_status_shown := ""
## The last land picked, and what it was picked from: [chosen, outlined, ok].
var _land_key: Array = []
var _land_cache: Array = []
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
	_shapes.ground_at = _ground_at
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
	if _painting and _has_hover:
		_paint_walls()
	if tool == Tool.PATH and _has_hover:
		path_tool.free_held = Input.is_action_pressed("build_free_place")
		path_tool.extend_trail(_hover_point)
		var status := path_tool.status(_hover_point)
		if status != _path_status:
			_path_status = status
			hint_changed.emit()
	var door_status := _door_status() if tool == Tool.OPENING and _has_hover else ""
	if door_status != _door_status_shown:
		_door_status_shown = door_status
		hint_changed.emit()
	var land_status := _land_status() if _buying() and _has_hover else ""
	if land_status != _land_status_shown:
		_land_status_shown = land_status
		hint_changed.emit()
	_draw_preview()


func _input(event: InputEvent) -> void:
	# A middle click that doesn't drag the camera is the eyedropper.
	var middle := event as InputEventMouseButton
	if middle != null and middle.button_index == MOUSE_BUTTON_MIDDLE and tool != Tool.NONE:
		if middle.pressed:
			_middle_from = middle.position
		elif middle.position.distance_to(_middle_from) < 4.0:
			eyedrop()
	# Finish a drag even if the button is let go over the toolbar.
	if event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_brushing = false
		_painting = false
		if _dragging:
			_on_release()
		if tool == Tool.PATH and path_tool.mode == PathTool.Mode.FREEHAND and _has_hover:
			path_tool.end_trail(_hover_point)


func _unhandled_input(event: InputEvent) -> void:
	if map == null:
		return
	if event.is_action_pressed("build_cancel"):
		if tool == Tool.NONE and not _dragging:
			# Nothing to put away: leave Esc to the game (the pause menu).
			return
		if _dragging:
			_dragging = false
		elif _carried != null:
			_carried = null
			hint_changed.emit()
		elif tool == Tool.PATH and path_tool.cancel():
			pass
		elif tool == Tool.FLOOR and stair_tool.cancel():
			pass
		elif tool == Tool.TERRAIN and not _river_points.is_empty():
			_river_points.clear()
		else:
			tool = Tool.NONE
		get_viewport().set_input_as_handled()
	elif tool == Tool.PATH and path_tool.is_drawing() and (event.is_action_pressed("level_up")
			or event.is_action_pressed("level_down")):
		# While placing a path, Page Up and Down choose stairs or a bridge
		# rather than changing floor.
		if event.is_action_pressed("level_up"):
			path_tool.raise()
		else:
			path_tool.lower()
		get_viewport().set_input_as_handled()
	elif _carried != null and (event.is_action_pressed("build_rotate")
			or event.is_action_pressed("build_brush_smaller") or event.is_action_pressed("build_brush_bigger")):
		_turn_carried(-1 if event.is_action_pressed("build_brush_smaller") else 1)
		Sound.play(&"build_rotate")
		get_viewport().set_input_as_handled()
	elif _is_shortcut(event, KEY_C):
		if copy_hovered():
			get_viewport().set_input_as_handled()
	elif _is_shortcut(event, KEY_V):
		if paste():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_look") and tool == Tool.OBJECT and object_def != null:
		object_look = (mini(object_look, object_def.look_count()) + 1) % (object_def.look_count() + 1)
		if object_def.look_count() == 1:
			object_look = 0
		hint_changed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_rotate") and tool == Tool.OBJECT:
		object_angle = wrapf(snappedf(object_angle + deg_to_rad(rotation_step), deg_to_rad(rotation_step)),
				0.0, TAU)
		Sound.play(&"build_rotate")
		get_viewport().set_input_as_handled()
	elif tool == Tool.OBJECT and (event.is_action_pressed("build_brush_smaller")
			or event.is_action_pressed("build_brush_bigger")):
		var index := ROTATION_STEPS.find(rotation_step)
		index += 1 if event.is_action_pressed("build_brush_smaller") else -1
		rotation_step = ROTATION_STEPS[clampi(index, 0, ROTATION_STEPS.size() - 1)]
		hint_changed.emit()
		get_viewport().set_input_as_handled()
	elif tool == Tool.TERRAIN and water_mode == WaterMode.RIVER and (event.is_action_pressed("build_brush_smaller")
			or event.is_action_pressed("build_brush_bigger")):
		river_width = clampf(river_width + (-1.0 if event.is_action_pressed("build_brush_smaller") else 1.0),
				River.LEAST_WIDTH, River.MOST_WIDTH)
		hint_changed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_brush_smaller") and _uses_brush():
		brush_radius = maxf(brush_radius - 1.0, smallest_brush())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_brush_bigger") and _uses_brush():
		brush_radius = minf(brush_radius + 1.0, max_brush_radius)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_eyedropper") and tool != Tool.NONE:
		eyedrop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_toggle_walls"):
		next_wall_view()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and tool != Tool.NONE and _has_hover:
			_on_press()
			get_viewport().set_input_as_handled()


func _on_press() -> void:
	if _ground_only(tool) and _level() != 0:
		return
	if _spends() and spending_allowed.is_valid() and not spending_allowed.call():
		spending_refused.emit()
		return
	match tool:
		Tool.FLOOR when floor_mode == FloorMode.STAIRS:
			_press_stairs()
		Tool.MOVE when _carried != null:
			drop()
		Tool.ROOM, Tool.FLOOR, Tool.DEMOLISH, Tool.MOVE:
			_dragging = true
			_drag_start_cell = _hover_cell()
			_drag_start_point = _hover_point
		Tool.WALL when wall_mode == WallMode.PAINT:
			_painting = true
			_paint_walls()
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
				map.set_opening(edge, opening, window_kind, door_kind)
		Tool.OBJECT:
			if object_def == null:
				return
			var target := _surface_target()
			var centre := _object_centre()
			if not target.is_empty():
				map.place_on_surface(object_def, target[0].id, target[1], snappedf(object_angle, PI * 0.5),
						_look_to_place())
			elif _can_place(centre, _placing_angle(centre)):
				map.place_object_at(object_def, centre, _placing_angle(centre), _look_to_place())
		Tool.ROOM_TYPE:
			var room := map.room_at_point(_hover_point)
			if room != null:
				map.set_room_type(room, room_type.id if room_type != null else &"")
		Tool.ROUTE:
			route_clicked.emit(_level(), _hover_point, _erasing())
		Tool.ZONE:
			if _hover_door() != NO_DOOR:
				door_lock_clicked.emit(_level(), _hover_door(), Input.is_action_pressed("build_whole_room"))
				return
			var room := map.room_at_point(_hover_point)
			if room != null:
				map.set_room_zone(room, zone.id if zone != null else &"")
		Tool.PATH:
			if paths == null:
				return
			if path_tool.mode == PathTool.Mode.FREEHAND and not _erasing():
				path_tool.begin_trail(_hover_point)
			else:
				path_tool.press(_hover_point, _erasing())
		Tool.TERRAIN when _buying():
			_dragging = true
			_drag_start_cell = _hover_cell()
		Tool.TERRAIN when water_mode != WaterMode.NONE:
			if water != null and water_mode == WaterMode.ADD:
				water.fill_at(_hover_cell())
			elif water != null and water_mode == WaterMode.RIVER:
				press_river(_hover_point)
			elif water != null:
				var river := water.river_at(_hover_cell())
				if river != null and water.body_at(_hover_cell()) == null:
					water.remove_river(river)
				else:
					water.remove_at(_hover_cell())
		Tool.PLANTS when brush_radius < 0.5:
			# The smallest size places or removes one plant per click.
			if foliage == null or _level() != 0:
				return
			if _erasing():
				foliage.remove_in_circle(_hover_point, 0.6)
			elif plant_def != null and can_grow(_hover_point):
				foliage.add(plant_def, _hover_point,
						_rng.randf_range(plant_def.scale_range.x, plant_def.scale_range.y),
						_rng.randf() * TAU, 1.0 / plant_density)
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
		Tool.TERRAIN when _buying():
			var plots := _land_choice()
			var done := land_plots.sell_all(plots) if selling_land else land_plots.buy_all(plots, flatten_land)
			_land_cache = []
			if not done:
				land_refused.emit()
		Tool.MOVE:
			pick_up(rect)
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


## Whether the current tool, as it is set, would build something that
## costs money.
func _spends() -> bool:
	if _erasing():
		return false
	match tool:
		Tool.ROOM, Tool.OPENING, Tool.OBJECT:
			return true
		Tool.MOVE:
			return _carried != null and (_pasting or _carried.is_structure())
		Tool.FLOOR:
			return floor_mode in [FloorMode.LAY, FloorMode.RAMP, FloorMode.STAIRS]
		Tool.WALL:
			return wall_mode == WallMode.BUILD
	return false


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

## Moves Tab on to the next wall view.
func next_wall_view() -> void:
	wall_view = ((wall_view + 1) % WallView.size()) as WallView


## What the current tool does, for the toolbar.
## Where the mouse is on the level being built on, in tile units, or
## null when it is off the map.
func hover_point() -> Variant:
	return _hover_point if _has_hover else null


func hint() -> String:
	if tool == Tool.FLOOR and floor_mode != FloorMode.LAY:
		return FLOOR_HINTS[floor_mode]
	if tool == Tool.WALL and wall_mode == WallMode.PAINT:
		return WALL_PAINT_HINT
	if _ground_only(tool) and _level() != 0:
		if tool == Tool.WALL:
			return "Perimeter fences go round the ground floor. Page Down to go back to it."
		return "This tool works on the ground floor. Page Down to go back to it."
	if _buying():
		return ((SELL_HINT if selling_land else LAND_HINT) + "\n" + _land_status_shown).strip_edges()
	if tool == Tool.TERRAIN and water_mode == WaterMode.RIVER:
		return "%s Width %d." % [WATER_HINTS[water_mode], roundi(river_width)]
	if tool == Tool.TERRAIN and water_mode != WaterMode.NONE:
		return WATER_HINTS[water_mode]
	if tool == Tool.PATH:
		return (PATH_HINTS[path_tool.mode] + "\n" + _path_status).strip_edges()
	if tool == Tool.OBJECT:
		var text: String = HINTS[tool] % String.num(rotation_step)
		if object_def != null and object_def.look_count() > 1:
			text += "\nLook: %s" % ("Mixed" if object_look >= object_def.look_count()
					else object_def.look_name(object_look))
		if object_def != null and object_def.sits == ObjectDef.Sits.SURFACE:
			text += "\nGoes on a table, desk or counter top."
		return text
	if tool == Tool.OPENING:
		return (HINTS[tool] + "\n" + _door_status_shown).strip_edges()
	if tool == Tool.MOVE and _carried != null:
		return ("Click to put down another copy. " if _pasting else "Click to put it down. ") \
				+ "R or [ and ] turn it, Ctrl+C copies it, Esc puts it back."
	return HINTS[tool]


#region Moving and copying

## Picks up what's under the mouse for the move tool: on a click, the
## object or else the room there; on a drag, everything in the box.
func pick_up(rect: Rect2i) -> bool:
	var clip := _clip_at(rect)
	if clip == null:
		return false
	_carried = clip
	_pasting = false
	_grab = _hover_point - Vector2(clip.from)
	hint_changed.emit()
	return true


func _clip_at(rect: Rect2i) -> BuildClip:
	if rect.size != Vector2i.ONE:
		return BuildClip.capture_rect(map, rect)
	var placed := map.object_at(_hover_point)
	if placed != null:
		return BuildClip.capture_object(map, placed)
	var room := map.room_at_point(_hover_point)
	return BuildClip.capture_room(map, room) if room != null else null


## Copies what the move tool carries, or else the object or room under the
## mouse. A copy being carried stays in hand; a move is put back.
func copy_hovered() -> bool:
	var clip := _carried
	if clip == null:
		if not _has_hover or map == null or tool == Tool.NONE:
			return false
		clip = _clip_at(Rect2i(_hover_cell(), Vector2i.ONE))
	if clip == null:
		return false
	clipboard = clip.copy()
	if not _pasting:
		_carried = null
	copied.emit("room" if clip.is_structure() else "object")
	hint_changed.emit()
	return true


## Takes up a copy of what was copied last, to put down as many times as
## you like.
func paste() -> bool:
	if clipboard == null or map == null:
		return false
	carry_copy(clipboard)
	return true


## Takes up a copy of a clip, such as a template, to put down.
func carry_copy(clip: BuildClip) -> void:
	tool = Tool.MOVE
	_carried = clip.copy()
	_pasting = true
	_grab = Vector2(_carried.size) * 0.5
	hint_changed.emit()


func carrying() -> BuildClip:
	return _carried


func _turn_carried(quarters: int) -> void:
	for i in posmod(quarters, 4):
		_grab = Vector2(_carried.size.y - _grab.y, _grab.x)
		_carried.rotate(1)


## Where what's carried would go down: its top-left tile.
func _carry_at() -> Vector2i:
	return Vector2i((_hover_point - _grab).round())


## Why what's carried can't go down at a tile, or empty if it can.
func _drop_problem(at: Vector2i) -> String:
	var problem := _carried.floor_problem(map, at, [] as Array[Vector2i] if _pasting else _carried.taken)
	if not problem.is_empty():
		return problem
	var price := _drop_price()
	if price > 0 and balance.is_valid() and balance.call() < price:
		return "Not enough money"
	return ""


## What putting down what's carried costs: a paste, everything in it; a
## move, its walls and floor in full again. Moving objects is free.
func _drop_price() -> int:
	if build_costs == null or _carried == null:
		return 0
	if _pasting:
		return build_costs.clip_price(_carried, true)
	if blueprints != null and not blueprints.instant:
		# The walls and floor are planned again, and paid for when built.
		return 0
	return build_costs.clip_price(_carried, false) if _carried.is_structure() else 0


## Puts down what's carried where the mouse is. Returns whether it went.
func drop() -> bool:
	if _carried == null:
		return false
	var at := _carry_at()
	var problem := _drop_problem(at)
	if problem.is_empty():
		problem = _put_carried(at)
	if not problem.is_empty():
		drop_refused.emit(problem)
		return false
	if not _pasting:
		_carried = null
		hint_changed.emit()
	return true


## Does the move or paste, putting everything back if any object won't
## fit. Returns why it failed, or empty.
func _put_carried(at: Vector2i) -> String:
	var clip := _carried if not _pasting else _carried.copy()
	var price := _drop_price()
	var before := map.to_data()
	var worth_before := build_costs.worth() if build_costs != null else 0
	if build_costs != null:
		build_costs.suspend()
	var lifted: Array[BuildingMap.PlacedObject] = []
	if not _pasting:
		lifted = map.lift_objects(clip.ids)
		if not clip.taken.is_empty():
			map.demolish_cells(clip.taken)
	var area := Rect2i(at, clip.size)
	if blueprints != null:
		blueprints.hold()
	var misfits := clip.put(map, at, build_height(area) if clip.is_structure() else 0.0, lifted)
	if misfits > 0:
		map.load_data(before, find_object)
		if blueprints != null:
			blueprints.release()
		if build_costs != null:
			build_costs.resume()
		return "It doesn't fit there." if misfits == clip.objects.size() else \
				"Some of the furniture doesn't fit there."
	if clip.is_structure():
		settle_ground(area)
	if blueprints != null:
		blueprints.release()
	if build_costs != null:
		# A paste pays for what it added; a move for its structure anew.
		build_costs.resume(maxi(build_costs.worth() - worth_before, 0) if _pasting else price)
	return ""


func _preview_carried() -> void:
	var at := _carry_at()
	var ok := _drop_problem(at).is_empty()
	var colour := ok_colour if ok else bad_colour
	var area := Rect2i(at, _carried.size)
	var height := _preview_height(area) if _carried.is_structure() else NAN
	_shapes.cells(_carried.cells_at(at), colour, height)
	for wall: Array in _carried.walls:
		_shapes.edge(BuildingMap.edge_between(wall[0] + at, wall[1] + at), colour, height)
	for entry: Array in _carried.objects:
		_shapes.object(entry[0], entry[2], entry[1] + Vector2(at), colour)


func _is_shortcut(event: InputEvent, keycode: Key) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and (key.ctrl_pressed or key.meta_pressed) \
			and not key.shift_pressed and key.physical_keycode == keycode

#endregion


## What a door in the wall under the mouse would mean, when the floors
## either side are at different heights.
func _door_status() -> String:
	if opening != BuildingMap.Wall.DOOR or _hover_slant() != NO_SLANT:
		return ""
	var edge := _hover_edge()
	if map.wall_at(edge) == BuildingMap.Wall.NONE:
		return ""
	var rise := map.door_rise(edge)
	if rise <= BuildingMap.MAX_STEP + BuildingMap.EPSILON:
		return ""
	if not Building.door_steps:
		return "The floors either side are %s m apart, too big a step for a door." % String.num(rise, 2)
	if rise > BuildingMap.DOOR_STEPS_MAX + BuildingMap.EPSILON:
		return "The floors either side are %s m apart, too far even for steps." % String.num(rise, 2)
	return "The floors either side are %s m apart, so the door gets steps." % String.num(rise, 2)


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
	# The ground round the building slopes gently to meet it, rather than
	# leaving a cliff or a bank at its edge.
	var pull := {} # Corner: [how strongly it is pulled, the height it is pulled to]
	for corner: Vector2i in heights:
		for dx in range(-GROUND_SKIRT, GROUND_SKIRT + 1):
			for dy in range(-GROUND_SKIRT, GROUND_SKIRT + 1):
				var near: Vector2i = corner + Vector2i(dx, dy)
				if heights.has(near) or not terrain.in_bounds(near) or _corner_built_on(near) \
						or not (map.owns(near) or map.owns(near - Vector2i.ONE)):
					continue
				var weight := 1.0 - float(maxi(absi(dx), absi(dy))) / (GROUND_SKIRT + 1)
				if not pull.has(near) or pull[near][0] < weight:
					pull[near] = [weight, heights[corner]]
	for corner: Vector2i in pull:
		heights[corner] = lerpf(terrain.corner_height(corner), pull[corner][1], pull[corner][0])
	terrain.set_corners(heights)


## Is any floor, on the ground or below it, built at a terrain corner?
func _corner_built_on(corner: Vector2i) -> bool:
	if building != null:
		return building.corner_in_use(corner)
	return map.corner_in_use(corner)


## The height new floor over this rectangle would go in at: the same as
## any floor already in or beside it, so rooms line up, or else the
## average height of the ground under it.
func build_height(rect: Rect2i) -> float:
	var near := map.floor_height_near(rect)
	if not is_nan(near):
		return near
	var start := _drag_start_cell if rect.has_point(_drag_start_cell) else rect.position
	# The average height of the ground it covers, so the ground is cut and
	# filled about evenly.
	var ground := 0.0
	if terrain != null:
		var cells := BuildingMap.cells_in(rect)
		for cell in cells:
			ground += terrain.cell_height(cell)
		ground = snappedf(ground / maxi(cells.size(), 1), 0.25)
	if _level() != 0:
		return building.storey_height(_level(), start, ground)
	return ground


## Moves the floor in a rectangle up or down, for split levels. Upstairs
## and in basements floors stay near their storey's height; on the ground
## they stay out of the water, and the ground is refitted underneath.
## Returns how many tiles moved.
func nudge_floors(rect: Rect2i, amount: float) -> int:
	if not Building.split_levels:
		return 0
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
	if not _dragging or not Building.split_levels:
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


func _can_place(position: Vector2, angle := NAN) -> bool:
	if is_nan(angle):
		angle = object_angle
	if object_def.sits == ObjectDef.Sits.SURFACE:
		return false
	if building != null:
		return building.can_place(_level(), object_def, position, angle)
	return map.can_place_at(object_def, position, angle)


## The surface and free spot under the mouse for something that goes on
## surfaces, as [PlacedObject, spot], or empty.
func _surface_target() -> Array:
	if object_def == null or not object_def.goes_on_surfaces():
		return []
	var surface := map.surface_at(_hover_point)
	if surface == null:
		return []
	var spot := map.free_spot_near(surface, _hover_point)
	return [surface, spot] if spot != -1 else []


## The look to give the next thing placed.
func _look_to_place() -> int:
	if object_look >= object_def.look_count():
		return randi() % object_def.look_count()
	return object_look


## How to turn the object being placed at a point: as chosen, or, for a
## chair beside a table or desk, facing the nearest side of it.
func _placing_angle(centre: Vector2) -> float:
	if not object_def.faces_surfaces or _free_rotating:
		return object_angle
	var best: BuildingMap.PlacedObject = null
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if placed.def.is_surface() and placed.rect.grow(0.75).has_point(centre) \
				and (best == null or placed.centre.distance_to(centre) < best.centre.distance_to(centre)):
			best = placed
	if best == null:
		return object_angle
	# Which side of it the chair is on, in its own frame.
	var local := (centre - best.centre).rotated(-best.angle)
	var half := best.def.size * 0.5
	var side := Vector2(signf(local.x), 0.0) if absf(local.x) - half.x > absf(local.y) - half.y \
			else Vector2(0.0, signf(local.y) if local.y != 0.0 else 1.0)
	return BuildingMap.facing(centre, centre - side.rotated(best.angle))


## The level being built on: 0 without a building.
func _level() -> int:
	return building.active if building != null else 0


## Tools that only make sense on the ground level.
func _ground_only(t: Tool) -> bool:
	return t == Tool.TERRAIN or t == Tool.PLANTS or t == Tool.PATH or (t == Tool.WALL
			and wall_mode == WallMode.BUILD and _perimeter_style())


## Whether the wall style is a perimeter fence, which only goes round the
## ground.
func _perimeter_style() -> bool:
	var def := map.wall_def(wall_style) if map != null else null
	return def != null and def.secure


## Does this edge already have the opening the tool would put in?
func _has_chosen_opening(edge: Vector3i) -> bool:
	if map.wall_at(edge) != opening:
		return false
	if opening == BuildingMap.Wall.DOOR:
		return map.door_kind_at(edge) == door_kind
	return opening != BuildingMap.Wall.WINDOW or map.window_kind(edge) == window_kind


const NO_DOOR := Vector3i(0, 0, -1)


## The door on a straight wall right by the mouse, or NO_DOOR.
func _hover_door() -> Vector3i:
	var edge := _hover_edge()
	if _edge_distance() < 0.3 and map.wall_at(edge) == BuildingMap.Wall.DOOR:
		return edge
	return NO_DOOR


## Plants go down to single placement; terrain keeps a real brush.
func smallest_brush() -> float:
	return 0.0 if tool == Tool.PLANTS else min_brush_radius


func _uses_brush() -> bool:
	return tool == Tool.TERRAIN or tool == Tool.PLANTS


func _apply_brush(delta: float) -> void:
	if _level() != 0:
		return
	match tool:
		Tool.TERRAIN:
			if terrain == null:
				return
			var boost := terrain_strength * 2.0
			var strength := sculpt_speed * boost * delta
			if terrain_brush == Terrain.Brush.FLATTEN or terrain_brush == Terrain.Brush.SMOOTH:
				strength = clampf(blend_speed * boost * delta, 0.0, 1.0)
			terrain.sculpt(terrain_brush, _hover_point, maxf(brush_radius, min_brush_radius), strength, _flatten_target,
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
			foliage.paint(plant_def, _hover_point, brush_radius, 3, _rng, can_grow, 1.0 / plant_density)


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
	if tool == Tool.OBJECT and object_def != null and object_def.goes_on_surfaces():
		var top: Variant = _surface_top_under_mouse()
		if top != null:
			_has_hover = true
			_hover_point = top


## Where the mouse meets the top of a table, desk or counter, in tiles, or
## null: things that go on surfaces are placed by pointing at the top, not
## at the floor under it.
func _surface_top_under_mouse() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null or map == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := grid.to_local(camera.project_ray_origin(mouse))
	var direction := grid.global_basis.inverse() * camera.project_ray_normal(mouse)
	var best: Variant = null
	var nearest := INF
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if not placed.def.is_surface() or placed.on_surface():
			continue
		var top := map.floor_height(Vector2i(placed.centre.floor())) + placed.def.height
		var hit: Variant = Plane(Vector3.UP, top).intersects_ray(origin, direction)
		if hit == null:
			continue
		var point := Vector2(hit.x, hit.z) / grid.cell_size
		if placed.rect.has_point(point) and Geometry2D.is_point_in_polygon(point, placed.polygon()) \
				and origin.distance_to(hit) < nearest:
			nearest = origin.distance_to(hit)
			best = point
	return best


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


## The wall sides a click with the paint mode would paint, as [wall, side]
## pairs (see BuildingMap.paint_side): the side under the mouse, or with
## Shift every side facing into the room there.
func planned_paint() -> Array:
	if Input.is_action_pressed("build_whole_room"):
		return map.sides_facing(_hover_point, WHOLE_ROOM_LIMIT)
	var hit := _wall_side_under_mouse()
	return [] if hit.is_empty() else [hit]


func _paint_walls() -> void:
	map.paint_sides(planned_paint(), &"" if _erasing() else wall_style)


## The wall side the mouse points at, as [wall, side], or empty. Walls stand
## up, so the mouse is followed up to the face it is over (the side facing
## the camera) rather than down to the ground behind it. Over the floor it
## takes the nearest wall on the side the mouse is.
func _wall_side_under_mouse() -> Array:
	var cs := grid.cell_size
	var camera := camera_rig.camera if camera_rig != null else null
	if camera != null:
		var mouse := get_viewport().get_mouse_position()
		var to_grid := grid.global_transform.affine_inverse()
		var origin := to_grid * camera.project_ray_origin(mouse)
		var direction := (to_grid.basis * camera.project_ray_normal(mouse)).normalized()
		var eye := Vector2(origin.x, origin.z) / cs
		var best: Array = []
		var nearest := INF
		var area := Rect2i(_hover_cell() - Vector2i(3, 3), Vector2i(7, 7))
		var candidates: Array = []
		for edge in BuildingMap.rect_edges(area):
			if map.wall_at(edge) != BuildingMap.Wall.NONE:
				candidates.append(edge)
		for cell in BuildingMap.cells_in(area):
			for key: Vector4i in map.slants_through(cell):
				if not candidates.has(key):
					candidates.append(key)
		for wall: Variant in candidates:
			var def := map.wall_def(map.style_of(wall))
			if def != null and def.see_through:
				continue
			var ends := BuildingMap.wall_ends(wall)
			var flat := ends[1] - ends[0]
			var normal := Vector3(-flat.y, 0.0, flat.x).normalized()
			var facing := direction.dot(normal)
			if absf(facing) < 0.001:
				continue
			var distance := (Vector3(ends[0].x, 0.0, ends[0].y) * cs - origin).dot(normal) / facing
			if distance <= 0.0 or distance >= nearest:
				continue
			var hit := origin + direction * distance
			var point := Vector2(hit.x, hit.z) / cs
			var t := (point - ends[0]).dot(flat) / flat.length_squared()
			var ground := _ground_at(ends[0].lerp(ends[1], clampf(t, 0.0, 1.0)))
			var height := def.height if def != null else 1.5
			if view != null and view.is_cut(ends[0], ends[1]):
				height = minf(height, view.low_wall_height)
			if t < 0.0 or t > 1.0 or hit.y < ground - 0.05 or hit.y > ground + height + 0.05:
				continue
			nearest = distance
			best = [wall, BuildingMap.wall_side(wall, eye)]
		if not best.is_empty():
			return best
	var slant := _hover_slant()
	if slant != NO_SLANT:
		return [slant, BuildingMap.wall_side(slant, _hover_point)]
	var edge := _hover_edge()
	if map.wall_at(edge) != BuildingMap.Wall.NONE and _edge_distance() < 0.35:
		return [edge, BuildingMap.wall_side(edge, _hover_point)]
	return []


func _has_chosen_slant_opening(key: Vector4i) -> bool:
	if map.slant_at(key) != opening:
		return false
	return opening != BuildingMap.Wall.WINDOW or map.slant_window_kind(key) == window_kind

#endregion

#region Preview

func _draw_preview() -> void:
	_preview_mesh.clear_surfaces()
	_shapes.clear()
	_shapes.map = map
	_shapes.cell_size = grid.cell_size
	_shapes.wall_height = view.low_wall_height if view != null and view.walls_low else preview_wall_height
	_draw_path_preview()
	if map == null or tool == Tool.NONE or not _has_hover:
		return
	if _ground_only(tool) and _level() != 0:
		return
	match tool:
		Tool.ROOM:
			var rect := _drag_rect()
			var dry := can_build_floor(rect)
			_shapes.cells(BuildingMap.cells_in(rect), ok_colour if dry else bad_colour,
					_preview_height(rect))
			for edge in BuildingMap.rect_perimeter(rect):
				_shapes.edge(edge, ok_colour if dry and map.can_build_wall(edge) else bad_colour,
						_preview_height(rect))
		Tool.FLOOR when floor_mode == FloorMode.STAIRS:
			var planned := stair_tool.plan(_hover_cell())
			if _erasing():
				var flight := map.stairs_at(_hover_cell())
				if flight != null:
					_shapes.cells(flight.cells, demolish_colour)
			else:
				_shapes.stairs(Staircase.create(planned[0], planned[1], stair_tool.rounded), ok_colour if _stairs_fit(planned[0]) else bad_colour)
		Tool.FLOOR when floor_mode == FloorMode.RAMP:
			var ramp := planned_ramp()
			_shapes.cells(BuildingMap.cells_in(_drag_rect()), ok_colour if ramp != null else bad_colour)
		Tool.FLOOR when floor_mode != FloorMode.LAY:
			var cells: Array[Vector2i] = []
			for cell in BuildingMap.cells_in(_drag_rect()):
				if map.has_floor(cell):
					cells.append(cell)
			_shapes.cells(cells, ok_colour)
		Tool.FLOOR:
			var chosen := planned_floor()
			if chosen.is_empty():
				_shapes.cells([_hover_cell()], bad_colour)
			else:
				var height := NAN if _erasing() else _preview_height(_pieces_bounds(chosen))
				_shapes.pieces(chosen, demolish_colour if _erasing() else ok_colour, height)
		Tool.TERRAIN when _buying():
			_preview_land()
		Tool.TERRAIN when water_mode != WaterMode.NONE:
			_preview_water()
		Tool.TERRAIN, Tool.PLANTS:
			var colour := demolish_colour if tool == Tool.PLANTS and _erasing() else ok_colour
			var radius := brush_radius if tool == Tool.PLANTS else maxf(brush_radius, min_brush_radius)
			_shapes.ring(_hover_point, maxf(radius, 0.35), colour)
		Tool.DEMOLISH:
			var placed := map.object_at(_hover_point)
			var flight := map.stairs_at(_hover_cell())
			if _dragging:
				_shapes.cells(BuildingMap.cells_in(_drag_rect()), demolish_colour)
			elif placed != null:
				_shapes.rect(placed.rect, demolish_colour, placed.def.height + 0.05)
			elif flight != null:
				_shapes.cells(flight.cells, demolish_colour, NAN, Building.STOREY * 0.5)
			elif _hover_slant() != NO_SLANT:
				_shapes.slant(_hover_slant(), demolish_colour)
			elif map.wall_at(_hover_edge()) != BuildingMap.Wall.NONE and _edge_distance() < 0.25:
				_shapes.edge(_hover_edge(), demolish_colour)
			else:
				_shapes.cells(BuildingMap.cells_in(_drag_rect()), demolish_colour)
		Tool.WALL when wall_mode == WallMode.PAINT:
			for entry: Array in planned_paint():
				var ok := _erasing() or map.can_paint(entry[0], wall_style)
				_shapes.wall_side(entry[0], entry[1],
						(demolish_colour if _erasing() else ok_colour) if ok else bad_colour)
		Tool.WALL:
			if _dragging:
				for edge in BuildingMap.edges_on_line(_drag_start_corner, _wall_end_corner()):
					if _erasing():
						_shapes.edge(edge, demolish_colour)
					else:
						_shapes.edge(edge, ok_colour if map.can_build_wall(edge) else bad_colour)
				for key in BuildingMap.slants_on_line(_drag_start_corner, _wall_end_corner()):
					if _erasing():
						_shapes.slant(key, demolish_colour)
					else:
						_shapes.slant(key, ok_colour if map.can_build_slant(key) else bad_colour)
			else:
				_shapes.corner(_hover_corner(), ok_colour)
		Tool.OPENING when _hover_slant() != NO_SLANT:
			var key := _hover_slant()
			var ok := not (opening == BuildingMap.Wall.WINDOW and map.is_outdoor_slant(key))
			_shapes.slant(key, ok_colour if ok else bad_colour)
		Tool.OPENING:
			var edge := _hover_edge()
			var ok := map.wall_at(edge) != BuildingMap.Wall.NONE or map.planned_walls.has(edge)
			if opening == BuildingMap.Wall.WINDOW and map.is_outdoor_wall(edge):
				ok = false
			if opening == BuildingMap.Wall.DOOR and not map.can_put_door(edge):
				ok = false
			_shapes.edge(edge, ok_colour if ok else bad_colour)
		Tool.OBJECT:
			if object_def != null:
				var target := _surface_target()
				if not target.is_empty():
					var surface: BuildingMap.PlacedObject = target[0]
					_shapes.object(object_def, surface.angle + snappedf(object_angle, PI * 0.5),
							map.spot_point(surface, target[1]), ok_colour, surface.def.height)
				else:
					var centre := _object_centre()
					var angle := _placing_angle(centre)
					var ok := _can_place(centre, angle)
					_shapes.object(object_def, angle, centre, ok_colour if ok else bad_colour)
		Tool.MOVE when _carried != null:
			_preview_carried()
		Tool.MOVE:
			var placed := map.object_at(_hover_point)
			var room := map.room_at_point(_hover_point)
			if _dragging:
				_shapes.cells(BuildingMap.cells_in(_drag_rect()), ok_colour)
			elif placed != null:
				_shapes.rect(placed.rect, ok_colour, placed.def.height + 0.05)
			elif room != null:
				_shapes.cells(room.cells, ok_colour)
		Tool.ROOM_TYPE:
			var room := map.room_at_point(_hover_point)
			if room != null:
				var colour := room_type.colour if room_type != null else Color.WHITE
				colour.a = 0.45
				_shapes.cells(room.cells, colour)
		Tool.ZONE:
			if _hover_door() != NO_DOOR:
				_shapes.edge(_hover_door(), ok_colour)
			else:
				var room := map.room_at_point(_hover_point)
				if room != null:
					var colour := zone.colour if zone != null else Color.WHITE
					colour.a = 0.45
					_shapes.cells(room.cells, colour)
	_shapes.draw(_preview_mesh, _preview_material)


## Would a new building here stay out of the water?
func _is_dry(rect: Rect2i) -> bool:
	if terrain == null or _level() != 0:
		return true
	var height := build_height(rect)
	for cell in BuildingMap.cells_in(rect):
		if terrain.water_surface(Vector2(cell) + Vector2(0.5, 0.5)) > height:
			return false
	return true


func _buying() -> bool:
	return tool == Tool.TERRAIN and buying_land and land_plots != null


## The plots a click or drag picks: those for sale (or, selling, yours)
## under it.
## What the drag or hover under the mouse would build and cost, for a label
## at the cursor: [text, affordable], or [] when there's nothing to say.
func readout() -> Array:
	if not _has_hover or map == null:
		return []
	if tool == Tool.TERRAIN and water != null and water.is_sea(_hover_cell()):
		return [water.tide_words(), true]
	match tool:
		Tool.ROOM when _dragging:
			var rect := _drag_rect()
			return _priced("%d × %d" % [rect.size.x, rect.size.y], _room_cost(rect))
		Tool.FLOOR when _dragging and floor_mode == FloorMode.LAY:
			var rect := _drag_rect()
			if _erasing():
				return ["%d × %d" % [rect.size.x, rect.size.y], true]
			var cells := {}
			for piece in planned_floor():
				if map.floors.get(piece.cell, &"") != floor_style:
					cells[piece.cell] = true
			var def := map.floor_def(floor_style)
			return _priced("%d × %d" % [rect.size.x, rect.size.y], cells.size() * (def.price if def != null else 0))
		Tool.WALL when _dragging and wall_mode == WallMode.BUILD:
			var end := _wall_end_corner()
			var length := Vector2(_drag_start_corner).distance_to(Vector2(end))
			var words := "%s m" % (str(roundi(length)) if is_equal_approx(length, roundf(length)) else "%.1f" % length)
			if _erasing():
				return [words, true]
			var def := map.wall_def(wall_style)
			var cost := 0
			for edge in BuildingMap.edges_on_line(_drag_start_corner, end):
				if map.wall_at(edge) == BuildingMap.Wall.NONE:
					cost += def.price if def != null else 0
			for key in BuildingMap.slants_on_line(_drag_start_corner, end):
				if map.slant_at(key) == BuildingMap.Wall.NONE:
					cost += roundi((def.price if def != null else 0) * Vector2(key.x, key.y).distance_to(Vector2(key.z, key.w)))
			return _priced(words, cost)
		Tool.DEMOLISH when _dragging:
			var rect := _drag_rect()
			return ["%d × %d" % [rect.size.x, rect.size.y], true]
		Tool.OBJECT when object_def != null and object_def.price > 0:
			return _priced(object_def.display_name, object_def.price)
		Tool.MOVE when _carried != null:
			var words := "%d × %d" % [_carried.size.x, _carried.size.y]
			var problem := _drop_problem(_carry_at())
			if not problem.is_empty():
				return [problem, false]
			return _priced(words, _drop_price())
		Tool.MOVE when _dragging:
			var rect := _drag_rect()
			return ["%d × %d" % [rect.size.x, rect.size.y], true]
		Tool.ROOM_TYPE when room_type != null:
			var room := map.room_at_point(_hover_point)
			if room == null:
				return []
			var problems := room_type.problems(room, map)
			if problems.is_empty():
				return ["Ready to be a %s" % room_type.display_name.to_lower(), true]
			return ["%s:\n%s" % [room_type.display_name, "\n".join(problems)], false]
	return []


## A room's floor and its new walls, at the chosen styles.
func _room_cost(rect: Rect2i) -> int:
	var floor_def := map.floor_def(floor_style)
	var wall_def := map.wall_def(wall_style)
	var cost := 0
	for cell in BuildingMap.cells_in(rect):
		if map.owns(cell) and map.floors.get(cell, &"") != floor_style:
			cost += floor_def.price if floor_def != null else 0
	for edge in BuildingMap.rect_perimeter(rect):
		if map.wall_at(edge) == BuildingMap.Wall.NONE:
			cost += wall_def.price if wall_def != null else 0
	return cost


func _priced(words: String, cost: int) -> Array:
	if cost <= 0:
		return [words, true]
	var ok: bool = not balance.is_valid() or balance.call() >= cost
	return ["%s · %s" % [words, Ledger.text(cost)], ok]


## Picks up the style of whatever is under the mouse (an object and its
## look, a wall, a floor, a path or a plant) and switches to its tool.
func eyedrop() -> bool:
	if not _has_hover or map == null:
		return false
	var placed := map.object_at(_hover_point)
	if placed != null:
		object_def = placed.def
		object_look = placed.look
		object_angle = placed.angle
		tool = Tool.OBJECT
		return true
	var edge := _hover_edge()
	if map.wall_at(edge) != BuildingMap.Wall.NONE and _edge_distance() < 0.25:
		wall_style = map.wall_style(edge)
		wall_mode = WallMode.BUILD
		tool = Tool.WALL
		return true
	if foliage != null and _level() == 0:
		for plant in foliage.plants:
			if plant.position.distance_to(_hover_point) < 0.6:
				plant_def = plant.def
				tool = Tool.PLANTS
				return true
	if paths != null and _level() == 0:
		var near := paths.closest(_hover_point)
		if not near.is_empty() and near[2] < 0.6:
			path_tool.style = (near[0] as PathNetwork.Segment).style
			tool = Tool.PATH
			return true
	var cell := _hover_cell()
	if map.has_floor(cell):
		floor_style = map.floors[cell]
		floor_mode = FloorMode.LAY
		tool = Tool.FLOOR
		return true
	return false


func _land_choice() -> Array[Rect2i]:
	var end := _hover_cell()
	var start := _drag_start_cell if _dragging else end
	var key := [start, land_plots.plot_at(end), selling_land, land_plots.building.land.size(), _land_money()]
	if key == _land_key and not _land_cache.is_empty():
		return _land_cache[0]
	var under := land_plots.plots_between(start, end)
	var chosen: Array[Rect2i] = []
	if selling_land:
		chosen.assign(under.filter(land_plots.is_owned))
	else:
		chosen = land_plots.buyable(under)
	var outlined: Array[Rect2i] = []
	if selling_land:
		outlined = land_plots.owned()
	else:
		outlined = land_plots.plots()
	var ok := land_plots.can_sell_all(chosen) if selling_land else land_plots.can_afford_all(chosen, flatten_land)
	_land_key = key
	_land_cache = [chosen, outlined, ok]
	return chosen


func _land_money() -> int:
	return land_plots.ledger.balance if land_plots.ledger != null else 0


## Outlines every plot for sale (or, selling, yours), filling those a click
## or drag would take: green if it can go ahead, red if not.
func _preview_land() -> void:
	if not _has_hover:
		return
	var chosen := _land_choice()
	# Bought and waiting on planning permission: a soft blue wash.
	for plots: Array in land_plots.pending.values():
		for plot: Rect2i in plots:
			_shapes.cells(BuildingMap.cells_in(plot), pending_colour, NAN, 0.03)
	for plot: Rect2i in _land_cache[1]:
		if chosen.has(plot):
			continue
		for cell in _plot_edge(plot):
			_shapes.cells([cell], land_colour, NAN, 0.03)
	var colour := ok_colour if _land_cache[2] else bad_colour
	for plot in chosen:
		_shapes.cells(BuildingMap.cells_in(plot), colour)


func _plot_edge(plot: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in BuildingMap.cells_in(plot):
		if cell.x == plot.position.x or cell.y == plot.position.y \
				or cell.x == plot.end.x - 1 or cell.y == plot.end.y - 1:
			out.append(cell)
	return out


## What a click or drag would buy or sell, and for how much.
func _land_status() -> String:
	var chosen := _land_choice()
	var count := chosen.size()
	var plots_text := "%d plot%s" % [count, "" if count == 1 else "s"]
	if selling_land:
		if count == 0:
			return "Point at one of your plots."
		var back := 0
		for plot in chosen:
			back += land_plots.sell_price(plot)
		if not land_plots.can_sell_all(chosen):
			return "Only empty plots sell back, and your land must stay in one piece."
		return "Sell %s back for %s." % [plots_text, Ledger.text(back)]
	if count == 0:
		return "Point at a plot next to your land."
	var text := "%s: %s" % [plots_text, Ledger.text(land_plots.price_of(chosen))]
	if flatten_land:
		var fee := 0
		for plot in chosen:
			fee += land_plots.flatten_price(plot)
		text += ", plus %s to flatten" % Ledger.text(fee)
	if not land_plots.can_afford_all(chosen, flatten_land):
		text += ". You can't afford it yet."
	return text


## Adds a point to the river being drawn; a click on the last point again
## finishes it. Returns the river once made.
func press_river(point: Vector2) -> River:
	if _river_points.size() >= 2 and point.distance_to(_river_points[_river_points.size() - 1]) < 0.75:
		var river := water.add_river(_river_points, river_width)
		_river_points.clear()
		return river
	if _river_points.is_empty() or point.distance_to(_river_points[_river_points.size() - 1]) >= 0.75:
		_river_points.append(point)
	return null


## Shows the water a click would add (or a red tile if there is no hollow),
## or the body a click would drain.
func _preview_water() -> void:
	if water == null:
		return
	var cell := _hover_cell()
	if water_mode == WaterMode.RIVER:
		var drawn := _river_points.duplicate()
		drawn.append(_hover_point)
		if drawn.size() < 2:
			_shapes.cells([cell], ok_colour)
			return
		var river := River.new()
		river.points = drawn
		river.width = river_width
		river.line = River.sample(drawn)
		river.beds.resize(river.line.size())
		for i in river.line.size():
			river.beds[i] = (terrain.height_at(river.line[i]) if terrain != null else 0.0) - river.depth
		_shapes.cells(river.cells().keys(), ok_colour)
		return
	var existing := water.body_at(cell)
	if water_mode == WaterMode.REMOVE:
		if existing != null:
			_shapes.cells(existing.cells.keys(), demolish_colour, existing.level)
		else:
			_shapes.cells([cell], bad_colour)
		return
	if existing != null:
		_shapes.cells([cell], bad_colour, existing.level)
		return
	# Working a basin out can take a while on open ground, so only redo it
	# when the tile under the mouse or the ground changes.
	if cell != _basin_cell or _basin_dirty:
		_basin_cell = cell
		_basin_dirty = false
		_basin = water.find_basin(cell)
	if _basin != null:
		_shapes.cells(_basin.cells.keys(), ok_colour, _basin.level)
	else:
		_shapes.cells([cell], bad_colour)


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


#endregion
