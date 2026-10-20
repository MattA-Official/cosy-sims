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

## What prisoners need, and what sees to it.
const NEEDS: Array[NeedDef] = [
	preload("res://games/prison/catalogue/need_sleep.tres"),
	preload("res://games/prison/catalogue/need_hunger.tres"),
	preload("res://games/prison/catalogue/need_hygiene.tres"),
	preload("res://games/prison/catalogue/need_bladder.tres"),
	preload("res://games/prison/catalogue/need_recreation.tres"),
	preload("res://games/prison/catalogue/need_outdoors.tres"),
	preload("res://games/prison/catalogue/need_social.tres"),
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
]


static func object(id: StringName) -> ObjectDef:
	for def in OBJECTS:
		if def.id == id:
			return def
	return null


## Every moodlet, by id, as People wants them.
static func moodlets() -> Dictionary[StringName, MoodletDef]:
	var out: Dictionary[StringName, MoodletDef] = {}
	for def in MOODLETS:
		out[def.id] = def
	return out


static func room_type(id: StringName) -> RoomTypeDef:
	for def in ROOM_TYPES:
		if def.id == id:
			return def
	return null
