class_name Blueprints
extends Node3D
## Building that takes time. Unless building is instant, the floor, walls,
## doors and windows you put down become blueprints: see-through plans
## that shimmer where they'll go, until a handyman comes to build them,
## piece by piece, with a progress bar over the work. They're paid for when
## the handyman starts; until then they can be cancelled with the demolish
## tool for nothing. Planned walls and doors already stop people walking
## through; planned floor is still ground. Objects are always instant.
##
## Plans live in BuildingMap.planned_floors and planned_walls, so saving
## and undo keep them; the jobs are posted afresh from them.

## Game minutes of work for each piece.
const FLOOR_MINUTES := 1.0
const WALL_MINUTES := 3.0
const OPENING_MINUTES := 4.0
## Work is done in stages of about this long, each building its pieces.
const STAGE_MINUTES := 8.0
## Game minutes a job waits before trying again when there's no money.
const MONEY_WAIT := 30.0
const GHOST_COLOUR := Color(0.5, 0.75, 1.0, 0.5)
const BAR_HEIGHT := 2.4

var building: Building
var terrain: Terrain
var jobs: JobBoard
var ledger: Ledger
var build_costs: BuildCosts
var cell_size := 1.0
## Whether things go up the moment they're placed, as before blueprints.
var instant := true
## () -> bool: whether changes now are the player building (and so become
## plans), rather than the prison running or undo putting things back.
var active: Callable
## Set while a handyman's work goes up, so its flourishes show.
var finishing := false

var _seen: Dictionary[int, Dictionary] = {}
var _held := 0
var _busy := false
var _jobs: Dictionary[Vector2i, Job] = {} ## By (level, batch).
var _ghosts: Dictionary[int, MeshInstance3D] = {}
var _bars: Dictionary[Vector2i, Label3D] = {}
var _material := MeshShapes.vertex_colour_material(true)
var _shapes := PreviewShapes.new()
var _redraw_queued := false
var _time := 0.0


func start() -> void:
	for n: int in building.levels:
		_seen[n] = _snapshot(building.levels[n])
	building.changed.connect(_on_changed)
	_shapes.ground_at = func(point: Vector2) -> float: return terrain.height_at(point) if terrain != null else 0.0
	_shapes.wall_height = 1.2
	_queue_redraw()


## Holds plans back while a compound change (a move or paste) is made, so
## it's planned whole when released.
func hold() -> void:
	_held += 1


func release() -> void:
	_held = maxi(_held - 1, 0)
	if _held == 0:
		_on_changed()


## The work still planned in a batch, as cells and edges.
func pieces(level: int, batch: int) -> Array:
	var map := building.levels[level]
	var out: Array = []
	for cell: Vector2i in map.planned_floors:
		if map.planned_floors[cell][2] == batch:
			out.append(cell)
	for edge: Vector3i in map.planned_walls:
		if map.planned_walls[edge][4] == batch:
			out.append(edge)
	return out


## How far a batch is built, from 0 to 1.
func progress(level: int, batch: int) -> float:
	var map := building.levels[level]
	var size: int = map.batch_sizes.get(batch, 0)
	return 1.0 - float(pieces(level, batch).size()) / size if size > 0 else 1.0


## What the rest of a batch costs.
func price(level: int, batch: int) -> int:
	var map := building.levels[level]
	var sum := 0
	for piece: Variant in pieces(level, batch):
		if piece is Vector2i:
			sum += build_costs.floor_price(map.planned_floors[piece][0]) if build_costs != null else 0
		else:
			var entry: Array = map.planned_walls[piece]
			sum += build_costs.wall_entry_price(entry, map.wall_at(piece) == BuildingMap.Wall.NONE) \
					if build_costs != null else 0
	return sum


func _on_changed() -> void:
	if _busy or _held > 0:
		return
	var planning: bool = not instant and (not active.is_valid() or active.call())
	for n: int in building.levels:
		var map := building.levels[n]
		if planning and _seen.has(n):
			_plan(map, _seen[n])
		elif _seen.has(n):
			_refund_cancelled(map, _seen[n])
		_seen[n] = _snapshot(map)
	_sync()
	_queue_redraw()


func _snapshot(map: BuildingMap) -> Dictionary:
	return {"floors": map.floors.duplicate(), "walls": map.walls.duplicate(),
			"styles": map.wall_styles.duplicate(), "windows": map.window_kinds.duplicate(),
			"door_kinds": map.door_kinds.duplicate(), "planned_floors": map.planned_floors.duplicate(true),
			"planned_walls": map.planned_walls.duplicate(true)}


## Turns what was just built into plans, putting the map back as it was.
func _plan(map: BuildingMap, before: Dictionary) -> void:
	var batch := _next_batch()
	var count := 0
	for cell: Vector2i in map.floors.keys():
		var style: StringName = map.floors[cell]
		if before.floors.get(cell) == style:
			continue
		map.planned_floors[cell] = [style, map.floor_height(cell), batch]
		if before.floors.has(cell):
			map.floors[cell] = before.floors[cell]
		else:
			map.floors.erase(cell)
			map.piece_styles.erase(cell)
		count += 1
	for edge: Vector3i in map.walls.keys():
		var entry := [map.walls[edge], map.wall_style(edge), map.window_kinds.get(edge, &""),
				map.door_kinds.get(edge, &""), batch]
		if before.walls.has(edge) and before.walls[edge] == entry[0] \
				and before.styles.get(edge, BuildingMap.DEFAULT_WALL) == entry[1] \
				and before.windows.get(edge, &"") == entry[2] and before.door_kinds.get(edge, &"") == entry[3]:
			continue
		map.planned_walls[edge] = entry
		_put_wall_back(map, edge, before)
		count += 1
	if count == 0:
		return
	map.batch_sizes[batch] = count
	_busy = true
	map.planned_changed()
	_busy = false
	Sound.play(&"build_place")


func _put_wall_back(map: BuildingMap, edge: Vector3i, before: Dictionary) -> void:
	for pair: Array in [[map.walls, before.walls], [map.wall_styles, before.styles],
			[map.window_kinds, before.windows], [map.door_kinds, before.door_kinds]]:
		var now: Dictionary = pair[0]
		var then: Dictionary = pair[1]
		if then.has(edge):
			now[edge] = then[edge]
		else:
			now.erase(edge)
	if not before.walls.has(edge):
		map.wall_paints.erase(edge)


func _next_batch() -> int:
	var top := 0
	for n: int in building.levels:
		for batch: int in building.levels[n].batch_sizes:
			top = maxi(top, batch)
	return top + 1


## Plans taken away (demolished) from a batch already paid for give their
## money back.
func _refund_cancelled(map: BuildingMap, before: Dictionary) -> void:
	if ledger == null or build_costs == null:
		return
	var back := 0
	for cell: Vector2i in before.planned_floors:
		var entry: Array = before.planned_floors[cell]
		if not map.planned_floors.has(cell) and not map.floors.has(cell) and map.paid_batches.has(entry[2]):
			back += build_costs.floor_price(entry[0])
	for edge: Vector3i in before.planned_walls:
		var entry: Array = before.planned_walls[edge]
		if not map.planned_walls.has(edge) and not map.walls.has(edge) and map.paid_batches.has(entry[4]):
			back += build_costs.wall_entry_price(entry)
	if back > 0:
		ledger.add(back, build_costs.line)


## Posts a job for each batch of plans that hasn't one, and takes jobs off
## for batches all built or cancelled.
func _sync() -> void:
	if jobs == null:
		return
	var wanted: Dictionary[Vector2i, bool] = {}
	for n: int in building.levels:
		var map := building.levels[n]
		for cell: Vector2i in map.planned_floors:
			wanted[Vector2i(n, map.planned_floors[cell][2])] = true
		for edge: Vector3i in map.planned_walls:
			wanted[Vector2i(n, map.planned_walls[edge][4])] = true
	for key: Vector2i in _jobs.keys():
		if not wanted.has(key):
			jobs.cancel(_jobs[key])
			_jobs.erase(key)
	for key: Vector2i in wanted:
		if not _jobs.has(key):
			_jobs[key] = jobs.post(_make_job(key.x, key.y))


func _make_job(level: int, batch: int) -> Job:
	var map := building.levels[level]
	var all := pieces(level, batch)
	# Floor first, then walls, then doors and windows.
	all.sort_custom(func(a: Variant, b: Variant) -> bool: return _order(map, a) < _order(map, b))
	var job := Job.new()
	job.kind = &"build"
	job.title = _title(map, all)
	job.priority = 3
	var chunk: Array = []
	var minutes := 0.0
	for i in all.size():
		chunk.append(all[i])
		minutes += _minutes(map, all[i])
		if minutes >= STAGE_MINUTES or i == all.size() - 1:
			var stage := Job.on_tile(Job.Do.WORK, level, _work_tile(map, all, chunk))
			stage.minutes = minutes
			stage.doing = "Building"
			var these := chunk.duplicate()
			stage.finish = func(_stage: Job.Stage, _worker: Person) -> void: _build(level, batch, these)
			job.stages.append(stage)
			chunk = []
			minutes = 0.0
	job.on_done = func(_job: Job) -> void:
		_jobs.erase(Vector2i(level, batch))
		Sound.play(&"build_finished")
	return job


func _order(map: BuildingMap, piece: Variant) -> int:
	if piece is Vector2i:
		return 0
	return 1 if map.planned_walls[piece][0] == BuildingMap.Wall.WALL else 2


func _minutes(map: BuildingMap, piece: Variant) -> float:
	if piece is Vector2i:
		return FLOOR_MINUTES
	var opening: bool = map.planned_walls[piece][0] != BuildingMap.Wall.WALL
	return (OPENING_MINUTES if opening else 0.0) + (WALL_MINUTES if map.wall_at(piece) == BuildingMap.Wall.NONE else 0.0)


func _title(map: BuildingMap, all: Array) -> String:
	var floors := all.filter(func(p: Variant) -> bool: return p is Vector2i).size()
	var walls := all.size() - floors
	if floors > 0 and walls > 0:
		return "Build a room"
	if floors > 0:
		return "Lay some floor"
	var openings := all.filter(func(p: Variant) -> bool:
		return p is Vector3i and map.planned_walls[p][0] != BuildingMap.Wall.WALL).size()
	return "Put in a door or window" if openings == all.size() else "Build some walls"


## Where to stand for some of the work: a tile just outside the whole
## batch (so walls going up don't shut the builder in), nearest the pieces.
func _work_tile(map: BuildingMap, all: Array, chunk: Array) -> Vector2i:
	var low := Vector2i(1 << 30, 1 << 30)
	var high := -low
	var middle := Vector2.ZERO
	for piece: Variant in all:
		var cell := Vector2i(piece.x, piece.y)
		low = low.min(cell)
		high = high.max(cell)
	for piece: Variant in chunk:
		middle += Vector2(piece.x, piece.y) + Vector2(0.5, 0.5)
	middle /= chunk.size()
	var ring := Rect2i(low, high - low + Vector2i.ONE).grow(1)
	var best := ring.position
	var best_distance := INF
	for cell in BuildingMap.cells_in(ring):
		if ring.grow(-1).has_point(cell) or not map.owns(cell) or map.planned_floors.has(cell):
			continue
		var distance := (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(middle)
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


## A stage's pieces go up: the map gets them, already paid for.
func _build(level: int, batch: int, chunk: Array) -> void:
	var map := building.levels[level]
	if not map.paid_batches.has(batch):
		_pay(level, batch)
	_busy = true
	finishing = true
	if build_costs != null:
		build_costs.suspend()
	for piece: Variant in chunk:
		if piece is Vector2i:
			var entry: Array = map.planned_floors.get(piece, [])
			if entry.is_empty() or entry[2] != batch:
				continue
			map.floors[piece] = entry[0]
			map.floor_heights[piece] = entry[1]
			map.planned_floors.erase(piece)
		else:
			var entry: Array = map.planned_walls.get(piece, [])
			if entry.is_empty() or entry[4] != batch:
				continue
			map.walls[piece] = entry[0]
			map.wall_styles[piece] = entry[1]
			if entry[0] == BuildingMap.Wall.WINDOW:
				map.window_kinds[piece] = entry[2]
			else:
				map.window_kinds.erase(piece)
			if entry[0] == BuildingMap.Wall.DOOR and not (entry[3] as StringName).is_empty():
				map.door_kinds[piece] = entry[3]
			else:
				map.door_kinds.erase(piece)
			map.planned_walls.erase(piece)
	if pieces(level, batch).is_empty():
		map.batch_sizes.erase(batch)
		map.paid_batches.erase(batch)
	map.planned_changed()
	if build_costs != null:
		build_costs.resume()
	finishing = false
	_busy = false
	_seen[level] = _snapshot(map)
	_queue_redraw()


## Pays for the rest of a batch as work starts on it. Returns whether it
## could be paid.
func _pay(level: int, batch: int) -> bool:
	var map := building.levels[level]
	if map.paid_batches.has(batch):
		return true
	var cost := price(level, batch)
	if ledger != null and not ledger.can_spend() and cost > 0:
		return false
	if ledger != null and cost > 0:
		ledger.add(-cost, build_costs.line if build_costs != null else "Building")
	map.paid_batches[batch] = true
	return true


func _process(delta: float) -> void:
	_time += delta
	_material.albedo_color.a = 0.75 + 0.25 * sin(_time * 3.0)
	# Work is paid for as a handyman takes it up; without the money it
	# waits.
	for key: Vector2i in _jobs:
		var job := _jobs[key]
		var map: BuildingMap = building.levels.get(key.x)
		if map == null or job.worker == null or map.paid_batches.has(key.y):
			continue
		if not _pay(key.x, key.y):
			var worker := job.worker
			jobs.abandon(worker)
			job.wait = MONEY_WAIT
			job.reason = "Waiting for money"
	_update_bars()


func _update_bars() -> void:
	for key: Vector2i in _bars.keys():
		if not _jobs.has(key):
			_bars[key].queue_free()
			_bars.erase(key)
	for key: Vector2i in _jobs:
		var map: BuildingMap = building.levels.get(key.x)
		if map == null:
			continue
		var bar: Label3D = _bars.get(key)
		if bar == null:
			bar = _make_bar(map, key)
			_bars[key] = bar
		var job := _jobs[key]
		var done := progress(key.x, key.y)
		var filled := roundi(done * 10.0)
		var words := "Building" if job.worker != null else ("Waiting for money" if job.reason == "Waiting for money"
				else "Waiting for a handyman")
		bar.text = "%s\n%s%s" % [words, "▰".repeat(filled), "▱".repeat(10 - filled)]


func _make_bar(map: BuildingMap, key: Vector2i) -> Label3D:
	var all := pieces(key.x, key.y)
	var middle := Vector2.ZERO
	for piece: Variant in all:
		middle += Vector2(piece.x, piece.y) + Vector2(0.5, 0.5)
	middle /= maxi(all.size(), 1)
	var cell := Vector2i(middle.floor())
	var entry: Array = map.planned_floors.get(cell, [])
	var ground: float = entry[1] if not entry.is_empty() else _shapes.ground_at.call(middle)
	var bar := Label3D.new()
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.no_depth_test = true
	bar.render_priority = 3
	bar.pixel_size = 0.006
	bar.font_size = 40
	bar.outline_size = 10
	bar.modulate = Color(0.85, 0.93, 1.0)
	bar.position = Vector3(middle.x * cell_size, ground + BAR_HEIGHT, middle.y * cell_size)
	add_child(bar)
	return bar


func _queue_redraw() -> void:
	if _redraw_queued:
		return
	_redraw_queued = true
	_redraw.call_deferred()


## The see-through plans: floor and walls in a soft blue.
func _redraw() -> void:
	_redraw_queued = false
	if not is_inside_tree():
		return
	for n: int in building.levels:
		var map := building.levels[n]
		var ghost: MeshInstance3D = _ghosts.get(n)
		if ghost == null:
			ghost = MeshInstance3D.new()
			ghost.mesh = ImmediateMesh.new()
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ghost)
			_ghosts[n] = ghost
		var mesh := ghost.mesh as ImmediateMesh
		mesh.clear_surfaces()
		_shapes.clear()
		_shapes.map = map
		_shapes.cell_size = cell_size
		for cell: Vector2i in map.planned_floors:
			_shapes.cells([cell], GHOST_COLOUR, map.planned_floors[cell][1])
		for edge: Vector3i in map.planned_walls:
			_shapes.edge(edge, GHOST_COLOUR)
		if not _shapes.is_empty():
			_shapes.draw(mesh, _material)
