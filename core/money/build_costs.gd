class_name BuildCosts
extends Node
## Charges for building. Whatever is built is worth its price: floor by the
## tile, walls by the length, doors, windows, stairs and objects each.
## When the building's worth goes up the difference is paid; when it goes
## down (demolishing), REFUND of the difference comes back. Restyling to
## something dearer pays the difference too.

## Share of the price given back on demolition.
const REFUND := 0.75
## Prices for things without a def of their own.
const DOOR_PRICE := 100
const WINDOW_PRICES: Dictionary[StringName, int] = {&"glass": 60, &"bars": 80}
const STAIR_TILE_PRICE := 60
const RAMP_TILE_PRICE := 30

var building: Building
var ledger: Ledger
var door_kinds: Dictionary[StringName, DoorKindDef] = {}
## The line building costs go under.
var line := "Building"

var _worth := 0


## Starts charging from the building as it is now, which is free.
func start() -> void:
	_worth = worth()
	building.changed.connect(_on_changed)


## What everything built is worth at full price.
func worth() -> int:
	var sum := 0
	for n: int in building.levels:
		sum += level_worth(building.levels[n])
	return sum


func level_worth(map: BuildingMap) -> int:
	var sum := 0
	for cell: Vector2i in map.floors:
		var def := map.floor_def(map.floors[cell])
		if def != null:
			sum += def.price
	for edge: Vector3i in map.walls:
		sum += _wall_price(map.wall_def(map.wall_styles.get(edge, BuildingMap.DEFAULT_WALL)), 1.0)
		sum += _opening_price(map.walls[edge], map.door_kind_at(edge), map.window_kinds.get(edge, &""))
	for key: Vector4i in map.slants:
		var length := Vector2(key.x, key.y).distance_to(Vector2(key.z, key.w))
		sum += _wall_price(map.wall_def(map.slant_styles.get(key, BuildingMap.DEFAULT_WALL)), length)
		sum += _opening_price(map.slants[key], &"", map.slant_window_kinds.get(key, &""))
	for placed: BuildingMap.PlacedObject in map.objects.values():
		sum += placed.def.price
	for flight: Staircase in map.stairs.values():
		sum += flight.cells.size() * STAIR_TILE_PRICE
	for ramp in map.ramps:
		sum += ramp.rect.get_area() * RAMP_TILE_PRICE
	return sum


func _wall_price(def: WallDef, length: float) -> int:
	return roundi(def.price * length) if def != null else 0


func _opening_price(kind: int, door_kind: StringName, window: StringName) -> int:
	match kind:
		BuildingMap.Wall.DOOR:
			var def: DoorKindDef = door_kinds.get(door_kind)
			return def.price if def != null and def.price > 0 else DOOR_PRICE
		BuildingMap.Wall.WINDOW:
			return WINDOW_PRICES.get(window, WINDOW_PRICES[&"glass"])
	return 0


func _on_changed() -> void:
	var now := worth()
	var change := now - _worth
	_worth = now
	if change > 0:
		ledger.add(-change, line)
	elif change < 0:
		ledger.add(roundi(-change * REFUND), line)
