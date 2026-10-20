class_name Fights
extends Node3D
## Cartoon fights: a dust cloud with stars and bonks where two or more
## prisoners scrap. Each game minute everyone in it lands a blow on someone
## else (more with a weapon from their pocket); a gentle soul may walk off
## instead. Hotheads close by may pile in. A fight peters out after a few
## minutes (sooner but harder with a weapon), or when a guard arrives and
## breaks it up. Everyone who sees it feels worse. Injuries are left to
## the infirmary (see Infirmary).

## Damage a blow does before any weapon, give or take half.
const BASE_HIT := 3.0
## How long fights last, unarmed and armed, in game minutes.
const MINUTES := 4.0
const ARMED_MINUTES := 2.0
## Who may join in: within this many tiles, temper over JOIN_TEMPER, at
## JOIN_CHANCE a minute, up to MAX_FIGHTERS.
const JOIN_DISTANCE := 3.0
const JOIN_TEMPER := 60.0
const JOIN_CHANCE := 0.2
const MAX_FIGHTERS := 4
const GENTLE_LEAVES := 0.5
## Who sees it.
const WITNESS_DISTANCE := 5.0
## Who starts one picks someone within this many tiles.
const REACH := 3.0
const BONKS: Array[String] = ["Bonk!", "Biff!", "Pow!", "Thwack!"]
const CLOUD := preload("res://games/prison/art/models/dust_cloud.glb")


class Fight:
	var fighters: Array[Person] = []
	var level := 0
	var centre := Vector2.ZERO
	var minutes_left := MINUTES
	var armed := false
	var cloud: Node3D


signal started(fight: Fight)
signal ended(fight: Fight)
signal knocked_out(person: Person)

var people: People
var jobs: JobBoard
var prisoner_group: StringName = &"prisoner"
var gentle: StringName = &"gentle"
var saw_moodlet: StringName = &"saw_a_fight"
var saw_nasty_moodlet: StringName = &"saw_a_nasty_fight"
var cell_size := 1.0
## (level, point) -> float: floor height under a point.
var height_at: Callable
## Weapons may come out; off for scuffles only.
var weapons := true
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(_minute: int) -> void: tick())

var fights: Array[Fight] = []
var _rng := RandomNumberGenerator.new()


func start() -> void:
	people.deciders.append(_in_a_fight)
	jobs.rebuilders[&"break_up"] = func(_work: Dictionary) -> Job: return null


## Who someone would pick a fight with: the unhappiest prisoner close by.
func target_for(person: Person) -> Person:
	var best: Person = null
	for other in people.nearby(person, REACH):
		if other.group != prisoner_group or fighting(other) or other.led or other.going_home \
				or Health.injury(other.health) == Health.Injury.KNOCKED_OUT \
				or other.flat().distance_to(person.flat()) > REACH:
			continue
		if best == null or other.mood < best.mood:
			best = other
	return best


func fighting(person: Person) -> bool:
	return fight_of(person) != null


func fight_of(person: Person) -> Fight:
	for fight in fights:
		if fight.fighters.has(person):
			return fight
	return null


## Starts a fight between two people. Returns it, or null if either is
## already in one.
func begin(a: Person, b: Person) -> Fight:
	if fighting(a) or fighting(b):
		return null
	var fight := Fight.new()
	fight.level = a.level
	fight.centre = (a.flat() + b.flat()) / 2.0
	for person: Person in [a, b]:
		_join(fight, person)
	fight.cloud = _cloud()
	add_child(fight.cloud)
	_place(fight)
	fights.append(fight)
	_post_break_up(fight)
	started.emit(fight)
	return fight


## A minute of every fight.
func tick() -> void:
	for fight in fights.duplicate():
		for person in fight.fighters.duplicate():
			if not people.people.has(person):
				fight.fighters.erase(person)
		for person in fight.fighters.duplicate():
			if fight.fighters.size() < 2 or not fight.fighters.has(person):
				break
			var others: Array = fight.fighters.filter(func(p: Person) -> bool: return p != person)
			var target: Person = others[_rng.randi() % others.size()]
			hit(person, target)
			if target.traits.any(func(t: TraitDef) -> bool: return t.id == gentle) and _rng.randf() < GENTLE_LEAVES \
					and Health.injury(target.health) != Health.Injury.KNOCKED_OUT:
				_leave(fight, target)
				people.wander(target)
		# Knocked out, they're out of it.
		for person in fight.fighters.duplicate():
			if Health.injury(person.health) == Health.Injury.KNOCKED_OUT:
				_leave(fight, person)
		_pile_in(fight)
		fight.minutes_left -= 1.0
		if fight.minutes_left <= 0.0 or fight.fighters.size() < 2:
			end(fight)
		else:
			_place(fight)
			(fight.cloud.get_node("Bonk") as Label3D).text = BONKS[_rng.randi() % BONKS.size()]


## One blow, with whatever weapon they have on them.
func hit(person: Person, target: Person) -> void:
	var damage := BASE_HIT * _rng.randf_range(0.5, 1.5) + weapon_hit(person)
	var was_out := Health.injury(target.health) == Health.Injury.KNOCKED_OUT
	target.health = maxf(0.0, target.health - damage)
	if not was_out and Health.injury(target.health) == Health.Injury.KNOCKED_OUT:
		knocked_out.emit(target)


## The extra damage from the best weapon in their pocket.
func weapon_hit(person: Person) -> float:
	if not weapons:
		return 0.0
	var best := 0.0
	for def in person.pocket:
		best = maxf(best, def.hit)
	return best


## Ends a fight: everyone lets go, and those who saw it feel worse.
func end(fight: Fight) -> void:
	if not fights.has(fight):
		return
	fights.erase(fight)
	for person in fight.fighters.duplicate():
		_leave(fight, person)
	for job in jobs.of_kind(&"break_up"):
		if job.get_meta(&"fight") == fight and job.worker == null:
			jobs.cancel(job)
	if fight.cloud != null:
		fight.cloud.queue_free()
	var moodlet := saw_nasty_moodlet if fight.armed else saw_moodlet
	var seen: Dictionary[Person, bool] = {}
	for person in people.people:
		if person.level == fight.level and person.flat().distance_to(fight.centre) <= WITNESS_DISTANCE \
				and person.group == prisoner_group and not seen.has(person):
			seen[person] = true
			people.add_moodlet(person, moodlet)
	ended.emit(fight)


func _join(fight: Fight, person: Person) -> void:
	people.stop(person)
	fight.fighters.append(person)
	person.activity = "Fighting"
	if weapon_hit(person) > 0.0:
		if not fight.armed:
			fight.minutes_left = minf(fight.minutes_left, ARMED_MINUTES)
		fight.armed = true


func _leave(fight: Fight, person: Person) -> void:
	fight.fighters.erase(person)
	if people.people.has(person):
		people.stop(person)


func _pile_in(fight: Fight) -> void:
	if fight.fighters.size() >= MAX_FIGHTERS:
		return
	for person in people.people:
		if fight.fighters.size() >= MAX_FIGHTERS:
			return
		if person.group != prisoner_group or person.level != fight.level or person.temper <= JOIN_TEMPER \
				or fighting(person) or person.led or Health.injury(person.health) >= Health.Injury.HURT \
				or person.flat().distance_to(fight.centre) > JOIN_DISTANCE:
			continue
		if _rng.randf() < JOIN_CHANCE:
			_join(fight, person)
			person.record.append([clock.day() if clock != null else 1, &"fight", "joined a fight"])


## A guard goes to break it up, which ends it.
func _post_break_up(fight: Fight) -> void:
	var job := Job.new()
	job.kind = &"break_up"
	job.title = "Break up a fight"
	job.priority = 6
	job.set_meta(&"fight", fight)
	var stage := Job.on_tile(Job.Do.WORK, fight.level, Vector2i(fight.centre.floor()))
	stage.minutes = 1.0
	stage.doing = "Breaking up a fight"
	stage.finish = func(_stage: Job.Stage, guard: Person) -> void:
		if fights.has(fight):
			# No guns, just a cartoon baton; an armed one lands a blow first.
			if fight.armed and not fight.fighters.is_empty():
				hit(fight.fighters[0], guard)
			end(fight)
	job.stages = [stage]
	jobs.post(job)


## Fighters stay put while it lasts.
func _in_a_fight(person: Person, _may_wander: bool) -> bool:
	if not fighting(person):
		return false
	person.activity = "Fighting"
	return true


func _place(fight: Fight) -> void:
	if fight.cloud == null:
		return
	var y: float = height_at.call(fight.level, fight.centre) if height_at.is_valid() else 0.0
	fight.cloud.position = Vector3(fight.centre.x * cell_size, y, fight.centre.y * cell_size)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for fight in fights:
		if fight.cloud == null:
			continue
		var puff := fight.cloud.get_node("Puff") as Node3D
		puff.scale = Vector3.ONE * cell_size * (1.0 + sin(t * 8.0) * 0.06)
		puff.position.y = absf(sin(t * 6.0)) * 0.05
		fight.cloud.rotation.y = t * 1.5


## A puff of dust, stars and a "Bonk!".
func _cloud() -> Node3D:
	var cloud := Node3D.new()
	var puff := CLOUD.instantiate() as Node3D
	puff.name = "Puff"
	puff.scale = Vector3.ONE * cell_size
	cloud.add_child(puff)
	var stars := Label3D.new()
	stars.name = "Stars"
	stars.text = "★ ★ ★"
	stars.font_size = 48
	stars.outline_size = 12
	stars.pixel_size = 0.006
	stars.modulate = Color(1.0, 0.85, 0.3)
	stars.outline_modulate = Color(0.45, 0.3, 0.1)
	stars.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stars.no_depth_test = true
	stars.position.y = 1.15
	cloud.add_child(stars)
	var bonk := Label3D.new()
	bonk.name = "Bonk"
	bonk.text = BONKS[0]
	bonk.font_size = 56
	bonk.outline_size = 16
	bonk.pixel_size = 0.006
	bonk.modulate = Color(1.0, 0.96, 0.9)
	bonk.outline_modulate = Color(0.6, 0.2, 0.15)
	bonk.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bonk.no_depth_test = true
	bonk.position = Vector3(0.6, 1.75, 0.0)
	cloud.add_child(bonk)
	return cloud
