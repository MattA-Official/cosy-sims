class_name HealthTint
extends Node3D
## The Health view: tints each room on the level in view by how many in it
## are ill. Amber for one, red for OUTBREAK or more. Turned on from the
## Programmes page.

const REFRESH_SECONDS := 0.5
const SOME := Color(0.95, 0.75, 0.3, 0.4)
const MANY := Color(0.9, 0.35, 0.3, 0.5)

@export var cell_size := 1.0
@export var lift := 0.04

var building: Building
var people: People
var illnesses: Illnesses
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
	material.no_depth_test = false
	instance.material_override = material
	add_child(instance)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH_SECONDS
		_redraw()


## Rooms with anyone ill in them on a level, and how many: Room -> count.
func ill_rooms(level: int) -> Dictionary[Room, int]:
	var out: Dictionary[Room, int] = {}
	for person in illnesses.ill():
		var here := people.room_of(person)
		if not here.is_empty() and here[0] == level:
			out[here[1]] = out.get(here[1], 0) + 1
	return out


func _redraw() -> void:
	if not is_inside_tree():
		return
	_mesh.clear_surfaces()
	if not shown or building == null or illnesses == null:
		return
	var map := building.levels.get(building.active) as BuildingMap
	if map == null:
		return
	var rooms := ill_rooms(building.active)
	if rooms.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for room: Room in rooms:
		var colour := MANY if rooms[room] >= Illnesses.OUTBREAK else SOME
		for cell in room.cells:
			var height := map.floor_height(cell)
			MeshShapes.add_box_immediate(_mesh, Vector3((cell.x + 0.5) * cell_size, height + lift, (cell.y + 0.5) * cell_size),
					Vector3(0.5, 0.01, 0.5) * cell_size, colour)
	_mesh.surface_end()
