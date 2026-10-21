class_name Modifiers
extends Node
## Named numbers that bonuses add to, such as &"search_speed" +0.1 from a
## Chief of Security. Each source (a head, a trait, later a research card)
## sets its own amounts; a system reads the sum when it needs it, so no
## system is told about heads directly.
##
##   modifiers.set_source(&"head_security", {&"search_speed": 0.1})
##   var faster := 1.0 + modifiers.value(&"search_speed")

signal changed

## Source id -> {modifier: amount}.
var sources: Dictionary[StringName, Dictionary] = {}
## Source id -> [{modifier: amount}, (person) -> bool]: amounts that count
## only for some people, such as a policy tried in one wing.
var scoped: Dictionary[StringName, Array] = {}


func set_source(id: StringName, amounts: Dictionary) -> void:
	if sources.get(id, {}) == amounts:
		return
	sources[id] = amounts.duplicate()
	changed.emit()


func clear_source(id: StringName) -> void:
	if sources.erase(id):
		changed.emit()


## The sum of every source's amount for a modifier; 0 when none.
func value(modifier: StringName) -> float:
	var sum := 0.0
	for id: StringName in sources:
		sum += float(sources[id].get(modifier, 0.0))
	return sum


func set_scoped(id: StringName, amounts: Dictionary, applies: Callable) -> void:
	scoped[id] = [amounts.duplicate(), applies]
	changed.emit()


func clear_scoped(id: StringName) -> void:
	if scoped.erase(id):
		changed.emit()


## The sum for one person: every source, and the scoped ones that apply
## to them.
func value_for(modifier: StringName, person: Object) -> float:
	var sum := value(modifier)
	for id: StringName in scoped:
		var entry: Array = scoped[id]
		if (entry[0] as Dictionary).has(modifier) and (entry[1] as Callable).call(person):
			sum += float(entry[0][modifier])
	return sum


## value_for from a Modifiers node that may be missing.
static func amount_for(of: Modifiers, modifier: StringName, person: Object) -> float:
	return of.value_for(modifier, person) if of != null else 0.0


## The modifier's sum, or 0 from a missing Modifiers node.
static func amount(of: Modifiers, modifier: StringName) -> float:
	return of.value(modifier) if of != null else 0.0


## 1 plus the modifier, for scaling a speed or an amount; a missing
## Modifiers node scales by 1.
static func scale(of: Modifiers, modifier: StringName) -> float:
	return 1.0 + of.value(modifier) if of != null else 1.0
