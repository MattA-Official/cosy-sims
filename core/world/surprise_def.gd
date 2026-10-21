class_name SurpriseDef
extends Resource
## One small surprise that tests a system or two, such as an escaped hen
## or flu week (see Surprises). Its behaviour is a Surprise script.

@export var id: StringName
@export var display_name: String
## Relative chance when a surprise is drawn.
@export var weight := 1.0
## Seasons it comes in; empty for any.
@export var seasons: Array[StringName] = []
## Conditions the game names, such as &"has_kitchen"; all must hold.
@export var requires: Array[StringName] = []
## Not before this game day, and not again for this long.
@export var min_day := 1
@export var cooldown_days := 10
## How long it lasts.
@export var hours := 6.0
## A Surprise subclass that does it.
@export var behaviour: Script
## What the card or pop-up says.
@export_multiline var card_text: String
## Optional answers; the default happens after Surprises.CHOICE_MINUTES.
@export var choices: Array[String] = []
@export var default_choice := 0
