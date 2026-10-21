class_name UndoHistory
extends Node
## Undo and redo for building and landscaping: Ctrl+Z steps back, Ctrl+Y
## (or Ctrl+Shift+Z) steps forward again. Each step is a snapshot of the
## world as plain data, taken once a change is finished (the mouse let
## go), so a long drag or a brush stroke undoes in one go.

signal undone
signal redone

## Steps kept to go back through.
const MAX_STEPS := 50

## () -> Dictionary: the world as it is now.
var capture: Callable
## (Dictionary) -> void: puts the world back as a capture left it.
var restore: Callable

## () -> bool: something else to undo once every step is undone, such as
## the latest land bought. Optional.
var nothing_to_undo: Callable
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _current: Dictionary = {}
var _pending := false
var _restoring := false


## Starts from the world as it is now, with nothing to undo. Every signal
## given marks a change.
func start(signals: Array[Signal]) -> void:
	_current = capture.call()
	for changed in signals:
		changed.connect(_on_changed)


func can_undo() -> bool:
	return not _undo.is_empty() or _pending


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> bool:
	_flush()
	if _undo.is_empty():
		return nothing_to_undo.call() if nothing_to_undo.is_valid() else false
	_redo.append(_current)
	_put_back(_undo.pop_back())
	undone.emit()
	return true


func redo() -> bool:
	_flush()
	if _redo.is_empty():
		return false
	_undo.append(_current)
	_put_back(_redo.pop_back())
	redone.emit()
	return true


## Whether a restore is under way, so listeners can tell undo from building.
func restoring() -> bool:
	return _restoring


## Forgets every step, starting again from the world as it is, such as
## after loading a save.
func reset() -> void:
	_undo.clear()
	_redo.clear()
	_pending = false
	_current = capture.call()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not (key.ctrl_pressed or key.meta_pressed):
		return
	if key.physical_keycode == KEY_Z and not key.shift_pressed:
		undo()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_Y or (key.physical_keycode == KEY_Z and key.shift_pressed):
		redo()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _pending and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_flush()


func _on_changed() -> void:
	if not _restoring:
		_pending = true


## Makes the change so far one step.
func _flush() -> void:
	if not _pending:
		return
	_pending = false
	_undo.append(_current)
	if _undo.size() > MAX_STEPS:
		_undo.pop_front()
	_redo.clear()
	_current = capture.call()


func _put_back(state: Dictionary) -> void:
	_restoring = true
	restore.call(state)
	_restoring = false
	_current = state
