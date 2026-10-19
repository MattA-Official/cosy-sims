class_name PrisonCatalogue
## Everything the prison game can build. Edit the .tres files in catalogue/
## in the inspector to tweak sizes and colours.

const OBJECTS: Array[ObjectDef] = [
	preload("res://games/prison/catalogue/bed.tres"),
	preload("res://games/prison/catalogue/toilet.tres"),
	preload("res://games/prison/catalogue/table.tres"),
	preload("res://games/prison/catalogue/shower.tres"),
	preload("res://games/prison/catalogue/lift.tres"),
]

const FLOORS: Array[FloorDef] = [
	preload("res://games/prison/catalogue/floor_concrete.tres"),
	preload("res://games/prison/catalogue/floor_tiles.tres"),
	preload("res://games/prison/catalogue/floor_wood.tres"),
	preload("res://games/prison/catalogue/floor_paving.tres"),
	preload("res://games/prison/catalogue/floor_lawn.tres"),
]

const WALLS: Array[WallDef] = [
	preload("res://games/prison/catalogue/wall_plaster.tres"),
	preload("res://games/prison/catalogue/wall_brick.tres"),
	preload("res://games/prison/catalogue/wall_fence.tres"),
	preload("res://games/prison/catalogue/wall_hedge.tres"),
]

const PLANTS: Array[FoliageDef] = [
	preload("res://games/prison/catalogue/plant_oak.tres"),
	preload("res://games/prison/catalogue/plant_blossom.tres"),
	preload("res://games/prison/catalogue/plant_bush.tres"),
	preload("res://games/prison/catalogue/plant_daffodil.tres"),
	preload("res://games/prison/catalogue/plant_tulip.tres"),
]

const PATHS: Array[PathStyleDef] = [
	preload("res://games/prison/catalogue/path_gravel.tres"),
	preload("res://games/prison/catalogue/path_paving.tres"),
	preload("res://games/prison/catalogue/path_road.tres"),
]

## What prisoners need, and the objects that see to it.
const NEEDS: Array[NeedDef] = [
	preload("res://games/prison/catalogue/need_sleep.tres"),
	preload("res://games/prison/catalogue/need_hunger.tres"),
	preload("res://games/prison/catalogue/need_hygiene.tres"),
]

const ROOM_TYPES: Array[RoomTypeDef] = [
	preload("res://games/prison/catalogue/room_cell.tres"),
	preload("res://games/prison/catalogue/room_canteen.tres"),
	preload("res://games/prison/catalogue/room_shower.tres"),
	preload("res://games/prison/catalogue/room_yard.tres"),
]


static func object(id: StringName) -> ObjectDef:
	for def in OBJECTS:
		if def.id == id:
			return def
	return null


static func room_type(id: StringName) -> RoomTypeDef:
	for def in ROOM_TYPES:
		if def.id == id:
			return def
	return null
