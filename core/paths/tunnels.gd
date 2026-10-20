class_name Tunnels
extends Node3D
## Draws a tunnel mouth in a grassy bank wherever a road leaves your land,
## so vehicles come and go out of sight rather than from nowhere.

var roads: Roads:
	set(value):
		roads = value
		roads.paths.changed.connect(queue_rebuild)
		queue_rebuild()
var cell_size := 1.0
## (point: Vector2) -> float: the ground's height at a point in tiles.
var ground_at: Callable
## The tunnel mouth, facing +Z (towards the land) with the bank behind,
## and its opening at the origin. Without one a plain stand-in is drawn.
var model: PackedScene
var stone := Color(0.62, 0.6, 0.56)
var bank := Color(0.45, 0.62, 0.36)
var dark := Color(0.08, 0.08, 0.09)

var _queued := false


func queue_rebuild() -> void:
	if _queued:
		return
	_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_queued = false
	for child in get_children():
		child.queue_free()
	if roads == null:
		return
	for node in roads.edge_nodes():
		var at: Vector2 = roads.paths.nodes[node]
		var out := roads.outward(node)
		var mouth := model.instantiate() as Node3D if model != null else _stand_in()
		var height: float = ground_at.call(at) if ground_at.is_valid() else 0.0
		mouth.position = Vector3(at.x * cell_size, height, at.y * cell_size)
		# +Z faces back along the road, into the land.
		mouth.rotation.y = atan2(-out.x, -out.y)
		add_child(mouth)


## Stone portal round a dark opening, set in a grassy bank.
func _stand_in() -> Node3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := cell_size
	# The bank reaches back from the portal, over the hidden end of the road.
	MeshShapes.add_box(st, Vector3(0, 1.6, -3.2) * c, Vector3(3.6, 1.6, 3.0) * c, bank)
	MeshShapes.add_box(st, Vector3(0, 1.45, -0.15) * c, Vector3(2.4, 1.45, 0.2) * c, stone)
	# The opening, a little in front of the stone so it shows.
	MeshShapes.add_box(st, Vector3(0, 0.95, 0.02) * c, Vector3(1.75, 0.95, 0.06) * c, dark)
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = MeshShapes.vertex_colour_material()
	var holder := Node3D.new()
	holder.add_child(mesh)
	return holder
