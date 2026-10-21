class_name Budget
extends Node
## Money beyond the daily grant: a week's forecast of money in and out,
## industry contracts for the workshop's goods, and small loans.
##
## Each morning a couple of contracts are on offer: so many goods in so
## many days for a lump sum on top of the usual sale price. One runs at a
## time; late, it pays nothing extra. A loan comes at once and is paid back
## a share each midnight, with interest.

signal contract_done(contract: Dictionary)
signal contract_missed(contract: Dictionary)

const OFFER_HOUR := 7
const OFFERS := 2
## Goods per contract, days to make them, and the bonus per good on top of
## the sale price.
const CONTRACT_GOODS := Vector2i(10, 30)
const CONTRACT_DAYS := Vector2i(3, 6)
const BONUS_PER_GOOD := 25
const CLIENTS: Array[String] = ["the council", "a garden centre", "a school", "a café chain", "a toy shop",
		"the hospital", "a furniture shop", "a hotel"]
const LOAN_SIZES: Array[int] = [2000, 5000, 10000]
const LOAN_INTEREST := 0.1
const LOAN_DAYS := 10
const FORECAST_DAYS := 7

var ledger: Ledger
var finances: Finances
var intake: Intake
var workshop: Workshop
var building: Building
## When set, its operation times are used instead of the hour above (main
## passes on Regime.operation_due).
var regime: Regime
var clock: GameClock:
	set(value):
		clock = value
		clock.hour_changed.connect(func(hour: int) -> void:
			if hour == OFFER_HOUR and regime == null:
				make_offers())
		clock.day_changed.connect(func(_day: int) -> void: _midnight())

## Contracts on offer today: {client, goods, days, pay}.
var offers: Array[Dictionary] = []
## The one under way: {client, goods, days, pay, made, due}, or empty.
var contract: Dictionary = {}
## The loan being paid off: {left, per_day}, or empty.
var loan: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func start() -> void:
	workshop.collected.connect(func(count: int) -> void:
		if contract.is_empty():
			return
		contract.made += count
		if contract.made >= contract.goods:
			ledger.add(contract.pay, "Contracts")
			var done := contract
			contract = {}
			contract_done.emit(done))


## A couple of contracts for the day, if there's a workshop to make goods.
func make_offers() -> Array[Dictionary]:
	offers.clear()
	if not has_workshop():
		return offers
	for i in OFFERS:
		var goods := _rng.randi_range(CONTRACT_GOODS.x, CONTRACT_GOODS.y)
		goods -= goods % 5
		offers.append({"client": CLIENTS[_rng.randi() % CLIENTS.size()], "goods": goods,
				"days": _rng.randi_range(CONTRACT_DAYS.x, CONTRACT_DAYS.y), "pay": goods * BONUS_PER_GOOD})
	return offers


## Takes an offer on, if nothing else is under way.
func accept(index: int) -> bool:
	if not contract.is_empty() or index < 0 or index >= offers.size():
		return false
	contract = offers[index].duplicate()
	contract.made = 0
	contract.due = clock.day() + contract.days
	offers.clear()
	return true


## Borrows money now; a share comes back out each midnight.
func borrow(amount: int) -> bool:
	if not loan.is_empty() or amount <= 0:
		return false
	var owed := roundi(amount * (1.0 + LOAN_INTEREST))
	loan = {"left": owed, "per_day": ceili(float(owed) / LOAN_DAYS)}
	ledger.add(amount, "Loans")
	return true


## The next week, a line a day: [day, money in, money out, balance after],
## from what comes in and goes out now.
func forecast(days := FORECAST_DAYS) -> Array:
	var out: Array = []
	var balance := ledger.balance
	var wages := 0
	for shift in finances.shifts.shifts:
		wages += finances.shift_wages(shift)
	var food: int = -ledger.yesterday.get("Food", 0)
	var goods: int = ledger.yesterday.get("Goods sold", 0)
	var grant := finances.daily_grant()
	var per_prisoner := float(grant) / maxi(_prisoners(), 1) if _prisoners() > 0 else 50.0 * finances.grant_scale
	var beds := intake.free_beds()
	var left: int = loan.get("left", 0)
	for entry: Array in intake.forecast(days):
		var arrivals := mini(entry[2], beds)
		beds -= arrivals
		grant += roundi(arrivals * per_prisoner)
		var money_in := grant + goods + arrivals * Intake.FEE
		var repay := mini(loan.get("per_day", 0), left)
		left -= repay
		var money_out := wages + food + repay
		balance += money_in - money_out
		out.append([entry[0], money_in, money_out, balance])
	return out


func has_workshop() -> bool:
	for n: int in building.levels:
		for room: Room in building.levels[n].rooms():
			if room.type == &"workshop":
				return true
	return false


## Midnight: a loan payment, and a late contract lapses.
func _midnight() -> void:
	if not loan.is_empty():
		var pay := mini(loan.per_day, loan.left)
		ledger.add(-pay, "Loan repayments")
		loan.left -= pay
		if loan.left <= 0:
			loan = {}
	if not contract.is_empty() and clock.day() > contract.due:
		var missed := contract
		contract = {}
		contract_missed.emit(missed)
	offers.clear()


func _prisoners() -> int:
	return finances.people.people.filter(func(p: Person) -> bool:
		return p.group == finances.prisoner_group).size()
