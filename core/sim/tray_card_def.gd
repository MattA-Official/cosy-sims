class_name TrayCardDef
extends Resource
## A kind of card for the in-tray: a request or a letter with two or three
## answers, one of which happens by itself when the card runs out of days.

@export var id: StringName
@export var title: String
## With {who} for the card's subject, such as "{who} asks for a guitar".
@export_multiline var body: String
## &"prisoner_request", &"staff_request", &"memo" or &"complaint".
@export var kind: StringName
## &"prisoner", &"staff" or &"" for who {who} is.
@export var subject: StringName
## Chance weight in the daily roll.
@export var weight := 1.0
@export var min_prisoners := 0
## 1 for Light red tape and up, 2 for Full only.
@export var red_tape := 1
@export var choices: Array[TrayChoiceDef] = []
@export var default_choice := 0
@export var deadline_days := 2


static func make(id: StringName, kind: StringName, subject: StringName, title: String, body: String,
		choices: Array, default_choice := 0) -> TrayCardDef:
	var def := TrayCardDef.new()
	def.id = id
	def.kind = kind
	def.subject = subject
	def.title = title
	def.body = body
	def.choices.assign(choices)
	def.default_choice = default_choice
	return def


static func choice(label: String, effects: Array, tags: Array, why := "") -> TrayChoiceDef:
	var out := TrayChoiceDef.new()
	out.label = label
	out.effects.assign(effects)
	out.tags.assign(tags)
	out.why = why
	return out
