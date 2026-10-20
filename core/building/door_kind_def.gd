class_name DoorKindDef
extends Resource
## A door that lets only some people through, such as a staff door. Plain
## doors have no kind and let through anyone allowed in the rooms either
## side.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## The groups of people (Person.group) who may walk through.
@export var groups: Array[StringName] = []
## The little plate over the door that marks it.
@export var colour := Color.WHITE
@export var icon: Texture2D
## Drawn in the doorway in place of the plain door, filling a one-metre
## opening along its x. Optional.
@export var model: PackedScene
## What fitting one costs, when money is on.
@export var price := 0
## Beeps at anyone walking through carrying something metal.
@export var detects_metal := false


func lets_through(group: StringName) -> bool:
	return groups.has(group)
