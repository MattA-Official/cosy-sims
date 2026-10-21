class_name Heads
extends Node
## Department heads. The warden works a hire card for a department at their
## desk; when it's done, APPLICANTS people apply and wait APPLY_DAYS days
## for an answer. The head taken on works days at a claimed office desk,
## and their department's bonus counts while they're on the payroll,
## halved while their desk is overloaded. No head is needed: a small prison
## runs on the warden alone.
##
## It also lands the morning's paperwork on the warden's and the heads'
## desks (see DeskWork).

## A hire card finished and its applicants are waiting.
signal applicants_ready(department: DepartmentDef)
signal hired(department: DepartmentDef, record: StaffRoster.Record)

const APPLICANTS := 2
const APPLY_DAYS := 3
## Days of pay as notice for letting a head go.
const NOTICE_DAYS := 3
const SHIFT := &"day"

var departments: Array[DepartmentDef] = []
var roster: StaffRoster
var desk_work: DeskWork
var modifiers: Modifiers
var building: Building
var warden_role: StringName = &"warden"
## () -> int: prisoners in the prison, for the paperwork.
var prisoners: Callable
## (amount) -> void: pays a head's notice. Optional.
var pay: Callable
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == DeskWork.PAPER_HOUR:
				morning())


func start() -> void:
	roster.changed.connect(refresh_bonuses)
	desk_work.changed.connect(refresh_bonuses)
	desk_work.finished.connect(_on_finished)
	refresh_bonuses()


func warden() -> StaffRoster.Record:
	for record in roster.records:
		if record.role == warden_role:
			return record
	return null


func head(department: DepartmentDef) -> StaffRoster.Record:
	for record in roster.records:
		if record.role == department.head_role.id:
			return record
	return null


func head_ids() -> Array[int]:
	var out: Array[int] = []
	for department in departments:
		var record := head(department)
		if record != null:
			out.append(record.id)
	return out


func department_of(record: StaffRoster.Record) -> DepartmentDef:
	for department in departments:
		if department.head_role.id == record.role:
			return department
	return null


## Whether the department's hire card has turned up: any of its rooms built.
func available(department: DepartmentDef) -> bool:
	if department.needs_rooms.is_empty() or building == null:
		return true
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			if department.needs_rooms.has(room.type):
				return true
	return false


## The hire card on the warden's desk, or null.
func hire_card() -> DeskWork.Item:
	var record := warden()
	if record == null:
		return null
	var cards := desk_work.items(record.id, &"research")
	return cards[0] if not cards.is_empty() else null


func hiring() -> DepartmentDef:
	var card := hire_card()
	return find(StringName(card.ref)) if card != null else null


func find(id: StringName) -> DepartmentDef:
	for department in departments:
		if department.id == id:
			return department
	return null


func applicants(department: DepartmentDef) -> Array[StaffRoster.Record]:
	return roster.applicants_for(department.head_role.id, SHIFT)


## Why a hire card can't start now, or "".
func why_not(department: DepartmentDef) -> String:
	if warden() == null:
		return "Take on a warden first."
	if head(department) != null:
		return "%s is already %s." % [head(department).name, department.head_role.display_name]
	if not applicants(department).is_empty():
		return "Applicants are waiting."
	if not available(department):
		var rooms := " or ".join(department.needs_rooms.map(func(t: StringName) -> String:
				return String(t).replace("_", " ")))
		return "Build %s %s first." % ["an" if "aeiou".contains(rooms.left(1)) else "a", rooms]
	if hiring() != null:
		return "The warden is already on the %s hire card." % hiring().display_name.to_lower()
	return ""


## Puts a department's hire card on the warden's desk. Returns whether it
## went on.
func start_hire(department: DepartmentDef) -> bool:
	if not why_not(department).is_empty():
		return false
	desk_work.add(warden().id, &"research", "Hire card: %s" % department.head_role.display_name,
			department.hire_minutes / Modifiers.scale(modifiers, &"hire_speed"), String(department.id))
	return true


## Takes the hire card off the warden's desk.
func cancel_hire() -> void:
	var card := hire_card()
	if card != null:
		(desk_work.piles[warden().id] as Array).erase(card)
		desk_work.changed.emit()


## Takes on one of a department's applicants; the others go home.
func hire(applicant: StaffRoster.Record) -> StaffRoster.Record:
	var department := department_of(applicant)
	if department == null or head(department) != null:
		return null
	for other in applicants(department):
		if other != applicant:
			roster.applicants.erase(other)
	var record := roster.hire(applicant)
	if record != null:
		hired.emit(department, record)
	return record


## Lets a head go, with NOTICE_DAYS days' pay.
func let_go(record: StaffRoster.Record) -> void:
	if pay.is_valid():
		pay.call(roster.day_pay(record) * (NOTICE_DAYS - 1))
	roster.dismiss(record)
	desk_work.forget(record.id)


## The morning's paperwork, then the bonuses again for anyone overloaded.
func morning() -> void:
	var record := warden()
	desk_work.morning(prisoners.call() if prisoners.is_valid() else 0, record.id if record != null else 0, head_ids())


## Each department's bonus, by whether it has a head and how their desk is,
## and the bonus of each member of staff's style, such as the warden's.
func refresh_bonuses() -> void:
	if modifiers == null:
		return
	for id: StringName in modifiers.sources.keys():
		if String(id).begins_with("style_") or String(id).begins_with("perk_"):
			modifiers.clear_source(id)
	for record in roster.records:
		var style := roster.style_of(record)
		if not style.is_empty():
			modifiers.set_source(StringName("style_%d" % record.id), style["bonus"])
		var role := roster._role(record.role)
		if roster.has_perk(record) and not role.perk_bonus.is_empty():
			modifiers.set_source(StringName("perk_%d" % record.id), role.perk_bonus)
	for department in departments:
		var record := head(department)
		if record == null:
			modifiers.clear_source(department.id)
			continue
		var share := 0.5 if desk_work.is_overloaded(record.id) else 1.0
		var amounts := {}
		for key: StringName in department.bonus:
			amounts[key] = department.bonus[key] * share
		modifiers.set_source(department.id, amounts)


func _on_finished(_owner: int, item: DeskWork.Item) -> void:
	if item.kind != &"research":
		return
	var department := find(StringName(item.ref))
	if department == null:
		return
	for i in APPLICANTS:
		roster.add_applicant(department.head_role.id, SHIFT, APPLY_DAYS)
	applicants_ready.emit(department)
