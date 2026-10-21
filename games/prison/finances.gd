class_name Finances
extends Node
## Where the prison's money comes from and goes. A grant for every prisoner
## each midnight; wages as each shift starts; the workshop's goods sold
## and the kitchen's food bought when the lorry calls. Building costs are
## BuildCosts' job, and new arrivals pay their own fee (see Intake).

## Money to start a new prison with, outside sandbox.
const STARTING_MONEY := 20000
## The grant for each prisoner of no category, each day, before the
## grade's bonus. Categories have their own.
const GRANT_PER_PRISONER := 50
const GOODS_PRICE := 30
## One crate makes a batch of meals (Kitchen.MEALS_PER_BATCH).
const CRATE_PRICE := 40

var ledger: Ledger
var people: People
var shifts: Shifts
var roles: Dictionary[StringName, StaffRoleDef] = {}
var categories: Dictionary[StringName, CategoryDef] = {}
var prisoner_group: StringName = &"prisoner"
## Multiplies the daily grant: the grade's bonus, 1 for none.
var grant_scale := 1.0
## Multiplies wages (difficulty).
var wage_scale := 1.0
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(_on_hour)
		clock.day_changed.connect(func(_day: int) -> void: _end_day())
var kitchen: Kitchen:
	set(value):
		kitchen = value
		kitchen.delivered.connect(func(count: int) -> void: ledger.add(-count * CRATE_PRICE, "Food"))
var workshop: Workshop:
	set(value):
		workshop = value
		workshop.collected.connect(func(count: int) -> void: ledger.add(count * GOODS_PRICE, "Goods sold"))


## Wages for a shift's staff, as it starts.
func shift_wages(shift: ShiftDef) -> int:
	return roundi(shifts.wage_bill(shift.id) * shift.pay_scale * wage_scale)


## The grant for today's prisoners, by their category.
func daily_grant() -> int:
	var sum := 0
	for person in people.people:
		if person.group == prisoner_group:
			var category: CategoryDef = categories.get(person.category)
			sum += category.daily_grant if category != null else GRANT_PER_PRISONER
	return roundi(sum * grant_scale)


func _on_hour(hour: int) -> void:
	for shift in shifts.shifts:
		if shift.start_hour == hour:
			ledger.add(-shift_wages(shift), "Wages")


func _end_day() -> void:
	ledger.add(daily_grant(), "Daily grant")
	ledger.close_day()
