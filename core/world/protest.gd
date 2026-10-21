class_name Protest
extends Node
## Campaigners at the gate. Each morning's paper builds pressure: a bad
## headline adds PAPER_BAD, a good one takes PAPER_GOOD off, and it falls
## DAILY_FALL a day on its own. At ARRIVE_AT a crowd comes on the morning
## bus with placards about the worst recent topic (ProtestTopicDef) and
## stands by the bus stop, heckling staff, worrying visitors, holding up
## vehicles and costing reputation by the hour; at LEAVE_AT they pack up
## and go. A topic's fix holding at the paper takes FIX_EASE off. Ten good
## days in a row with a fine reputation bring well-wishers with cake for a
## day instead. Never anything worse. Shared by any game.

enum State { NONE, PROTESTING, LEAVING, WELL_WISHERS }

const MOST := 100.0
const PAPER_BAD := 15.0
const PAPER_GOOD := 10.0
const DAILY_FALL := 5.0
const ARRIVE_AT := 40.0
const LEAVE_AT := 15.0
const FIX_EASE := 20.0
## The crowd: FEWEST at ARRIVE_AT, one more each CROWD_STEP, up to CROWD_MOST.
const FEWEST := 3
const CROWD_STEP := 10.0
const CROWD_MOST := 12
## When the crowd comes, on the morning bus.
const ARRIVE_HOUR := 9
## Well-wishers: good days in a row, and the reputation they need.
const GOOD_DAYS := 10
const GOOD_REPUTATION := 75.0
## Hourly reputation news while protesting.
const PROTEST_NEWS := &"protest"
## How near counts as passing the crowd, in tiles, and how long a vehicle
## waits there.
const NEAR := 3.0
const HOLD_MINUTES := 10.0
const LEAVE_MINUTES := 60.0

signal arrived(count: int, friendly: bool)
signal left

var people: People
var reputation: Reputation
var topics: Array[ProtestTopicDef] = []
var group: StringName = &"protestor"
## Whether crowds come at all (the Protestors setting).
var enabled := true
var pressure := 0.0
var topic: StringName = &""
var state := State.NONE
var good_days := 0
## Topic id -> () -> bool: whether its fix holds this morning.
var fixes: Dictionary[StringName, Callable] = {}
## () -> [level, spot]: where the crowd gets off the bus and stands near.
var stop: Callable
## Optional: (arrived: Callable) -> bool sends a bus that calls arrived
## when it pulls up; false if no bus could come.
var send_bus: Callable
## Optional: () -> bool, weather bad enough to send them home.
var stormy: Callable
## Who passing the crowd gets which moodlet: group -> id.
var heckled: Dictionary[StringName, StringName] = {&"staff": &"heckled", &"visitor": &"nervous"}
var cheered: Dictionary[StringName, StringName] = {&"staff": &"cheered_on"}
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(_on_hour)
		clock.minute_passed.connect(func(_minute: int) -> void: tick())
		clock.day_changed.connect(func(_day: int) -> void: midnight())

var _rng := RandomNumberGenerator.new()
var _leaving: Dictionary[Person, float] = {}


func _ready() -> void:
	_rng.randomize()


func attach() -> void:
	if not people.needs_off.has(group):
		people.needs_off.append(group)
	people.deciders.append(_decide)


func topic_def(id: StringName) -> ProtestTopicDef:
	for def in topics:
		if def.id == id:
			return def
	return null


## The crowd at the gate now.
func crowd() -> Array[Person]:
	var out: Array[Person] = []
	for person in people.people:
		if person.group == group:
			out.append(person)
	return out


## The morning paper is out: its tone moves the pressure, and a fix that
## holds eases it.
func read_paper(tone: ReputationEventDef.Tone, about: StringName) -> void:
	match tone:
		ReputationEventDef.Tone.BAD:
			pressure += PAPER_BAD
			if about != &"":
				topic = about
			good_days = 0
		ReputationEventDef.Tone.GOOD:
			pressure -= PAPER_GOOD
			good_days += 1
		_:
			good_days += 1
	if topic != &"" and fixes.has(topic) and fixes[topic].call():
		pressure -= FIX_EASE
	pressure = clampf(pressure, 0.0, MOST)


## Takes some pressure off, such as an open day or a word from the warden.
func ease(amount: float) -> void:
	pressure = clampf(pressure - amount, 0.0, MOST)
	if state == State.PROTESTING and pressure <= LEAVE_AT:
		pack_up()


## How many come at this pressure.
func crowd_size() -> int:
	return mini(FEWEST + floori((pressure - ARRIVE_AT) / CROWD_STEP), CROWD_MOST)


## A crowd arrives at the stop. Returns them.
func gather(friendly := false) -> Array[Person]:
	var out: Array[Person] = []
	var at: Array = stop.call() if stop.is_valid() else []
	if at.is_empty():
		return out
	var count := FEWEST if friendly else crowd_size()
	var def := topic_def(topic)
	for i in count:
		var spot: Vector2 = at[1] + Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5))
		var person := people.add_person(at[0], spot, "", group)
		if person == null:
			person = people.add_person(at[0], at[1], "", group)
		if person == null:
			continue
		person.traits.clear()
		if friendly:
			person.profile["placard"] = ["Well done!", "Thank you, staff!", "We baked you a cake"][i % 3]
		elif def != null and not def.placards.is_empty():
			person.profile["placard"] = def.placards[i % def.placards.size()]
		person.profile["stand"] = [at[0], spot]
		person.bubble = person.profile.get("placard", "")
		out.append(person)
	state = State.WELL_WISHERS if friendly else State.PROTESTING
	arrived.emit(out.size(), friendly)
	return out


## The crowd packs up and heads off.
func pack_up() -> void:
	if state == State.NONE:
		return
	state = State.LEAVING
	for person in crowd():
		if not _leaving.has(person):
			_leaving[person] = 0.0
			person.bubble = ""
			people.stop(person)
	left.emit()


func _on_hour(hour: int) -> void:
	if not enabled:
		if state == State.PROTESTING or state == State.WELL_WISHERS:
			pack_up()
		return
	if state == State.PROTESTING:
		if reputation != null:
			reputation.report(PROTEST_NEWS)
		if pressure <= LEAVE_AT or (stormy.is_valid() and stormy.call()):
			pack_up()
	elif state == State.NONE and hour == ARRIVE_HOUR:
		var friendly := pressure < ARRIVE_AT and good_days >= GOOD_DAYS and reputation != null \
				and reputation.score > GOOD_REPUTATION
		if pressure >= ARRIVE_AT or friendly:
			if not send_bus.is_valid() or not send_bus.call(func() -> void: gather(friendly)):
				gather(friendly)


## Each minute: those passing the crowd feel it, and leavers go.
func tick() -> void:
	var here := crowd()
	if state == State.LEAVING and here.is_empty():
		state = State.NONE
	if state == State.PROTESTING or state == State.WELL_WISHERS:
		var moods := cheered if state == State.WELL_WISHERS else heckled
		for person in people.people:
			if not moods.has(person.group) or person.moodlets.has(moods[person.group]):
				continue
			for member in here:
				if member.level == person.level and member.flat().distance_to(person.flat()) <= NEAR:
					people.add_moodlet(person, moods[person.group])
					break
	var at: Array = stop.call() if stop.is_valid() else []
	for person: Person in _leaving.keys():
		_leaving[person] += 1.0
		var gone: bool = not people.people.has(person) or _leaving[person] >= LEAVE_MINUTES \
				or (not at.is_empty() and person.flat().distance_to(at[1]) <= 1.0)
		if gone:
			_leaving.erase(person)
			if people.people.has(person):
				people.remove_person(person)
		elif person.state == Person.State.IDLE and not at.is_empty():
			people.walk_to(person, at[0], at[1], "Heading for the bus")


## Midnight: pressure eases a little, and well-wishers go home.
func midnight() -> void:
	pressure = maxf(0.0, pressure - DAILY_FALL)
	if state == State.WELL_WISHERS:
		pack_up()


## How long a vehicle passing a point waits for the crowd to part.
func hold_at(point: Vector2) -> float:
	if state != State.PROTESTING:
		return 0.0
	for member in crowd():
		if member.flat().distance_to(point) <= NEAR:
			return HOLD_MINUTES
	return 0.0


## "Protesting about food: Better dinners!" and the fix, for the inspector.
func words(person: Person) -> String:
	if person.group != group:
		return ""
	if state == State.WELL_WISHERS:
		return "Here to cheer the staff on, with cake."
	var def := topic_def(topic)
	if def == null:
		return "Protesting."
	return "Protesting about %s: \"%s\"\nWhat would help: %s." % [def.display_name.to_lower(),
			person.profile.get("placard", ""), def.fix_words]


## Protestors stand by the stop with their placards.
func _decide(person: Person, _may_wander: bool) -> bool:
	if person.group != group:
		return false
	if _leaving.has(person):
		return true
	var stand: Array = person.profile.get("stand", [])
	if not stand.is_empty() and person.flat().distance_to(stand[1]) > 0.6:
		people.walk_to(person, stand[0], stand[1], "Joining the crowd")
		return true
	person.timer = 10.0
	person.activity = "Cheering the staff on" if state == State.WELL_WISHERS else "Waving a placard"
	return true


func capture() -> Dictionary:
	return {"pressure": pressure, "topic": String(topic), "state": state, "good_days": good_days}


func restore(data: Dictionary) -> void:
	pressure = float(data.get("pressure", 0.0))
	topic = StringName(data.get("topic", ""))
	state = int(data.get("state", State.NONE)) as State
	good_days = int(data.get("good_days", 0))
	if state == State.LEAVING and people != null:
		pack_up()
