class_name DeskTint
extends Node3D
## The Offices view: tints each claimed desk on the level in view by how
## much desk work waits for whoever sits there. Green under
## DeskWork.CLEAR minutes, amber up to DeskWork.OVERLOAD, red when they're
## overloaded. Turned on from the Heads page.

const REFRESH_SECONDS := 0.5
const CLEAR := Color(0.45, 0.8, 0.45, 0.55)
const BUSY := Color(0.95, 0.72, 0.3, 0.6)
const OVERLOADED := Color(0.9, 0.35, 0.3, 0.65)

@export var cell_size := 1.0
@export var lift := 0.05

var building: Building
var people: People
var claims: Claims
## (person) -> float: minutes on their pile, below 0 for nobody's desk.
var minutes_of: Callable
## (person) -> bool: whether they're overloaded.
var overloaded: Callable
var shown := false:
	set(value):
		shown = value
		_redraw()

var _mesh := ImmediateMesh.new()
var _wait := 0.0


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := MeshShapes.vertex_colour_material(true)
	# Under the desk and whoever sits at it, not over them.
	material.no_depth_test = false
	instance.material_override = material
	add_child(instance)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH_SECONDS
		_redraw()


## Each claimed desk and its colour: [level, PlacedObject, Color].
func desks() -> Array:
	var out: Array = []
	for person in people.people:
		var key := claims.claim_of(person)
		if key == Person.NO_OBJECT:
			continue
		var minutes: float = minutes_of.call(person)
		if minutes < 0.0:
			continue
		var placed := building.object_at(key)
		if placed == null:
			continue
		var colour := CLEAR
		if overloaded.call(person):
			colour = OVERLOADED
		elif minutes >= DeskWork.CLEAR:
			colour = BUSY
		out.append([key.x, placed, colour])
	return out


func _redraw() -> void:
	if not is_inside_tree():
		return
	_mesh.clear_surfaces()
	if not shown or building == null:
		return
	var any := false
	for entry: Array in desks():
		if entry[0] != building.active:
			continue
		if not any:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			any = true
		var placed: BuildingMap.PlacedObject = entry[1]
		var rect := placed.rect.grow(0.35)
		var centre := rect.get_center()
		var height := (building.levels[entry[0]] as BuildingMap).floor_height(Vector2i(centre.floor()))
		MeshShapes.add_box_immediate(_mesh, Vector3(centre.x * cell_size, height + lift, centre.y * cell_size),
				Vector3(rect.size.x * 0.5, 0.01, rect.size.y * 0.5) * cell_size, entry[2])
	if any:
		_mesh.surface_end()
