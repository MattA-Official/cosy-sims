class_name BudgetPanel
extends VBoxContainer
## The Money window's budget: the week ahead day by day, the workshop's
## contracts on offer or under way, and loans.

var budget: Budget

var _forecast := GridContainer.new()
var _contracts := VBoxContainer.new()
var _loan := HBoxContainer.new()
var _loan_words := Label.new()
var _shown: Array = []


func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	add_child(_heading("The week ahead"))
	var note := Label.new()
	note.text = "From today's staff, prisoners, food and goods, with the forecast arrivals."
	note.theme_type_variation = &"SubtleLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	_forecast.columns = 4
	_forecast.add_theme_constant_override(&"h_separation", 16)
	add_child(_forecast)
	add_child(_heading("Contracts"))
	_contracts.add_theme_constant_override(&"separation", 4)
	add_child(_contracts)
	add_child(_heading("Loans"))
	_loan_words.theme_type_variation = &"SubtleLabel"
	_loan_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loan_words.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(_loan_words)
	_loan.add_theme_constant_override(&"separation", 6)
	for amount in Budget.LOAN_SIZES:
		var button := Button.new()
		button.text = "Borrow %s" % Ledger.text(amount)
		button.focus_mode = FOCUS_NONE
		button.tooltip_text = "Paid back over %d days with %d%% interest: %s in all." % [Budget.LOAN_DAYS,
				roundi(Budget.LOAN_INTEREST * 100.0), Ledger.text(roundi(amount * (1.0 + Budget.LOAN_INTEREST)))]
		button.pressed.connect(func() -> void:
			budget.borrow(amount)
			refresh())
		_loan.add_child(button)
	add_child(_loan)


func refresh() -> void:
	if budget == null:
		return
	var rows := budget.forecast()
	var key: Array = [rows, budget.offers.duplicate(true), budget.contract.duplicate(), budget.loan.duplicate()]
	if key == _shown:
		return
	_shown = key
	for child in _forecast.get_children():
		_forecast.remove_child(child)
		child.queue_free()
	for text in ["Day", "In", "Out", "Balance"]:
		_cell(text, true)
	for row: Array in rows:
		_cell(GameClock.WEEKDAYS[(row[0] - 1) % GameClock.WEEKDAYS.size()].left(3), false)
		_cell("+" + Ledger.text(row[1]), false)
		_cell(Ledger.text(-row[2]), false, row[2] > 0)
		_cell(Ledger.text(row[3]), false, row[3] < 0)
	for child in _contracts.get_children():
		_contracts.remove_child(child)
		child.queue_free()
	if not budget.contract.is_empty():
		var c := budget.contract
		_contracts.add_child(_words("For %s: %d of %d goods made, due by day %d. Pays %s on top." % [c.client,
				c.made, c.goods, c.due, Ledger.text(c.pay)]))
	elif not budget.has_workshop():
		_contracts.add_child(_words("Build a workshop to take on contracts for its goods."))
	elif budget.offers.is_empty():
		_contracts.add_child(_words("New contracts come each morning at %02d:00." % Budget.OFFER_HOUR))
	else:
		for i in budget.offers.size():
			var offer := budget.offers[i]
			var row := HBoxContainer.new()
			var label := _words("%s: %d goods in %d days, %s on top." % [(offer.client as String).capitalize(),
					offer.goods, offer.days, Ledger.text(offer.pay)])
			label.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_child(label)
			var take := Button.new()
			take.text = "Take on"
			take.focus_mode = FOCUS_NONE
			take.pressed.connect(func() -> void:
				budget.accept(i)
				refresh())
			row.add_child(take)
			_contracts.add_child(row)
	if budget.loan.is_empty():
		_loan_words.text = "Borrow to tide you over; it's paid back a share each midnight."
	else:
		_loan_words.text = "Paying back a loan: %s left, %s a day." % [Ledger.text(budget.loan.left),
				Ledger.text(budget.loan.per_day)]
	_loan.visible = budget.loan.is_empty()


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeaderLabel"
	return label


func _words(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SubtleLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _cell(text: String, bold: bool, red := false) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if not text.is_empty() and text != "Day" else HORIZONTAL_ALIGNMENT_LEFT
	if bold:
		label.theme_type_variation = &"SubtleLabel"
	if red:
		label.add_theme_color_override(&"font_color", Color(0.75, 0.35, 0.32))
	_forecast.add_child(label)
