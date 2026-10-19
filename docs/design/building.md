# Building and world design

Decisions made with Matt, and the shape we're heading for. Newest
decisions are listed first within each section.

## Decided

### Grid and placement
- **Walls, floors and rooms use whole 1 m tiles.** Walls sit on the edges
  between tiles, like The Sims.
- **Objects snap based on what they are.** Each `ObjectDef` has a `snap`
  setting: whole tiles (beds, tables), quarter tiles (toilets, showers), or
  free placement (decorations). Holding Alt places anything freely. Object
  sizes can be fractional, and objects can touch each other and walls.
- **The plot can grow.** The grid covers the whole world (96 × 96 for now),
  but you can only build on land you own (`BuildingMap.land`). You start
  with the middle 48 × 48, and `add_land()` adds more. Buying plots will
  sit on top of this later.

### Indoors and outdoors
- **Walls decide.** A floor area that is fully enclosed by indoor walls and
  doors is indoors. Anything bounded by a fence or hedge, or open on any
  side, is outdoors. Roofs will be drawn over indoor rooms automatically.
- **Floors and walls come in styles** (`FloorDef`, `WallDef`), each marked
  indoor or outdoor:
  - indoor floors: concrete, tiles, wood
  - outdoor floors: paving, lawn
  - indoor walls: plaster, brick
  - outdoor walls: fence, hedge
- **Room types say where they belong**: cells, canteens and shower rooms
  must be indoors, and a yard must be outdoors.

### Demolition
- A click removes the most specific thing under the mouse: an object, then
  a wall near the mouse, then the tile.
- Dragging clears floor, objects and inner walls. Walls around the edge stay
  if a neighbouring room still uses them.
- Hold Ctrl with the wall or floor tool to remove walls or floor only.

## Agreed direction, not built yet

### Paths and roads: off the grid
Paths and roads will **not** be tile floors. They'll work like Cities:
Skylines 2: you draw curved segments between nodes, and they snap to each
other, to doors and to buildings rather than to the grid. In practice:
- A `PathNetwork` of nodes and Bézier segments, each with a style (gravel
  path, paving, road) and a width.
- Meshes are generated along the curves, and they follow the terrain.
- Junctions are made where segments meet, with simple rounded joins for
  now.
- Paths are outdoor-only. Grid floors stay for building interiors and
  patios.

### Terrain, water and foliage
- **Terrain is a heightmap** that you sculpt with raise, lower, flatten and
  smooth brushes. Placing a building flattens the ground under its tiles.
- **Water** starts as a flat water level: anything below it is underwater.
  Ponds and rivers can be carved later.
- **Foliage** comes in two kinds. Grass and flowers are painted on and drawn
  with MultiMesh. Trees and bushes are free-placed objects, and building
  over them clears them.

### What this means for people (step 3)
Since paths are curves and the ground can slope, people won't walk on the
tile grid. They'll use Godot's navigation meshes, baked from floors, paths
and walkable terrain, with walls and objects as obstacles and doors as the
links between areas. The tile grid stays the authority for rooms and
building.

## Open questions
- Multi-storey buildings: when, and how do stairs work?
- Roofs: drawn automatically for now. Do you want to be able to choose
  roof styles?
- Undo: per action, or per drag?
