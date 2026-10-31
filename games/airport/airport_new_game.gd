class_name AirportNewGame
## What the new airport screen picked, waiting for the airport scene to
## start with it. The title screen fills these in and sets `pending`; the
## airport reads them once in its _ready and clears `pending`.

## Cosy names to start from; the dice picks one.
const NAMES: Array[String] = ["Puddleby Airfield", "Little Wicket International", "Mossbank Regional",
		"Kettle Green Airport", "Hollyhock Field", "Brambleford Aerodrome", "Thistledown Airport",
		"Crumpet Cross Airfield", "Wobbly Bridge Regional", "Nettlecombe Skyport"]

## Starts on offer: empty land, or a small working shed to try things in.
enum Start { EMPTY, SHED }

static var pending := false
static var airport_name := ""
static var start := Start.SHED
static var map_size: StringName = &"small"


static func random_name() -> String:
	return NAMES.pick_random()
