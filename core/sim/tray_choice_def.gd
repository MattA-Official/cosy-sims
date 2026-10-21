class_name TrayChoiceDef
extends Resource
## One answer to an in-tray card, such as "Yes, a guitar".

@export var label: String
## What happens, as plain dictionaries the game's effect runner knows, such
## as {"money": -40} or {"moodlet": &"guitar", "who": "subject"}.
@export var effects: Array[Dictionary] = []
## Tags delegation rules match, such as &"approve" or &"decline".
@export var tags: Array[StringName] = []
## One line for afterwards, such as "Gus got his guitar".
@export var why: String
