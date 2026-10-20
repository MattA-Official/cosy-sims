class_name GroupDef
extends Resource
## A kind of person in the game, such as prisoners, staff or visitors.
## Zones and doors say which groups may go where.

@export var id: StringName
## Plural, as in "Prisoners and staff".
@export var display_name: String
## Carries keys, so locked doors don't stop them.
@export var has_keys := false
## Gets a bed of their own in a home room, such as a cell.
@export var gets_bed := false
## The colour of their clothes.
@export var outfit_colour := Color(0.95, 0.55, 0.2)
## The NeedDef ids they have. Empty means every need, as for prisoners;
## staff sleep at home, so have no sleep need here.
@export var needs: Array[StringName] = []
