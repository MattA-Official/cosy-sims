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

## Agreed direction

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

### Terrain, water and foliage (basics built)
- **Terrain is a heightmap** (`core/terrain/terrain.gd`), one height per
  tile corner, that you sculpt with raise, lower, flatten and smooth
  brushes. You can only sculpt your own land, and the ground under
  buildings is locked.
- **Floors have their own height**, stored in `BuildingMap.floor_heights`
  rather than read from the terrain. New floor takes the height of any
  floor beside it, or else the ground where the drag started, rounded to
  0.25 m. The ground is then fitted to the floor: each corner drops to the
  lowest floor touching it, so it never pokes through, and higher floors
  stand on foundations. This is the groundwork for manual floor heights
  and storeys. You can't build where that height is under water.
- **Windows** are a kind of wall piece, like doors: glass or barred. They
  block walking, keep rooms enclosed and indoors, and can't go in fences.
- **Water** is placed bodies (`core/terrain/water_layer.gd`). Clicking a
  hollow fills it to the height where it would spill over its rim, found
  by rising from the lowest tile and always spreading to the lowest
  neighbour. Each body refills from its seed tile whenever the ground
  changes, so ponds follow digging, and drain if their hollow goes.
  Floors block water. Hollows over 1500 tiles are refused, so a click on
  a plain ringed by hills doesn't flood it. A sea level is available for
  coastal maps (`Terrain.has_sea`). Rivers, as downhill splines, come
  with paths.
- **Foliage** (`core/terrain/foliage_layer.gd`): trees, bushes and flowers
  are free-placed (not on the grid), painted with a brush, and drawn with
  MultiMesh. Plants keep their distance from each other, won't grow on
  floors or under water, and building over them clears them.
- The world outside your land has gentle hills, a pond and woodland,
  generated from a seed (`games/prison/starting_landscape.gd`). Your land
  starts flat.

### What this means for people (step 3)
Since paths are curves and the ground can slope, people won't walk on the
tile grid. They'll use Godot's navigation meshes, baked from floors, paths
and walkable terrain, with walls and objects as obstacles and doors as the
links between areas. The tile grid stays the authority for rooms and
building.

### Agreed order
Debug view and windows (done), then water bodies (done), then spline paths (outdoors,
sloping with the ground, steps where steep, bridges; floors also count as
paths, with one-way paths later), then storeys (manual floor heights,
stairs, ramps, staff-only lifts, basements), then people.

## Open questions
- Multi-storey buildings: when, and how do stairs work?
- Roofs: drawn automatically for now. Do you want to be able to choose
  roof styles?
- Undo: per action, or per drag?
