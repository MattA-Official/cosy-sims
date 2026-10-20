class_name MisconductModel
extends Resource
## The sums behind misconduct, shared by every game. Unhappy people build
## up temper; once an hour they may act on it, likelier the higher it is
## and less likely when someone in charge is watching. What they do is a
## rung of the ladder (MisconductDef) that their mood allows, the worst
## ones likeliest.

## Temper builds below this mood and falls away above it.
@export var calm_mood := 45.0
## Temper an hour for each point of mood below calm_mood.
@export var temper_gain := 0.6
## Temper lost an hour above calm_mood.
@export var temper_decay := 10.0
## Chance an hour at full temper (it goes with the square of temper).
@export var roll_factor := 0.4
## Chance is multiplied by this while someone in charge is close by.
@export var watched_factor := 0.5
## Each rung up the ladder is this much likelier than the one below.
@export var worse_weight := 1.5
## Temper lost after acting up.
@export var after_acting := 40.0


## Temper after `hours` at this mood. `scale` comes from traits.
func temper_after(temper: float, mood: float, hours: float, scale := 1.0) -> float:
	if mood < calm_mood:
		return minf(100.0, temper + (calm_mood - mood) * temper_gain * scale * hours)
	return maxf(0.0, temper - temper_decay * hours)


## The chance of acting up in an hour's roll.
func chance(temper: float, watched: bool, scale := 1.0) -> float:
	var out := pow(temper / 100.0, 2.0) * roll_factor * scale
	return out * watched_factor if watched else out


## Picks a rung someone may reach, given their mood, the minutes they have
## spent under each rung's mood (by id) and their trait ids. `rungs` is in
## order, mildest first. Returns null if none fits.
func pick(rungs: Array[MisconductDef], mood: float, minutes_below: Dictionary, trait_ids: Array[StringName],
		rng: RandomNumberGenerator) -> MisconductDef:
	var allowed: Array[MisconductDef] = []
	var weights: Array[float] = []
	var total := 0.0
	for i in rungs.size():
		var def := rungs[i]
		if mood >= def.mood_below or minutes_below.get(def.id, 0.0) < def.days_below * GameClock.MINUTES_PER_DAY:
			continue
		var w := def.weight * pow(worse_weight, i)
		for id in trait_ids:
			w *= def.trait_weights.get(id, 1.0)
		allowed.append(def)
		weights.append(w)
		total += w
	if allowed.is_empty() or total <= 0.0:
		return null
	var roll := rng.randf() * total
	for i in allowed.size():
		roll -= weights[i]
		if roll <= 0.0:
			return allowed[i]
	return allowed[-1]
