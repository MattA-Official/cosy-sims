class_name Licences
extends RefCounted
## Licences people hold, such as an airside driving permit or a screener's
## ticket: passed on a course (CourseDef.licence) and asked for by jobs
## (Job.licence) and roles (StaffRoleDef.licence). Kept in the person's
## profile, so they are saved with them.

const KEY := "licences"


## Does someone hold a licence? Everyone holds the empty one.
static func has(person: Person, id: StringName) -> bool:
	return id.is_empty() or (person.profile.get(KEY, []) as Array).has(id)


## Gives someone a licence. Returns whether they hadn't one.
static func grant(person: Person, id: StringName) -> bool:
	if id.is_empty() or has(person, id):
		return false
	var held: Array = person.profile.get_or_add(KEY, [])
	held.append(id)
	return true


## Takes a licence away, as when it lapses or is suspended.
static func revoke(person: Person, id: StringName) -> bool:
	var held: Array = person.profile.get(KEY, [])
	if not held.has(id):
		return false
	held.erase(id)
	return true


## Every licence someone holds.
static func held(person: Person) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(person.profile.get(KEY, []))
	return out


## What passing a course gives: its licence, if it has one. Returns
## whether that was new.
static func pass_course(person: Person, course: CourseDef) -> bool:
	return course != null and grant(person, course.licence)


## Can someone work a role, as far as licences go?
static func may_work(person: Person, role: StaffRoleDef) -> bool:
	return role == null or has(person, role.licence)
