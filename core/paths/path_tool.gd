class_name PathTool
extends RefCounted
## The path drawing tool, in the style of Cities: Skylines 2. Straight mode
## takes a click for each end; curved mode takes a start, a bend point and
## an end. Each path carries on from the end of the last until you stop
## with Esc, so you can lay a long winding path click by click. Freehand
## mode follows a drag and smooths it into curves when you let go.
##
## Points snap to the middle of tiles, like floors; the bend of a curve
## does not. Holding Alt while placing a point does the opposite, and the
## grid can be turned off altogether. Ends also snap to other paths (making
## junctions) and to outside doors. Paths stay on your own land and off
## floors, but may touch a floor where they meet a door. They may cross
## other paths, making a junction, but not run along or over them.
##
## Paths follow the ground. Page Up or Down while placing makes the next
## stretch a built one instead: stairs, a ramp or a bridge running straight
## between its ends. The first press builds it with its far end on the
## ground; more presses raise that end a step at a time.

enum Mode { STRAIGHT, CURVED, FREEHAND }

## How close an end must be to an outside door to snap to it, in tiles.
const DOOR_SNAP := 0.8
## How far from its ends a path may run over floor, to reach a door.
const DOOR_REACH := 0.7

var network: PathNetwork
var view: PathView
var map: BuildingMap
var terrain: Terrain
var foliage: FoliageLayer
var mode := Mode.STRAIGHT
var style: StringName = &""
## Snap points to the middle of tiles.
var snap_to_grid := true
## Held while placing a point to snap it when it would not, or not when it
## would.
var free_held := false
## Is the stretch being placed built (stairs, ramp or bridge)?
var built := false
## Steps the far end of a built stretch is raised off the ground.
var raise_steps := 0

## Freehand curves are this long, in tiles, before the next one starts.
const FREEHAND_STEP := 3.0

var _placed: Array[Vector2] = [] ## The start, then the bend in curved mode.
var _start_height := NAN ## The start's height if it is off the ground.
var _trail: Array[Vector2] = [] ## Points dragged through in freehand mode.


func is_drawing() -> bool:
	return not _placed.is_empty()


## Stops the path being drawn. Returns false if there was none.
func cancel() -> bool:
	var was := is_drawing() or not _trail.is_empty()
	_placed.clear()
	_trail.clear()
	_start_height = NAN
	built = false
	raise_steps = 0
	return was


## Page Up: build the next stretch, or raise its far end a step.
func raise() -> void:
	if built:
		raise_steps += 1
	built = true


## Page Down: lower the far end of a built stretch a step, or go back to
## following the ground.
func lower() -> void:
	if raise_steps > 0:
		raise_steps -= 1
	else:
		built = false


## Freehand: starts a drag.
func begin_trail(point: Vector2) -> void:
	_trail = [snap(point, true)]


## Freehand: the mouse moved while dragging.
func extend_trail(point: Vector2) -> void:
	if not _trail.is_empty() and _trail[-1].distance_to(point) >= 0.5:
		_trail.append(point)


## Freehand: the drag ended. Turns the trail into a chain of curves, each
## bending through the middle of its stretch of the trail. Returns how many
## were added.
func end_trail(point: Vector2) -> int:
	if _trail.is_empty():
		return 0
	_trail.append(snap(point, true))
	var trail := _trail
	_trail = []
	var added := 0
	var start := 0
	while start < trail.size() - 1:
		var end := start + 1
		var length := 0.0
		while end < trail.size() - 1 and length < FREEHAND_STEP:
			length += trail[end].distance_to(trail[end + 1])
			end += 1
		var a := trail[start]
		var b := trail[end]
		var middle := trail[(start + end) / 2]
		# The control point that makes the curve pass through `middle`.
		var curve := [a, middle * 2.0 - (a + b) * 0.5, b]
		if is_valid(curve):
			if network.add_segment(a, b, curve[1], style) != null:
				added += 1
				_clear_plants(network.sample_curve(a, curve[1], b))
		start = end
	return added


## Handles a click. With `erase`, removes the path under the mouse instead.
## Returns the segment added, if any.
func press(point: Vector2, erase := false) -> PathNetwork.Segment:
	if erase:
		cancel()
		var hit := network.closest(point)
		if not hit.is_empty() and hit[2] <= 1.0:
			network.remove_segment(hit[0].id)
		return null
	var needed := 2 if mode == Mode.STRAIGHT else 3
	if _placed.is_empty():
		var start := snap(point, true)
		_placed.append(start)
		_start_height = network.snap_height(start)
		if not is_nan(_start_height):
			built = true
		return null
	if _placed.size() + 1 < needed:
		_placed.append(snap(point, false))
		return null
	var curve := _curve_to(snap(point, true))
	if not is_valid(curve):
		return null
	var heights := end_heights(curve)
	var segment := network.add_segment(curve[0], curve[2],
			curve[1] if mode == Mode.CURVED else null, style, _is_built(curve), heights[0], heights[1])
	if segment == null:
		return null
	_clear_plants(network.sample_curve(curve[0], curve[1], curve[2]))
	_placed = [curve[2]]
	_start_height = heights[1]
	return segment


## Where a click at `point` would put a point: on a nearby path, at a nearby
## outside door, or on the grid. `is_end` says whether it is an end, which
## snaps to the grid, or a bend, which does not; holding Alt swaps that.
func snap(point: Vector2, is_end := true) -> Vector2:
	var snapped := network.snap(point)
	if snapped != point:
		return snapped
	var best := point
	var best_distance := DOOR_SNAP
	for door in door_points():
		var distance := door.distance_to(point)
		if distance < best_distance:
			best = door
			best_distance = distance
	if best != point:
		return best
	var to_grid := snap_to_grid and is_end
	if free_held:
		to_grid = not to_grid
	return point.floor() + Vector2(0.5, 0.5) if to_grid else point


## The heights of a curve's ends, NAN for on the ground: an existing node
## keeps its own; a new far end on a built stretch is raised by the steps
## chosen.
func end_heights(curve: Array) -> Array[float]:
	var from := _start_height
	var to := network.snap_height(curve[2])
	if is_nan(to) and network.node_near(curve[2], 0.01) == -1 and _is_built(curve) and raise_steps > 0:
		to = _ground(curve[2]) + raise_steps * Staircase.RISE
	return [from, to]


## A short note on the stretch being placed, for the hint.
func status(point: Vector2) -> String:
	var curve := pending_curve(point)
	var note := ""
	if built:
		note = "Built: far end on the ground." if raise_steps == 0 \
				else "Built: far end raised %.2f m." % (raise_steps * Staircase.RISE)
	if not curve.is_empty():
		var problem := problem_with(curve)
		if not problem.is_empty():
			note = (note + " " + problem).strip_edges()
	return note


## Just outside each door that has floor on one side only.
func door_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for edge: Vector3i in map.walls:
		if map.wall_at(edge) != BuildingMap.Wall.DOOR:
			continue
		var sides := BuildingMap.edge_cells(edge)
		var inside := map.has_floor(sides[0])
		if inside == map.has_floor(sides[1]):
			continue
		var outside: Vector2i = sides[1] if inside else sides[0]
		var along := Vector2(1, 0) if edge.z == BuildingMap.EDGE_X else Vector2(0, 1)
		var middle := Vector2(edge.x, edge.y) + along * 0.5
		var out_dir := (Vector2(outside) + Vector2(0.5, 0.5) - middle).normalized()
		out.append(middle + out_dir * 0.1)
	return out


## The curve [start, control, end] that clicking at `point` would finish,
## or [] if more points are needed first.
func pending_curve(point: Vector2) -> Array:
	if _placed.is_empty():
		return []
	if mode == Mode.CURVED and _placed.size() == 1:
		# Still choosing the bend: show it straight to the mouse for now.
		var end := snap(point, true)
		return [_placed[0], (_placed[0] + end) * 0.5, end]
	return _curve_to(snap(point, true))


## Whether a curve can be built.
func is_valid(curve: Array) -> bool:
	return not curve.is_empty() and problem_with(curve).is_empty()


## Why a curve cannot be built, or "" if it can: it must be long enough, on
## your land, off floors except right by its ends, not too steep or in the
## water unless built, and must not run along or over another path.
func problem_with(curve: Array) -> String:
	var a: Vector2 = curve[0]
	var b: Vector2 = curve[2]
	if a.distance_to(b) < 0.5:
		return "Too short."
	var points := PathNetwork.sample_curve(a, curve[1], b, 0.25)
	for p in points:
		var cell := Vector2i(p.floor())
		if not map.owns(cell):
			return "Not on your land."
		if map.has_floor(cell) and p.distance_to(a) > DOOR_REACH and p.distance_to(b) > DOOR_REACH:
			return "In the way of a building."
	var heights := end_heights(curve)
	var profile := PathProfile.build(PathNetwork.sample_curve(a, curve[1], b), terrain,
			_is_built(curve), heights[0], heights[1])
	if not profile.problem.is_empty():
		return profile.problem
	if _overlaps(curve, heights):
		return "Runs over another path. Paths may only cross."
	return ""


## Does a curve run along or over another path, rather than just crossing
## it or joining it at an end?
func _overlaps(curve: Array, heights: Array[float]) -> bool:
	var a: Vector2 = curve[0]
	var b: Vector2 = curve[2]
	var is_built := _is_built(curve)
	var half := _half_width()
	var crossed := network.crossings(a, curve[1], b, is_built, heights[0], heights[1])
	var mine := PathNetwork.sample_curve(a, curve[1], b, 0.25)
	for segment: PathNetwork.Segment in network.segments.values():
		var def := view.style(segment.style) if view != null else null
		var reach := half + (def.width * 0.5 if def != null else 0.75)
		var clear := reach + 0.3 # Near a junction, paths are bound to meet.
		var theirs := network.sample(segment, 0.25)
		for i in mine.size():
			var p := mine[i]
			if p.distance_to(a) < clear or p.distance_to(b) < clear:
				continue
			if crossed.any(func(hit: Array) -> bool: return p.distance_to(hit[3]) < clear * 1.5):
				continue
			for j in theirs.size():
				if p.distance_to(theirs[j]) >= reach * 0.9:
					continue
				var t_mine := float(i) / maxf(mine.size() - 1, 1)
				var t_theirs := float(j) / maxf(theirs.size() - 1, 1)
				var mine_height := PathNetwork.curve_height(a, b, t_mine, terrain, is_built,
						heights[0], heights[1], curve[1])
				if absf(mine_height - network.height_on(segment, t_theirs)) < PathNetwork.PASS_UNDER:
					return true
	return false


## A stretch is built if you chose it, or if either end is off the ground.
func _is_built(curve: Array) -> bool:
	if built:
		return true
	return not is_nan(_start_height) or not is_nan(network.snap_height(curve[2]))


## Draws the path a click would add, tinted to show if it is allowed, plus
## a marker where the next point would go.
func preview(st: SurfaceTool, point: Vector2, ok_tint: Color, bad_tint: Color) -> void:
	var def := view.style(style)
	if not _trail.is_empty():
		var trail := PackedVector2Array(_trail)
		trail.append(point)
		view.add_curve(st, trail, def, ok_tint)
		return
	var curve := pending_curve(point)
	if curve.is_empty():
		var target := snap(point, _placed.is_empty())
		view.add_block(st, target - Vector2(0.2, 0), target + Vector2(0.2, 0), 0.2,
				_ground(target) + 0.6, _ground(target) + 0.6, _ground(target), ok_tint, ok_tint)
		return
	var tint := ok_tint if is_valid(curve) else bad_tint
	var heights := end_heights(curve)
	view.add_curve(st, PathNetwork.sample_curve(curve[0], curve[1], curve[2]), def, tint,
			_is_built(curve), heights[0], heights[1])
	if mode == Mode.CURVED and _placed.size() == 2:
		var bend: Vector2 = _placed[1]
		view.add_block(st, bend - Vector2(0.15, 0), bend + Vector2(0.15, 0), 0.15,
				_ground(bend) + 0.4, _ground(bend) + 0.4, _ground(bend), tint, tint)


func _clear_plants(points: PackedVector2Array) -> void:
	if foliage == null:
		return
	var half := _half_width()
	for p in points:
		foliage.remove_in_circle(p, half + 0.2)


func _curve_to(end: Vector2) -> Array:
	var start := _placed[0]
	var control := _placed[1] if _placed.size() > 1 else (start + end) * 0.5
	return [start, control, end]


func _half_width() -> float:
	var def := view.style(style) if view != null else null
	return def.width * 0.5 if def != null else 0.75


func _ground(point: Vector2) -> float:
	return terrain.height_at(point) if terrain != null else 0.0
