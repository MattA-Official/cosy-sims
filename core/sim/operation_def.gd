class_name OperationDef
extends Resource
## Something the prison does at set times of day: the kitchen lorry, the
## intake bus, tool counts. Each time can be moved within a window on the
## Regime page; a fixed one shows where it is but can't be moved.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## When it happens, as half hours of the day (0 is midnight, 47 is 23:30).
@export var times: Array[int] = []
## The earliest and latest half hour any of its times may move to.
@export var earliest := 0
@export var latest := 47
## Half hours that must lie between two of its times.
@export var min_gap := 0
@export var fixed := false
## Why it can't be moved, when fixed, such as "Moves with the rota".
@export var fixed_reason := ""
## Staff role that must be on duty for it, such as &"warden"; empty for none.
@export var needs_role: StringName
## Clash when it falls in a block with this main tag (such as a meal), or
## in one of these activity ids (such as the yard, for a count).
@export var avoid_tags: Array[StringName] = []
@export var avoid_blocks: Array[StringName] = []


static func make(id_: StringName, name: String, about: String, at: Array[int], from: int, to: int,
		gap := 0) -> OperationDef:
	var def := OperationDef.new()
	def.id = id_
	def.display_name = name
	def.description = about
	def.times = at
	def.earliest = from
	def.latest = to
	def.min_gap = gap
	def.fixed = from == to and at.size() == 1
	return def
