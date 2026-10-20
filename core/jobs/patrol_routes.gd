class_name PatrolRoutes
extends Node3D
## Routes for guards to walk, drawn with the route tool as a loop of
## points, and how many guards walk each. Shown as dotted loops while the
## route tool is open or the debug view is on.

signal changed

## A loop of points to walk, on one level.
class Route:
	var level := 0
	## In tile units, each in the middle of a tile.
	var points: Array[Vector2] = []
	## How many guards walk it.
	var guards := 0
	var name := ""

## Tiles from the first point that count as clicking it, to close a loop.
const CLOSE_DISTANCE := 0.75
## Tiles from a route that count as clicking it, to remove it.
const PICK_DISTANCE := 0.75
## Tiles between the dots drawn along a route.
const DOT_SPACING := 0.35

@export var controller: BuildController
@export var debug_overlay: DebugOverlay
@export var colour := Color(0.35, 0.55, 0.95, 0.9)
@export var drawing_colour := Color(0.35, 0.55, 0.95, 0.5)
var cell_size := 1.0
## Height of the walkable surface at (level, point), or NAN.
var height_at: Callable

var routes: Array[Route] = []
## The route being drawn, or null.
var drawing: Route

var _mesh := ImmediateMesh.new()
var _material := MeshShapes.vertex_colour_material(true)
var _next_number := 1


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	if controller != null:
		controller.route_clicked.connect(click)
		controller.tool_changed.connect(func(_tool: BuildController.Tool) -> void: cancel())


func _input(event: InputEvent) -> void:
	if drawing == null:
		return
	if event.is_action_pressed("build_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		finish()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	var tool_open := controller != null and controller.tool == BuildController.Tool.ROUTE
	if not tool_open and (debug_overlay == null or not debug_overlay.visible):
		return
	var drawn := false
	for route in routes:
		drawn = _draw_loop(route.level, route.points, true, colour, drawn)
	if drawing != null:
		var points := drawing.points.duplicate()
		var hover: Variant = controller.hover_point() if controller != null else null
		if hover != null:
			points.append(_snap(hover))
		drawn = _draw_loop(drawing.level, points, false, drawing_colour, drawn)
	if drawn:
		_mesh.surface_end()


## The route tool clicked a point: starts a route, adds to it, closes it
## when the first point is clicked again, or with `erase` removes the route
## there.
func click(level: int, point: Vector2, erase := false) -> void:
	if erase:
		var route := route_at(level, point)
		if route != null:
			remove(route)
		return
	var spot := _snap(point)
	if drawing == null:
		drawing = Route.new()
		drawing.level = level
	elif drawing.points.size() >= 2 and spot.distance_to(drawing.points[0]) <= CLOSE_DISTANCE:
		finish()
		return
	if drawing.points.is_empty() or drawing.points.back() != spot:
		drawing.points.append(spot)


## Closes the loop being drawn and keeps it, if it has two points or more.
func finish() -> void:
	if drawing != null and drawing.points.size() >= 2:
		drawing.name = "Route %d" % _next_number
		_next_number += 1
		routes.append(drawing)
		changed.emit()
	drawing = null


func cancel() -> void:
	drawing = null


func remove(route: Route) -> void:
	routes.erase(route)
	changed.emit()


## Sets how many guards walk a route.
func set_guards(route: Route, count: int) -> void:
	route.guards = maxi(count, 0)
	changed.emit()


## The route passing within PICK_DISTANCE of a point, or null.
func route_at(level: int, point: Vector2) -> Route:
	for route in routes:
		if route.level != level:
			continue
		for i in route.points.size():
			var a := route.points[i]
			var b := route.points[(i + 1) % route.points.size()]
			if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) <= PICK_DISTANCE:
				return route
	return null


static func _snap(point: Vector2) -> Vector2:
	return point.floor() + Vector2(0.5, 0.5)


func _draw_loop(level: int, points: Array, closed: bool, tint: Color, drawn: bool) -> bool:
	var count := points.size() if closed else points.size() - 1
	for i in count:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var dots := maxi(1, ceili(a.distance_to(b) / DOT_SPACING))
		for k in dots:
			var at := a.lerp(b, float(k) / dots)
			var y: float = height_at.call(level, at) if height_at.is_valid() else 0.0
			if is_nan(y):
				continue
			if not drawn:
				_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
				drawn = true
			MeshShapes.add_box_immediate(_mesh, Vector3(at.x, y + 0.08, at.y) * Vector3(cell_size, 1.0, cell_size),
					Vector3(0.07, 0.03, 0.07), tint)
	for point: Vector2 in points:
		var y: float = height_at.call(level, point) if height_at.is_valid() else 0.0
		if is_nan(y):
			continue
		if not drawn:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
			drawn = true
		MeshShapes.add_box_immediate(_mesh, Vector3(point.x * cell_size, y + 0.08, point.y * cell_size),
				Vector3(0.2, 0.05, 0.2), tint)
	return drawn
