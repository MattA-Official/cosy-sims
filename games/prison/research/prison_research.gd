class_name PrisonResearch
## The prison's research board, read from cards.json (the same file the
## interactive board on the design doc uses) and effects.json, with the
## six know-how kinds and what earns them. Built once and shared.

const CARDS := "res://games/prison/research/cards.json"
const EFFECTS := "res://games/prison/research/effects.json"

## Know-how and desk minutes by tier, for cards that don't say.
const TIER_KNOWHOW: Array[int] = [0, 15, 30, 50, 80, 120, 180]
const TIER_MINUTES: Array[float] = [0.0, 480.0, 900.0, 1440.0, 2160.0, 2880.0, 3600.0]
const HIRE_KNOWHOW := 20
const HIRE_MINUTES := 480.0

## cards.json branch -> department id.
const BRANCHES := {"office": &"office", "sec": &"security", "well": &"wellbeing", "med": &"medical",
		"edu": &"education", "ind": &"industry", "adm": &"admin"}

## The "up" words in cards.json -> [kind, id, count, value, fallback]. An
## id of "a|b" counts either event.
const REVEALS := {
	"4-star grade": [RevealDef.Kind.GRADE, &"", 4, null, true],
	"Maximum Security expansion": [RevealDef.Kind.ADDON, &"maximum_security", 1, null, false],
	"Prison Farm add-on": [RevealDef.Kind.ADDON, &"prison_farm", 1, null, false],
	"Character scale leans strict": [RevealDef.Kind.LEAN, &"", 1, null, false],
	"Character scale leans caring": [RevealDef.Kind.LEAN, &"", -1, null, false],
	"First year ends": [RevealDef.Kind.FIRST, &"year_end", 1, null, true],
	"Ministry memo": [RevealDef.Kind.EVENT, &"ministry_memo", 1, null, true],
	"Protestors at the gate": [RevealDef.Kind.EVENT, &"protestors", 1, null, true],
	"Staff needs setting on": [RevealDef.Kind.SETTING, &"staff_needs", 1, true, false],
	"Red tape setting on": [RevealDef.Kind.SETTING, &"red_tape", 1, true, false],
	"5 course passes": [RevealDef.Kind.COUNT, &"course_passed", 5, null, true],
	# No utilities setting yet: word of mouth turns these up.
	"Utilities set to Self-sufficient": [RevealDef.Kind.SETTING, &"utilities", 1, &"self_sufficient", true],
	"Utilities set to Bought in": [RevealDef.Kind.SETTING, &"utilities", 1, &"bought_in", true],
	"A kitchen, laundry or workshop is built": [RevealDef.Kind.BUILT, &"kitchen|laundry|workshop", 1, null, true],
	"An infirmary is built (M7)": [RevealDef.Kind.BUILT, &"infirmary", 1, null, true],
	"A classroom is built (M8)": [RevealDef.Kind.BUILT, &"classroom", 1, null, true],
	"A visits room is built": [RevealDef.Kind.BUILT, &"visiting", 1, null, true],
	"A kitchen is built": [RevealDef.Kind.BUILT, &"kitchen", 1, null, true],
	"A head reaches level 3": [RevealDef.Kind.HEAD_LEVEL, &"", 3, null, true],
	"First riot or big repair bill": [RevealDef.Kind.FIRST, &"riot|big_repair_bill", 1, null, true],
	"First escape": [RevealDef.Kind.FIRST, &"escape", 1, null, true],
	"10 night shifts worked": [RevealDef.Kind.COUNT, &"night_shift", 10, null, true],
	"First delivery smuggling found": [RevealDef.Kind.FIRST, &"delivery_smuggling_found", 1, null, true],
	"First item passed at a visit": [RevealDef.Kind.FIRST, &"visit_smuggled", 1, null, true],
	"5 drug finds": [RevealDef.Kind.COUNT, &"drug_found", 5, null, true],
	"10 drug finds": [RevealDef.Kind.COUNT, &"drug_found", 10, null, true],
	"First fight with 5 or more people": [RevealDef.Kind.FIRST, &"big_fight", 1, null, true],
	"Perimeter fence closed": [RevealDef.Kind.FIRST, &"perimeter_closed", 1, null, true],
	"10 contraband finds": [RevealDef.Kind.COUNT, &"contraband_found", 10, null, true],
	"First riot": [RevealDef.Kind.FIRST, &"riot", 1, null, true],
	"A stray turns up": [RevealDef.Kind.EVENT, &"stray", 1, null, true],
	"10 fights": [RevealDef.Kind.COUNT, &"fight", 10, null, true],
	"First winter (M12 seasons)": [RevealDef.Kind.EVENT, &"winter", 1, null, false],
	"Celebrity chef event": [RevealDef.Kind.EVENT, &"celebrity_chef", 1, null, true],
	"20 visits": [RevealDef.Kind.COUNT, &"visit", 20, null, true],
	"First cold outbreak (M11)": [RevealDef.Kind.FIRST, &"cold_outbreak", 1, null, true],
	"Flu week event": [RevealDef.Kind.EVENT, &"flu_week", 1, null, true],
	"First serious injury": [RevealDef.Kind.FIRST, &"serious_injury", 1, null, true],
	"5 prisoners share a language": [RevealDef.Kind.EVENT, &"shared_language", 1, null, true],
	"A prisoner with a high skill": [RevealDef.Kind.PRISONER, &"high_skill", 1, null, true],
	"10 reformed releases": [RevealDef.Kind.COUNT, &"reformed_release", 10, null, true],
	"5 parole passes": [RevealDef.Kind.COUNT, &"parole_passed", 5, null, true],
	"First improvised weapon found": [RevealDef.Kind.FIRST, &"weapon_found", 1, null, true],
	"First land plot bought": [RevealDef.Kind.FIRST, &"land_bought", 1, null, true],
	"A location without a road": [RevealDef.Kind.SETTING, &"no_road", 1, true, false],
	"First inspection": [RevealDef.Kind.FIRST, &"inspection", 1, null, true],
	"A late delivery": [RevealDef.Kind.FIRST, &"late_delivery", 1, null, true],
	"First bad news story (M12)": [RevealDef.Kind.FIRST, &"bad_news", 1, null, false],
}

## [kind id, name, letter, colour].
const KINDS := [
	[&"security", "Security", "S", Color(0.24, 0.42, 0.62)],
	[&"care", "Care", "C", Color(0.69, 0.31, 0.42)],
	[&"health", "Health", "H", Color(0.14, 0.52, 0.48)],
	[&"learning", "Learning", "L", Color(0.61, 0.48, 0.09)],
	[&"craft", "Craft", "R", Color(0.53, 0.35, 0.23)],
	[&"admin", "Admin", "A", Color(0.42, 0.34, 0.64)],
]

## [event, kind, amount, words].
const SOURCES := [
	[&"patrol_hour", &"security", 0.5, "Patrols"],
	[&"search_done", &"security", 1.0, "Searches"],
	[&"contraband_found", &"security", 4.0, "Contraband found"],
	[&"night_shift", &"security", 1.0, "Night shifts"],
	[&"meal_good", &"care", 0.1, "Good meals"],
	[&"meal_lovely", &"care", 0.3, "Hearty meals"],
	[&"visit", &"care", 2.0, "Visits"],
	[&"calm_day", &"care", 10.0, "Calm day"],
	[&"treatment", &"health", 2.0, "Treatments"],
	[&"checkup", &"health", 1.0, "Check-ups"],
	[&"course_session", &"learning", 2.0, "Lessons"],
	[&"course_passed", &"learning", 5.0, "Exams passed"],
	[&"workshop_good", &"craft", 0.5, "Workshop goods"],
	[&"meal_batch", &"craft", 0.5, "Meals cooked"],
	[&"laundry_load", &"craft", 0.3, "Laundry"],
	[&"repair_done", &"craft", 1.0, "Repairs"],
	[&"desk_hour", &"admin", 1.0, "Paperwork"],
	[&"tray_card", &"admin", 1.0, "In-tray"],
	[&"tray_card_warden", &"admin", 1.0, "In-tray"],
	[&"grant_goal", &"admin", 5.0, "Grant goals"],
]

## Flags cards switch on for systems still to come, and where they'll be
## read. Every other flag, and every modifier key, must be read by a
## system now (a test checks).
const FUTURE_FLAGS := {
	&"petitions": "M11 prisoner life", &"hobby_clubs": "M11 hobbies", &"prison_cat": "M11 pets",
	&"prison_shop": "M11 shop", &"phone_credit": "M11 privileges", &"earned_privileges": "M11 privileges",
	&"hygiene_drive": "M11 colds", &"vaccinations": "M11 colds", &"isolation_ward": "M11 colds",
	&"town_meetings": "M12 reputation", &"open_day": "M12 reputation", &"public_relations": "M12 reputation",
	&"open_books": "M12 reputation", &"lobbying": "M12 Ministry", &"long_term_plan": "M12 Ministry",
	&"seasonal_days": "M12 seasons", &"inspection_prep": "M12 inspections", &"health_inspection_ready": "M12 inspections",
	&"escape_review": "Escape Mode", &"day_release": "Open Prison add-on", &"prison_farm": "Prison Farm add-on",
	&"gang_intelligence": "Maximum Security add-on", &"armoury": "Maximum Security add-on",
	&"marksmen": "Maximum Security add-on", &"mediation": "Maximum Security add-on",
	&"max_security_wing": "Maximum Security add-on",
	&"patrol_planner": "patrol planner", &"sniffer_dogs": "dog handler role", &"cctv_room": "camera cover",
	&"lockdown_button": "lockdown button", &"remote_doors": "door control desk", &"watchtowers": "watchtowers",
	&"tactical_team": "response squad", &"ambulance_bay": "ambulances", &"computer_room": "flexible objects",
	&"furniture_workshop": "flexible objects", &"road_works": "roads", &"generators": "utilities",
	&"solar_and_water": "utilities", &"jetty_and_helipad": "location packs", &"bookkeeping": "the daily report",
	&"intake_desk": "intake choices", &"logistics": "deliveries",
}
## Modifier keys read with the group or role in front, and the pattern
## the reading code uses.
const GROUP_KEYS := {&"guard_walk_speed": "%s_walk_speed", &"staff_need_rate": "%s_need_rate",
		&"prisoner_mood": "%s_mood", &"knowhow_learning": "knowhow_%s"}

## Know-how kind -> the department whose head brings it to a joint card.
const KIND_DEPARTMENTS := {&"security": &"security", &"care": &"wellbeing", &"health": &"medical",
		&"learning": &"education", &"craft": &"industry", &"admin": &"admin"}

## Refinements: [department, main kind, name, gives, modifier, amount each].
const REFINEMENTS := [
	[&"security", &"security", "Sharper guards", "Guards 2% faster", &"guard_walk_speed", 0.02],
	[&"wellbeing", &"care", "Thriftier menus", "Meals 2% cheaper", &"supply_price", -0.02],
	[&"medical", &"health", "Quicker treatment", "Treatment 2% faster", &"treat_speed", 0.02],
	[&"education", &"learning", "Better teaching", "Course passes 2% higher", &"course_pass", 0.02],
	[&"industry", &"craft", "Tighter workshops", "Output 2% higher", &"job_output", 0.02],
	[&"admin", &"admin", "Tidier books", "Running costs 1% lower", &"running_costs", -0.01],
]

static var _board: ResearchBoardDef


static func board() -> ResearchBoardDef:
	if _board == null:
		_board = make_board()
	return _board


static func make_board() -> ResearchBoardDef:
	var out := ResearchBoardDef.new()
	for row: Array in KINDS:
		var def := KnowhowDef.new()
		def.id = row[0]
		def.display_name = row[1]
		def.letter = row[2]
		def.colour = row[3]
		out.knowhow.append(def)
	for row: Array in SOURCES:
		var source := KnowhowSourceDef.new()
		source.event = row[0]
		source.kind = row[1]
		source.amount = row[2]
		source.text = row[3]
		out.sources.append(source)
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EFFECTS))
	for data: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(CARDS)):
		var card := _card(data, out)
		for effect: Dictionary in effects.get(String(card.id), []):
			card.effects.append(effect)
		out.cards.append(card)
		if String(card.id).begins_with("hire-"):
			out.hire_cards[_department_of_hire(card)] = card.id
	out.kind_departments.assign(KIND_DEPARTMENTS)
	for row: Array in REFINEMENTS:
		var card := ResearchCardDef.new()
		card.id = StringName("refine-%s" % row[0])
		card.department = row[0]
		card.knowhow[row[1]] = TIER_KNOWHOW[3]
		card.desk_minutes = TIER_MINUTES[3]
		card.tier = 3
		card.display_name = row[2]
		card.gives_text = row[3]
		card.effects.append({"modifier": String(row[4]), "amount": row[5]})
		card.repeatable = true
		out.refinements.append(card)
	return out


static func _card(data: Dictionary, board_def: ResearchBoardDef) -> ResearchCardDef:
	var card := ResearchCardDef.new()
	card.id = StringName(data.id)
	card.display_name = data.name
	card.gives_text = data.gives
	card.department = BRANCHES[data.branch]
	card.tier = int(data.tier)
	card.requires.assign((data.pre as Array).map(func(p: String) -> StringName: return StringName(p)))
	match data.rule:
		"all": card.rule = 0
		"any": card.rule = 1
		_: card.rule = int(data.rule)
	var hire := String(card.id).begins_with("hire-")
	var total: int = HIRE_KNOWHOW if hire else TIER_KNOWHOW[card.tier]
	card.desk_minutes = HIRE_MINUTES if hire else TIER_MINUTES[card.tier]
	var letters: Array = data.kh
	var shares: Array[float] = [1.0]
	if letters.size() == 2:
		shares = [0.6, 0.4]
	elif letters.size() >= 3:
		shares = [0.5, 0.25, 0.25]
	for i in letters.size():
		for def in board_def.knowhow:
			if def.letter == letters[i]:
				card.knowhow[def.id] = roundi(total * shares[mini(i, shares.size() - 1)])
	card.lean = 1 if data.lean == "strict" else -1 if data.lean == "caring" else 0
	card.pair = StringName(data.pair)
	var addon: String = data.addon
	if not addon.is_empty() and not addon.ends_with("hook"):
		card.addon = StringName(addon.to_snake_case())
	card.trial = TRIALS.has(String(card.id))
	if data.up != "Start":
		var row: Array = REVEALS.get(data.up, [])
		if row.is_empty():
			push_warning("No reveal for '%s'" % data.up)
		else:
			var reveal := RevealDef.new()
			reveal.kind = row[0]
			reveal.id = row[1]
			reveal.count = row[2]
			reveal.value = row[3]
			reveal.fallback = row[4]
			reveal.hint = data.up
			card.reveal = reveal
	return card


## Policy cards, tried in one wing first.
const TRIALS := ["cell-searches", "earned-privileges", "strict-rules", "prison-council", "phone-credit",
		"walkabouts", "open-door-hour", "night-watch", "informants"]


static func _department_of_hire(card: ResearchCardDef) -> StringName:
	match String(card.id):
		"hire-chief-of-security": return &"security"
		"hire-head-of-wellbeing": return &"wellbeing"
		"hire-business-manager": return &"admin"
		"hire-works-manager": return &"industry"
		"hire-senior-doctor": return &"medical"
		"hire-head-of-learning": return &"education"
	return &""
