class_name ItemView
extends Node3D
## Draws items: stacked on top of whatever holds them, piled on the floor,
## and held in front of whoever carries them. Items without a model show
## as small boxes of their colour. Piles show a few items at most, however
## many there are.

## The most shown in one pile, in layers of four.
const SHOWN := 8
## Half the size of an item drawn as a box.
const BOX := Vector3(0.11, 0.06, 0.09)
## Where a carried item sits on someone, in their body's frame (which faces
## -z): on their hands, held out in front.
const HELD_AT := Vector3(0.0, 0.47, -0.2)

@export var cell_size := 1.0

var items: ItemStore:
	set(value):
		items = value
		items.changed.connect(func() -> void: _dirty = true)
var people: People
var building: Building:
	set(value):
		building = value
		building.changed.connect(func() -> void: _dirty = true)
		building.active_changed.connect(func(_level: int) -> void: _dirty = true)

var _dirty := true
var _mesh := ImmediateMesh.new()
var _models := Node3D.new()
var _carried: Dictionary[Person, Node3D] = {}
var _material := MeshShapes.vertex_colour_material()


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.material_override = _material
	add_child(instance)
	add_child(_models)


func _process(_delta: float) -> void:
	if items == null or building == null:
		return
	if _dirty:
		_dirty = false
		_redraw()
	_place_carried()


func _redraw() -> void:
	_mesh.clear_surfaces()
	for child in _models.get_children():
		child.queue_free()
	var drawn := false
	for key: Vector2i in items.held:
		var map := building.levels.get(key.x) as BuildingMap
		var placed: BuildingMap.PlacedObject = map.objects.get(key.y) if map != null else null
		if placed == null or key.x > building.active:
			continue
		var top := map.floor_height(Vector2i(placed.centre.floor())) + placed.def.height
		drawn = _pile(items.held[key], Vector3(placed.centre.x, top, placed.centre.y), drawn)
	for key: Vector3i in items.on_floor:
		if key.x > building.active:
			continue
		var spot := Vector2(key.y, key.z) + Vector2(0.5, 0.5)
		var height := people.nav().height_at(key.x, spot) if people != null else NAN
		drawn = _pile(items.on_floor[key], Vector3(spot.x, 0.0 if is_nan(height) else height, spot.y), drawn)
	if drawn:
		_mesh.surface_end()


## Draws up to SHOWN items standing on `base`, in tile units with metres
## up. Returns whether a surface is open.
func _pile(pile: Dictionary, base: Vector3, drawn: bool) -> bool:
	var i := 0
	for item: ItemDef in pile:
		for n in mini(pile[item], SHOWN - i):
			var corner := Vector2(-1.0 if i % 2 == 0 else 1.0, -1.0 if (i / 2) % 2 == 0 else 1.0)
			var at := Vector3((base.x + corner.x * BOX.x * 1.15) * cell_size,
					base.y + BOX.y * (2 * (i / 4) + 1), (base.z + corner.y * BOX.z * 1.15) * cell_size)
			if item.model != null:
				var model := item.model.instantiate() as Node3D
				model.position = at - Vector3.UP * BOX.y
				_models.add_child(model)
			else:
				if not drawn:
					_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
					drawn = true
				MeshShapes.add_box_immediate(_mesh, at, BOX, item.colour)
			i += 1
		if i >= SHOWN:
			break
	return drawn


## Keeps a carried item in front of each carrier, following their body.
func _place_carried() -> void:
	for person: Person in _carried.keys():
		if not items.carried.has(person) or _carried[person].get_meta(&"item") != items.carrying(person):
			_carried[person].queue_free()
			_carried.erase(person)
			var held_by := people.body_of(person) if people != null else null
			if held_by != null:
				PersonPoses.carry(held_by, false)
	for person: Person in items.carried:
		var body := people.body_of(person) if people != null else null
		if body == null:
			continue
		if not _carried.has(person):
			_carried[person] = _held_node(items.carrying(person))
			add_child(_carried[person])
			PersonPoses.carry(body, true)
		var node := _carried[person]
		node.visible = body.visible
		node.global_transform = Transform3D(Basis(Vector3.UP, body.rotation.y),
				body.global_position + Basis(Vector3.UP, body.rotation.y) * HELD_AT)


func _held_node(item: ItemDef) -> Node3D:
	var node: Node3D
	if item.model != null:
		node = item.model.instantiate() as Node3D
	else:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = BOX * 2.0
		var material := StandardMaterial3D.new()
		material.albedo_color = item.colour
		mesh.material = material
		box.mesh = mesh
		node = box
	node.set_meta(&"item", item)
	return node
