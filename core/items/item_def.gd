class_name ItemDef
extends Resource
## Something people carry about, such as a crate of food, a meal tray or a
## bundle of laundry. Each game keeps its own catalogue of these.

@export var id: StringName
@export var display_name: String
## What it is good for, such as "ingredient" or "meal". Objects say which
## tags they hold, and jobs fetch items by tag.
@export var tags: Array[StringName] = []
## How many one person carries at once.
@export var carry_count := 1
## Its model, held in front of whoever carries it and stacked where it is
## kept. Without one it shows as a box of `colour`.
@export var model: PackedScene
@export var colour := Color(0.8, 0.65, 0.45)

## Contraband: things prisoners shouldn't have. Prisoners up to no good may
## pocket one when they finish using an object with one of these tags
## (a spoon from a canteen table, a screwdriver from a workbench).
@export var pocketed_from: Array[StringName] = []
## Sets off a metal detector.
@export var metal := false
## How easily a search or a dog notices it, 0 to 1.
@export var smell := 0.0
## What it's worth between prisoners, in biscuits.
@export var trade_value := 1
## What it's for: &"treat", &"weapon", &"dig", &"phone" or &"rowdy".
@export var use: StringName
## Extra damage a blow does with it, for weapons.
@export var hit := 0.0
## Given to whoever uses it up, for treats.
@export var use_moodlet: StringName


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
## How big it's drawn lying in a pile or on something, as items are about
## 0.4 m and a few should fit on a counter. Litter is drawn full size.
@export var piled_scale := 0.55
