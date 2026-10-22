class_name PrisonCampaign
## Wires the light campaign (core/sim/campaign.gd) into the prison: the
## settings and tools each chapter starts with, Old Stan on the staff, the
## cast's triggers, and starting the next chapter.

## Chapter settings: key -> [the system on main, its property].
const SETTINGS := {
	"utilities": [&"utilities", &"mode"], "weather": [&"weather", &"enabled"],
	"surprises": [&"surprises", &"frequency"], "red_tape": [&"desk_work", &"red_tape"],
	"seasons": [&"calendar", &"enabled"], "protestors": [&"protest", &"enabled"],
}


static func setup(main: Node, fresh: bool) -> void:
	var campaign: Campaign = main.campaign
	var standing: Standing = main.standing
	var counters: Counters = main.counters
	var clock: GameClock = main.clock
	campaign.name = "Campaign"
	campaign.chapters.assign(PrisonCatalogue.CHAPTERS)
	campaign.cast.assign(PrisonCatalogue.CAST)
	campaign.in_tray = main.in_tray
	main.add_child(campaign)
	# Goals the chapters ask for that the sandbox's don't.
	standing.goal_kinds[&"balance"] = func(_goal: GoalDef) -> float: return float((main.ledger as Ledger).balance)
	standing.goal_kinds[&"open_day_score"] = func(_goal: GoalDef) -> float: return main.get_meta(&"open_day_score", 0.0)
	standing.goal_kinds[&"reputation"] = func(_goal: GoalDef) -> float: return (main.reputation as Reputation).score
	var scenario := standing.scenario
	if scenario == null or scenario.chapter <= 0:
		return
	campaign.chapter = scenario
	var toolbar := main.get_node_or_null("HUD/BuildToolbar")
	if toolbar != null:
		toolbar.locked = scenario.locked_tools
	if fresh:
		apply_settings(main, scenario.settings)
		name_stan.call_deferred(main)
		campaign.trigger.call_deferred(&"start")
	var done: Dictionary[StringName, bool] = standing.scenario_done.duplicate()
	clock.minute_passed.connect(func(_minute: int) -> void:
		for id: StringName in standing.scenario_done:
			if not done.has(id):
				done[id] = true
				campaign.trigger(StringName("goal:" + String(id))))
	clock.day_changed.connect(func(day: int) -> void:
		campaign.trigger(StringName("day:%d" % day)))
	counters.counted.connect(func(id: StringName, total: int, n: int) -> void:
		if total == n:
			campaign.trigger(StringName("first:" + String(id))))
	standing.nightly.append(func() -> void:
		campaign.night(standing.grade <= 1 or (main.ledger as Ledger).balance < 0))
	standing.scenario_won.connect(func(_def: ScenarioDef) -> void: campaign.win())
	campaign.next_chosen.connect(func(next: ScenarioDef) -> void: start_chapter(main, next))


static func apply_settings(main: Node, settings: Dictionary) -> void:
	for key: String in settings:
		if SETTINGS.has(key):
			var target: Object = main.get(SETTINGS[key][0])
			if target != null:
				target.set(SETTINGS[key][1], settings[key])


## The longest-serving guard on the roster becomes Old Stan.
static func name_stan(main: Node) -> void:
	var campaign: Campaign = main.campaign
	var stan := campaign.cast_member(&"stan")
	if stan == null or stan.staff_role.is_empty():
		return
	for record: StaffRoster.Record in (main.roster as StaffRoster).records:
		if record.role == stan.staff_role:
			record.name = stan.display_name
			if record.person != null:
				record.person.name = stan.display_name
			return


## Loads the next chapter, keeping the prison's name.
static func start_chapter(main: Node, def: ScenarioDef) -> void:
	if main.get_tree().current_scene != main:
		return
	NewGame.pending = true
	NewGame.start = def.layout
	NewGame.prison_name = main.title
	Standing.next_scenario = def.id
	main.get_tree().reload_current_scene.call_deferred()
