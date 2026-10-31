class_name AirportHelp
## What the help card (F1) lists for the airport game.

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
		["Z", "Zones: landside, airside and staff only. Red doors are gaps in the line"],
		["C", "Belts: drag along then across; click a piece to turn it round"],
		["B", "Move, copy and templates"],
		["Esc", "Put the tool away"],
		["Shift", "Floor: the whole room"],
		["Ctrl", "Remove instead"],
		["Alt", "Place freely, or any angle"],
		["R", "Turn an object"],
		["[ / ]", "Turn step, or brush size"],
		["Click a one-way door", "Turn it round"],
		["Floor, Void", "Open an upper floor over a double-height hall"],
		["Ctrl+Z / Ctrl+Y", "Undo or redo; undo gives back land bought this hour"],
		["Ctrl+C / Ctrl+V", "Copy the room or object under the mouse, and put down copies"],
	]],
	["Time", [
		["Space", "Pause, or carry on"],
		[", / .", "Slower or faster (up to 4×)"],
	]],
	["Other", [
		["F1", "This card"],
		["Esc", "Pause menu, with nothing else open"],
		["F3", "Debug view and inspector"],
	]],
]
