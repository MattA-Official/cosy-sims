class_name LandPlots
extends RefCounted
## Buying and selling land in square plots of SIZE tiles. The map's
## buyable area is a grid of plots; you start owning some in the middle,
## and can buy any plot next to your land, one at a time or a dragged
## block at once, so land takes any shape. Flat, dry plots cost the most;
## water brings the price down. Ticking flatten levels a plot with your land
## along their shared edges, for a fee by how much ground moves.
##
## Empty land sells back at SELL_SHARE of what it cost. A purchase can be
## undone for a full refund until the next game hour.
##
## With `hold` set, a purchase may have to wait for planning permission:
## it's paid for, but stays off your land until grant() is called.

## Just before land is bought (the first plot of a batch), and just after.
signal buying(plot: Rect2i)
signal bought(plot: Rect2i)
## Land given back, by sale or undo.
signal sold(plot: Rect2i)
## A purchase is waiting for permission, filed under `key`.
signal awaiting(key: Vector2i, plots: Array[Rect2i])
## A purchase waiting for permission was undone.
signal withdrawn(key: Vector2i)

## Tiles along each side of a plot.
const SIZE := 24
## Price of a flat, dry plot: about a week's healthy surplus.
const PLOT_PRICE := 5000
## A rough or wet plot costs at least this share of the full price.
const CHEAPEST := 0.6
## Average slope (metres of height between neighbouring corners) at which
## a plot is as cheap as it gets.
const ROUGHEST := 0.5
## Flattening, per metre each corner moves.
const FLATTEN_PRICE := 30
## Of what a plot cost, what selling it back brings.
const SELL_SHARE := 0.5

var building: Building
var terrain: Terrain
var water: WaterLayer
var ledger: Ledger
## Paths and roads, which make land in use. Optional.
var paths: PathNetwork
## The hour count now, for undoing a purchase within the hour. Optional:
## without it purchases can't be undone.
var clock: GameClock
## The ledger line purchases go under.
var line := "Land"
## Where land can be bought, in tiles: a whole number of plots each way.
var area := Rect2i()
## What each plot bought cost, by its top-left tile.
var paid: Dictionary[Vector2i, int] = {}
## The latest purchase while it can still be undone: {plots, cost, hour}.
var last_purchase: Dictionary = {}
## (plots: Array[Rect2i]) -> bool: whether a purchase must wait for
## permission. Optional.
var hold: Callable
## Purchases waiting for permission, by their first plot's top-left tile.
var pending: Dictionary[Vector2i, Array] = {}


## Every plot in the buyable area.
func all_plots() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for z in range(area.position.y, area.end.y, SIZE):
		for x in range(area.position.x, area.end.x, SIZE):
			out.append(Rect2i(x, z, SIZE, SIZE))
	return out


## Every plot you could buy now: not yours, next to land that is.
func plots() -> Array[Rect2i]:
	return all_plots().filter(for_sale)


## Owned plots.
func owned() -> Array[Rect2i]:
	return all_plots().filter(is_owned)


func is_owned(plot: Rect2i) -> bool:
	return building.ground().owns(plot.get_center())


func for_sale(plot: Rect2i) -> bool:
	return area.encloses(plot) and not is_owned(plot) and not is_pending(plot) and _next_to(plot, owned())


## Whether a plot is bought but waiting for permission.
func is_pending(plot: Rect2i) -> bool:
	return pending.values().any(func(plots: Array) -> bool: return plots.has(plot))


## The plot holding a tile, or an empty rect outside the buyable area.
func plot_at(cell: Vector2i) -> Rect2i:
	if not area.has_point(cell):
		return Rect2i()
	var at := area.position + (cell - area.position) / SIZE * SIZE
	return Rect2i(at, Vector2i(SIZE, SIZE))


## The plots a dragged block of tiles covers.
func plots_between(a: Vector2i, b: Vector2i) -> Array[Rect2i]:
	var from := plot_at(Vector2i(mini(a.x, b.x), mini(a.y, b.y)).clamp(area.position, area.end - Vector2i.ONE))
	var to := plot_at(Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)).clamp(area.position, area.end - Vector2i.ONE))
	var out: Array[Rect2i] = []
	if not from.has_area():
		return out
	for z in range(from.position.y, to.end.y, SIZE):
		for x in range(from.position.x, to.end.x, SIZE):
			out.append(Rect2i(x, z, SIZE, SIZE))
	return out


## Of some plots, those you could buy together: not yours, and joined to
## your land through each other.
func buyable(chosen: Array[Rect2i]) -> Array[Rect2i]:
	var have := owned()
	var left := chosen.filter(func(p: Rect2i) -> bool: return area.encloses(p) and not is_owned(p) and not is_pending(p))
	var out: Array[Rect2i] = []
	var grew := true
	while grew:
		grew = false
		for plot: Rect2i in left.duplicate():
			if _next_to(plot, have) or _next_to(plot, out):
				out.append(plot)
				left.erase(plot)
				grew = true
	return out


func price(plot: Rect2i) -> int:
	var tiles := plot.get_area()
	var wet := 0
	for cell in BuildingMap.cells_in(plot):
		if water != null and water.body_at(cell) != null:
			wet += 1
	var rough := clampf(_slope(plot) / ROUGHEST, 0.0, 1.0)
	var share := lerpf(1.0, CHEAPEST, maxf(rough, float(wet) / tiles))
	return int(snappedf(PLOT_PRICE * share, 10.0))


func price_of(chosen: Array[Rect2i], flatten := false) -> int:
	var sum := 0
	for plot in chosen:
		sum += price(plot) + (flatten_price(plot) if flatten else 0)
	return sum


## What flattening the plot would cost on top of its price.
func flatten_price(plot: Rect2i) -> int:
	var target := flatten_height(plot)
	var moved := 0.0
	for corner in _corners(plot):
		moved += absf(terrain.corner_height(corner) - target)
	return int(snappedf(moved * FLATTEN_PRICE, 10.0))


## The height flattening levels the plot to: the average of your land's
## corners along their shared edges.
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
	return can_afford_all([plot], flatten)


func can_afford_all(chosen: Array[Rect2i], flatten := false) -> bool:
	if ledger == null or ledger.sandbox:
		return true
	return ledger.balance >= price_of(chosen, flatten)


## Buys one plot if it's for sale and you can pay, flattening it if asked.
func buy(plot: Rect2i, flatten: bool) -> bool:
	return buy_all([plot], flatten)


## Buys plots together if they're all for sale (joined to your land through
## each other) and you can pay for the lot.
func buy_all(chosen: Array[Rect2i], flatten := false) -> bool:
	if chosen.is_empty() or buyable(chosen).size() != chosen.size() or not can_afford_all(chosen, flatten):
		return false
	var cost := 0
	var waiting: bool = hold.is_valid() and hold.call(chosen)
	if not waiting:
		buying.emit(chosen[0])
	for plot in chosen:
		var each := price(plot)
		if flatten:
			var fee := flatten_price(plot)
			terrain.flatten_cells(BuildingMap.cells_in(plot), flatten_height(plot))
			if ledger != null:
				ledger.add(-fee, "Groundworks")
		if ledger != null:
			ledger.add(-each, line)
		paid[plot.position] = each
		cost += each
		if not waiting:
			building.add_land(plot)
	last_purchase = {"plots": chosen.duplicate(), "cost": cost, "hour": _hour()} if clock != null else {}
	if waiting:
		pending[chosen[0].position] = chosen.duplicate()
		awaiting.emit(chosen[0].position, chosen.duplicate())
	else:
		bought.emit(chosen[0])
	return true


## Permission came through: the purchase filed under `key` becomes yours.
func grant(key: Vector2i) -> bool:
	if not pending.has(key):
		return false
	var plots: Array = pending[key]
	pending.erase(key)
	buying.emit(plots[0])
	for plot: Rect2i in plots:
		building.add_land(plot)
	if not last_purchase.is_empty() and last_purchase.plots[0] == plots[0]:
		# Undoing it now would be a sale, not a withdrawal.
		last_purchase.hour = _hour()
	bought.emit(plots[0])
	return true


## Whether a plot can be sold back: yours, with nothing built on it, and
## leaving your land in one piece.
func can_sell(plot: Rect2i) -> bool:
	return can_sell_all([plot])


func can_sell_all(chosen: Array[Rect2i]) -> bool:
	if chosen.is_empty():
		return false
	for plot in chosen:
		if not is_owned(plot) or in_use(plot):
			return false
	var left := owned().filter(func(p: Rect2i) -> bool: return not chosen.has(p))
	return not left.is_empty() and _joined(left)


## Whether anything is built on a plot, or a path or road crosses it.
func in_use(plot: Rect2i) -> bool:
	if building.in_use(plot):
		return true
	if paths != null:
		for id: int in paths.nodes:
			if Rect2(plot).has_point(paths.nodes[id]):
				return true
		for segment in paths.segments.values():
			for t in 9:
				if Rect2(plot).has_point(paths.point_on(segment, t / 8.0)):
					return true
	return false


## What selling back brings.
func sell_price(plot: Rect2i) -> int:
	return int(snappedf(paid.get(plot.position, price(plot)) * SELL_SHARE, 10.0))


func sell_all(chosen: Array[Rect2i]) -> bool:
	if not can_sell_all(chosen):
		return false
	for plot in chosen:
		if ledger != null:
			ledger.add(sell_price(plot), line)
		_give_back(plot)
	last_purchase = {}
	return true


## Whether the latest purchase can still be undone: within the game hour
## it was made, with nothing built on it since.
func can_undo() -> bool:
	if last_purchase.is_empty() or _hour() != last_purchase.hour:
		return false
	if pending.has(last_purchase.plots[0].position):
		return true
	var chosen: Array[Rect2i] = []
	chosen.assign(last_purchase.plots)
	return can_sell_all(chosen)


## Gives back the latest purchase for every penny, if it can be undone.
func undo_last() -> bool:
	if not can_undo():
		return false
	if ledger != null:
		ledger.add(last_purchase.cost, line)
	var key: Vector2i = last_purchase.plots[0].position
	if pending.has(key):
		pending.erase(key)
		for plot: Rect2i in last_purchase.plots:
			paid.erase(plot.position)
		withdrawn.emit(key)
	else:
		for plot: Rect2i in last_purchase.plots:
			_give_back(plot)
	last_purchase = {}
	return true


func _give_back(plot: Rect2i) -> void:
	paid.erase(plot.position)
	building.remove_land(plot)
	sold.emit(plot)


func _next_to(plot: Rect2i, others: Array) -> bool:
	for other: Rect2i in others:
		var gap := (other.position - plot.position).abs()
		if gap.x + gap.y == SIZE:
			return true
	return false


## Whether plots all join up, side to side.
func _joined(chosen: Array) -> bool:
	var reached: Array = [chosen[0]]
	var grew := true
	while grew:
		grew = false
		for plot: Rect2i in chosen:
			if not reached.has(plot) and _next_to(plot, reached):
				reached.append(plot)
				grew = true
	return reached.size() == chosen.size()


func _hour() -> int:
	return floori(clock.total_minutes / GameClock.MINUTES_PER_HOUR) if clock != null else 0


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
