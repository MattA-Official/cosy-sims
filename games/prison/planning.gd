class_name Planning
extends Node
## Planning permission: with red tape on, land you buy is paid for at once
## but only becomes yours to build on once an application is filled in at
## a desk (MINUTES_PER_PLOT of desk work a plot, double with red tape
## Full). A clerk does it if there is one, otherwise the warden. Undoing
## the purchase within the hour withdraws it for a full refund.

const KIND := &"planning"
const MINUTES_PER_PLOT := 30.0

var desk_work: DeskWork
var heads: Heads
## () -> bool: a clerk is on the staff.
var has_clerk: Callable
var land_plots: LandPlots


func start() -> void:
	land_plots.hold = func(_plots: Array) -> bool: return _owner() != 0
	land_plots.awaiting.connect(func(key: Vector2i, plots: Array[Rect2i]) -> void:
		desk_work.add(_owner(), KIND, "Planning application: %d plot%s" % [plots.size(), "" if plots.size() == 1 else "s"],
				minutes(plots.size()), key))
	land_plots.withdrawn.connect(func(key: Vector2i) -> void: desk_work.remove(KIND, key))
	desk_work.finished.connect(func(_owner_id: int, item: DeskWork.Item) -> void:
		if item.kind == KIND:
			land_plots.grant(item.ref))


## Desk minutes to apply for some plots, by the red tape setting.
func minutes(plots: int) -> float:
	return MINUTES_PER_PLOT * plots * (2.0 if desk_work.red_tape == DeskWork.RedTape.FULL else 1.0)


## Whose desk applications go to: the clerks' shared pile, the warden's,
## or nobody's (0: red tape Off, or no warden to sign it).
func _owner() -> int:
	if desk_work.red_tape == DeskWork.RedTape.OFF:
		return 0
	if has_clerk.is_valid() and has_clerk.call():
		return DeskWork.SHARED
	return heads.warden().id if heads.warden() != null else 0
