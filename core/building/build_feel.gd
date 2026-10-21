class_name BuildFeel
extends Node3D
## The flourishes that make building feel good: objects pop as they land,
## walls rise, floors sweep in, dust puffs up where things come down, and
## each makes its sound. It watches the building for what changed, so
## every tool (and a move or paste) gets them for free.

const DUST := preload("res://core/building/effects/demolish_dust.tscn")
## Effects shown for one change at most, so a big paste stays calm.
const MOST := 30
const RISE_TIME := 0.35
const SWEEP_TIME := 0.3

var building: Building
var terrain: Terrain
var cell_size := 1.0
## (level: int) -> BuildingView, for popping objects.
var view_for: Callable
## () -> bool: whether to show and sound changes now (while building, not
## while the prison runs itself or undo puts things back).
var active: Callable

var _seen: Dictionary[int, Dictionary] = {}
var _material := _make_material()


func start() -> void:
	for n: int in building.levels:
		_seen[n] = _snapshot(building.levels[n])
	building.changed.connect(_on_changed)


func _on_changed() -> void:
	var showing: bool = not active.is_valid() or active.call()
	for n: int in building.levels:
		var map := building.levels[n]
		var now := _snapshot(map)
		if showing and _seen.has(n):
			_show(n, map, _seen[n], now)
		_seen[n] = now


func _snapshot(map: BuildingMap) -> Dictionary:
	var objects := {}
	for placed: BuildingMap.PlacedObject in map.objects.values():
		objects[placed.id] = [placed.centre, placed.def.size, placed.angle]
	return {"objects": objects, "walls": map.walls.duplicate(), "floors": map.floors.duplicate(),
			"paints": map.wall_paints.duplicate(true), "slants": map.slants.size()}


func _show(level: int, map: BuildingMap, before: Dictionary, now: Dictionary) -> void:
	var budget := MOST
	# Objects: a pop for each new one (or one moved), dust where one went.
	var landed: Array[int] = []
	var gone := 0
	for id: int in now.objects:
		if not before.objects.has(id) or before.objects[id] != now.objects[id]:
			landed.append(id)
	for id: int in before.objects:
		if not now.objects.has(id):
			gone += 1
			if budget > 0:
				budget -= 1
				var entry: Array = before.objects[id]
				_dust(map, entry[0], maxf(entry[1].x, entry[1].y))
	if not landed.is_empty():
		var view: BuildingView = view_for.call(level) if view_for.is_valid() else null
		if view != null:
			view.pop(landed)
		Sound.play(&"build_place")
	# Walls: rising where new, dust where knocked down.
	var risen := 0
	var opened := false
	for edge: Vector3i in now.walls:
		if not before.walls.has(edge):
			risen += 1
			if budget > 0:
				budget -= 1
				_rise(map, edge)
		elif before.walls[edge] != now.walls[edge]:
			opened = true
	for edge: Vector3i in before.walls:
		if not now.walls.has(edge):
			gone += 1
			if budget > 0 and gone <= MOST / 2:
				budget -= 1
				var ends := BuildingMap.edge_ends(edge)
				_dust(map, (ends[0] + ends[1]) * 0.5, 1.0)
	# Floors: a sweep over what's new, dust over what's lifted.
	var laid: Array[Vector2i] = []
	var lifted: Array[Vector2i] = []
	for cell: Vector2i in now.floors:
		if not before.floors.has(cell) or before.floors[cell] != now.floors[cell]:
			laid.append(cell)
	for cell: Vector2i in before.floors:
		if not now.floors.has(cell):
			lifted.append(cell)
	if not laid.is_empty():
		_sweep(map, laid)
		Sound.play(&"build_floor")
	if not lifted.is_empty():
		gone += 1
		for i in mini(lifted.size(), budget):
			_dust(map, Vector2(lifted[i]) + Vector2(0.5, 0.5), 1.0)
	if risen > 0 or now.slants > before.slants:
		Sound.play(&"build_wall")
	elif opened:
		Sound.play(&"build_place")
	if gone > 0:
		Sound.play(&"build_remove")
	if now.paints != before.paints:
		Sound.play(&"build_paint")


func _height(map: BuildingMap, point: Vector2) -> float:
	var cell := Vector2i(point.floor())
	if map.has_floor(cell):
		return map.floor_height(cell)
	return terrain.height_at(point) if terrain != null else 0.0


func _dust(map: BuildingMap, point: Vector2, size: float) -> void:
	var dust: Node3D = DUST.instantiate()
	dust.position = Vector3(point.x * cell_size, _height(map, point), point.y * cell_size)
	dust.scale = Vector3.ONE * clampf(size, 0.6, 2.5)
	add_child(dust)


## A pale slab that rises up the new wall and fades.
func _rise(map: BuildingMap, edge: Vector3i) -> void:
	var ends := BuildingMap.edge_ends(edge)
	var middle := (ends[0] + ends[1]) * 0.5
	var def := map.wall_def(map.wall_style(edge))
	var height := def.height if def != null else 1.5
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	var along := ends[1] - ends[0]
	box.size = Vector3(absf(along.x) * cell_size + 0.18, 1.0, absf(along.y) * cell_size + 0.18)
	slab.mesh = box
	slab.material_override = _material.duplicate()
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var base := _height(map, middle - Vector2(along.y, along.x) * 0.25)
	base = minf(base, _height(map, middle + Vector2(along.y, along.x) * 0.25))
	slab.position = Vector3(middle.x * cell_size, base, middle.y * cell_size)
	slab.scale = Vector3(1, 0.01, 1)
	add_child(slab)
	var tween := slab.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(slab, "scale:y", height + 0.04, RISE_TIME)
	tween.parallel().tween_property(slab, "position:y", base + (height + 0.04) * 0.5, RISE_TIME)
	tween.tween_property(slab.material_override, "albedo_color:a", 0.0, 0.2)
	tween.tween_callback(slab.queue_free)


## A pale sheet that spreads over newly laid floor and fades.
func _sweep(map: BuildingMap, cells: Array[Vector2i]) -> void:
	var low := cells[0]
	var high := cells[0]
	for cell in cells:
		low = low.min(cell)
		high = high.max(cell)
	var rect := Rect2(Vector2(low), Vector2(high - low + Vector2i.ONE))
	var sheet := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(rect.size.x * cell_size, 0.04, rect.size.y * cell_size)
	sheet.mesh = plane
	sheet.material_override = _material.duplicate()
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var centre := rect.get_center()
	sheet.position = Vector3(rect.position.x * cell_size, _height(map, centre) + 0.03, centre.y * cell_size)
	sheet.scale = Vector3(0.01, 1, 1)
	add_child(sheet)
	var tween := sheet.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(sheet, "scale:x", 1.0, SWEEP_TIME)
	tween.parallel().tween_property(sheet, "position:x", centre.x * cell_size, SWEEP_TIME)
	tween.tween_property(sheet.material_override, "albedo_color:a", 0.0, 0.25)
	tween.tween_callback(sheet.queue_free)


static func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.98, 0.9, 0.55)
	return material
