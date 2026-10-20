extends SceneTree
func _init() -> void:
	var main: Node = load("res://games/prison/main.tscn").instantiate()
	main.sample = 11
	root.add_child(main)
	await process_frame
	for n in main.building.levels:
		for p in main.building.levels[n].objects.values():
			if p.def.id in [&"office_desk", &"guard_desk", &"games_table"]:
				print(p.def.id, " ", p.centre)
	quit()
