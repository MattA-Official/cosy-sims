class_name PrisonStaffTraits
extends RefCounted
## The prison's staff traits (StaffTraitDef): a pool for ordinary staff,
## three for each department head, and the warden's, who has two.

const STAFF: Array[StringName] = [&"guard", &"cook", &"cleaner", &"handyman", &"nurse", &"teacher", &"counsellor", &"clerk"]


static func all() -> Array[StaffTraitDef]:
	var out: Array[StaffTraitDef] = []
	# Anyone on the floor.
	var calm := StaffTraitDef.make(&"calm", "Calm", "Morale moves half as fast, up or down", STAFF)
	calm.morale_rate = 0.5
	out.append(calm)
	var cheerful := StaffTraitDef.make(&"cheerful", "Cheerful", "Happier at work (+5 morale)", STAFF)
	cheerful.morale = 5.0
	out.append(cheerful)
	out.append(StaffTraitDef.make(&"speedy", "Speedy", "Works 10% faster", STAFF, {}, 1.1))
	var grumbler := StaffTraitDef.make(&"grumbler", "Grumbler", "Works 10% faster but grumbles (-5 morale)", STAFF, {}, 1.1)
	grumbler.morale = -5.0
	out.append(grumbler)
	out.append(StaffTraitDef.make(&"eagle_eyed", "Eagle-eyed", "Guards search 3% faster", [&"guard"], {&"search_speed": 0.03}))
	out.append(StaffTraitDef.make(&"kitchen_whizz", "Kitchen whizz", "Meals 10% likelier to be lovely", [&"cook"], {&"tasty_meals": 0.1}))
	out.append(StaffTraitDef.make(&"neat_freak", "Neat freak", "Cleans 15% faster", [&"cleaner"], {}, 1.15))
	out.append(StaffTraitDef.make(&"handy", "Handy", "Mends 15% faster", [&"handyman"], {}, 1.15))
	out.append(StaffTraitDef.make(&"bedside_manner", "Bedside manner", "Treatment 5% quicker", [&"nurse"], {&"treat_speed": 0.05}))
	out.append(StaffTraitDef.make(&"natural_teacher", "Natural teacher", "Course passes 3% likelier", [&"teacher"], {&"course_pass": 0.03}))
	out.append(StaffTraitDef.make(&"warm", "Warm", "Good moments last 3% longer", [&"counsellor"], {&"good_moodlet_time": 0.03}))
	out.append(StaffTraitDef.make(&"tidy_desk", "Tidy desk", "Desk work 15% faster", [&"clerk"], {}, 1.15))
	# The warden.
	out.append(StaffTraitDef.make(&"green_fingers", "Green fingers", "Good moments last 10% longer", [&"warden"],
			{&"good_moodlet_time": 0.1}))
	var stickler := StaffTraitDef.make(&"stickler", "Stickler", "Guards search 10% faster", [&"warden"], {&"search_speed": 0.1})
	stickler.lean = 1
	out.append(stickler)
	var soft := StaffTraitDef.make(&"soft_touch", "Soft touch", "Course passes 5% likelier", [&"warden"], {&"course_pass": 0.05})
	soft.lean = -1
	out.append(soft)
	var pincher := StaffTraitDef.make(&"penny_pincher", "Penny pincher", "Wages and food cost 5% less, but staff are less happy (-5 morale)",
			[&"warden"], {&"running_costs": -0.05})
	pincher.staff_morale = -5.0
	out.append(pincher)
	out.append(StaffTraitDef.make(&"old_hand", "Old hand", "Hire cards 25% quicker", [&"warden"], {&"hire_speed": 0.25}))
	# Department heads, three each.
	var head := func(id: StringName, words: String, about: String, department: StringName, bonus: Dictionary,
			lean := 0, speed := 1.0) -> StaffTraitDef:
		var def := StaffTraitDef.make(id, words, about, [StringName("head_%s" % department)], bonus, speed)
		def.lean = lean
		return def
	out.append(head.call(&"by_the_book", "By the book", "Guards search 5% faster", &"security", {&"search_speed": 0.05}, 1))
	out.append(head.call(&"veteran", "Old hand", "Works 10% faster", &"security", {}, 0, 1.1))
	out.append(head.call(&"softly_spoken", "Softly spoken", "Good moments last 3% longer", &"security", {&"good_moodlet_time": 0.03}, -1))
	out.append(head.call(&"ex_nurse", "Ex-nurse", "Treatment 5% quicker", &"wellbeing", {&"treat_speed": 0.05}))
	out.append(head.call(&"sporty", "Sporty", "Good moments last 3% longer", &"wellbeing", {&"good_moodlet_time": 0.03}))
	var party: StaffTraitDef = head.call(&"party_planner", "Party planner", "Staff a little happier (+2 morale); things that happen count half as much again towards new research cards", &"wellbeing", {&"reveal_counts": 0.5})
	party.staff_morale = 2.0
	out.append(party)
	out.append(head.call(&"thrifty", "Penny pincher", "Wages and food cost 3% less", &"admin", {&"running_costs": -0.03}, 1))
	var charmer: StaffTraitDef = head.call(&"charmer", "Charmer", "Staff happier (+3 morale)", &"admin", {})
	charmer.staff_morale = 3.0
	out.append(charmer)
	out.append(head.call(&"pedant", "Stickler", "Desk work 15% faster", &"admin", {}, 1, 1.15))
	out.append(head.call(&"tinkerer", "Tinkerer", "Job output 5% higher", &"industry", {&"job_output": 0.05}))
	out.append(head.call(&"foodie", "Foodie", "Meals 10% likelier to be lovely", &"industry", {&"tasty_meals": 0.1}))
	out.append(head.call(&"gardener", "Green fingers", "Good moments last 3% longer", &"industry", {&"good_moodlet_time": 0.03}, -1))
	out.append(head.call(&"old_school", "Old school", "Treatment 5% quicker", &"medical", {&"treat_speed": 0.05}, 1))
	out.append(head.call(&"researcher", "Researcher", "Works 10% faster", &"medical", {}, 0, 1.1))
	out.append(head.call(&"kindly", "Kindly", "Good moments last 3% longer", &"medical", {&"good_moodlet_time": 0.03}, -1))
	out.append(head.call(&"bookworm", "Bookworm", "Course passes 3% likelier", &"education", {&"course_pass": 0.03}))
	out.append(head.call(&"firm", "Firm", "Course passes 2% likelier", &"education", {&"course_pass": 0.02}, 1))
	out.append(head.call(&"mentor", "Mentor", "Staff learn 10% faster", &"education", {&"staff_xp": 0.1}, -1))
	return out
