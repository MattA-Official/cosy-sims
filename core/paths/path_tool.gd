class_name PathTool
extends RefCounted
## The path drawing tool, in the style of Cities: Skylines 2. Straight mode
## takes a click for each end; curved mode takes a start, a bend point and
## an end. Each path carries on from the end of the last until you stop
## with Esc, so you can lay a long winding path click by click. Freehand
## mode follows a drag and smooths it into curves when you let go.
##
## Ends snap to other paths (making junctions) and to outside doors. Paths
## stay on your own land and off floors, but may touch a floor where they
## meet a door.

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

## Freehand curves are this long, in tiles, before the next one starts.
const FREEHAND_STEP := 3.0

var _placed: Array[Vector2] = [] ## The start, then the bend in curved mode.
var _trail: Array[Vector2] = [] ## Points dragged through in freehand mode.


func is_drawing() -> bool:
	return not _placed.is_empty()


## Stops the path being drawn. Returns false if there was none.
func cancel() -> bool:
	var was := is_drawing() or not _trail.is_empty()
	_placed.clear()
	_trail.clear()
	return was


## Freehand: starts a drag.
func begin_trail(point: Vector2) -> void:
	_trail = [snap(point)]


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
	_trail.append(snap(point))
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
	var target := snap(point)
	var needed := 2 if mode == Mode.STRAIGHT else 3
	if _placed.size() + 1 < needed:
		_placed.append(target)
		return null
	var curve := _curve_to(target)
	if not is_valid(curve):
		return null
	var segment := network.add_segment(curve[0], curve[2],
			curve[1] if mode == Mode.CURVED else null, style)
	if segment == null:
		return null
	_clear_plants(network.sample(segment))
	_placed = [network.node_position(segment.b)]
	return segment


## Where a click at `point` would put an end: on a nearby path, at a nearby
## outside door, or where it is.
func snap(point: Vector2) -> Vector2:
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
	return best


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
		var end := snap(point)
		return [_placed[0], (_placed[0] + end) * 0.5, end]
	return _curve_to(snap(point))


## Whether a curve can be built: long enough, on your land, out of the
## water at its ends, and off floors except right by its ends.
func is_valid(curve: Array) -> bool:
	if curve.is_empty():
		return false
	var a: Vector2 = curve[0]
	var b: Vector2 = curve[2]
	if a.distance_to(b) < 0.5:
		return false
	if terrain != null and (terrain.is_underwater(a) or terrain.is_underwater(b)):
		return false
	for p in PathNetwork.sample_curve(a, curve[1], b, 0.25):
		var cell := Vector2i(p.floor())
		if not map.owns(cell):
			return false
		if map.has_floor(cell) and p.distance_to(a) > DOOR_REACH and p.distance_to(b) > DOOR_REACH:
			return false
	return true


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
		var target := snap(point)
		view.add_block(st, target - Vector2(0.2, 0), target + Vector2(0.2, 0), 0.2,
				_ground(target) + 0.6, _ground(target) + 0.6, _ground(target), ok_tint, ok_tint)
		return
	var tint := ok_tint if is_valid(curve) else bad_tint
	view.add_curve(st, PathNetwork.sample_curve(curve[0], curve[1], curve[2]), def, tint)
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
