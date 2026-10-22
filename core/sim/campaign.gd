class_name Campaign
extends Node
## A chapter of the light campaign at work: its cast speaking up as things
## happen, in letters that wait in the in-tray and never pause the game;
## a kind nudge after a bad run; and, once the chapter is won, the offer of
## the next one. There is no losing a chapter. Which chapters are done is
## kept on this computer, not in the save.

signal next_chosen(def: ScenarioDef)

const PROGRESS := "user://campaign.cfg"
## Bad nights in a row before the nudge.
const NUDGE_NIGHTS := 2
## Days a letter waits in the tray.
const LETTER_DAYS := 3

var chapters: Array[ScenarioDef] = []
var cast: Array[CastDef] = []
## The chapter being played, or null outside the campaign.
var chapter: ScenarioDef
var in_tray: InTray:
	set(value):
		in_tray = value
		in_tray.lookups.append(_letter)
		in_tray.answered.connect(_on_answered)
## Indexes of the chapter's lines already said.
var shown: Dictionary[int, bool] = {}
var bad_nights := 0
var won := false
## Where progress is kept; tests point it elsewhere.
var progress_path := PROGRESS


func active() -> bool:
	return chapter != null


## Says every line waiting on `event` not yet said. Returns how many.
func trigger(event: StringName) -> int:
	if chapter == null:
		return 0
	var said := 0
	for i in chapter.cast_lines.size():
		if chapter.cast_lines[i].trigger == event and not shown.has(i):
			say(i)
			said += 1
	return said


func say(index: int) -> InTray.Card:
	shown[index] = true
	if in_tray == null:
		return null
	return in_tray.post_about(_letter(StringName("cast:%s:%d" % [chapter.id, index])), 0, "")


## Each night: after a run of bad ones, a kind word.
func night(bad: bool) -> void:
	if chapter == null or won:
		return
	bad_nights = bad_nights + 1 if bad else 0
	if bad_nights >= NUDGE_NIGHTS:
		trigger(&"nudge")


## The chapter is won: remembered on this computer, and the next offered.
func win() -> void:
	if chapter == null or won:
		return
	won = true
	mark_done(chapter.id)
	trigger(&"won")
	if not chapter.next.is_empty() and in_tray != null:
		in_tray.post_about(_letter(StringName("chapter_done:" + String(chapter.id))), 0, "")


func next_chapter() -> ScenarioDef:
	return find(chapter.next) if chapter != null else null


func find(id: StringName) -> ScenarioDef:
	for def in chapters:
		if def.id == id:
			return def
	return null


func cast_member(id: StringName) -> CastDef:
	for def in cast:
		if def.id == id:
			return def
	return null


## Chapters done on this computer.
func done() -> Array[StringName]:
	var out: Array[StringName] = []
	var file := ConfigFile.new()
	if file.load(progress_path) == OK:
		for id: String in file.get_value("campaign", "done", []):
			out.append(StringName(id))
	return out


func mark_done(id: StringName) -> void:
	var file := ConfigFile.new()
	file.load(progress_path)
	var ids: Array = file.get_value("campaign", "done", [])
	if not ids.has(String(id)):
		ids.append(String(id))
	file.set_value("campaign", "done", ids)
	file.save(progress_path)


## The chapters open to play: the first, and each after one done.
func unlocked() -> Array[ScenarioDef]:
	var finished := done()
	var out: Array[ScenarioDef] = []
	for i in chapters.size():
		if i == 0 or finished.has(chapters[i - 1].id) or finished.has(chapters[i].id):
			out.append(chapters[i])
	return out


func capture() -> Dictionary:
	return {"shown": shown.keys(), "bad_nights": bad_nights, "won": won}


func restore(data: Dictionary) -> void:
	shown.clear()
	for index: int in data.get("shown", []):
		shown[index] = true
	bad_nights = data.get("bad_nights", 0)
	won = data.get("won", false)


func _on_answered(card: InTray.Card, choice: TrayChoiceDef, _by: StringName) -> void:
	if String(card.def.id).begins_with("chapter_done:") and choice.tags.has(&"next"):
		var next := next_chapter()
		if next != null:
			next_chosen.emit(next)


## The cast's letters and the end of a chapter, made from their ids.
func _letter(id: StringName) -> TrayCardDef:
	var parts := String(id).split(":")
	var def: TrayCardDef
	if parts[0] == "cast" and parts.size() == 3:
		var scenario := find(StringName(parts[1]))
		var index := parts[2].to_int()
		if scenario == null or index >= scenario.cast_lines.size():
			return null
		var line := scenario.cast_lines[index]
		var who := cast_member(line.who)
		var title := "%s, %s" % [who.display_name, who.role] if who != null else "A letter"
		def = TrayCardDef.make(id, &"memo", &"", title, line.words,
				[TrayCardDef.choice("Thanks", [], [&"approve"], "Read a letter from %s" % (who.display_name if who != null else "a friend"))])
	elif parts[0] == "chapter_done" and parts.size() == 2:
		var scenario := find(StringName(parts[1]))
		var next := find(scenario.next) if scenario != null else null
		if next == null:
			return null
		def = TrayCardDef.make(id, &"memo", &"", "%s: done" % scenario.title,
				"Every goal is met. Start chapter %d, %s, or carry on here as long as you like." % [next.chapter, next.title],
				[TrayCardDef.choice("Next chapter", [], [&"next"], "Went on to the next chapter"),
				TrayCardDef.choice("Carry on here", [], [&"decline"], "Stayed on")], 1)
	else:
		return null
	def.weight = 0.0
	def.deadline_days = LETTER_DAYS
	return def
