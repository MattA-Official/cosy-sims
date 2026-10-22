class_name UtilityView
extends Node3D
## While the utilities tool is open, shows the cables and pipes on the level
## in view, each kind in its own lane of the tile, and colours everything
## that makes or uses power, water or sewage: green when supplied, amber on
## stores, red when off.

const COLOURS: Dictionary[StringName, Color] = {&"power": Color(0.98, 0.8, 0.25),
		&"water": Color(0.35, 0.65, 0.95), &"sewage": Color(0.6, 0.45, 0.3)}
## Where each kind's lane runs across a tile, from its middle.
const LANES: Dictionary[StringName, float] = {&"power": -0.25, &"water": 0.0, &"sewage": 0.25}
const STATE_COLOURS := {Utilities.Supply.ON: Color(0.45, 0.9, 0.5, 0.55),
		Utilities.Supply.STORES: Color(1.0, 0.75, 0.3, 0.6), Utilities.Supply.OFF: Color(1.0, 0.35, 0.3, 0.6)}
## Seconds between redraws while open, as things switch on and off.
const REFRESH := 1.0

@export var cell_size := 1.0
## How far above the floor the runs sit.
@export var lift := 0.06

var utilities: Utilities
var controller: BuildController:
	set(value):
		controller = value
		controller.tool_changed.connect(func(_tool: BuildController.Tool) -> void: _redraw())
var building: Building:
	set(value):
		building = value
		building.changed.connect(_redraw)
		building.active_changed.connect(func(_level: int) -> void: _redraw())
## (cell: Vector2i) -> float: the ground's height, for runs across open
## ground.
var ground_height: Callable

var _mesh := ImmediateMesh.new()
var _wait := 0.0


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = MeshShapes.vertex_colour_material(true)
	add_child(instance)
	_redraw()


func _process(delta: float) -> void:
	if controller == null or controller.tool != BuildController.Tool.CONDUIT:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH
		_redraw()


func _redraw() -> void:
	if not is_inside_tree() or building == null or controller == null or utilities == null:
		return
	_mesh.clear_surfaces()
	if controller.tool != BuildController.Tool.CONDUIT:
		return
	var level := building.active
	var map := building.levels.get(level) as BuildingMap
	if map == null or (map.conduits.is_empty() and map.objects.is_empty()):
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector2i in map.conduits:
		var height := _height(map, cell) + lift
		for kind: StringName in BuildingMap.CONDUIT_BITS:
			if not map.has_conduit(cell, kind):
				continue
			var lane: float = LANES[kind]
			var node := Vector2(cell) + Vector2(0.5 + lane, 0.5 + lane)
			# A strip towards each side that joins on, so runs read as lines.
			_strip(node, Vector2(0.08, 0.08), height, COLOURS[kind])
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if map.has_conduit(cell + step, kind):
					var half := Vector2(0.25, 0.05) if step.x != 0 else Vector2(0.05, 0.25)
					_strip(node + Vector2(step) * 0.25, half, height, COLOURS[kind])
	for placed: BuildingMap.PlacedObject in map.objects.values():
		var state := utilities.supply_of(level, placed)
		if state == Utilities.Supply.NONE:
			continue
		var top := _height(map, Vector2i(placed.centre.floor())) + placed.def.height + 0.05
		_strip(placed.centre, placed.rect.size * 0.5, top, STATE_COLOURS[state])
	_mesh.surface_end()


func _strip(centre: Vector2, half: Vector2, height: float, colour: Color) -> void:
	MeshShapes.add_box_immediate(_mesh, Vector3(centre.x * cell_size, height, centre.y * cell_size),
			Vector3(half.x, 0.01, half.y) * cell_size, colour)


func _height(map: BuildingMap, cell: Vector2i) -> float:
	if map.has_floor(cell):
		return map.floor_height(cell)
	return ground_height.call(cell) if ground_height.is_valid() else 0.0
