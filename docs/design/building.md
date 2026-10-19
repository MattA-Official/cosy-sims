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

### Paths and roads: curves that snap to the grid (built)
Paths and roads are **not** tile floors. They work like Cities: Skylines
2 (`core/paths/`), but snap to the grid like floors do:
- A `PathNetwork` of nodes and quadratic Bézier segments, each with a
  style (`PathStyleDef`: gravel, paving, road) and a width.
- The path tool has straight, curved (start, bend, end) and freehand
  modes. Each path carries on from the last until Esc. Ends snap to
  nodes, to the middle of segments (splitting them into a junction), to
  outside doors, and otherwise to the middle of a tile; a curve's bend
  point does not snap. Holding Alt while placing a point swaps that for
  the one point, and the toolbar turns the grid off altogether.
- Paths may cross but not run along or over each other. A crossing at
  about the same height makes a new junction; one at least 1 m above
  another passes over it. Where paths meet, the inside corners between
  them are filled with a smooth curve and the outside of a bend is
  rounded off (no more round pads). A curve that crosses the same path
  twice makes two junctions. An end dropped partway along another path
  only joins it at about its own height, so a ground path ending under a
  bridge stays on the ground rather than joining the bridge in mid-air.
- Ground paths follow the land and that is all: too steep (over 0.35
  rise per tile) or through water and they cannot be built, and the hint
  says so. Stairs, ramps and bridges are a choice: Page Up or Down while
  placing makes the stretch built, running straight from one end's height
  to the other's. The first press keeps the far end on the ground; more
  presses raise it a step (0.25 m) at a time, and Page Down undoes them.
  A built stretch steeper than a ground path may be is stairs, with steps
  the same 0.25 m as stairs indoors spread evenly along it; a gentle one
  is a ramp, and a bridge on piers where it is well off the ground or over
  water (at least 0.15 m above it). Ends off the ground keep their height,
  so a walkway can carry on from one.
- Paths are outdoor-only, stay on owned land, and can't cross floors
  except right by their ends (to reach a door). Building over a path
  removes it. Grid floors stay for interiors and patios; floors will
  count as walkable paths when people arrive, with one-way paths later.
- Not yet: rivers as downhill splines, paths across land you don't own,
  and road markings at junctions.

### Terrain, water and foliage (basics built)
- **Terrain is a heightmap** (`core/terrain/terrain.gd`), one height per
  tile corner, that you sculpt with raise, lower, flatten and smooth
  brushes. You can only sculpt your own land, and the ground under
  buildings is locked.
- **Floors have their own height**, stored in `BuildingMap.floor_heights`
  rather than read from the terrain. New floor takes the height of any
  floor beside it, or else the average ground height under the whole
  drag, rounded to 0.25 m (so a room on a slope half sits in it rather
  than perching on its highest or lowest corner). The ground is then
  fitted to the floor: each corner drops to the lowest floor touching it,
  so it never pokes through, and higher floors stand on foundations. The
  ground for two tiles round the building is then eased towards the floor
  height (`BuildController.GROUND_SKIRT`), so a building on a hill sits
  in a gentle bank instead of a cliff or a trench; tiles already built on
  and land you don't own are left alone. You can't build where that
  height is under water.
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

### People and pathfinding (step 3, first slice built)
People walk on a graph rather than a baked navmesh (`core/people/`), so
it follows the build exactly and needs no baking:
- `NavGraph` is an A* graph (Godot's `AStar3D`) with a point for every
  floor piece on every level (angled walls included) and every tile of
  open ground on your land. Points join where people can step across:
  no wall or window between (doors are fine), no drop over a step, and
  gentle enough ground. Diagonals are allowed across whole tiles when
  both ways round are open. Objects block the pieces they cover.
- Stairs add a point per tile up the flight, lifts a point in each car
  (with a cost for the wait), and built paths points along their length,
  so they join levels and cross water and steep ground. Ground paths make
  the ground under them cheaper than bare grass, so people keep to them.
- Walks are smoothed: straight stretches with nothing in the way are
  taken in one go. The graph is rebuilt whenever the build or the paths
  change, and half a second after sculpting stops (rebuilding on every
  frame of the brush made it lag; the ground mesh is also built from
  packed arrays, and buildings only redraw when the brush is next to
  them). The open ground (heights, water, path costs and which
  neighbours are gentle enough) is kept between rebuilds as a
  `NavGraph.GroundLayer` and only worked out again when the terrain,
  water, paths or land change, so a building change rebuilds in about a
  third of the time (about 16 ms on the starter prison, down from 47).
  A truly incremental graph is left for when prisons get much bigger.
- People use an object from a tile inside its room, never through a
  wall from the other side.
- Needs (`NeedDef` resources: sleep, hunger, hygiene for the prison) run
  from 100 down. Below 40, people walk to the nearest free object that
  sees to the lowest need (bed, table, shower), claim it, use it until
  the need is met and carry on. With nothing pressing they wander, and a
  need that becomes pressing cuts the wander short. If nothing can be
  found or reached they say so and try again a little later.
- People are placeholder figures about 0.9 m tall, hidden above the level
  being looked at, like floors.
- The inspector (debug view, F3, with no build tool in hand): click a
  person, object, room or tile. People show what they are doing, where
  they are heading and their needs as sliders you can drag; you can
  rename them, send them somewhere, or remove them, and their route is
  drawn on the ground. Objects show who is using them and can be removed;
  rooms and tiles can have a prisoner added. People can be paused.
- **Sample prisons** (`games/prison/sample_prisons.gd`), picked with the
  Main node's Sample setting or from the bottom of the inspector panel
  (which reloads the scene). Each tests a different part of finding the
  way: Starter block (doors, corridor, yard), Two storeys (stairs and a
  lift), Hillside (terraces 2 m apart with banks too steep to climb, so
  only path stairs and a long ramp join them), Island (one bridge over a
  moat), Long way round (a corridor that doubles back, and a door in an
  angled wall), Basement (stairs turning at a landing), Crowded canteen
  (24 prisoners queueing for two tables and two showers) and Locked out
  (showers with no door, and a raised canteen that needs door steps).
  The tests load every sample and check who can reach a bed, a table and
  a shower.
- Next: the daily routine (lockup, meals, yard time) and more needs.

### Agreed order
Debug view and windows, water bodies, spline paths, storeys and angled
walls are done, and so is the first slice of people and pathfinding.

### Storeys (built)
- Fixed 1.75 m storeys, stepped through with Page Up and Page Down.
  Basements are storeys below ground. Above or below the ground, a grid
  (`core/building/level_grid.gd`) shows over your land at that level's
  height: on floors at their own height, and elsewhere on one flat sheet
  at the level's usual height.
- **Split levels are off for now** (Matt, 2026-10-19), to keep levels
  simple: every floor sits at its storey's height. The code is kept
  behind `Building.split_levels`, which you can turn on with the Split
  Levels box on the Main node in the inspector. With it on, each floor
  can be nudged up or down in quarter-metre steps within its storey
  (the floor tool's Raise and Lower modes), and ramps can be drawn
  between the heights.
- Scale is stylised like Prison Architect and Parkitect rather than
  real-world: a tile is 1 m but walls are 1.5 m, doors 1.15 m, and
  furniture is low and chunky. People will be about 0.9 m tall, so a
  quarter-metre split is a step they can take and anything taller needs a
  ramp or stairs.
- Getting between levels: drawn stairs, lift objects, and drawn ramps for
  split levels and odd heights. `Building.links()` lists every way between
  levels, ready for pathfinding.
- Stairs are drawn like the Sims 4 stair builder, with the floor tool's
  Stairs mode: click the foot, move the way they climb, click short of the
  top for a landing and carry on in any direction (round a corner, or back
  on themselves), and click at the top to build. Every staircase has the
  same steps: seven risers of 0.25 m make a storey, two treads to a tile,
  so there are always three tiles of steps plus any landings. Landings are
  square or rounded (a quarter circle round the inside of a turn, so a
  landing that turns back makes a half circle). Treads take the chosen
  floor style. Stairs cut a hole in the floor above over every tile they
  cover, and the floor can go back once they are removed. Nothing can be
  placed on stairs, no wall can cut across a flight, and demolishing any
  tile of them removes them. A stairwell stays part of the room around it.
- **Doors between floors at different heights** (Matt, 2026-10-19): a
  door can't join floors more than a step (0.25 m) apart; the door tool
  shows the wall in red and says how far apart they are. Behind a flag,
  `Building.door_steps` (the Door Steps box on the Main node), such a
  door instead gets a few steps on the low side, for gaps up to a metre:
  one riser per quarter metre, with the treads sharing the tile in front
  of the door. People climb them, and nothing can be placed on them.
  If the floors drift too far apart after a door goes in (say a floor is
  raised), the door stays but gets a label saying nobody can use it and
  how far apart the floors are.
- There is one kind of lift.
- Room and door labels never pile up on screen: where two would overlap,
  the one about a problem wins, then the bigger room.
- Upstairs walls reach down to the underside of the floor slab, so they
  look whole from a stairwell.
- Code layout: `GridGeometry` holds the pure cell, edge and angled-wall
  maths, and `BuildingMap` extends it; `PreviewShapes` collects and draws
  the build tools' see-through previews for `BuildController`.
- **Roofs** (Matt, 2026-10-19): flat and generated, never placed. Every
  piece of an indoor room with no floor on the level above gets a roof at
  the top of its walls; fenced (outdoor) rooms don't. Roofs show on the
  levels below the one you are building on, so going up a floor shows
  the building below roofed over. Pitched roofs and a roof tool are for
  later.
- **Wall views** (card 2026-10-19, "Sims style"): Tab loops Walls up,
  Cutaway, Walls down and Roofs on. Cutaway drops any wall with floor
  behind it as the camera looks, so you see into rooms while far walls
  stay up; it follows the camera in eighths of a turn. The view applies
  to the level being built on; levels below keep their walls up and
  their roofs on. Roofs on shows every level above ground, roofs and all. Lifts link with a lift in the same spot on
  the next level up.
- With split levels on, ramps are drawn with the floor tool's Ramp mode: drag over floor from the
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
- Floor is stored per tile with per-piece styles where a cut tile's sides
  differ, so each side of an angled wall can have its own floor. The floor
  tool only fills the side of any walls where a drag starts, and
  Shift-click floors or restyles everything walled in around the click
  (Matt, 2026-10-19). So a building can be drawn walls first, then floored
  with one click.
- Doors and windows stay 1 m wide in longer angled wall pieces, with plain
  wall either side.
- Objects turn to any angle: R turns by a step (45° by default, [ and ]
  pick 90° down to 1°), and holding F pins the object and turns it to face
  the mouse. Turned objects snap their middle to half or quarter tiles.
  Lifts stay square-on. Objects cannot straddle any wall.
- People and pathfinding will use the tile pieces too.
- Idea for later: curved walls, perhaps reusing the path curves.

## Open questions
- Roofs: drawn automatically for now. Do you want to be able to choose
  roof styles?
- Undo: per action, or per drag?
