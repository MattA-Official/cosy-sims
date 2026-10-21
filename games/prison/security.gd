class_name Security
extends Node
## Keeping an eye on the place. Guards see the room they're in, and CCTV
## cameras see a cone in front of them while a guard sits at a monitor;
## what was seen fades over half an hour (see Coverage). Prisoners don't
## act up where they've been seen lately. Every incident is counted for the
## day, weighted by how bad it was, and the day's Safety grade comes from
## the total; each one also goes up as an alert for the Security window.

## Tiles a guard can see, and a camera's range and cone.
const GUARD_SIGHT := 5.0
const CAMERA_RANGE := 8.0
const CAMERA_CONE := PI * 0.5
const MONITOR_MINUTES := 90.0
const CAMERA_TAG := &"camera"
const MONITOR_TAG := &"cctv"
const DESK_TAG := &"guard_desk"
## How much each kind of incident counts against Safety.
const WEIGHTS: Dictionary[StringName, float] = {
	&"walk_back": 0.2,
	&"contraband": 0.5,
	&"vandalism": 1.0,
	&"fight": 1.0,
	&"knocked_out": 3.0,
	&"escape": 10.0,
	&"escape_plan": 3.0,
	&"sit_in": 1.0,
	&"death": 20.0,
}
const NAMES: Dictionary[StringName, String] = {
	&"walk_back": "Walked back",
	&"contraband": "Contraband found",
	&"vandalism": "Vandalism",
	&"fight": "Fights",
	&"knocked_out": "Knocked out",
	&"escape": "Escape attempts",
	&"escape_plan": "Escape plans found",
	&"sit_in": "Sit-in hours",
	&"missing_tool": "Tools missing",
	&"metal_detector": "Metal detector beeps",
	&"death": "Deaths",
}
const ALERTS_KEPT := 40
## How serious each kind of incident is for the area it happened in: 1
## for a missing tool or found contraband, 2 for a fight or a tunnel, 3
## for an escape, a sit-in or a death.
const SEVERITY: Dictionary[StringName, int] = {
	&"contraband": 1, &"missing_tool": 1, &"vandalism": 1, &"metal_detector": 1,
	&"fight": 2, &"knocked_out": 2, &"escape_plan": 2,
	&"escape": 3, &"sit_in": 3, &"death": 3,
}
## Game hours an area stays on alert.
const AREA_HOURS := 24.0
## Out in the open, how near counts as the same area.
const OPEN_AREA := 10.0
## While an area is on alert: guards patrol it this much more, searches
## pick its cells this much more, and tempers there rise this much.
const ALERT_PATROL := 3.0
const ALERT_SEARCH := 3.0
const ALERT_TEMPER := 0.7

signal alerted(words: String, level: int, point: Vector2)
## An incident was counted.
signal counted(kind: StringName)

var people: People
var jobs: JobBoard
var building: Building
var guard_role: StringName = &"guard"
var prisoner_group: StringName = &"prisoner"
## Low-security prisoners sharing a room with high-security ones get this.
var mixing_moodlet: StringName = &"uneasy"
const MIX_LOW := &"low"
const MIX_HIGH := &"high"
const MIX_EVERY := 10
var coverage := Coverage.new()
## Incidents so far today and yesterday, by kind.
var today: Dictionary[StringName, int] = {}
var yesterday: Dictionary[StringName, int] = {}
## Newest first: [day, minute of the day, words, level, point].
var alerts: Array = []
## Areas on alert: each {level, point, severity, hours}, the area being
## the room at the point (or open ground near it).
var areas: Array[Dictionary] = []
var clock: GameClock:
	set(value):
		clock = value
		clock.minute_passed.connect(func(minute: int) -> void:
			tick()
			if minute % MIX_EVERY == 0:
				check_mixing())


func start() -> void:
	coverage.building = building
	clock.hour_changed.connect(func(_hour: int) -> void: _age_areas())
	people.moodlet_added.connect(func(person: Person, id: StringName) -> void:
		if id == &"walked_back":
			count(&"walk_back", person))


func tick() -> void:
	_man_monitors()
	coverage.update(watchers())


## Who and what is watching now, for Coverage.update.
func watchers() -> Array:
	var out: Array = []
	for person in people.people:
		if person.role == guard_role and not person.going_home and not person.lying:
			out.append([person.level, person.flat(), GUARD_SIGHT])
	if cameras_live():
		for key in building.objects_tagged([CAMERA_TAG]):
			var placed := building.object_at(key)
			out.append([key.x, placed.centre, CAMERA_RANGE, facing(placed), CAMERA_CONE])
	return out


## Low-security prisoners in a room with high-security ones feel uneasy,
## a reason to keep them apart.
func check_mixing() -> void:
	var high_rooms: Array[Room] = []
	for person in people.people:
		if person.group == prisoner_group and person.category == MIX_HIGH:
			var here := people.room_of(person)
			if not here.is_empty() and not high_rooms.has(here[1]):
				high_rooms.append(here[1])
	if high_rooms.is_empty():
		return
	for person in people.people:
		if person.group != prisoner_group or person.category != MIX_LOW:
			continue
		var here := people.room_of(person)
		if not here.is_empty() and high_rooms.has(here[1]):
			people.add_moodlet(person, mixing_moodlet)


## Which way a camera looks: its front, as models face.
static func facing(placed: BuildingMap.PlacedObject) -> Vector2:
	return Vector2(0, 1).rotated(placed.angle)


## Whether a guard is sat at a monitor, so the cameras are being watched:
## at a monitor of its own, or at a guard desk with a monitor on it.
func cameras_live() -> bool:
	for job in jobs.of_kind(&"monitor"):
		if job.worker != null and job.worker.state == Person.State.USING:
			return true
	for job in jobs.of_kind(&"post"):
		var stage := job.current()
		if job.worker != null and job.worker.state == Person.State.USING and stage != null \
				and _has_monitor(Vector2i(stage.level, stage.object)):
			return true
	return false


func _has_monitor(desk: Vector2i) -> bool:
	var map: BuildingMap = building.levels.get(desk.x)
	if map == null:
		return false
	for placed: BuildingMap.PlacedObject in map.objects.values():
		if placed.on == desk.y and placed.def.tags.has(MONITOR_TAG):
			return true
	return false


## A monitor on a guard desk is watched by whoever mans the desk.
func _on_desk(key: Vector2i) -> bool:
	var placed := building.object_at(key)
	if placed == null or placed.on == 0:
		return false
	var desk := building.object_at(Vector2i(key.x, placed.on))
	return desk != null and desk.def.tags.has(DESK_TAG)


## Whether somewhere was seen lately enough to put people off.
func watched(level: int, point: Vector2) -> bool:
	return coverage.seen_at(level, point) > 0.5


## Counts an incident, and raises an alert for it unless `quiet`.
func count(kind: StringName, person: Person = null, words := "", quiet := false) -> void:
	today[kind] = today.get(kind, 0) + 1
	counted.emit(kind)
	if kind == &"walk_back" or quiet:
		return
	var text: String = words if not words.is_empty() else NAMES.get(kind, String(kind))
	if person != null and not words.contains(person.name):
		text = "%s: %s" % [person.name, text]
	var level := person.level if person != null else 0
	var point := person.flat() if person != null else Vector2.ZERO
	_alert(text, level, point)
	if person != null and SEVERITY.has(kind):
		raise(level, point, SEVERITY[kind])


## Puts up an alert without counting anything, such as for a room, and
## puts the area on alert at `severity` (0 for not).
func alert_at(text: String, level: int, point: Vector2, severity := 0) -> void:
	_alert(text, level, point)
	if severity > 0:
		raise(level, point, severity)


## Puts the area at a point on alert, or keeps it there at the higher
## severity, for another AREA_HOURS.
func raise(level: int, point: Vector2, severity: int) -> void:
	for area in areas:
		if _same_area(area, level, point):
			area.severity = maxi(area.severity, severity)
			area.hours = AREA_HOURS
			return
	areas.append({"level": level, "point": point, "severity": severity, "hours": AREA_HOURS})


## How serious the alert on the area at a point is: 0 for none, up to 3.
func alert_level(level: int, point: Vector2) -> int:
	var worst := 0
	for area in areas:
		if area.severity > worst and _same_area(area, level, point):
			worst = area.severity
	return worst


## The areas on alert in words, worst first, for the Security window.
func area_words() -> Array[String]:
	var sorted := areas.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.severity > b.severity)
	var out: Array[String] = []
	for area: Dictionary in sorted:
		out.append("%s: %s, %d h left" % [_area_name(area), ["", "watchful", "on alert", "alarm"][area.severity],
				ceili(area.hours)])
	return out


func _same_area(area: Dictionary, level: int, point: Vector2) -> bool:
	if area.level != level:
		return false
	var room := _room_at(level, area.point)
	if room != null:
		return _room_at(level, point) == room
	return _room_at(level, point) == null and (area.point as Vector2).distance_to(point) <= OPEN_AREA


func _room_at(level: int, point: Vector2) -> Room:
	var map := building.levels.get(level) as BuildingMap
	return map.room_at_point(point) if map != null else null


func _area_name(area: Dictionary) -> String:
	var room := _room_at(area.level, area.point)
	if room == null:
		return "Outside"
	var type := people.room_type(room.type) if people != null else null
	return type.display_name if type != null else "A room"


func _age_areas() -> void:
	for area in areas.duplicate():
		area.hours -= 1.0
		if area.hours <= 0.0:
			areas.erase(area)


func _alert(text: String, level: int, point: Vector2) -> void:
	alerts.push_front([clock.day() if clock != null else 0, clock.minute_of_day() if clock != null else 0,
			text, level, point])
	if alerts.size() > ALERTS_KEPT:
		alerts.resize(ALERTS_KEPT)
	alerted.emit(text, level, point)


## Weighted incidents in a tally.
static func points(tally: Dictionary) -> float:
	var total := 0.0
	for kind: StringName in tally:
		total += WEIGHTS.get(kind, 0.0) * tally[kind]
	return total


## Safety stars from a day's incidents: points per 10 prisoners.
static func safety_stars(tally: Dictionary, prisoners: int) -> int:
	var per_ten := points(tally) * 10.0 / maxi(prisoners, 1)
	var bands: Array[float] = [2.0, 1.0, 0.5, 0.2]
	var stars := 1
	for band in bands:
		if per_ten <= band:
			stars += 1
	return stars


## Midnight: today becomes yesterday.
func end_day() -> void:
	yesterday = today
	today = {}


## Keeps a guard at each CCTV monitor while there are cameras to watch.
func _man_monitors() -> void:
	var monitors := building.objects_tagged([MONITOR_TAG]).filter(func(key: Vector2i) -> bool:
		return not _on_desk(key))
	var any_cameras := not building.objects_tagged([CAMERA_TAG]).is_empty()
	var covered: Array[Vector2i] = []
	for job in jobs.of_kind(&"monitor"):
		var stage := job.stages[0]
		var key := Vector2i(stage.level, stage.object)
		if not monitors.has(key) or not any_cameras:
			jobs.cancel(job)
		else:
			covered.append(key)
	if not any_cameras:
		return
	for key in monitors:
		if covered.has(key):
			continue
		var job := Job.new()
		job.kind = &"monitor"
		job.title = "Watch the cameras"
		job.priority = 3
		var sit := Job.at(Job.Do.WORK, key.x, key.y)
		sit.minutes = MONITOR_MINUTES
		sit.doing = "Watching the cameras"
		job.stages = [sit]
		jobs.post(job)
