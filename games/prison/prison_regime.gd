class_name PrisonRegime
## The prison's operations and sessions for the Regime page. Times are half
## hours of the day: 12 is 06:00, 18 is 09:00.

const MEAL := &"table"


static func operations() -> Array[OperationDef]:
	var out: Array[OperationDef] = []
	var lorry := OperationDef.make(&"kitchen_lorry", "Kitchen lorry",
			"Food crates come for the kitchen, rubbish goes, and the workshop's goods go off to be sold.",
			[12], 8, 20)
	lorry.avoid_tags = [MEAL]
	out.append(lorry)
	var report := OperationDef.make(&"daily_report", "Daily report and autosave",
			"The Ministry's grades for yesterday, and the game saves.", [12], 12, 12)
	report.fixed_reason = "The Ministry's day starts at 06:00"
	out.append(report)
	var contracts := OperationDef.make(&"workshop_contracts", "Workshop contracts",
			"New contracts are offered for the workshop.", [14], 12, 24)
	out.append(contracts)
	var release := OperationDef.make(&"release", "Release to reception",
			"Prisoners due out set off for reception from now until 18:00.", [16], 14, 24)
	release.avoid_tags = [MEAL]
	out.append(release)
	var bus := OperationDef.make(&"intake_bus", "Intake bus",
			"The morning bus brings new prisoners. Transfer offers come an hour after it.", [18], 16, 28)
	bus.avoid_tags = [MEAL]
	out.append(bus)
	var planning := OperationDef.make(&"parole_planning", "Parole planning",
			"The warden picks who goes before the parole board today.", [26], 12, 35)
	planning.needs_role = &"warden"
	out.append(planning)
	var hearings := OperationDef.make(&"parole_hearings", "Parole hearings",
			"Hearings start, one after another at the warden's desk.", [28], 12, 35)
	hearings.needs_role = &"warden"
	out.append(hearings)
	var counts := OperationDef.make(&"tool_counts", "Tool counts",
			"Tools in the kitchen and workshop are counted; anything missing is noticed.", [12, 36], 0, 47, 8)
	counts.avoid_blocks = [&"yard"]
	out.append(counts)
	var searches := OperationDef.make(&"cell_searches", "Random cell searches",
			"Between these two times guards search cells at random, as often as Security sets.", [18, 38], 12, 44, 2)
	out.append(searches)
	var shifts := OperationDef.make(&"shift_changes", "Shift changes",
			"Day staff come in and night staff go home, and the other way round.", [12, 36], 12, 12)
	shifts.fixed = true
	shifts.fixed_reason = "Moves with the rota"
	out.append(shifts)
	return out


## A session for each course: as long as one of its sessions, every day.
static func sessions(courses: Array[CourseDef]) -> Array[SessionDef]:
	var out: Array[SessionDef] = []
	for course in courses:
		var def := SessionDef.new()
		def.id = course.id
		def.display_name = course.display_name
		def.length = ceili(course.session_minutes / Schedule.SLOT_MINUTES)
		def.room_type = course.room_type
		def.staff_role = course.teacher_role
		def.course = course.id
		def.per_week = 7
		out.append(def)
	return out
