extends Node3D
## A one-shot puff of dust and a few crumbs for demolishing. Add it where
## the thing stood (scale it to the footprint); it frees itself when done.

@onready var _puffs: CPUParticles3D = $Puffs
@onready var _crumbs: CPUParticles3D = $Crumbs


func _ready() -> void:
	_puffs.emitting = true
	_crumbs.emitting = true
	await get_tree().create_timer(maxf(_puffs.lifetime, _crumbs.lifetime) + 0.1).timeout
	queue_free()
