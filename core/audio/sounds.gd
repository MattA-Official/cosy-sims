extends Node
## Plays the game's sounds through their own buses, each with a volume you
## can set (kept in the user folder). Sounds are defined in DEFS by id and
## found as <id>_1.wav, <id>_2.wav ... in DIR; any game in the series can
## add its own with add().
##
## Registered as the Sounds autoload: Sounds.play(&"build_place").

## Buses under Master, made at start if the project doesn't have them.
const BUSES: Array[StringName] = [&"Effects", &"Interface", &"Ambience", &"Music"]
const DIR := "res://core/audio/sounds/"
const SETTINGS := "user://audio.cfg"
const PLAYERS := 8
## [bus, volume in dB] by id. The files carry their own relative loudness
## (see docs/art.md), so they all play at 0 dB.
const DEFS := {
	&"build_place": [&"Effects", 0.0],
	&"build_remove": [&"Effects", 0.0],
	&"build_rotate": [&"Interface", 0.0],
	&"build_paint": [&"Effects", 0.0],
	&"build_error": [&"Interface", 0.0],
	&"build_finished": [&"Effects", 0.0],
	&"build_wall": [&"Effects", 0.0],
	&"build_floor": [&"Effects", 0.0],
}

var defs: Dictionary[StringName, SoundDef] = {}
## Turns every sound off, such as while a save loads or undo puts things
## back.
var muted := false

var _players: Array[AudioStreamPlayer] = []
var _last_played: Dictionary[StringName, float] = {}
var _next := 0


func _ready() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")
	for id: StringName in DEFS:
		var def := SoundDef.new()
		def.id = id
		def.bus = DEFS[id][0]
		def.volume_db = DEFS[id][1]
		for n in range(1, 10):
			var file := "%s%s_%d.wav" % [DIR, id, n]
			if not ResourceLoader.exists(file):
				break
			def.streams.append(load(file))
		add(def)
	for i in PLAYERS:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_load_volumes()


func add(def: SoundDef) -> void:
	defs[def.id] = def


## Plays a sound by id, a take at random. Quietly does nothing for an
## unknown id, or one played a moment ago.
func play(id: StringName, volume_db := 0.0) -> void:
	var def: SoundDef = defs.get(id)
	if muted or def == null or def.streams.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(id, -INF) < def.gap:
		return
	_last_played[id] = now
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = def.streams.pick_random()
	player.bus = def.bus if AudioServer.get_bus_index(def.bus) >= 0 else &"Master"
	player.volume_db = def.volume_db + volume_db
	player.pitch_scale = 1.0 + randf_range(-def.pitch_spread, def.pitch_spread)
	player.play()


## A bus's volume from 0 to 1.
func volume(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(index)) if index >= 0 else 0.0


func set_volume(bus: StringName, amount: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	amount = clampf(amount, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(amount))
	AudioServer.set_bus_mute(index, amount <= 0.001)
	var file := ConfigFile.new()
	file.load(SETTINGS)
	file.set_value("volume", String(bus), amount)
	file.save(SETTINGS)


func _load_volumes() -> void:
	var file := ConfigFile.new()
	if file.load(SETTINGS) != OK:
		return
	for bus in [&"Master"] + BUSES:
		if file.has_section_key("volume", String(bus)):
			var amount: float = file.get_value("volume", String(bus))
			var index := AudioServer.get_bus_index(bus)
			if index >= 0:
				AudioServer.set_bus_volume_db(index, linear_to_db(amount))
				AudioServer.set_bus_mute(index, amount <= 0.001)
