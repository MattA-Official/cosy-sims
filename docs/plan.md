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
   *Done. The daily schedule is milestone M1 of the prison game plan: a
   game clock with speeds, a timetable of blocks (`core/sim/`), cell
   doors that lock at night, and needs that run per game hour. M2 added
   seven needs, traits, mood with moodlets and reasons, room quality and
   dorms (`core/sim/mood_model.gd`, `core/building/room_quality.gd`).
   M3 added zones (who may be in each room), staff doors, doors locked by
   hand and a walking graph set up per group (`core/people/access.gd`).
   M4 added items people carry (`core/items/`), a job board with fetch,
   deliver and work stages (`core/jobs/`), staff roles, work programmes
   and the Staff window, and the kitchen, cleaning, laundry and workshop
   (`games/prison/`). M5 added day and night shifts (`core/jobs/shifts.gd`),
   staff energy and the needs setting, guards with guard posts, security
   gates and patrol routes (`games/prison/guarding.gd`,
   `core/jobs/patrol_routes.gd`), and wear and repair
   (`core/jobs/wear.gd`). M6 added money (`core/money/`: a ledger,
   building costs, wages, grants), the bus and new arrivals through
   reception (`games/prison/intake.gd`), the warden's office with grant
   goals, a daily grade and report (`games/prison/office.gd`,
   `games/prison/standing.gd`), undo and saving
   (`core/save/undo_history.gd`, `games/prison/prison_save.gd`),
   flexible objects (chairs and small things on tables and desks, looks
   and staff dressing their own desk), roads with vehicles and car parks
   (`core/paths/roads.gd`, `core/paths/vehicles.gd`,
   `games/prison/car_park.gd`), and buying land
   (`core/building/land_plots.gd`).*
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

## Gate 1 review (20 October 2026)

Phase 1 (M1 to M3) is done: a day runs itself. Checked by running every
sample for three game days.

- **A day plays out on its own.** The starter block and the staff wing
  sit at a content mood (around 60) with no accidents. One bug turned up
  and is fixed: someone who stopped part way up the stairs could never
  find a way anywhere again, which caused most of the accidents in the
  older samples. Two storeys, Island, Long way round and Basement still
  sit fed up because they have no yard; they are path tests, so that is
  left as it is.
- **The one-way rule holds.** Nothing in `core/` refers to
  `games/prison/`. The only prison flavour left in core is `&"prisoner"`
  as the default group (on `Person`, `Schedule`, `ScheduleRunner` and
  `People.add_person`), which a later game can simply not use.
- **What lives where.** `core/sim/`: clock, timetable (`Schedule`,
  `ActivityDef`, `ScheduleRunner`), day and night, door lamps, the mood
  model, moodlets and traits. `core/people/`: needs, people and their
  decisions, groups, access and the walking graph. `core/building/`:
  room types, room quality, zones and door kinds. All prison content is
  `.tres` data in `games/prison/catalogue/`.
- **Debts to pay in Phase 2.**
  - `core/people/people.gd` is about 1,500 lines. Split it into deciding,
    mood, walking and bodies once the art thread's poses for people
    have landed, so the two don't collide.
  - Doors in angled walls can't be locked or made staff doors yet.
  - Staff only wander, eat and chat; their jobs, shifts and staff room
    come with M4 and M5.
