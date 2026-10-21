class_name Progress
extends RefCounted
## Moves one ProgressDef for people, by named sources, within each
## source's daily cap and the def's cap on a day's gains, and remembers
## what each gave today so the inspector can say why.
##
##   progress.add(person, &"good_day")  # +2, unless capped
##   progress.today_text(person)        # "+4 today: Good day +2, Work shift +2"

signal changed(person: Person)

var def: ProgressDef
var sources: Dictionary[StringName, ProgressSourceDef] = {}
## () -> float: multipliers on gains (not losses), such as research cards
## that speed reform.
var gain_scales: Array[Callable] = []


func _init(progress_def: ProgressDef = null, source_defs: Array = []) -> void:
	def = progress_def
	for source: ProgressSourceDef in source_defs:
		sources[source.id] = source


func value(person: Person) -> float:
	return person.profile.get(def.id, def.start)


func set_value(person: Person, amount: float) -> void:
	person.profile[def.id] = clampf(amount, 0.0, 100.0)
	changed.emit(person)


## Applies a source `times` over. Returns how much it actually moved.
func add(person: Person, source_id: StringName, times := 1.0) -> float:
	var source: ProgressSourceDef = sources.get(source_id)
	if source == null:
		push_warning("No progress source %s" % source_id)
		return 0.0
	var amount := source.amount * times
	if amount > 0.0:
		for scale in gain_scales:
			amount *= scale.call()
	var today := _today(person)
	if amount > 0.0:
		var given: float = today.get(source_id, 0.0)
		if source.per_day_cap > 0.0:
			amount = minf(amount, maxf(source.per_day_cap - given, 0.0))
		if not source.milestone:
			var gained := 0.0
			for id: StringName in today:
				var counted: ProgressSourceDef = sources.get(id)
				if counted == null or not counted.milestone:
					gained += maxf(today[id], 0.0)
			amount = minf(amount, maxf(def.daily_cap - gained, 0.0))
	var before := value(person)
	var after := clampf(before + amount, 0.0, 100.0)
	if is_zero_approx(after - before) and is_zero_approx(amount):
		return 0.0
	today[source_id] = today.get(source_id, 0.0) + amount
	person.profile[def.id] = after
	changed.emit(person)
	return after - before


## What each source gave today, by id.
func _today(person: Person) -> Dictionary:
	var key := String(def.id) + "_today"
	if not person.profile.has(key):
		person.profile[key] = {}
	return person.profile[key]


## Today's change and its parts, such as "+4 today: Good day +2, Work
## shift +2", or "" if nothing moved it.
func today_text(person: Person) -> String:
	var today := _today(person)
	var parts := PackedStringArray()
	var sum := 0.0
	for id: StringName in today:
		var amount: float = today[id]
		if is_zero_approx(amount):
			continue
		sum += amount
		var source: ProgressSourceDef = sources.get(id)
		parts.append("%s %+d" % [source.text if source != null else String(id), roundi(amount)])
	if parts.is_empty():
		return ""
	return "%+d today: %s" % [roundi(sum), ", ".join(parts)]


## Starts a fresh day for everyone: today's caps reset.
func new_day(people: Array[Person]) -> void:
	var key := String(def.id) + "_today"
	for person in people:
		person.profile.erase(key)
