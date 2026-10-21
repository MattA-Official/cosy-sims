class_name Purse
extends RefCounted
## Someone's tokens: what they hold to spend and what is put aside for
## when they leave. Kept in Person.profile so it saves with them. Shared by
## any game whose residents earn and spend.

static func tokens(person: Person) -> int:
	return int(person.profile.get("tokens", 0))


static func savings(person: Person) -> int:
	return int(person.profile.get("savings", 0))


## Pays someone, putting `save_share` (0 to 1) of it aside. Fractions of a
## token carry over to the next pay.
static func pay(person: Person, amount: float, save_share := 0.0) -> void:
	var owed: float = person.profile.get("tokens_owed", 0.0) + amount
	var whole := floori(owed)
	person.profile["tokens_owed"] = owed - whole
	if whole <= 0:
		return
	var saved := roundi(whole * clampf(save_share, 0.0, 1.0))
	person.profile["savings"] = savings(person) + saved
	person.profile["tokens"] = tokens(person) + whole - saved


## Takes tokens to spend. False, taking nothing, if they haven't enough.
static func spend(person: Person, amount: int) -> bool:
	if tokens(person) < amount:
		return false
	person.profile["tokens"] = tokens(person) - amount
	return true


## "12 tokens, 30 saved" for the inspector, or "" with none.
static func words(person: Person) -> String:
	if not person.profile.has("tokens") and not person.profile.has("savings"):
		return ""
	return "%d token%s, %d saved" % [tokens(person), "" if tokens(person) == 1 else "s", savings(person)]
