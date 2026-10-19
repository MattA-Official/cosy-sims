extends Control
## A mock-up HUD for judging the cosy theme: a top bar, an inspector card, a
## room card with tabs, a toast, a tooltip and the build toolbar. None of it
## is wired up. Open theme_preview.tscn and press F6, or put it over the game
## with tools/ui_preview_shot.gd.

const TOOLS := ["Room", "Floor", "Wall", "Doors and windows", "Objects", "Room type",
		"Demolish", "Terrain", "Plants", "Paths"]


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_top_bar()
	_toast()
	_inspector()
	_room_card()
	_tooltip()
	_toolbar()


func _top_bar() -> void:
	var bar := _panel("HudBar")
	bar.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	bar.position.y = 14
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	var day := _label("Day 3", "TitleLabel")
	row.add_child(day)
	row.add_child(_label("07:40  Breakfast", "HeaderLabel"))
	row.add_child(VSeparator.new())
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for i in 4:
		var b := _button(["II", "1x", "2x", "3x"][i], "FlatButton")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 1
		speeds.add_child(b)
	row.add_child(speeds)
	row.add_child(VSeparator.new())
	row.add_child(_label("£12,450", "HeaderLabel"))
	row.add_child(_label("+£310 today", "SubtleLabel"))
	row.add_child(VSeparator.new())
	row.add_child(_label("Prisoners", "SubtleLabel"))
	row.add_child(_label("42 / 60", "HeaderLabel"))
	_centre_x(bar)


func _toast() -> void:
	var toast := _panel("ToastPanel")
	toast.position.y = 84
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(_label("Breakfast is served", "HeaderLabel"))
	col.add_child(_label("38 prisoners are heading to the canteen.", "SubtleLabel"))
	toast.add_child(col)
	toast.reset_size()
	toast.position.x = get_viewport_rect().size.x - toast.size.x - 16


func _inspector() -> void:
	var card := _panel()
	card.position = Vector2(16, 84)
	card.custom_minimum_size.x = 320
	var col := VBoxContainer.new()
	card.add_child(col)
	col.add_child(_label("PRISONER", "TitleLabel"))
	col.add_child(_label("Tess Inchley", "HeaderLabel"))
	col.add_child(_label("Cell 4  ·  Low security  ·  Day 12 of 90", "SubtleLabel"))
	var doing := _panel("InsetPanel", col)
	doing.add_child(_label("Eating breakfast in the canteen"))
	col.add_child(_spacer(4))
	for need: Array in [["Sleep", 62, ""], ["Hunger", 84, ""], ["Hygiene", 41, "BarWarning"],
			["Comfort", 18, "BarDanger"]]:
		var row := HBoxContainer.new()
		var name := _label(need[0])
		name.custom_minimum_size.x = 84
		row.add_child(name)
		var bar := ProgressBar.new()
		bar.theme_type_variation = need[2]
		bar.value = need[1]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		bar.size_flags_horizontal = SIZE_EXPAND_FILL
		bar.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(bar)
		var value := _label(str(need[1]), "SubtleLabel")
		value.custom_minimum_size.x = 28
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		col.add_child(row)
	col.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	var send := _button("Send somewhere", "AccentButton")
	send.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(send)
	var follow := _button("Follow")
	follow.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(follow)
	col.add_child(buttons)
	var remove := _button("Release early", "DangerButton")
	col.add_child(remove)


func _room_card() -> void:
	var tabs := TabContainer.new()
	add_child(tabs)
	tabs.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_MINSIZE, 16)
	tabs.offset_top = 190
	tabs.offset_left = -376
	var overview := VBoxContainer.new()
	overview.name = "Canteen"
	tabs.add_child(overview)
	var regime := VBoxContainer.new()
	regime.name = "Regime"
	tabs.add_child(regime)
	var staff := VBoxContainer.new()
	staff.name = "Staff"
	tabs.add_child(staff)
	overview.add_child(_label("Room name", "SubtleLabel"))
	var name := LineEdit.new()
	name.text = "East canteen"
	overview.add_child(name)
	var floor_row := HBoxContainer.new()
	floor_row.add_child(_label("Floor"))
	var floor := OptionButton.new()
	for item in ["Lino", "Tiles", "Concrete"]:
		floor.add_item(item)
	floor.size_flags_horizontal = SIZE_EXPAND_FILL
	floor_row.add_child(floor)
	overview.add_child(floor_row)
	overview.add_child(_spacer(2))
	var lock := CheckBox.new()
	lock.text = "Lock at night"
	lock.button_pressed = true
	overview.add_child(lock)
	var guard := CheckBox.new()
	guard.text = "Needs a guard"
	overview.add_child(guard)
	var open := CheckButton.new()
	open.text = "Open to prisoners"
	open.button_pressed = true
	overview.add_child(open)
	var shut := CheckButton.new()
	shut.text = "Staff only"
	overview.add_child(shut)
	overview.add_child(_spacer(2))
	var seats := HBoxContainer.new()
	seats.add_child(_label("Seats"))
	var slider := HSlider.new()
	slider.max_value = 80
	slider.value = 48
	slider.tick_count = 9
	slider.ticks_on_borders = true
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	seats.add_child(slider)
	seats.add_child(_label("48", "HeaderLabel"))
	overview.add_child(seats)
	overview.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_child(_label("64 tiles  ·  Indoors", "SubtleLabel"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var off := _button("Disabled")
	off.disabled = true
	footer.add_child(off)
	overview.add_child(footer)


func _tooltip() -> void:
	var tip := _panel("TooltipPanel")
	tip.position = Vector2(820, 470)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(_label("Cell 4", "HeaderLabel"))
	col.add_child(_label("Bed, toilet, desk  ·  Tess Inchley", "SubtleLabel"))
	tip.add_child(col)


func _toolbar() -> void:
	var dock := VBoxContainer.new()
	add_child(dock)
	dock.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	dock.offset_top = -170
	dock.offset_bottom = -14
	dock.alignment = BoxContainer.ALIGNMENT_END
	dock.add_theme_constant_override("separation", 10)

	var hint := HBoxContainer.new()
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_child(_label("Drag to lay floor.", "HudLabel"))
	hint.add_child(_label("Shift", "KeyLabel"))
	hint.add_child(_label("floors the whole room,", "HudLabel"))
	hint.add_child(_label("Ctrl", "KeyLabel"))
	hint.add_child(_label("removes.", "HudLabel"))
	dock.add_child(hint)

	var options := _panel("HudBar", dock)
	options.size_flags_horizontal = SIZE_SHRINK_CENTER
	var opts := HBoxContainer.new()
	var group := ButtonGroup.new()
	for i in 5:
		var b := _button(["Lay", "Raise", "Lower", "Ramp", "Stairs"][i], "FlatButton")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		opts.add_child(b)
	opts.add_child(VSeparator.new())
	for style in ["Lino", "Tiles", "Concrete", "Carpet"]:
		var b := _button(style)
		b.toggle_mode = true
		b.button_pressed = style == "Lino"
		opts.add_child(b)
	options.add_child(opts)

	var tools := _panel("HudBar", dock)
	tools.size_flags_horizontal = SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	var tool_group := ButtonGroup.new()
	for i in TOOLS.size():
		var b := _button("", "ToolButton")
		b.toggle_mode = true
		b.button_group = tool_group
		b.button_pressed = i == 1
		row.add_child(b)
		var inner := HBoxContainer.new()
		inner.mouse_filter = MOUSE_FILTER_IGNORE
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.add_theme_constant_override("separation", 6)
		b.add_child(inner)
		inner.add_child(_label(str((i + 1) % 10), "KeyLabel"))
		var text := _label(TOOLS[i])
		text.add_theme_font_override("font", get_theme_font("font", "ToolButton"))
		text.add_theme_color_override("font_color", get_theme_color(
				"font_pressed_color" if i == 1 else "font_color", "ToolButton"))
		inner.add_child(text)
		inner.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		inner.offset_bottom = -2
		b.custom_minimum_size = Vector2(inner.get_combined_minimum_size().x + 26, 44)
	tools.add_child(row)


func _panel(variation := "", parent: Node = self) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	parent.add_child(panel)
	return panel


func _label(text: String, variation := "") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.size_flags_vertical = SIZE_SHRINK_CENTER
	return label


func _button(text: String, variation := "") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.focus_mode = FOCUS_NONE
	return button


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer


func _centre_x(control: Control) -> void:
	control.reset_size()
	control.position.x = (get_viewport_rect().size.x - control.get_combined_minimum_size().x) * 0.5
