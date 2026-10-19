class_name BuildController
extends Node3D
## The build tools: turns mouse input into changes to a BuildingMap, and
## shows a see-through preview of what will happen before you commit.
##
## Drag tools (room, floor, wall, demolish) act when you let go of the left
## mouse button. Click tools (door, object, room type) act on click.

signal tool_changed(tool: Tool)

enum Tool { NONE, ROOM, FLOOR, WALL, DOOR, OBJECT, ROOM_TYPE, DEMOLISH }

const HINTS := {
	Tool.NONE: "",
	Tool.ROOM: "Drag to build a walled room.",
	Tool.FLOOR: "Drag to lay or restyle floor. Hold Ctrl to remove floor.",
	Tool.WALL: "Drag between corners to build or restyle walls. Hold Ctrl to remove them.",
	Tool.DOOR: "Click a wall to make it a door. Click a door to make it a wall again.",
	Tool.OBJECT: "Click to place. R rotates. Hold Alt to place freely.",
	Tool.ROOM_TYPE: "Click a room to mark it.",
	Tool.DEMOLISH: "Click an object or wall to remove it, or drag to clear an area.",
}

@export var grid: BuildGrid
@export var camera_rig: CameraRig
@export var view: BuildingView

@export_group("Preview colours")
@export var ok_colour := Color(0.45, 0.95, 0.55, 0.45)
@export var bad_colour := Color(1.0, 0.4, 0.4, 0.45)
@export var demolish_colour := Color(1.0, 0.3, 0.25, 0.4)

var map: BuildingMap
var tool := Tool.NONE:
	set(value):
		tool = value
		_dragging = false
		tool_changed.emit(tool)
var object_def: ObjectDef
## Styles used by the room, floor and wall tools.
var floor_style: StringName = BuildingMap.DEFAULT_FLOOR
var wall_style: StringName = BuildingMap.DEFAULT_WALL
var object_rotation := 0
## The room type the room type tool applies. Null clears a room's type.
var room_type: RoomTypeDef

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


func _ready() -> void:
	var preview := MeshInstance3D.new()
	preview.mesh = _preview_mesh
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)


func _process(_delta: float) -> void:
	_update_hover()
	_draw_preview()


func _input(event: InputEvent) -> void:
	# Finish a drag even if the button is let go over the toolbar.
	if _dragging and event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_on_release()


func _unhandled_input(event: InputEvent) -> void:
	if map == null:
		return
	if event.is_action_pressed("build_cancel"):
		if _dragging:
			_dragging = false
		else:
			tool = Tool.NONE
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_rotate") and tool == Tool.OBJECT:
		object_rotation = (object_rotation + 1) % 4
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_toggle_walls"):
		view.walls_low = not view.walls_low
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and tool != Tool.NONE and _has_hover:
			_on_press()
			get_viewport().set_input_as_handled()


func _on_press() -> void:
	match tool:
		Tool.ROOM, Tool.FLOOR, Tool.DEMOLISH:
			_dragging = true
			_drag_start_cell = _hover_cell()
		Tool.WALL:
			_dragging = true
			_drag_start_corner = _hover_corner()
		Tool.DOOR:
			var edge := _hover_edge()
			map.set_door(edge, map.wall_at(edge) == BuildingMap.Wall.WALL)
		Tool.OBJECT:
			if object_def != null:
				map.place_object(object_def, _object_position(), object_rotation)
		Tool.ROOM_TYPE:
			var room := map.room_at(_hover_cell())
			if room != null:
				map.set_room_type(room, room_type.id if room_type != null else &"")


func _on_release() -> void:
	if not _dragging:
		return
	var rect := _drag_rect()
	_dragging = false
	var erase := _erasing()
	match tool:
		Tool.ROOM:
			map.build_room(rect, floor_style, wall_style)
		Tool.FLOOR:
			if erase:
				map.clear_floor(rect)
			else:
				map.fill_floor(rect, floor_style)
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
	if map == null or tool == Tool.NONE or not _has_hover:
		return
	match tool:
		Tool.ROOM:
			var rect := _drag_rect()
			_preview_cells(BuildingMap.cells_in(rect), ok_colour)
			for edge in BuildingMap.rect_perimeter(rect):
				_preview_edge(edge, ok_colour if map.can_build_wall(edge) else bad_colour)
		Tool.FLOOR:
			_preview_cells(BuildingMap.cells_in(_drag_rect()),
					demolish_colour if _erasing() else ok_colour)
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
		Tool.DOOR:
			var edge := _hover_edge()
			_preview_edge(edge, ok_colour if map.wall_at(edge) != BuildingMap.Wall.NONE else bad_colour)
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


func _preview_cells(cells: Array[Vector2i], colour: Color, height := 0.06) -> void:
	var cs := grid.cell_size
	for cell in cells:
		var centre := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5) * cs
		_preview_boxes.append([centre + Vector3.UP * height * 0.5,
				Vector3(cs * 0.48, height * 0.5, cs * 0.48), colour])


func _preview_rect(rect: Rect2, colour: Color, height: float) -> void:
	var cs := grid.cell_size
	var centre := rect.get_center() * cs
	_preview_boxes.append([Vector3(centre.x, height * 0.5, centre.y),
			Vector3(rect.size.x * cs * 0.5, height * 0.5, rect.size.y * cs * 0.5), colour])


func _preview_edge(edge: Vector3i, colour: Color) -> void:
	if not map.edge_in_bounds(edge):
		return
	var cs := grid.cell_size
	var along := Vector3.RIGHT if edge.z == BuildingMap.EDGE_X else Vector3.BACK
	var across := Vector3.BACK if edge.z == BuildingMap.EDGE_X else Vector3.RIGHT
	var height := view.low_wall_height if view.walls_low else view.wall_height
	var centre := Vector3(edge.x, 0.0, edge.y) * cs + along * cs * 0.5 + Vector3.UP * height * 0.5
	_preview_boxes.append([centre, along * cs * 0.5 + across * 0.1 + Vector3.UP * height * 0.5,
			colour])


func _preview_corner(corner: Vector2i, colour: Color) -> void:
	var cs := grid.cell_size
	_preview_boxes.append([Vector3(corner.x * cs, 0.5, corner.y * cs), Vector3(0.12, 0.5, 0.12),
			colour])

#endregion
