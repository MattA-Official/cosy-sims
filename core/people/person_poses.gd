class_name PersonPoses
extends RefCounted
## How people look while they use things: lying in bed, sitting at a table
## or on a toilet or bench, standing in the shower. Only the body moves;
## where People keeps the person is unchanged.
##
## Body models can have legs that swing forward to sit and arms that swing
## forward to carry: meshes whose names end in "_legs" (pivoting at the
## hips) and "_arms" (pivoting at the shoulders).

enum Pose {
	STAND, ## As they are.
	SIT_AT, ## On a seat along one long side, facing the middle (tables).
	SIT_ON, ## On the object itself, facing its front (toilets, benches).
	LIE, ## On their back, head towards the object's front (beds).
	SHOWER, ## Standing in it, facing out, swaying a little.
	SIT_FACING, ## On a chair in front of it, facing it (desks).
}

## The pose for objects with each tag: [pose, seat height in metres, how
## far from the middle in metres] (for SIT_AT, out to the seats; otherwise
## forwards). Tags not listed stand.
var by_tag := {
	&"bed": [Pose.LIE, 0.55, 0.0],
	&"table": [Pose.SIT_AT, 0.33, 0.46],
	&"toilet": [Pose.SIT_ON, 0.31, 0.02],
	&"bench": [Pose.SIT_ON, 0.45, 0.04],
	&"shower": [Pose.SHOWER, 0.06, 0.05],
	&"chair": [Pose.SIT_ON, 0.32, 0.0],
}

## How high off the floor a sitter's bottom is in the body model.
const SEAT := 0.2
## How far the arms swing forward to carry something, from hanging down.
const CARRY := PI * 0.45
## Where the head is along a lying body, from the feet.
const HEAD := 0.7


## Poses `body` for someone using `placed`, which stands on the floor at
## `floor_y`. `stand` is where they stood before, in tile units, to pick a
## side of a table. Returns false (and leaves the body alone) for objects
## with no pose.
func apply(body: Node3D, placed: BuildingMap.PlacedObject, floor_y: float, stand: Vector2,
		cs: float, need: StringName) -> bool:
	var entry: Array = []
	for tag in placed.def.tags:
		if by_tag.has(tag):
			entry = by_tag[tag]
			break
	if entry.is_empty():
		return false
	var pose: Pose = entry[0]
	var height: float = entry[1]
	var reach: float = entry[2]
	# The object's own frame: its front is local +z, as the models face.
	var turn := Basis(Vector3.UP, -placed.angle)
	var front := turn * Vector3.BACK
	var side := turn * Vector3.RIGHT
	var centre := Vector3(placed.centre.x * cs, floor_y, placed.centre.y * cs)
	var t := Time.get_ticks_msec() * 0.001 + body.get_instance_id() % 97
	match pose:
		Pose.LIE:
			# Feet towards the foot of the bed, head on the pillow, face up.
			var head_at := centre + front * (placed.def.size.y * cs * 0.5 - 0.28)
			body.transform = Transform3D(Basis(front.cross(Vector3.DOWN), front, Vector3.DOWN),
					head_at - front * HEAD + Vector3.UP * height)
			_legs(body, 0.0)
		Pose.SIT_AT:
			# The side nearest where they stood, at the seat nearest along it.
			var from := Vector3(stand.x * cs, floor_y, stand.y * cs) - centre
			var out := front * signf(from.dot(front) if absf(from.dot(front)) > 0.01 else 1.0)
			var along := maxf(placed.def.size.x * cs * 0.5 - 0.63, 0.0) * signf(from.dot(side))
			var seat := centre + out * reach + side * along
			_face(body, -out, seat + Vector3.UP * (height - SEAT))
			_legs(body, PI * 0.5)
			if need == &"hunger":
				body.position.y += absf(sin(t * 6.0)) * 0.012
		Pose.SIT_ON:
			_face(body, front, centre + front * reach + Vector3.UP * (height - SEAT))
			_legs(body, PI * 0.5)
		Pose.SIT_FACING:
			_face(body, -front, centre + front * reach + Vector3.UP * (height - SEAT))
			_legs(body, PI * 0.5)
		Pose.SHOWER:
			_face(body, front, centre + front * reach + Vector3.UP * height)
			body.rotation.z = sin(t * 2.0) * 0.05
			_legs(body, 0.0)
	return true


## Back to standing, as the walking code expects.
func clear(body: Node3D) -> void:
	body.rotation = Vector3(0.0, body.rotation.y, 0.0)
	_legs(body, 0.0)


## Arms out in front to hold something, or back down by their sides.
static func carry(body: Node3D, holding: bool) -> void:
	_swing(body, &"arms", CARRY if holding else 0.0)


func _face(body: Node3D, direction: Vector3, at: Vector3) -> void:
	body.transform = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), at)


func _legs(body: Node3D, swing: float) -> void:
	_swing(body, &"legs", swing)


## Turns every "*_<part>" mesh forward by `swing` about its own pivot.
static func _swing(body: Node3D, part: StringName, swing: float) -> void:
	if not body.has_meta(part):
		var nodes: Array[Node3D] = []
		for node: Node in body.find_children("*_" + part, "Node3D", true, false):
			nodes.append(node as Node3D)
		body.set_meta(part, nodes)
	for node: Node3D in body.get_meta(part):
		node.rotation.x = swing
