class_name Coverage
extends RefCounted
## Where watchers can see: each game minute every watcher marks the tiles
## near them as seen, and seen fades away over FADE_MINUTES. Walls block
## the view: a watcher only sees tiles in the room they're in (or, outdoors,
## open ground). A prison's guards and cameras, a museum's attendants.

const FADE_MINUTES := 30.0

var building: Building
## Tile (level, x, z): how freshly seen, 1 just now down to 0.
var seen: Dictionary[Vector3i, float] = {}


## Fades what was seen, then marks what each watcher sees now. Watchers are
## [level, point, range in tiles], or with a facing and a cone (radians
## across) added for a camera.
func update(watchers: Array, minutes := 1.0) -> void:
	var fade := minutes / FADE_MINUTES
	for key: Vector3i in seen.keys():
		seen[key] -= fade
		if seen[key] <= 0.0:
			seen.erase(key)
	for watcher: Array in watchers:
		if watcher.size() > 3:
			mark(watcher[0], watcher[1], watcher[2], watcher[3], watcher[4])
		else:
			mark(watcher[0], watcher[1], watcher[2])


## Marks the tiles a watcher at `point` can see: all round, or within
## `cone` either side of `facing` split evenly.
func mark(level: int, point: Vector2, reach: float, facing := Vector2.ZERO, cone := TAU) -> void:
	var map: BuildingMap = building.levels.get(level)
	if map == null:
		return
	var room := map.room_at_point(point)
	var from := Vector2i(point.floor())
	var r := ceili(reach) + 1
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := from + Vector2i(dx, dz)
			var to := Vector2(cell) + Vector2(0.5, 0.5) - point
			if to.length() > reach:
				continue
			if facing != Vector2.ZERO and to.length() > 0.75 and absf(facing.angle_to(to)) > cone * 0.5:
				continue
			if room != null and not room.cells.has(cell):
				continue
			if room == null and (map.room_at(cell) != null or not map.owns(cell)):
				continue
			seen[Vector3i(level, cell.x, cell.y)] = 1.0


## How freshly a point was seen, 0 to 1.
func seen_at(level: int, point: Vector2) -> float:
	var cell := Vector2i(point.floor())
	return seen.get(Vector3i(level, cell.x, cell.y), 0.0)
