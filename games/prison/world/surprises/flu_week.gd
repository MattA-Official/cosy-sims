extends Surprise
## Flu week: colds spread twice as fast, and a few prisoners come down with
## flu, which spreads to anyone close by (PrisonLife.start_flu_week). Twice
## as many start ill when hard.

const FIRST := 3
## Loaded when needed: the catalogue that lists this script is used by it.
const LIFE := "res://games/prison/life/prison_life.gd"


func start() -> void:
	load(LIFE).start_flu_week(main, FIRST * (2 if hard else 1))


func words() -> String:
	var count := (main.illnesses as Illnesses).ill().size()
	return "%d ill" % count
