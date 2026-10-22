class_name CastLineDef
extends Resource
## One thing a cast member says in a campaign chapter, and when: &"start",
## &"won", &"nudge" (a bad run), &"goal:<goal id>" when a win goal is done,
## &"first:<counter>" the first time something happens, or &"day:<n>".

@export var who: StringName
@export var trigger: StringName
@export_multiline var words: String
