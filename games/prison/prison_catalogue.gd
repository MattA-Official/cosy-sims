class_name PrisonCatalogue
## Everything the prison game can build. Edit the .tres files in catalogue/
## in the inspector to tweak sizes and colours.

const OBJECTS: Array[ObjectDef] = [
	preload("res://games/prison/catalogue/bed.tres"),
	preload("res://games/prison/catalogue/toilet.tres"),
	preload("res://games/prison/catalogue/sink.tres"),
	preload("res://games/prison/catalogue/desk.tres"),
	preload("res://games/prison/catalogue/table.tres"),
	preload("res://games/prison/catalogue/shower.tres"),
	preload("res://games/prison/catalogue/radio.tres"),
	preload("res://games/prison/catalogue/coffee_machine.tres"),
	preload("res://games/prison/catalogue/tv.tres"),
	preload("res://games/prison/catalogue/bookshelf.tres"),
	preload("res://games/prison/catalogue/games_table.tres"),
	preload("res://games/prison/catalogue/weights_bench.tres"),
	preload("res://games/prison/catalogue/basketball_hoop.tres"),
	preload("res://games/prison/catalogue/bench.tres"),
	preload("res://games/prison/catalogue/rug.tres"),
	preload("res://games/prison/catalogue/poster.tres"),
	preload("res://games/prison/catalogue/plant_pot.tres"),
	preload("res://games/prison/catalogue/wall_shelf.tres"),
	preload("res://games/prison/catalogue/lift.tres"),
	preload("res://games/prison/catalogue/fridge.tres"),
	preload("res://games/prison/catalogue/food_shelf.tres"),
	preload("res://games/prison/catalogue/cooker.tres"),
	preload("res://games/prison/catalogue/serving_counter.tres"),
	preload("res://games/prison/catalogue/delivery_pallet.tres"),
	preload("res://games/prison/catalogue/bin.tres"),
	preload("res://games/prison/catalogue/skip.tres"),
	preload("res://games/prison/catalogue/laundry_basket.tres"),
	preload("res://games/prison/catalogue/washing_machine.tres"),
	preload("res://games/prison/catalogue/ironing_board.tres"),
	preload("res://games/prison/catalogue/clothes_shelf.tres"),
	preload("res://games/prison/catalogue/workbench.tres"),
	preload("res://games/prison/catalogue/guard_desk.tres"),
	preload("res://games/prison/catalogue/goods_shelf.tres"),
]

## Things people carry about.
const ITEMS: Array[ItemDef] = [
	preload("res://games/prison/catalogue/item_food_crate.tres"),
	preload("res://games/prison/catalogue/item_meal_tray.tres"),
	preload("res://games/prison/catalogue/item_litter_paper.tres"),
	preload("res://games/prison/catalogue/item_litter_can.tres"),
	preload("res://games/prison/catalogue/item_litter_wrapper.tres"),
	preload("res://games/prison/catalogue/item_rubbish_bag.tres"),
	preload("res://games/prison/catalogue/item_dirty_laundry.tres"),
	preload("res://games/prison/catalogue/item_clean_laundry.tres"),
	preload("res://games/prison/catalogue/item_wooden_toy.tres"),
	preload("res://games/prison/catalogue/item_birdhouse.tres"),
]
## What people drop as litter.
const LITTER: Array[ItemDef] = [
	preload("res://games/prison/catalogue/item_litter_paper.tres"),
	preload("res://games/prison/catalogue/item_litter_can.tres"),
	preload("res://games/prison/catalogue/item_litter_wrapper.tres"),
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
	preload("res://games/prison/catalogue/wall_grey.tres"),
	preload("res://games/prison/catalogue/wall_tiles.tres"),
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

## The kinds of people, and who may go where.
const GROUPS: Array[GroupDef] = [
	preload("res://games/prison/catalogue/group_prisoner.tres"),
	preload("res://games/prison/catalogue/group_staff.tres"),
	preload("res://games/prison/catalogue/group_visitor.tres"),
]

const ZONES: Array[ZoneDef] = [
	preload("res://games/prison/catalogue/zone_shared.tres"),
	preload("res://games/prison/catalogue/zone_staff.tres"),
	preload("res://games/prison/catalogue/zone_visitors.tres"),
	preload("res://games/prison/catalogue/zone_everyone.tres"),
]
## Rooms nobody has painted, and whose type names no zone.
const DEFAULT_ZONE := &"shared"

## Kinds of staff, and the jobs each takes.
const ROLES: Array[StaffRoleDef] = [
	preload("res://games/prison/catalogue/role_cook.tres"),
	preload("res://games/prison/catalogue/role_cleaner.tres"),
	preload("res://games/prison/catalogue/role_handyman.tres"),
	preload("res://games/prison/catalogue/role_guard.tres"),
]

## Staff shifts. Days start at 06:00 so the cook is in for breakfast;
## nights pay half as much again.
const SHIFTS: Array[ShiftDef] = [
	preload("res://games/prison/catalogue/shift_day.tres"),
	preload("res://games/prison/catalogue/shift_night.tres"),
]

## Work prisoners can do in work blocks.
const PROGRAMMES: Array[WorkProgrammeDef] = [
	preload("res://games/prison/catalogue/programme_kitchen.tres"),
	preload("res://games/prison/catalogue/programme_laundry.tres"),
	preload("res://games/prison/catalogue/programme_cleaning.tres"),
	preload("res://games/prison/catalogue/programme_workshop.tres"),
]

const DOOR_KINDS: Array[DoorKindDef] = [
	preload("res://games/prison/catalogue/door_staff.tres"),
	preload("res://games/prison/catalogue/door_security_gate.tres"),
]

## What prisoners need, and what sees to it.
const NEEDS: Array[NeedDef] = [
	preload("res://games/prison/catalogue/need_sleep.tres"),
	preload("res://games/prison/catalogue/need_hunger.tres"),
	preload("res://games/prison/catalogue/need_hygiene.tres"),
	preload("res://games/prison/catalogue/need_bladder.tres"),
	preload("res://games/prison/catalogue/need_recreation.tres"),
	preload("res://games/prison/catalogue/need_outdoors.tres"),
	preload("res://games/prison/catalogue/need_social.tres"),
	preload("res://games/prison/catalogue/need_energy.tres"),
]

## Who prisoners can be: everyone gets two of these.
const TRAITS: Array[TraitDef] = [
	preload("res://games/prison/catalogue/trait_night_owl.tres"),
	preload("res://games/prison/catalogue/trait_early_bird.tres"),
	preload("res://games/prison/catalogue/trait_tidy.tres"),
	preload("res://games/prison/catalogue/trait_messy.tres"),
	preload("res://games/prison/catalogue/trait_bookworm.tres"),
	preload("res://games/prison/catalogue/trait_sporty.tres"),
	preload("res://games/prison/catalogue/trait_chatty.tres"),
	preload("res://games/prison/catalogue/trait_loner.tres"),
	preload("res://games/prison/catalogue/trait_foodie.tres"),
	preload("res://games/prison/catalogue/trait_green_fingers.tres"),
	preload("res://games/prison/catalogue/trait_hothead.tres"),
	preload("res://games/prison/catalogue/trait_gentle.tres"),
	preload("res://games/prison/catalogue/trait_light_fingered.tres"),
	preload("res://games/prison/catalogue/trait_homesick.tres"),
	preload("res://games/prison/catalogue/trait_grafter.tres"),
	preload("res://games/prison/catalogue/trait_lazy.tres"),
]

## Things that happen to prisoners and lift or lower their mood a while.
const MOODLETS: Array[MoodletDef] = [
	preload("res://games/prison/catalogue/moodlet_good_meal.tres"),
	preload("res://games/prison/catalogue/moodlet_missed_meal.tres"),
	preload("res://games/prison/catalogue/moodlet_grubby_uniform.tres"),
	preload("res://games/prison/catalogue/moodlet_useful_day.tres"),
	preload("res://games/prison/catalogue/moodlet_made_to_work.tres"),
	preload("res://games/prison/catalogue/moodlet_walked_back.tres"),
	preload("res://games/prison/catalogue/moodlet_lovely_meal.tres"),
	preload("res://games/prison/catalogue/moodlet_locked_up_hungry.tres"),
	preload("res://games/prison/catalogue/moodlet_had_an_accident.tres"),
	preload("res://games/prison/catalogue/moodlet_woken_too_early.tres"),
	preload("res://games/prison/catalogue/moodlet_up_with_the_lark.tres"),
	preload("res://games/prison/catalogue/moodlet_calmed.tres"),
	preload("res://games/prison/catalogue/moodlet_too_crowded.tres"),
	preload("res://games/prison/catalogue/moodlet_good_chat.tres"),
	preload("res://games/prison/catalogue/moodlet_fresh_air.tres"),
	preload("res://games/prison/catalogue/moodlet_feels_clean.tres"),
	preload("res://games/prison/catalogue/moodlet_slept_well.tres"),
	preload("res://games/prison/catalogue/moodlet_had_fun.tres"),
]

## Models drawn by code rather than placed from the catalogue (see
## games/prison/art/).
const DOOR_MODEL := preload("res://games/prison/art/models/door.glb")
const PERSON_MODEL := preload("res://games/prison/art/models/person.glb")

## Every block the timetable can hold, in the order the timetable window
## shows them.
const ACTIVITIES: Array[ActivityDef] = [
	preload("res://games/prison/catalogue/activity_sleep.tres"),
	preload("res://games/prison/catalogue/activity_lockup.tres"),
	preload("res://games/prison/catalogue/activity_eat.tres"),
	preload("res://games/prison/catalogue/activity_shower.tres"),
	preload("res://games/prison/catalogue/activity_yard.tres"),
	preload("res://games/prison/catalogue/activity_free.tres"),
	preload("res://games/prison/catalogue/activity_work.tres"),
]

## The prisoners' day: 11 hours in their cells overnight, three meals, a
## shower, the yard and free time. Work is free time until jobs arrive.
const SCHEDULE: Schedule = preload("res://games/prison/catalogue/schedule_prisoners.tres")

## Rooms where a bed is someone's own.
const HOME_ROOM_TYPES: Array[StringName] = [&"cell", &"dorm"]

const ROOM_TYPES: Array[RoomTypeDef] = [
	preload("res://games/prison/catalogue/room_cell.tres"),
	preload("res://games/prison/catalogue/room_dorm.tres"),
	preload("res://games/prison/catalogue/room_canteen.tres"),
	preload("res://games/prison/catalogue/room_shower.tres"),
	preload("res://games/prison/catalogue/room_yard.tres"),
	preload("res://games/prison/catalogue/room_kitchen.tres"),
	preload("res://games/prison/catalogue/room_laundry.tres"),
	preload("res://games/prison/catalogue/room_workshop.tres"),
	preload("res://games/prison/catalogue/room_guard_post.tres"),
]


static func object(id: StringName) -> ObjectDef:
	for def in OBJECTS:
		if def.id == id:
			return def
	return null


## Every moodlet, by id, as People wants them.
## Who may go where, set up with the prison's groups, zones and doors.
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


## Door models by door kind, for the building views.
static func door_models() -> Dictionary[StringName, PackedScene]:
	var out: Dictionary[StringName, PackedScene] = {}
	for def in DOOR_KINDS:
		if def.model != null:
			out[def.id] = def.model
	return out


static func roles() -> Dictionary[StringName, StaffRoleDef]:
	var out: Dictionary[StringName, StaffRoleDef] = {}
	for def in ROLES:
		out[def.id] = def
	return out


static func programmes() -> Dictionary[StringName, WorkProgrammeDef]:
	var out: Dictionary[StringName, WorkProgrammeDef] = {}
	for def in PROGRAMMES:
		out[def.id] = def
	return out


static func moodlets() -> Dictionary[StringName, MoodletDef]:
	var out: Dictionary[StringName, MoodletDef] = {}
	for def in MOODLETS:
		out[def.id] = def
	return out


static func item(id: StringName) -> ItemDef:
	for def in ITEMS:
		if def.id == id:
			return def
	return null


static func room_type(id: StringName) -> RoomTypeDef:
	for def in ROOM_TYPES:
		if def.id == id:
			return def
	return null
