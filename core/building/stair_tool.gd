class_name StairTool
extends RefCounted
## Draws a staircase tile by tile, like the Sims 4 stair builder. Click the
## foot, then move the mouse the way the stairs should climb. Clicking short
## of the top puts a landing on the tile under the mouse, and the stairs
## carry on from there whichever way you move next, so they can turn a
## corner or come back on themselves. Clicking once the steps reach the top
## builds them.

## Landings with rounded outer corners rather than square ones.
var rounded := false

var _started := false
var _start := Vector2i.ZERO
var _cells: Array[Vector2i] = []
var _landings: Array[bool] = []
var _last_dir := Vector2i(0, 1)


func is_drawing() -> bool:
	return _started


## Starts again. Returns false if nothing was being drawn.
func cancel() -> bool:
	var was := _started
	_started = false
	_cells.clear()
	_landings.clear()
	return was


## The staircase a click with the mouse over `cell` would leave, as
## [route, landing flags, finished]. Before the first click it is a
## straight flight from the mouse.
func plan(cell: Vector2i) -> Array:
	var cells: Array[Vector2i] = _cells.duplicate()
	var landings: Array[bool] = _landings.duplicate()
	if not _started:
		_add_steps(cells, landings, cell, _last_dir, Staircase.STEP_TILES)
		return [cells, landings, true]
	var origin := _start if cells.is_empty() else cells[-1]
	var dir := _axis(cell - origin)
	var previous := Vector2i.ZERO if cells.is_empty() else _direction_into_last()
	if dir == Vector2i.ZERO or dir == -previous:
		dir = previous if previous != Vector2i.ZERO else _last_dir
	var first := _start if cells.is_empty() else origin + dir
	var offset := cell - first
	var reach := offset.x * dir.x + offset.y * dir.y + 1
	var left := steps_left()
	# The foot is always a step, so a landing needs at least one step first.
	if reach > left or (cells.is_empty() and reach <= 1):
		_add_steps(cells, landings, first, dir, left)
		return [cells, landings, true]
	reach = maxi(reach, 1)
	_add_steps(cells, landings, first, dir, reach - 1)
	cells.append(first + dir * (reach - 1))
	landings.append(true)
	return [cells, landings, false]


## Handles a click over `cell`. Returns the finished staircase once the
## steps reach the top; it is up to the caller to check it fits and build it.
func press(cell: Vector2i) -> Staircase:
	if not _started:
		_started = true
		_start = cell
		return null
	var planned := plan(cell)
	if planned[2]:
		return finish(planned)
	_cells = planned[0]
	_landings = planned[1]
	return null


## Turns a finished plan into a staircase and starts again.
func finish(planned: Array) -> Staircase:
	var route: Array[Vector2i] = planned[0]
	var flags: Array[bool] = planned[1]
	var flight := Staircase.create(route, flags, rounded)
	_last_dir = flight.direction_in(0)
	cancel()
	return flight


## Tiles of steps still to place.
func steps_left() -> int:
	return Staircase.STEP_TILES - _landings.count(false)


func _direction_into_last() -> Vector2i:
	if _cells.size() >= 2:
		return _cells[-1] - _cells[-2]
	return _cells[-1] - _start if _cells[-1] != _start else _last_dir


static func _add_steps(cells: Array[Vector2i], landings: Array[bool], from: Vector2i,
		dir: Vector2i, count: int) -> void:
	for i in count:
		cells.append(from + dir * i)
		landings.append(false)


## The main direction of an offset, as a unit step along one axis.
static func _axis(offset: Vector2i) -> Vector2i:
	if offset == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(offset.x) >= absi(offset.y):
		return Vector2i(signi(offset.x), 0)
	return Vector2i(0, signi(offset.y))
