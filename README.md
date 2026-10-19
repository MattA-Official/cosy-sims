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
| 2 Floor | Drag to lay or restyle floor; hold Ctrl to remove |
| 3 Wall | Drag from corner to corner to build or restyle; hold Ctrl to remove |
| 4 Doors and windows | Pick a door, glass window or barred window, then click a wall; click it again to fill it in |
| 5 Objects | Click to place; R rotates; hold Alt to place freely |
| 6 Room type | Click a room to mark it as a cell, canteen and so on |
| 7 Demolish | Click an object or wall to remove it, or drag to clear an area |
| 8 Terrain | Hold to raise, lower, flatten or smooth the ground |
| 9 Plants | Hold to plant trees, bushes or flowers; hold Ctrl to clear them |
| [ / ] | Brush size, for terrain and plants |
| Tab | Walls up or cut away |
| Esc | Put the tool away |
| F3 | Debug view: rooms tinted and labelled, and details of the tile under the mouse |

The room, floor and wall tools let you pick a style in the row above the
toolbar. Fences, hedges, paving and lawn are outdoor styles: a room enclosed
by walls is indoors, but one bounded by a fence stays outdoors. Rooms are
worked out from the walls automatically. Once a room has a type, a label
floats over it saying what it still needs, such as a toilet.

You can only build, sculpt and plant inside the land you own, which is
marked by a low kerb. Building a room or floor flattens the ground under it
and clears any plants, and the ground under buildings can't be sculpted.
Lower the ground below the water level to dig a pond.

Each floor remembers its own height. New floor lines up with any floor
next to it, or else with the ground where you started dragging (rounded to
a quarter of a metre), and the ground is fitted underneath so it never
shows through. Higher floors stand on foundations.
See [docs/design/building.md](docs/design/building.md) for the design
decisions behind all this.

## Layout

| Path | What |
| --- | --- |
| `core/` | Parts every game will share: camera, grid, input, building, terrain. Kept free of prison-specific code. |
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
