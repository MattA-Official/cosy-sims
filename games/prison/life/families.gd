class_name Families
## A prisoner's small named family: one to three relatives, each with a
## fondness from 0 to 100, kept in Person.profile["family"] as
## [{name, relation, fondness}]. The fond write and visit; letters home,
## calls and visits keep fondness up, and it fades a little each day.
## Children may bring a drawing on a family day, pinned up in the cell.

const MOST := 3
const FONDNESS := Vector2(35.0, 90.0)
## Fondness to write, and to visit.
const LETTER_FONDNESS := 30.0
const VISIT_FONDNESS := 50.0
## Fondness lost a day, and gained by a letter home, a call and a visit.
const FADE := 1.0
const WRITE_BACK := 5.0
const CALL := 2.0
const VISIT := 3.0
## How long a drawing stays up, and what it adds to the cell.
const DRAWING_DAYS := 7
const DRAWING_QUALITY := 1.0

const RELATIONS: Array[String] = ["mum", "dad", "partner", "son", "daughter", "gran", "grandad", "sister", "brother"]
const CHILDREN: Array[String] = ["son", "daughter"]
const SHE: Array[String] = ["mum", "daughter", "gran", "sister"]
const HE: Array[String] = ["dad", "son", "grandad", "brother"]
const HER_NAMES: Array[String] = ["Jean", "Maggie", "Pat", "Lily", "Rosie", "Ivy", "Sue", "Nell", "Poppy", "Ada",
		"June", "Kath", "Daisy", "Mabel", "Tess"]
const HIS_NAMES: Array[String] = ["Ron", "Len", "Stan", "Alf", "Jack", "Ted", "Sid", "Archie", "Fred", "Bert",
		"Ray", "Wilf", "Charlie", "Joe", "Ernie"]


## Gives someone a family, if they haven't one.
static func make(person: Person, rng: RandomNumberGenerator) -> void:
	if person.profile.has("family"):
		return
	var relations := RELATIONS.duplicate()
	var family: Array = []
	for i in rng.randi_range(1, MOST):
		var relation: String = relations.pop_at(rng.randi() % relations.size())
		var names := HER_NAMES if SHE.has(relation) else HIS_NAMES if HE.has(relation) \
				else (HER_NAMES if rng.randf() < 0.5 else HIS_NAMES)
		family.append({"name": names[rng.randi() % names.size()], "relation": relation,
				"fondness": snappedf(rng.randf_range(FONDNESS.x, FONDNESS.y), 1.0)})
	person.profile["family"] = family


static func of(person: Person) -> Array:
	return person.profile.get("family", [])


## The fondest relative with at least so much fondness, or {}.
static func fondest(person: Person, least := 0.0) -> Dictionary:
	var best: Dictionary = {}
	for relative: Dictionary in of(person):
		if float(relative.fondness) >= least and (best.is_empty() or float(relative.fondness) > float(best.fondness)):
			best = relative
	return best


## A random relative with at least so much fondness, or {}.
static func any(person: Person, least: float, rng: RandomNumberGenerator) -> Dictionary:
	var fond := of(person).filter(func(r: Dictionary) -> bool: return float(r.fondness) >= least)
	return fond[rng.randi() % fond.size()] if not fond.is_empty() else {}


static func child(person: Person) -> Dictionary:
	for relative: Dictionary in of(person):
		if CHILDREN.has(relative.relation):
			return relative
	return {}


static func warm(relative: Dictionary, amount: float) -> void:
	if not relative.is_empty():
		relative.fondness = clampf(float(relative.fondness) + amount, 0.0, 100.0)


## A day passes: fondness fades and old drawings come down.
static func new_day(person: Person, day: int) -> void:
	for relative: Dictionary in of(person):
		warm(relative, -FADE)
	var drawing: Dictionary = person.profile.get("drawing", {})
	if not drawing.is_empty() and day - int(drawing.get("day", day)) >= DRAWING_DAYS:
		person.profile.erase("drawing")


## "Mum" or "Gran", for a visitor's name tag.
static func title(relative: Dictionary) -> String:
	return String(relative.get("relation", "family")).capitalize()


## "Family: Mum Jean ♥♥♥♡♡ · son Archie ♥♥♡♡♡" for the inspector, or "".
static func words(person: Person) -> String:
	var parts: Array[String] = []
	for relative: Dictionary in of(person):
		var hearts := clampi(roundi(float(relative.fondness) / 20.0), 0, 5)
		parts.append("%s %s %s" % [title(relative), relative.name, "♥".repeat(hearts) + "♡".repeat(5 - hearts)])
	var out := "Family: %s" % " · ".join(parts) if not parts.is_empty() else ""
	var drawing: Dictionary = person.profile.get("drawing", {})
	if not drawing.is_empty():
		out += "\nA drawing from %s on the wall" % drawing.get("from", "home")
	return out
