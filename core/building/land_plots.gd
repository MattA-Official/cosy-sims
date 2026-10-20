class_name LandPlots
extends RefCounted
## Buying more land, a strip at a time as in Prison Architect: a strip
## runs the whole length of one side of your land and DEPTH tiles out from
## it, so your land stays a rectangle and grows in any direction. Flat,
## dry land costs the most; hills and water bring the price down. Ticking
## flatten smooths the new strip to the height of your land along their
## shared edge, for a fee by how much ground moves.

## How far a strip reaches out from your land, in tiles. Nearer the map's
## edge than that, the strip takes what's left if it's at least MIN_DEPTH.
const DEPTH := 12
const MIN_DEPTH := 4
## Price of a flat, dry tile.
const TILE_PRICE := 25
## A rough or wet strip costs at least this share of the full price.
const CHEAPEST := 0.6
## Average slope (metres of height between neighbouring corners) at which
## a strip is as cheap as it gets.
const ROUGHEST := 0.5
## Flattening, per metre each corner moves.
const FLATTEN_PRICE := 30

## Just before land is bought, and just after.
signal buying(plot: Rect2i)
signal bought(plot: Rect2i)

var building: Building
var terrain: Terrain
var water: WaterLayer
var ledger: Ledger
## The ledger line purchases go under.
var line := "Land"


## Every strip you could buy now: up to one on each side.
func plots() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if building == null or building.land.is_empty():
		return out
	var land := building.ground().land_bounds()
	var map := _bounds()
	var room := [land.position.x - map.position.x, map.end.x - land.end.x,
			land.position.y - map.position.y, map.end.y - land.end.y]
	for side in 4:
		var depth := mini(DEPTH, room[side])
		if depth < MIN_DEPTH:
			continue
		match side:
			0: out.append(Rect2i(land.position.x - depth, land.position.y, depth, land.size.y))
			1: out.append(Rect2i(land.end.x, land.position.y, depth, land.size.y))
			2: out.append(Rect2i(land.position.x, land.position.y - depth, land.size.x, depth))
			3: out.append(Rect2i(land.position.x, land.end.y, land.size.x, depth))
	return out


## The buyable plot holding the tile, or an empty rect.
func plot_at(cell: Vector2i) -> Rect2i:
	for plot in plots():
		if plot.has_point(cell):
			return plot
	return Rect2i()


func price(plot: Rect2i) -> int:
	var tiles := plot.get_area()
	var wet := 0
	for cell in BuildingMap.cells_in(plot):
		if water != null and water.body_at(cell) != null:
			wet += 1
	var rough := clampf(_slope(plot) / ROUGHEST, 0.0, 1.0)
	var share := lerpf(1.0, CHEAPEST, maxf(rough, float(wet) / tiles))
	return int(snappedf(tiles * TILE_PRICE * share, 10.0))


## What flattening the plot would cost on top of its price.
func flatten_price(plot: Rect2i) -> int:
	var target := flatten_height(plot)
	var moved := 0.0
	for corner in _corners(plot):
		moved += absf(terrain.corner_height(corner) - target)
	return int(snappedf(moved * FLATTEN_PRICE, 10.0))


## The height flattening levels the plot to: the average of your land's
## corners along their shared edge.
func flatten_height(plot: Rect2i) -> float:
	var sum := 0.0
	var count := 0
	for corner in _corners(plot):
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
			if building.ground().owns(corner + offset):
				sum += terrain.corner_height(corner)
				count += 1
				break
	return sum / count if count > 0 else terrain.cell_height(plot.get_center())


func can_afford(plot: Rect2i, flatten: bool) -> bool:
	if ledger == null or ledger.sandbox:
		return true
	return ledger.balance >= price(plot) + (flatten_price(plot) if flatten else 0)


## Buys the plot if it's for sale and you can pay, flattening it if asked.
func buy(plot: Rect2i, flatten: bool) -> bool:
	if not plot in plots() or not can_afford(plot, flatten):
		return false
	var cost := price(plot)
	if flatten:
		var fee := flatten_price(plot)
		var height := flatten_height(plot)
		terrain.flatten_cells(BuildingMap.cells_in(plot), height)
		if ledger != null:
			ledger.add(-fee, "Groundworks")
	if ledger != null:
		ledger.add(-cost, line)
	buying.emit(plot)
	building.add_land(plot)
	bought.emit(plot)
	return true


func _bounds() -> Rect2i:
	return Rect2i(Vector2i.ZERO, terrain.size) if terrain != null else building.ground().land_bounds().grow(DEPTH * 2)


func _corners(plot: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in plot.size.y + 1:
		for x in plot.size.x + 1:
			out.append(plot.position + Vector2i(x, z))
	return out


## The average height step between neighbouring corners across the plot.
func _slope(plot: Rect2i) -> float:
	var sum := 0.0
	var count := 0
	for corner in _corners(plot):
		var h := terrain.corner_height(corner)
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if corner.x + step.x <= plot.end.x and corner.y + step.y <= plot.end.y:
				sum += absf(terrain.corner_height(corner + step) - h)
				count += 1
	return sum / count if count > 0 else 0.0
