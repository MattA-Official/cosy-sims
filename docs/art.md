# Art: models and textures

The prison game's art lives in `games/prison/art/`. Everything is made from
code, so any shape or colour can be changed and rebuilt:

| Folder | What's in it |
| --- | --- |
| `art/src/models.py` | Every model, built with Blender's Python module and exported as `.glb` |
| `art/src/textures.py` | Every texture, painted with numpy |
| `art/models/` | The exported `.glb` files the game loads |
| `art/textures/` | The exported `.png` files the game loads |

`art/src/` has a `.gdignore`, so Godot doesn't try to import the scripts.

## The look

Matt's brief: simple, low-detail but smooth shapes, flat textures, and
colours a real prison would plausibly use.

- Chunky shapes with soft rounded edges; no small clutter.
- One palette shared by every model (`PALETTE` in `models.py`): slate-green
  paint for all metalwork (bed frames, table legs, doors, the lift), brushed
  steel for the toilet and shower fittings, a grey-blue blanket on white
  sheets, a blue vinyl mattress, pale beech laminate for table tops.
- Walls are cream painted blockwork over a sage dado, or red brick.
- Prisoners wear orange; skin and hair vary from person to person.
- No normal maps, no photo textures.

## What there is

- Objects: bed, toilet, sink, shower, table (canteen), lift, tv, radio, bookshelf, wall_shelf, poster, rug, plant_pot, bench,
  weights_bench, basketball_hoop.
- Jobs: cooker, fridge, serving_counter, washing_machine, ironing_board,
  laundry_basket, clothes_shelf, workbench, storage_shelf, table_trolley,
  bin, skip (outdoor), coffee_machine, reception_desk (2 x 1 counter, staff side at
  the back).
- Carried items (about 0.4 m, origin at the middle of the bottom):
  food_crate, meal_tray, dirty_laundry, clean_laundry, rubbish_bag,
  wooden_toy, birdhouse. Floor litter: litter_paper, litter_can,
  litter_wrapper.
- Security: cctv_camera (0.5 x 0.5, 2.2 m post, lens along +z).
- Memorial: memorial_plaque (0.5 x 0.25, 0.5 m stone stand, brass plate facing +z).
- Reform and release: class_desk (1 x 0.5, top 0.5, sitter at +z), whiteboard
  (1.5 x 0.25, 1.1 m, writing at +z), armchair (0.75 x 0.75, seat 0.3),
  postcard_board (1 x 0.1 on the wall, 0.6 to 1.2 m up; cards are meshes
  `card_1` to `card_6`), phone (0.4 x 0.2 wall payphone, 0.9 m).
- Contraband items (same size and origin as other items): biscuit, spoon,
  rolling_pin, frying_pan, screwdriver, mallet, soap_sock.
- Infirmary: infirmary_bed (1 x 2, head to the front like the cell bed;
  people lie in it), medicine_cabinet (1 x 1, 1.4 m, back to the wall).
- Effects: dust_cloud (about 1.3 m across, origin on the ground), for
  fights.
- Vehicles: lorry (2 x 5 tiles, cab towards Godot's +z), bus (4 x 1.6 m,
  front towards Godot's +x, doors on its -z side), car (1 x 2 tiles, front
  towards +z; looks car_red, car_blue, car_cream).
- Roads: tunnel_portal (stone mouth round a 3.6 x 2.2 m opening in a 7 m
  grassy bank running 6 m back; origin at the middle of the road at the
  mouth, facing +z; dark inside so vehicles vanish), used as
  `Tunnels.model`. Texture `path_tarmac` (no markings; the game draws
  them).
- Roadside: bus_stop (1 x 0.5, sign and shelter, front towards the road
  at +z).
- Floors also include floor_car_park: tarmac with a white bay line on one
  x edge of each tile, so every tile is one bay.
- Doors: door (in use), cell_door (barred, not used yet), security_gate
  (all bars, for a door kind), people_gate (chain link, for the perimeter
  fence), vehicle_gate (sliding, with hazard stripes and a no-entry sign),
  metal_detector (walk-through arch, green light on top).
- People: person. Plants: tree, bush, flower.
- Icons (`core/ui/icons/`): mood_beaming, mood_content, mood_fed_up,
  mood_angry, in the same white line style as the rest. Markers
  (`core/ui/markers/`): broken (a spanner with a puff of smoke).

The poster and wall shelf are wall-hung: their footprint is on the floor
against the wall, and the model is raised (poster middle about 1 m up,
shelf top about 1.1 m).

## Surfaces, chairs and small things

Tables and desks are plain surfaces: chairs and the things on them are
separate models, so the game can put them together (see "Flexible objects"
on the future features doc). Positions below are in Godot metres, in the
surface's own frame (front is +z, as for every object).

| Surface | Footprint | Top | Spots for small things | Chair sides |
| --- | --- | --- | --- | --- |
| `games_table` | 1 x 1 | 0.725 | four at (±0.2, ±0.2), or one board in the middle | front and back at z ±0.65, also x ±0.65 |
| `desk` (cell desk, against a wall) | 1 x 0.5 | 0.53 | two at x ±0.25, z 0 | front, z +0.5 |
| `office_desk` | 1.5 x 0.75 | 0.53 | three at x -0.5, 0, +0.5, z -0.05 | front, z +0.6 |
| `guard_desk` (office desk at the back of 1.5 x 1) | 1.5 x 1 | 0.53 | three at x -0.5, 0, +0.5, z -0.17 | front, z +0.3 |

- **Looks**: each surface also comes as `<name>_pine`, `<name>_metal` and
  `<name>_painted`, the same shape and size, so one definition can pick
  any of them.
- **Chairs** (0.5 x 0.5, seat top 0.32, the sitter faces +z, so turn a
  chair half round to face a table from its front): `chair` (painted
  metal), `chair_cushioned`, `chair_pine`, `office_chair` (swivel).
- **Small things** (origin at the middle of the bottom; the front faces
  +z, towards whoever sits at the front): `chess_board` (0.4 x 0.4),
  `cctv_monitor` (0.5 x 0.25, with keyboard), `radio`, and the warden's desk
  dressing `nameplate` (turn it to face visitors), `in_tray`,
  `desk_plant`, `mug`.

## Scale and orientation

- Tile 1 m, storey 1.75 m, walls 1.5 m tall and 0.15 m thick, doors
  1.15 m, people about 0.9 m.
- Each model's origin is the middle of its footprint on the floor, and its
  footprint matches its catalogue entry's `size` (x across, y deep).
- Objects face the camera's starting view (Blender's -Y, Godot's +Z), with
  their backs to the wall behind, so their build-menu pictures show the
  front. People face Blender's +Y, which is the way the game walks them.
- Plants are built at size 1; `FoliageDef.size` scales them.

## How the game uses them

- **Objects**: `ObjectDef.model`. Without a model an object is a box of
  its `height` and `colour`, so a new object can be tried out before it has
  a model.
- **Doors**: `BuildingView.door_model` (set from
  `PrisonCatalogue.DOOR_MODEL`), scaled to fill the one-metre doorway.
  Cut-away walls still draw doors as a low slab of `door_colour`.
- **People**: `People.body_model` (from `PrisonCatalogue.PERSON_MODEL`).
  Meshes named `outfit`, `skin` and `hair` are tinted: the outfit by
  `People.body_colour`, skin and hair picked per person from
  `People.skin_tones` and `People.hair_colours`.
- **Poses**: `core/people/person_poses.gd` lies people in bed, sits them
  at tables, on toilets and on benches (their `*_legs` meshes swing
  forward from the hips) and stands them in showers, by the object's tag.
  `PersonPoses.carry()` swings the `*_arms` meshes forward from the
  shoulders; `ItemView` calls it while someone holds an item, which sits on
  their hands at `ItemView.HELD_AT`.
  Meshes named `*_<group>` or `*_<role>` only show on people in that
  group or with that role: the staff badge (`gold_staff`), the guard's
  peaked cap (`navy_guard`), the warden's banded cap and tie
  (`navy_warden`, `gold_warden`), the cook's hat (`sheet_cook`), the
  teacher's cardigan (`knit_teacher`, `cream_teacher`) and the
  counsellor's scarf (`scarf_counsellor`).
- **Plants**: `FoliageDef.model`. A mesh named `trunk` takes
  `trunk_colour`; ones named `canopy` or `bloom` take `colour`; the rest
  (flower stems) keep their own colour. So the round tree and the blossom
  tree share one model.
- **Floors and walls**: `FloorDef.texture` and `WallDef.texture`. Walls
  can also have a dado (`dado_colour`, `dado_height`). A see-through wall
  whose texture has see-through parts (`chain_link.png`, the perimeter
  fence) is drawn as a cut-out mesh panel between posts; one without is
  drawn as rails. The perimeter wall uses `wall_concrete_panels.png`.
- **Paths**: `PathView.texture`, one grit texture for every style.
- **Ground**: the `detail` texture on the ground shader
  (`core/grid/grid_ground.gdshader`), repeating every `detail_scale` metres.

Textures are near-white greyscale covering exactly one metre. The game
multiplies them by the style's own colour, so colours stay in the
catalogue `.tres` files and one texture can serve many colours. Generated
geometry gets texture coordinates in metres from
`MeshShapes.uv_for()`, which maps upright faces along their own direction,
so blocks stay level on walls at any angle.

The parts of a model that share a material are joined into one mesh named
after the material, so each model is only a few draw calls.

## Rebuilding

```
pip install bpy numpy pillow                 # Blender as a Python module
cd games/prison/art/src
python3 textures.py ../textures              # every texture
python3 models.py ../models                  # every model
python3 models.py ../models bed lift         # just these
python3 models.py /tmp lineup                # a picture of every model
```

Then open the project in Godot (or run `godot --headless --import`) to
import them. New textures need mipmaps: in the Import dock tick
**Mipmaps > Generate** (or set `mipmaps/generate=true` in the `.import`
file) and reimport.

To see the result in the game, `tools/art_shot.gd` saves a close-up with
the HUD hidden:

```
godot --path . --rendering-driver vulkan -s res://tools/art_shot.gd -- out.png 44 47 9 45 40
```

The numbers are the tile to look at (x, z), the camera distance, its turn
and its tilt. Add `sample=N` for another sample prison, or `hud` to keep
the HUD.

## Adding something new

1. Add a function to `models.py` that builds it from the `Prop` shapes
   (`box`, `cyl`, `ball`, `capsule`, `tube`), using `PALETTE` materials,
   and add it to `MODELS`.
2. Export it and point its catalogue entry's `model` at the `.glb`.
3. Check it in the line-up and in the game.

The Art assets thread in the project makes new models and textures on
request: say what it is, its footprint in tiles, and anything it must do
(a part the game recolours, a side that goes against a wall).
