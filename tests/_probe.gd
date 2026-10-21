extends "res://tests/test_runner.gd"
func _process(_delta) -> bool: _test_perks(); print("done ", _failures); quit(0); return true
