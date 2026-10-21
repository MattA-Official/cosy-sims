class_name PostcardDef
extends Resource
## What a leaver went on to do, keyed by their best skill or a course they
## passed: a few plans for the history line ("open a bakery") and the
## postcards they might send. {name} is the sender's first name.

## A skill or course id, or empty for anyone.
@export var key: StringName
## "open a bakery", as in "Dot Kettle left to open a bakery".
@export var plans: PackedStringArray = []
## "Opened a bakery. Thank you for the cooking course! {name}"
@export var lines: PackedStringArray = []
