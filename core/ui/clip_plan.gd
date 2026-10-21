class_name ClipPlan
## A small top-down plan of a clip, for template buttons: floor in its
## colour, walls dark, doors gaps, objects as pale blocks.

const PIXELS := 12
const WALL := Color(0.25, 0.22, 0.2)
const OBJECT := Color(0.95, 0.93, 0.88)


static func texture(clip: BuildClip, floor_def: Callable) -> ImageTexture:
	var side := maxi(clip.size.x, clip.size.y) + 1
	var image := Image.create(side * PIXELS, side * PIXELS, false, Image.FORMAT_RGBA8)
	var offset := (Vector2i(side, side) - clip.size) * PIXELS / 2
	for cell: Vector2i in clip.floors:
		var def: FloorDef = floor_def.call(clip.floors[cell][0])
		image.fill_rect(Rect2i(offset + cell * PIXELS, Vector2i(PIXELS, PIXELS)),
				def.colour if def != null else Color.GRAY)
	for entry: Array in clip.objects:
		var def: ObjectDef = entry[0]
		var turned := absf(sin(entry[2])) > 0.7
		var size := Vector2(def.size.y, def.size.x) if turned else def.size
		var at := (entry[1] as Vector2 - size * 0.5) * PIXELS + Vector2(offset)
		image.fill_rect(Rect2i(Vector2i(at.round()) + Vector2i.ONE, Vector2i((size * PIXELS).round()) - Vector2i(2, 2)), OBJECT)
	for wall: Array in clip.walls:
		var a: Vector2i = wall[0]
		var b: Vector2i = wall[1]
		var corner := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)) * PIXELS + offset
		if wall[2] == BuildingMap.Wall.DOOR:
			continue
		var line := Rect2i(corner - Vector2i(1, 0), Vector2i(3, PIXELS)) if a.y == b.y \
				else Rect2i(corner - Vector2i(0, 1), Vector2i(PIXELS, 3))
		image.fill_rect(line, WALL)
	return ImageTexture.create_from_image(image)
