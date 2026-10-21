class_name Sound
## Reaches the Sounds autoload from scripts that load before it exists,
## such as classes a test runner compiles up front. Does nothing without
## it.


static func play(id: StringName, volume_db := 0.0) -> void:
	var board := _board()
	if board != null:
		board.play(id, volume_db)


static func volume(bus: StringName) -> float:
	var board := _board()
	return board.volume(bus) if board != null else 1.0


static func set_volume(bus: StringName, amount: float) -> void:
	var board := _board()
	if board != null:
		board.set_volume(bus, amount)


static func _board() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Sounds") if tree != null else null
