# Cosy Sims

A series of small, cute management sims that share one look and one set of
familiar mechanics. First up is a prison game, drawing on Prison Architect for
its systems, Parkitect for its camera and style, and The Sims / Software Inc.
for flexible building. Later games might include a hospital, an airport, a
school and a museum.

![The sample prison on its plot, with hills, woods and a pond around it](docs/images/terrain.png)

All art is placeholder for now. Built with [Godot 4.7](https://godotengine.org/).

## Getting started

1. Install Godot 4.7 (the standard build, not .NET).
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **F5** to run. You start with a small sample prison you can fly
   around and build on.

### Controls

| Camera | |
| --- | --- |
| WASD or arrows | Pan |
| Q / E | Rotate |
| Mouse wheel or + / - | Zoom |
| Shift | Go faster |
| Right-drag | Pan |
| Middle-drag | Rotate and tilt |

| Building | |
| --- | --- |
| 1 Room | Drag to build a floor with walls all round |
| 2 Floor | Drag to lay or restyle floor on the side of any walls where you start; Shift-click floors or restyles the whole room; hold Ctrl to remove. Raise and Lower nudge floors for split levels; Ramp drags a slope from the low side to the high side. Stairs: click the foot, move the way they climb, click short of the top for a landing, at the top to build; choose square or rounded landings |
| 3 Wall | Drag from corner to corner to build or restyle; snaps straight or to 45°, or pick Any angle (or hold Alt); hold Ctrl to remove |
| 4 Doors and windows | Pick a door, glass window or barred window, then click a wall; click it again to fill it in |
| 5 Objects | Click to place; R turns by 45° and [ / ] change the step (90° down to 1°); hold F to pin it and turn it to face the mouse; hold Alt to place freely. Lifts link with a lift in the same spot upstairs |
| 6 Room type | Click a room to mark it as a cell, canteen and so on |
| 7 Demolish | Click an object or wall to remove it, or drag to clear an area |
| 8 Terrain | Hold to raise, lower, flatten or smooth the ground; or add water to a hollow, or drain a pond |
| 9 Plants | Hold to plant trees, bushes or flowers; hold Ctrl to clear them |
| 0 Paths | Straight: click each end. Curved: click the start, a bend and the end. Freehand: drag. Points snap to the middle of tiles (bends don't); hold Alt to swap that for one point, or turn Snap to grid off. Page Up / Down while placing builds stairs, a ramp or a bridge and raises its far end. Esc stops; Ctrl-click removes a path |
| [ / ] | Brush size, for terrain and plants |
| Tab | Walls up or cut away |
| Esc | Put the tool away |
| F3 | Debug view: rooms tinted and labelled, and details of the tile under the mouse. With no build tool (Esc), click a person, object, room or tile to inspect it: set a person's needs, send them somewhere, add or remove prisoners, pause everyone |

The room, floor and wall tools let you pick a style in the row above the
toolbar. Fences, hedges, paving and lawn are outdoor styles: a room enclosed
by walls is indoors, but one bounded by a fence stays outdoors. Rooms are
worked out from the walls automatically. Once a room has a type, a label
floats over it saying what it still needs, such as a toilet.

You can only build, sculpt and plant inside the land you own, which is
marked by a low kerb. Building a room or floor flattens the ground under it
and clears any plants, and the ground under buildings can't be sculpted.
To make a pond, dig a hollow and click it with **Add water**. The
water rises to the lowest point of the rim, and moves when you dig deeper
or cut through the rim. Water stays off floors.

Paths and roads are curves, not tiles, though their ends snap to the
middle of tiles. Ends also snap to other paths (making a junction) and to
outside doors, and a path crossing another makes a junction with smooth
corners; paths can't run along or over each other. A path follows the
ground; stairs, ramps and bridges are your choice with Page Up and Page
Down while placing. Paths stay on your own land and off floors, and
building over a path removes it.

Each floor remembers its own height. New floor lines up with any floor
next to it, or else with the ground where you started dragging (rounded to
a quarter of a metre), and the ground is fitted underneath so it never
shows through. Higher floors stand on foundations.

Prisoners walk the build: through doors, up stairs and lifts, along paths
and over bridges. They get sleepy, hungry and grubby, and head off to a
free bed, table or shower when they need one; otherwise they wander.
Press F3 and click someone to see what they're up to.

See [docs/design/building.md](docs/design/building.md) for the design
decisions behind all this.

## Layout

| Path | What |
| --- | --- |
| `core/` | Parts every game will share: camera, grid, input, building, terrain, paths, people. Kept free of prison-specific code. |
| `games/prison/` | The prison game. Anything specific to prisons lives here. |
| `tests/` | Headless checks (see below). |
| `tools/` | Developer helpers, such as the screenshot script. |
| `docs/` | The plan, and design notes in `docs/design/`. |

The rule of thumb: build things in `games/prison/` first, and move them into
`core/` once they work and we can see what is genuinely generic. See
[docs/plan.md](docs/plan.md).

## Checks

```sh
godot --headless --import --path .          # once, to build the class cache
godot --headless --path . -s res://tests/test_runner.gd
```

To save a screenshot of the main scene (needs a display, not `--headless`;
on a machine without a GPU, `xvfb-run` with Mesa's lavapipe Vulkan driver
works):

```sh
godot --path . -s res://tools/screenshot.gd -- screenshot.png
```
