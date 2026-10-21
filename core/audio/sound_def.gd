class_name SoundDef
extends Resource
## A sound the game can play: one or more takes to pick between at random,
## the bus it plays through and how loud.

@export var id: StringName
@export var streams: Array[AudioStream] = []
## Effects, Interface, Ambience or Music.
@export var bus: StringName = &"Effects"
@export var volume_db := 0.0
## How far each play's pitch may wander either way, as a share.
@export var pitch_spread := 0.05
## Shortest time between two plays, in seconds, so a burst of changes
## makes one sound rather than a clatter.
@export var gap := 0.06
