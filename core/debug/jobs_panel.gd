class_name JobsPanel
extends Node3D
## Shown with the debug view (F3): a panel on the right listing every open
## job (who is on it, or why it is waiting) and the stock of every item,
## with any warnings the game raises, and a dotted line on the ground from
## each worker to where their job takes them next.

## Seconds between refreshing the lists.
const REFRESH_SECONDS := 0.5
## Where the panel's top sits when it is beside the debug overlay's panel.
const TOP := 70.0
## The panel's width, the same as the debug overlay's panel.
const WIDTH := 418.0
const GAP := 12.0
## The most jobs listed; the rest are counted.
const MOST_LISTED := 8
## The most kinds of item listed under Stock; the rest are counted.
const MOST_STOCK := 8
## Items with this tag are counted together on one line.
const LUMPED_TAG := &"litter"

@export var debug_overlay: DebugOverlay
@export var line_colour := Color(0.45, 0.7, 0.95, 0.9)

var jobs: JobBoard
var items: ItemStore
var building: Building
## Returns warnings to show under the stock, such as "Food runs out
## tomorrow", as an Array of Strings. Optional.
var warnings: Callable

var _layer := CanvasLayer.new()
var _panel := PanelContainer.new()
var _text := Label.new()
var _mesh := ImmediateMesh.new()
var _material := MeshShapes.vertex_colour_material(true)
var _wait := 0.0


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_layer.layer = 10
	add_child(_layer)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_top = TOP
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 14)
	_panel.add_child(_text)
	_layer.add_child(_panel)


func _process(delta: float) -> void:
	var on := debug_overlay == null or debug_overlay.visible
	_panel.visible = on
	_mesh.clear_surfaces()
	if not on or jobs == null:
		return
	_draw_lines()
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH_SECONDS
		_text.text = describe()
		_place_panel()


## Under the debug overlay's panel when it fits, otherwise beside it.
func _place_panel() -> void:
	_panel.reset_size()
	var under := TOP if debug_overlay == null else debug_overlay.panel_bottom() + GAP * 0.5
	var fits := under + _panel.size.y <= _panel.get_viewport_rect().size.y - GAP
	var right := -GAP if fits or debug_overlay == null else -GAP * 2.0 - WIDTH
	_panel.offset_right = right
	_panel.offset_left = right - WIDTH
	_panel.offset_top = under if fits else TOP
	_panel.offset_bottom = _panel.offset_top


## The panel's words: jobs, stock and warnings.
func describe() -> String:
	var lines := PackedStringArray(["Jobs (%d)" % jobs.jobs.size()])
	var sorted := jobs.jobs.duplicate()
	sorted.sort_custom(func(a: Job, b: Job) -> bool: return a.priority > b.priority)
	for job: Job in sorted.slice(0, MOST_LISTED):
		var who := job.worker.name if job.worker != null else ("waiting: %s" % job.reason.to_lower()
				if job.wait > 0.0 else "nobody yet")
		lines.append("  %s · %s" % [job.title, who])
	if sorted.size() > MOST_LISTED:
		lines.append("  and %d more" % (sorted.size() - MOST_LISTED))
	if items != null:
		lines.append("")
		lines.append("Stock")
		var totals := stock()
		var names := totals.keys()
		names.sort()
		for item_name: String in names:
			lines.append("  %s: %d" % [item_name, totals[item_name]])
		if totals.is_empty():
			lines.append("  nothing yet")
	if warnings.is_valid():
		for warning: String in warnings.call():
			lines.append("⚠ %s" % warning)
	return "\n".join(lines)


## How many of each item there are anywhere, by name, with all the
## litter on one line.
func stock() -> Dictionary:
	var out := {}
	for pile: Dictionary in items.held.values() + items.on_floor.values():
		for item: ItemDef in pile:
			_count(out, item, pile[item])
	for pair: Array in items.carried.values():
		_count(out, pair[0], pair[1])
	return out


func _count(out: Dictionary, item: ItemDef, count: int) -> void:
	var item_name := LUMPED_TAG.capitalize() if item.tags.has(LUMPED_TAG) else item.display_name
	out[item_name] = out.get(item_name, 0) + count


func _draw_lines() -> void:
	var drawn := false
	for job in jobs.jobs:
		var stage := job.current()
		if job.worker == null or stage == null:
			continue
		var place: Variant = _place(stage)
		if place == null:
			continue
		var to: Vector3 = place
		if not drawn:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
			drawn = true
		var from := job.worker.position + Vector3.UP * 0.1
		var dots := maxi(1, ceili(from.distance_to(to) / 0.35))
		for k in dots:
			var at := from.lerp(to, float(k + 1) / dots)
			MeshShapes.add_box_immediate(_mesh, at, Vector3(0.05, 0.03, 0.05), line_colour)
	if drawn:
		_mesh.surface_end()


## Where a stage happens, a little above the floor, or null if it hasn't
## picked its place yet.
func _place(stage: Job.Stage) -> Variant:
	var map := building.levels.get(stage.level) as BuildingMap
	if map == null:
		return null
	var spot := Vector2(stage.tile) + Vector2(0.5, 0.5)
	if stage.at_object():
		var placed: BuildingMap.PlacedObject = map.objects.get(stage.object)
		if placed == null:
			return null
		spot = placed.centre
	return Vector3(spot.x, map.floor_height(Vector2i(spot.floor())) + 0.1, spot.y)
