class_name Staircase
extends RefCounted
## A staircase drawn on the grid, like the Sims 4 stair builder. It runs
## through a route of tiles from its foot: step tiles climbing straight on,
## and landings wherever it pauses or turns. Every staircase climbs one
## storey in the same steps, so a straight flight and one that turns back
## on itself both have three tiles of steps; landings add flat tiles
## between them.
##
## Paths use the same RISE for their steps, so stairs look alike indoors
## and out.

## Height of one step. Seven of them make a storey.
const RISE := 0.25
## Depth of one step: two to a tile.
const GOING := 0.5
## Tiles of steps in every staircase. Six treads and the floor above make
## seven risers.
const STEP_TILES := 3

var id := 0
## The tiles it covers in order, foot first.
var cells: Array[Vector2i] = []
## One per cell: is it a landing rather than steps?
var landings: Array[bool] = []
## Landings with their outer corners rounded off rather than square.
var rounded := false
## The floor style its treads take.
var style: StringName = &""


static func create(route: Array[Vector2i], landing_flags: Array[bool], is_rounded := false,
		floor_style: StringName = &"") -> Staircase:
	var stairs := Staircase.new()
	stairs.cells = route.duplicate()
	stairs.landings = landing_flags.duplicate()
	stairs.rounded = is_rounded
	stairs.style = floor_style
	return stairs


## The way the route runs into cell i (out of it, for the foot).
func direction_in(i: int) -> Vector2i:
	if cells.size() < 2:
		return Vector2i(0, 1)
	return cells[1] - cells[0] if i == 0 else cells[i] - cells[i - 1]


## The way the route runs out of cell i (into it, for the last cell).
func direction_out(i: int) -> Vector2i:
	return direction_in(i + 1) if i + 1 < cells.size() else direction_in(i)


## The tile people step on from before climbing.
func entry() -> Vector2i:
	return cells[0] - direction_in(0)


## The tile on the floor above where the stairs come out.
func exit() -> Vector2i:
	return cells[-1] + direction_out(cells.size() - 1)


## Each flat surface, bottom to top, as [outline in tile units, height
## above the foot]. Step tiles have two treads each; landings are one
## surface level with the tread before them.
func treads() -> Array:
	var out: Array = []
	var risers := 0
	for i in cells.size():
		var cell := Vector2(cells[i])
		if landings[i]:
			out.append([landing_outline(i), risers * RISE])
			continue
		var dir := Vector2(direction_in(i))
		var across := Vector2(-dir.y, dir.x) * 0.5
		var back := cell + Vector2(0.5, 0.5) - dir * 0.5
		for half in 2:
			risers += 1
			var a := back + dir * GOING * half
			var b := a + dir * GOING
			out.append([PackedVector2Array([a - across, b - across, b + across, a + across]),
					risers * RISE])
	return out


## The height of the top tread above the foot: one step short of a storey.
func top_height() -> float:
	return STEP_TILES * 2 * RISE


## A landing's outline. Square landings fill the tile; rounded ones where
## the stairs turn swing round the inside corner in a quarter circle, so
## a landing that turns back on itself makes a half circle.
func landing_outline(i: int) -> PackedVector2Array:
	var cell := Vector2(cells[i])
	var square := PackedVector2Array([cell, cell + Vector2(1, 0), cell + Vector2(1, 1),
			cell + Vector2(0, 1)])
	var into := Vector2(direction_in(i))
	var onward := Vector2(direction_out(i))
	if not rounded or into == onward:
		return square
	# The corner on the inside of the turn, and a quarter circle about it
	# reaching to the far side of the tile.
	var inside := cell + Vector2(0.5, 0.5) + (-into + onward) * 0.5
	var out := PackedVector2Array([inside])
	var arc := 8
	for k in arc + 1:
		var t := PI * 0.5 * k / arc
		out.append(inside + into * cos(t) + -onward * sin(t))
	return out


## Does the route cover this tile?
func covers(cell: Vector2i) -> bool:
	return cells.has(cell)
