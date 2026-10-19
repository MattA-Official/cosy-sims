# Plan

Goal: a small playable prison prototype, then pull the shared parts into a
core that later games (hospital, airport, school, museum) can reuse. Built in
evening-sized chunks.

1. **Refresher and project setup.** Godot 4 project, repo, and a test scene:
   a grid floor with a Parkitect-style camera (pan, rotate, zoom). *Done.*
2. **Building.** Floors and walls on the grid (walls on cell edges, like The
   Sims), then doors and a few objects (bed, toilet, table). Rooms detected
   from enclosed walls and given a type such as cell or canteen. *Done.*
3. **People and needs.** Prisoners who walk around with pathfinding, two or
   three needs (hunger, sleep, hygiene) that send them to the right objects,
   and a simple daily schedule. This makes it a playable prototype.
   *Walking and needs done; the daily schedule is next.*
4. **Review and extract the core.** Note what is prison-specific and what is
   generic (camera, grid, building, agents, needs, schedules), then move the
   generic parts into `core/`.

Deliberately left until after step 4: money, guards and staff, events.

## Notes from step 2

- The building data (`core/building/`) went straight into the core, since
  floors, walls on edges, doors, objects and rooms are clearly the same in
  every game. What a cell or canteen needs lives in the prison catalogue.
- Objects and room types are `.tres` resources in
  `games/prison/catalogue/`, so they can be tweaked in the inspector.
- Not done yet: undo, saving and loading, multi-storey buildings, costs.
- After review, added per-object snapping, growable land, floor and wall
  styles (indoor and outdoor), and better demolition. Paths, roads and
  terrain are agreed to be off-grid; see `docs/design/building.md`.
- Terrain basics added before step 3: sculpting, a water level, plants,
  and buildings that flatten the ground. Next: spline paths and roads,
  then people on a navmesh.
