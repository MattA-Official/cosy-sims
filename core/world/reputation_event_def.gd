class_name ReputationEventDef
extends Resource
## One kind of news the town hears about, such as an escape or an open
## day, and how much it moves the place's reputation (see Reputation).

enum Tone { GOOD, BAD, NEUTRAL }

@export var id: StringName
## Points added to the 0–100 score.
@export var change := 0.0
@export var tone := Tone.NEUTRAL
## What it's about, for protestors' placards: overcrowding, food, soft,
## safety, kindness.
@export var topic: StringName
## Headlines to pick from. {name} is the subject, such as a prisoner.
@export var headlines: Array[String] = []
## Which story leads the paper: the heaviest of the day.
@export var weight := 1
## At most once a day, for news that comes in hourly, such as a sit-in.
@export var once_a_day := false
