class_name StarterTemplates
## The prison's starter templates: a single cell, a double cell, a shower
## block and a small canteen, each built on a scratch map and picked up.


static func build() -> Array:
	var map := BuildingMap.new(Rect2i(0, 0, 32, 32))
	var floors: Array[FloorDef] = []
	floors.assign(PrisonCatalogue.FLOORS)
	var walls: Array[WallDef] = []
	walls.assign(PrisonCatalogue.WALLS)
	map.register_styles(floors, walls)
	var out: Array = []
	SamplePrisons._cell(map, Rect2i(1, 1, 2, 3))
	SamplePrisons._door(map, Vector2i(1, 3), Vector2i.DOWN)
	out.append(["Single cell", BuildClip.capture_room(map, map.room_at(Vector2i(1, 1))).copy()])
	SamplePrisons._cell(map, Rect2i(5, 1, 3, 3))
	SamplePrisons._door(map, Vector2i(6, 3), Vector2i.DOWN)
	out.append(["Double cell", BuildClip.capture_room(map, map.room_at(Vector2i(5, 1))).copy()])
	SamplePrisons._room(map, Rect2i(10, 1, 4, 3), &"tiles", &"brick", &"shower")
	SamplePrisons._showers(map, Vector2i(10, 1), 4)
	SamplePrisons._door(map, Vector2i(11, 3), Vector2i.DOWN)
	out.append(["Shower block", BuildClip.capture_room(map, map.room_at(Vector2i(10, 1))).copy()])
	SamplePrisons._room(map, Rect2i(1, 8, 7, 6), &"concrete", &"brick", &"canteen")
	map.place_object(PrisonCatalogue.object(&"serving_counter"), Vector2(1, 8), 0)
	SamplePrisons._tables(map, Vector2i(1, 10), 2, 2)
	SamplePrisons._door(map, Vector2i(4, 13), Vector2i.DOWN)
	out.append(["Small canteen", BuildClip.capture_room(map, map.room_at(Vector2i(1, 8))).copy()])
	return out
