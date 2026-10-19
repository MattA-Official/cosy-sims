class_name SampleLayout
## A tiny starter prison: two cells off a corridor, a canteen and a shower
## room, with one thing left unfinished so the warnings are visible.


static func build(map: BuildingMap, at: Vector2i) -> void:
	var cell_type := PrisonCatalogue.room_type(&"cell")
	var bed := PrisonCatalogue.object(&"bed")
	var toilet := PrisonCatalogue.object(&"toilet")

	# Two 3x3 cells side by side, doors facing a corridor below them.
	for i in 2:
		var origin := at + Vector2i(i * 3, 0)
		map.build_room(Rect2i(origin, Vector2i(3, 3)))
		map.set_door(Vector3i(origin.x + 1, origin.y + 3, BuildingMap.EDGE_X), true)
		map.place_object(bed, origin, 0)
		if i == 0:
			map.place_object(toilet, origin + Vector2i(2, 0), 0)
		map.set_room_type(map.room_at(origin), cell_type.id)

	# Corridor, then a canteen and a shower room below it.
	map.build_room(Rect2i(at + Vector2i(0, 3), Vector2i(12, 2)))
	map.build_room(Rect2i(at + Vector2i(0, 5), Vector2i(7, 5)))
	map.build_room(Rect2i(at + Vector2i(7, 5), Vector2i(5, 5)))
	map.set_door(Vector3i(at.x + 3, at.y + 5, BuildingMap.EDGE_X), true)
	map.set_door(Vector3i(at.x + 9, at.y + 5, BuildingMap.EDGE_X), true)
	map.set_door(Vector3i(at.x, at.y + 3, BuildingMap.EDGE_Z), true)

	var table := PrisonCatalogue.object(&"table")
	for row in 2:
		map.place_object(table, at + Vector2i(1, 6 + row * 2), 0)
		map.place_object(table, at + Vector2i(4, 6 + row * 2), 0)
	map.set_room_type(map.room_at(at + Vector2i(1, 6)), &"canteen")

	var shower := PrisonCatalogue.object(&"shower")
	for x in 3:
		map.place_object(shower, at + Vector2i(8 + x, 9), 0)
	map.set_room_type(map.room_at(at + Vector2i(8, 6)), &"shower")
