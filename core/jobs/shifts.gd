class_name Shifts
extends Node
## Staff come and go in shifts. For each role and shift there is a number
## wanted; while a shift is on, that many staff of the role are on site,
## and the rest are at home. The next shift arrives at the entrance early
## enough to walk in and be there a little before it starts, and the one
## before goes home once it is over, so no job is left at handover. Staff without a role or shift (put down
## by hand) stay for good.

signal changed
## Someone on their way home has gone.
signal left(person: Person)

## Minutes before a shift starts that its staff are in, after walking from
## the entrance.
const OVERLAP_MINUTES := 15
## Game minutes someone going home may take to get out before they simply
## go.
const LEAVE_MINUTES := 60.0
## Needs are at least this met on arrival.
const FRESH := 90.0
## Tiles from the entrance that count as out.
const OUT_DISTANCE := 1.0

var people: People
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: balance())
var roles: Array[StaffRoleDef] = []
var shifts: Array[ShiftDef] = []
## Where staff arrive and leave, as [level, spot]. Empty arrives them
## where `start_spot` says, and lets them go where they stand.
var entrance: Array = []
## Game minutes to walk in from the entrance.
var walk_in_minutes := 0.0
## Somewhere to stand on site when the game starts, as [level, spot] (or
## [] for nowhere), for staff already at work. Optional.
var start_spot: Callable
## How many of each role are wanted on each shift: role id to shift id to
## count.
var wanted: Dictionary[StringName, Dictionary] = {}

## People on their way home, with game minutes they have been going.
var _leaving: Dictionary[Person, float] = {}
## (role, shift) -> bool: brings someone in another way, such as by car,
## calling come_in() once they're here; false to walk in from the
## entrance as usual.
var ride_in: Callable
## (person) -> Array: where someone leaving heads for, as [level, spot],
## such as their car; empty for the entrance.
var way_out: Callable
## Staff on their way in by ride_in, as [role, shift] pairs.
var _coming: Array = []


## Staff already about (from a sample prison, say) join the shift that is
## on, and count as wanted for it.
func start() -> void:
	var now := on_now()
	if now == null:
		return
	for person in people.people:
		if person.role != &"" and person.shift == &"":
			person.shift = now.id
			set_wanted(person.role, now.id, wanted_for(person.role, now.id) + 1, false)
	balance(true)


## The shift that is on now (the one that started most recently), or null.
func on_now() -> ShiftDef:
	var best: ShiftDef = null
	var best_since := GameClock.MINUTES_PER_DAY
	for shift in shifts:
		var since := posmod(clock.minute_of_day() - shift.start_hour * GameClock.MINUTES_PER_HOUR,
				GameClock.MINUTES_PER_DAY)
		if shift.is_on(clock.minute_of_day()) and since < best_since:
			best = shift
			best_since = since
	return best


func wanted_for(role: StringName, shift: StringName) -> int:
	return wanted.get(role, {}).get(shift, 0)


## Sets how many of a role a shift wants. On a shift that is on, staff
## arrive or go home to match straight away.
func set_wanted(role: StringName, shift: StringName, count: int, now := true) -> void:
	if not wanted.has(role):
		wanted[role] = {}
	wanted[role][shift] = maxi(count, 0)
	if now:
		balance()
	changed.emit()


## Staff of a role on a shift on site now, not counting anyone going home.
func on_site(role: StringName, shift: StringName) -> Array[Person]:
	var out: Array[Person] = []
	for person in people.people:
		if person.role == role and person.shift == shift and not person.going_home:
			out.append(person)
	return out


## Brings in or sends home staff so each shift that is on has as many as
## it wants, and nobody stays from a shift that is over. `at_work` puts
## new arrivals on site rather than at the entrance.
func balance(at_work := false) -> void:
	if people == null or clock == null:
		return
	var minute := clock.minute_of_day()
	for shift in shifts:
		var on := shift.is_on(minute, OVERLAP_MINUTES + ceili(walk_in_minutes))
		for role in roles:
			var here := on_site(role.id, shift.id)
			var want := wanted_for(role.id, shift.id) if on else 0
			var coming := _coming.count([role.id, shift.id])
			for i in want - here.size() - coming:
				_arrive(role.id, shift.id, at_work)
			for i in here.size() - want:
				send_home(here[here.size() - 1 - i])
	for person: Person in _leaving.keys():
		_leaving[person] += 1.0
		var exit := _exit_for(person)
		var out := exit.is_empty() or person.flat().distance_to(exit[1]) <= OUT_DISTANCE \
				or _leaving[person] >= LEAVE_MINUTES
		if out or not people.people.has(person):
			_leaving.erase(person)
			if people.people.has(person):
				people.remove_person(person)
			left.emit(person)
		elif person.state == Person.State.IDLE:
			_head_out(person)


## Sends someone home, finishing nothing: their job goes back on the board.
func send_home(person: Person) -> void:
	if person.going_home:
		return
	person.going_home = true
	people.stop(person)
	_leaving[person] = 0.0
	_head_out(person)
	changed.emit()


func _head_out(person: Person) -> void:
	var exit := _exit_for(person)
	if exit.is_empty() or not people.walk_to(person, exit[0], exit[1], "Going home"):
		person.activity = "Going home"


## Where someone leaving heads: their way out, or the entrance.
func _exit_for(person: Person) -> Array:
	var out: Array = way_out.call(person) if way_out.is_valid() else []
	return out if not out.is_empty() else entrance


## Someone brought in by ride_in is here, at [level, spot].
func come_in(role: StringName, shift: StringName, spot: Array) -> Person:
	var i := _coming.find([role, shift])
	if i == -1:
		return null
	_coming.remove_at(i)
	return _arrive(role, shift, false, spot)


func _arrive(role: StringName, shift: StringName, at_work: bool, at: Array = []) -> Person:
	if at.is_empty() and not at_work and ride_in.is_valid() and ride_in.call(role, shift):
		_coming.append([role, shift])
		return null
	var spot: Array = at if not at.is_empty() else entrance
	if (at_work or spot.is_empty()) and start_spot.is_valid():
		spot = start_spot.call()
	if spot.is_empty():
		return null
	var person := people.add_person(spot[0], spot[1], "", &"staff")
	if person == null:
		return null
	people.set_role(person, role)
	person.shift = shift
	# Fresh from home.
	for need: StringName in person.needs:
		person.needs[need] = maxf(person.needs[need], FRESH)
	changed.emit()
	return person
