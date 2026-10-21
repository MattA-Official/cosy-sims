class_name OffenceDef
extends Resource
## What a prisoner was sent down for: a soft, cosy offence on their file.
## High-category offences show only as "Serious offence".

@export var id: StringName
@export var display_name: String
## The prisoner category it is picked for (low, medium or high).
@export var category: StringName = &"low"
## How often it comes up within its category.
@export var weight := 1.0
