class_name StaffRoster
extends Node
## Everyone on the payroll, by name. Each member of staff is hired from the
## day's applicants for one role on one shift, at the wage they asked for,
## and keeps their name, look and traits whenever they come in. Shifts
## brings in whoever is on the roster for the shift that's on.
##
## Morale drifts towards how they feel at work (their mood while on site)
## and how their pay compares with the going rate, MORALE_STEP a day at
## most. Under QUIT_MORALE for QUIT_DAYS days running, they hand in their
## notice. A raise lifts it; letting someone go costs a day's pay.
##
## Staff get better with practice: XP_MINUTES of finished work is a point
## of experience, and LEVEL_XP points make each level, which works faster
## (LEVEL_PACE) and is paid WAGE_STEP more a level. Low morale brings sick
## days: each night, under SICK_LINE, a chance of a day off tomorrow.

signal changed
## Someone handed in their notice and won't be back.
signal quit(record: Record)
signal levelled_up(record: Record)
## Someone won't be in tomorrow.
signal off_sick(record: Record)

const MORALE_START := 70.0
const MORALE_STEP := 5.0
const QUIT_MORALE := 20.0
const QUIT_DAYS := 5
## Morale points for each 1% their pay is over (or under) the going rate.
const PAY_MORALE := 1.0
## Applicants for each role and shift, at least and at most, and the days
## each waits for an answer.
const APPLICANTS := Vector2i(1, 2)
const APPLICANT_DAYS := 3
## What applicants ask, against the role's going rate.
const ASKING := Vector2(0.85, 1.2)
const RAISE := 0.1
## Experience for levels 2 to 5, and how fast each level works.
const LEVEL_XP: Array[float] = [2.0, 5.0, 9.0, 14.0]
const LEVEL_PACE: Array[float] = [1.0, 1.1, 1.1, 1.15, 1.15]
const MOST_LEVEL := 5
const XP_MINUTES := 480.0
const WAGE_STEP := 0.05
## Under this morale, each point under is SICK_CHANCE more chance a night
## of a sick day tomorrow.
const SICK_LINE := 40.0
const SICK_CHANCE := 0.005

## One member of staff, or an applicant hoping to be.
class Record:
	var id := 0
	var name := ""
	var role: StringName = &""
	var shift: StringName = &""
	var traits: Array[TraitDef] = []
	var wage := 0
	var morale := MORALE_START
	var low_days := 0
	var hired_day := 0
	var look_seed := 0
	var level := 1
	var xp := 0.0
	## Off sick through this day.
	var off_until := 0
	## An applicant's last day of waiting.
	var until := 0
	## On site now, or null; and on their way in by car or bus.
	var person: Person
	var coming := false
	## Their mood at work, summed each hour, for tonight's morale.
	var mood_sum := 0.0
	var mood_hours := 0

	func first_name() -> String:
		return name.get_slice(" ", 0)

var people: People
var roles: Array[StaffRoleDef] = []
var shifts: Array[ShiftDef] = []
## The traits staff can have.
var trait_pool: Array[TraitDef] = []
## (amount) -> void: pays notice to someone let go. Optional.
var pay: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(_hour: int) -> void: _sample())
		clock.day_changed.connect(func(_day: int) -> void: nightly())

var records: Array[Record] = []
var applicants: Array[Record] = []
var next_id := 1
var _rng := RandomNumberGenerator.new()


func start() -> void:
	people.person_removed.connect(func(person: Person) -> void:
		var record := record_of(person)
		if record != null:
			record.person = null
			record.coming = false)
	if applicants.is_empty():
		refresh_applicants()


## Staff on a role and shift.
func on(role: StringName, shift: StringName) -> Array[Record]:
	return records.filter(func(r: Record) -> bool: return r.role == role and r.shift == shift)


func count(role: StringName, shift: StringName) -> int:
	return on(role, shift).size()


func record_of(person: Person) -> Record:
	var id: int = person.profile.get("staff_id", 0)
	if id == 0:
		return null
	for record in records:
		if record.id == id:
			return record
	return null


## The next of a role and shift to come in: not here and not on their way.
func next_in(role: StringName, shift: StringName) -> Record:
	for record in on(role, shift):
		if record.person == null and not record.coming and not is_off(record):
			return record
	return null


## Whether someone is off sick today.
func is_off(record: Record) -> bool:
	return record.off_until >= _day()


## Experience for someone, levelling them up as they pass each line.
func add_xp(record: Record, amount: float) -> void:
	record.xp += amount
	while record.level < MOST_LEVEL and record.xp >= LEVEL_XP[record.level - 1]:
		record.level += 1
		levelled_up.emit(record)
	changed.emit()


## Experience for a finished job: its time at work.
func job_done(job: Job, worker: Person) -> void:
	var record := record_of(worker)
	if record == null:
		return
	var minutes := 0.0
	for stage in job.stages:
		minutes += stage.minutes if stage.do == Job.Do.WORK else 2.0
	add_xp(record, minutes / XP_MINUTES)


## How fast someone works for their level; 1 for anyone not on staff.
func pace(person: Person) -> float:
	var record := record_of(person)
	return LEVEL_PACE[record.level - 1] if record != null else 1.0


## Takes on an applicant. Returns their record, or null.
func hire(applicant: Record) -> Record:
	if not applicants.has(applicant):
		return null
	applicants.erase(applicant)
	applicant.hired_day = _day()
	applicant.morale = MORALE_START
	records.append(applicant)
	changed.emit()
	return applicant


## Takes someone on straight away, without applying: for sample prisons,
## old saves and tests.
func take_on(role: StringName, shift: StringName) -> Record:
	var record := _make(role, shift)
	record.hired_day = _day()
	records.append(record)
	changed.emit()
	return record


## Lets someone go, with a day's pay as notice unless told otherwise.
## Whoever is on site goes home.
func dismiss(record: Record, notice := true) -> void:
	if not records.has(record):
		return
	records.erase(record)
	if notice and pay.is_valid():
		pay.call(day_pay(record))
	changed.emit()


## A raise of RAISE on their wage.
func raise(record: Record) -> void:
	record.wage = roundi(record.wage * (1.0 + RAISE) / 5.0) * 5
	changed.emit()


## Someone already on site with a role, joining the roster as they are.
func adopt(person: Person) -> Record:
	var record := _make(person.role, person.shift)
	record.name = person.name
	record.traits = person.traits.filter(func(t: TraitDef) -> bool:
			return trait_pool.is_empty() or trait_pool.has(t))
	person.traits = record.traits.duplicate()
	record.look_seed = person.look_seed if person.look_seed >= 0 else person.id
	person.look_seed = record.look_seed
	record.hired_day = _day()
	records.append(record)
	link(person, record)
	return record


func link(person: Person, record: Record) -> void:
	record.person = person
	record.coming = false
	person.profile["staff_id"] = record.id


## A day of someone's pay, at their shift's rate.
func day_pay(record: Record) -> int:
	var shift := _shift(record.shift)
	return roundi(record.wage * (1.0 + WAGE_STEP * (record.level - 1)) * (shift.pay_scale if shift != null else 1.0))


## What a shift's staff cost before the shift's own rate.
func wages_on(shift: StringName) -> int:
	var sum := 0
	for record in records:
		if record.shift == shift:
			sum += record.wage
	return sum


## How their pay compares with the going rate, as morale points.
func pay_feeling(record: Record) -> float:
	var def := _role(record.role)
	if def == null or def.wage <= 0:
		return 0.0
	return (float(record.wage) / def.wage - 1.0) * 100.0 * PAY_MORALE


## Where their morale is heading: how they feel at work, and their pay.
func morale_target(record: Record) -> float:
	var mood := record.mood_sum / record.mood_hours if record.mood_hours > 0 else 60.0
	return clampf(mood + 10.0 + pay_feeling(record), 0.0, 100.0)


## Midnight: morale moves, the unhappy quit, and new applicants come.
func nightly() -> void:
	for record: Record in records.duplicate():
		var target := morale_target(record)
		record.morale = move_toward(record.morale, target, MORALE_STEP)
		record.mood_sum = 0.0
		record.mood_hours = 0
		record.low_days = record.low_days + 1 if record.morale < QUIT_MORALE else 0
		if record.low_days >= QUIT_DAYS:
			records.erase(record)
			quit.emit(record)
		elif _rng.randf() < maxf(0.0, (SICK_LINE - record.morale) * SICK_CHANCE):
			record.off_until = _day()
			off_sick.emit(record)
	refresh_applicants()
	changed.emit()


## Drops applicants who have waited long enough, and tops up each role and
## shift to at least APPLICANTS.x.
func refresh_applicants() -> void:
	var today := _day()
	applicants = applicants.filter(func(a: Record) -> bool: return a.until >= today)
	for def in roles:
		for shift in shifts:
			if def.by_card or not def.works(shift.id):
				continue
			var waiting := applicants.filter(func(a: Record) -> bool:
					return a.role == def.id and a.shift == shift.id).size()
			var want := _rng.randi_range(APPLICANTS.x, APPLICANTS.y)
			for i in want - waiting:
				var applicant := _make(def.id, shift.id)
				applicant.until = today + APPLICANT_DAYS - 1
				applicants.append(applicant)
	changed.emit()


## A new applicant for a role and shift, waiting `days` days.
func add_applicant(role: StringName, shift: StringName, days := APPLICANT_DAYS) -> Record:
	var applicant := _make(role, shift)
	applicant.until = _day() + days - 1
	applicants.append(applicant)
	changed.emit()
	return applicant


func applicants_for(role: StringName, shift: StringName) -> Array[Record]:
	return applicants.filter(func(a: Record) -> bool: return a.role == role and a.shift == shift)


## The cheapest applicant for a role and shift, or null.
func cheapest(role: StringName, shift: StringName) -> Record:
	var best: Record = null
	for applicant in applicants_for(role, shift):
		if best == null or applicant.wage < best.wage:
			best = applicant
	return best


## The roster as plain data for a save.
func capture() -> Dictionary:
	return {"next_id": next_id, "records": records.map(_data), "applicants": applicants.map(_data)}


func restore(data: Dictionary) -> void:
	next_id = data.get("next_id", next_id)
	records.clear()
	applicants.clear()
	for entry: Dictionary in data.get("records", []):
		records.append(_from(entry))
	for entry: Dictionary in data.get("applicants", []):
		applicants.append(_from(entry))
	changed.emit()


## Words about someone on staff, for the inspector, or "".
func summary(person: Person) -> String:
	var record := record_of(person)
	if record == null:
		return ""
	var feeling := "happy at work" if record.morale >= 70.0 else "content" if record.morale >= 40.0 \
			else "unhappy at work" if record.morale >= QUIT_MORALE else "thinking of quitting"
	return "Level %d%s, morale %d (%s), %s a day, hired day %d" % [record.level,
			" (%d%% faster)" % roundi((pace(person) - 1.0) * 100.0) if record.level > 1 else "",
			roundi(record.morale), feeling, Ledger.text(day_pay(record)), record.hired_day]


func _make(role: StringName, shift: StringName) -> Record:
	var record := Record.new()
	record.id = next_id
	next_id += 1
	record.name = people.random_name()
	record.role = role
	record.shift = shift
	record.traits = people.pick_traits(trait_pool if not trait_pool.is_empty() else people.traits)
	record.look_seed = _rng.randi() % 100000
	var def := _role(role)
	var rate := def.wage if def != null else 0
	record.wage = roundi(rate * _rng.randf_range(ASKING.x, ASKING.y) / 5.0) * 5
	return record


## Each hour, how everyone at work feels.
func _sample() -> void:
	for record in records:
		if record.person != null and not record.person.going_home:
			record.mood_sum += record.person.mood
			record.mood_hours += 1


func _data(record: Record) -> Dictionary:
	return {"id": record.id, "name": record.name, "role": record.role, "shift": record.shift,
			"traits": record.traits.map(func(t: TraitDef) -> StringName: return t.id), "wage": record.wage,
			"morale": record.morale, "low_days": record.low_days, "hired_day": record.hired_day,
			"look_seed": record.look_seed, "until": record.until, "mood_sum": record.mood_sum,
			"mood_hours": record.mood_hours, "level": record.level, "xp": record.xp,
			"off_until": record.off_until}


func _from(entry: Dictionary) -> Record:
	var record := Record.new()
	record.id = entry["id"]
	record.name = entry["name"]
	record.role = entry["role"]
	record.shift = entry["shift"]
	for id: StringName in entry.get("traits", []):
		for def in people.traits:
			if def.id == id:
				record.traits.append(def)
	record.wage = entry.get("wage", 0)
	record.morale = entry.get("morale", MORALE_START)
	record.low_days = entry.get("low_days", 0)
	record.hired_day = entry.get("hired_day", 0)
	record.look_seed = entry.get("look_seed", 0)
	record.until = entry.get("until", 0)
	record.mood_sum = entry.get("mood_sum", 0.0)
	record.mood_hours = entry.get("mood_hours", 0)
	record.level = entry.get("level", 1)
	record.xp = entry.get("xp", 0.0)
	record.off_until = entry.get("off_until", 0)
	next_id = maxi(next_id, record.id + 1)
	return record


func _role(id: StringName) -> StaffRoleDef:
	for def in roles:
		if def.id == id:
			return def
	return null


func _shift(id: StringName) -> ShiftDef:
	for def in shifts:
		if def.id == id:
			return def
	return null


func _day() -> int:
	return clock.day() if clock != null else 1
