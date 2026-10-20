class_name Room
extends RefCounted
## A connected patch of floor, bounded by walls, doors or the edge of the
## floor. BuildingMap works these out; nothing else should create them.

var id := 0
var cells: Array[Vector2i] = []
## Every piece of floor in the room, as Vector3i(cell x, cell z, piece index).
## Cells cut by angled walls can have pieces in more than one room.
var pieces: Array[Vector3i] = []
## Floor area in tiles.
var area := 0.0
## True when walls or doors close off every side of the floor.
var enclosed := true
## True when enclosed by indoor walls only. Fences leave a room outdoors.
var indoor := false
## The RoomTypeDef id, or empty when the player has not chosen one.
var type: StringName = &""
## The ZoneDef id painted onto it, or empty to go by its type.
var zone: StringName = &""


## The middle of the room, in cell units (cell (0, 0) spans 0 to 1).
func centre() -> Vector2:
	var total := Vector2.ZERO
	for cell in cells:
		total += Vector2(cell) + Vector2(0.5, 0.5)
	return total / maxf(cells.size(), 1)
