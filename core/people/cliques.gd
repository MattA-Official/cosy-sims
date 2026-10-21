class_name Cliques
extends Node
## Friendly groups around a shared hobby, such as the Knitting Circle.
## Nobody draws them: each midnight, residents who share a hobby and are
## each friends with at least two others in the group become a clique, and
## members who have drifted from everyone in it leave. Members sit together,
## do their hobby together for club spirit, and act up together when their
## grievance (their average temper) runs high. Shared by any game with
## residents.

## The fewest and most in a clique.
const LEAST := 3
const MOST := 8
## Friends with this many others in the group to form one.
const FRIENDS_IN := 2
## Members leave once their bond with everyone in it is below this.
const KEEP_BOND := 20.0
## Grievance at which they act up together, and past which anything goes.
const GRIEVANCE_JOIN := 60.0
const GRIEVANCE_ANY := 80.0
## How far away members join in when one acts up, in tiles.
const JOIN_DISTANCE := 10.0
## Members look for seats this close to each other, in tiles, and like
## them this much more.
const SIT_NEAR := 3.0
const SIT_SCALE := 1.2
## Pin colours: small badges, not gang colours.
const COLOURS: Array[Color] = [Color(0.85, 0.55, 0.45), Color(0.5, 0.7, 0.85), Color(0.9, 0.8, 0.45),
		Color(0.6, 0.8, 0.55), Color(0.75, 0.6, 0.85), Color(0.9, 0.65, 0.75), Color(0.55, 0.8, 0.8)]

signal formed(clique: Clique)
signal ended(clique: Clique)

class Clique:
	var id := 0
	var name := ""
	var hobby: StringName
	## Person ids.
	var members: Array[int] = []
	var colour := Color.WHITE

var people: People
var relationships: Relationships
var hobbies: Hobbies
var cliques: Array[Clique] = []
## Groups who form cliques.
var groups: Array[StringName] = [&"prisoner"]
## Tags of seats members choose near each other, such as canteen tables.
var sit_tags: Array[StringName] = [&"table", &"bench", &"chair"]
var clock: GameClock:
	set(value):
		clock = value
		clock.day_changed.connect(func(_day: int) -> void: update())

var _next_id := 1


func attach() -> void:
	people.pulls.append(pulls)


func clique_of(person: Person) -> Clique:
	for clique in cliques:
		if clique.members.has(person.id):
			return clique
	return null


func members_of(clique: Clique) -> Array[Person]:
	var out: Array[Person] = []
	for person in people.people:
		if clique.members.has(person.id):
			out.append(person)
	return out


## Average member temper, 0 to 100.
func grievance(clique: Clique) -> float:
	var members := members_of(clique)
	if members.is_empty():
		return 0.0
	var sum := 0.0
	for member in members:
		sum += member.temper
	return sum / members.size()


## The midnight round: members leave or go, cliques end, new ones form.
func update() -> void:
	_keep()
	_form()


func _keep() -> void:
	var here: Dictionary[int, Person] = {}
	for person in people.people:
		here[person.id] = person
	for clique: Clique in cliques.duplicate():
		clique.members = clique.members.filter(func(id: int) -> bool: return here.has(id))
		for id: int in clique.members.duplicate():
			var person := here[id]
			var close := clique.members.any(func(other: int) -> bool:
				return other != id and relationships.bond(person, here[other]) >= KEEP_BOND)
			if not close:
				clique.members.erase(id)
		if clique.members.size() < LEAST:
			cliques.erase(clique)
			ended.emit(clique)


func _form() -> void:
	for def in hobbies.defs:
		var free: Array[Person] = []
		for person in people.people:
			if groups.has(person.group) and clique_of(person) == null and hobbies.hobbies_of(person).has(def):
				free.append(person)
		# Join an existing clique of the hobby when friends with two in it.
		for clique in cliques:
			if clique.hobby != def.id:
				continue
			var members := members_of(clique)
			for person: Person in free.duplicate():
				if clique.members.size() >= MOST:
					break
				if _friends_among(person, members) >= FRIENDS_IN:
					clique.members.append(person.id)
					members.append(person)
					free.erase(person)
		# New cliques from friendly groups of the rest.
		while true:
			var group := _friendly_group(free)
			if group.size() < LEAST:
				break
			for person in group:
				free.erase(person)
			_start(def, group)


## The largest group among these where each is friends with FRIENDS_IN
## others: grows from one person through their friends, then drops whoever
## has too few friends left in it.
func _friendly_group(pool: Array[Person]) -> Array[Person]:
	var best: Array[Person] = []
	var seen: Dictionary[Person, bool] = {}
	for start in pool:
		if seen.has(start):
			continue
		var group: Array[Person] = [start]
		var i := 0
		while i < group.size():
			for other in pool:
				if not group.has(other) and relationships.is_friend(group[i], other):
					group.append(other)
			i += 1
		for person in group:
			seen[person] = true
		var changed := true
		while changed:
			changed = false
			for person: Person in group.duplicate():
				if _friends_among(person, group) < FRIENDS_IN:
					group.erase(person)
					changed = true
		if group.size() > best.size():
			best = group
	if best.size() > MOST:
		best.sort_custom(func(a: Person, b: Person) -> bool: return _friends_among(a, best) > _friends_among(b, best))
		best = best.slice(0, MOST)
	return best


func _friends_among(person: Person, group: Array[Person]) -> int:
	var count := 0
	for other in group:
		if other != person and relationships.is_friend(person, other):
			count += 1
	return count


func _start(def: HobbyDef, group: Array[Person]) -> Clique:
	var clique := Clique.new()
	clique.id = _next_id
	_next_id += 1
	clique.hobby = def.id
	clique.name = def.club_name
	if cliques.any(func(c: Clique) -> bool: return c.name == clique.name):
		clique.name = def.club_name.replace("The ", "The Other ")
	clique.colour = COLOURS[(clique.id - 1) % COLOURS.size()]
	for person in group:
		clique.members.append(person.id)
	cliques.append(clique)
	formed.emit(clique)
	return clique


## Members doing their hobby together: one list per room with LEAST or
## more, as [clique, members].
func together() -> Array:
	var out: Array = []
	for clique in cliques:
		var rooms: Dictionary[String, Array] = {}
		for member in members_of(clique):
			var doing := hobbies.doing(member)
			var here := people.room_of(member)
			if doing == null or doing.id != clique.hobby or here.is_empty():
				continue
			rooms.get_or_add("%d:%d" % [here[0], (here[1] as Object).get_instance_id()], []).append(member)
		for list: Array in rooms.values():
			if list.size() >= LEAST:
				var members: Array[Person] = []
				members.assign(list)
				out.append([clique, members])
	return out


## Members sitting nearby, for People.pulls: places on the same level to
## choose seats near.
func pulls(person: Person, tag: StringName) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not sit_tags.has(tag):
		return out
	var clique := clique_of(person)
	if clique == null:
		return out
	for member in members_of(clique):
		if member != person and member.level == person.level and member.state == Person.State.USING:
			out.append(member.flat())
	return out


## Members close enough to join in when one acts up.
func joiners(person: Person) -> Array[Person]:
	var out: Array[Person] = []
	var clique := clique_of(person)
	if clique == null:
		return out
	for member in members_of(clique):
		if member != person and member.level == person.level \
				and member.flat().distance_to(person.flat()) <= JOIN_DISTANCE:
			out.append(member)
	return out


## "The Chess Club (with Bea, Gus)" for the inspector, or "".
func words(person: Person) -> String:
	var clique := clique_of(person)
	if clique == null:
		return ""
	var others: Array[String] = []
	for member in members_of(clique):
		if member != person:
			others.append(member.name.get_slice(" ", 0))
	return "%s (with %s)" % [clique.name, People._who(others)]


func capture() -> Array:
	var out: Array = []
	for clique in cliques:
		out.append({"id": clique.id, "name": clique.name, "hobby": String(clique.hobby),
				"members": clique.members.duplicate(), "colour": clique.colour.to_html()})
	return out


func restore(data: Array) -> void:
	cliques.clear()
	for entry: Dictionary in data:
		var clique := Clique.new()
		clique.id = int(entry["id"])
		clique.name = entry["name"]
		clique.hobby = StringName(entry["hobby"])
		for id in entry["members"]:
			clique.members.append(int(id))
		clique.colour = Color.html(entry["colour"])
		cliques.append(clique)
		_next_id = maxi(_next_id, clique.id + 1)
