class_name Ledger
extends Node
## The prison's money: the balance, what came in and went out today, line
## by line, and how the last few days closed. Going below zero stops
## building and hiring, nothing else. In sandbox the balance never matters.

signal changed

## Days of closing balances kept for the chart.
const HISTORY_DAYS := 7

var balance := 0
## Unlimited money: spending is always allowed.
var sandbox := false
## Today's lines so far: name to total (money in is positive).
var today: Dictionary[String, int] = {}
## Yesterday's lines, as `today` was at midnight.
var yesterday: Dictionary[String, int] = {}
## Closing balances of the last HISTORY_DAYS days, oldest first.
var closing: Array[int] = []
## Money spent each of the last HISTORY_DAYS days, oldest first.
var spent: Array[int] = []


## Adds money in (positive) or out (negative) under a line such as
## "Wages".
func add(amount: int, line: String) -> void:
	if amount == 0:
		return
	balance += amount
	today[line] = today.get(line, 0) + amount
	changed.emit()


## Whether building and hiring are allowed: in sandbox, or not in debt.
func can_spend() -> bool:
	return sandbox or balance >= 0


## Ends the day: today's lines become yesterday's, and the balance goes on
## the chart. The game calls it at midnight, after the day's last money.
func close_day() -> void:
	yesterday = today
	today = {}
	var out := 0
	for line: String in yesterday:
		out += mini(yesterday[line], 0)
	spent.append(-out)
	if spent.size() > HISTORY_DAYS:
		spent = spent.slice(spent.size() - HISTORY_DAYS)
	closing.append(balance)
	if closing.size() > HISTORY_DAYS:
		closing = closing.slice(closing.size() - HISTORY_DAYS)
	changed.emit()


## Average spent a day over the last few days, or 0 before any.
func daily_costs(days := 3) -> float:
	var recent := spent.slice(maxi(spent.size() - days, 0))
	if recent.is_empty():
		return 0.0
	var sum := 0
	for amount in recent:
		sum += amount
	return float(sum) / recent.size()


## The total of some lines' amounts.
static func total(lines: Dictionary[String, int]) -> int:
	var sum := 0
	for line: String in lines:
		sum += lines[line]
	return sum


## Money as shown to the player, such as "£1,250" or "-£40".
static func text(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + "£" + digits + grouped
