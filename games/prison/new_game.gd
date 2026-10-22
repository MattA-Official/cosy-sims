class_name NewGame
## What the new game screen picked, waiting for the prison scene to start
## with it. The title screen fills these in and sets `pending`; the prison
## reads them once in its _ready and clears `pending`.

## Cosy names to start from; the dice on the new game screen picks one.
const NAMES: Array[String] = ["HMP Little Wicket", "HMP Mossbank", "HMP Hollyhock Lane", "HMP Puddleby",
		"HMP Kettle Green", "HMP Brambleford", "HMP Thistledown", "HMP Nettlecombe", "HMP Tumbledown Hill",
		"HMP Crumpet Cross", "HMP Wobbly Bridge", "HMP Sleepy Hollow"]
## Every sample prison the new game screen offers as a starting point,
## by index into SamplePrisons.NAMES: the ones that play as a game.
const STARTS: Array[int] = [11, 12, 10, 9, 0]

static var pending := false
static var prison_name := ""
## A sample prison (SamplePrisons index) to start in, or -1 for empty land.
static var start := -1
## Whether to run the guided first day (on empty land).
static var tutorial := false
static var sentence_length := Sentences.Length.NORMAL
static var staff_cars := false
static var split_levels := false
static var door_steps := false
## The warden picked: their work trait ids, empty for the default warden.
static var warden_traits: Array[StringName] = []


## Three warden candidates, each two different warden work traits (ids).
static func warden_candidates() -> Array:
	var ids: Array = PrisonStaffTraits.all().filter(func(t: StaffTraitDef) -> bool: return t.roles.has(&"warden")) \
			.map(func(t: StaffTraitDef) -> StringName: return t.id)
	var out: Array = []
	while out.size() < 3:
		ids.shuffle()
		var pair := [ids[0], ids[1]]
		if not out.any(func(o: Array) -> bool: return o.has(pair[0]) and o.has(pair[1])):
			out.append(pair)
	return out


static func random_name() -> String:
	return NAMES.pick_random()
