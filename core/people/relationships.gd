class_name Relationships
extends Node
## Who gets on with whom. Time spent together in the same room makes
## bonds grow, clashing traits sour them, and events move them (a fight,
## a quiet-room spell, a trade). A bond of FRIEND_AT or more is a friend,
## RIVAL_AT or less a rival. Pairs are kept sparsely, so only those who
## have met cost anything. Shared by any game with residents.

## A bond's range, and where friends and rivals start.
const MOST := 100.0
const FRIEND_AT := 40.0
const RIVAL_AT := -40.0
## Bond gained a game hour together, and lost when traits clash.
const GAIN := 0.5
const CLASH_LOSS := 1.0
## Sharing a trait or a hobby makes it grow this much faster.
const SHARED_SCALE := 1.5
## Cellmates spend nights and lock-up together: twice the gain.
const CELLMATE_SCALE := 2.0
## A first meeting starts here when they share a trait, or minus it when
## their traits clash.
const FIRST_BOND := 20.0
## Bonds drift this much a day towards 0 for pairs who didn't meet.
const DAILY_FADE := 2.0
## Game minutes between looks at who is together.
const TICK_MINUTES := 2.0
## Mood near friends and rivals, and the most friends count for.
const FRIEND_MOOD := 2.0
const FRIEND_MOOD_MOST := 6.0
const RIVAL_MOOD := -3.0
const RIVAL_MOOD_MOST := -6.0
## Misconduct odds near a rival.
const RIVAL_ODDS := 1.1

## Staff rapport: how well a member of staff knows a resident, 0 to 100,
## gained each shift they work where that resident is, and its effects
## above RAPPORT_FROM.
const RAPPORT_SHIFT := 2.0
const RAPPORT_FADE := 1.0
const RAPPORT_FROM := 50.0
const RAPPORT_MOST_EFFECT := 0.2

signal became_friends(a: Person, b: Person)
signal became_rivals(a: Person, b: Person)

var people: People
## Groups whose people form bonds.
var groups: Array[StringName] = [&"prisoner"]
## (a, b) -> float: how much faster a pair's bond grows for what they share
## beyond traits, such as a hobby. Optional; 1 means nothing extra.
var share_scale: Callable
## (lower id, higher id) -> bond, -100 to 100.
var bonds: Dictionary[Vector2i, float] = {}
## (staff record id, resident person id) -> rapport, 0 to 100.
var rapport: Dictionary[Vector2i, float] = {}
## Rapport pairs that grew today, kept from fading.
var _rapport_today: Dictionary[Vector2i, bool] = {}
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void:
			_wait -= 1.0
			if _wait <= 0.0:
				_wait = TICK_MINUTES
				tick(TICK_MINUTES))
		clock.day_changed.connect(func(_day: int) -> void:
			fade()
			_fade_rapport())

## Pairs that spent time together today, kept from fading.
var _met_today: Dictionary[Vector2i, bool] = {}
var _wait := 0.0


static func key(a: Person, b: Person) -> Vector2i:
	return Vector2i(mini(a.id, b.id), maxi(a.id, b.id))


func bond(a: Person, b: Person) -> float:
	return bonds.get(key(a, b), 0.0)


func is_friend(a: Person, b: Person) -> bool:
	return bond(a, b) >= FRIEND_AT


func is_rival(a: Person, b: Person) -> bool:
	return bond(a, b) <= RIVAL_AT


## Moves a pair's bond, telling anyone listening when they become friends
## or rivals.
func change(a: Person, b: Person, amount: float) -> void:
	if a == b or a == null or b == null:
		return
	var k := key(a, b)
	var was: float = bonds.get(k, 0.0)
	var now := clampf(was + amount, -MOST, MOST)
	if absf(now) < 0.01:
		bonds.erase(k)
	else:
		bonds[k] = now
	if was < FRIEND_AT and now >= FRIEND_AT:
		became_friends.emit(a, b)
	elif was > RIVAL_AT and now <= RIVAL_AT:
		became_rivals.emit(a, b)


## How two people get on, or would if they shared a cell: "Friends",
## "Likely friends (both Sporty)", "Likely rivals (Tidy and Messy)" or
## "Strangers".
func predict(a: Person, b: Person) -> String:
	var b_now := bond(a, b)
	if b_now >= FRIEND_AT:
		return "Friends"
	if b_now <= RIVAL_AT:
		return "Rivals"
	if people != null and people._clash(a, b):
		for t in a.traits:
			for other in b.traits:
				if t.clashes_with.has(other.id) or other.clashes_with.has(t.id):
					return "Likely rivals (%s and %s)" % [t.display_name, other.display_name]
	for t in a.traits:
		if b.traits.has(t):
			return "Likely friends (both %s)" % t.display_name
	return "Getting on" if b_now > 10.0 else "Not getting on" if b_now < -10.0 else "Strangers"


## Someone's friends or rivals, strongest first, as [Person, bond] pairs.
func friends_of(person: Person) -> Array:
	return _others(person, func(b: float) -> bool: return b >= FRIEND_AT, true)


func rivals_of(person: Person) -> Array:
	return _others(person, func(b: float) -> bool: return b <= RIVAL_AT, false)


func _others(person: Person, keep: Callable, high_first: bool) -> Array:
	var out: Array = []
	if people == null:
		return out
	var by_id: Dictionary[int, Person] = {}
	for other in people.people:
		by_id[other.id] = other
	for k: Vector2i in bonds:
		if (k.x == person.id or k.y == person.id) and keep.call(bonds[k]):
			var other: Person = by_id.get(k.y if k.x == person.id else k.x)
			if other != null:
				out.append([other, bonds[k]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] if high_first else a[1] < b[1])
	return out


## Pairs in the same room, awake (or cellmates asleep at home), grow
## closer; clashing traits drift apart.
func tick(minutes: float) -> void:
	if people == null:
		return
	var hours := minutes / 60.0
	for person in people.people:
		if not groups.has(person.group) or person.state == Person.State.WALKING:
			continue
		var here := people.room_of(person)
		for other in people.nearby(person):
			# Each pair once.
			if other.id <= person.id or other.group != person.group or other.state == Person.State.WALKING:
				continue
			if not People._same_place(here, people.room_of(other)):
				continue
			var cellmates := _cellmates(person, other)
			if (people.is_asleep(person) or people.is_asleep(other)) and not cellmates:
				continue
			var k := key(person, other)
			if not bonds.has(k):
				_first_meeting(person, other)
			_met_today[k] = true
			var rate := GAIN
			if people._clash(person, other):
				rate = -CLASH_LOSS
			else:
				if person.traits.any(func(t: TraitDef) -> bool: return other.traits.has(t)):
					rate *= SHARED_SCALE
				if share_scale.is_valid():
					rate *= share_scale.call(person, other)
			if cellmates:
				rate *= CELLMATE_SCALE
			change(person, other, rate * hours)


func _first_meeting(a: Person, b: Person) -> void:
	if people._clash(a, b):
		change(a, b, -FIRST_BOND)
	elif a.traits.any(func(t: TraitDef) -> bool: return b.traits.has(t)):
		change(a, b, FIRST_BOND)
	else:
		bonds[key(a, b)] = 0.01


func _cellmates(a: Person, b: Person) -> bool:
	var home := people.home_room(a)
	return not home.is_empty() and People._same_place(home, people.home_room(b))


## Pairs that didn't meet today drift back towards 0; the gone are
## forgotten.
func fade() -> void:
	var here: Dictionary[int, bool] = {}
	if people != null:
		for person in people.people:
			here[person.id] = true
	for k: Vector2i in bonds.keys():
		if people != null and not (here.has(k.x) and here.has(k.y)):
			bonds.erase(k)
			continue
		if _met_today.has(k):
			continue
		var b: float = bonds[k]
		b = maxf(0.0, b - DAILY_FADE) if b > 0.0 else minf(0.0, b + DAILY_FADE)
		if absf(b) < 0.01:
			bonds.erase(k)
		else:
			bonds[k] = b
	_met_today.clear()


## Mood parts from friends and rivals close by: "Near Bea" and "Gus is
## about", for People.mood_extras.
func mood_parts(person: Person, _here: Array) -> Array:
	var out: Array = []
	if people == null or not groups.has(person.group):
		return out
	var friends: Array[String] = []
	var rivals: Array[String] = []
	for other in people.nearby(person):
		var b := bond(person, other)
		if b >= FRIEND_AT:
			friends.append(other.name.get_slice(" ", 0))
		elif b <= RIVAL_AT:
			rivals.append(other.name.get_slice(" ", 0))
	if not friends.is_empty():
		out.append(["Near %s" % People._who(friends), minf(FRIEND_MOOD * friends.size(), FRIEND_MOOD_MOST)])
	if not rivals.is_empty():
		out.append(["%s %s about" % [People._who(rivals), "is" if rivals.size() == 1 else "are"],
				maxf(RIVAL_MOOD * rivals.size(), RIVAL_MOOD_MOST)])
	return out


## Whether a rival is within reach, for misconduct odds.
func rival_near(person: Person) -> bool:
	if people == null:
		return false
	for other in people.nearby(person):
		if is_rival(person, other):
			return true
	return false


## "Friends: Bea, Gus. Rivals: Ann." for the inspector, or "".
func words(person: Person) -> String:
	var parts: Array[String] = []
	var friends := friends_of(person).slice(0, 3).map(func(p: Array) -> String: return "♥ %s" % (p[0] as Person).name)
	var rivals := rivals_of(person).slice(0, 3).map(func(p: Array) -> String: return "☁ %s" % (p[0] as Person).name)
	if not friends.is_empty():
		parts.append("Friends: %s" % ", ".join(friends))
	if not rivals.is_empty():
		parts.append("Rivals: %s" % ", ".join(rivals))
	return "\n".join(parts)


## A shift's worth of rapport between a member of staff (by record id) and
## a resident they worked near.
func add_rapport(staff_id: int, resident: Person, amount := RAPPORT_SHIFT) -> void:
	var k := Vector2i(staff_id, resident.id)
	rapport[k] = clampf(rapport.get(k, 0.0) + amount, 0.0, MOST)
	_rapport_today[k] = true


func rapport_of(staff_id: int, resident: Person) -> float:
	return rapport.get(Vector2i(staff_id, resident.id), 0.0)


## 1 at RAPPORT_FROM or less, down to 1 - RAPPORT_MOST_EFFECT at 100: how
## much a well-known face slows temper or speeds talking.
static func rapport_scale(amount: float) -> float:
	return 1.0 - RAPPORT_MOST_EFFECT * clampf((amount - RAPPORT_FROM) / (MOST - RAPPORT_FROM), 0.0, 1.0)


func _fade_rapport() -> void:
	for k: Vector2i in rapport.keys():
		if _rapport_today.has(k):
			continue
		rapport[k] -= RAPPORT_FADE
		if rapport[k] <= 0.0:
			rapport.erase(k)
	_rapport_today.clear()


static func _pack(store: Dictionary) -> Dictionary:
	var out := {}
	for k: Vector2i in store:
		out["%d,%d" % [k.x, k.y]] = store[k]
	return out


static func _unpack(data: Dictionary, into: Dictionary) -> void:
	into.clear()
	for text: String in data:
		var ids := text.split(",")
		into[Vector2i(int(ids[0]), int(ids[1]))] = float(data[text])


func capture() -> Dictionary:
	return {"bonds": _pack(bonds), "rapport": _pack(rapport)}


func restore(data: Dictionary) -> void:
	_unpack(data.get("bonds", {}), bonds)
	_unpack(data.get("rapport", {}), rapport)
