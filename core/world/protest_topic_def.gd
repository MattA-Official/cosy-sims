class_name ProtestTopicDef
extends Resource
## What a crowd at the gate is upset about (see Protest): its placards and
## the fix that calms it, which the game checks each morning.

@export var id: StringName
@export var display_name: String
@export var placards: Array[String] = []
## The fix, for the inspector, such as "Serve good meals for two days".
@export var fix_words: String
