class_name SamplePrisons
## Ready-made prisons to start from, each testing a different part of how
## people find their way: stairs and lifts, slopes, water, long winding
## routes, basements, crowds, and places nobody can reach. Pick one on the
## Main node (Sample) or from the F3 inspector.

const NAMES: Array[String] = ["Starter block", "Two storeys", "Hillside", "Island", "Long way round",
		"Basement", "Crowded canteen", "Locked out", "Staff wing", "Kitchen"]

## What each one tests, shown in the inspector.
const CHALLENGES: Array[String] = [
	"Doors, a corridor and a fenced yard on flat ground.",
	"Cells upstairs, the canteen and showers downstairs: up and down by the stairs or the lift.",
	"Three terraces 2 m apart, with banks too steep to climb: path stairs join the bottom two, a long ramp the top two.",
	"The cells are on an island in a moat. One bridge crosses it, and nobody swims.",
	"A corridor that doubles back on itself, and showers behind an angled wall with a door in it.",
	"The canteen and showers are in the basement, down stairs that turn at a landing.",
	"Twenty-four hungry prisoners, a dorm of sixteen beds, two tables and two showers: they queue, give up and try again.",
	"The showers have no door, and the canteen is 0.75 m up. With Door Steps on its door gets steps; with it off, nobody can eat.",
	"A staff room behind a staff door and an office zoned staff only: staff come and go, prisoners keep out.",
	"The staff wing with a kitchen: the morning lorry's crates go to the fridge, the cook fills the serving counter before each meal, and prisoners take a tray to a table.",
]

## Set before reloading the scene to start in a different sample.
static var next := -1


## Everything a sample builds on.
class Site:
	var building: Building
	var terrain: Terrain
	var water: WaterLayer
	var foliage: FoliageLayer
	var paths: PathNetwork
	var people: People

	func land() -> Rect2i:
		return building.land[0]

	func map(n := 0) -> BuildingMap:
		return building.level(n)


## Shapes the land and builds a sample by its index; -1 leaves the land
## empty. Returns false for an unknown index.
static func build(index: int, site: Site) -> bool:
	match index:
		-1:
			_landscape(site)
			_plant(site, false)
		0: _starter(site)
		1: _two_storeys(site)
		2: _hillside(site)
		3: _island(site)
		4: _long_way_round(site)
		5: _basement(site)
		6: _crowded(site)
		7: _locked_out(site)
		8: _staff_wing(site)
		9: _staff_wing(site, true)
		_: return false
	return true


#region Samples

static func _starter(site: Site) -> void:
	_landscape(site)
	var o := site.land().get_center() - Vector2i(8, 7)
	SampleLayout.build(site.map(), o)
	StartingLandscape.plant(site.foliage, site.terrain, site.map(), o)
	for i in 6:
		site.people.add_person(0, Vector2(o) + Vector2(1.5 + i * 1.7, 3.5 + (i % 2)))


static func _two_storeys(site: Site) -> void:
	_landscape(site)
	var o := site.land().get_center() - Vector2i(7, 5)
	var ground := site.map()
	var up := site.map(1)
	# Downstairs: a day room under the cells, a corridor with the stairs at
	# one end and a lift at the other, and the canteen and showers.
	_room(ground, Rect2i(o, Vector2i(14, 4)), &"wood")
	_room(ground, Rect2i(o + Vector2i(0, 4), Vector2i(14, 2)))
	_room(ground, Rect2i(o + Vector2i(0, 6), Vector2i(7, 5)), &"wood", &"brick", &"canteen")
	_room(ground, Rect2i(o + Vector2i(7, 6), Vector2i(7, 5)), &"tiles", &"brick", &"shower")
	_door(ground, o + Vector2i(6, 4), Vector2i.UP)
	_door(ground, o + Vector2i(3, 6), Vector2i.UP)
	_door(ground, o + Vector2i(10, 6), Vector2i.UP)
	_door(ground, o + Vector2i(0, 5), Vector2i.LEFT)
	_tables(ground, o + Vector2i(1, 7), 2, 2)
	_showers(ground, o + Vector2i(8, 9), 4)
	# Along the corridor's lower row, clear of the doors, so the stairwell
	# upstairs leaves the landing in front of every cell.
	var route: Array[Vector2i] = [o + Vector2i(4, 5), o + Vector2i(5, 5), o + Vector2i(6, 5)]
	ground.add_stairs(Staircase.create(route, [false, false, false] as Array[bool], false, &"concrete"))
	var lift := PrisonCatalogue.object(&"lift")
	ground.place_object(lift, Vector2(o + Vector2i(13, 4)), 0)
	# Upstairs: four cells off a landing.
	_room(up, Rect2i(o + Vector2i(0, 4), Vector2i(14, 2)), &"concrete", &"brick", &"", Building.STOREY)
	up.place_object(lift, Vector2(o + Vector2i(13, 4)), 0)
	for i in 4:
		var cell := o + Vector2i(1 + i * 3, 0)
		_cell(up, Rect2i(cell, Vector2i(3, 4)), Building.STOREY)
		_door(up, cell + Vector2i(1, 3), Vector2i.DOWN)
	_plant(site)
	for i in 8:
		site.people.add_person(1, Vector2(o) + Vector2(4.5 + i, 4.5))


static func _hillside(site: Site) -> void:
	var land := site.land()
	# Flat terraces 2 m apart, with one-tile banks between them.
	var steps: Array[int] = [land.position.y + 16, land.position.y + 32]
	var terrace := func(corner: Vector2i) -> float:
		var h := 0.0
		for z in steps:
			if corner.y > z:
				h += 2.0
		return h
	_landscape(site, terrace)
	var ground := site.map()
	var x := land.position.x
	var low := land.position.y
	# Bottom: the canteen. Middle: the showers. Top: the cells.
	var canteen := Rect2i(x + 8, low + 6, 9, 5)
	_room(ground, canteen, &"wood", &"brick", &"canteen")
	_door(ground, Vector2i(canteen.position.x + 4, canteen.end.y - 1), Vector2i.DOWN)
	_tables(ground, canteen.position + Vector2i(1, 1), 3, 2)
	var showers := Rect2i(x + 10, steps[0] + 5, 6, 4)
	_room(ground, showers, &"tiles", &"brick", &"shower", 2.0)
	_door(ground, Vector2i(showers.position.x + 2, showers.position.y), Vector2i.UP)
	_door(ground, Vector2i(showers.end.x - 1, showers.position.y + 2), Vector2i.RIGHT)
	_showers(ground, showers.position + Vector2i(0, 3), 4)
	var block := Rect2i(x + 20, steps[1] + 5, 12, 5)
	for i in 4:
		_cell(ground, Rect2i(block.position + Vector2i(i * 3, 2), Vector2i(3, 3)), 4.0, true)
		_door(ground, block.position + Vector2i(i * 3 + 1, 2), Vector2i.UP)
	_room(ground, Rect2i(block.position, Vector2i(12, 2)), &"concrete", &"brick", &"", 4.0)
	_door(ground, block.position, Vector2i.LEFT)
	# Stairs up the lower bank, and a long ramp across the upper one.
	var foot := Vector2(x + 12.5, steps[0] - 1.5)
	var head := Vector2(x + 12.5, steps[0] + 2.5)
	site.paths.add_segment(Vector2(x + 12.5, canteen.end.y + 1.5), Vector2(x + 2.5, canteen.end.y + 1.5),
			Vector2(x + 2.5 + 3.0, canteen.end.y + 4.5), &"gravel")
	site.paths.add_segment(Vector2(x + 12.5, canteen.end.y + 1.5), foot, null, &"gravel")
	site.paths.add_segment(foot, head, null, &"paving", true)
	site.paths.add_segment(head, Vector2(x + 12.5, showers.position.y - 0.5), null, &"gravel")
	var ramp_start := Vector2(showers.end.x + 2.5, showers.position.y + 2.5)
	var ramp_end := Vector2(block.position.x - 2.5, block.position.y + 0.5)
	site.paths.add_segment(Vector2(showers.end.x + 0.5, showers.position.y + 2.5), ramp_start, null, &"gravel")
	site.paths.add_segment(ramp_start, ramp_end, Vector2(ramp_start.x + 6.0, ramp_end.y - 1.0), &"paving",
			true)
	site.paths.add_segment(ramp_end, Vector2(block.position.x - 0.5, block.position.y + 0.5), null, &"gravel")
	_plant(site)
	for i in 6:
		site.people.add_person(0, Vector2(block.position) + Vector2(1.5 + i * 1.6, 0.5 + (i % 2)))


static func _island(site: Site) -> void:
	var middle := Vector2(site.land().get_center())
	# A ring of water round a dry island in the middle of the land.
	var moat := func(corner: Vector2i) -> float:
		var d := Vector2(corner).distance_to(middle)
		return -1.2 * (smoothstep(5.5, 6.5, d) - smoothstep(9.0, 10.0, d))
	_landscape(site, moat)
	site.water.fill_at(Vector2i(middle) + Vector2i(8, 0))
	var ground := site.map()
	var c := Vector2i(middle)
	for i in 2:
		var cell := c + Vector2i(-3 + i * 3, -4)
		_cell(ground, Rect2i(cell, Vector2i(3, 3)))
		_door(ground, cell + Vector2i(1, 2), Vector2i.DOWN)
	var corridor := Rect2i(c + Vector2i(-3, -1), Vector2i(6, 2))
	_room(ground, corridor)
	_door(ground, c + Vector2i(0, 0), Vector2i.DOWN)
	# The mainland: canteen and showers south of the moat.
	var canteen := Rect2i(c + Vector2i(-8, 12), Vector2i(8, 5))
	var showers := Rect2i(c + Vector2i(0, 12), Vector2i(6, 5))
	_room(ground, canteen, &"wood", &"brick", &"canteen")
	_room(ground, showers, &"tiles", &"brick", &"shower")
	_door(ground, canteen.position + Vector2i(5, 0), Vector2i.UP)
	_door(ground, showers.position + Vector2i(2, 0), Vector2i.UP)
	_tables(ground, canteen.position + Vector2i(1, 2), 2, 2)
	_showers(ground, showers.position + Vector2i(0, 4), 4)
	var shore := middle + Vector2(0.5, 10.5)
	site.paths.add_segment(middle + Vector2(0.5, 2.5), middle + Vector2(0.5, 4.5), null, &"gravel")
	site.paths.add_segment(middle + Vector2(0.5, 4.5), shore, null, &"paving", true)
	site.paths.add_segment(shore, middle + Vector2(-2.5, 11.5), null, &"gravel")
	site.paths.add_segment(shore, middle + Vector2(2.5, 11.5), null, &"gravel")
	_plant(site)
	# One for each bed: two shared cells.
	for i in 4:
		site.people.add_person(0, middle + Vector2(-1.5 + i, -0.5 + (i % 2)))


static func _long_way_round(site: Site) -> void:
	_landscape(site)
	var ground := site.map()
	var area := Rect2i(site.land().get_center() - Vector2i(10, 6), Vector2i(20, 13))
	var x := area.position.x
	var z := area.position.y
	ground.fill_floor(area, &"concrete")
	ground.build_walls(BuildingMap.rect_perimeter(area), &"brick")
	# Three long walls make a corridor that doubles back: out of the cells,
	# left along the first stretch, then right along the second.
	for row: int in [3, 6, 9]:
		ground.build_walls(BuildingMap.edges_on_line(Vector2i(x, z + row), Vector2i(area.end.x, z + row)), &"brick")
	for i in 4:
		ground.build_walls(BuildingMap.edges_on_line(Vector2i(x + 3 + i * 3, z), Vector2i(x + 3 + i * 3, z + 3)),
				&"brick")
		ground.set_door(Vector3i(x + 1 + i * 3, z + 3, BuildingMap.EDGE_X), true)
		ground.place_object(PrisonCatalogue.object(&"bed"), Vector2(x + i * 3, z), 0)
		ground.place_object(PrisonCatalogue.object(&"toilet"), Vector2(x + i * 3 + 2.5, z), 0)
		ground.set_room_type(ground.room_at(Vector2i(x + i * 3, z)), &"cell")
	ground.set_door(Vector3i(x, z + 6, BuildingMap.EDGE_X), true)
	ground.set_door(Vector3i(x + 14, z + 9, BuildingMap.EDGE_X), true)
	ground.set_door(Vector3i(x, z + 4, BuildingMap.EDGE_Z), true)
	# The canteen at the bottom, with the showers cut off behind an
	# angled wall across its far corner.
	var keys := BuildingMap.slants_on_line(Vector2i(area.end.x - 4, area.end.y), Vector2i(area.end.x, area.end.y - 4))
	ground.build_slants(keys, &"brick")
	ground.set_slant_opening(keys[1], BuildingMap.Wall.DOOR)
	_tables(ground, Vector2i(x + 1, z + 10), 3, 1)
	var shower := PrisonCatalogue.object(&"shower")
	for spot: Vector2 in [Vector2(-0.5, -0.5), Vector2(-1.5, -0.5), Vector2(-0.5, -1.5)]:
		ground.place_object_at(shower, Vector2(area.end) + spot, 0.0)
	ground.set_room_type(ground.room_at_point(Vector2(x + 1.5, z + 11.5)), &"canteen")
	ground.set_room_type(ground.room_at_point(Vector2(area.end) - Vector2(0.5, 0.5)), &"shower")
	_plant(site)
	for i in 4:
		site.people.add_person(0, Vector2(x + i * 3 + 1.5, z + 1.5))


static func _basement(site: Site) -> void:
	_landscape(site)
	var o := site.land().get_center() - Vector2i(6, 5)
	var ground := site.map()
	var below := site.map(-1)
	for i in 4:
		var cell := o + Vector2i(i * 3, 0)
		_cell(ground, Rect2i(cell, Vector2i(3, 3)))
		_door(ground, cell + Vector2i(1, 2), Vector2i.DOWN)
	var hall := Rect2i(o + Vector2i(0, 3), Vector2i(12, 4))
	_room(ground, hall)
	_door(ground, hall.position + Vector2i(0, 1), Vector2i.LEFT)
	# Down below: a lobby at the foot of the stairs, then the canteen and
	# the showers. The stairs climb east, turn at a landing and finish
	# heading north into the hall.
	var depth := -Building.STOREY
	_room(below, hall, &"concrete", &"brick", &"", depth)
	var canteen := Rect2i(o + Vector2i(0, 7), Vector2i(6, 4))
	var showers := Rect2i(o + Vector2i(6, 7), Vector2i(6, 4))
	_room(below, canteen, &"wood", &"brick", &"canteen", depth)
	_room(below, showers, &"tiles", &"brick", &"shower", depth)
	_door(below, canteen.position + Vector2i(2, 0), Vector2i.UP)
	_door(below, showers.position + Vector2i(3, 0), Vector2i.UP)
	_tables(below, canteen.position + Vector2i(1, 1), 2, 1)
	_showers(below, showers.position + Vector2i(1, 3), 4)
	var route: Array[Vector2i] = [o + Vector2i(6, 6), o + Vector2i(7, 6), o + Vector2i(8, 6), o + Vector2i(8, 5)]
	below.add_stairs(Staircase.create(route, [false, false, true, false] as Array[bool], true, &"concrete"))
	_plant(site)
	for i in 6:
		site.people.add_person(0, Vector2(o) + Vector2(0.5 + i * 2, 4.5))


static func _crowded(site: Site) -> void:
	_landscape(site)
	var o := site.land().get_center() - Vector2i(12, 6)
	var ground := site.map()
	var dorm := Rect2i(o, Vector2i(16, 6))
	_room(ground, dorm, &"concrete", &"brick", &"dorm")
	var bed := PrisonCatalogue.object(&"bed")
	for i in 8:
		ground.place_object(bed, Vector2(o + Vector2i(i * 2, 0)), 0)
		ground.place_object(bed, Vector2(o + Vector2i(i * 2, 4)), 0)
	# Toilets and a shower between the beds along the back wall.
	ground.place_object(PrisonCatalogue.object(&"toilet"), Vector2(o) + Vector2(1.25, 0), 0)
	ground.place_object(PrisonCatalogue.object(&"toilet"), Vector2(o) + Vector2(9.25, 0), 0)
	ground.place_object(PrisonCatalogue.object(&"shower"), Vector2(o) + Vector2(5.125, 0), 0)
	var canteen := Rect2i(o + Vector2i(0, 6), Vector2i(8, 5))
	var showers := Rect2i(o + Vector2i(8, 6), Vector2i(8, 5))
	_room(ground, canteen, &"wood", &"brick", &"canteen")
	_room(ground, showers, &"tiles", &"brick", &"shower")
	# Doors on odd tiles, between the beds.
	_door(ground, o + Vector2i(5, 6), Vector2i.UP)
	_door(ground, o + Vector2i(13, 6), Vector2i.UP)
	_tables(ground, canteen.position + Vector2i(1, 2), 2, 1)
	_showers(ground, showers.position + Vector2i(2, 4), 2)
	var yard := Rect2i(o + Vector2i(16, 0), Vector2i(8, 11))
	ground.build_room(yard, &"lawn", &"fence")
	ground.set_room_type(ground.room_at(yard.position), &"yard")
	ground.set_door(Vector3i(yard.position.x, o.y + 2, BuildingMap.EDGE_Z), true)
	_plant(site)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 24:
		var person := site.people.add_person(0, Vector2(o) + Vector2(0.5 + (i % 12) * 1.3, 2.5 + floori(i / 12.0)))
		if person != null:
			person.needs[&"hunger"] = rng.randf_range(10.0, 45.0)


static func _locked_out(site: Site) -> void:
	_landscape(site)
	var o := site.land().get_center() - Vector2i(7, 5)
	var ground := site.map()
	for i in 2:
		var cell := o + Vector2i(i * 3, 0)
		_cell(ground, Rect2i(cell, Vector2i(3, 3)))
		_door(ground, cell + Vector2i(1, 2), Vector2i.DOWN)
	# Showers with no way in.
	var showers := Rect2i(o + Vector2i(6, 0), Vector2i(5, 3))
	_room(ground, showers, &"tiles", &"brick", &"shower")
	_showers(ground, showers.position + Vector2i(1, 1), 3)
	var corridor := Rect2i(o + Vector2i(0, 3), Vector2i(14, 2))
	_room(ground, corridor)
	_door(ground, corridor.position, Vector2i.LEFT)
	# A canteen on a platform 0.75 m up. Its door only goes in with door steps.
	var canteen := Rect2i(o + Vector2i(0, 5), Vector2i(8, 5))
	site.terrain.flatten_cells(BuildingMap.cells_in(canteen), 0.75)
	# Its top edge meets the corridor, so the ground there stays low.
	var edge := {}
	for i in canteen.size.x + 1:
		edge[Vector2i(canteen.position.x + i, canteen.position.y)] = 0.0
	site.terrain.set_corners(edge)
	_room(ground, canteen, &"wood", &"brick", &"canteen", 0.75)
	_door(ground, canteen.position + Vector2i(3, 0), Vector2i.UP)
	_tables(ground, canteen.position + Vector2i(1, 2), 2, 2)
	_plant(site)
	for i in 4:
		site.people.add_person(0, Vector2(o) + Vector2(1.5 + i * 2, 3.5 + (i % 2)))

static func _staff_wing(site: Site, kitchen := false) -> void:
	_landscape(site)
	var o := site.land().get_center() - Vector2i(10, 8)
	var ground := site.map()
	# A yard off the canteen, built first so the canteen and showers swap
	# the shared fence for proper walls.
	var yard := Rect2i(o + Vector2i(0, 10), Vector2i(12, 5))
	ground.build_room(yard, &"lawn", &"fence")
	ground.set_room_type(ground.room_at(yard.position), &"yard")
	for i in 4:
		var cell := o + Vector2i(i * 3, 0)
		_cell(ground, Rect2i(cell, Vector2i(3, 3)))
		_door(ground, cell + Vector2i(1, 2), Vector2i.DOWN)
	var corridor := Rect2i(o + Vector2i(0, 3), Vector2i(16, 2))
	_room(ground, corridor)
	_door(ground, corridor.position, Vector2i.LEFT)
	var canteen := Rect2i(o + Vector2i(0, 5), Vector2i(8, 5))
	_room(ground, canteen, &"wood", &"brick", &"canteen")
	_door(ground, canteen.position + Vector2i(3, 0), Vector2i.UP)
	_tables(ground, canteen.position + Vector2i(1, 2), 2, 1)
	var showers := Rect2i(o + Vector2i(8, 5), Vector2i(4, 5))
	_room(ground, showers, &"tiles", &"brick", &"shower")
	_door(ground, showers.position + Vector2i(1, 0), Vector2i.UP)
	_showers(ground, showers.position + Vector2i(0, 4), 3)
	# The staff room: only staff get through its door.
	var staff_room := Rect2i(o + Vector2i(12, 5), Vector2i(4, 5))
	_room(ground, staff_room, &"wood", &"plaster")
	var staff_door := BuildingMap.edge_between(staff_room.position + Vector2i(1, 0), staff_room.position + Vector2i(1, -1))
	ground.set_door(staff_door, true, &"staff")
	var corner := Vector2(staff_room.position)
	ground.place_object(PrisonCatalogue.object(&"tv"), corner + Vector2(3, 0), 0)
	ground.place_object(PrisonCatalogue.object(&"table"), corner + Vector2(2, 2), 0)
	ground.place_object(PrisonCatalogue.object(&"bench"), corner + Vector2(2.5, 4.5), 2)
	ground.place_object(PrisonCatalogue.object(&"toilet"), corner + Vector2(0, 4.25), 2)
	ground.place_object(PrisonCatalogue.object(&"plant_pot"), corner, 0)
	ground.set_room_zone(ground.room_at(staff_room.position), &"staff")
	# An office off the end of the corridor, with a plain door: zoned staff
	# only, so prisoners keep out all the same.
	var office := Rect2i(o + Vector2i(16, 2), Vector2i(4, 4))
	_room(ground, office, &"wood", &"plaster")
	_door(ground, office.position + Vector2i(0, 2), Vector2i.LEFT)
	ground.place_object(PrisonCatalogue.object(&"desk"), Vector2(office.position) + Vector2(1, 0), 0)
	ground.place_object(PrisonCatalogue.object(&"bookshelf"), Vector2(office.position) + Vector2(3, 0), 0)
	ground.set_room_zone(ground.room_at(office.position), &"staff")
	_door(ground, canteen.position + Vector2i(5, 4), Vector2i.DOWN)
	ground.place_object(PrisonCatalogue.object(&"bench"), Vector2(yard.position) + Vector2(1, 4.5), 2)
	ground.place_object(PrisonCatalogue.object(&"basketball_hoop"), Vector2(yard.position) + Vector2(10, 0.5), 0)
	if kitchen:
		_kitchen(ground, canteen)
	_plant(site)
	for i in 6:
		site.people.add_person(0, Vector2(o) + Vector2(1.5 + i * 2, 3.5 + (i % 2)))
	for i in 2:
		var member := site.people.add_person(0, Vector2(staff_room.position) + Vector2(1.5 - i, 3.5 - i), "", &"staff")
		if kitchen:
			site.people.set_role(member, [&"cook", &"handyman"][i])


## A kitchen off the west end of a canteen, with a serving counter in the
## canteen's corner and a delivery pallet on a bay outside the back door.
static func _kitchen(ground: BuildingMap, canteen: Rect2i) -> void:
	var kitchen := Rect2i(canteen.position - Vector2i(5, 0), Vector2i(5, 5))
	_room(ground, kitchen, &"tiles", &"tiles", &"kitchen")
	_door(ground, canteen.position + Vector2i(0, 2), Vector2i.LEFT)
	_door(ground, kitchen.position + Vector2i(0, 2), Vector2i.LEFT)
	var corner := Vector2(kitchen.position)
	ground.place_object(PrisonCatalogue.object(&"fridge"), corner, 0)
	ground.place_object(PrisonCatalogue.object(&"cooker"), corner + Vector2(2, 0), 0)
	ground.place_object(PrisonCatalogue.object(&"cooker"), corner + Vector2(3, 0), 0)
	ground.place_object(PrisonCatalogue.object(&"food_shelf"), corner + Vector2(0, 4.5), 0)
	ground.place_object(PrisonCatalogue.object(&"sink"), corner + Vector2(4, 4), 0)
	ground.place_object(PrisonCatalogue.object(&"serving_counter"), Vector2(canteen.position), 0)
	# A paved delivery bay outside the back door.
	ground.fill_floor(Rect2i(kitchen.position + Vector2i(-4, 0), Vector2i(4, 5)), &"paving")
	ground.place_object(PrisonCatalogue.object(&"delivery_pallet"), corner + Vector2(-3, 1.5), 0)

#endregion

#region Helpers

## Hills round the land and a pond off to the east, as in the starter.
static func _landscape(site: Site, base: Callable = Callable()) -> void:
	var land := site.land()
	var pond := Vector2(land.end.x + 9, land.get_center().y + 6)
	StartingLandscape.shape(site.terrain, land, pond, 6.0, 7, base)
	site.water.fill_at(Vector2i(pond))


static func _plant(site: Site, garden := false) -> void:
	StartingLandscape.plant(site.foliage, site.terrain, site.map(), site.land().position, 7, garden)


static func _room(map: BuildingMap, rect: Rect2i, floor_style: StringName = &"concrete",
		wall_style: StringName = &"brick", type: StringName = &"", height := 0.0) -> void:
	map.build_room(rect, floor_style, wall_style, height)
	if type != &"":
		map.set_room_type(map.room_at(rect.position), type)


## A cell with a bed against its back wall (two, shared, if it is wide
## enough) and a toilet in the corner. The back wall is the top one, or the
## bottom one for a cell with its door at the top.
static func _cell(map: BuildingMap, rect: Rect2i, height := 0.0, door_at_top := false) -> void:
	_room(map, rect, &"concrete", &"brick", &"cell", height)
	var bed := PrisonCatalogue.object(&"bed")
	var back := Vector2(rect.position) + (Vector2(0, rect.size.y - 2) if door_at_top else Vector2.ZERO)
	map.place_object(bed, back, 0)
	if rect.size.x >= 3:
		map.place_object(bed, back + Vector2(1, 0), 0)
	map.place_object(PrisonCatalogue.object(&"toilet"), Vector2(rect.end.x - 0.5, rect.position.y), 0)
	map.place_object(PrisonCatalogue.object(&"radio"), Vector2(rect.end.x - 1.0, rect.position.y), 0)


## A door in the wall on one side of a tile.
static func _door(map: BuildingMap, cell: Vector2i, side: Vector2i) -> bool:
	return map.set_door(BuildingMap.edge_between(cell, cell + side), true)


## Rows of tables, two tiles apart each way, from a top-left tile.
static func _tables(map: BuildingMap, from: Vector2i, across: int, down: int) -> void:
	var table := PrisonCatalogue.object(&"table")
	for row in down:
		for i in across:
			map.place_object(table, Vector2(from + Vector2i(i * 3, row * 2)), 0)


## A row of showers along a wall, from a tile.
static func _showers(map: BuildingMap, from: Vector2i, count: int) -> void:
	var shower := PrisonCatalogue.object(&"shower")
	for i in count:
		map.place_object(shower, Vector2(from) + Vector2(i + 0.125, 0.125), 0)

#endregion
