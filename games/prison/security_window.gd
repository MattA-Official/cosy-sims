class_name SecurityWindow
extends PanelContainer
## Security at a glance: cameras and guards, the perimeter, today's
## incidents and the Safety grade they're heading for, searches, anyone at
## large, and the latest alerts (click one to look). Toggle with K.

const REFRESH_SECONDS := 0.5
const ALERTS_SHOWN := 8

## (level, point in tile units) -> void: looks at somewhere.
signal look_pressed(level: int, point: Vector2)

var security: Security
var secure_area: SecureArea
var searching: Searching
var escapes: Escapes
var coverage_tint: CoverageTint
var sit_ins: SitIns
var infirmary: Infirmary
var prisoners: Callable

var _show := CheckBox.new()
var _status := Label.new()
var _today := Label.new()
var _alerts := VBoxContainer.new()
var _sit_ins := VBoxContainer.new()
var _shown_sit_ins: Array = []
var _wait := 0.0
var _shown_alerts := -1
var _shakedown := Button.new()
var _deaths := CheckBox.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	grow_horizontal = GROW_DIRECTION_BOTH
	offset_top = 76.0
	custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)

	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Security"
	title.theme_type_variation = &"HeaderLabel"
	heading.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(spacer)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"FlatButton"
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(hide)
	heading.add_child(close)
	box.add_child(heading)

	_show.text = "Show what's being watched"
	_show.tooltip_text = "Tints in blue where guards and watched cameras have seen lately. Prisoners behave where it's blue."
	_show.focus_mode = FOCUS_NONE
	_show.toggled.connect(func(on: bool) -> void:
		if coverage_tint != null:
			coverage_tint.shown = on)
	box.add_child(_show)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.theme_type_variation = &"SubtleLabel"
	box.add_child(_status)
	box.add_child(HSeparator.new())
	var today_heading := Label.new()
	today_heading.text = "Today"
	today_heading.theme_type_variation = &"HeaderLabel"
	box.add_child(today_heading)
	_today.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_today)
	_sit_ins.add_theme_constant_override(&"separation", 4)
	box.add_child(_sit_ins)
	_shakedown.focus_mode = FOCUS_NONE
	_shakedown.tooltip_text = "At the next Lockup, guards search every cell. Finds stashes, but puts everyone in a temper."
	_shakedown.pressed.connect(func() -> void:
		searching.shakedown_tonight = not searching.shakedown_tonight
		refresh())
	box.add_child(_shakedown)
	box.add_child(HSeparator.new())
	var alerts_heading := Label.new()
	alerts_heading.text = "Alerts"
	alerts_heading.theme_type_variation = &"HeaderLabel"
	box.add_child(alerts_heading)
	_alerts.add_theme_constant_override(&"separation", 0)
	box.add_child(_alerts)
	box.add_child(HSeparator.new())
	_deaths.text = "Deaths (rare)"
	_deaths.tooltip_text = "Off, nobody dies. On, someone knocked out and left untreated, or beaten badly, can die."
	_deaths.focus_mode = FOCUS_NONE
	_deaths.toggled.connect(func(on: bool) -> void:
		if infirmary != null:
			infirmary.deaths = on)
	box.add_child(_deaths)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH_SECONDS
		refresh()


func toggle() -> void:
	visible = not visible
	refresh()


func refresh() -> void:
	if security == null:
		return
	_show.set_pressed_no_signal(coverage_tint != null and coverage_tint.shown)
	_status.text = "\n".join(status_lines())
	_today.text = "\n".join(today_lines())
	_show_sit_ins()
	_shakedown.visible = searching != null
	if searching != null:
		_shakedown.text = "Shakedown booked for Lockup (cancel)" if searching.shakedown_tonight else "Shakedown tonight"
	_deaths.visible = infirmary != null
	_deaths.set_pressed_no_signal(infirmary != null and infirmary.deaths)
	if _shown_alerts != security.alerts.size() or (not security.alerts.is_empty() and _alerts.get_child_count() == 0):
		_show_alerts()


## Cameras, guards and the perimeter, a line each.
func status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var cameras := security.building.objects_tagged([Security.CAMERA_TAG]).size()
	var monitors := security.building.objects_tagged([Security.MONITOR_TAG]).size()
	if cameras == 0:
		lines.append("No cameras yet. A CCTV camera watches a cone in front of it while a guard sits at a monitor.")
	elif monitors == 0:
		lines.append("%d %s, but no CCTV monitor to watch them on." % [cameras, _plural(cameras, "camera")])
	elif security.cameras_live():
		lines.append("%d %s, watched from the monitor." % [cameras, _plural(cameras, "camera")])
	else:
		lines.append("%d %s, but nobody is at a monitor just now." % [cameras, _plural(cameras, "camera")])
	var guards := security.people.people.filter(func(p: Person) -> bool:
		return p.role == security.guard_role and not p.going_home).size()
	lines.append("%d %s on duty." % [guards, _plural(guards, "guard")])
	if secure_area != null:
		lines.append("Perimeter built: open ground inside it is secure." if secure_area.has_perimeter
				else "No perimeter yet: a prisoner who wanders off outside can walk away. Fence the prison in with perimeter walls and gates.")
	return lines


## Today's incidents, the Safety they're heading for, searches and escapes.
func today_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var parts := PackedStringArray()
	for kind: StringName in Security.NAMES:
		if security.today.get(kind, 0) > 0:
			parts.append("%s %d" % [Security.NAMES[kind], security.today[kind]])
	lines.append("No incidents." if parts.is_empty() else "  ·  ".join(parts))
	var count: int = prisoners.call() if prisoners.is_valid() else 0
	var stars := Security.safety_stars(security.today, count)
	lines.append("Safety so far  %s%s" % ["★".repeat(stars), "☆".repeat(5 - stars)])
	if searching != null:
		var found := "" if searching.found_today.is_empty() else ", found %s" % ", ".join(searching.found_today)
		lines.append("%d %s%s." % [searching.searches_today, _plural(searching.searches_today, "search", "searches"), found])
	if escapes != null and not escapes.at_large.is_empty():
		var names := PackedStringArray()
		for entry: Array in escapes.at_large:
			names.append(entry[0])
		lines.append("At large: %s." % ", ".join(names))
	return lines


## Each sit-in going on, with what would end it and a button to talk.
func _show_sit_ins() -> void:
	var now: Array = sit_ins.sit_ins.duplicate() if sit_ins != null else []
	var talking := now.map(func(s: SitIns.SitIn) -> bool: return s.job != null)
	if now == _shown_sit_ins.slice(0, now.size()) and _shown_sit_ins.slice(now.size()) == talking \
			and _shown_sit_ins.size() == now.size() * 2:
		return
	_shown_sit_ins = now + talking
	for child in _sit_ins.get_children():
		_sit_ins.remove_child(child)
		child.queue_free()
	for sit_in: SitIns.SitIn in now:
		var row := HBoxContainer.new()
		var words := Label.new()
		words.text = "Sit-in: \"%s\" (%d sitting, over %s). To fix it, %s." % [sit_in.demand,
				sit_in.members.size(), sit_in.cause.to_lower(), sit_in.hint]
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.size_flags_horizontal = SIZE_EXPAND_FILL
		words.custom_minimum_size = Vector2(300, 0)
		row.add_child(words)
		var talk := Button.new()
		talk.text = "Someone's on the way" if sit_in.job != null else "Talk them round"
		talk.disabled = sit_in.job != null
		talk.focus_mode = FOCUS_NONE
		talk.tooltip_text = "A guard (or the warden, twice as fast) hears them out for 20 minutes."
		talk.pressed.connect(func() -> void:
			sit_ins.negotiate(sit_in)
			refresh())
		row.add_child(talk)
		_sit_ins.add_child(row)


func _show_alerts() -> void:
	_shown_alerts = security.alerts.size()
	for child in _alerts.get_children():
		_alerts.remove_child(child)
		child.queue_free()
	if security.alerts.is_empty():
		var none := Label.new()
		none.text = "Nothing yet."
		none.theme_type_variation = &"SubtleLabel"
		_alerts.add_child(none)
		return
	for i in mini(security.alerts.size(), ALERTS_SHOWN):
		var alert: Array = security.alerts[i]
		var button := Button.new()
		button.text = "Day %d  %s  %s" % [alert[0], "%02d:%02d" % [alert[1] / 60, alert[1] % 60], alert[2]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.theme_type_variation = &"FlatButton"
		button.focus_mode = FOCUS_NONE
		button.tooltip_text = "Look there"
		var level: int = alert[3]
		var point: Vector2 = alert[4]
		button.pressed.connect(func() -> void: look_pressed.emit(level, point))
		_alerts.add_child(button)


static func _plural(count: int, one: String, many := "") -> String:
	return one if count == 1 else (many if not many.is_empty() else one + "s")
