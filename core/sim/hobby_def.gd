class_name HobbyDef
extends Resource
## Something people love doing, such as chess or painting. Using one of its
## objects fills Fun (the recreation need) faster, cheers them up and
## builds a skill. Shared by any game with residents; each game keeps its
## own as .tres files.

@export var id: StringName
@export var display_name: String
## Objects that let them do it, by tag.
@export var object_tags: Array[StringName] = []
## Fun fills this much faster doing it.
@export var fill_scale := 2.0
## Traits that make it likelier at arrival, such as Green fingers for
## gardening.
@export var likes_traits: Array[StringName] = []
## What a club of it is called, such as "The Knitting Circle".
@export var club_name: String
## An item made now and then while doing it (a painting, a scarf), or none.
@export var makes_item: StringName
## Life-log words when they finish one, such as "Painted a picture".
@export var made_words: String
