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

- Objects: bed, toilet, sink, shower, table (canteen), games_table, desk,
  lift, tv, radio, bookshelf, wall_shelf, poster, rug, plant_pot, bench,
  weights_bench, basketball_hoop.
- Jobs: cooker, fridge, serving_counter, washing_machine, ironing_board,
  laundry_basket, clothes_shelf, workbench, storage_shelf, table_trolley,
  bin, skip (outdoor).
- Carried items (about 0.4 m, origin at the middle of the bottom):
  food_crate, meal_tray, dirty_laundry, clean_laundry, rubbish_bag,
  wooden_toy, birdhouse. Floor litter: litter_paper, litter_can,
  litter_wrapper.
- Vehicles: lorry (2 x 5 tiles, cab towards Godot's +z).
- Doors: door (in use), cell_door (barred, not used yet).
- People: person. Plants: tree, bush, flower.
- Icons (`core/ui/icons/`): mood_beaming, mood_content, mood_fed_up,
  mood_angry, in the same white line style as the rest.

The poster and wall shelf are wall-hung: their footprint is on the floor
against the wall, and the model is raised (poster middle about 1 m up,
shelf top about 1.1 m).

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
  Meshes named `*_<group>` (the staff cap and badge, `*_staff`) only show
  on people in that group.
- **Plants**: `FoliageDef.model`. A mesh named `trunk` takes
  `trunk_colour`; ones named `canopy` or `bloom` take `colour`; the rest
  (flower stems) keep their own colour. So the round tree and the blossom
  tree share one model.
- **Floors and walls**: `FloorDef.texture` and `WallDef.texture`. Walls
  can also have a dado (`dado_colour`, `dado_height`).
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
