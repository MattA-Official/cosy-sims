class_name PrisonHelp
## What the help card (F1) lists for the prison game.

const SECTIONS := [
	["Camera", [
		["W / A / S / D", "Pan (or the arrow keys)"],
		["Q / E", "Rotate"],
		["Wheel", "Zoom (or + and -)"],
		["Shift", "Go faster"],
		["Right-drag", "Pan"],
		["Middle-drag", "Rotate and tilt"],
		["PgUp / PgDn", "Up or down a level"],
		["Tab", "Wall view: up, cutaway, down, roofs"],
	]],
	["Building", [
		["1 to 0", "Pick a tool"],
		["Z", "Zones: who may go where, and door locks"],
		["X", "Patrol routes for guards"],
		["Esc", "Put the tool away"],
		["Shift", "Floor: the whole room; Zones: pin a lock"],
		["Ctrl", "Remove instead"],
		["Alt", "Place freely, or any angle"],
		["R", "Turn an object"],
		["V", "Change an object's look"],
		["[ / ]", "Turn step, or brush size"],
		["F", "Hold to turn to face the mouse"],
	]],
	["Time", [
		["Space", "Pause, or carry on"],
		[", / .", "Slower or faster (up to 4×)"],
		["T", "The timetable"],
		["P", "Staff and work programmes"],
		["M", "Money"],
		["O", "Warden's office: intake, goals, grade"],
		["K", "Security: cameras, incidents, alerts"],
	]],
	["Other", [
		["F1", "This card"],
		["F2", "Save and load"],
		["F4", "Game settings: difficulty, sentence length"],
		["Ctrl+Z / Ctrl+Y", "Undo or redo building"],
		["F3", "Debug view and inspector"],
	]],
]
