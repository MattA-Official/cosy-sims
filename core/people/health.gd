class_name Health
extends RefCounted
## How well someone is, from 100 (well) down: bruised, hurt (limping, needs
## treating) and knocked out (flat on the floor seeing stars until helped).
## Shared by every game; the prison's fights and infirmary use it, and the
## hospital game will too.

enum Injury { NONE, BRUISED, HURT, KNOCKED_OUT }

const WELL := 99.5
const BRUISED_ABOVE := 70.0
const HURT_ABOVE := 40.0
## Walking speed while hurt, and while being helped along knocked out.
const HURT_PACE := 0.6
const KNOCKED_OUT_PACE := 0.5

const WORDS: Array[String] = ["Well", "Bruised", "Hurt", "Knocked out"]


static func injury(health: float) -> Injury:
	if health >= WELL:
		return Injury.NONE
	if health >= BRUISED_ABOVE:
		return Injury.BRUISED
	if health >= HURT_ABOVE:
		return Injury.HURT
	return Injury.KNOCKED_OUT


static func pace(health: float) -> float:
	match injury(health):
		Injury.HURT:
			return HURT_PACE
		Injury.KNOCKED_OUT:
			return KNOCKED_OUT_PACE
	return 1.0


static func words(health: float) -> String:
	return WORDS[injury(health)]
