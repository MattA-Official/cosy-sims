class_name SampleAirports
## Ready-made starts for the airport: an empty field, or the shed, a small
## terminal showing off everything A0 adds to the build tools.
##
## The shed, from its top-left corner `o`, about 25 × 14 tiles:
##   Check-in hall (0,2)-(12,10): double height, with a viewing mezzanine
##     on the floor above its bottom three rows and escalators up and down
##     to it. Three check-in desks along the back wall, queue posts snaking
##     in front of the middle one, an information desk and the boards.
##   Departure lounge (12,2)-(20,10), through a screening point.
##   Gate (20,2)-(25,10), with a gate desk.
##   Arrivals hall (20,10)-(25,14): in through a one-way door from the gate,
##     out to the road.
##   Toilets (16,10)-(20,13), off the lounge, painted airside.
##   Bag hall (0,10)-(12,14), behind a staff security door, with belts.

## The shed's size in tiles, for centring it.
const SHED_SIZE := Vector2i(25, 14)


## Everything a sample builds on.
class Site:
	var building: Building
	var terrain: Terrain
	var water: WaterLayer
	var foliage: FoliageLayer
	var paths: PathNetwork
	var people: People
	var area := Rect2i()

	func land() -> Rect2i:
		return building.land[0]


## Builds a start: the shed, or just a few trees for an empty field.
static func build(start: AirportNewGame.Start, site: Site) -> void:
	var land := site.land()
	if start == AirportNewGame.Start.SHED:
		var o := land.get_center() - SHED_SIZE / 2
		shed(site, o)
		_trees(site, Rect2i(o - Vector2i(4, 6), SHED_SIZE + Vector2i(8, 12)))
	else:
		_trees(site, Rect2i(land.get_center(), Vector2i.ZERO))


## The shed terminal from its top-left tile.
static func shed(site: Site, o: Vector2i) -> void:
	var b := site.building
	var ground := b.ground()
	var hall := Rect2i(o + Vector2i(0, 2), Vector2i(12, 8))
	var lounge := Rect2i(o + Vector2i(12, 2), Vector2i(8, 8))
	var gate := Rect2i(o + Vector2i(20, 2), Vector2i(5, 8))
	var arrivals := Rect2i(o + Vector2i(20, 10), Vector2i(5, 4))
	var toilets := Rect2i(o + Vector2i(16, 10), Vector2i(4, 3))
	var bags := Rect2i(o + Vector2i(0, 10), Vector2i(12, 4))
	_room(ground, hall, &"terrazzo", &"glass", &"check_in_hall")
	_room(ground, lounge, &"carpet", &"panels", &"departure_lounge")
	_room(ground, gate, &"carpet", &"glass", &"gate")
	_room(ground, arrivals, &"terrazzo", &"panels", &"arrivals_hall")
	_room(ground, toilets, &"tiles", &"panels", &"toilets")
	_room(ground, bags, &"concrete", &"brick", &"bag_hall")
	# Toilets have no zone of their own; these are past screening.
	ground.set_room_zone(ground.room_at(toilets.position), &"airside")

	# Ways in and out, and the lines between landside and airside.
	_door(ground, o + Vector2i(0, 7), Vector2i.LEFT) # In from the road.
	_door(ground, o + Vector2i(11, 5), Vector2i.RIGHT, &"screening")
	_door(ground, o + Vector2i(19, 5), Vector2i.RIGHT)
	_door(ground, o + Vector2i(18, 9), Vector2i.DOWN) # To the toilets.
	_door(ground, o + Vector2i(10, 9), Vector2i.DOWN, &"staff_security")
	# Off the plane, through the gate and out through arrivals, one way.
	var off := BuildingMap.edge_between(o + Vector2i(22, 9), o + Vector2i(22, 10))
	ground.set_door(off, true)
	ground.set_door_way(off, BuildingMap.way_from(off, o + Vector2i(22, 9)))
	var out := BuildingMap.edge_between(o + Vector2i(24, 12), o + Vector2i(25, 12))
	ground.set_door(out, true)
	ground.set_door_way(out, BuildingMap.way_from(out, o + Vector2i(24, 12)))

	# The check-in hall: desks along the back, a snaking queue for the
	# middle one, information and the departures board.
	var desk := AirportCatalogue.object(&"check_in_desk")
	for i in 3:
		ground.place_object_at(desk, Vector2(o) + Vector2(4.0 + i * 3.0, 2.5), 0.0)
	var post := AirportCatalogue.object(&"queue_post")
	for at: Vector2 in [Vector2(7, 5), Vector2(9, 5), Vector2(9, 7), Vector2(7, 7), Vector2(5, 7)]:
		ground.place_object_at(post, Vector2(o) + at, 0.0)
	ground.place_object_at(AirportCatalogue.object(&"info_desk"), Vector2(o) + Vector2(5.0, 9.5), PI)
	ground.place_object_at(AirportCatalogue.object(&"departures_board"), Vector2(o) + Vector2(8.0, 9.875), PI)
	ground.place_object_at(AirportCatalogue.object(&"sign_gates"), Vector2(o) + Vector2(11.0, 6.875), PI)
	ground.place_object_at(AirportCatalogue.object(&"sign_check_in"), Vector2(o) + Vector2(0.5, 9.875), PI)
	for x in [2.5, 3.5]:
		ground.place_object_at(AirportCatalogue.object(&"check_in_kiosk"), Vector2(o) + Vector2(x, 8.0), 0.0)
	ground.place_object_at(AirportCatalogue.object(&"plant_pot"), Vector2(o) + Vector2(11.5, 9.5), 0.0)

	# Escalators up and down to the viewing mezzanine, in the corner.
	ground.place_object_at(AirportCatalogue.object(&"escalator_up"), Vector2(o) + Vector2(0.5, 5.0), 0.0)
	ground.place_object_at(AirportCatalogue.object(&"escalator_down"), Vector2(o) + Vector2(1.5, 5.0), 0.0)

	# Upstairs: walls round the hall's footprint, floor over its bottom
	# three rows for the mezzanine, and the rest left open.
	var up := b.level(1)
	up.build_room(hall, &"terrazzo", &"glass", Building.STOREY)
	var open := Rect2i(hall.position, Vector2i(hall.size.x, 5))
	up.clear_floor(open)
	b.set_void(1, BuildingMap.cells_in(open))
	var bench := AirportCatalogue.object(&"bench")
	for x in [5.0, 8.0]:
		up.place_object_at(bench, Vector2(o) + Vector2(x, 8.0), PI)

	# The lounge: rows of seats, the way to the toilets and the gate.
	var seats := AirportCatalogue.object(&"seat_row")
	for row in 3:
		for col in 2:
			ground.place_object_at(seats, Vector2(o) + Vector2(14.5 + col * 3.5, 3.5 + row * 2.0), 0.0)
	ground.place_object_at(AirportCatalogue.object(&"sign_toilets"), Vector2(o) + Vector2(18.0, 9.875), PI)
	ground.place_object_at(AirportCatalogue.object(&"sign_gates"), Vector2(o) + Vector2(19.0, 2.125), 0.0)
	ground.place_object_at(AirportCatalogue.object(&"coffee_machine"), Vector2(o) + Vector2(12.5, 9.5), PI)

	# The gate desk by the window, and the toilets.
	ground.place_object_at(AirportCatalogue.object(&"gate_desk"), Vector2(o) + Vector2(22.5, 3.0), 0.0)
	ground.place_object_at(seats, Vector2(o) + Vector2(22.5, 6.0), 0.0)
	for i in 2:
		ground.place_object_at(AirportCatalogue.object(&"toilet"), Vector2(o) + Vector2(16.5 + i, 12.5), PI)
	ground.place_object_at(AirportCatalogue.object(&"sink"), Vector2(o) + Vector2(19.5, 11.0), PI * 1.5)
	ground.place_object_at(AirportCatalogue.object(&"sign_exit"), Vector2(o) + Vector2(24.875, 11.5), PI * 0.5)

	# The bag hall: a run from behind check-in round to the reclaim end.
	b.belts.lay(b, 0, Belts.route(o + Vector2i(1, 11), o + Vector2i(9, 12)))
	b.belts.lay(b, 0, Belts.route(o + Vector2i(9, 13), o + Vector2i(1, 13)))

	# A road along the front and a path to the door.
	var road_x := float(o.x) - 4.5
	site.paths.add_segment(Vector2(road_x, o.y - 6.0), Vector2(road_x, o.y + SHED_SIZE.y + 6.0), null, &"road")
	site.paths.add_segment(Vector2(road_x + 2.0, o.y + 7.5), Vector2(o.x, o.y + 7.5), null, &"footpath")

	# A few people to watch: passengers in the hall and lounge, staff in
	# the bag hall.
	for i in 6:
		site.people.add_person(0, Vector2(o) + Vector2(2.5 + i * 1.5, 7.5 + (i % 2)), "", &"passenger")
	for i in 4:
		site.people.add_person(0, Vector2(o) + Vector2(13.5 + i * 1.5, 8.5), "", &"passenger")
	for i in 2:
		site.people.add_person(0, Vector2(o) + Vector2(4.5 + i * 3.0, 12.0), "", &"staff")


static func _room(map: BuildingMap, rect: Rect2i, floor_style: StringName, wall_style: StringName,
		type: StringName) -> void:
	map.build_room(rect, floor_style, wall_style)
	map.set_room_type(map.room_at(rect.position), type)


static func _door(map: BuildingMap, cell: Vector2i, side: Vector2i, kind: StringName = &"") -> bool:
	return map.set_door(BuildingMap.edge_between(cell, cell + side), true, kind)


## Trees and bushes round the land, kept off `keep_clear`.
static func _trees(site: Site, keep_clear: Rect2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var land := Rect2(site.land())
	var clear := Rect2(keep_clear).grow(1.0)
	for i in 40:
		var at := Vector2(rng.randf_range(land.position.x + 1, land.end.x - 1),
				rng.randf_range(land.position.y + 1, land.end.y - 1))
		if clear.has_point(at):
			continue
		var def: FoliageDef = AirportCatalogue.PLANTS[rng.randi_range(0, 1)]
		site.foliage.paint(def, at, 1.5, 3, rng, func(spot: Vector2) -> bool: return not clear.has_point(spot))
