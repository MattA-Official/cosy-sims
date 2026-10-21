# Cosy Sims

A series of small, cute management sims that share one look and one set of
familiar mechanics. First up is a prison game, drawing on Prison Architect for
its systems, Parkitect for its camera and style, and The Sims / Software Inc.
for flexible building. Later games might include a hospital, an airport, a
school and a museum.

![The sample prison on its plot, with hills, woods and a pond around it](docs/images/terrain.png)

The models and textures are made in code (see [docs/art.md](docs/art.md)).
Built with [Godot 4.7](https://godotengine.org/).

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
| 2 Wall | Drag from corner to corner to build or restyle; snaps straight or to 45°, or pick Any angle (or hold Alt); hold Ctrl to remove. Paint mode: click or drag along walls to paint the side you can see; Shift-click paints every wall round the room; Ctrl takes paint off |
| 3 Floor | Drag to lay or restyle floor on the side of any walls where you start; Shift-click floors or restyles the whole room; hold Ctrl to remove. Stairs: click the foot, move the way they climb, click short of the top for a landing, at the top to build; choose square or rounded landings |
| 4 Doors and windows | Pick a door, staff door, glass window or barred window, then click a wall; click it again to fill it in. A door can't join floors more than a step apart (see Door Steps below) |
| 5 Objects | Click to place; R turns by 45° and [ / ] change the step (90° down to 1°); hold F to pin it and turn it to face the mouse; hold Alt to place freely; V changes its look (pine, metal, painted and so on, or Mixed). Small things such as a chess board or a monitor go on a table, desk or counter top, and chairs face the nearest table. Lifts link with a lift in the same spot upstairs |
| 6 Room type | Click a room to mark it as a cell, canteen and so on |
| 7 Paths | Pick a path or road style. Straight: click each end. Curved: click the start, a bend and the end. Freehand: drag. Points snap to the middle of tiles (bends don't); hold Alt to swap that for one point, or turn Snap to grid off. Page Up / Down while placing builds stairs, a ramp or a bridge and raises its far end. Esc stops; Ctrl-click removes a path |
| 8 Plants | Hold to plant trees, bushes or flowers; hold Ctrl to clear them. The Size slider goes down to Single, which places one plant per click; Density spaces them out |
| 9 Terrain | Hold to raise, lower, flatten or smooth the ground, with sliders for size and strength; or add water to a hollow, or drain a pond. **Buy land** shows the plots for sale next to your land: click one to buy it, ticking **Flatten when bought** to level it with your land for a fee |
| 0 Demolish | Click an object or wall to remove it, or drag to clear an area |
| Z Zones | Rooms tint by who may be in them. Pick a zone (Prisoners and staff, Staff only, Visitors and staff, Everyone) and click a room to paint it, or pick Room type's to go back to its default. Click a door to lock or unlock it until the block changes; Shift-click to pin it that way |
| X Patrol routes | Click points to draw a loop for guards to walk; click the first point or press Enter to close it, Esc to stop. Ctrl-click a route to remove it. Put guards on it in the Staff window |
| [ / ] | Brush size, for terrain and plants |
| Tab | Loops through the wall views: Walls up; Cutaway (walls in front of rooms drop, following the camera round); Walls down; Roofs on (every level with its roofs, as from outside) |
| Ctrl+Z / Ctrl+Y | Undo or redo building and landscaping (Ctrl+Shift+Z redoes too) |
| Esc | Put the tool away |
| F1 | The controls card |
| F3 | Debug view: rooms tinted and labelled, and details of the tile under the mouse. With no build tool (Esc), click a person, object, room or tile to inspect it: set a person's needs, send them somewhere, add or remove prisoners, pause everyone |

| Time | |
| --- | --- |
| Space | Pause, or carry on. Building works while paused |
| , / . | Slower or faster: 1×, 2× or 4× |
| T | The timetable |
| P | Staff and work programmes |
| M | Money: the balance, today's and yesterday's lines, and Sandbox |
| O | The warden's office: intake, grant goals, the grade and the daily report |
| K | Security: cameras, guards, the perimeter, today's incidents, sit-ins and alerts |
| F2 | Save and load: three slots and the morning autosave |

Hover any button in the build menu to see what it is. The room, floor and
wall tools let you pick a style from the picture tiles above the toolbar;
the Room tool shows each floor and wall pairing as a little cut-away room.
The level, wall view (Tab), controls card (F1) and debug view (F3) also have
buttons in the top-right corner. See [docs/ui.md](docs/ui.md) for how the UI
is put together. Fences, hedges, paving and lawn are outdoor styles: a room enclosed
by walls is indoors, but one bounded by a fence stays outdoors. Rooms are
worked out from the walls automatically. Once a room has a type, a label
floats over it saying what it still needs, such as a toilet. Labels that
would overlap on screen are hidden, keeping the ones about problems. A
door whose floors have drifted too far apart gets a label saying nobody
can use it.

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
next to it, or else with the average height of the ground under it
(rounded to a quarter of a metre). The ground is fitted underneath so it
never shows through, and eased into a gentle bank round the building.
Higher floors stand on foundations. Upstairs and in basements, a grid
shows at that floor's height.

Indoor rooms get flat roofs at the top of their walls, wherever there is
no floor above. You see them when you go up a floor, or with Tab's Roofs
on view.

Split levels (floors nudged up or down within a storey, with ramps
between them) are switched off for now. Tick **Split Levels** on the Main
node in Godot's inspector to bring back the floor tool's Raise, Lower and
Ramp modes. Likewise, tick **Door Steps** to let a door join floors up to
a metre apart, with a few steps built on the low side; with it off, such
doors are refused.

Prisoners walk the build: through doors, up stairs and lifts, along paths
and over bridges. They get sleepy, hungry and grubby, and head off to a
free bed, table or shower when they need one; otherwise they wander.
Press F3 and click someone to see what they're up to.

### The daily routine

At normal speed a game minute lasts a real second, so a game day takes 24
minutes (6 at 4×). The clock in the top-left corner shows the time, the
day and the block everyone is in. Prisoners follow a timetable of
one-hour blocks:

| Time | Block | Prisoners go |
| --- | --- | --- |
| 22:00 to 07:00 | Sleep | To bed in their own cell, door locked |
| 07:00, 12:00, 17:00 | Eat | To the canteen; meals only happen now |
| 08:00 | Shower | To the shower room, then free once washed |
| 09:00 to 12:00, 15:00 to 17:00 | Work | Free time until jobs arrive |
| 13:00 to 15:00 | Yard | Out to the yard |
| 18:00 to 20:00 | Free time | Anywhere, as their needs ask |
| 20:00 to 22:00 | Lockup | Locked in their own cell |

Press T (or the calendar button) to change it: pick a block and click or
drag across the hours. Each prisoner gets a bed of their own in a cell,
and the cell's door locks for Lockup and Sleep once everyone who sleeps
there is inside; a little lamp over the door shows red when it is locked.
Anyone not where the block wants them 15 minutes in gets a "?" over their
head, and the F3 inspector says why (no bed, can't reach the canteen).
**Separate timetable for…** in the timetable window gives a security
category its own timetable, starting as a copy of everyone's (say, high
security in the yard an hour later so they never mix); pick which one to
paint from the menu, and **Merge back** puts them on everyone's again.
Meals are still cooked by everyone's timetable. Categories also change how
quickly temper builds (low 0.8×, high 1.2×), how often random searches
pick their cell (low ½, high 3×) and how far off a guard spots them out of
place (high 5 tiles, others 3). Low-security prisoners sharing a room with
high-security ones feel uneasy. To keep them apart, the Zones tool has a
**High security wing** (staff and high security prisoners only) and a
**Low and medium wing**; prisoners only get beds in cells they're allowed
in, and moving category hands beds out again.
With F3 you can also jump the clock to any hour. The sun follows the
clock, from dawn about 06:00 to dusk about 20:00; the sun button keeps it
day while you build.

### Needs and mood

Prisoners have seven needs: sleep, hunger, hygiene, bladder, recreation,
fresh air and company. The first five send them to objects (a toilet,
a TV, a bookshelf, the weights); fresh air comes from being outdoors and
company from being near someone in the same room. The block decides what
is allowed, so recreation waits for the yard or free time, but a need
that is nearly empty will break the rules (and borrow a neighbour's
toilet if it must).

Mood is 50 plus a little for each well-met need, minus more for each low
one, plus the rooms they sleep and spend time in, plus moodlets such as
"Had a good meal" or "Woken too early". It shows as a face over anyone
fed up or angry, and the F3 inspector lists the biggest reasons under
"Why?". Each prisoner has two traits (Night owl, Bookworm, Hothead and
so on) that change how fast needs run down, what they like doing and
how they take things.

Rooms get a quality score from -10 to +10: space per bed, windows, decor
(rugs, posters, plants), and nicer floors and walls. A dorm sleeps four
or more but costs a little mood for the lack of privacy.

### Zones and doors

Every room has a zone saying who may be in it. Rooms start in their
type's zone, which for all of today's rooms is Prisoners and staff;
the Zones tool (Z) paints a different one on, such as Staff only for an
office. Ground outside any room is open to everyone. Staff doors let only
staff through, whatever the rooms either side allow, and show a blue plate
over them. Staff carry keys, so locked doors only stop prisoners (and
visitors, later).

Click a door with the Zones tool to lock or unlock it by hand: a padlock
shows over it, and it goes back to the timetable when the block changes.
Shift-click pins it that way (a red pin on the padlock) until you
Shift-click it again. Prisoners caught in a room they may not be in walk
out of it. In the F3 inspector, a room or tile can also take a member of
staff, who wanders, eats and chats where staff may go.

### Staff and jobs

Press P (or the people button by the clock) for the Staff window: + and −
set how many cooks, cleaners, handymen and guards work days (06:00 to
18:00) and nights (18:00 to 06:00), put guards on patrol routes, and put
prisoners on or off a work programme (kitchen, laundry, cleaning,
workshop). Staff arrive at the edge of the land early enough to walk in
before their shift, and go home when it ends. They come on the staff bus,
which drops them at the bus stop before each shift; staff going home walk
back to the stop to catch one. Without a road they walk in from the edge
of the land. Staff cars and car parks (pairs of car park tiles near the
road) are behind the **Staff Cars** setting on the Main node for now. Each is paid a wage as their shift starts, with nights
paying half as much again.

With Staff needs on (the default, in the Staff window), staff get
hungry, need the toilet and run low on energy over a shift; a coffee
machine in the staff room tops it up, and worn-out staff work slower.
Off, they simply work their shift.

Work is a board of jobs, each a list of stages: fetch something, deliver
it, or work at an object for a while. The morning lorry leaves crates of
food on a pallet to carry to the fridge. An hour before each meal the
cook takes a crate, cooks at the cooker and fills the serving counter;
prisoners take a tray to a table, and miss the meal if none are left.
People drop litter (messy ones more), cleaners sweep it to a bin and take
full bins to the skip. After a shower prisoners swap their uniform for a
clean one, and the dirty ones get washed, ironed and stacked back on the
shelves. In work blocks prisoners on the workshop programme make toys
and birdhouses that the lorry takes away to sell.

Guards sit at guard post desks, patrol where the prisoners are (or walk
a patrol route), and walk back any prisoner they spot out of place.
Security gates (a door kind in the Doors and windows tool) stay locked
to prisoners unless a guard is at a guard post desk nearby.

Toilets, showers, cookers, washing machines and TVs wear out with use
and break: nobody can use a broken one, a spanner floats over it, and
the handyman comes to mend it.

With F3 on, a jobs panel lists every open job (who is on it, or why it is
waiting), the stock of every item and anything that stops the kitchen or
laundry working and anything broken, and dotted lines show where each
worker is heading. Patrol routes show as dotted loops too.

### Money, the warden and new arrivals

You start with £20,000 (press M). Building costs money as you build and
gives three quarters back when you demolish (all of it if you undo).
Each midnight the prison is paid a grant for every prisoner, wages go out
as each shift starts, the lorry buys food and takes the workshop's goods
to sell, and each new prisoner brings a fee. Out of money, building and
hiring stop until the balance is back above zero. Tick **Sandbox** in the
Money window to build for free.

Every map has a road running along the inside of your land, with markings
and the ground smoothed under it, into a tunnel at each end; now and then
a car drives through. Each morning at 09:00 a bus drives
in to the bus stop (or the entrance), and the day's arrivals walk to
reception to be searched, then a guard walks them to a free bed. Nobody
comes without a reception or a free bed. Hire a warden and give them an
office with an office desk to choose how many come and which security
categories you accept (press O); they also unlock grant goals that pay
out when done and a report each morning. Each midnight the prison is
graded from one to five stars on safety, wellbeing, reform and money; a
better grade means a bigger grant.

Press F2 to save into one of three slots, or load one; the game also saves
itself each morning. A save keeps everyone in the middle of what they
were doing: walking somewhere, eating, at work.

More land is for sale in strips, as in Prison Architect: each runs the
whole length of one side of your land and 12 tiles out (the Terrain
tool's **Buy land**), so your land stays a rectangle. Flat, dry land costs
the most; hills and water make it cheaper. Tick **Flatten when bought** to
level the strip with your land along their shared edge, for a fee by how
much ground moves. A road running into the strip carries on to the new
edge. Buying land can't be undone.

### Trouble

Unhappy prisoners build up temper (shown in the inspector with what's
mostly behind it). Once a game hour each may act on it, half as likely
with a guard within a few tiles. How far they go depends on how low their
mood is:

- **Grumbling** (mood under 45): "Grumble grumble" over their head, and
  they slow down for a while. No record.
- **Mischief** (under 30): they skive off the timetable for an hour,
  wandering about and dropping litter. Guards who spot them walk them back.
- **Vandalism** (under 20): they break the nearest breakable object (TV,
  toilet, shower...), which then needs mending. People who see it feel a
  bit worse.

The worse two warn first ("Up to something", "Fuming!"); a guard turning up
or their mood lifting calls it off. Offences go on their record in the
inspector with the reason, such as "broke the toilet in the cell (hungry)".
Hotheads boil over faster, gentle souls slower; light-fingered prisoners
lean towards mischief. Acting on it lets off steam.

**Contraband.** Prisoners tempted to mischief (or light-fingered ones) may
pocket something when they finish with an object and no staff are within
3 tiles: a spoon from a canteen table, a biscuit from the serving counter,
a rolling pin or frying pan from the cooker, a screwdriver or mallet from
the workbench, a sock full of soap from the shower. Back in their cell they
hide it in whatever hides things best (toilet, then bed, bookshelf, bin).
Biscuits get eaten when they're feeling low. You never see a stash until
it's found.

**Searches.** In the inspector, a prisoner has **Search them** (a guard
stops them and pats them down, finding everything on them) and **Search
their cell** (a guard turns it over for 8 minutes; well-hidden stashes are
found less often, messy cells more). Guards also search two random cells a
day. Anything found is taken away and goes on the owner's record, and
being searched puts people out (tidy prisoners most).

**Tools, trading and metal detectors.** Kitchens and workshops count their
tools at each shift change (06:00 and 18:00): a rolling pin or screwdriver
taken since raises a "missing" alert. Biscuits are money: in free time or
the yard a prisoner spoiling for trouble (fuming, or a hothead) may buy a
weapon from someone in the same room, out of sight of staff, at its
biscuit price. A **Metal detector** (Doors, with the gates) is an open
doorway that beeps at a prisoner carrying a spoon, frying pan or
screwdriver, and a guard comes to search them. **Shakedown tonight** in
the Security window has guards search every cell at the next Lockup,
finding stashes but putting everyone in a temper.

**Fights.** Below mood 15 a prisoner may square up ("Spoiling for a
fight!") and then pick on the unhappiest prisoner within 3 tiles. A dust
cloud with stars and bonks appears; everyone in it lands a blow each
minute, harder with a weapon from their pocket. Hotheads close by may pile
in (up to 4); gentle souls often walk off. Fights last 4 minutes, 2 if
armed, or until a guard arrives to break them up (a guard breaking up an
armed fight takes a knock). Everyone who sees one feels worse, more so if
weapons came out.

**Health and the infirmary.** Health runs from 100: bruised (above 70, no
effect), hurt (above 40, they limp) and knocked out (flat on the floor
seeing stars). Build an **Infirmary** (an infirmary bed and a medicine
cabinet) and hire a **Nurse** in the staff window. The hurt limp to a free
bed and lie down; a guard or the nurse carries the knocked out there. In
bed they mend slowly, and a nurse's visit mends them quickly; they get up
at 90. Without an infirmary the hurt mend slowly as they go and the knocked
out come round after an hour. Nobody dies, unless you tick **Deaths
(rare)** in the Security window: then someone knocked out and left lying,
or beaten right down, can die. A little ghost floats up, a plaque marks
the spot, and it counts 20 against Safety.

**Consequences.** Each offence scores points (grumbling 0, mischief 1,
contraband or vandalism 2, a fight 3) that fade by one a day. The first
minor one is a warning; after that they lose a privilege (the yard, which
becomes lockup for them; the telly and radio; games and the gym), two once
it reaches 4 points. A fight means a day in a **Quiet room** (mark a small
room with a bed and a toilet as one): a guard walks them there and they
stay put, meals passed in, and come out calm. Over 8 points at midnight
moves them up a security category; a clean week moves them down. In the
inspector you can **Send to the quiet room** or **Let them off**. The
warden's office has the policies: random cell searches (none, 2 or 5 a
day), how long privileges are lost for (1, 2 or 4 days) and whether fights
mean the quiet room.

**Perimeter.** The Wall tool has a **Perimeter fence** (see-through, can
be cut) and a **Perimeter wall**. Ground they enclose is secure; the Zones
tool tints open ground green inside the perimeter and orange outside. A
**People gate** in the perimeter opens for prisoners only while a guard
sits at a guard post nearby, like a security gate; a **Vehicle gate** lets
staff through but never prisoners. Any gate counts as shut for working out
what's secure.

**Escapes.** Before there's a perimeter, any prisoner out of place (skiving
off, say) may simply walk off your land, and the bus warns you. Once
there's a perimeter, ground outside it is out of bounds: a prisoner there
is out of place and gets walked back. A prisoner out of
place who can walk to the edge of your land without crossing the perimeter
may make a run for it ("Legging it!"), likelier when unhappy. The nearest
two guards give chase, a little faster than a prisoner runs. Caught, it's
an escape attempt on their record and a day in the quiet room; reach the
edge and they're gone, with a £2,000 fine.

**CCTV and the Security window.** Guards see the room they're in; a **CCTV
camera** (Objects) sees 8 tiles in a quarter-circle in front of it, but only
while a guard sits at a **CCTV monitor** (a monitor on a guard desk is
watched by whoever mans the post; one on its own gets a guard of its own).
What was seen fades over half an hour, and prisoners don't act up where
they've been seen lately. The patrol route tool, or **Show what's being
watched** in the **Security** window (K, or the shield in the clock bar),
tints it blue. The window also lists cameras, guards on duty, the
perimeter, today's incidents and searches, anyone at large, and the latest
alerts; click an alert to look there.

**Sit-ins.** Once an hour, if a room holds 6 or more prisoners and most
of them (60%) are very unhappy (mood under 25) about the same thing, they
sit down on the floor with placards ("Proper dinners!") and won't budge.
Unhappy prisoners who wander in may join; gentle souls don't, and put
others off. Fix what they're upset about and they stand up within ten
minutes; or press **Talk them round** (Security window, or the inspector)
and a guard hears them out for 20 minutes (the warden takes 10), which
leaves them feeling listened to. Left six hours, the angriest two come to
blows. Each hour of a sit-in counts against Safety, and it goes on the
sitters' records.

**Safety.** Each midnight Safety is graded on the day's incidents, weighted
(walked back 0.2, contraband found 0.5, vandalism or a fight 1, someone
knocked out 3, an escape attempt 10, each hour of a sit-in 1) and counted per 10 prisoners: 0.2 or
less is five stars, then 0.5, 1 and 2, and worse is one star. The morning
report lists yesterday's incidents.

### Sample prisons

Pick a sample with **Sample** on the Main node, or press F3 and choose one
at the bottom of the inspector panel. Each one tests a different part of
how prisoners find their way:

| Sample | What it tests |
| --- | --- |
| Starter block | Doors, a corridor and a fenced yard on flat ground |
| Two storeys | Cells upstairs, canteen and showers downstairs, joined by stairs and a lift |
| Hillside | Terraces too steep to climb, joined only by path stairs and a long ramp |
| Island | Cells on an island in a moat, with one bridge |
| Long way round | A corridor that doubles back, and showers behind an angled wall with a door |
| Basement | Canteen and showers in the basement, down stairs with a landing |
| Crowded canteen | 24 prisoners in a dorm with too few beds, toilets and showers: a stress test for mood |
| Locked out | Showers with no door, and a raised canteen that needs Door Steps |
| Staff wing | A staff room behind a staff door, and an office zoned staff only |
| Working prison | The staff wing with a kitchen, laundry and workshop, three staff and prisoners on work programmes |
| Guarded prison | The working prison with a guard post (with a CCTV monitor for a camera in the canteen) and a security gate to the yard, two guards by day and one by night |
| Paying prison | The guarded prison with a warden in an office, a reception and a bus stop on the road (and a car park with Staff Cars on) |

See [docs/design/building.md](docs/design/building.md) for the design
decisions behind all this.

## Layout

| Path | What |
| --- | --- |
| `core/` | Parts every game will share: camera, grid, input, building, terrain, paths, people. Kept free of prison-specific code. New simulation (the clock, timetables) goes in `core/sim/`. |
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
