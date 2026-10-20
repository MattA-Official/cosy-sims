class_name LandPlots
extends RefCounted
## Buying more land. The map is cut into square plots lined up with the
## first piece of land you own; any plot touching your land can be bought,
## which moves your boundary out over it. Flat, dry plots cost the most;
## hills and water bring the price down. Ticking flatten smooths the new
## plot to the height of your land along their shared edge, for a fee by how
## much ground moves.

## Plot width and depth in tiles.
const SIZE := 8
## Price of a flat, dry tile.
const TILE_PRICE := 60
## A rough or wet plot costs at least this share of the full price.
const CHEAPEST := 0.6
## Average slope (metres of height between neighbouring corners) at which
## a plot is as cheap as it gets.
const ROUGHEST := 0.5
## Flattening, per metre each corner moves.
const FLATTEN_PRICE := 30

signal bought(plot: Rect2i)

var building: Building
var terrain: Terrain
var water: WaterLayer
var ledger: Ledger
## The ledger line purchases go under.
var line := "Land"


## Every plot you could buy now.
func plots() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if building == null or building.land.is_empty():
		return out
	var origin := building.land[0].position
	var bounds := _bounds()
	var first := Vector2i(posmod(origin.x - bounds.position.x, SIZE), posmod(origin.y - bounds.position.y, SIZE))
	first += bounds.position
	for z in range(first.y, bounds.end.y - SIZE + 1, SIZE):
		for x in range(first.x, bounds.end.x - SIZE + 1, SIZE):
			var plot := Rect2i(x, z, SIZE, SIZE)
			if _owns_any(plot) or not _touches_land(plot):
				continue
			out.append(plot)
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
	building.add_land(plot)
	bought.emit(plot)
	return true


func _bounds() -> Rect2i:
	return Rect2i(Vector2i.ZERO, terrain.size) if terrain != null else building.ground().land_bounds().grow(SIZE * 3)


func _owns_any(plot: Rect2i) -> bool:
	for rect in building.land:
		if rect.intersects(plot):
			return true
	return false


## Whether the plot shares an edge (not just a corner) with land you own.
func _touches_land(plot: Rect2i) -> bool:
	var map := building.ground()
	for i in plot.size.x:
		if map.owns(Vector2i(plot.position.x + i, plot.position.y - 1)) \
				or map.owns(Vector2i(plot.position.x + i, plot.end.y)):
			return true
	for i in plot.size.y:
		if map.owns(Vector2i(plot.position.x - 1, plot.position.y + i)) \
				or map.owns(Vector2i(plot.end.x, plot.position.y + i)):
			return true
	return false


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
