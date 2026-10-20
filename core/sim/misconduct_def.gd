class_name MisconductDef
extends Resource
## One rung of the misconduct ladder, such as grumbling or vandalism: how
## unhappy someone must be to do it, and how it shows. What it actually
## does is up to the game (see games/prison/misconduct.gd).

@export var id: StringName
## How it reads in someone's record, such as "broke the %s".
@export var display_name: String
## Highest mood that allows this rung.
@export var mood_below := 45.0
## Game days spent under mood_below first, for rungs that take planning.
@export var days_below := 0.0
## Base weight when picking among the rungs someone may reach.
@export var weight := 1.0
## Trait id: how much likelier they are to pick this rung (2 for a
## Hothead's fights).
@export var trait_weights: Dictionary[StringName, float] = {}
## A warning shown over their head first, for this many game minutes; 0 for
## none. A guard turning up or mood lifting calls it off.
@export var warning_minutes := 10.0
## What shows over their head while warning, or grumbling, kept short so
## a crowd stays readable; "%s", if used, is filled with the worst thing on
## their mind.
@export var bubble := "%s"
## Given to everyone close by who sees it.
@export var witness_moodlet: StringName
## Points on their record, for consequences; 0 leaves no record.
@export var points := 1
