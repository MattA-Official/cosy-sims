class_name RevealDef
extends Resource
## What turns a face-down research card face up.

enum Kind { START, COUNT, FIRST, BUILT, EVENT, SETTING, GRADE, LEAN, ADDON, HEAD_LEVEL, PRISONER }

@export var kind := Kind.START
## A Counters id (COUNT, FIRST, EVENT), room type (BUILT), setting
## (SETTING) or add-on (ADDON).
@export var id: StringName
## The threshold for COUNT, stars for GRADE, level for HEAD_LEVEL, and +1
## strict or -1 caring for LEAN.
@export var count := 1
## A setting's value, such as &"self_sufficient".
@export var value: Variant
## The "Turns up" words on the card back, such as "10 drug finds".
@export var hint: String
## Whether word of mouth turns it up too, a while after everything it
## needs is done.
@export var fallback := true
