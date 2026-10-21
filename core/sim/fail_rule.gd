class_name FailRule
extends Resource
## A way to lose on a hard setting: deep in debt for days, a one-star
## grade for days, or a sit-in that drags on. The first night it holds
## the report warns; after `days` nights in a row (or `amount` hours, for
## a sit-in) the game is lost if the difficulty allows it.

## &"debt" (balance below -amount), &"grade" (grade at or below amount),
## or &"sit_in" (a sit-in lasting amount game hours).
@export var kind: StringName
@export var amount := 0.0
@export var days := 1
## The warning; %d is nights (or hours) left to put it right.
@export var warning: String
## Said on the card when the game is lost.
@export var reason: String
