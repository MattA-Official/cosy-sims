class_name ResearchBoardDef
extends Resource
## The whole research board for a game: its cards and know-how kinds.

@export var cards: Array[ResearchCardDef] = []
@export var knowhow: Array[KnowhowDef] = []
@export var sources: Array[KnowhowSourceDef] = []
## Department id -> the hire card that brings its head.
@export var hire_cards: Dictionary[StringName, StringName] = {}

var _by_id: Dictionary[StringName, ResearchCardDef] = {}


func card(id: StringName) -> ResearchCardDef:
	if _by_id.size() != cards.size():
		_by_id.clear()
		for def in cards:
			_by_id[def.id] = def
	return _by_id.get(id)


## Cards that need this one.
func children(id: StringName) -> Array[ResearchCardDef]:
	var out: Array[ResearchCardDef] = []
	for def in cards:
		if def.requires.has(id):
			out.append(def)
	return out
