extends "res://tests/test_runner.gd"
func _process(_delta) -> bool: _test_heads(); _test_perks(); _test_staff_roster(); print("done ", _failures); quit(0); return true
