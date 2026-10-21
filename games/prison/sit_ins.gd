class_name SitIns
extends Node
## The cosy riot. When most of a crowd of prisoners in one room are very
## unhappy about the same thing, they sit down where they are with a
## placard and won't budge. Fixing what they're upset about stands them
## up again; so does a guard (or, twice as fast, the warden) talking them
## round. Left for hours, the angriest two come to blows.

## Fewest prisoners in a room for a sit-in, the share of them that must be
## this unhappy, and how likely an unhappy newcomer is to join.
const MIN_CROWD := 6
const SHARE := 0.6
const MOOD_UNDER := 25.0
const JOIN_UNDER := 30.0
const JOIN_CHANCE := 0.3
const GENTLE_DAMPS := 0.1
## How long until it boils over, and how long a guard takes to talk them
## round (the warden takes half).
const BOIL_MINUTES := 360.0
const TALK_MINUTES := 20.0
## Minutes they take to stand up once the cause is gone.
const FIXED_MINUTES := 10.0
const LISTENED_MOODLET := &"listened_to"

## What's on the placard, and the hint for fixing it, by complaint.
const DEMANDS: Dictionary[String, Array] = {
	"Hungry": ["Proper dinners!", "check the kitchen is cooking and the canteen has seats"],
	"Missed a meal": ["Proper dinners!", "check the kitchen is cooking and the canteen has seats"],
	"Tired": ["Let us sleep!", "check everyone has a bed and the timetable has enough sleep"],
	"Worn out": ["Let us sleep!", "check everyone has a bed and the timetable has enough sleep"],
	"Grubby": ["Hot showers!", "build more showers or give them shower time"],
	"Needs the loo": ["More loos!", "build more toilets"],
	"Bored": ["Something to do!", "add a TV, games or a gym, and free time"],
	"Cooped up": ["Fresh air!", "give them yard time"],
	"Lonely": ["Let us chat!", "give them free time together"],
}

class SitIn:
	var level: int
	var room: Room
	var members: Array[Person] = []
	var cause: String
	var demand: String
	var hint: String
	var minutes := 0.0
	## Talked round, 0 to 1.
	var talked := 0.0
	## Minutes since the cause went away for most of them, or -1.
	var fixed_for := -1.0
	var job: Job

signal started(sit_in: SitIn)
signal ended(sit_in: SitIn, how: String)

var people: People
var jobs: JobBoard
var fights: Fights
var prisoner_group: StringName = &"prisoner"
var warden_role: StringName = &"warden"
var gentle: StringName = &"gentle"
var enabled := true
var sit_ins: Array[SitIn] = []
## (talker, sit-in) -> float: how much faster someone talks them round,
## such as a guard they know well. Optional.
var talk_speed: Callable
## (crowd) -> int: the fewest who can start a sit-in in this crowd, such
## as a clique needing fewer. Optional; MIN_CROWD otherwise.
var crowd_least: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(minute: int) -> void:
			tick()
			if minute % 60 == 0:
				check())
## People who walked in on a sit-in and chose not to join it.
var _passed: Dictionary[Person, SitIn] = {}
var _rng := RandomNumberGenerator.new()


func start() -> void:
	people.deciders.push_front(_sitting)
	people.person_removed.connect(func(person: Person) -> void:
		for sit_in in sit_ins:
			sit_in.members.erase(person)
		_passed.erase(person))


## The sit-in someone is in, or null.
func sit_in_of(person: Person) -> SitIn:
	for sit_in in sit_ins:
		if sit_in.members.has(person):
			return sit_in
	return null


## Looks for a crowd ready to sit in. Returns any that started.
func check() -> Array[SitIn]:
	var out: Array[SitIn] = []
	if not enabled:
		return out
	var crowds: Dictionary[Room, Array] = {}
	for person in people.people:
		if person.group != prisoner_group or person.led or person.lying or sit_in_of(person) != null:
			continue
		var here := people.room_of(person)
		if here.is_empty():
			continue
		if not crowds.has(here[1]):
			crowds[here[1]] = [here[0]]
		crowds[here[1]].append(person)
	for room: Room in crowds:
		var level: int = crowds[room][0]
		var crowd: Array = crowds[room].slice(1)
		var sit_in := try_start(level, room, crowd)
		if sit_in != null:
			out.append(sit_in)
	return out


## Starts a sit-in if enough of this crowd are unhappy about the same thing.
func try_start(level: int, room: Room, crowd: Array) -> SitIn:
	var least: int = crowd_least.call(crowd) if crowd_least.is_valid() else MIN_CROWD
	if crowd.size() < least:
		return null
	var unhappy: Array = crowd.filter(func(p: Person) -> bool: return p.mood < MOOD_UNDER)
	if unhappy.size() < crowd.size() * SHARE:
		return null
	var cause := Grievance.shared(unhappy)
	if cause.is_empty():
		return null
	var sit_in := SitIn.new()
	sit_in.level = level
	sit_in.room = room
	sit_in.cause = cause
	var demand: Array = DEMANDS.get(cause, ["Fair's fair!", "cheer them up: " + cause.to_lower()])
	sit_in.demand = demand[0]
	sit_in.hint = demand[1]
	for person: Person in unhappy:
		if person.traits.any(func(t: TraitDef) -> bool: return t.id == gentle):
			continue
		_join(sit_in, person)
	if sit_in.members.size() < least * SHARE:
		for person in sit_in.members:
			_stand_up(person)
		return null
	sit_ins.append(sit_in)
	started.emit(sit_in)
	return sit_in


func tick(minutes := 1.0) -> void:
	for sit_in in sit_ins.duplicate():
		sit_in.minutes += minutes
		for person in sit_in.members:
			person.bubble = sit_in.demand
			person.bubble_minutes = 5.0
		_spread(sit_in)
		# Fixed: most of them no longer mind.
		var still: Array = sit_in.members.filter(func(p: Person) -> bool: return Grievance.has(p, sit_in.cause, 5))
		if still.size() * 2 <= sit_in.members.size():
			sit_in.fixed_for = maxf(sit_in.fixed_for, 0.0) + minutes
			if sit_in.fixed_for >= FIXED_MINUTES:
				end(sit_in, "fixed")
				continue
		else:
			sit_in.fixed_for = -1.0
		# Talking them round.
		var talker: Person = sit_in.job.worker if sit_in.job != null else null
		if talker != null and talker.state == Person.State.USING:
			sit_in.talked += minutes / TALK_MINUTES * (2.0 if talker.role == warden_role else 1.0) \
					* (talk_speed.call(talker, sit_in) if talk_speed.is_valid() else 1.0)
			if sit_in.talked >= 1.0:
				end(sit_in, "talked")
				continue
		if sit_in.minutes >= BOIL_MINUTES:
			end(sit_in, "boiled")
			continue
		if sit_in.members.size() < 2:
			end(sit_in, "fizzled")


## Sends a guard (or the warden) to talk them round.
func negotiate(sit_in: SitIn) -> Job:
	if sit_in.job != null and jobs.jobs.has(sit_in.job):
		return sit_in.job
	var job := Job.new()
	job.kind = &"negotiate"
	job.title = "Talk round the sit-in"
	job.priority = 5
	var centre := sit_in.room.centre()
	var tile := Vector2i(centre.floor())
	if not sit_in.room.cells.has(tile):
		tile = sit_in.room.cells[sit_in.room.cells.size() / 2]
	var talk := Job.on_tile(Job.Do.WORK, sit_in.level, tile)
	talk.minutes = TALK_MINUTES
	talk.doing = "Talking them round"
	talk.finish = func(_stage: Job.Stage, _worker: Person) -> void:
		if sit_ins.has(sit_in):
			end(sit_in, "talked")
	job.stages = [talk]
	sit_in.job = job
	jobs.post(job)
	return job


## Ends a sit-in: "fixed", "talked", "boiled" (the angriest two fight) or
## "fizzled".
func end(sit_in: SitIn, how: String) -> void:
	sit_ins.erase(sit_in)
	if sit_in.job != null and jobs.jobs.has(sit_in.job):
		jobs.cancel(sit_in.job)
	var members := sit_in.members.duplicate()
	for person: Person in members:
		_stand_up(person)
		person.bubble = ""
		person.record.append([clock.day() if clock != null else 1, &"sit_in",
				"sat in over %s" % sit_in.cause.to_lower()])
		if how == "talked":
			people.add_moodlet(person, LISTENED_MOODLET)
	for person: Person in _passed.keys():
		if _passed[person] == sit_in:
			_passed.erase(person)
	if how == "boiled" and members.size() >= 2 and fights != null:
		members.sort_custom(func(a: Person, b: Person) -> bool: return a.temper > b.temper)
		fights.begin(members[0], members[1])
	ended.emit(sit_in, how)


## What the sit-in is about, for toasts and the report.
static func words(sit_in: SitIn, room_name: String) -> String:
	return "A sit-in in the %s over %s" % [room_name, sit_in.cause.to_lower()]


## Unhappy prisoners walking in may sit down too.
func _spread(sit_in: SitIn) -> void:
	var gentle_ones := 0
	var newcomers: Array[Person] = []
	for person in people.people:
		if person.group != prisoner_group or sit_in.members.has(person) or person.led or person.lying:
			continue
		var here := people.room_of(person)
		if here.is_empty() or here[1] != sit_in.room:
			if _passed.get(person) == sit_in:
				_passed.erase(person)
			continue
		if person.traits.any(func(t: TraitDef) -> bool: return t.id == gentle):
			gentle_ones += 1
		elif person.mood < JOIN_UNDER and _passed.get(person) != sit_in and sit_in_of(person) == null:
			newcomers.append(person)
	for person in newcomers:
		if _rng.randf() < maxf(JOIN_CHANCE - GENTLE_DAMPS * gentle_ones, 0.0):
			_join(sit_in, person)
		else:
			_passed[person] = sit_in


func _join(sit_in: SitIn, person: Person) -> void:
	people.stop(person)
	person.sitting = true
	person.bubble = sit_in.demand
	person.bubble_minutes = 5.0
	sit_in.members.append(person)


func _stand_up(person: Person) -> void:
	person.sitting = false
	if not person.lying:
		people.set_block(person, person.block)


## Members stay sat down; their temper holds where it was.
func _sitting(person: Person, _may_wander: bool) -> bool:
	var sit_in := sit_in_of(person)
	if sit_in == null:
		return false
	person.activity = "Sitting in"
	person.reason = "%s (over %s)" % [sit_in.demand, sit_in.cause.to_lower()]
	return true
