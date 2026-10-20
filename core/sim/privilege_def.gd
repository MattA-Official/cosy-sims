class_name PrivilegeDef
extends Resource
## Something people can lose for a while as a consequence, such as the yard
## or the telly: objects they may not use, and blocks swapped for others.
## A school's detention or a hospital's visiting ban are the same idea.

@export var id: StringName
@export var display_name: String
## Objects with any of these tags are off limits.
@export var blocks_tags: Array[StringName] = []
## Timetable block id: the block they get instead, such as yard to lockup.
@export var swap_block: Dictionary[StringName, StringName] = {}
