class_name AirportCatalogue
## Everything the airport game can build. Edit the .tres files in
## catalogue/ in the inspector to tweak sizes and colours. A few plain
## things (toilets, sinks, bins, plants, the lift) are borrowed from the
## prison's catalogue until the airport has its own.

## Tabs of the objects menu, in order (see ObjectDef.category).
const OBJECT_CATEGORIES: Array[String] = ["Check-in", "Gates", "Signs", "Movers", "Facilities", "Staff",
		"Decoration"]
const OBJECTS: Array[ObjectDef] = [
	preload("res://games/airport/catalogue/check_in_desk.tres"),
	preload("res://games/airport/catalogue/check_in_kiosk.tres"),
	preload("res://games/airport/catalogue/queue_post.tres"),
	preload("res://games/airport/catalogue/info_desk.tres"),
	preload("res://games/airport/catalogue/gate_desk.tres"),
	preload("res://games/airport/catalogue/seat_row.tres"),
	preload("res://games/airport/catalogue/departures_board.tres"),
	preload("res://games/airport/catalogue/sign_gates.tres"),
	preload("res://games/airport/catalogue/sign_check_in.tres"),
	preload("res://games/airport/catalogue/sign_toilets.tres"),
	preload("res://games/airport/catalogue/sign_exit.tres"),
	preload("res://games/airport/catalogue/escalator_up.tres"),
	preload("res://games/airport/catalogue/escalator_down.tres"),
	preload("res://games/airport/catalogue/travelator.tres"),
	preload("res://games/prison/catalogue/lift.tres"),
	preload("res://games/prison/catalogue/toilet.tres"),
	preload("res://games/prison/catalogue/sink.tres"),
	preload("res://games/prison/catalogue/bin.tres"),
	preload("res://games/prison/catalogue/office_desk.tres"),
	preload("res://games/prison/catalogue/chair.tres"),
	preload("res://games/prison/catalogue/coffee_machine.tres"),
	preload("res://games/prison/catalogue/plant_pot.tres"),
	preload("res://games/prison/catalogue/bench.tres"),
]

const FLOORS: Array[FloorDef] = [
	preload("res://games/airport/catalogue/floor_terrazzo.tres"),
	preload("res://games/airport/catalogue/floor_carpet.tres"),
	preload("res://games/airport/catalogue/floor_concrete.tres"),
	preload("res://games/airport/catalogue/floor_tiles.tres"),
	preload("res://games/airport/catalogue/floor_tarmac.tres"),
	preload("res://games/airport/catalogue/floor_paving.tres"),
	preload("res://games/airport/catalogue/floor_lawn.tres"),
]

const WALLS: Array[WallDef] = [
	preload("res://games/airport/catalogue/wall_panels.tres"),
	preload("res://games/airport/catalogue/wall_glass.tres"),
	preload("res://games/airport/catalogue/wall_brick.tres"),
	preload("res://games/airport/catalogue/wall_airside_fence.tres"),
	preload("res://games/airport/catalogue/wall_hedge.tres"),
]

const PLANTS: Array[FoliageDef] = [
	preload("res://games/prison/catalogue/plant_oak.tres"),
	preload("res://games/prison/catalogue/plant_bush.tres"),
	preload("res://games/prison/catalogue/plant_daffodil.tres"),
	preload("res://games/prison/catalogue/plant_tulip.tres"),
]

const PATHS: Array[PathStyleDef] = [
	preload("res://games/airport/catalogue/path_footpath.tres"),
	preload("res://games/airport/catalogue/path_road.tres"),
]

## The kinds of people, and who may go where.
const GROUPS: Array[GroupDef] = [
	preload("res://games/airport/catalogue/group_passenger.tres"),
	preload("res://games/airport/catalogue/group_visitor.tres"),
	preload("res://games/airport/catalogue/group_staff.tres"),
]

## Who may be where: landside and airside, with the line between them.
const ZONES: Array[ZoneDef] = [
	preload("res://games/airport/catalogue/zone_landside.tres"),
	preload("res://games/airport/catalogue/zone_airside.tres"),
	preload("res://games/airport/catalogue/zone_arrivals.tres"),
	preload("res://games/airport/catalogue/zone_international.tres"),
	preload("res://games/airport/catalogue/zone_staff_landside.tres"),
	preload("res://games/airport/catalogue/zone_staff_airside.tres"),
	preload("res://games/airport/catalogue/zone_restricted.tres"),
]
## Rooms nobody has painted, whose type names no zone, are landside.
const DEFAULT_ZONE := &"landside"

const DOOR_KINDS: Array[DoorKindDef] = [
	preload("res://games/airport/catalogue/door_staff_security.tres"),
	preload("res://games/airport/catalogue/door_screening.tres"),
]

const ROOM_TYPES: Array[RoomTypeDef] = [
	preload("res://games/airport/catalogue/room_check_in_hall.tres"),
	preload("res://games/airport/catalogue/room_departure_lounge.tres"),
	preload("res://games/airport/catalogue/room_gate.tres"),
	preload("res://games/airport/catalogue/room_arrivals_hall.tres"),
	preload("res://games/airport/catalogue/room_toilets.tres"),
	preload("res://games/airport/catalogue/room_bag_hall.tres"),
	preload("res://games/airport/catalogue/room_staff_room.tres"),
	preload("res://games/airport/catalogue/room_office.tres"),
	preload("res://games/airport/catalogue/room_kerb.tres"),
]

## Needs, borrowed from the prison for now; the airport's own (thirst,
## stress, connection) come with passengers.
const NEEDS: Array[NeedDef] = [
	preload("res://games/prison/catalogue/need_hunger.tres"),
	preload("res://games/prison/catalogue/need_bladder.tres"),
]

const DOOR_MODEL := preload("res://games/prison/art/models/door.glb")
const PERSON_MODEL := preload("res://games/prison/art/models/person.glb")

## The build toolbar's tools, in order: as the prison's, less patrol routes
## and utilities, plus belts. Keys 1 to 9 then 0, then Z, C and B.
const TOOLS := [
	[BuildController.Tool.ROOM, "Room", "Drag out a floor with walls all round.", "tool_room"],
	[BuildController.Tool.WALL, "Wall", "Build or restyle walls, glass and fences.", "tool_wall"],
	[BuildController.Tool.FLOOR, "Floor", "Lay or restyle floors, build stairs, or leave a void for a double-height hall.", "tool_floor"],
	[BuildController.Tool.OPENING, "Doors and windows", "Put a door, one-way door, badge door or window in a wall.", "tool_opening"],
	[BuildController.Tool.OBJECT, "Objects", "Place desks, seats, signs, escalators and more.", "tool_object"],
	[BuildController.Tool.ROOM_TYPE, "Room type", "Mark a room as a check-in hall, gate and so on.", "tool_room_type"],
	[BuildController.Tool.PATH, "Paths", "Lay paths and roads, with stairs and bridges.", "tool_path"],
	[BuildController.Tool.PLANTS, "Plants", "Plant trees, bushes and flowers.", "tool_plants"],
	[BuildController.Tool.TERRAIN, "Terrain", "Shape the ground, or add and drain water.", "tool_terrain"],
	[BuildController.Tool.DEMOLISH, "Demolish", "Remove objects and walls, or clear an area.", "tool_demolish"],
	[BuildController.Tool.ZONE, "Zones", "Say who may go where: landside, airside and staff only. Doors across the line show red unless they are a checkpoint.", "tool_zones"],
	[BuildController.Tool.BELT, "Belts", "Lay conveyor belts for bags: along, then across, the way they run.", "tool_belt"],
	[BuildController.Tool.MOVE, "Move and templates", "Pick up an object, a room or a box of things and put it somewhere else. Ctrl+C and Ctrl+V copy; keep rooms as templates.", "tool_move"],
]
const GROUP_STARTS: Array[int] = [6, 9, 10, 12]
const EXTRA_KEYS: Array[String] = ["Z", "C", "B"]

const FLOOR_MODES := [
	[BuildController.FloorMode.LAY, "Lay", "mode_lay", "Lay or restyle floor."],
	[BuildController.FloorMode.RAISE, "Raise", "mode_raise", "Nudge a floor up within its storey."],
	[BuildController.FloorMode.LOWER, "Lower", "mode_lower", "Nudge a floor down within its storey."],
	[BuildController.FloorMode.RAMP, "Ramp", "mode_ramp", "Slope a floor between two heights."],
	[BuildController.FloorMode.STAIRS, "Stairs", "mode_stairs", "Build a staircase up to the next storey."],
	[BuildController.FloorMode.VOID, "Void", "mode_void", "Leave an upper floor open so the room below is a double-height hall."],
]

## Each is [wall kind, door kind or window kind, name, icon, what it does,
## one-way].
const OPENINGS := [
	[BuildingMap.Wall.DOOR, &"", "Door", "opening_door", "A door people can walk through.", false],
	[BuildingMap.Wall.DOOR, &"", "One-way door", "opening_one_way", "People only go through from the side you click; click again to turn it round. For arrivals and exits from reclaim.", true],
	[BuildingMap.Wall.DOOR, &"staff_security", "Staff security door", "opening_badge_door", "A badge reader: only staff walk through. A proper crossing between landside and airside.", false],
	[BuildingMap.Wall.DOOR, &"screening", "Screening point", "opening_screening", "Where passengers cross from landside to airside.", false],
	[BuildingMap.Wall.WINDOW, BuildingMap.WINDOW_GLASS, "Glass window", "opening_glass", "Lets light in and lets people see out.", false],
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


static func access() -> Access:
	var out := Access.new()
	for def in GROUPS:
		out.groups[def.id] = def
	for def in ZONES:
		out.zones[def.id] = def
	for def in DOOR_KINDS:
		out.door_kinds[def.id] = def
	for def in ROOM_TYPES:
		out.room_types[def.id] = def
	out.default_zone = DEFAULT_ZONE
	return out


## Map sizes a new airport can take, smallest first.
const MAP_SIZES: Array[MapSizeDef] = [
	preload("res://games/airport/catalogue/map_small.tres"),
	preload("res://games/airport/catalogue/map_medium.tres"),
	preload("res://games/airport/catalogue/map_large.tres"),
]


static func map_size(id: StringName) -> MapSizeDef:
	for def in MAP_SIZES:
		if def.id == id:
			return def
	return MAP_SIZES[0]
