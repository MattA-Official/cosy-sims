class_name Surprise
extends RefCounted
## What a running surprise does (see Surprises). Subclasses fill in what
## they need; `main` is the game's root, for reaching its systems.

var def: SurpriseDef
var main: Node
## The harder version, on the hardest difficulty.
var hard := false
var minutes_left := 0.0


func start() -> void:
	pass


func tick(_minutes: float) -> void:
	pass


## Tidies up when its time is over.
func finish() -> void:
	pass


## One of def.choices was picked.
func choose(_index: int) -> void:
	pass


## A few words for the banner under the clock, such as "Hen still loose".
## Empty for the plain name.
func words() -> String:
	return ""


func to_data() -> Dictionary:
	return {}


func from_data(_data: Dictionary) -> void:
	pass
