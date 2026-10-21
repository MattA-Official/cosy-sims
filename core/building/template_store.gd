class_name TemplateStore
extends RefCounted
## Rooms and layouts kept by name to put down again: the game's starters,
## and your own, saved in the user folder so they last across saves and
## games.

const PATH := "user://templates.cfg"
const SECTION := "templates"

## Where your own templates are kept.
var path := PATH
## The game's own templates, [name, clip], listed first. They can't be
## overwritten or deleted.
var starters: Array = []
## (StringName) -> ObjectDef, for loading templates.
var find_object: Callable

var _file := ConfigFile.new()
var _loaded := false


## Every template's name, starters first, then your own in the order kept.
func names() -> Array[String]:
	_load()
	var out: Array[String] = []
	for entry: Array in starters:
		out.append(entry[0])
	for name in _file.get_section_keys(SECTION) if _file.has_section(SECTION) else PackedStringArray():
		if not out.has(name):
			out.append(name)
	return out


func is_starter(name: String) -> bool:
	return starters.any(func(entry: Array) -> bool: return entry[0] == name)


## The template by name, ready to put down, or null.
func clip(name: String) -> BuildClip:
	for entry: Array in starters:
		if entry[0] == name:
			return (entry[1] as BuildClip).copy()
	_load()
	if not _file.has_section_key(SECTION, name):
		return null
	return BuildClip.from_data(_file.get_value(SECTION, name), find_object)


## Keeps a clip under a name, replacing your own template of that name.
## Returns false for a starter's name or an empty name.
func keep(name: String, what: BuildClip) -> bool:
	name = name.strip_edges()
	if name.is_empty() or is_starter(name) or what == null:
		return false
	_load()
	_file.set_value(SECTION, name, what.to_data())
	return _file.save(path) == OK


## Forgets one of your own templates.
func forget(name: String) -> bool:
	_load()
	if not _file.has_section_key(SECTION, name):
		return false
	_file.erase_section_key(SECTION, name)
	return _file.save(path) == OK


## A name not yet used, such as "Cell 2".
func free_name(base: String) -> String:
	var taken := names()
	if not taken.has(base):
		return base
	var n := 2
	while taken.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_file = ConfigFile.new()
	if FileAccess.file_exists(path):
		_file.load(path)
