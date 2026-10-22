class_name InspectionDef
extends Resource
## What an inspector from the Ministry checks, in the order they walk.

@export var id: StringName
@export var checks: Array[InspectionCheckDef] = []
## Checks that may fail with the visit still passing.
@export var allowed_fails := 1
