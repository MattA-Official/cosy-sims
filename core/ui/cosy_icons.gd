class_name CosyIcons
extends RefCounted
## Small smooth icons for the theme (tick boxes, switches, slider knobs),
## drawn from signed distance functions so their edges stay soft at any size.


static func check_box(size: int, fill: Color, mark: Color, ticked: bool) -> ImageTexture:
	return _draw(Vector2i(size, size), func(pos: Vector2) -> Color:
		var c := Vector2(size, size) * 0.5
		var col := _over(Color(0, 0, 0, 0), fill, _cover(_rounded_box(pos - c, c - Vector2(1, 1), size * 0.28)))
		if ticked:
			var d := minf(_segment(pos, Vector2(size * 0.27, size * 0.52), Vector2(size * 0.44, size * 0.68)),
					_segment(pos, Vector2(size * 0.44, size * 0.68), Vector2(size * 0.74, size * 0.34)))
			col = _over(col, mark, _cover(d - size * 0.08))
		return col)


static func radio(size: int, fill: Color, mark: Color, on: bool) -> ImageTexture:
	return _draw(Vector2i(size, size), func(pos: Vector2) -> Color:
		var c := Vector2(size, size) * 0.5
		var col := _over(Color(0, 0, 0, 0), fill, _cover(pos.distance_to(c) - (size * 0.5 - 1)))
		if on:
			col = _over(col, mark, _cover(pos.distance_to(c) - size * 0.2))
		return col)


## A pill-shaped on/off switch with a round thumb.
static func switch(width: int, height: int, fill: Color, thumb: Color, on: bool) -> ImageTexture:
	return _draw(Vector2i(width, height), func(pos: Vector2) -> Color:
		var c := Vector2(width, height) * 0.5
		var r := height * 0.5 - 1
		var col := _over(Color(0, 0, 0, 0), fill, _cover(_rounded_box(pos - c, c - Vector2(1, 1), r)))
		var thumb_x := width - height * 0.5 if on else height * 0.5
		col = _over(col, thumb, _cover(pos.distance_to(Vector2(thumb_x, c.y)) - (r - 3)))
		return col)


## A round slider knob with a coloured ring.
static func knob(size: int, fill: Color, ring: Color) -> ImageTexture:
	return _draw(Vector2i(size, size), func(pos: Vector2) -> Color:
		var d := pos.distance_to(Vector2(size, size) * 0.5)
		var col := _over(Color(0, 0, 0, 0), ring, _cover(d - (size * 0.5 - 1)))
		return _over(col, fill, _cover(d - (size * 0.5 - 5))))


static func dot(size: int, fill: Color) -> ImageTexture:
	return _draw(Vector2i(size, size), func(pos: Vector2) -> Color:
		return _over(Color(0, 0, 0, 0), fill, _cover(pos.distance_to(Vector2(size, size) * 0.5) - size * 0.5 + 0.5)))


## A downward chevron, for drop-down buttons.
static func chevron(size: int, colour: Color) -> ImageTexture:
	return _draw(Vector2i(size, size), func(pos: Vector2) -> Color:
		var d := minf(_segment(pos, Vector2(size * 0.22, size * 0.38), Vector2(size * 0.5, size * 0.66)),
				_segment(pos, Vector2(size * 0.5, size * 0.66), Vector2(size * 0.78, size * 0.38)))
		return _over(Color(0, 0, 0, 0), colour, _cover(d - size * 0.08)))


static func _draw(size: Vector2i, shade: Callable) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			image.set_pixel(x, y, shade.call(Vector2(x + 0.5, y + 0.5)))
	return ImageTexture.create_from_image(image)


## How much of a pixel a shape covers, from its signed distance.
static func _cover(distance: float) -> float:
	return clampf(0.5 - distance, 0.0, 1.0)


static func _over(under: Color, colour: Color, amount: float) -> Color:
	var a := colour.a * amount
	var out_a := a + under.a * (1.0 - a)
	if out_a <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb := (Vector3(colour.r, colour.g, colour.b) * a
			+ Vector3(under.r, under.g, under.b) * under.a * (1.0 - a)) / out_a
	return Color(rgb.x, rgb.y, rgb.z, out_a)


static func _rounded_box(pos: Vector2, half: Vector2, radius: float) -> float:
	var q := pos.abs() - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


static func _segment(pos: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := pos - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length()
