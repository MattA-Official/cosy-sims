class_name ProgressSourceDef
extends Resource
## Something that moves a ProgressDef up or down, such as a good day or a
## course passed, with the words the inspector shows for it.

@export var id: StringName
## Shown in the "Why?" line, such as "Good day".
@export var text: String
@export var amount := 1.0
## Most it gives one person in a day; 0 for no limit.
@export var per_day_cap := 0.0
## A one-off milestone, such as passing a course: not held back by the
## day's cap, nor counted towards it.
@export var milestone := false
