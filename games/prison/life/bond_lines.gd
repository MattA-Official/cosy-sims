class_name BondLines
extends Node3D
## While the inspector has someone picked, thin lines run from them to
## their friends (green), rivals (red) and fellow clique members (in the
## clique's colour) on the level in view. A child of the inspector, so it
## shares its space.

const FRIEND := Color(0.35, 0.75, 0.4, 0.85)
const RIVAL := Color(0.85, 0.3, 0.3, 0.85)
const HEIGHT := 1.1
const REFRESH_SECONDS := 0.25

var inspector: Inspector
var relationships: Relationships
## Optional.
var cliques: Cliques
var building: Building

var _mesh := ImmediateMesh.new()
var _wait := 0.0


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = MeshShapes.vertex_colour_material(true)
	add_child(instance)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REFRESH_SECONDS
	_mesh.clear_surfaces()
	var person: Person = inspector.selected() as Person if inspector != null and inspector.selected() is Person else null
	if person == null or not inspector.is_open() or relationships == null:
		return
	var lines := lines_for(person)
	if lines.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line: Array in lines:
		_mesh.surface_set_color(line[1])
		_mesh.surface_add_vertex(_at(person))
		_mesh.surface_set_color(line[1])
		_mesh.surface_add_vertex(_at(line[0]))
	_mesh.surface_end()


## [other Person, colour] for each friend and rival on the level in view.
func lines_for(person: Person) -> Array:
	var out: Array = []
	var level := building.active if building != null else person.level
	for pair: Array in relationships.friends_of(person):
		if (pair[0] as Person).level == level:
			out.append([pair[0], FRIEND])
	for pair: Array in relationships.rivals_of(person):
		if (pair[0] as Person).level == level:
			out.append([pair[0], RIVAL])
	var clique := cliques.clique_of(person) if cliques != null else null
	if clique != null:
		for member in cliques.members_of(clique):
			if member != person and member.level == level and not relationships.is_friend(person, member):
				out.append([member, clique.colour])
	return out


func _at(person: Person) -> Vector3:
	return person.position + Vector3.UP * HEIGHT
