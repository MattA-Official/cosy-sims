class_name KnowhowSourceDef
extends Resource
## So much know-how of a kind for each time a Counters event happens.

## The Counters id, such as &"visit".
@export var event: StringName
## The KnowhowDef id it adds to.
@export var kind: StringName
@export var amount := 1.0
## How the source reads in a breakdown, such as "Visits".
@export var text: String
