class_name Sentences
extends Node
## Every prisoner has a sentence in game days, rolled at the bus from
## their security category's range, and a file (see PrisonerFile). Each
## midnight a day is served; whoever reaches their release day is due out.
## Part-way through, they may go before a parole hearing.

signal due_out(person: Person)

enum Length { SHORT, NORMAL, LONG }
const LENGTH_SCALES: Array[float] = [0.6, 1.0, 1.5]
const LENGTH_NAMES: Array[String] = ["Short", "Normal", "Long"]
## Share of the sentence served before parole hearings, and for high
## security.
const PAROLE_SHARE := 0.5
const HIGH_PAROLE_SHARE := 0.66
const STARTING_REFORM := 20.0
const REOFFENDER_REFORM := 10.0
## A grafter arrives already handy at one of these.
const SKILLS: Array[StringName] = [&"cooking", &"woodwork", &"reading", &"laundry", &"cleaning"]
const GRAFTER := &"grafter"
const GRAFTER_SKILL := 20

var people: People
var intake: Intake
var categories: Dictionary[StringName, CategoryDef] = {}
var reform: Progress
var prisoner_group: StringName = &"prisoner"
## A new-game setting: how long sentences run.
var length := Length.NORMAL
var clock: GameClock:
	set(value):
		clock = value
var _rng := RandomNumberGenerator.new()


## Opens files for anyone here without one, part-way through their time
## so they don't all go home on the same day.
func start() -> void:
	intake.arrived.connect(func(came: Array[Person]) -> void:
		for person in came:
			open_file(person))
	for person in people.people:
		if person.group == prisoner_group and not PrisonerFile.of(person).has_sentence():
			open_file(person, true)


## Rolls a sentence for someone arriving. `part_served` starts them
## somewhere in the middle of it.
func open_file(person: Person, part_served := false) -> void:
	var file := PrisonerFile.of(person)
	var category: CategoryDef = categories.get(person.category)
	var low := category.stay_days_min if category != null else 5
	var high := category.stay_days_max if category != null else 12
	var days := maxi(roundi(_rng.randi_range(low, high) * LENGTH_SCALES[length]), 1)
	var today := _today()
	file.sentence_days = days
	file.served_days = _rng.randi_range(0, days - 1) if part_served else 0
	var start := today - file.served_days
	file.release_day = start + days
	var share := HIGH_PAROLE_SHARE if person.category == &"high" else PAROLE_SHARE
	file.parole_from_day = start + ceili(days * share)
	if reform != null and not person.profile.has(reform.def.id):
		reform.set_value(person, REOFFENDER_REFORM if file.came_back > 0 else STARTING_REFORM)
	if person.traits.any(func(t: TraitDef) -> bool: return t.id == GRAFTER) and file.skills.is_empty():
		file.raise_skill(SKILLS[_rng.randi() % SKILLS.size()], GRAFTER_SKILL)
	file.add_log(today, "Arrived to serve %d days" % days)


## A day served by everyone. Called at midnight.
func tick() -> void:
	var today := _today()
	for person in people.people.duplicate():
		if person.group != prisoner_group:
			continue
		var file := PrisonerFile.of(person)
		if not file.has_sentence():
			continue
		file.served_days += 1
		if today >= file.release_day and not file.due_out:
			file.due_out = true
			due_out.emit(person)


## "Day 4 of 9 · parole from day 5", for the inspector.
func summary(person: Person) -> String:
	var file := PrisonerFile.of(person)
	if not file.has_sentence():
		return ""
	var words := "Day %d of %d" % [mini(file.served_days + 1, file.sentence_days), file.sentence_days]
	if file.due_out:
		return words + " · going home"
	if _today() < file.parole_from_day:
		words += " · parole from day %d" % file.parole_from_day
	return words + " · out on day %d" % file.release_day


func _today() -> int:
	return clock.day() if clock != null else 1
