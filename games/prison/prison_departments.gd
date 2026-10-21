class_name PrisonDepartments
## The six departments the warden can hire a head for, and the heads'
## roles. Made once, so every system shares the same role objects.

const NAMES := ["security", "wellbeing", "admin", "industry", "medical", "education"]

static var _all: Array[DepartmentDef] = []


static func all() -> Array[DepartmentDef]:
	if _all.is_empty():
		_all.append(_make(&"security", "Security", "Chief of Security",
				"Keeps the guards sharp: searches, patrols and the perimeter.",
				{&"search_speed": 0.1}, "Guards search 10% faster", [], Color(0.42, 0.5, 0.66)))
		_all.append(_make(&"wellbeing", "Wellbeing", "Head of Wellbeing",
				"Looks after how prisoners feel: meals, visits and the little things.",
				{&"good_moodlet_time": 0.25}, "Good moments last 25% longer", [], Color(0.86, 0.62, 0.55)))
		_all.append(_make(&"admin", "Administration", "Business Manager",
				"Watches the money: suppliers, wages and the books.",
				{&"running_costs": -0.05}, "Wages and food cost 5% less", [], Color(0.55, 0.62, 0.5)))
		_all.append(_make(&"industry", "Industry", "Works Manager",
				"Runs the kitchen, laundry and workshop like a business.",
				{&"job_output": 0.1}, "Workshop makes 10% more", [&"kitchen", &"laundry", &"workshop"], Color(0.78, 0.6, 0.38)))
		_all.append(_make(&"medical", "Medical", "Senior Doctor",
				"Runs the infirmary.",
				{&"treat_speed": 0.2}, "Nurses treat 20% faster", [&"infirmary"], Color(0.62, 0.78, 0.76)))
		_all.append(_make(&"education", "Education", "Head of Learning",
				"Runs the courses and the classroom.",
				{&"course_pass": 0.1}, "Course exams 10% likelier to pass", [&"classroom"], Color(0.6, 0.6, 0.8)))
	return _all


## The ways a warden may work, each with a small bonus while they're in
## charge. Applicants for warden each have one.
static func warden_styles() -> Array:
	return [
		{"id": &"green_fingers", "name": "Green fingers", "words": "Good moments last 10% longer",
				"bonus": {&"good_moodlet_time": 0.1}},
		{"id": &"stickler", "name": "Stickler", "words": "Guards search 10% faster", "bonus": {&"search_speed": 0.1}},
		{"id": &"soft_touch", "name": "Soft touch", "words": "Course exams 5% likelier to pass",
				"bonus": {&"course_pass": 0.05}},
		{"id": &"penny_pincher", "name": "Penny pincher", "words": "Wages and food cost 3% less",
				"bonus": {&"running_costs": -0.03}},
		{"id": &"old_hand", "name": "Old hand", "words": "Hire cards 25% quicker", "bonus": {&"hire_speed": 0.25}},
	]


static func roles() -> Array[StaffRoleDef]:
	var out: Array[StaffRoleDef] = []
	for def in all():
		out.append(def.head_role)
	return out


static func find(id: StringName) -> DepartmentDef:
	for def in all():
		if def.id == id:
			return def
	return null


static func _make(id: StringName, words: String, head: String, about: String, bonus: Dictionary,
		bonus_text: String, rooms: Array[StringName], colour: Color) -> DepartmentDef:
	var role := StaffRoleDef.new()
	role.id = StringName("head_%s" % id)
	role.display_name = head
	role.description = "%s Hired from the warden's desk. %s." % [about, bonus_text]
	role.job_kinds = [&"office"]
	role.wage = 120
	role.most = 1
	role.only_shifts = [&"day"]
	role.by_card = true
	role.outfit_colour = colour.darkened(0.35)
	role.icon = preload("res://core/ui/icons/role_warden.svg")
	role.claims = &"office_desk"
	role.dressing = [preload("res://games/prison/catalogue/nameplate.tres"),
			preload("res://games/prison/catalogue/desk_plant.tres"), preload("res://games/prison/catalogue/mug.tres")]
	var def := DepartmentDef.new()
	def.id = id
	def.display_name = words
	def.head_role = role
	def.bonus.assign(bonus)
	def.bonus_text = bonus_text
	def.needs_rooms = rooms
	def.colour = colour
	return def
