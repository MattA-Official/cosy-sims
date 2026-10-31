extends SceneTree
## Headless checks for the airport game and the core pieces it added
## (one-way doors, double-height rooms, queues, signs, movers, belts,
## licences). Quicker than the full suite. Run from the project folder with:
##   godot --headless -s res://tests/airport_tests.gd

var _failures := 0


func _process(_delta: float) -> bool:
	_test_one_way_doors()
	_test_double_height()
	_test_licences()
	_test_queue_lines()
	_test_signage()
	_test_movers()
	if _failures == 0:
		print("All airport tests passed.")
	quit(1 if _failures > 0 else 0)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _test_one_way_doors() -> void:
	var building := Building.new(Rect2i(0, 0, 30, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var ground := building.ground()
	ground.build_room(Rect2i(2, 2, 4, 4), &"concrete", &"brick", 0.0)
	ground.build_room(Rect2i(6, 2, 4, 4), &"concrete", &"brick", 0.0)
	var edge := BuildingMap.edge_between(Vector2i(5, 3), Vector2i(6, 3))
	ground.set_door(edge, true)
	_check(ground.door_way(edge) == 0, "doors start two-way")
	_check(ground.set_door_way(edge, BuildingMap.way_from(edge, Vector2i(5, 3))), "a door turns one-way")
	_check(ground.passable_from(edge, Vector2i(5, 3)) and not ground.passable_from(edge, Vector2i(6, 3)),
			"a one-way door lets people through one way only")
	var graph := NavGraph.build(building)
	var west := Vector2(3.5, 3.5)
	var east := Vector2(8.5, 3.5)
	_check(not graph.find_path(0, west, 0, east).is_empty(), "people walk through a one-way door its way")
	_check(graph.find_path(0, east, 0, west).is_empty(), "nobody walks back through a one-way door")
	graph.set_door_locked(0, edge, true)
	_check(graph.find_path(0, west, 0, east).is_empty(), "a locked one-way door stops everyone")
	graph.set_door_locked(0, edge, false)
	_check(not graph.find_path(0, west, 0, east).is_empty() and graph.find_path(0, east, 0, west).is_empty(),
			"unlocked, it is one-way again")
	# Out of a room onto open ground, through a one-way exit.
	var exit := BuildingMap.edge_between(Vector2i(8, 5), Vector2i(8, 6))
	ground.set_door(exit, true)
	ground.set_door_way(exit, BuildingMap.way_from(exit, Vector2i(8, 6)))
	graph = NavGraph.build(building)
	var outside := Vector2(8.5, 12.5)
	_check(not graph.find_path(0, outside, 0, east).is_empty(), "in from the ground through a one-way door")
	ground.set_door_way(exit, BuildingMap.way_from(exit, Vector2i(8, 5)))
	graph = NavGraph.build(building)
	_check(not graph.find_path(0, east, 0, outside).is_empty() and graph.find_path(0, outside, 0, east).is_empty(),
			"flipped, the exit only lets people out")
	ground.set_door_way(exit, 0)
	graph = NavGraph.build(building)
	_check(not graph.find_path(0, outside, 0, east).is_empty(), "two-way again")
	# Saved and loaded, and gone with the door.
	var data := building.to_data()
	var copy := Building.new(Rect2i(0, 0, 30, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	copy.load_data(data, PrisonCatalogue.object)
	_check(copy.ground().door_way(edge) == ground.door_way(edge), "one-way doors are saved")
	ground.set_door(edge, false)
	_check(ground.door_way(edge) == 0 and not ground.door_ways.has(edge), "filling a door in forgets its way")
	# A one-way gate in a fence on open ground.
	var yard := Building.new(Rect2i(0, 0, 20, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var fence: Array[Vector3i] = []
	for z in range(0, 20):
		fence.append(BuildingMap.edge_between(Vector2i(9, z), Vector2i(10, z)))
	yard.ground().build_walls(fence, &"fence")
	var gate := BuildingMap.edge_between(Vector2i(9, 10), Vector2i(10, 10))
	yard.ground().set_door(gate, true)
	yard.ground().set_door_way(gate, BuildingMap.way_from(gate, Vector2i(9, 10)))
	graph = NavGraph.build(yard)
	_check(not graph.find_path(0, Vector2(4.5, 10.5), 0, Vector2(15.5, 10.5)).is_empty()
			and graph.find_path(0, Vector2(15.5, 10.5), 0, Vector2(4.5, 10.5)).is_empty(),
			"a one-way gate on open ground")


func _test_double_height() -> void:
	var building := Building.new(Rect2i(0, 0, 30, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var ground := building.ground()
	ground.build_room(Rect2i(2, 2, 8, 6), &"concrete", &"brick", 0.0)
	var up := building.level(1)
	up.build_room(Rect2i(2, 2, 8, 6), &"wood", &"brick", Building.STOREY)
	var hall: Array[Vector2i] = []
	for cell in BuildingMap.cells_in(Rect2i(2, 2, 5, 6)):
		hall.append(cell)
	_check(building.set_void(1, hall) == 30, "tiles upstairs become a void")
	_check(not up.has_floor(Vector2i(3, 3)) and up.has_floor(Vector2i(8, 3)), "a void takes the floor away")
	_check(building.is_double_height(0, Vector2i(3, 3)) and not building.is_double_height(0, Vector2i(8, 3)),
			"the room below is double height under the void")
	up.fill_floor(Rect2i(3, 3, 1, 1), &"wood", Building.STOREY)
	_check(not up.has_floor(Vector2i(3, 3)), "no floor goes on a void")
	_check(building.set_void(0, hall) == 0, "the ground floor can't be a void")
	var graph := NavGraph.build(building)
	_check(graph.point_at(1, Vector2(3.5, 3.5)) == -1, "nobody stands on a void")
	_check(graph.point_at(1, Vector2(8.5, 3.5)) != -1, "the mezzanine beside it is still floor")
	var mezzanine := up.room_at(Vector2i(8, 3))
	_check(mezzanine != null and mezzanine.indoor, "a mezzanine round a void is still indoors")
	var data := building.to_data()
	var copy := Building.new(Rect2i(0, 0, 30, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	copy.load_data(data, PrisonCatalogue.object)
	_check(copy.is_double_height(0, Vector2i(3, 3)) and not copy.level(1).has_floor(Vector2i(3, 3)),
			"voids are saved")
	_check(building.set_void(1, hall, false) == 30, "voids fill back in")
	up.fill_floor(Rect2i(3, 3, 1, 1), &"wood", Building.STOREY)
	_check(up.has_floor(Vector2i(3, 3)) and not building.is_double_height(0, Vector2i(3, 3)),
			"floor goes back once the void is gone")


func _test_licences() -> void:
	var board := JobBoard.new()
	var role := StaffRoleDef.new()
	role.id = &"ramp_agent"
	role.job_kinds = [&"tow"]
	board.roles[role.id] = role
	var person := Person.new()
	person.role = &"ramp_agent"
	var job := Job.new()
	job.kind = &"tow"
	_check(board.may_take(person, job), "a job with no licence needs none")
	job.licence = &"airside_driving"
	_check(not board.may_take(person, job), "no licence, no tug")
	var course := CourseDef.new()
	course.id = &"airside_driving_course"
	course.licence = &"airside_driving"
	_check(Licences.pass_course(person, course) and Licences.has(person, &"airside_driving"),
			"passing the course gives its licence")
	_check(board.may_take(person, job), "licensed, they take the job")
	_check(not Licences.pass_course(person, course), "a second pass gives nothing new")
	role.licence = &"screener"
	_check(not board.may_take(person, job), "a role can need a licence for all its work")
	Licences.grant(person, &"screener")
	_check(board.may_take(person, job) and Licences.held(person).size() == 2, "both licences held")
	Licences.revoke(person, &"airside_driving")
	_check(not board.may_take(person, job), "a revoked licence stops the work")


func _test_queue_lines() -> void:
	var line := QueueLine.along(PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(3, 3)]))
	var people: Array[Person] = []
	for i in 6:
		people.append(Person.new())
		_check(line.join(people[i]) == i, "people join at the back, in order")
	_check(line.join(people[2]) == 2, "joining again keeps your place")
	_check(line.spot(0) == Vector2(0, 0) and line.spot(4).is_equal_approx(Vector2(3, 0)),
			"the line runs back along its route")
	_check(line.spot(5).is_equal_approx(Vector2(3, 0.75)), "and turns the corner at a post")
	_check(line.room() == 9 and not line.overflowing(), "nine fit along six tiles of posts")
	_check(line.spot(12).is_equal_approx(Vector2(3, 6)), "past the last post it carries straight on")
	_check(line.serve() == people[0] and line.index_of(people[1]) == 0, "the front is served and everyone moves up")
	line.leave(people[3])
	_check(line.index_of(people[4]) == 2 and line.size() == 4, "leaving lets those behind move up")
	# Posts laid on the floor make the route.
	var map := BuildingMap.new(Rect2i(0, 0, 20, 20))
	map.fill_floor(Rect2i(0, 0, 20, 20))
	var post := ObjectDef.new()
	post.id = &"queue_post"
	post.size = Vector2(0.25, 0.25)
	post.snap = ObjectDef.Snap.FREE
	post.tags = [&"queue_post"]
	for spot in [Vector2(5.5, 3.5), Vector2(5.5, 5.5), Vector2(7.5, 5.5), Vector2(7.5, 3.5), Vector2(15.5, 15.5)]:
		map.place_object_at(post, spot, 0.0)
	var route := QueueLine.posted_route(map, Vector2(5.5, 1.5))
	_check(route.size() == 5 and route[1] == Vector2(5.5, 3.5) and route[4] == Vector2(7.5, 3.5),
			"posts chain into a snaking route, nearest first")
	_check(not route.has(Vector2(15.5, 15.5)), "a post far off is left out")
	_check(QueueLine.posted_route(map, Vector2(15.5, 1.5)).size() == 1, "no posts near, just the front")


func _test_signage() -> void:
	var building := Building.new(Rect2i(0, 0, 30, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var ground := building.ground()
	ground.build_room(Rect2i(2, 2, 6, 6), &"concrete", &"brick", 0.0)
	ground.build_room(Rect2i(8, 2, 6, 6), &"concrete", &"brick", 0.0)
	ground.set_door(BuildingMap.edge_between(Vector2i(7, 4), Vector2i(8, 4)), true)
	ground.set_room_type(ground.room_at(Vector2i(10, 4)), &"gate")
	var signage := Signage.new()
	signage.building = building
	var person := Person.new()
	person.group = &"passenger"
	person.position = Vector3(3.5, 0.0, 3.5)
	_check(not signage.knows_way(person, &"gate"), "with no sign, a newcomer doesn't know the way")
	var staff := Person.new()
	staff.group = &"staff"
	staff.position = person.position
	_check(signage.knows_way(staff, &"gate"), "staff know their way about")
	var sign := ObjectDef.new()
	sign.id = &"sign_gates"
	sign.size = Vector2(0.5, 0.25)
	sign.snap = ObjectDef.Snap.FREE
	sign.signs_to = [&"gate", &"toilet"]
	var placed := ground.place_object_at(sign, Vector2(5.0, 3.0), 0.0)
	_check(signage.signs_seen(0, person.flat()).size() == 1, "they see the sign in their room")
	_check(signage.knows_way(person, &"gate") and not signage.knows_way(person, &"check_in"),
			"a sign shows the way only to what it says")
	person.position = Vector3(10.5, 0.0, 4.5)
	_check(signage.signs_seen(0, person.flat()).is_empty() and signage.knows_way(person, &"gate"),
			"in the gate room, the gate is in sight")
	ground.remove_object(placed)
	person.position = Vector3(3.5, 0.0, 3.5)
	_check(not signage.knows_way(person, &"gate"), "sign gone, lost again")
	Signage.learn(person, &"gate")
	_check(signage.knows_way(person, &"gate"), "once found, a place needs no sign")
	# Out on open ground, signs within sight count.
	var outside := Person.new()
	outside.group = &"passenger"
	outside.position = Vector3(20.5, 0.0, 12.5)
	ground.fill_floor(Rect2i(23, 11, 2, 2))
	ground.place_object_at(sign, Vector2(24.0, 12.0), 0.0)
	_check(signage.knows_way(outside, &"toilet"), "a sign across open ground is seen")
	outside.position = Vector3(1.5, 0.0, 18.5)
	_check(not signage.knows_way(outside, &"toilet"), "but not from far off")


func _mover_def(id: StringName, connects: ObjectDef.Connects, length: float, way: int) -> ObjectDef:
	var def := ObjectDef.new()
	def.id = id
	def.size = Vector2(1, length)
	def.connects = connects
	def.mover_way = way
	def.mover_speed = 2.0
	return def


func _test_movers() -> void:
	var building := Building.new(Rect2i(0, 0, 30, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	var ground := building.ground()
	ground.build_room(Rect2i(2, 2, 6, 12), &"concrete", &"brick", 0.0)
	var up := building.level(1)
	up.build_room(Rect2i(2, 2, 6, 12), &"wood", &"brick", Building.STOREY)
	var escalator := _mover_def(&"escalator_up", ObjectDef.Connects.ESCALATOR, 4, 1)
	var id := ground.place_object_at(escalator, Vector2(3.5, 6.0), 0.0)
	_check(id != 0, "an escalator goes down on the floor")
	_check(not up.has_floor(Vector2i(3, 5)) and up.holes.has(Vector2i(3, 7)) and up.has_floor(Vector2i(3, 9)),
			"it opens the floor above it, like stairs")
	var mover := Movers.of(0, ground.objects[id])
	_check(mover.foot.is_equal_approx(Vector2(3.5, 3.5)) and mover.head.is_equal_approx(Vector2(3.5, 8.5))
			and mover.head_level == 1, "it runs from its foot to its head a level up")
	var graph := NavGraph.build(building)
	var climb := graph.find_path(0, Vector2(3.5, 2.5), 1, Vector2(3.5, 11.5))
	_check(not climb.is_empty(), "people ride the escalator up")
	_check(climb.any(func(p: Vector3) -> bool: return graph.pace_towards(p) > 1.0), "riding is quicker than walking")
	_check(graph.find_path(1, Vector2(3.5, 11.5), 0, Vector2(3.5, 2.5)).is_empty(), "nobody walks down the up escalator")
	var stepped_on_side := false
	for p in climb:
		if p.x > 3.0 and p.x < 4.0 and p.z > 4.2 and p.z < 7.8 and graph.pace_towards(p) == 1.0:
			stepped_on_side = true
	_check(not stepped_on_side, "nobody walks across the escalator's side")
	var down := _mover_def(&"escalator_down", ObjectDef.Connects.ESCALATOR, 4, -1)
	ground.place_object_at(down, Vector2(5.5, 6.0), 0.0)
	graph = NavGraph.build(building)
	_check(not graph.find_path(1, Vector2(5.5, 11.5), 0, Vector2(5.5, 2.5)).is_empty(), "and down the down one")
	# A travelator on one floor.
	var hall := Building.new(Rect2i(0, 0, 30, 20), PrisonCatalogue.FLOORS, PrisonCatalogue.WALLS)
	hall.ground().build_room(Rect2i(2, 2, 3, 16), &"concrete", &"brick", 0.0)
	var walkway := _mover_def(&"travelator", ObjectDef.Connects.TRAVELATOR, 10, 1)
	hall.ground().place_object_at(walkway, Vector2(3.5, 9.0), 0.0)
	graph = NavGraph.build(hall)
	var along := graph.find_path(0, Vector2(3.5, 2.5), 0, Vector2(3.5, 16.5))
	_check(along.any(func(p: Vector3) -> bool: return graph.pace_towards(p) > 1.0), "people take the travelator its way")
	var back := graph.find_path(0, Vector2(3.5, 16.5), 0, Vector2(3.5, 2.5))
	_check(not back.is_empty() and back.all(func(p: Vector3) -> bool: return graph.pace_towards(p) == 1.0),
			"and walk beside it the other way")
