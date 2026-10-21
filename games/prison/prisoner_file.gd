class_name PrisonerFile
extends RefCounted
## A prisoner's file: their sentence, reform, skills, courses passed and a
## life log. It lives in person.profile, so it saves with them; this only
## gives it names.
##
##   var file := PrisonerFile.of(person)
##   file.days_left(clock.day())  # 4

## Life-log lines kept.
const LOG_KEPT := 30

var profile: Dictionary

## Game days they were given, and have served.
var sentence_days: int:
	get: return profile.get("sentence_days", 0)
	set(value): profile["sentence_days"] = value
var served_days: int:
	get: return profile.get("served_days", 0)
	set(value): profile["served_days"] = value
## The day the sentence ends, and the first day a parole hearing may be.
var release_day: int:
	get: return profile.get("release_day", 0)
	set(value): profile["release_day"] = value
var parole_from_day: int:
	get: return profile.get("parole_from_day", 0)
	set(value): profile["parole_from_day"] = value
## Skill id to 0-100, such as &"cooking".
var skills: Dictionary:
	get:
		if not profile.has("skills"):
			profile["skills"] = {}
		return profile["skills"]
## Course ids passed.
var passed: Array:
	get:
		if not profile.has("passed"):
			profile["passed"] = []
		return profile["passed"]
## [day, words] lines, oldest first, such as "Passed Woodwork".
var log: Array:
	get:
		if not profile.has("log"):
			profile["log"] = []
		return profile["log"]
## Times they've come back after leaving.
var came_back: int:
	get: return profile.get("came_back", 0)
	set(value): profile["came_back"] = value
## Their time is up (or parole granted): they go home in the morning.
var due_out: bool:
	get: return profile.get("due_out", false)
	set(value): profile["due_out"] = value


static func of(person: Person) -> PrisonerFile:
	var file := PrisonerFile.new()
	file.profile = person.profile
	return file


func has_sentence() -> bool:
	return profile.has("sentence_days")


func days_left(today: int) -> int:
	return maxi(release_day - today, 0)


func add_log(day: int, words: String) -> void:
	log.append([day, words])
	if log.size() > LOG_KEPT:
		log.remove_at(0)


func skill(id: StringName) -> int:
	return skills.get(id, 0)


func raise_skill(id: StringName, amount: int) -> void:
	skills[id] = clampi(skill(id) + amount, 0, 100)


## Their best skill's id, or &"" if they have none yet.
func best_skill() -> StringName:
	var best: StringName = &""
	for id: StringName in skills:
		if best == &"" or skills[id] > skills[best]:
			best = id
	return best
