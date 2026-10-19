class_name SampleLayout
## A tiny starter prison: two cells (with barred windows) off a corridor, a
## canteen with glass windows, a shower room and a fenced yard, with one
## thing left unfinished so the warnings show.


static func build(map: BuildingMap, at: Vector2i) -> void:
	var bed := PrisonCatalogue.object(&"bed")
	var toilet := PrisonCatalogue.object(&"toilet")
	var o := Vector2(at)

	# A fenced lawn yard with a paved patio, built first so the buildings
	# next to it swap the shared fence for proper walls.
	var yard := Rect2i(at + Vector2i(12, 0), Vector2i(7, 10))
	map.build_room(yard, &"lawn", &"fence")
	map.fill_floor(Rect2i(yard.position + Vector2i(0, 3), Vector2i(4, 2)), &"paving")
	map.set_room_type(map.room_at(yard.position), &"yard")

	# Two 3x3 cells side by side, doors facing a corridor below them.
	for i in 2:
		var origin := at + Vector2i(i * 3, 0)
		map.build_room(Rect2i(origin, Vector2i(3, 3)), &"concrete", &"brick")
		map.set_door(Vector3i(origin.x + 1, origin.y + 3, BuildingMap.EDGE_X), true)
		map.set_opening(Vector3i(origin.x + 1, origin.y, BuildingMap.EDGE_X),
				BuildingMap.Wall.WINDOW, BuildingMap.WINDOW_BARS)
		map.place_object(bed, Vector2(origin), 0)
		if i == 0:
			map.place_object(toilet, Vector2(origin) + Vector2(2.5, 0), 0)
		map.set_room_type(map.room_at(origin), &"cell")

	# Corridor, then a canteen and a shower room below it.
	map.build_room(Rect2i(at + Vector2i(0, 3), Vector2i(12, 2)))
	map.build_room(Rect2i(at + Vector2i(0, 5), Vector2i(7, 5)), &"wood")
	map.build_room(Rect2i(at + Vector2i(7, 5), Vector2i(5, 5)), &"tiles")
	map.set_door(Vector3i(at.x + 3, at.y + 5, BuildingMap.EDGE_X), true)
	map.set_door(Vector3i(at.x + 9, at.y + 5, BuildingMap.EDGE_X), true)
	map.set_door(Vector3i(at.x + 12, at.y + 3, BuildingMap.EDGE_Z), true)
	# The way in: a door at the west end of the corridor.
	map.set_door(Vector3i(at.x, at.y + 3, BuildingMap.EDGE_Z), true)
	for x: int in [1, 3, 5]:
		map.set_opening(Vector3i(at.x + x, at.y + 10, BuildingMap.EDGE_X),
				BuildingMap.Wall.WINDOW, BuildingMap.WINDOW_GLASS)

	var table := PrisonCatalogue.object(&"table")
	for row in 2:
		map.place_object(table, o + Vector2(1, 6 + row * 2), 0)
		map.place_object(table, o + Vector2(4, 6 + row * 2), 0)
	map.set_room_type(map.room_at(at + Vector2i(1, 6)), &"canteen")

	var shower := PrisonCatalogue.object(&"shower")
	for x in 4:
		map.place_object(shower, o + Vector2(7.25 + x, 9.25), 0)
	map.set_room_type(map.room_at(at + Vector2i(8, 6)), &"shower")

