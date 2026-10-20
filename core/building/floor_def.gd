class_name FloorDef
extends Resource
## A floor style, such as tiles indoors or a gravel path outdoors.

@export var id: StringName
@export var display_name: String
@export var colour := Color.WHITE
## Outdoor floors (paths, paving, grass) are for yards and grounds.
@export var outdoor := false
## Optional pattern laid over the colour, one repeat a metre: near-white
## greyscale, so the colour still decides how it looks.
@export var texture: Texture2D
## How nice it is to be on, for room quality: 0 for bare concrete, 1 for
## wood.
@export var comfort := 0.0
