extends Node
## Registers the shared input actions in code, so every game in the series
## gets the same controls without copying a long input map between projects.
## Actions already defined in Project Settings are left alone, so a game can
## still override a binding there.

const KEY_ACTIONS := {
	"camera_pan_forward": [KEY_W, KEY_UP],
	"camera_pan_back": [KEY_S, KEY_DOWN],
	"camera_pan_left": [KEY_A, KEY_LEFT],
	"camera_pan_right": [KEY_D, KEY_RIGHT],
	"camera_rotate_left": [KEY_Q],
	"camera_rotate_right": [KEY_E],
	"camera_zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"camera_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"camera_fast": [KEY_SHIFT],
	"build_cancel": [KEY_ESCAPE],
	"build_rotate": [KEY_R],
	"build_toggle_walls": [KEY_TAB],
	"build_free_place": [KEY_ALT],
	"build_erase": [KEY_CTRL],
	"build_whole_room": [KEY_SHIFT],
	"build_free_rotate": [KEY_F],
	"build_look": [KEY_V],
	"build_eyedropper": [KEY_I],
	"build_brush_smaller": [KEY_BRACKETLEFT],
	"build_brush_bigger": [KEY_BRACKETRIGHT],
	"debug_toggle": [KEY_F3],
	"level_up": [KEY_PAGEUP],
	"level_down": [KEY_PAGEDOWN],
	"help_toggle": [KEY_F1],
	"time_pause": [KEY_SPACE],
	"time_slower": [KEY_COMMA],
	"time_faster": [KEY_PERIOD],
	"timetable_toggle": [KEY_T],
	"staff_toggle": [KEY_P],
	"money_toggle": [KEY_M],
	"office_toggle": [KEY_O],
	"security_toggle": [KEY_K],
	"programmes_toggle": [KEY_L],
	"saves_toggle": [KEY_F2],
	"settings_toggle": [KEY_F4],
}


func _enter_tree() -> void:
	for action: String in KEY_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in KEY_ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
