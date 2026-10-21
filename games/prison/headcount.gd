class_name Headcount
extends RefCounted
## The headcount guide: how many of each kind of staff a prison this size
## wants on each shift, and the shifts nobody covers, for the Staff window.
## Rough ratios, not rules: one cook per COOK_RATIO prisoners, a guard per
## GUARD_RATIO awake prisoners (half that at night, when they're locked
## up), a cleaner per CLEANER_RATIO, and a handyman and a nurse once
## there's something for them to do.

const COOK_RATIO := 15
const GUARD_RATIO := 8
const CLEANER_RATIO := 20

var shifts: Shifts
var building: Building
var people: People
var prisoner_group: StringName = &"prisoner"


## How many of a role a shift should have, by the ratios.
func suggested(role: StringName, shift: StringName) -> int:
	var prisoners := _prisoners()
	if prisoners == 0:
		return 0
	var day := shift == &"day"
	match role:
		&"guard":
			return ceili(float(prisoners) / GUARD_RATIO) if day else ceili(float(prisoners) / (GUARD_RATIO * 2))
		&"cook":
			return ceili(float(prisoners) / COOK_RATIO) if day and _has(Kitchen.COOKERS) else 0
		&"cleaner":
			return ceili(float(prisoners) / CLEANER_RATIO) if day else 0
		&"handyman":
			return 1 if day and _has_breakables() else 0
		&"nurse":
			return 1 if day and _has_room(&"infirmary") else 0
	return 0


## Lines of advice: the shifts short of the guide, and shifts nobody covers.
func advice() -> Array[String]:
	var out: Array[String] = []
	var prisoners := _prisoners()
	for role: StringName in [&"guard", &"cook", &"cleaner", &"handyman", &"nurse"]:
		for shift: StringName in [&"day", &"night"]:
			var want := suggested(role, shift)
			var have := shifts.wanted_for(role, shift)
			if have >= want:
				continue
			var name := String(role) + ("s" if want != 1 else "")
			if have == 0 and role == &"guard" and shift == &"night":
				out.append("Nobody guards the night shift: %d prisoners go unwatched after dark." % prisoners)
			elif have == 0 and role == &"handyman":
				out.append("No handyman: nothing that breaks gets mended.")
			else:
				out.append("%s: the guide suggests %d on %s shift for %d prisoners (you have %d)." % [
						name.capitalize(), want, String(shift), prisoners, have])
	return out


func _prisoners() -> int:
	return people.people.filter(func(p: Person) -> bool: return p.group == prisoner_group and not p.going_home).size()


func _has(tags: Array[StringName]) -> bool:
	return not building.objects_tagged(tags).is_empty()


func _has_room(type: StringName) -> bool:
	for n: int in building.levels:
		for room: Room in (building.levels[n] as BuildingMap).rooms():
			if room.type == type:
				return true
	return false


func _has_breakables() -> bool:
	for n: int in building.levels:
		for placed: BuildingMap.PlacedObject in (building.levels[n] as BuildingMap).objects.values():
			if placed.def.uses_before_breaking > 0:
				return true
	return false
