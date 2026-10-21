class_name TrialMarks
extends Node3D
## Rooms in a research trial's wing on the level in view get a soft dashed
## outline, and the wing one "Trial: Earned privileges, day 2 of 3" label.

const COLOUR := Color(0.85, 0.37, 0.13, 0.7)
## Dash length along each cell edge, out of one cell.
const DASH := 0.5
const THICKNESS := 0.06

@export var cell_size := 1.0
@export var lift := 0.06

var research: Research:
	set(value):
		research = value
		research.changed.connect(_redraw)
var building: Building:
	set(value):
		building = value
		building.changed.connect(_redraw)
		building.active_changed.connect(func(_level: int) -> void: _redraw())
var clock: GameClock:
	set(value):
		clock = value
		clock.day_changed.connect(func(_day: int) -> void: _redraw())

var _mesh := ImmediateMesh.new()
var _labels := Node3D.new()
var _label_font := CosyTheme.bold_font()


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = MeshShapes.vertex_colour_material(true)
	add_child(instance)
	add_child(_labels)
	_redraw()


## The trial rooms on a level, as [Room, label] pairs.
func marks(level: int) -> Array:
	var out: Array = []
	if research == null or building == null:
		return out
	var map := building.levels.get(level) as BuildingMap
	if map == null:
		return out
	for id: StringName in research.trials:
		var trial: Dictionary = research.trials[id]
		var day := clampi(research._day() - int(trial.start_day) + 1, 1, Research.TRIAL_DAYS)
		var words := "Trial: %s, day %d of %d" % [research.card(id).display_name, day, Research.TRIAL_DAYS]
		if int(trial.report_day) > 0:
			words = "Trial: %s, report in the in-tray" % research.card(id).display_name
		for key: Array in trial.rooms:
			if int(key[0]) != level:
				continue
			var room := map.room_at(Vector2i(int(key[1]), int(key[2])))
			if room != null:
				out.append([room, words])
	return out


func _redraw() -> void:
	if not is_inside_tree() or building == null:
		return
	_mesh.clear_surfaces()
	for child in _labels.get_children():
		child.queue_free()
	var found := marks(building.active)
	if found.is_empty():
		return
	var map := building.levels[building.active] as BuildingMap
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each wing's label goes over the middle of its rooms.
	var middles: Dictionary[String, Array] = {}
	for entry: Array in found:
		var room: Room = entry[0]
		var top := -INF
		for cell in room.cells:
			var height := map.floor_height(cell) + lift
			top = maxf(top, height)
			for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if room.cells.has(cell + side):
					continue
				# A dash in the middle of each outside edge, so it reads dashed.
				var mid := Vector2(cell) + Vector2(0.5, 0.5) + Vector2(side) * (0.5 - THICKNESS)
				var half := Vector2(THICKNESS, DASH * 0.5) if side.x != 0 else Vector2(DASH * 0.5, THICKNESS)
				MeshShapes.add_box_immediate(_mesh, Vector3(mid.x * cell_size, height, mid.y * cell_size),
						Vector3(half.x, 0.01, half.y) * cell_size, COLOUR)
		var middle: Array = middles.get_or_add(entry[1], [Vector2.ZERO, 0, -INF])
		middle[0] += room.centre()
		middle[1] += 1
		middle[2] = maxf(middle[2], top)
	for words: String in middles:
		var middle: Array = middles[words]
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 40
		label.pixel_size = 0.008
		label.outline_size = 8
		label.font = _label_font
		label.modulate = Color.WHITE
		label.outline_modulate = COLOUR.darkened(0.4)
		label.text = words
		var centre: Vector2 = middle[0] / float(middle[1])
		label.position = Vector3(centre.x * cell_size, middle[2] + 0.1, centre.y * cell_size)
		_labels.add_child(label)
	_mesh.surface_end()
