class_name DebugOverlay
extends Node3D
## A developer view, toggled with F3. Tints every room by whether it is
## indoors, outdoors or open, labels each one, and shows a panel with
## everything known about the tile under the mouse.
##
## Colour is only a hint: the labels and the panel say the same in words.

@export var cursor: GridCursor
@export var terrain: Terrain
@export var foliage: FoliageLayer
@export var room_types: Array[RoomTypeDef] = []

@export_group("Colours")
@export var indoor_colour := Color(0.3, 0.55, 1.0, 0.35)
@export var outdoor_colour := Color(0.35, 0.9, 0.4, 0.35)
@export var open_colour := Color(1.0, 0.65, 0.2, 0.4)

var map: BuildingMap:
	set(value):
		if map != null:
			map.changed.disconnect(_mark_dirty)
		map = value
		if map != null:
			map.changed.connect(_mark_dirty)
		_mark_dirty()

var _mesh := ImmediateMesh.new()
var _material := MeshShapes.vertex_colour_material(true)
var _labels := Node3D.new()
var _layer := CanvasLayer.new()
var _panel := PanelContainer.new()
var _text := Label.new()
var _dirty := true


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	add_child(_labels)

	_layer.layer = 10
	add_child(_layer)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -430.0
	_panel.offset_right = -12.0
	_panel.offset_top = 12.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.82)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_text.add_theme_font_size_override("font_size", 14)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_text)
	_layer.add_child(_panel)

	if terrain != null:
		terrain.changed.connect(_mark_dirty)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible or map == null:
		return
	if _dirty:
		_dirty = false
		_draw_rooms()
	_text.text = describe(cursor.hovered_cell if cursor != null else GridCursor.NO_CELL)


func _mark_dirty() -> void:
	_dirty = true


func _on_visibility_changed() -> void:
	_layer.visible = visible
	_dirty = true


#region Text

## Everything worth knowing about a tile, plus totals for the whole map.
func describe(cell: Vector2i) -> String:
	var lines: PackedStringArray = ["DEBUG VIEW (F3 to hide)", ""]
	if cell == GridCursor.NO_CELL:
		lines.append("Point at a tile for details.")
	else:
		lines.append_array(_describe_cell(cell))
	lines.append("")
	lines.append_array(_describe_totals())
	lines.append("")
	lines.append("Tints: blue = indoors, green = enclosed outdoors, amber = not enclosed")
	return "\n".join(lines)


func _describe_cell(cell: Vector2i) -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("Tile %d, %d    %s" % [cell.x, cell.y, "owned" if map.owns(cell) else "not owned"])
	if terrain != null:
		var corners: Array[float] = []
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i.ONE]:
			corners.append(terrain.corner_height(cell + offset))
		var centre := Vector2(cell) + Vector2(0.5, 0.5)
		lines.append("Ground: %.2f m (corners %.2f to %.2f)" % [terrain.cell_height(cell),
				corners.min(), corners.max()])
		lines.append("Sculpting: %s" % ("locked by a building" if terrain.is_locked.call(cell)
				else "free"))
		var body := terrain.water.body_at(cell) if terrain.water != null else null
		if body != null:
			lines.append("Water: pond of %d tiles, surface at %.2f m, %.2f m deep here" % [
					body.cells.size(), body.level, body.level - terrain.cell_height(cell)])
		elif terrain.has_sea and terrain.is_underwater(centre):
			lines.append("Water: sea, surface at %.2f m" % terrain.sea_level)
		else:
			lines.append("Water: none")
	var floor_id: StringName = map.floors.get(cell, &"")
	if map.holes.has(cell):
		lines.append("Floor: open to stairs below")
	elif floor_id.is_empty():
		lines.append("Floor: none")
	else:
		var def := map.floor_def(floor_id)
		lines.append("Floor: %s%s at %.2f m" % [def.display_name if def != null else floor_id,
				" (outdoor style)" if def != null and def.outdoor else "", map.floor_height(cell)])

	var room := map.room_at(cell)
	if room != null:
		var type := _room_type(room.type)
		lines.append("Room %d: %s, %d tiles" % [room.id,
				type.display_name if type != null else "no type", room.cells.size()])
		lines.append("  Enclosed: %s    %s" % ["yes" if room.enclosed else "no",
				"Indoors" if room.indoor else "Outdoors"])
		if type != null:
			var problems := type.problems(room, map)
			lines.append("  Problems: %s" % (", ".join(problems) if not problems.is_empty() else "none"))
		var names: PackedStringArray = []
		for placed in map.objects_in_room(room):
			names.append(placed.def.display_name)
		lines.append("  Objects: %s" % (", ".join(names) if not names.is_empty() else "none"))
	var under := map.object_at(Vector2(cell) + Vector2(0.5, 0.5))
	if under != null and under.def.connects != ObjectDef.Connects.NONE:
		lines.append("%s: goes up a level%s" % [under.def.display_name,
				", staff only" if under.def.staff_only else ""])

	lines.append("Edges:")
	for side: Array in [["North (-Z)", Vector2i.UP], ["South (+Z)", Vector2i.DOWN],
			["West (-X)", Vector2i.LEFT], ["East (+X)", Vector2i.RIGHT]]:
		var next: Vector2i = cell + side[1]
		var edge := BuildingMap.edge_between(cell, next)
		lines.append("  %s: %s, %s" % [side[0], _describe_edge(edge),
				"walkable" if map.can_walk_between(cell, next) else "blocked"])

	if foliage != null:
		var near := 0
		for plant in foliage.plants:
			if Rect2(Vector2(cell), Vector2.ONE).grow(0.5).has_point(plant.position):
				near += 1
		lines.append("Plants on or next to this tile: %d" % near)
	return lines


func _describe_edge(edge: Vector3i) -> String:
	var kind := map.wall_at(edge)
	if kind == BuildingMap.Wall.NONE:
		return "open"
	var def := map.wall_def(map.wall_style(edge))
	var style := def.display_name if def != null else String(map.wall_style(edge))
	match kind:
		BuildingMap.Wall.DOOR:
			return "door in %s" % style
		BuildingMap.Wall.WINDOW:
			return "%s window in %s" % [map.window_kind(edge), style]
	return "%s wall%s" % [style, " (outdoor)" if def != null and def.outdoor else ""]


func _describe_totals() -> PackedStringArray:
	var indoor := 0
	var outdoor := 0
	var open := 0
	for room in map.rooms():
		if room.indoor:
			indoor += 1
		elif room.enclosed:
			outdoor += 1
		else:
			open += 1
	var counts := {}
	for kind: int in map.walls.values():
		counts[kind] = counts.get(kind, 0) + 1
	var lines: PackedStringArray = []
	lines.append("Rooms: %d indoors, %d enclosed outdoors, %d not enclosed" % [indoor, outdoor, open])
	lines.append("Floor tiles: %d    Walls: %d    Doors: %d    Windows: %d" % [map.floors.size(),
			counts.get(BuildingMap.Wall.WALL, 0), counts.get(BuildingMap.Wall.DOOR, 0),
			counts.get(BuildingMap.Wall.WINDOW, 0)])
	lines.append("Objects: %d    Plants: %d    Ponds and lakes: %d" % [map.objects.size(),
			foliage.plants.size() if foliage != null else 0,
			terrain.water.bodies.size() if terrain != null and terrain.water != null else 0])
	var bounds := map.land_bounds()
	lines.append("Land: %d x %d from %d, %d    FPS: %d" % [bounds.size.x, bounds.size.y,
			bounds.position.x, bounds.position.y, Engine.get_frames_per_second()])
	return lines


func _room_type(id: StringName) -> RoomTypeDef:
	for def in room_types:
		if def.id == id:
			return def
	return null

#endregion

#region Drawing

func _draw_rooms() -> void:
	_mesh.clear_surfaces()
	for child in _labels.get_children():
		child.queue_free()
	var rooms := map.rooms()
	if rooms.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for room in rooms:
		var colour := indoor_colour if room.indoor else (outdoor_colour if room.enclosed else open_colour)
		for cell in room.cells:
			var ground := terrain.cell_height(cell) if terrain != null else 0.0
			MeshShapes.add_box_immediate(_mesh, Vector3(cell.x + 0.5, ground + 0.08, cell.y + 0.5),
					Vector3(0.46, 0.02, 0.46), colour)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 40
		label.pixel_size = 0.008
		label.outline_size = 8
		label.modulate = Color.WHITE
		label.text = "Room %d: %s" % [room.id, "indoors" if room.indoor
				else ("outdoors, enclosed" if room.enclosed else "not enclosed")]
		var centre := room.centre()
		var ground := terrain.height_at(centre) if terrain != null else 0.0
		# Kept low so it sits under the room type label rather than on top of it.
		label.position = Vector3(centre.x, ground + 0.15, centre.y)
		_labels.add_child(label)
	_mesh.surface_end()

#endregion
