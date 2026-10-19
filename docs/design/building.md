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

### Paths and roads: off the grid (built)
Paths and roads are **not** tile floors. They work like Cities: Skylines
2 (`core/paths/`):
- A `PathNetwork` of nodes and quadratic Bézier segments, each with a
  style (`PathStyleDef`: gravel, paving, road) and a width.
- The path tool has straight, curved (start, bend, end) and freehand
  modes. Each path carries on from the last until Esc. Ends snap to
  nodes, to the middle of segments (splitting them into a junction) and to
  outside doors. Junctions and bends get a round pad.
- `PathProfile` fits a path to the land: gentle slopes follow the ground,
  stretches steeper than 0.35 rise per tile become steps, and stretches
  over water become bridges running straight from bank to bank, at least
  0.4 m above the water.
- Paths are outdoor-only, stay on owned land, and can't cross floors
  except right by their ends (to reach a door). Building over a path
  removes it. Grid floors stay for interiors and patios; floors will
  count as walkable paths when people arrive, with one-way paths later.
- Not yet: rivers as downhill splines, paths across land you don't own,
  and road junction shapes beyond round pads.

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
Debug view and windows, water bodies, spline paths, storeys and angled
walls are done. Next come people and pathfinding.

### Storeys (built)
- Fixed 1.75 m storeys, stepped through with Page Up and Page Down. Each
  floor can be nudged up or down in quarter-metre steps within its storey
  for split levels. Basements are storeys below ground.
- Scale is stylised like Prison Architect and Parkitect rather than
  real-world: a tile is 1 m but walls are 1.5 m, doors 1.15 m, and
  furniture is low and chunky. People will be about 0.9 m tall, so a
  quarter-metre split is a step they can take and anything taller needs a
  ramp or stairs.
- Getting between levels: ready-made stair and lift objects, plus drawn
  ramps for split levels and odd heights. Stairs are 1 by 3 tiles and
  climb one storey; they cut a hole in the floor above, and the floor can
  go back once they are removed. A stairwell stays part of the room around
  it. Lifts link with a lift in the same spot on the next level up; a
  staff lift makes the link staff only. `Building.links()` lists every way
  between levels, ready for pathfinding.
- Ramps are drawn with the floor tool's Ramp mode: drag over floor from the
  low side to the high side, and the ramp meets the floor just beyond each
  end. Nothing can be placed on a ramp, and nudging any of it flattens it
  back to tiles.

### Wall shapes (angled walls built)
- Walls run from tile corner to tile corner at any angle ("Corner to
  corner", chosen 2026-10-19). The wall tool snaps to straight or 45°
  lines; holding Alt allows any angle, such as 1:2 or 1:3.
- An angled wall is stored as pieces between the corners its line passes
  through exactly, so a 45° wall has one piece per tile and doors and
  windows go in one piece each.
- Tiles an angled wall crosses are cut into pieces along it. Rooms are
  worked out from pieces, so each side of a cut tile can belong to a
  different room. Floor stays per tile, but one piece of a cut tile can be
  taken up on its own (Ctrl-click with the floor tool) to trim floor
  outside an angled wall.
- Objects cannot straddle an angled wall. People and pathfinding will use
  the pieces too.
- Idea for later: curved walls, perhaps reusing the path curves.

## Open questions
- Multi-storey buildings: when, and how do stairs work?
- Roofs: drawn automatically for now. Do you want to be able to choose
  roof styles?
- Undo: per action, or per drag?
