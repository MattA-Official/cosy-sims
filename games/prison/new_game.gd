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
static var sentence_length := Sentences.Length.NORMAL
static var staff_cars := false
static var split_levels := false
static var door_steps := false


static func random_name() -> String:
	return NAMES.pick_random()
