class_name ResearchBoardDef
extends Resource
## The whole research board for a game: its cards and know-how kinds.

@export var cards: Array[ResearchCardDef] = []
@export var knowhow: Array[KnowhowDef] = []
@export var sources: Array[KnowhowSourceDef] = []
## Department id -> the hire card that brings its head.
@export var hire_cards: Dictionary[StringName, StringName] = {}
## Know-how kind -> the department whose head brings it to a joint card.
@export var kind_departments: Dictionary[StringName, StringName] = {}
## One repeatable card per department, offered once its wedge is done.
@export var refinements: Array[ResearchCardDef] = []

var _by_id: Dictionary[StringName, ResearchCardDef] = {}


func card(id: StringName) -> ResearchCardDef:
	if _by_id.size() != cards.size() + refinements.size():
		_by_id.clear()
		for def in cards + refinements:
			_by_id[def.id] = def
	return _by_id.get(id)


## Cards that need this one.
## The refinement for a department, or null.
func refinement(department: StringName) -> ResearchCardDef:
	for def in refinements:
		if def.department == department:
			return def
	return null


func children(id: StringName) -> Array[ResearchCardDef]:
	var out: Array[ResearchCardDef] = []
	for def in cards:
		if def.requires.has(id):
			out.append(def)
	return out
