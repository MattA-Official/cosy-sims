class_name TraitDef
extends Resource
## Part of who someone is, such as Chatty or Night owl. Everyone gets two.
## A trait changes numbers that are already there (how fast needs run down,
## what people like to do, how much things upset them) rather than adding
## behaviour of its own, so each game can make its own from the same
## fields.

@export var id: StringName
@export var display_name: String
## One line for the inspector, such as "Needs company; loses it fast".
@export var description: String
## The trait nobody can have alongside this one, such as Loner for Chatty.
@export var opposite: StringName
## Need id: how much faster it runs down (1.5 for half as fast again).
@export var need_rates: Dictionary[StringName, float] = {}
## Object tag or need id: how much more they like doing it (1.5 makes a
## Bookworm pick a book over the yard).
@export var likes: Dictionary[StringName, float] = {}
## Moodlet id: the one they get instead, such as a lovely meal for a
## Foodie rather than a good one.
@export var moodlet_swaps: Dictionary[StringName, StringName] = {}
## Object tag: mood while in a room that has one, such as +3 for plants,
## and how that reads, such as "Plants about".
@export var room_likes: Dictionary[StringName, float] = {}
@export var room_like_text: String
## Bad moodlets count this much more (1.5 for a Hothead).
@export var bad_mood_scale := 1.0
## Trait ids they don't get on with when sharing a room to sleep in.
@export var clashes_with: Array[StringName] = []
## More than this many people close by is a crowd, which gives them
## `crowd_moodlet`; 0 for never.
@export var crowd_limit := 0
@export var crowd_moodlet: StringName
## Mood while their bed is in a dorm rather than a cell of their own.
@export var dorm_mood := 0.0
## A moodlet everyone close by gets from them, such as feeling calmer.
@export var nearby_moodlet: StringName
## When the Sleep block ends before this hour, they get `wake_moodlet`
## (grumbling Night owls, cheerful Early birds). -1 for never.
@export var wake_before_hour := -1
@export var wake_moodlet: StringName
## A mood that is always there, and how it reads, such as Homesick's
## "Misses home" until visits can help.
@export var steady_mood := 0.0
@export var steady_text: String
## How much more (or less) litter they leave about.
@export var litter_scale := 1.0
