class_name MissingFiles
extends Node
## Some arrivals come without their paperwork (MISSING_CHANCE, unless red
## tape is Off). Their file says "Awaiting paperwork" and they can't go up
## for parole until FILE_MINUTES of desk work fills it in: a clerk's job
## if there is one, otherwise the warden's. Without a filing cabinet
## anywhere, it takes twice as long.

const MISSING_CHANCE := 0.1
const FILE_MINUTES := 60.0
const KIND := &"file"
const CABINETS: Array[StringName] = [&"filing_cabinet"]

var desk_work: DeskWork
var heads: Heads
var people: People
## Optional: for looking for a filing cabinet.
var building: Building
## () -> bool: a clerk is on the staff.
var has_clerk: Callable
var intake: Intake:
	set(value):
		intake = value
		intake.arrived.connect(func(arrivals: Array[Person]) -> void:
			for person in arrivals:
				if _rng.randf() < MISSING_CHANCE:
					lose(person))

var _rng := RandomNumberGenerator.new()


func start() -> void:
	desk_work.finished.connect(func(_owner: int, item: DeskWork.Item) -> void:
		if item.kind == KIND:
			_found(int(item.ref)))


static func is_missing(person: Person) -> bool:
	return person.profile.get("file_missing", false)


## Someone's file goes missing, and desk work goes on a pile to sort it.
## Returns whether it did (not with red tape Off, nor without a warden or
## clerk to sort it).
func lose(person: Person) -> bool:
	if desk_work.red_tape == DeskWork.RedTape.OFF:
		return false
	var owner := DeskWork.SHARED if has_clerk.is_valid() and has_clerk.call() else \
			(heads.warden().id if heads.warden() != null else 0)
	if owner == 0:
		return false
	person.profile["file_missing"] = true
	desk_work.add(owner, KIND, "File for %s" % person.name, file_minutes(), person.id)
	return true


func _found(id: int) -> void:
	for person in people.people:
		if person.id == id:
			person.profile.erase("file_missing")
			return


## Desk minutes to sort a missing file: double without a filing cabinet.
func file_minutes() -> float:
	var cabinet := building == null or not building.objects_tagged(CABINETS).is_empty()
	return FILE_MINUTES if cabinet else FILE_MINUTES * 2.0
