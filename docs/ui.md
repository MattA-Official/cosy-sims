# The UI: how it fits together

Every game in the series shares one look and one set of UI pieces, all in
`core/ui/`. A game only supplies its own content (its catalogue, its help
text) and wires the pieces to its systems. This page covers what each piece
is, and how to add things to it.

## What's on screen

| Piece | Where | File | What it shows |
| --- | --- | --- | --- |
| Status bar | Top middle | `core/ui/status_bar.gd` | Short readouts: level, room under the mouse, people |
| View bar | Top right | `core/ui/view_bar.gd` | Level up and down, wall views, help and debug buttons |
| Build menu | Bottom middle | `games/prison/build_toolbar.gd` | Tool icons, and the choices for the current tool above them |
| Notes | Bottom right | `core/ui/toasts.gd` | Short messages that fade away |
| Controls card | Middle, on F1 | `core/ui/help_card.gd` | Every key and mouse control |
| Inspector and debug panel | Left and right, on F3 | `core/debug/` | Developer tools |

The prison game puts all of these on its `HUD` layer in
`games/prison/main.gd` (see `_add_hud()`).

## The theme

`core/ui/cosy_theme.tres` is set as the project's theme
(**Project Settings > GUI > Theme > Custom**), so every button, label and
panel picks it up without being told to. It is generated from
`core/ui/cosy_theme.gd`, which holds the palette and every style in one
place.

To change a colour or a corner, edit `cosy_theme.gd` and rebuild:

```
godot --headless --path . -s res://tools/build_theme.gd
```

Don't edit the `.tres` in the editor: the next rebuild overwrites it. Each
game can keep every shape and change only its accent colour:
`CosyTheme.build(CosyTheme.LIGHT, Color("5b9aa6"))`.

### Theme type variations

Rather than restyling a control by hand, set its **Theme Type Variation**
(in the inspector under Theme, or `theme_type_variation = &"HeaderLabel"` in
code) to one of these:

| Kind | Variations |
| --- | --- |
| Labels | `HeaderLabel` (bold, big), `TitleLabel` (small caps heading), `SubtleLabel` (muted, small), `KeyLabel` (a keycap), `HudLabel` (white with an outline, for text over the world) |
| Buttons | `AccentButton` (the main action), `DangerButton` (destructive), `FlatButton` (no background until hovered), `ToolButton` (build tools), `TileButton` (picture tiles), `ModeButton` (small square icon buttons) |
| Panels | `HudBar` (rounded bar), `InsetPanel` (a sunken box inside a card), `ToastPanel` (a note with an accent edge), `TooltipPanel` |
| Progress bars | `BarWarning` (amber), `BarDanger` (red); the default is green |

A plain `PanelContainer` is already a cream card, so most new windows need
no variation at all.

To try the look on its own, open `core/ui/theme_preview.tscn` and press F6.

## Icons

Icons are white line drawings in `core/ui/icons/`, 24 by 24 units, saved as
48 px SVGs. The theme tints them, so they turn cream on a picked button and
ink-coloured elsewhere. To add one:

1. Copy an existing `.svg`, keeping `stroke="#fff"` and `stroke-width="2"`,
   and draw with rounded lines.
2. Let Godot import it (open the editor, or run `godot --headless --path . --import`).
3. Load it with `load("res://core/ui/icons/my_icon.svg")`.

## Buttons with hover cards

`CosyButton` (`core/ui/cosy_button.gd`) is a `Button` whose tooltip is a
small card with a bold `title` and a line or two of `details`. Every button
in the build menu and view bar uses it, so pictures can stand in for words.

```gdscript
var tile := CosyButton.tile("Bed", "1 × 2 tiles", thumbnails.object(bed_def))
var symbol := CosyButton.tile("Cell", "Needs a bed and a toilet", cell_icon, true)
```

The fourth argument says the picture is a white line drawing to tint, not a
thumbnail with its own colours.

## The build menu

### Adding something to the catalogue

Nothing in the UI needs to change. Add a `.tres` to `games/prison/catalogue/`
and list it in `games/prison/prison_catalogue.gd`; the build menu makes a
tile for it the next time the tool opens.

Pictures come from `core/ui/thumbnails.gd`, which draws each entry once, in
a little world of its own, from the same angle as the game camera:

| Catalogue | Picture |
| --- | --- |
| Objects (`ObjectDef`) | The object as it looks in game |
| Floors (`FloorDef`) | A swatch |
| Walls (`WallDef`) | A short run of wall, or a fence |
| Rooms (the Room tool) | Every floor with every wall of the same kind, as a cut-away corner |
| Plants (`FoliageDef`) and paths (`PathStyleDef`) | As they look in game |
| Room types (`RoomTypeDef`) | Their `icon`, an SVG from `core/ui/icons/` |

When objects get real models, teach `Thumbnails.object()` to load the model
instead of drawing a box; every tile updates with it.

### Adding a tool

1. Add it to `BuildController.Tool` and handle it in the controller.
2. Add an entry to `TOOLS` in `build_toolbar.gd`:
   `[BuildController.Tool.MY_TOOL, "Name", "What it does.", "icon_name"]`.
   Its place in the list is its number key. `GROUP_STARTS` says where the
   dividers go.
3. In `_on_tool_changed()`, add a `match` branch that fills the bar above
   with its choices (see below).

### Adding a mode to a tool

Modes are the small square icon buttons, stacked two to a column. Each mode
list is a constant in `build_toolbar.gd` with entries
`[value, name, icon, what it does]`, for example:

```gdscript
const BRUSHES := [
	[Terrain.Brush.RAISE, "Raise", "brush_raise", "Hold to raise the ground."],
]
```

To add a mode, add an entry (and an icon). To give a tool a new set:

```gdscript
_columns("Brushes", _mode_buttons(BRUSHES, controller.terrain_brush,
		func(brush: Terrain.Brush) -> void: controller.terrain_brush = brush))
```

`_mode_buttons` makes one button per entry, lights the one equal to the
current value, and calls your function with the value picked. `_columns`
lays them out under a heading. For modes that deserve big tiles (the
terrain brushes and water), `_icon_tiles(title, entries, current, pick)`
takes the same entries and makes a tile each.

Brush tools get a **Brush** section of sliders from
`_add_brush_sliders(plants)`: size for terrain and plants (plants go down
to "Single", one plant per click), strength for terrain, and density for
plants. They follow the
controller's `brush_changed` signal, so [ and ] move them too. For a tile row instead, use
`_section("Title")` and add `CosyButton.tile(...)` buttons to the row it
returns.

## The status bar

The game sets readouts by key; they appear in the order first set, with
dividers between.

```gdscript
status.set_item(&"clock", "07:40  Breakfast", &"HeaderLabel")
status.set_item(&"money", "£12,450")
status.remove_item(&"money")
```

When the clock and money arrive, they slot in here.

## Notes (toasts)

`Toasts` is an autoload, so anything can post one:

```gdscript
Toasts.post("Breakfast is served", "38 prisoners are heading to the canteen.")
Toasts.post("Saved", "", 3.0) # Title only, gone after three seconds.
```

Up to four show at once; the oldest goes first.

## The controls card

Each game lists its controls as data (`games/prison/prison_help.gd`) and
hands them over before the card is added to the tree:

```gdscript
help_card.sections = PrisonHelp.SECTIONS
hud.add_child(help_card)
```

Each section is `[heading, [[keys, what they do], ...]]`. Keys separated by
` / ` each get their own keycap. F1 (`help_toggle` in
`core/input/default_actions.gd`) toggles it, Esc closes it.

## The view bar

`ViewBar` needs the game's `building` and `controller` before it goes into
the tree. It changes the level and wall view itself, and follows Page Up /
Down and Tab. Its help and debug buttons only emit `help_pressed` and
`debug_pressed`, so the game decides what they open; call `show_debug(on)`
to light the debug button.

## Adding a new panel

1. Make a script that extends `PanelContainer` (a cream card by default) in
   `core/ui/` if every game could use it, or in the game's folder if not.
2. Build its contents in `_ready()` with plain controls and the variations
   above. Give it any data it needs (like `building`) through variables
   the game sets before adding it.
3. Add it to the game's `HUD` layer in `main.gd`, and connect its signals
   there. Keep game rules out of the panel: it emits signals, the game acts.
4. Anchor it with `set_anchors_and_offsets_preset()` in `_ready()`, once it
   is in the tree, so it follows the window size.
