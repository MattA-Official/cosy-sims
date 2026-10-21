class_name PrisonTray
extends Node
## The prison's in-tray cards, and what their answers do. Effects are
## dictionaries:
##   {"money": -40}                       paid or earned, on the "In-tray" line
##   {"moodlet": &"tray_guitar"}          for the card's prisoner
##   {"moodlet": &"tray_mural", "who": "prisoners"}   for every prisoner
##   {"morale": 10}                       for the card's member of staff
##   {"morale": 5, "who": "staff"}        for all staff
##   {"raise": true}                      the card's member of staff gets a raise
##   {"day_off": true}                    they stay home tomorrow
##   {"paperwork": 60}                    on the warden's desk
##   {"resign": &"raise"}                 answers a resignation (StaffRoster.resign_answer)

const PRISONER := &"prisoner"

var people: People
var ledger: Ledger
var roster: StaffRoster
var desk_work: DeskWork
var heads: Heads
var clock: GameClock
var _rng := RandomNumberGenerator.new()


## Moodlets the cards give.
static func moodlets() -> Array[MoodletDef]:
	var out: Array[MoodletDef] = []
	for entry: Array in [
			[&"tray_yes", "Request granted", 6.0, 72.0],
			[&"tray_no", "Request turned down", -3.0, 48.0],
			[&"tray_treat", "Something nice from the office", 3.0, 48.0],
			[&"tray_cold", "Cold showers", -2.0, 24.0]]:
		var def := MoodletDef.new()
		def.id = entry[0]
		def.display_name = entry[1]
		def.mood = entry[2]
		def.hours = entry[3]
		out.append(def)
	return out


static func cards() -> Array[TrayCardDef]:
	var no_mood := [{"moodlet": &"tray_no"}]
	var approve := [&"approve"]
	var decline := [&"decline"]
	var out: Array[TrayCardDef] = []
	out.append(TrayCardDef.make(&"guitar", &"prisoner_request", PRISONER, "A guitar",
			"{who} asks for a guitar in their cell. They promise to learn more than three chords.",
			[TrayCardDef.choice("Yes, a guitar (£40)", [{"money": -40}, {"moodlet": &"tray_yes"}], approve, "{who} got a guitar."),
			TrayCardDef.choice("No", no_mood, decline, "{who} didn't get a guitar.")], 1))
	out.append(TrayCardDef.make(&"mural", &"prisoner_request", PRISONER, "A mural",
			"{who} would like to paint a mural on the canteen wall. Something with seagulls.",
			[TrayCardDef.choice("Yes, buy paint (£60)", [{"money": -60}, {"moodlet": &"tray_treat", "who": "prisoners"}, {"moodlet": &"tray_yes"}],
				approve, "{who} painted the seagulls."),
			TrayCardDef.choice("No", no_mood, decline)], 1))
	out.append(TrayCardDef.make(&"blankets", &"prisoner_request", PRISONER, "Extra blankets",
			"{who} says the cells are chilly at night and asks for extra blankets all round.",
			[TrayCardDef.choice("Yes, blankets for all (£80)", [{"money": -80}, {"moodlet": &"tray_treat", "who": "prisoners"}], approve),
			TrayCardDef.choice("No", no_mood, decline)], 1))
	out.append(TrayCardDef.make(&"book_club", &"prisoner_request", PRISONER, "A book club",
			"{who} wants to start a book club. First up: a very long book about whales.",
			[TrayCardDef.choice("Yes, buy books (£30)", [{"money": -30}, {"moodlet": &"tray_yes"}], approve),
			TrayCardDef.choice("No", no_mood, decline)], 1))
	out.append(TrayCardDef.make(&"pot_plant", &"prisoner_request", PRISONER, "A pot plant",
			"{who} asks to keep a small pot plant in their cell. They've already named it Doris.",
			[TrayCardDef.choice("Yes (£10)", [{"money": -10}, {"moodlet": &"tray_yes"}], approve),
			TrayCardDef.choice("No", no_mood, decline)], 1))
	out.append(TrayCardDef.make(&"spicy", &"prisoner_request", PRISONER, "Spicier food",
			"{who} asks, on behalf of several people, whether the food could be a little less beige.",
			[TrayCardDef.choice("Order spices (£50)", [{"money": -50}, {"moodlet": &"tray_treat", "who": "prisoners"}], approve),
			TrayCardDef.choice("No", no_mood, decline)], 1))
	out.append(TrayCardDef.make(&"kettle", &"staff_request", &"staff", "A new kettle",
			"{who} asks for a new kettle for the staff. The old one has started to whistle in a minor key.",
			[TrayCardDef.choice("Buy a kettle (£30)", [{"money": -30}, {"morale": 5, "who": "staff"}], approve),
			TrayCardDef.choice("No", [{"morale": -5}], decline)], 1))
	out.append(TrayCardDef.make(&"wedding", &"staff_request", &"staff", "A day off",
			"{who} asks for tomorrow off to go to their sister's wedding.",
			[TrayCardDef.choice("Yes, have fun", [{"morale": 12}, {"day_off": true}], approve),
			TrayCardDef.choice("Sorry, we need you", [{"morale": -10}], decline)], 1))
	out.append(TrayCardDef.make(&"pay_review", &"staff_request", &"staff", "A pay review",
			"{who} asks for a pay review after all their hard work.",
			[TrayCardDef.choice("Give a raise (10%)", [{"raise": true}], approve),
			TrayCardDef.choice("Not now", [{"morale": -8}], decline)], 1))
	out.append(TrayCardDef.make(&"quiz", &"staff_request", &"staff", "A quiz night",
			"{who} suggests a staff quiz night, with prizes.",
			[TrayCardDef.choice("Yes, fund prizes (£50)", [{"money": -50}, {"morale": 5, "who": "staff"}], approve),
			TrayCardDef.choice("No", [{"morale": -3}], decline)], 1))
	out.append(TrayCardDef.make(&"pool_table", &"memo", &"", "A pool table",
			"The Ministry has a used pool table going spare. It's slightly wonky. £150 to you.",
			[TrayCardDef.choice("Buy it (£150)", [{"money": -150}, {"moodlet": &"tray_treat", "who": "prisoners"}], approve),
			TrayCardDef.choice("No thanks", [], decline)], 1))
	out.append(TrayCardDef.make(&"bakery", &"memo", &"", "Day-old bread",
			"The bakery in the village offers its day-old bread to the kitchen. They'll pay us to take it away, as it saves them a skip.",
			[TrayCardDef.choice("Accept (+£60)", [{"money": 60}, {"moodlet": &"tray_treat", "who": "prisoners"}], approve),
			TrayCardDef.choice("Decline", [], decline)], 1))
	out.append(TrayCardDef.make(&"headcount", &"memo", &"", "A headcount report",
			"The Ministry asks for a headcount report, with a small grant for filing it.",
			[TrayCardDef.choice("File it (+£100, an hour of paperwork)", [{"money": 100}, {"paperwork": 60}], approve),
			TrayCardDef.choice("Ignore it", [], decline)], 1))
	out.append(TrayCardDef.make(&"noisy_yard", &"complaint", &"", "Noisy yard",
			"A neighbour writes that the yard is rather loud in the evenings, and could we keep it down.",
			[TrayCardDef.choice("Send biscuits and an apology (£20)", [{"money": -20}], approve),
			TrayCardDef.choice("Ignore it", [], decline)], 1))
	out.append(TrayCardDef.make(&"cold_showers", &"complaint", PRISONER, "Cold showers",
			"{who} complains that the showers have gone cold again.",
			[TrayCardDef.choice("Fix the boiler (£120)", [{"money": -120}, {"moodlet": &"tray_treat", "who": "prisoners"}], approve),
			TrayCardDef.choice("Ignore it", [{"moodlet": &"tray_cold", "who": "prisoners"}], decline)], 1))
	out.append(TrayCardDef.make(&"visiting", &"complaint", &"", "Visiting hours",
			"A prisoner's family write asking if visiting hours could be a bit longer on Sundays.",
			[TrayCardDef.choice("Send a kind letter (£5)", [{"money": -5}], approve),
			TrayCardDef.choice("Ignore it", [], decline)], 1))
	return out


## The letter someone unhappy writes; posted by the roster, not the roll.
static func resignation() -> TrayCardDef:
	var def := TrayCardDef.make(&"resignation", &"resignation", &"staff", "A resignation letter",
			"{who} has written to say they're not happy here and would like to leave.",
			[TrayCardDef.choice("Accept it", [{"resign": &"accept"}], [&"decline"], "{who} left."),
			TrayCardDef.choice("Offer a raise (20%)", [{"resign": &"raise"}], [&"approve"], "{who} stayed for a raise."),
			TrayCardDef.choice("Offer %d days' leave" % StaffRoster.LEAVE_DAYS, [{"resign": &"leave"}], [], "{who} took some leave.")], 0)
	def.weight = 0.0
	def.deadline_days = 3
	return def


## The card for a staff suggestion (Suggestions), posted about whoever
## suggested it.
static func suggestion(idea: Dictionary) -> TrayCardDef:
	var def := TrayCardDef.make(StringName("suggest_%s" % idea["id"]), &"suggestion", &"staff", idea["title"],
			"{who} suggests: \"%s\"" % idea["words"],
			[TrayCardDef.choice("Good idea", [{"morale": 5}], [&"approve"], "{who}'s idea: %s." % String(idea["title"]).to_lower()),
			TrayCardDef.choice("Not now", [{"morale": -3}], [&"decline"], "{who}'s idea put aside.")], 0)
	def.weight = 0.0
	def.deadline_days = 3
	return def


## The annual review: warning that a head or the warden is unhappy enough to
## leave soon. Posted by main on StaffRoster.unhappy.
static func review() -> TrayCardDef:
	var def := TrayCardDef.make(&"annual_review", &"review", &"staff", "An annual review",
			"{who} is unhappy at work, and it came out at their annual review. They may well leave in a few days.",
			[TrayCardDef.choice("Give a raise (10%)", [{"raise": true}, {"morale": 10}], [&"approve"], "{who} got a raise at their review."),
			TrayCardDef.choice("Have a chat (+8 morale)", [{"morale": 8}], [], "{who} had a long chat at their review."),
			TrayCardDef.choice("Leave it", [], [&"decline"], "{who}'s review came to nothing.")], 2)
	def.weight = 0.0
	def.deadline_days = 2
	return def


## Words for a member of staff, such as "Dot the cook".
func staff_words(record: StaffRoster.Record) -> String:
	var role := roster._role(record.role)
	return "%s the %s" % [record.first_name(), role.display_name.to_lower() if role != null else "staff member"]


## Picks who a card is about. False when nobody fits.
func pick_subject(card: InTray.Card) -> bool:
	match card.def.subject:
		PRISONER:
			var prisoners := people.people.filter(func(p: Person) -> bool: return p.group == PRISONER)
			if prisoners.is_empty():
				return false
			var person: Person = prisoners[_rng.randi() % prisoners.size()]
			card.subject = person.id
			card.words = person.name.get_slice(" ", 0)
		&"staff":
			if roster.records.is_empty():
				return false
			var record: StaffRoster.Record = roster.records[_rng.randi() % roster.records.size()]
			card.subject = record.id
			card.words = staff_words(record)
	return true


func apply(card: InTray.Card, choice: TrayChoiceDef) -> void:
	for effect: Dictionary in choice.effects:
		if effect.has("money") and ledger != null:
			ledger.add(effect.money, "In-tray")
		if effect.has("moodlet"):
			if effect.get("who", "") == "prisoners":
				for person in people.people:
					if person.group == PRISONER:
						people.add_moodlet(person, effect.moodlet)
			else:
				var person := _person(card.subject)
				if person != null:
					people.add_moodlet(person, effect.moodlet)
		if effect.has("morale"):
			var records: Array = roster.records if effect.get("who", "") == "staff" else [_record(card.subject)]
			for record: StaffRoster.Record in records:
				if record != null:
					record.morale = clampf(record.morale + effect.morale, 0.0, 100.0)
		if effect.has("raise") and _record(card.subject) != null:
			roster.raise(_record(card.subject))
		if effect.has("day_off") and _record(card.subject) != null:
			_record(card.subject).off_until = clock.day() + 1 if clock != null else 2
		if effect.has("resign") and _record(card.subject) != null:
			roster.resign_answer(_record(card.subject), effect.resign)
		if effect.has("paperwork") and heads != null and heads.warden() != null:
			desk_work.add_paperwork(heads.warden().id, effect.paperwork)


## A card's words for afterwards, such as "Gus got a guitar."
static func why(card: InTray.Card, choice: TrayChoiceDef) -> String:
	if not choice.why.is_empty():
		return choice.why.replace("{who}", card.words)
	return "%s: %s." % [card.def.title, choice.label.get_slice(" (", 0).to_lower()]


func _person(id: int) -> Person:
	for person in people.people:
		if person.id == id and person.group == PRISONER:
			return person
	return null


func _record(id: int) -> StaffRoster.Record:
	for record in roster.records:
		if record.id == id:
			return record
	return null
