"""Models for the prison game, built in code with Blender and exported as .glb.

Simple chunky shapes with soft rounded edges and plain standard-issue
colours (see /docs/art.md). Everything is at game scale: tile 1 m, walls
1.5 m tall, doors 1.15 m, people about 0.9 m. Each model's origin is the
middle of its footprint on the floor.

Parts that share a material are joined into one mesh named after the
material, so each model is a handful of draw calls, and the game can find
the parts it recolours (a person's outfit, a tree's canopy) by name.

Run from this folder (Blender as a Python module: pip install bpy):
    python3 models.py ../models           # every model
    python3 models.py ../models bed lift  # just these
    python3 models.py ../renders lineup   # a picture of them all

Blender is Z-up; the glTF exporter turns that into Godot's Y-up, so
Blender's -Y is Godot's +Z. Objects face -Y (towards the game's starting
camera, so their build-menu pictures show the front, with their backs to
the wall behind); people face +Y, which is where the game walks them.
"""
import math
import os
import random
import sys

import bpy  # noqa: E402  (must come before bmesh)
import bmesh
from mathutils import Euler, Matrix, Vector

WALL_H, WALL_T = 1.5, 0.15
DOOR_H = 1.15

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# ---------------------------------------------------------------- materials

def hexc(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)


_mats = {}


def mat(name, colour="#ffffff", rough=0.7, metal=0.0):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = hexc(colour)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    _mats[name] = m
    return m


# One palette for everything, so the props sit together.
PALETTE = dict(
    paint=("#7f9c99", 0.5, 0.1),        # all painted metal: frames, legs, door
    steel=("#c9c5bd", 0.35, 0.6),
    steel_dark=("#8f8b84", 0.5, 0.5),
    sheet=("#efece4", 0.9, 0),
    blanket=("#8496a8", 1.0, 0),
    mattress=("#6f8ea3", 0.5, 0),
    wood=("#d9b98f", 0.55, 0),          # pale beech laminate
    tiles=("#e4ebe9", 0.25, 0),
    rubber=("#4f5354", 0.8, 0),
    glass=("#cfe9f2", 0.05, 0),
    light=("#ffe9b0", 0.4, 0),
    screen=("#3d4a52", 0.15, 0),
    cream=("#e8e0cc", 0.6, 0),         # plastic: radio, board
    vinyl=("#5d7184", 0.5, 0),          # gym padding
    plates=("#45494b", 0.6, 0.2),
    ball=("#d98a4e", 0.7, 0),           # hoop and basketball
    rug=("#b9ae98", 1.0, 0),            # oatmeal wool
    rug_edge=("#8a9f8a", 1.0, 0),
    paper=("#f1ead8", 0.9, 0),
    poster_a=("#9fbcc8", 0.9, 0),       # poster sky
    poster_b=("#8cae84", 0.9, 0),       # poster hills
    poster_c=("#e9c27a", 0.9, 0),       # poster sun
    pot=("#c98f6b", 0.8, 0),            # terracotta
    leaf=("#5f9a52", 0.9, 0),
    book_a=("#8496a8", 0.8, 0),
    book_b=("#b5806a", 0.8, 0),
    book_c=("#9aab84", 0.8, 0),
    book_d=("#d8c79a", 0.8, 0),
    # Recoloured by the game: kept white-ish so a tint reads true.
    outfit=("#ffffff", 0.85, 0),
    skin=("#ffffff", 0.7, 0),
    hair=("#ffffff", 0.8, 0),
    shoes=("#3b3a3c", 0.7, 0),
    navy=("#3f5168", 0.7, 0),           # staff cap
    white=("#f1efe9", 0.45, 0),         # appliances
    crate=("#b98d5e", 0.8, 0),          # rough timber
    food_a=("#e6b961", 0.7, 0),         # potatoes, bread
    food_b=("#8fb86a", 0.7, 0),         # peas, greens
    food_c=("#c9714f", 0.7, 0),         # beans, sauce
    plastic=("#7fa3c4", 0.6, 0),        # laundry basket
    uniform=("#e8894a", 0.9, 0),        # folded prison orange
    skip=("#d6a64a", 0.6, 0.1),
    bag=("#3b3d40", 0.35, 0),
    lorry=("#f2efe6", 0.5, 0),
    stripe=("#8aa98a", 0.6, 0),
    blue_stripe=("#7d93ad", 0.6, 0),
    pine=("#e2b47a", 0.6, 0),           # solid pine furniture
    painted=("#b9c7b4", 0.5, 0),        # painted wooden furniture, soft sage
    cushion=("#8a9bb5", 0.85, 0),       # chair cushions
    coffee=("#6b4a36", 0.3, 0),
    car_red=("#c4685a", 0.4, 0.05),     # staff cars: muted, a bit chalky
    car_blue=("#6f8fb0", 0.4, 0.05),
    car_cream=("#e8dcc0", 0.4, 0.05),
    sign_blue=("#4d6f9c", 0.5, 0),
    grass=("#66a14c", 0.95, 0),         # matches the ground shader's grass
    stone=("#a8a196", 0.9, 0),          # tunnel portal
    stone_dark=("#8d867b", 0.9, 0),
    dark=("#151517", 1.0, 0),           # inside a tunnel
    biscuit=("#d9a45f", 0.8, 0),
    hospital=("#eef2f2", 0.5, 0),       # infirmary white
    cross=("#5fa86f", 0.6, 0),          # first-aid green
    dust=("#efe8da", 1.0, 0),
    galv=("#a3a9ad", 0.45, 0.4),        # galvanised fence wire and posts
    hazard=("#e2b13c", 0.6, 0),         # warning yellow
    gold=("#e0b65a", 0.35, 0.6),        # staff badge
    fabric=("#93a48f", 1.0, 0),         # counselling armchair, soft sage
    cork=("#c8a275", 1.0, 0),
    soil=("#6e5644", 1.0, 0),
    rope=("#cdb58a", 1.0, 0),
    walnut=("#7a5638", 0.45, 0),        # piano and dark wood
    fur_ginger=("#d6915a", 1.0, 0),
    fur_rabbit=("#a8978a", 1.0, 0),
    fur_dog=("#dcb47c", 1.0, 0),
    budgie=("#86c06a", 0.7, 0),
    pop=("#a9cf8f", 0.25, 0),           # cloudy green home-brew
    trunk_dark=("#6b5240", 0.9, 0),     # fruit stalks
    knit=("#bf9a66", 1.0, 0),           # teacher's cardigan, camel
    scarf=("#b06f5c", 1.0, 0),          # counsellor's scarf, muted rust
    trunk=("#ffffff", 0.9, 0),
    canopy=("#ffffff", 0.9, 0),
    stem=("#5d8f4a", 0.9, 0),
    bloom=("#ffffff", 0.8, 0),
)


def M(name):
    colour, rough, metal = PALETTE[name]
    return mat(name, colour, rough, metal)


# ---------------------------------------------------------------- geometry

def _bevel(bm, width, segs):
    if width <= 0:
        return
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(30)]
    bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segs, profile=0.5,
                    affect="EDGES", clamp_overlap=True)


def _xf(loc, rot):
    return Matrix.Translation(loc) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()


def _fillet(pts, radius, steps=6):
    if radius <= 0 or len(pts) < 3:
        return pts
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        p, a, b = pts[i], pts[i - 1], pts[i + 1]
        d1, d2 = (p - a), (b - p)
        r = min(radius, d1.length * 0.45, d2.length * 0.45)
        s, e = p - d1.normalized() * r, p + d2.normalized() * r
        for k in range(steps + 1):
            t = k / steps
            out.append(s * (1 - t) ** 2 + p * 2 * t * (1 - t) + e * t * t)
    out.append(pts[-1])
    return out


class Prop:
    """Shapes built around one origin; parts with the same material are
    joined into one mesh named after it. Parts added while `group` is set
    are kept apart as material_group, pivoting about `pivots[group]`, so
    the game can move them (a person's legs)."""

    def __init__(self, name, turn=0):
        self.name = name
        self.turn = turn  # degrees about z, baked in when built
        self.parts = {}  # (material, group) -> [bmesh]
        self.group = None
        self.pivots = {}
        self.plain = set()  # groups whose mesh is named just the group

    def add(self, material, bm, bevel=0.0, segs=3, xf=Matrix()):
        _bevel(bm, bevel, segs)
        bm.transform(xf)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        self.parts.setdefault((material, self.group), []).append(bm)

    def box(self, material, size, loc, bevel=0.02, segs=3, rot=(0, 0, 0)):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bm.transform(Matrix.Diagonal((*size, 1)))
        self.add(material, bm, bevel, segs, _xf(loc, rot))

    def taper(self, material, bottom, top, height, loc, bevel=0.02, segs=2):
        """A box narrower at the bottom than the top (or the other way):
        `bottom` and `top` are (x, y) sizes."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            size = top if v.co.z > 0 else bottom
            v.co.x *= size[0]
            v.co.y *= size[1]
            v.co.z *= height
        self.add(material, bm, bevel, segs, _xf(loc, (0, 0, 0)))

    def prism(self, material, outline, depth, y=0.0, bevel=0.02, segs=1):
        """A flat shape in the x-z plane (`outline` as (x, z) points, any
        shape without holes), `depth` thick from `y` towards +y."""
        bm = bmesh.new()
        verts = [bm.verts.new((x, y, z)) for x, z in outline]
        face = bm.faces.new(verts)
        bmesh.ops.extrude_face_region(bm, geom=[face])
        for v in bm.verts:
            if v not in verts:
                v.co.y = y + depth
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        self.add(material, bm, bevel, segs)

    def cyl(self, material, r, depth, loc, r2=None, bevel=0.01, segs=2, rot=(0, 0, 0), n=24,
            scale=(1, 1, 1)):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=n, radius1=r,
                              radius2=r if r2 is None else r2, depth=depth)
        bm.transform(Matrix.Diagonal((*scale, 1)))
        self.add(material, bm, bevel, segs, _xf(loc, rot))

    def ball(self, material, r, loc, scale=(1, 1, 1), rot=(0, 0, 0), u=20, v=12):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=r)
        bm.transform(Matrix.Diagonal((*scale, 1)))
        self.add(material, bm, 0, 0, _xf(loc, rot))

    def capsule(self, material, r, length, loc, scale=(1, 1, 1), rot=(0, 0, 0), n=20):
        """A rounded pill standing up: `length` is the straight middle."""
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=n, v_segments=12, radius=r)
        for vert in bm.verts:
            vert.co.z += length / 2 if vert.co.z > 1e-5 else (-length / 2 if vert.co.z < -1e-5 else 0)
        bm.transform(Matrix.Diagonal((*scale, 1)))
        self.add(material, bm, 0, 0, _xf(loc, rot))

    def tube(self, material, pts, r, fillet=0.06, n=12):
        pts = _fillet([Vector(p) for p in pts], fillet)
        bm = bmesh.new()
        rings, prev = [], None
        for i, p in enumerate(pts):
            if i == 0:
                t = pts[1] - pts[0]
            elif i == len(pts) - 1:
                t = pts[-1] - pts[-2]
            else:
                t = (pts[i + 1] - p).normalized() + (p - pts[i - 1]).normalized()
            t.normalize()
            if prev is None:
                a = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
                nrm = t.cross(a).normalized()
            else:
                nrm = (prev - t * prev.dot(t)).normalized()
            prev = nrm
            b = t.cross(nrm)
            rings.append([bm.verts.new(p + (nrm * math.cos(k * 2 * math.pi / n) +
                                            b * math.sin(k * 2 * math.pi / n)) * r) for k in range(n)])
        for a, b in zip(rings, rings[1:]):
            for k in range(n):
                bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        self.add(material, bm)

    def build(self, location=(0, 0, 0), rot_z=0.0):
        """Makes the Blender objects: an empty named after the prop with one
        mesh per material under it."""
        root = bpy.data.objects.new(self.name, None)
        scene.collection.objects.link(root)
        objects = [root]
        for (material, group), bms in self.parts.items():
            joined = bmesh.new()
            for bm in bms:
                me = bpy.data.meshes.new("tmp")
                bm.to_mesh(me)
                joined.from_mesh(me)
                bpy.data.meshes.remove(me)
                bm.free()
            if self.turn:
                joined.transform(Matrix.Rotation(math.radians(self.turn), 4, "Z"))
            name = material if group is None else group if group in self.plain else "%s_%s" % (material, group)
            pivot = Vector(self.pivots.get(group, (0, 0, 0)))
            joined.transform(Matrix.Translation(-pivot))
            me = bpy.data.meshes.new(name)
            joined.to_mesh(me)
            joined.free()
            me.materials.append(M(material))
            me.shade_smooth()
            me.set_sharp_from_angle(angle=math.radians(40))
            ob = bpy.data.objects.new(name, me)
            scene.collection.objects.link(ob)
            ob.parent = root
            ob.location = pivot
            objects.append(ob)
        root.location = location
        root.rotation_euler = (0, 0, math.radians(rot_z))
        self.objects = objects
        return self

    def export(self, folder):
        bpy.ops.object.select_all(action="DESELECT")
        for ob in self.objects:
            ob.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(folder, self.name + ".glb"),
                                  export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True)


# ---------------------------------------------------------------- objects
# Footprints match the catalogue (ObjectDef.size: x across, y deep).

def bed():
    p = Prop("bed")  # 1 x 2 tiles, head towards -y
    for y, top in ((-0.95, 0.62), (0.95, 0.44)):
        p.tube("paint", [(-0.42, y, 0), (-0.42, y, top), (0.42, y, top), (0.42, y, 0)], 0.035, 0.14)
        p.tube("paint", [(-0.42, y, 0.3), (0.42, y, 0.3)], 0.025, 0)
    for x in (-0.42, 0.42):
        p.box("paint", (0.05, 1.9, 0.09), (x, 0, 0.22), 0.02, 2)
    p.box("mattress", (0.8, 1.82, 0.14), (0, 0, 0.31), 0.05, 3)
    p.box("sheet", (0.82, 0.5, 0.15), (0, -0.66, 0.315), 0.055, 3)
    p.box("blanket", (0.86, 1.34, 0.17), (0, 0.27, 0.315), 0.06, 3)
    p.box("sheet", (0.52, 0.3, 0.1), (0, -0.67, 0.43), 0.045, 3)
    return p


def toilet():
    p = Prop("toilet", 180)  # 0.5 x 0.75 steel combi unit, back to the wall
    p.box("steel", (0.46, 0.2, 0.74), (0, -0.265, 0.37), 0.05, 3)
    p.cyl("steel", 0.14, 0.07, (0, -0.25, 0.77), bevel=0.025, n=20)
    p.cyl("steel_dark", 0.105, 0.01, (0, -0.25, 0.802), bevel=0, n=20)
    p.tube("steel", [(0, -0.34, 0.8), (0, -0.34, 0.87), (0, -0.28, 0.87)], 0.016, 0.03, n=10)
    p.cyl("steel", 0.13, 0.31, (0, 0.04, 0.155), r2=0.16, scale=(1, 1.2, 1), bevel=0.035, segs=3, n=20)
    p.cyl("steel_dark", 0.115, 0.01, (0, 0.04, 0.312), scale=(1, 1.2, 1), bevel=0, n=20)
    return p


def shower():
    p = Prop("shower", 180)  # 0.75 x 0.75 tiled corner shower, walls behind
    p.box("tiles", (0.7, 0.7, 0.06), (0, 0, 0.03), 0.02, 2)
    p.cyl("steel_dark", 0.04, 0.005, (0.1, 0.1, 0.062), bevel=0, n=16)
    p.box("tiles", (0.7, 0.06, 1.3), (0, -0.32, 0.71), 0.02, 2)
    p.box("tiles", (0.06, 0.64, 1.3), (-0.32, 0.03, 0.71), 0.02, 2)
    p.tube("steel", [(0.1, -0.28, 0.6), (0.1, -0.28, 1.18), (0.1, -0.1, 1.18), (0.1, -0.1, 1.13)], 0.02, 0.08, n=10)
    p.cyl("steel", 0.035, 0.05, (0.1, -0.1, 1.11), r2=0.075, bevel=0.012, n=20, rot=(180, 0, 0))
    p.cyl("steel", 0.045, 0.04, (0.1, -0.28, 0.8), bevel=0.015, n=20, rot=(90, 0, 0))
    return p


def table():
    p = Prop("table")  # 2 x 1, bolted-down canteen table with swing-out stools
    p.box("wood", (1.75, 0.66, 0.06), (0, 0, 0.5), 0.03, 3)
    for x in (-0.55, 0.55):
        p.tube("paint", [(x, 0, 0), (x, 0, 0.47)], 0.045, 0, n=12)
        p.cyl("paint", 0.14, 0.03, (x, 0, 0.015), bevel=0.012, n=20)
        for y in (-0.36, 0.36):
            p.tube("paint", [(x, 0, 0.1), (x * 0.82, y * 0.6, 0.1), (x * 0.82, y, 0.1), (x * 0.82, y, 0.28)], 0.025, 0.08, n=10)
            p.cyl("paint", 0.13, 0.06, (x * 0.82, y, 0.3), bevel=0.025, segs=3, n=20)
    return p


# Surfaces: plain tops with nothing on them. Things go on them as their own
# props, and chairs stand beside them. Each comes in looks that share one
# shape: the default (beech laminate on painted metal), pine, metal and
# painted, exported as <name>, <name>_pine, <name>_metal and <name>_painted.
LOOKS = {"": ("wood", "paint"), "pine": ("pine", "pine"), "metal": ("steel", "steel_dark"),
         "painted": ("painted", "painted")}


def _looks(make):
    """One builder per look: make(name, top, legs) -> Prop."""
    out = {}
    for look, (top, legs) in LOOKS.items():
        name = make.__name__ + ("_" + look if look else "")
        out[name] = (lambda name=name, top=top, legs=legs: make(name, top, legs))
    return out


def desk(name="desk", top="wood", legs="paint"):
    p = Prop(name, 180)  # 1 x 0.5, bolted to the wall behind; top at 0.53
    p.box(top, (0.95, 0.46, 0.06), (0, 0, 0.5), 0.025, 3)
    for x in (-0.4, 0.4):
        p.tube(legs, [(x, -0.2, 0.47), (x, 0.15, 0.47), (x, 0.15, 0)], 0.025, 0.1, n=10)
    return p


def office_desk(name="office_desk", top="wood", legs="paint", back=0.0):
    """1.5 x 0.75 desk with drawers, top at 0.53. `back` moves it towards
    the back of a deeper footprint."""
    p = Prop(name)
    y = back
    p.box(top, (1.45, 0.7, 0.06), (0, y, 0.5), 0.025, 3)
    for x in (-0.66, 0.66):
        p.box(legs, (0.06, 0.62, 0.47), (x, y, 0.235), 0.015, 2)
    p.box(legs, (0.4, 0.62, 0.42), (0.42, y, 0.26), 0.02, 2)
    for z in (0.16, 0.34):
        p.box("steel", (0.12, 0.02, 0.03), (0.42, y - 0.32, z), 0.008, 1)
    p.box(legs, (0.8, 0.03, 0.3), (-0.2, y + 0.3, 0.3), 0.01, 1)  # modesty panel
    return p


def games_table(name="games_table", top="wood", legs="paint"):
    p = Prop(name)  # 1 x 1 small table, top at 0.725
    p.box(top, (0.9, 0.9, 0.05), (0, 0, 0.7), 0.03, 3)
    p.tube(legs, [(0, 0, 0), (0, 0, 0.68)], 0.04, 0, n=12)
    p.cyl(legs, 0.25, 0.03, (0, 0, 0.015), bevel=0.012, n=24)
    return p


# Chairs: 0.5 x 0.5, the sitter faces the front (Godot +z); seat top 0.32.

def chair(name="chair", seat="paint", frame="steel_dark"):
    p = Prop(name)
    p.box(seat, (0.4, 0.38, 0.04), (0, 0, 0.3), 0.015, 2)
    p.box(seat, (0.4, 0.04, 0.26), (0, 0.19, 0.5), 0.015, 2)
    for x in (-0.17, 0.17):
        for y in (-0.15, 0.17):
            p.tube(frame, [(x, y, 0.0), (x, y, 0.29)], 0.014, 0, n=8)
        p.tube(frame, [(x, 0.17, 0.29), (x, 0.19, 0.62)], 0.014, 0, n=8)
    return p


def chair_cushioned():
    p = chair("chair_cushioned", seat="wood", frame="wood")
    p.box("cushion", (0.38, 0.36, 0.05), (0, -0.01, 0.345), 0.022, 3)
    return p


def chair_pine():
    return chair("chair_pine", seat="pine", frame="pine")


def office_chair():
    p = Prop("office_chair")  # swivel chair
    p.box("vinyl", (0.38, 0.36, 0.07), (0, 0, 0.31), 0.03, 3)
    p.box("vinyl", (0.36, 0.06, 0.32), (0, 0.19, 0.52), 0.03, 3)
    p.tube("steel_dark", [(0, 0.17, 0.33), (0, 0.2, 0.4)], 0.02, 0, n=8)
    p.tube("steel_dark", [(0, 0, 0.28), (0, 0, 0.06)], 0.025, 0, n=10)
    for a in range(5):
        ang = math.radians(a * 72)
        p.tube("steel_dark", [(0, 0, 0.06), (math.sin(ang) * 0.2, math.cos(ang) * 0.2, 0.05)], 0.018, 0, n=8)
        p.ball("rubber", 0.025, (math.sin(ang) * 0.2, math.cos(ang) * 0.2, 0.025), u=8, v=6)
    return p


# Small things that sit on a surface: origin at the middle of the bottom,
# front towards Godot's +z.

def chess_board():
    p = Prop("chess_board")  # 0.4 x 0.4 board with a few pieces
    p.box("cream", (0.4, 0.4, 0.02), (0, 0, 0.01), 0.006, 1)
    for i in range(4):
        for j in range(4):
            if (i + j) % 2 == 0:
                p.box("book_c", (0.09, 0.09, 0.006), (-0.15 + i * 0.1, -0.15 + j * 0.1, 0.022), 0, 0)
    for k, (x, y) in enumerate(((-0.15, -0.15), (0.05, -0.15), (-0.05, 0.15), (0.15, 0.05))):
        p.cyl("rubber" if k % 2 else "sheet", 0.03, 0.02, (x, y, 0.035), bevel=0.006, n=14)
        p.ball("rubber" if k % 2 else "sheet", 0.022, (x, y, 0.06), u=10, v=6)
    return p


def cctv_monitor():
    p = Prop("cctv_monitor")  # 0.5 x 0.25 monitor and keyboard, screen to the front
    p.box("steel_dark", (0.52, 0.12, 0.36), (0, 0.06, 0.3), 0.04, 3)
    p.box("screen", (0.44, 0.02, 0.28), (0, -0.005, 0.3), 0.01, 1)
    p.box("light", (0.004, 0.022, 0.28), (0, -0.005, 0.3), 0, 0)
    p.box("light", (0.44, 0.022, 0.004), (0, -0.005, 0.3), 0, 0)
    p.box("steel_dark", (0.08, 0.08, 0.1), (0, 0.08, 0.06), 0.02, 2)
    p.box("steel_dark", (0.2, 0.14, 0.015), (0, 0.08, 0.0075), 0.006, 1)
    p.box("steel_dark", (0.36, 0.12, 0.02), (0, -0.1, 0.01), 0.008, 1)  # keyboard
    return p


def cctv_camera():
    """0.5 x 0.5, 2.2 m: a slim grey post with a boxy camera on top, tilted
    a little down, its lens looking along Godot's +z (Blender -Y)."""
    p = Prop("cctv_camera")
    p.cyl("steel_dark", 0.14, 0.05, (0, 0, 0.025), bevel=0.015, n=20)
    p.tube("steel", [(0, 0, 0.04), (0, 0, 1.98)], 0.035, 0, n=12)
    p.box("steel_dark", (0.1, 0.1, 0.08), (0, 0, 2.0), 0.02, 2)  # bracket
    tilt = (-15, 0, 0)
    p.box("cream", (0.18, 0.36, 0.16), (0, -0.08, 2.1), 0.04, 3, rot=tilt)
    p.box("cream", (0.22, 0.4, 0.025), (0, -0.1, 2.195), 0.01, 1, rot=tilt)  # sun hood
    p.cyl("rubber", 0.055, 0.04, (0, -0.27, 2.05), bevel=0.012, n=20, rot=(90 - 15, 0, 0))
    p.cyl("screen", 0.04, 0.045, (0, -0.275, 2.05), bevel=0.008, n=20, rot=(90 - 15, 0, 0))
    p.ball("food_c", 0.012, (0.06, -0.24, 2.13), u=8, v=6)  # recording light
    return p


def nameplate():
    p = Prop("nameplate")  # a little wooden block with a brass plate
    p.taper("wood", (0.22, 0.06), (0.22, 0.03), 0.06, (0, 0, 0.03), 0.008, 1)
    p.box("gold", (0.18, 0.01, 0.035), (0, -0.026, 0.032), 0.003, 1, rot=(-15, 0, 0))
    return p


def in_tray():
    p = Prop("in_tray")  # two stacked wire trays with papers
    for z in (0.0, 0.07):
        p.box("steel", (0.3, 0.24, 0.012), (0, 0, z + 0.006), 0.004, 1)
        for x in (-0.15, 0.15):
            p.box("steel", (0.012, 0.24, 0.04), (x, 0, z + 0.02), 0.003, 1)
        p.box("paper", (0.26, 0.2, 0.02), (0, 0.01, z + 0.022), 0.004, 1)
    for x in (-0.13, 0.13):
        p.tube("steel", [(x, 0.1, 0.0), (x, 0.1, 0.08)], 0.006, 0, n=6)
    return p


def desk_plant():
    p = Prop("desk_plant")  # a little pot plant
    p.cyl("pot", 0.06, 0.09, (0, 0, 0.045), r2=0.075, bevel=0.012, n=18)
    for loc, r in (((0, 0, 0.13), 0.07), ((0.04, 0.02, 0.17), 0.05), ((-0.04, -0.01, 0.16), 0.05)):
        p.ball("leaf", r, loc, u=12, v=8)
    return p


def mug():
    p = Prop("mug")
    p.cyl("cream", 0.04, 0.09, (0, 0, 0.045), bevel=0.012, n=18)
    p.tube("cream", [(0.04, 0, 0.07), (0.07, 0, 0.065), (0.07, 0, 0.03), (0.04, 0, 0.025)], 0.01, 0.015, n=8)
    p.cyl("coffee", 0.034, 0.005, (0, 0, 0.085), bevel=0, n=16)
    return p


def coffee_machine():
    p = Prop("coffee_machine")  # 0.75 x 0.5: a little counter with a machine and mugs
    p.box("wood", (0.72, 0.46, 0.04), (0, 0, 0.56), 0.012, 2)
    p.box("paint", (0.68, 0.42, 0.54), (0, 0.01, 0.27), 0.02, 2)
    p.box("steel_dark", (0.3, 0.02, 0.4), (-0.17, -0.2, 0.27), 0.008, 1)
    p.box("steel_dark", (0.3, 0.02, 0.4), (0.17, -0.2, 0.27), 0.008, 1)
    # Machine: a rounded body with a spout and a drip tray.
    p.box("steel_dark", (0.3, 0.3, 0.3), (-0.12, 0.05, 0.73), 0.04, 3)
    p.box("steel", (0.26, 0.2, 0.04), (-0.12, -0.02, 0.6), 0.012, 2)
    p.box("steel_dark", (0.3, 0.12, 0.07), (-0.12, -0.08, 0.85), 0.02, 2)
    p.cyl("steel", 0.02, 0.05, (-0.12, -0.11, 0.8), bevel=0.005, n=12)
    p.cyl("light", 0.015, 0.01, (-0.02, -0.1, 0.72), bevel=0, n=12, rot=(90, 0, 0))
    p.cyl("cream", 0.035, 0.07, (-0.12, -0.08, 0.655), bevel=0.01, n=16)
    # A jar of sugar and a row of mugs.
    p.cyl("glass", 0.045, 0.1, (0.13, 0.12, 0.63), bevel=0.012, n=16)
    p.cyl("steel", 0.047, 0.015, (0.13, 0.12, 0.685), bevel=0.005, n=16)
    for k, x in enumerate((0.08, 0.18, 0.28)):
        p.cyl(("cream", "plastic", "cream")[k], 0.04, 0.08, (x, -0.1, 0.62), bevel=0.012, n=16)
    return p


def guard_desk():
    """1.5 x 1 guard post: a plain office desk at the back of the footprint,
    room for a chair at the front. The monitor and chair are their own."""
    return office_desk("guard_desk", back=0.12)


def reception_desk():
    """2 x 1 reception counter: a raised front for the new arrivals, a desk
    behind for the officer, a rubber stamp and a paper tray on top."""
    p = Prop("reception_desk")
    p.box("paint", (1.9, 0.5, 0.62), (0, -0.2, 0.31), 0.03, 3)
    p.box("wood", (1.96, 0.32, 0.04), (0, -0.32, 0.64), 0.015, 2)
    p.box("wood", (1.9, 0.5, 0.04), (0, 0.22, 0.48), 0.015, 2)
    for x in (-0.9, 0.9):
        p.box("paint", (0.06, 0.4, 0.46), (x, 0.25, 0.23), 0.015, 2)
    p.box("steel_dark", (1.8, 0.02, 0.06), (0, -0.455, 0.12), 0.008, 1)
    # Tray of forms and a stamp on its pad.
    p.box("steel", (0.3, 0.22, 0.04), (-0.55, -0.32, 0.68), 0.012, 2)
    p.box("paper", (0.26, 0.18, 0.02), (-0.55, -0.32, 0.69), 0.004, 1)
    p.box("food_c", (0.14, 0.09, 0.012), (0.4, -0.3, 0.665), 0.004, 1)
    p.cyl("rubber", 0.03, 0.02, (0.55, -0.3, 0.67), bevel=0.006, n=14)
    p.cyl("wood", 0.012, 0.06, (0.55, -0.3, 0.71), bevel=0.003, n=10)
    p.ball("wood", 0.025, (0.55, -0.3, 0.75), u=12, v=8)
    p.box("paper", (0.18, 0.24, 0.01), (0.1, -0.3, 0.665), 0.003, 1, rot=(0, 0, 8))
    p.box("steel_dark", (0.36, 0.14, 0.02), (-0.2, 0.25, 0.51), 0.008, 1)
    return p


def bus():
    """Prison bus, 4 x 1.6 x 1.6 m: front towards Blender +X (Godot +x),
    doors on Blender +Y (Godot -z)."""
    p = Prop("bus")
    L, W = 4.0, 1.6
    p.box("lorry", (L - 0.1, W - 0.06, 1.15), (0, 0, 0.95), 0.2, 4)
    p.box("blue_stripe", (L - 0.06, W - 0.02, 0.14), (0, 0, 0.72), 0.04, 2)
    p.box("steel_dark", (L - 0.4, W - 0.2, 0.2), (0, 0, 0.32), 0.05, 2)
    # Windscreen, lights and bumper at the front.
    p.box("glass", (0.12, W - 0.36, 0.42), (L / 2 - 0.08, 0, 1.18), 0.05, 2)
    for y in (-0.55, 0.55):
        p.cyl("light", 0.08, 0.05, (L / 2 - 0.04, y, 0.62), bevel=0.02, n=16, rot=(0, 90, 0))
    p.box("steel_dark", (0.16, W - 0.1, 0.16), (L / 2 - 0.04, 0, 0.42), 0.05, 2)
    p.box("steel_dark", (0.16, W - 0.1, 0.16), (-L / 2 + 0.04, 0, 0.42), 0.05, 2)
    # Barred side windows, both sides.
    for side in (-1, 1):
        for k in range(4):
            x = -1.35 + k * 0.72
            p.box("glass", (0.56, 0.06, 0.34), (x, side * (W / 2 - 0.02), 1.2), 0.03, 2)
            for b in range(4):
                bx = x - 0.21 + b * 0.14
                p.tube("paint", [(bx, side * (W / 2 + 0.005), 1.04), (bx, side * (W / 2 + 0.005), 1.36)], 0.012, 0, n=6)
        # Mirrors by the cab.
        p.box("steel_dark", (0.05, 0.1, 0.16), (L / 2 - 0.25, side * (W / 2 + 0.06), 1.2), 0.02, 2)
    # Folding doors on the +Y side, near the front.
    p.box("glass", (0.56, 0.06, 0.9), (1.25, W / 2 - 0.01, 0.85), 0.03, 2)
    p.box("paint", (0.01, 0.07, 0.9), (1.25, W / 2 - 0.01, 0.85), 0, 0)
    p.box("steel_dark", (0.6, 0.2, 0.08), (1.25, W / 2 - 0.08, 0.2), 0.02, 2)
    # Chunky wheels.
    for x in (-1.25, 1.2):
        for side in (-1, 1):
            p.cyl("rubber", 0.3, 0.24, (x, side * (W / 2 - 0.1), 0.3), bevel=0.05, segs=3, n=28, rot=(90, 0, 0))
            p.cyl("steel", 0.14, 0.26, (x, side * (W / 2 - 0.1), 0.3), bevel=0.03, n=20, rot=(90, 0, 0))
    return p


def car(name="car", body="car_cream"):
    """1 x 2 little staff car, front towards Godot's +z (Blender -Y)."""
    p = Prop(name)
    p.box(body, (0.9, 1.85, 0.38), (0, 0, 0.38), 0.14, 4)
    p.box(body, (0.82, 1.0, 0.36), (0, 0.12, 0.68), 0.16, 4)
    # Windows all round the cabin.
    p.box("glass", (0.7, 0.06, 0.24), (0, -0.4, 0.7), 0.04, 2, rot=(-25, 0, 0))
    p.box("glass", (0.68, 0.06, 0.22), (0, 0.63, 0.7), 0.04, 2, rot=(20, 0, 0))
    for side in (-1, 1):
        p.box("glass", (0.06, 0.78, 0.22), (side * 0.405, 0.12, 0.7), 0.03, 2)
        p.cyl("light", 0.06, 0.04, (side * 0.3, -0.92, 0.42), bevel=0.015, n=16, rot=(90, 0, 0))
        p.cyl("food_c", 0.045, 0.04, (side * 0.32, 0.92, 0.42), bevel=0.012, n=14, rot=(90, 0, 0))
        p.box("steel_dark", (0.04, 0.08, 0.06), (side * 0.47, -0.3, 0.62), 0.015, 2)
    p.box("steel_dark", (0.92, 0.1, 0.1), (0, -0.92, 0.24), 0.04, 2)
    p.box("steel_dark", (0.92, 0.1, 0.1), (0, 0.92, 0.24), 0.04, 2)
    for y in (-0.58, 0.58):
        for side in (-1, 1):
            p.cyl("rubber", 0.17, 0.14, (side * 0.4, y, 0.17), bevel=0.04, segs=3, n=24, rot=(0, 90, 0))
            p.cyl("steel", 0.08, 0.15, (side * 0.4, y, 0.17), bevel=0.02, n=16, rot=(0, 90, 0))
    return p


def bus_stop():
    """1 x 0.5 bus stop: a sign on a post and a little bench with a canopy,
    front (towards the road) at Godot's +z."""
    p = Prop("bus_stop")
    # Shelter: two posts at the back, a curved roof leaning forward.
    for x in (-0.42, 0.42):
        p.box("paint", (0.05, 0.05, 1.15), (x, 0.18, 0.575), 0.012, 2)
    p.box("glass", (0.8, 0.02, 0.7), (0, 0.19, 0.6), 0.008, 1)
    p.box("paint", (0.94, 0.42, 0.04), (0, 0.04, 1.17), 0.015, 2, rot=(-8, 0, 0))
    p.box("pine", (0.7, 0.18, 0.04), (0, 0.06, 0.3), 0.012, 2)
    for x in (-0.3, 0.3):
        p.box("paint", (0.04, 0.14, 0.28), (x, 0.06, 0.14), 0.01, 1)
    # The sign: a round blue disc on its own post at the front corner.
    p.tube("steel", [(0.38, -0.18, 0.0), (0.38, -0.18, 1.3)], 0.022, 0, n=10)
    p.cyl("sign_blue", 0.13, 0.03, (0.38, -0.18, 1.38), bevel=0.01, n=28, rot=(90, 0, 0))
    p.cyl("sheet", 0.09, 0.034, (0.38, -0.18, 1.38), bevel=0.006, n=28, rot=(90, 0, 0))
    p.box("sign_blue", (0.1, 0.036, 0.05), (0.38, -0.18, 1.38), 0.01, 1)
    p.box("sheet", (0.16, 0.02, 0.1), (0.38, -0.18, 1.12), 0.01, 1)  # timetable
    return p


def tunnel_portal():
    """Where the road leaves the land: a stone portal round a 3.6 x 2.2 m
    opening in a grassy bank 7 m wide. Origin at the middle of the road at
    the mouth; the mouth faces Godot's +z (Blender -Y) and the bank runs
    6 m back, with the tunnel dark inside so vehicles vanish into it."""
    p = Prop("tunnel_portal")
    half, wall, rise = 1.8, 1.3, 0.9   # opening half-width, wall height, arch rise
    arch = [(half * math.cos(math.pi * k / 16), wall + rise * math.sin(math.pi * k / 16)) for k in range(17)]
    face = [(-2.5, 0.0), (-2.5, 3.0), (2.5, 3.0), (2.5, 0.0), (half, 0.0)] + arch + [(-half, 0.0)]
    p.prism("stone", face, 0.45, y=0.0, bevel=0.03)
    # Voussoirs round the arch and a coping along the top.
    for k in range(9):
        a0, a1 = math.pi * k / 9, math.pi * (k + 1) / 9
        mid = (a0 + a1) / 2
        inner = [(half * math.cos(t), wall + rise * math.sin(t)) for t in (a0, a1)]
        outer = [((half + 0.35) * math.cos(t), wall + (rise + 0.35) * math.sin(t)) for t in (a0, a1)]
        p.prism("stone_dark" if k % 2 else "stone", [inner[0], outer[0], outer[1], inner[1]], 0.12, y=-0.08, bevel=0.02)
    for side in (-1, 1):
        p.box("stone_dark", (0.35, 0.12, wall), (side * (half + 0.175), -0.02, wall / 2), 0.02, 1)
    p.box("stone_dark", (5.2, 0.6, 0.22), (0, 0.15, 3.1), 0.05, 2)
    # Dark inside, so the road and vehicles disappear.
    p.box("dark", (half * 2, 5.6, wall + rise), (0, 3.25, (wall + rise) / 2), 0, 0)
    # The bank: soft grassy mounds either side and over the top.
    for side in (-1, 1):
        p.box("grass", (1.5, 6.4, 3.2), (side * 3.0, 3.4, 1.2), 0.7, 4)
        p.box("grass", (1.4, 2.0, 1.4), (side * 3.0, 0.2, 0.25), 0.6, 4)
    p.box("grass", (5.2, 6.0, 1.4), (0, 3.4, 2.9), 0.65, 4)
    return p


# Contraband, carried or hidden: about 0.4 m like the other items (the game
# shrinks piles), origin at the middle of the bottom.

def biscuit():
    p = Prop("biscuit")  # a short stack of round biscuits
    for i, (dx, dy) in enumerate(((0, 0), (0.01, -0.01), (-0.01, 0.005))):
        p.cyl("biscuit", 0.13, 0.05, (dx, dy, 0.025 + i * 0.055), bevel=0.018, segs=2, n=28)
    for a in range(6):
        ang = math.radians(a * 60 + 20)
        p.ball("crate", 0.012, (math.cos(ang) * 0.07, math.sin(ang) * 0.07, 0.165), u=8, v=6)
    return p


def spoon():
    p = Prop("spoon")
    p.box("steel", (0.32, 0.04, 0.018), (-0.06, 0, 0.02), 0.008, 1, rot=(0, -6, 0))
    p.ball("steel", 0.065, (0.15, 0, 0.035), scale=(1.3, 1, 0.35), u=16, v=8)
    return p


def rolling_pin():
    p = Prop("rolling_pin")
    p.cyl("pine", 0.06, 0.28, (0, 0, 0.06), bevel=0.02, n=20, rot=(0, 90, 0))
    for side in (-1, 1):
        p.cyl("crate", 0.025, 0.09, (side * 0.185, 0, 0.06), bevel=0.01, n=12, rot=(0, 90, 0))
    return p


def frying_pan():
    p = Prop("frying_pan")
    p.cyl("rubber", 0.14, 0.05, (-0.06, 0, 0.025), r2=0.16, bevel=0.015, segs=2, n=28)
    p.cyl("steel_dark", 0.13, 0.008, (-0.06, 0, 0.047), bevel=0, n=28)
    p.box("rubber", (0.2, 0.04, 0.025), (0.19, 0, 0.04), 0.01, 2, rot=(0, -8, 0))
    return p


def screwdriver():
    p = Prop("screwdriver")
    p.cyl("food_c", 0.035, 0.13, (-0.09, 0, 0.035), bevel=0.014, n=12, rot=(0, 90, 0))
    p.cyl("steel", 0.01, 0.2, (0.07, 0, 0.035), bevel=0.003, n=8, rot=(0, 90, 0))
    p.box("steel", (0.02, 0.025, 0.006), (0.17, 0, 0.035), 0.002, 1)
    return p


def mallet():
    p = Prop("mallet")
    p.cyl("pine", 0.016, 0.3, (-0.03, 0, 0.065), bevel=0.006, n=10, rot=(0, 90, 0))
    p.box("crate", (0.09, 0.15, 0.13), (0.15, 0, 0.065), 0.025, 2)
    return p


def soap_sock():
    p = Prop("soap_sock")  # a sock with a bar of soap knotted in the toe
    p.ball("sheet", 0.07, (0.1, 0, 0.065), scale=(1.15, 1, 0.9), u=16, v=10)
    p.capsule("sheet", 0.035, 0.18, (-0.05, 0, 0.035), rot=(0, 90, 0))
    p.ball("sheet", 0.04, (-0.17, 0, 0.04), scale=(1, 1, 0.8), u=10, v=8)
    p.box("plastic", (0.05, 0.04, 0.02), (0.13, -0.06, 0.08), 0.01, 1)  # soap peeking out
    return p


def infirmary_bed():
    """1 x 2 hospital bed, head towards -y like the cell bed (so people
    lie the same way), on a white frame with side rails."""
    p = Prop("infirmary_bed")
    for y, top in ((-0.95, 0.62), (0.95, 0.5)):
        p.box("hospital", (0.9, 0.05, top - 0.08), (0, y, (top + 0.08) / 2), 0.025, 2)
    for x in (-0.4, 0.4):
        for y in (-0.88, 0.88):
            p.tube("steel", [(x, y, 0.08), (x, y, 0.2)], 0.02, 0, n=8)
            p.ball("rubber", 0.04, (x, y, 0.045), u=10, v=6)
    p.box("hospital", (0.86, 1.86, 0.1), (0, 0, 0.24), 0.03, 2)
    p.box("sheet", (0.8, 1.8, 0.13), (0, 0, 0.35), 0.05, 3)
    p.box("plastic", (0.84, 1.3, 0.15), (0, 0.24, 0.355), 0.06, 3)  # pale blue blanket
    p.box("sheet", (0.52, 0.3, 0.1), (0, -0.67, 0.46), 0.045, 3)
    # Side rails, folded down along the middle.
    for side in (-1, 1):
        p.tube("steel", [(side * 0.45, -0.5, 0.3), (side * 0.45, -0.5, 0.5), (side * 0.45, 0.4, 0.5), (side * 0.45, 0.4, 0.3)], 0.015, 0.05, n=8)
        p.tube("steel", [(side * 0.45, -0.5, 0.4), (side * 0.45, 0.4, 0.4)], 0.012, 0, n=8)
    # A chart clipped to the foot.
    p.box("paper", (0.22, 0.02, 0.28), (0, 0.98, 0.36), 0.008, 1)
    return p


def medicine_cabinet():
    """1 x 1, 1.4 m tall: a white cabinet with a green cross, back to the
    wall, shelves of bottles behind glass doors on top."""
    p = Prop("medicine_cabinet")
    w, d = 0.9, 0.45
    p.box("hospital", (w, d, 0.62), (0, 0.2, 0.31), 0.03, 2)
    for x in (-0.22, 0.22):
        p.box("hospital", (0.42, 0.02, 0.56), (x, -0.035, 0.31), 0.01, 1)
        p.box("steel", (0.1, 0.02, 0.03), (x - math.copysign(0.12, x), -0.05, 0.12), 0.008, 1)
    p.box("hospital", (w, 0.3, 0.74), (0, 0.27, 1.02), 0.03, 2)
    for z in (0.83, 1.07):
        p.box("steel", (w - 0.08, 0.24, 0.015), (0, 0.27, z), 0.004, 1)
        for k, x in enumerate((-0.3, -0.15, 0.0, 0.15, 0.3)):
            p.cyl(("plastic", "food_c", "sheet", "cross", "food_a")[k], 0.035, 0.12 - (k % 2) * 0.03,
                  (x, 0.25, z + 0.07 - (k % 2) * 0.015), bevel=0.01, n=12)
    p.box("glass", (w - 0.06, 0.02, 0.66), (0, 0.115, 1.02), 0.01, 1)
    # The cross on the lower doors.
    a, b, z = 0.13, 0.042, 0.38
    plus = [(-b, z + a), (b, z + a), (b, z + b), (a, z + b), (a, z - b), (b, z - b), (b, z - a),
            (-b, z - a), (-b, z - b), (-a, z - b), (-a, z + b), (-b, z + b)]
    p.prism("cross", plus, 0.02, y=-0.065, bevel=0.006)
    return p


def dust_cloud():
    """A soft cartoon scrap cloud, about 1.3 m across, sitting on the
    ground: one lumpy mesh to replace the separate spheres."""
    p = Prop("dust_cloud")
    rng = __import__("random").Random(4)
    for i in range(9):
        a = math.tau * i / 9
        r = 0.42 + rng.uniform(-0.05, 0.06)
        p.ball("dust", rng.uniform(0.24, 0.32), (math.cos(a) * r, math.sin(a) * r, 0.4 + rng.uniform(-0.08, 0.1)), u=16, v=10)
    for loc, r in (((0, 0, 0.5), 0.42), ((0.12, -0.1, 0.78), 0.3), ((-0.15, 0.12, 0.74), 0.27)):
        p.ball("dust", r, loc, u=18, v=12)
    for i in range(5):
        a = math.tau * i / 5 + 0.4
        p.ball("dust", 0.14, (math.cos(a) * 0.72, math.sin(a) * 0.72, 0.14), u=12, v=8)
    return p


def lift():
    p = Prop("lift", 180)  # 1 x 1 cabin, 1.5 m tall, doors at the front
    h = 1.5
    for x in (-0.44, 0.44):
        for y in (-0.44, 0.44):
            p.box("paint", (0.1, 0.1, h - 0.1), (x, y, (h - 0.1) / 2), 0.03, 2)
    p.box("paint", (0.98, 0.98, 0.1), (0, 0, h - 0.05), 0.03, 2)
    p.box("steel_dark", (0.92, 0.92, 0.04), (0, 0, 0.02), 0.01, 1)
    # Back and sides: panels; front: two steel doors with a gap.
    p.box("steel", (0.8, 0.04, h - 0.12), (0, -0.44, (h - 0.12) / 2), 0.01, 1)
    for x in (-0.44, 0.44):
        p.box("steel", (0.04, 0.8, h - 0.12), (x, 0, (h - 0.12) / 2), 0.01, 1)
    for x in (-0.2, 0.2):
        p.box("steel", (0.39, 0.05, DOOR_H), (x, 0.44, DOOR_H / 2), 0.012, 2)
    p.box("paint", (0.8, 0.06, h - 0.1 - DOOR_H), (0, 0.44, DOOR_H + (h - 0.1 - DOOR_H) / 2), 0.02, 2)
    p.cyl("light", 0.05, 0.03, (0, 0.475, DOOR_H + 0.12), bevel=0.01, n=16, rot=(90, 0, 0))
    return p


def door():
    """A steel door that fills a 1 m opening in a wall along x, 1.15 m tall.
    Frame and leaf are deep enough for the thickest indoor wall."""
    p = Prop("door")
    w, fw, depth = 1.0, 0.08, 0.22
    for x in (-w / 2 + fw / 2, w / 2 - fw / 2):
        p.box("paint", (fw, depth, DOOR_H), (x, 0, DOOR_H / 2), 0.02, 2)
    p.box("paint", (w - 2 * fw, depth - 0.02, fw), (0, 0, DOOR_H - fw / 2), 0.02, 2)
    leaf_w = w - 2 * fw - 0.02
    p.box("paint", (leaf_w, 0.07, DOOR_H - fw - 0.01), (0, 0, (DOOR_H - fw) / 2), 0.02, 2)
    # Vision panel and a chunky handle each side.
    p.box("glass", (0.18, 0.08, 0.3), (0, 0, 0.75), 0.01, 1)
    for y in (-0.06, 0.06):
        p.box("steel", (0.12, 0.04, 0.05), (leaf_w / 2 - 0.12, y, 0.55), 0.015, 2)
    return p


def security_gate():
    """All-bars sliding gate: same opening as `door`, see-through."""
    p = Prop("security_gate")
    w, fw, depth = 1.0, 0.08, 0.22
    for x in (-w / 2 + fw / 2, w / 2 - fw / 2):
        p.box("paint", (fw, depth, DOOR_H), (x, 0, DOOR_H / 2), 0.02, 2)
    p.box("paint", (w - 2 * fw, depth - 0.02, fw), (0, 0, DOOR_H - fw / 2), 0.02, 2)
    # The track it slides along, and the rails top and bottom.
    p.box("steel_dark", (w - 2 * fw, 0.12, 0.04), (0, 0, DOOR_H - fw - 0.02), 0.01, 1)
    inner = w - 2 * fw
    for z in (0.06, 0.55, DOOR_H - fw - 0.08):
        p.box("paint", (inner, 0.05, 0.05), (0, 0, z), 0.015, 2)
    for i in range(7):
        x = -inner / 2 + inner * (i + 0.5) / 7
        p.tube("paint", [(x, 0, 0.03), (x, 0, DOOR_H - fw - 0.04)], 0.016, 0, n=10)
    p.box("steel", (0.06, 0.1, 0.16), (inner / 2 - 0.05, 0, 0.55), 0.015, 2)
    return p


def _mesh_infill(p, x0, x1, z0, z1, pitch=0.16, r=0.007, y=0.0, material="galv"):
    """Chain link as thin diagonal wires clipped to a rectangle."""
    w, h = x1 - x0, z1 - z0
    for sign in (1, -1):
        c = -h
        while c < w + h:
            pts = []
            for z in (0.0, h):  # where the line x = c + sign*z meets the rectangle
                xx = c + sign * z if sign > 0 else c - z
                pts.append((xx, z))
            (ax, az), (bx, bz) = pts
            # Clip the segment to 0..w in x.
            if ax > bx:
                (ax, az), (bx, bz) = (bx, bz), (ax, az)
            if bx < 0 or ax > w:
                c += pitch
                continue
            if ax < 0:
                az += (0 - ax) * (bz - az) / (bx - ax)
                ax = 0
            if bx > w:
                bz -= (bx - w) * (bz - az) / (bx - ax)
                bx = w
            if abs(bx - ax) > 0.02:
                p.tube(material, [(x0 + ax, y, z0 + az), (x0 + bx, y, z0 + bz)], r, 0, n=4)
            c += pitch


def people_gate():
    """A chain-link gate for the perimeter fence, same opening as `door`."""
    p = Prop("people_gate")
    for x in (-0.47, 0.47):
        p.tube("galv", [(x, 0, 0), (x, 0, DOOR_H)], 0.03, 0, n=10)
        p.ball("galv", 0.035, (x, 0, DOOR_H), u=10, v=6)
    # The leaf: a tube frame with mesh, hinged on the left.
    x0, x1, z0, z1 = -0.42, 0.42, 0.05, DOOR_H - 0.05
    p.tube("galv", [(x0, 0, z0), (x0, 0, z1), (x1, 0, z1), (x1, 0, z0), (x0, 0, z0)], 0.018, 0.04, n=8)
    p.tube("galv", [(x0, 0, (z0 + z1) / 2), (x1, 0, (z0 + z1) / 2)], 0.014, 0, n=8)
    _mesh_infill(p, x0, x1, z0, z1)
    p.box("steel_dark", (0.08, 0.08, 0.12), (x1 - 0.02, 0, 0.6), 0.015, 2)
    for z in (0.2, DOOR_H - 0.2):
        p.box("steel_dark", (0.07, 0.05, 0.05), (x0 - 0.03, 0, z), 0.01, 1)
    return p


def metal_detector():
    """A walk-through arch filling the same 1 m opening as `people_gate`:
    two off-white panels on grey feet, a header with a little readout and
    a green light on top that turns the game's colour when it beeps."""
    p = Prop("metal_detector")
    top = DOOR_H + 0.02
    for x in (-0.45, 0.45):
        p.box("white", (0.09, 0.42, top), (x, 0, top / 2), 0.03, 3)
        p.box("steel_dark", (0.13, 0.46, 0.06), (x, 0, 0.03), 0.015, 2)  # foot
        for k in range(5):  # sensor grooves on the inside face
            p.box("steel", (0.012, 0.3, 0.02), (x - 0.046 * (1 if x > 0 else -1), 0, 0.25 + k * 0.16), 0.004, 1)
    p.box("white", (1.0, 0.44, 0.12), (0, 0, top + 0.06), 0.04, 3)  # header
    for y in (-0.225, 0.225):  # a small readout on both faces
        p.box("screen", (0.2, 0.012, 0.06), (0, y, top + 0.06), 0.006, 1)
        p.box("cross", (0.05, 0.014, 0.02), (-0.05, y, top + 0.06), 0.004, 1)
    p.cyl("steel_dark", 0.05, 0.03, (0, 0, top + 0.135), bevel=0.01, n=18)
    p.ball("cross", 0.042, (0, 0, top + 0.15), scale=(1, 1, 0.9), u=16, v=10)
    return p


def memorial_plaque():
    """0.5 x 0.25, 0.5 m: a low stone stand with a sloping brass plate and
    a small posy at its foot. Gentle rather than grim; faces +z."""
    p = Prop("memorial_plaque")
    p.taper("stone", (0.36, 0.17), (0.32, 0.14), 0.32, (0, 0, 0.16), 0.02, 2)
    tilt = (25, 0, 0)
    p.box("stone", (0.4, 0.2, 0.08), (0, 0, 0.37), 0.02, 2, rot=tilt)
    def on_face(d, along=0.0):  # a point d off the sloping face, `along` up it
        return (0, -0.423 * d + 0.906 * along, 0.37 + 0.906 * d + 0.423 * along)
    p.box("gold", (0.32, 0.14, 0.008), on_face(0.042), 0.003, 1, rot=tilt)
    for k, w in enumerate((0.2, 0.24, 0.14)):  # three engraved lines
        p.box("stone_dark", (w, 0.012, 0.004), on_face(0.047, (1 - k) * 0.035), 0.002, 1, rot=tilt)
    # A posy of little flowers leaning on the stand.
    for x, y, z, mat in ((0.19, -0.08, 0.05, "leaf"), (0.23, -0.06, 0.09, "leaf"),
                         (0.17, -0.09, 0.1, "sheet"), (0.21, -0.1, 0.14, "poster_c"),
                         (0.25, -0.08, 0.13, "sheet"), (0.2, -0.05, 0.16, "sheet")):
        p.ball(mat, 0.042 if mat == "leaf" else 0.032, (x, y, z), u=12, v=8)
    return p


def vehicle_gate():
    """A sliding vehicle gate squeezed into one tile: a chunky frame on
    wheels running along a floor track, hazard stripes and a STOP sign."""
    p = Prop("vehicle_gate")
    # Guide posts with yellow and dark stripes.
    for x in (-0.47, 0.47):
        p.box("steel_dark", (0.08, 0.12, DOOR_H), (x, 0, DOOR_H / 2), 0.02, 2)
        for k in range(4):
            p.box("hazard", (0.085, 0.125, 0.12), (x, 0, 0.12 + k * 0.26), 0.01, 1)
    p.box("steel_dark", (1.0, 0.1, 0.05), (0, 0.0, 0.025), 0.015, 1)  # track
    # The leaf: heavy box-section frame with a diagonal brace and mesh.
    x0, x1, z0, z1 = -0.42, 0.42, 0.13, DOOR_H - 0.08
    p.box("galv", (0.86, 0.06, 0.06), (0, 0, z0), 0.015, 2)
    p.box("galv", (0.86, 0.06, 0.06), (0, 0, z1), 0.015, 2)
    for x in (x0, x1):
        p.box("galv", (0.06, 0.06, z1 - z0), (x, 0, (z0 + z1) / 2), 0.015, 2)
    p.tube("galv", [(x0, 0, z0), (x1, 0, z1)], 0.02, 0, n=8)
    _mesh_infill(p, x0, x1, z0, z1, pitch=0.13)
    for x in (-0.25, 0.25):
        p.cyl("rubber", 0.05, 0.04, (x, 0, 0.08), bevel=0.012, n=16, rot=(90, 0, 0))
    # A little STOP sign on both faces.
    for y in (-0.045, 0.045):
        p.cyl("food_c", 0.11, 0.015, (0, y, 0.68), bevel=0.004, n=8, rot=(90, 0, 22.5))
        p.box("sheet", (0.12, 0.017, 0.03), (0, y, 0.68), 0.004, 1)
    return p


def cell_door():
    """Barred cell door for later: same opening as `door`."""
    p = Prop("cell_door")
    w, fw, depth = 1.0, 0.08, 0.22
    for x in (-w / 2 + fw / 2, w / 2 - fw / 2):
        p.box("paint", (fw, depth, DOOR_H), (x, 0, DOOR_H / 2), 0.02, 2)
    p.box("paint", (w - 2 * fw, depth - 0.02, fw), (0, 0, DOOR_H - fw / 2), 0.02, 2)
    inner = w - 2 * fw
    for z in (0.1, DOOR_H - fw - 0.06):
        p.box("paint", (inner, 0.05, 0.09), (0, 0, z), 0.02, 2)
    for i in range(5):
        x = -inner / 2 + inner * (i + 0.5) / 5
        p.tube("paint", [(x, 0, 0.1), (x, 0, DOOR_H - fw - 0.06)], 0.02, 0, n=10)
    p.box("paint", (0.24, 0.06, 0.14), (0, 0, 0.62), 0.02, 2)
    p.box("steel", (0.08, 0.08, 0.12), (inner / 2 - 0.07, -0.01, 0.55), 0.02, 2)
    return p


# ---------------------------------------------------------------- people

def person():
    """About 0.9 m tall and chunky: big head, short body in one-piece
    overalls, stubby arms. Faces +y. The game tints outfit, skin and hair,
    swings the legs (outfit_legs, shoes_legs) forward to sit and the arms
    (outfit_arms, skin_arms) forward to carry. Parts named after a group
    or role only show on those people: *_staff (a badge), *_guard (a
    peaked cap), *_warden (a cap with a gold band, and a tie), *_cook (a
    chef's hat), *_teacher (a cardigan), *_counsellor (a scarf)."""
    p = Prop("person")
    # Legs and body: a soft pill, a touch wider at the hips.
    p.capsule("outfit", 0.16, 0.2, (0, 0, 0.38), scale=(1, 0.85, 1))
    p.group = "legs"
    p.pivots["legs"] = (0, 0, 0.22)
    for x in (-0.075, 0.075):
        p.capsule("outfit", 0.065, 0.1, (x, 0, 0.14))
        p.ball("shoes", 0.07, (x, 0.025, 0.04), scale=(1, 1.35, 0.7))
    p.group = None
    # Arms hang a little out from the body, hands peeking out.
    p.group = "arms"
    p.pivots["arms"] = (0, 0, 0.5)
    for side in (-1, 1):
        p.capsule("outfit", 0.05, 0.14, (side * 0.19, 0, 0.42), rot=(0, side * 12, 0))
        p.ball("skin", 0.045, (side * 0.215, 0.0, 0.28))
    p.group = None
    # Head, with ears and a soft cap of hair.
    p.ball("skin", 0.165, (0, 0, 0.7), scale=(1, 0.95, 1))
    for side in (-1, 1):
        p.ball("skin", 0.04, (side * 0.16, -0.01, 0.69), scale=(0.6, 1, 1), u=12, v=8)
    p.ball("hair", 0.172, (0, -0.02, 0.73), scale=(1.02, 0.98, 0.88))
    # Staff: a badge on the chest.
    p.group = "staff"
    p.cyl("gold", 0.035, 0.012, (0.07, 0.142, 0.47), bevel=0.004, n=16, rot=(90, 0, 0))
    # Guards: a peaked cap over the hair.
    p.group = "guard"
    p.ball("navy", 0.178, (0, -0.01, 0.75), scale=(1.02, 1.0, 0.72))
    p.cyl("navy", 0.17, 0.04, (0, 0.0, 0.79), bevel=0.015, n=24)
    p.ball("navy", 0.11, (0, 0.15, 0.77), scale=(1.1, 0.8, 0.18), u=16, v=8)
    # The warden: a smarter cap with a gold band, and a tie.
    p.group = "warden"
    p.ball("navy", 0.178, (0, -0.01, 0.75), scale=(1.02, 1.0, 0.72))
    p.cyl("navy", 0.17, 0.04, (0, 0.0, 0.79), bevel=0.015, n=24)
    p.ball("navy", 0.11, (0, 0.15, 0.77), scale=(1.1, 0.8, 0.18), u=16, v=8)
    p.cyl("gold", 0.173, 0.025, (0, 0.0, 0.77), bevel=0.006, n=24)
    p.box("navy", (0.05, 0.02, 0.04), (0, 0.142, 0.55), 0.008, 1)
    p.taper("navy", (0.065, 0.02), (0.04, 0.02), 0.14, (0, 0.145, 0.46), 0.008, 1)
    # Teachers: a camel cardigan with buttons.
    p.group = "teacher"
    p.capsule("knit", 0.168, 0.06, (0, 0, 0.45), scale=(1.0, 0.88, 1.0))
    for z in (0.36, 0.42, 0.48):
        p.ball("cream", 0.013, (-0.03, 0.146, z), scale=(1, 0.5, 1), u=8, v=6)
    # Counsellors: a soft scarf wrapped at the neck with one end hanging.
    p.group = "counsellor"
    ring = [(0.15 * math.cos(a), 0.13 * math.sin(a), 0.565)
            for a in (math.radians(d) for d in range(0, 360, 30))]
    p.tube("scarf", ring + [ring[0], ring[1]], 0.035, 0.03, n=10)
    p.capsule("scarf", 0.035, 0.12, (-0.06, 0.15, 0.45), scale=(1.1, 0.55, 1), rot=(8, 0, 6))
    # Cooks: a soft white chef's hat.
    p.group = "cook"
    p.cyl("sheet", 0.15, 0.1, (0, -0.01, 0.84), bevel=0.03, n=24)
    for x, y in ((-0.07, -0.05), (0.07, -0.05), (0, 0.07)):
        p.ball("sheet", 0.11, (x, y, 0.95), u=16, v=10)
    p.group = None
    # Face: two small dark eyes.
    for side in (-1, 1):
        p.ball("shoes", 0.018, (side * 0.06, 0.148, 0.71), scale=(1, 0.6, 1.3), u=10, v=6)
    return p


# ---------------------------------------------------------------- plants
# Built at size 1: FoliageDef.size scales them.

def tree():
    p = Prop("tree")
    p.cyl("trunk", 0.09, 0.62, (0, 0, 0.31), r2=0.065, bevel=0.02, n=12)
    for loc, r in (((0, 0, 0.95), 0.4), ((0.2, 0.08, 0.82), 0.27), ((-0.18, -0.12, 0.84), 0.28),
                   ((0.05, -0.2, 1.12), 0.24), ((-0.08, 0.18, 1.1), 0.25)):
        p.ball("canopy", r, loc, u=16, v=10)
    return p


def bush():
    p = Prop("bush")
    for loc, r in (((0, 0, 0.3), 0.36), ((0.25, 0.08, 0.22), 0.26), ((-0.24, -0.06, 0.22), 0.27),
                   ((0.05, -0.24, 0.2), 0.24), ((-0.05, 0.25, 0.2), 0.24)):
        p.ball("canopy", r, loc, scale=(1, 1, 0.85), u=16, v=10)
    return p


def flower():
    p = Prop("flower")  # a little clump: three stems with round blooms
    for loc, h in (((0, 0, 0), 0.75), ((0.22, 0.1, 0), 0.6), ((-0.18, 0.14, 0), 0.55)):
        x, y, _ = loc
        p.tube("stem", [(x, y, 0), (x * 1.1, y * 1.1, h)], 0.05, 0, n=6)
        for k in range(5):
            a = k * 2 * math.pi / 5
            p.ball("bloom", 0.11, (x + math.cos(a) * 0.1, y + math.sin(a) * 0.1, h), scale=(1, 1, 0.6), u=10, v=6)
        p.ball("light", 0.07, (x, y, h + 0.02), u=10, v=6)
    for a in (0.3, 2.4, 4.4):
        p.ball("stem", 0.16, (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.05), scale=(1.4, 0.6, 0.35), rot=(0, 0, math.degrees(a)), u=10, v=6)
    return p


# ---------------------------------------------------------------- needs and mood (M2)

def radio():
    p = Prop("radio")  # 0.5 x 0.25, sits on a desk or shelf
    p.box("cream", (0.44, 0.18, 0.22), (0, 0, 0.11), 0.04, 3)
    p.cyl("steel_dark", 0.07, 0.02, (-0.1, -0.09, 0.11), bevel=0.008, n=20, rot=(90, 0, 0))
    p.box("screen", (0.14, 0.02, 0.05), (0.1, -0.09, 0.14), 0.008, 1)
    p.cyl("paint", 0.025, 0.03, (0.1, -0.095, 0.07), bevel=0.008, n=14, rot=(90, 0, 0))
    p.tube("paint", [(-0.16, 0, 0.21), (-0.16, 0, 0.29), (0.16, 0, 0.29), (0.16, 0, 0.21)], 0.014, 0.05, n=8)
    return p


def tv():
    p = Prop("tv")  # 1 x 0.5 television on a low cabinet
    p.box("wood", (0.96, 0.46, 0.5), (0, 0, 0.25), 0.03, 3)
    p.box("paint", (0.88, 0.02, 0.36), (0, -0.23, 0.25), 0.01, 1)
    p.box("paint", (0.2, 0.14, 0.04), (0, 0.02, 0.52), 0.015, 2)
    p.box("paint", (0.06, 0.04, 0.12), (0, 0.04, 0.58), 0.015, 2)
    p.box("rubber", (0.9, 0.08, 0.56), (0, 0.04, 0.92), 0.035, 3)
    p.box("screen", (0.82, 0.02, 0.48), (0, -0.0, 0.92), 0.02, 2)
    p.ball("light", 0.012, (0.39, -0.002, 0.66), u=8, v=6)
    return p


def bookshelf():
    p = Prop("bookshelf")  # 1 x 0.5, 1.4 m tall, back to the wall
    h, w, d = 1.4, 0.96, 0.4
    for x in (-w / 2 + 0.03, w / 2 - 0.03):
        p.box("wood", (0.05, d, h), (x, 0.03, h / 2), 0.015, 2)
    p.box("wood", (w, 0.03, h), (0, d / 2 + 0.015, h / 2), 0.01, 1)
    shelves = (0.04, 0.38, 0.72, 1.06, h - 0.025)
    for z in shelves:
        p.box("wood", (w - 0.04, d, 0.04), (0, 0.03, z), 0.012, 2)
    colours = ("book_a", "book_b", "book_c", "book_d")
    for row, z in enumerate(shelves[:-1]):
        x, k = -0.4, row
        while x < 0.36 - row * 0.08:
            t = 0.05 + ((k * 7) % 3) * 0.012
            ht = 0.22 + ((k * 5) % 4) * 0.02
            p.box(colours[k % 4], (t, 0.26, ht), (x + t / 2, 0.06, z + 0.02 + ht / 2), 0.012, 2)
            x += t + 0.006
            k += 1
        if row == 1:  # a few lying flat at the end
            for i in range(3):
                p.box(colours[(i + 1) % 4], (0.22, 0.26, 0.045), (0.3, 0.06, z + 0.045 + i * 0.047), 0.012, 2)
    return p


def weights_bench():
    p = Prop("weights_bench")  # 1 x 2, bench with a barbell on its rack
    p.box("vinyl", (0.32, 1.2, 0.09), (0, 0.15, 0.44), 0.04, 3)
    for y in (-0.3, 0.6):
        p.tube("paint", [(0, y, 0.4), (0, y, 0.0)], 0.03, 0, n=10)
        p.tube("paint", [(-0.15, y, 0.0), (0.15, y, 0.0)], 0.025, 0, n=10)
    p.tube("paint", [(0, -0.3, 0.2), (0, 0.6, 0.2)], 0.025, 0, n=10)
    for x in (-0.3, 0.3):
        p.tube("paint", [(x, -0.75, 0.0), (x, -0.75, 0.6), (x, -0.62, 0.6)], 0.03, 0.04, n=10)
        p.tube("paint", [(x - 0.12, -0.75, 0.0), (x + 0.12, -0.75, 0.0)], 0.025, 0, n=10)
    p.tube("steel", [(-0.48, -0.65, 0.64), (0.48, -0.65, 0.64)], 0.016, 0, n=10)
    for x in (-0.42, 0.42):
        p.cyl("plates", 0.13, 0.05, (x, -0.65, 0.64), bevel=0.012, n=24, rot=(0, 90, 0))
    return p


def basketball_hoop():
    p = Prop("basketball_hoop")  # 1 x 1, post on a weighted base, hoop over the front
    p.box("paint", (0.7, 0.8, 0.16), (0, 0.05, 0.08), 0.05, 3)
    p.tube("paint", [(0, 0.25, 0.15), (0, 0.25, 2.0), (0, 0.05, 2.15)], 0.045, 0.2, n=14)
    p.box("sheet", (0.8, 0.04, 0.55), (0, 0.02, 2.2), 0.02, 2)
    p.box("ball", (0.28, 0.045, 0.2), (0, 0.0, 2.12), 0.0, 0)
    p.box("sheet", (0.22, 0.05, 0.14), (0, -0.002, 2.12), 0.0, 0)
    ring = [(math.cos(a) * 0.16, -0.2 + math.sin(a) * 0.16, 2.0)
            for a in [k * 2 * math.pi / 24 for k in range(25)]]
    p.tube("ball", ring, 0.012, 0, n=8)
    p.tube("ball", [(0, -0.04, 2.0), (0, 0.0, 2.0)], 0.015, 0, n=8)
    p.ball("ball", 0.12, (0.25, -0.3, 0.12), u=16, v=10)
    return p


def bench():
    p = Prop("bench")  # 1.5 x 0.5 outdoor bench: wooden slats on painted legs
    for x in (-0.6, 0.6):
        p.tube("paint", [(x, -0.18, 0), (x, -0.18, 0.4), (x, 0.2, 0.4), (x, 0.22, 0.72)], 0.025, 0.05, n=10)
        p.tube("paint", [(x, 0.18, 0), (x, 0.18, 0.4)], 0.025, 0, n=10)
    for y in (-0.15, -0.03, 0.09):
        p.box("wood", (1.45, 0.1, 0.035), (0, y, 0.43), 0.012, 2)
    for z in (0.56, 0.68):
        p.box("wood", (1.45, 0.03, 0.09), (0, 0.22 + (z - 0.56) * 0.06, z), 0.012, 2)
    return p


def sink():
    p = Prop("sink", 180)  # 0.5 x 0.5 steel basin on a pedestal, back to the wall
    p.box("steel", (0.44, 0.2, 0.62), (0, -0.14, 0.31), 0.04, 3)
    p.box("steel", (0.46, 0.4, 0.14), (0, -0.03, 0.74), 0.045, 3)
    p.cyl("steel_dark", 0.15, 0.01, (0, 0.0, 0.812), scale=(1, 0.75, 1), bevel=0, n=24)
    p.tube("steel", [(0, -0.2, 0.8), (0, -0.2, 0.9), (0, -0.12, 0.9)], 0.016, 0.03, n=10)
    p.cyl("steel", 0.025, 0.03, (0.1, -0.2, 0.83), bevel=0.008, n=12)
    return p


def rug():
    p = Prop("rug")  # 1.5 x 1, flat
    p.box("rug_edge", (1.46, 0.96, 0.012), (0, 0, 0.006), 0.006, 1)
    p.box("rug", (1.32, 0.82, 0.016), (0, 0, 0.008), 0.006, 1)
    return p


def poster():
    """0.75 x 0.1 footprint against the wall behind, hung with its middle
    about 1 m up: a calm landscape print."""
    p = Prop("poster")
    y, z, w, h = 0.03, 1.0, 0.5, 0.62
    p.box("paper", (w, 0.01, h), (0, y, z), 0.003, 1)
    p.box("poster_a", (w - 0.06, 0.012, h - 0.12), (0, y - 0.001, z + 0.02), 0, 0)
    p.ball("poster_c", 0.06, (0.1, y - 0.004, z + 0.14), scale=(1, 0.1, 1), u=16, v=8)
    p.ball("poster_b", 0.15, (-0.07, y - 0.006, z - 0.17), scale=(1, 0.1, 0.6), u=20, v=8)
    p.ball("poster_b", 0.12, (0.1, y - 0.005, z - 0.18), scale=(1, 0.1, 0.55), u=20, v=8)
    p.box("paper", (w - 0.06, 0.014, 0.1), (0, y - 0.002, z - 0.24), 0, 0)
    return p


def plant_pot():
    p = Prop("plant_pot")  # 0.5 x 0.5 potted plant, about 0.6 m tall
    p.cyl("pot", 0.16, 0.3, (0, 0, 0.15), r2=0.2, bevel=0.02, n=24)
    p.cyl("pot", 0.215, 0.05, (0, 0, 0.3), bevel=0.015, n=24)
    p.cyl("rubber", 0.18, 0.01, (0, 0, 0.32), bevel=0, n=24)
    for loc, r in (((0, 0, 0.46), 0.15), ((0.09, 0.05, 0.4), 0.11), ((-0.08, -0.06, 0.41), 0.11),
                   ((0.02, -0.08, 0.52), 0.1), ((-0.04, 0.08, 0.53), 0.1)):
        p.ball("leaf", r, loc, u=14, v=8)
    return p


def wall_shelf():
    """1 x 0.25 shelf against the wall behind, its top about 1.1 m up,
    with a few books and a mug."""
    p = Prop("wall_shelf")
    z = 1.1
    p.box("wood", (0.95, 0.22, 0.04), (0, 0, z - 0.02), 0.012, 2)
    for x in (-0.35, 0.35):
        p.tube("paint", [(x, 0.11, z - 0.2), (x, 0.11, z - 0.05), (x, -0.06, z - 0.05)], 0.012, 0.03, n=8)
    for k, x in enumerate((-0.38, -0.32, -0.265, -0.21)):
        ht = 0.2 + (k % 2) * 0.03
        p.box(("book_a", "book_b", "book_c", "book_d")[k], (0.05, 0.16, ht), (x, 0.01, z + ht / 2), 0.01, 2)
    p.box("book_d", (0.05, 0.16, 0.19), (-0.15, 0.01, z + 0.09), 0.01, 2, rot=(0, -20, 0))
    p.cyl("sheet", 0.04, 0.09, (0.12, 0.0, z + 0.045), bevel=0.01, n=16)
    p.tube("sheet", [(0.16, 0, z + 0.07), (0.19, 0, z + 0.06), (0.19, 0, z + 0.03), (0.16, 0, z + 0.02)], 0.009, 0.02, n=8)
    p.box("cream", (0.16, 0.1, 0.12), (0.33, 0.01, z + 0.06), 0.02, 2)
    return p



def snack_machine():
    """1 x 1, 1.8 m: a chunky vending machine, front to Godot +z. Rows of
    little coloured snacks behind a glass front (an open window with a
    couple of glints, so the snacks show), keypad on the right and a
    flap at the bottom."""
    p = Prop("snack_machine")
    h, w, d, y = 1.8, 0.9, 0.72, 0.1  # body centre sits back towards the wall
    yf = y - d / 2  # the front face
    p.box("car_red", (w, d, h - 0.06), (0, y, (h - 0.06) / 2 + 0.06), 0.04, 3)
    p.box("steel_dark", (w - 0.06, d - 0.06, 0.06), (0, y, 0.03), 0.01, 1)  # plinth
    p.box("cream", (w - 0.06, 0.02, 0.16), (0, yf - 0.005, h - 0.12), 0.02, 2)  # header sign
    for x in (-0.25, -0.1, 0.05, 0.2):
        p.ball(("food_c", "poster_c", "food_b", "sign_blue")[int((x + 0.25) / 0.15 + 0.1)], 0.035,
               (x, yf - 0.02, h - 0.12), scale=(1, 0.4, 1), u=10, v=6)
    # The window stands proud of the front: a dark inside with shelves of snacks.
    x0, x1, z0, z1 = -0.4, 0.18, 0.5, 1.6
    p.box("screen", (x1 - x0, 0.02, z1 - z0), ((x0 + x1) / 2, yf - 0.13 + 0.12, (z0 + z1) / 2), 0.004, 1)
    for sx in (x0, x1):  # the window's side cheeks and sill
        p.box("car_red", (0.03, 0.13, z1 - z0), (sx, yf - 0.13 + 0.06, (z0 + z1) / 2), 0.008, 1)
    for sz in (z0, z1):
        p.box("car_red", (x1 - x0 + 0.03, 0.13, 0.03), ((x0 + x1) / 2, yf - 0.13 + 0.06, sz), 0.008, 1)
    snacks = ("food_c", "poster_c", "food_b", "sign_blue", "book_b", "book_d", "cream", "uniform")
    rng = random.Random(3)
    rows = 5
    for r in range(rows):
        z = z0 + 0.05 + r * (z1 - z0 - 0.08) / rows
        p.box("steel", (x1 - x0 - 0.02, 0.1, 0.012), ((x0 + x1) / 2, yf - 0.13 + 0.06, z), 0.003, 1)
        for c in range(4):
            x = x0 + 0.08 + c * (x1 - x0 - 0.12) / 3
            mat = snacks[(r * 3 + c * 5) % len(snacks)]
            tall = 0.13 if (r + c) % 3 else 0.1
            for k in range(2):  # two of each, one behind the other
                p.box(mat, (0.1, 0.03, tall), (x, yf - 0.13 + 0.04 + k * 0.035, z + 0.006 + tall / 2),
                      0.01, 2, rot=(0, rng.uniform(-4, 4), 0))
            p.tube("steel", [(x - 0.04, yf - 0.13 + 0.025, z + 0.02), (x + 0.04, yf - 0.13 + 0.025, z + 0.02)], 0.004, 0, n=6)
    for gx, gz in ((-0.25, 1.35), (-0.18, 1.32)):  # glints on the glass
        p.box("glass", (0.025, 0.006, 0.42), (gx, yf - 0.135, gz), 0.002, 1, rot=(0, 25, 0))
    # Keypad and coin slot on the right.
    p.box("steel_dark", (0.17, 0.02, 0.44), (0.32, yf - 0.005, 1.15), 0.015, 2)
    p.box("screen", (0.12, 0.012, 0.05), (0.32, yf - 0.015, 1.31), 0.004, 1)
    p.box("cross", (0.05, 0.014, 0.015), (0.3, yf - 0.017, 1.31), 0.002, 1)
    for r in range(4):
        for c in range(3):
            p.box("steel", (0.03, 0.014, 0.025), (0.285 + c * 0.035, yf - 0.016, 1.22 - r * 0.04), 0.005, 1)
    p.box("steel", (0.012, 0.014, 0.05), (0.32, yf - 0.016, 1.0), 0.003, 1)  # coin slot
    # Collection flap at the bottom.
    p.box("steel_dark", (0.58, 0.03, 0.2), (-0.11, yf - 0.005, 0.28), 0.015, 2)
    p.box("bag", (0.5, 0.032, 0.03), (-0.11, yf - 0.008, 0.35), 0.006, 1)
    return p


# Contraband for the phones-and-brewing work: built big enough to read in a
# hand or on the floor, like the other items.

def mobile_phone():
    p = Prop("mobile_phone")  # a chunky little mobile
    p.box("bag", (0.13, 0.04, 0.24), (0, 0, 0.02 + 0.12), 0.025, 3, rot=(0, 0, 0))
    p.box("screen", (0.1, 0.01, 0.1), (0, -0.02, 0.2), 0.01, 1)
    for r in range(3):
        for c in range(3):
            p.box("steel", (0.022, 0.01, 0.016), (-0.03 + c * 0.03, -0.021, 0.1 - r * 0.026), 0.004, 1)
    p.cyl("bag", 0.012, 0.06, (0.045, 0.0, 0.28), bevel=0.004, n=8)  # stubby aerial
    return p


def sweets():
    p = Prop("sweets")  # a brown paper bag spilling wrapped sweets
    p.taper("crate", (0.14, 0.1), (0.17, 0.12), 0.18, (0, 0.02, 0.09), 0.02, 2)
    p.taper("crate", (0.17, 0.12), (0.12, 0.05), 0.05, (0, 0.02, 0.205), 0.015, 1)
    for k, (x, y, mat) in enumerate(((-0.12, -0.08, "food_c"), (-0.04, -0.12, "poster_c"),
                                     (0.06, -0.1, "food_b"), (0.13, -0.05, "sign_blue"))):
        p.ball(mat, 0.03, (x, y, 0.025), scale=(1.3, 1, 1), rot=(0, 0, k * 40), u=10, v=6)
        for side in (-1, 1):  # twisted wrapper ends
            a = math.radians(k * 40)
            p.ball(mat, 0.016, (x + side * 0.045 * math.cos(a), y + side * 0.045 * math.sin(a), 0.025),
                   scale=(1, 1.4, 0.6), rot=(0, 0, k * 40), u=8, v=6)
    return p


def fruit():
    p = Prop("fruit")  # an orange and an apple
    p.ball("ball", 0.085, (-0.06, 0, 0.08), u=16, v=10)
    p.ball("food_c", 0.08, (0.08, 0.03, 0.075), scale=(1, 1, 0.92), u=16, v=10)
    p.tube("trunk_dark", [(0.08, 0.03, 0.14), (0.085, 0.03, 0.175)], 0.008, 0, n=6)
    p.ball("leaf", 0.03, (0.105, 0.03, 0.17), scale=(1.4, 0.5, 0.6), rot=(0, -20, 0), u=10, v=6)
    return p


def fizzy_pop():
    p = Prop("fizzy_pop")  # a cloudy home-brew in an old plastic bottle
    p.cyl("pop", 0.07, 0.2, (0, 0, 0.1), bevel=0.03, segs=3, n=20)
    p.cyl("pop", 0.07, 0.08, (0, 0, 0.24), r2=0.025, bevel=0.01, n=20)
    p.cyl("sheet", 0.072, 0.07, (0, 0, 0.11), bevel=0.005, n=20)  # label
    p.cyl("food_c", 0.028, 0.035, (0, 0, 0.295), bevel=0.008, n=14)  # cap
    for x, z in ((0.03, 0.2), (-0.02, 0.16), (0.01, 0.23)):
        p.ball("sheet", 0.008, (x, -0.066, z), u=6, v=4)  # bubbles
    return p


def meeting_table(name="meeting_table", top="wood", legs="paint"):
    """2 x 1 oval table for meetings, top at 0.53 like the desks, on two
    pedestals so chairs fit all the way round."""
    p = Prop(name)
    p.cyl(top, 0.45, 0.05, (0, 0, 0.505), bevel=0.02, segs=3, n=48, scale=(2.1, 1, 1))
    for x in (-0.5, 0.5):
        p.tube(legs, [(x, 0, 0.03), (x, 0, 0.48)], 0.04, 0, n=12)
        p.box(legs, (0.08, 0.6, 0.04), (x, 0, 0.02), 0.015, 2)
    p.box(legs, (1.0, 0.05, 0.04), (0, 0, 0.46), 0.012, 1)
    return p


# ---------------------------------------------------------------- prisoner life (M11)

def easel():
    """1 x 1 painting easel, about 1.15 m: an A-frame holding a canvas with
    a half-done landscape, a paint palette on the ledge and a pot of
    brushes at its foot. The painter stands at the front (Godot +z)."""
    p = Prop("easel")
    for x in (-0.24, 0.24):
        p.tube("pine", [(x, -0.06, 0), (x * 0.35, 0.0, 1.15)], 0.018, 0, n=8)
    p.tube("pine", [(0, 0.3, 0), (0, 0.01, 1.0)], 0.016, 0, n=8)  # back leg
    p.box("pine", (0.5, 0.06, 0.03), (0, -0.07, 0.52), 0.008, 1)  # ledge
    p.box("pine", (0.12, 0.03, 0.03), (0, -0.03, 1.05), 0.006, 1)  # top clamp
    cy, cz, w, h = -0.06, 0.78, 0.46, 0.5
    tilt = (-6, 0, 0)
    p.box("sheet", (w, 0.025, h), (0, cy, cz), 0.006, 1, rot=tilt)  # canvas
    p.box("poster_a", (w - 0.06, 0.006, h * 0.45), (0, cy - 0.015, cz + h * 0.2), 0.002, 1, rot=tilt)
    p.ball("poster_b", 0.15, (-0.06, cy - 0.016, cz - 0.04), scale=(1.2, 0.05, 0.55), rot=tilt, u=16, v=6)
    p.ball("poster_c", 0.045, (0.13, cy - 0.016, cz + 0.15), scale=(1, 0.08, 1), rot=tilt, u=12, v=6)
    # The palette with blobs of paint, and a jar of brushes on the floor.
    p.cyl("pine", 0.1, 0.01, (0.1, -0.1, 0.545), bevel=0.003, n=18, scale=(1.3, 0.8, 1))
    for k, mat in enumerate(("food_c", "poster_c", "sign_blue", "leaf", "sheet")):
        a = 0.6 + k * 0.9
        p.ball(mat, 0.016, (0.1 + 0.08 * math.cos(a), -0.1 + 0.05 * math.sin(a), 0.553),
               scale=(1, 1, 0.5), u=8, v=6)
    p.cyl("glass", 0.05, 0.12, (-0.3, -0.25, 0.06), bevel=0.01, n=16)
    for k, mat in enumerate(("food_c", "sign_blue", "leaf")):
        x = -0.32 + k * 0.02
        p.tube("pine", [(x, -0.25, 0.04), (x + (k - 1) * 0.03, -0.25 + (k - 1) * 0.01, 0.24)], 0.007, 0, n=6)
        p.ball(mat, 0.012, (x + (k - 1) * 0.033, -0.25 + (k - 1) * 0.011, 0.25), scale=(1, 1, 1.6), u=8, v=6)
    return p


def piano():
    """2 x 1 upright piano against the wall behind (Godot -z), keys about
    0.45 up, with a padded stool in front for the player."""
    p = Prop("piano")
    w, d, h, yb = 1.4, 0.42, 0.88, 0.25  # body centre towards the wall
    yf = yb - d / 2
    p.box("walnut", (w, d, h), (0, yb, h / 2), 0.03, 3)
    p.box("walnut", (w + 0.04, d + 0.04, 0.04), (0, yb, h + 0.01), 0.015, 2)  # lid
    for x in (-w / 2 + 0.04, w / 2 - 0.04):  # cheeks and toes
        p.box("walnut", (0.07, 0.3, 0.42), (x, yf - 0.12, 0.27), 0.02, 2)
        p.box("walnut", (0.08, 0.08, 0.05), (x, yf - 0.24, 0.025), 0.015, 1)
    p.box("walnut", (w - 0.14, 0.22, 0.04), (0, yf - 0.1, 0.42), 0.01, 1)  # keybed
    p.box("sheet", (w - 0.16, 0.13, 0.025), (0, yf - 0.14, 0.45), 0.004, 1)  # white keys
    for k in range(36):
        if k % 7 in (2, 6):
            continue
        x = -(w - 0.2) / 2 + (k + 0.5) * (w - 0.2) / 36
        p.box("bag", (0.018, 0.075, 0.022), (x, yf - 0.115, 0.47), 0.004, 1)
    p.box("walnut", (w - 0.14, 0.03, 0.12), (0, yf - 0.015, 0.53), 0.01, 1)  # fallboard
    p.box("walnut", (0.5, 0.03, 0.04), (0, yf - 0.03, 0.62), 0.008, 1)  # music rest
    p.box("paper", (0.36, 0.012, 0.2), (0, yf - 0.025, 0.72), 0.003, 1, rot=(-10, 0, 0))
    for z in (0.66, 0.7, 0.74, 0.78):
        p.box("bag", (0.3, 0.004, 0.004), (0, yf - 0.034, z), 0, 0, rot=(-10, 0, 0))
    for x in (-0.12, 0.12):  # pedals
        p.box("gold", (0.04, 0.08, 0.015), (x, yf - 0.05, 0.03), 0.005, 1)
    # Stool.
    p.box("vinyl", (0.6, 0.3, 0.06), (0, -0.25, 0.31), 0.025, 3)
    for x in (-0.25, 0.25):
        for y in (-0.36, -0.14):
            p.tube("walnut", [(x, y, 0), (x, y, 0.29)], 0.018, 0, n=8)
    return p


def knitting_chair():
    """1 x 1: a cosy armchair with a crocheted blanket over its back and a
    wicker basket of wool beside it, needles poking out."""
    p = Prop("knitting_chair")
    _armchair(p, "cushion", dx=-0.1, dy=0.08)
    p.box("book_b", (0.5, 0.06, 0.3), (-0.1, 0.36, 0.46), 0.03, 3, rot=(-8, 0, 0))  # blanket
    for k in range(4):
        p.box("poster_c", (0.5, 0.062, 0.025), (-0.1, 0.36, 0.36 + k * 0.07), 0.01, 1, rot=(-8, 0, 0))
    bx, by = 0.36, -0.2
    p.cyl("crate", 0.12, 0.16, (bx, by, 0.08), r2=0.135, bevel=0.02, n=20)
    p.tube("crate", [(bx - 0.12, by, 0.16), (bx, by, 0.27), (bx + 0.12, by, 0.16)], 0.012, 0.08, n=8)
    for k, mat in enumerate(("food_c", "sign_blue", "poster_c")):
        a = k * 2.1
        p.ball(mat, 0.06, (bx + 0.05 * math.cos(a), by + 0.05 * math.sin(a), 0.18), u=12, v=8)
    for dx in (-0.02, 0.02):
        p.tube("steel", [(bx + dx, by, 0.15), (bx + dx + 0.05, by - 0.03, 0.33)], 0.005, 0, n=6)
    return p


def till():
    """1 x 1 shop counter with a till on top, the shopkeeper behind at the
    back (Godot -z) and customers in front."""
    p = Prop("till")
    p.box("pine", (0.95, 0.5, 0.05), (0, -0.05, 0.505), 0.015, 2)  # counter top
    p.box("painted", (0.9, 0.45, 0.48), (0, -0.05, 0.24), 0.02, 2)
    p.box("pine", (0.9, 0.02, 0.06), (0, -0.28, 0.24), 0.008, 1)  # front rail
    # The till: a chunky cream box with a little display and a drawer.
    tx = 0.18
    p.box("cream", (0.3, 0.26, 0.1), (tx, 0.0, 0.58), 0.02, 2)
    p.taper("cream", (0.3, 0.16), (0.3, 0.1), 0.08, (tx, 0.03, 0.67), 0.015, 1)
    for r in range(3):
        for c in range(4):
            p.box("steel_dark", (0.03, 0.025, 0.012), (tx - 0.075 + c * 0.05, 0.02 + r * 0.03, 0.715), 0.004, 1)
    p.box("cream", (0.1, 0.03, 0.08), (tx, 0.1, 0.76), 0.01, 1)  # display post
    p.box("screen", (0.09, 0.012, 0.05), (tx, 0.08, 0.765), 0.004, 1)
    p.box("cross", (0.05, 0.014, 0.012), (tx, 0.075, 0.77), 0.002, 1)
    p.box("paper", (0.06, 0.012, 0.06), (tx + 0.11, -0.05, 0.665), 0.003, 1, rot=(20, 0, 0))  # receipt
    # A jar of sweets and a little stack of choc bars for sale.
    p.cyl("glass", 0.07, 0.16, (-0.25, -0.12, 0.61), bevel=0.02, n=18)
    p.cyl("food_c", 0.075, 0.03, (-0.25, -0.12, 0.705), bevel=0.01, n=18)
    for k, mat in enumerate(("food_c", "poster_c", "food_b", "sign_blue", "poster_c")):
        a = k * 1.3
        p.ball(mat, 0.025, (-0.25 + 0.035 * math.cos(a), -0.12 + 0.035 * math.sin(a), 0.56 + (k % 2) * 0.04), u=8, v=6)
    for k in range(3):
        p.box(("book_b", "sign_blue", "food_c")[k], (0.15, 0.06, 0.02), (-0.05, -0.18, 0.54 + k * 0.021), 0.006, 1,
              rot=(0, 0, k * 8))
    return p


def pet_cage():
    """1 x 1 wooden hutch on legs, about 0.95 m: a wire front, a sloping roof,
    straw on the floor and a water bottle. Front to Godot +z."""
    p = Prop("pet_cage")
    z0, z1 = 0.4, 0.82
    for x in (-0.4, 0.4):
        for y in (-0.3, 0.3):
            p.box("crate", (0.06, 0.06, z0), (x, y, z0 / 2), 0.012, 2)
    p.box("crate", (0.88, 0.68, 0.04), (0, 0, z0), 0.012, 2)  # floor
    p.box("crate", (0.88, 0.04, z1 - z0), (0, 0.32, (z0 + z1) / 2), 0.012, 2)  # back
    for x in (-0.42, 0.42):
        p.box("crate", (0.04, 0.68, z1 - z0), (x, 0, (z0 + z1) / 2), 0.012, 2)
    p.box("crate", (0.3, 0.6, z1 - z0), (0.27, 0.02, (z0 + z1) / 2), 0.012, 2)  # bedroom end
    p.cyl("dark", 0.07, 0.02, (0.27, -0.29, z0 + 0.12), bevel=0.0, n=16, rot=(90, 0, 0), scale=(1, 1.3, 1))
    p.box("pine", (0.98, 0.8, 0.04), (0, 0.0, z1 + 0.06), 0.015, 2, rot=(-8, 0, 0))  # roof
    p.box("sheet", (0.5, 0.6, 0.02), (-0.15, 0.0, z0 + 0.03), 0.01, 1)  # straw
    for k in range(8):
        x = -0.38 + k * 0.08
        p.tube("galv", [(x, -0.32, z0 + 0.02), (x, -0.32, z1)], 0.005, 0, n=6)
    for z in (z0 + 0.14, z0 + 0.28):
        p.tube("galv", [(-0.4, -0.32, z), (0.1, -0.32, z)], 0.005, 0, n=6)
    p.box("crate", (0.56, 0.04, 0.04), (-0.13, -0.33, z1 - 0.01), 0.008, 1)
    p.cyl("glass", 0.025, 0.14, (-0.36, 0.28, z0 + 0.25), bevel=0.008, n=12)  # water bottle
    p.tube("steel", [(-0.36, 0.28, z0 + 0.18), (-0.36, 0.24, z0 + 0.12)], 0.005, 0, n=6)
    return p


def visit_table():
    """2 x 1 visiting table bolted down, top at 0.53 with a low divider down
    the middle: a prisoner on one long side, visitors on the other."""
    p = Prop("visit_table")
    p.box("wood", (1.85, 0.8, 0.05), (0, 0, 0.505), 0.025, 3)
    p.box("paint", (1.75, 0.04, 0.08), (0, 0, 0.57), 0.015, 2)  # divider
    for x in (-0.6, 0.6):
        p.tube("paint", [(x, 0, 0), (x, 0, 0.48)], 0.04, 0, n=12)
        p.box("paint", (0.1, 0.5, 0.03), (x, 0, 0.015), 0.012, 2)
    return p


# Animals: built at size 1 and chunky like the people, facing Godot +z,
# origin under the middle of the body.

def _eyes(p, x, y, z, r=0.012):
    for side in (-1, 1):
        p.ball("shoes", r, (side * x, y, z), scale=(1, 0.6, 1.2), u=8, v=6)


def cat():
    p = Prop("cat")  # a sitting-up ginger cat, about 0.3 m
    p.ball("fur_ginger", 0.1, (0, 0.02, 0.1), scale=(0.9, 1.1, 1.05), u=16, v=10)
    p.ball("fur_ginger", 0.085, (0, -0.06, 0.24), u=16, v=10)
    for side in (-1, 1):
        p.cyl("fur_ginger", 0.03, 0.06, (side * 0.05, -0.06, 0.32), r2=0.0, bevel=0.0, n=8)
        p.capsule("fur_ginger", 0.025, 0.04, (side * 0.04, -0.09, 0.03), scale=(1, 1.4, 0.8))  # front paws
    p.ball("cream", 0.04, (0, -0.13, 0.22), scale=(1.1, 0.6, 0.8), u=12, v=8)  # muzzle
    p.ball("pot", 0.01, (0, -0.15, 0.235), u=8, v=6)  # nose
    _eyes(p, 0.035, -0.135, 0.26)
    p.tube("fur_ginger", [(0.07, 0.1, 0.03), (0.15, 0.04, 0.03), (0.14, -0.06, 0.04)], 0.022, 0.06, n=10)
    p.ball("cream", 0.06, (0, -0.05, 0.13), scale=(1, 0.7, 1.3), u=12, v=8)  # pale chest
    return p


def rabbit():
    p = Prop("rabbit")  # a round grey-brown bunny, about 0.32 m to the ear tips
    p.ball("fur_rabbit", 0.1, (0, 0.03, 0.09), scale=(0.95, 1.2, 0.9), u=16, v=10)
    p.ball("fur_rabbit", 0.07, (0, -0.08, 0.16), u=16, v=10)
    for side in (-1, 1):
        p.capsule("fur_rabbit", 0.022, 0.09, (side * 0.03, -0.06, 0.27), scale=(1, 0.6, 1), rot=(-10, side * 12, 0))
        p.capsule("cream", 0.012, 0.07, (side * 0.03, -0.072, 0.27), scale=(1, 0.4, 1), rot=(-10, side * 12, 0))
        p.capsule("fur_rabbit", 0.025, 0.03, (side * 0.04, -0.07, 0.025), scale=(1, 1.4, 0.7))
    p.ball("sheet", 0.04, (0, 0.17, 0.09), u=12, v=8)  # tail
    p.ball("pot", 0.01, (0, -0.145, 0.16), u=8, v=6)
    _eyes(p, 0.035, -0.12, 0.18)
    return p


def budgie():
    p = Prop("budgie")  # a little green budgie, about 0.16 m, perched upright
    p.ball("budgie", 0.045, (0, 0.0, 0.06), scale=(1, 1.1, 1.3), u=14, v=10)
    p.ball("poster_c", 0.035, (0, -0.015, 0.12), u=14, v=10)  # yellow head
    p.cyl("pot", 0.012, 0.025, (0, -0.048, 0.115), r2=0.0, bevel=0.0, n=8, rot=(110, 0, 0))  # beak
    _eyes(p, 0.02, -0.04, 0.13, r=0.007)
    p.taper("sign_blue", (0.02, 0.01), (0.04, 0.012), 0.09, (0, 0.06, 0.03), 0.004, 1)  # tail
    for side in (-1, 1):
        p.ball("budgie", 0.03, (side * 0.04, 0.01, 0.065), scale=(0.35, 1.2, 1.1), u=10, v=8)  # wings
        p.tube("pot", [(side * 0.015, 0, 0.02), (side * 0.015, -0.01, 0.0)], 0.005, 0, n=6)
    return p


def hen():
    p = Prop("hen")  # a plump white hen, about 0.3 m to the comb
    p.ball("sheet", 0.1, (0, 0.02, 0.12), scale=(0.85, 1.15, 0.9), u=16, v=10)
    p.ball("sheet", 0.06, (0, -0.08, 0.22), u=14, v=10)
    p.taper("sheet", (0.08, 0.04), (0.04, 0.02), 0.1, (0, 0.13, 0.17), 0.02, 2)  # tail
    for k, (y, z, r) in enumerate(((-0.1, 0.285, 0.018), (-0.075, 0.29, 0.022), (-0.05, 0.28, 0.018))):
        p.ball("food_c", r, (0, y, z), scale=(0.5, 1, 1), u=10, v=6)  # comb
    p.ball("food_c", 0.014, (0, -0.135, 0.19), scale=(0.6, 0.8, 1.4), u=8, v=6)  # wattle
    p.cyl("uniform", 0.016, 0.04, (0, -0.15, 0.215), r2=0.0, bevel=0.0, n=8, rot=(90, 0, 0))  # beak
    _eyes(p, 0.04, -0.115, 0.235, r=0.01)
    for side in (-1, 1):
        p.ball("sheet", 0.06, (side * 0.075, 0.03, 0.13), scale=(0.35, 1.2, 0.8), u=12, v=8)  # wings
        x = side * 0.04
        p.tube("uniform", [(x, 0.0, 0.05), (x, 0.0, 0.0)], 0.008, 0, n=6)
        for a in (-25, 0, 25):
            t = math.radians(a)
            p.tube("uniform", [(x, 0.0, 0.004), (x + 0.03 * math.sin(t), -0.03 * math.cos(t), 0.004)], 0.005, 0, n=6)
    return p


def therapy_dog():
    """A friendly golden dog in a little blue therapy vest, about 0.45 m."""
    p = Prop("therapy_dog")
    p.capsule("fur_dog", 0.1, 0.16, (0, 0.03, 0.22), rot=(90, 0, 0))
    p.ball("fur_dog", 0.09, (0, -0.2, 0.36), u=16, v=10)
    p.ball("fur_dog", 0.05, (0, -0.28, 0.33), scale=(0.9, 1.2, 0.8), u=12, v=8)  # snout
    p.ball("shoes", 0.018, (0, -0.335, 0.345), u=8, v=6)  # nose
    _eyes(p, 0.04, -0.27, 0.39, r=0.013)
    for side in (-1, 1):
        p.capsule("walnut", 0.03, 0.06, (side * 0.085, -0.19, 0.33), scale=(0.6, 1, 1), rot=(0, side * 15, 0))  # ears
        for y in (-0.1, 0.15):
            p.capsule("fur_dog", 0.035, 0.12, (side * 0.06, y, 0.1))
    p.capsule("fur_dog", 0.028, 0.1, (0, 0.27, 0.3), rot=(-50, 0, 0))  # tail, up and wagging
    p.capsule("sign_blue", 0.104, 0.1, (0, 0.02, 0.225), rot=(90, 0, 0), scale=(1, 1, 1))  # vest
    p.box("sheet", (0.012, 0.06, 0.02), (0.105, 0.02, 0.25), 0.004, 1)
    p.box("sheet", (0.012, 0.02, 0.06), (0.105, 0.02, 0.25), 0.004, 1)
    p.box("sheet", (0.012, 0.06, 0.02), (-0.105, 0.02, 0.25), 0.004, 1)
    p.box("sheet", (0.012, 0.02, 0.06), (-0.105, 0.02, 0.25), 0.004, 1)
    return p


# ---------------------------------------------------------------- arrivals (M12)
# Front towards Godot -z (Blender +Y).

def ferry():
    """A small passenger ferry, 1.6 m wide by 4 m long, bow to Godot -z.
    The origin is at the waterline under its middle; the hull reaches
    0.3 m below."""
    p = Prop("ferry")
    W, L = 1.6, 4.0
    body = L - W * 0.6
    p.box("lorry", (W, body, 0.6), (0, -W * 0.3, 0.0), 0.12, 3)
    p.cyl("lorry", W / 2, 0.58, (0, body / 2 - W * 0.3, 0.0), bevel=0.1, segs=3, n=32, scale=(1, 1.2, 1))  # bow
    p.box("car_red", (W + 0.02, body - 0.1, 0.12), (0, -W * 0.3, -0.2), 0.05, 2)  # below the waterline
    p.box("blue_stripe", (W + 0.03, body - 0.2, 0.08), (0, -W * 0.3, 0.12), 0.03, 2)
    p.box("pine", (W - 0.14, body - 0.2, 0.04), (0, -W * 0.3, 0.29), 0.01, 1)  # deck
    # Cabin with windows, and a blue roof.
    cy = -0.3
    p.box("cream", (W - 0.3, 1.6, 0.62), (0, cy, 0.6), 0.06, 3)
    for side in (-1, 1):
        for k in range(4):
            p.box("glass", (0.02, 0.26, 0.2), (side * (W - 0.3) / 2, cy - 0.57 + k * 0.38, 0.7), 0.01, 1)
    p.box("glass", (W - 0.5, 0.02, 0.22), (0, cy + 0.8, 0.72), 0.01, 1)  # front window
    p.box("sign_blue", (W - 0.2, 1.75, 0.06), (0, cy, 0.94), 0.025, 2)
    p.cyl("steel_dark", 0.08, 0.3, (0, cy - 0.5, 1.1), bevel=0.02, n=16)  # funnel
    p.cyl("car_red", 0.083, 0.08, (0, cy - 0.5, 1.2), bevel=0.01, n=16)
    # Rails round the open front and back decks, and a lifebuoy.
    for side in (-1, 1):
        x = side * (W / 2 - 0.08)
        p.tube("steel", [(x, cy + 0.85, 0.5), (x, 1.2, 0.5), (side * 0.3, 1.75, 0.5)], 0.012, 0.15, n=6)
        p.tube("steel", [(x, cy - 0.85, 0.5), (x, -1.65, 0.5)], 0.012, 0.0, n=6)
        for y in (0.9, 1.2, -1.2, -1.5):
            p.tube("steel", [(x, y, 0.31), (x, y, 0.5)], 0.01, 0, n=6)
    p.tube("steel", [(-W / 2 + 0.08, -1.65, 0.5), (W / 2 - 0.08, -1.65, 0.5)], 0.012, 0, n=6)
    ring = [(0.16 * math.cos(a), 0, 0.16 * math.sin(a)) for a in (math.radians(d) for d in range(0, 360, 30))]
    p.tube("uniform", [(x, cy - 0.81, z + 0.6) for x, _, z in ring + ring[:2]], 0.03, 0.03, n=8)
    return p


def helicopter():
    """A small blue helicopter, nose to Godot -z, 3 m rotor span, about
    1.5 m to the rotor head, sitting on skids."""
    p = Prop("helicopter")
    p.ball("sign_blue", 0.55, (0, 0.35, 0.72), scale=(0.8, 1.2, 0.85), u=24, v=14)  # cabin
    p.ball("glass", 0.42, (0, 0.78, 0.8), scale=(0.85, 0.75, 0.75), u=20, v=12)  # bubble
    for side in (-1, 1):
        p.box("glass", (0.02, 0.3, 0.22), (side * 0.43, 0.3, 0.85), 0.01, 1)  # side windows
    p.capsule("sign_blue", 0.11, 1.5, (0, -0.95, 0.85), scale=(1, 1, 0.9), rot=(90, 0, 0))  # tail boom
    p.taper("sign_blue", (0.06, 0.25), (0.04, 0.12), 0.45, (0, -1.75, 1.0), 0.02, 2)  # fin
    p.cyl("steel_dark", 0.025, 0.12, (0.06, -1.78, 1.05), bevel=0.0, n=10, rot=(0, 90, 0))
    for k in (0, 90):
        p.box("steel_dark", (0.03, 0.5, 0.012), (0.12, -1.78, 1.05), 0.005, 1, rot=(k, 0, 0))  # tail rotor
    p.box("cream", (0.04, 0.6, 0.06), (0, -1.0, 0.88), 0.01, 1)  # stripe along the boom
    for side in (-1, 1):  # skids
        x = side * 0.42
        p.tube("galv", [(x, -0.45, 0.04), (x, 0.85, 0.04), (x, 1.0, 0.13)], 0.03, 0.12, n=10)
        for y in (-0.15, 0.6):
            p.tube("galv", [(x, y, 0.04), (side * 0.25, y, 0.35)], 0.025, 0, n=8)
    p.cyl("steel_dark", 0.06, 0.25, (0, 0.2, 1.33), bevel=0.02, n=14)  # mast
    p.cyl("steel_dark", 0.1, 0.06, (0, 0.2, 1.47), bevel=0.02, n=16)
    for a in (20, 110):
        p.box("rubber", (3.0, 0.12, 0.025), (0, 0.2, 1.5), 0.01, 1, rot=(0, 0, a))  # main rotor
    return p


def jetty():
    """2 x 1 m wooden jetty deck on posts, origin at the middle of its
    footprint at bank level; the deck sits 0.2 m up and the posts reach
    0.5 m below into the water."""
    p = Prop("jetty")
    for k in range(9):
        x = -0.9 + k * 0.225
        p.box("pine", (0.2, 0.98, 0.05), (x, 0, 0.18), 0.012, 2)
    for y in (-0.42, 0.42):
        p.box("crate", (1.98, 0.08, 0.1), (0, y, 0.1), 0.015, 2)  # bearers
    for x in (-0.9, 0.0, 0.9):
        for y in (-0.46, 0.46):
            p.cyl("crate", 0.06, 0.82, (x, y, -0.13), bevel=0.02, n=12)
            p.cyl("crate", 0.065, 0.03, (x, y, 0.29), bevel=0.012, n=12)  # post tops
    p.cyl("steel_dark", 0.05, 0.1, (0.75, 0.3, 0.26), bevel=0.015, n=12)  # bollard
    p.cyl("steel_dark", 0.07, 0.025, (0.75, 0.3, 0.32), bevel=0.01, n=12)
    p.tube("rope", [(0.75, 0.3, 0.28), (0.6, 0.35, 0.22), (0.45, 0.3, 0.215)], 0.015, 0.05, n=8)
    return p


# ---------------------------------------------------------------- office paperwork

def filing_cabinet():
    """1 x 1 tile, 1.3 m: two four-drawer cabinets side by side against the
    wall behind, drawers to the front (Godot +z). One drawer is left a
    little open with folders peeking out, and a box file sits on top."""
    p = Prop("filing_cabinet")
    h, d, yb = 1.3, 0.6, 0.18  # height, depth, centre (towards the wall)
    for x in (-0.23, 0.23):
        p.box("paint", (0.44, d, h - 0.03), (x, yb, (h - 0.03) / 2 + 0.03), 0.015, 2)
        p.box("steel_dark", (0.42, d - 0.04, 0.03), (x, yb, 0.015), 0.006, 1)  # plinth
        for k in range(4):
            z = 0.03 + (k + 0.5) * (h - 0.06) / 4
            out = 0.12 if (x > 0 and k == 1) else 0.0
            yf = yb - d / 2 - 0.006 - out
            p.box("paint", (0.4, 0.024, 0.29), (x, yf, z), 0.012, 2)
            p.box("steel", (0.16, 0.03, 0.025), (x, yf - 0.02, z + 0.06), 0.01, 2)  # handle
            p.box("steel", (0.09, 0.02, 0.045), (x, yf - 0.012, z + 0.11), 0.004, 1)  # label holder
            p.box("paper", (0.075, 0.022, 0.03), (x, yf - 0.014, z + 0.11), 0.002, 1)
            if out:
                for j, (mat, tilt) in enumerate((("book_d", -6), ("book_a", 4), ("cream", -2), ("book_c", 7))):
                    p.box(mat, (0.34, 0.012, 0.05), (x, yf + 0.02 + j * 0.028, z + 0.16), 0.004, 1,
                          rot=(tilt, 0, 0))
    p.box("book_b", (0.08, 0.3, 0.26), (-0.32, yb + 0.05, h + 0.13), 0.012, 2)  # box file
    p.cyl("steel", 0.02, 0.012, (-0.32, yb - 0.1, h + 0.19), bevel=0.003, n=12, rot=(90, 0, 0))
    p.box("cream", (0.3, 0.22, 0.03), (0.15, yb + 0.02, h + 0.015), 0.006, 1, rot=(0, 0, 6))
    return p


def _paper_stack(p, layers, lean=0.0, wobble=1.0, seed=1):
    """Bundles of A4 piled up from the floor of the prop. `layers` is a list
    of (material, thickness); each bundle is nudged and turned a little,
    and `lean` pushes every one further along x than the last."""
    rng = random.Random(seed)
    z = 0.0
    for i, (mat, th) in enumerate(layers):
        dx = lean * i + rng.uniform(-0.008, 0.008) * wobble
        dy = rng.uniform(-0.008, 0.008) * wobble
        turn = rng.uniform(-5, 5) * wobble
        p.box(mat, (0.29, 0.205, th), (dx, dy, z + th / 2), min(0.004, th / 3), 1, rot=(0, 0, turn))
        z += th
    return z


PAPER = ("paper", "sheet")


def paper_stack_small():
    """0.3 x 0.22, 0.06 m: a tidy little pile."""
    p = Prop("paper_stack_small")
    _paper_stack(p, [(PAPER[i % 2], 0.015) for i in range(4)], seed=3)
    return p


def paper_stack_tall():
    """0.3 x 0.22, 0.16 m: a pile with a couple of folders in it and a
    bulldog clip on top."""
    p = Prop("paper_stack_tall")
    layers = [("paper", 0.025), ("book_a", 0.012), ("sheet", 0.03), ("paper", 0.025),
              ("book_d", 0.012), ("sheet", 0.028), ("paper", 0.028)]
    top = _paper_stack(p, layers, wobble=1.6, seed=5)
    p.box("steel_dark", (0.05, 0.03, 0.02), (0.0, -0.1, top - 0.004), 0.005, 1)
    p.tube("steel", [(-0.015, -0.1, top + 0.005), (-0.015, -0.07, top + 0.03)], 0.003, 0, n=6)
    p.tube("steel", [(0.015, -0.1, top + 0.005), (0.015, -0.07, top + 0.03)], 0.003, 0, n=6)
    return p


def paper_stack_teetering():
    """0.3 x 0.22, 0.32 m: far too much paper, piled crooked and leaning,
    with a sheet sliding off the top."""
    p = Prop("paper_stack_teetering")
    mats = ("paper", "sheet", "paper", "book_c", "sheet", "paper", "sheet", "book_a",
            "paper", "sheet", "paper", "cream", "sheet", "paper")
    layers = [(m, 0.012 if m.startswith("book") or m == "cream" else 0.024) for m in mats]
    top = _paper_stack(p, layers, lean=0.0045, wobble=3.0, seed=11)
    p.box("sheet", (0.29, 0.205, 0.003), (0.1, 0.01, top + 0.012), 0.001, 1, rot=(0, -12, 18))
    return p


# ---------------------------------------------------------------- reform and release (M8)

def class_desk():
    """1 x 0.5 school desk, top at 0.5, a pencil groove along the front
    (the sitter's side, Godot +z) and a wire book tray under the back."""
    p = Prop("class_desk")
    p.box("wood", (0.95, 0.46, 0.04), (0, 0, 0.48), 0.015, 2)
    p.box("steel_dark", (0.5, 0.025, 0.006), (0, -0.19, 0.5), 0.003, 1)  # pencil groove
    for x in (-0.43, 0.43):
        for y in (-0.19, 0.19):
            p.tube("paint", [(x, y, 0), (x, y, 0.46)], 0.018, 0, n=10)
            p.ball("rubber", 0.022, (x, y, 0.012), scale=(1, 1, 0.6), u=8, v=6)
        p.tube("paint", [(x, -0.19, 0.12), (x, 0.19, 0.12)], 0.012, 0, n=8)
    p.box("paint", (0.86, 0.22, 0.012), (0, 0.08, 0.36), 0.004, 1)  # book tray
    p.box("paint", (0.86, 0.012, 0.06), (0, -0.03, 0.39), 0.004, 1)
    p.box("book_a", (0.22, 0.17, 0.03), (-0.2, 0.08, 0.38), 0.008, 1)
    p.box("book_c", (0.2, 0.16, 0.025), (-0.19, 0.09, 0.405), 0.008, 1, rot=(0, 0, 8))
    return p


def whiteboard():
    """1.5 x 0.25 whiteboard on two legs with feet, about 1.1 m tall,
    writing on the front (Godot +z)."""
    p = Prop("whiteboard")
    z0, z1, w = 0.42, 1.08, 1.36
    for x in (-0.7, 0.7):
        p.tube("steel_dark", [(x, 0, 0.03), (x, 0, z1)], 0.02, 0, n=10)
        p.box("steel_dark", (0.05, 0.24, 0.03), (x, 0, 0.015), 0.01, 1)
        for y in (-0.11, 0.11):
            p.ball("rubber", 0.022, (x, y, 0.012), scale=(1, 1, 0.6), u=8, v=6)
    p.box("steel", (w + 0.04, 0.035, z1 - z0 + 0.04), (0, 0, (z0 + z1) / 2), 0.012, 2)
    p.box("sheet", (w, 0.04, z1 - z0), (0, 0, (z0 + z1) / 2), 0.004, 1)
    p.box("steel", (w * 0.7, 0.07, 0.02), (0, -0.04, z0 - 0.01), 0.006, 1)  # pen tray
    for x, mat in ((-0.2, "sign_blue"), (-0.1, "food_c"), (0.0, "leaf")):
        p.cyl(mat, 0.011, 0.11, (x, -0.05, z0 + 0.01), bevel=0.004, n=10, rot=(0, 90, 0))
    p.box("cream", (0.1, 0.04, 0.04), (0.2, -0.05, z0 + 0.02), 0.012, 2)  # rubber
    # A few lines of writing and a tick.
    for k, (x, ln) in enumerate(((-0.35, 0.5), (-0.4, 0.4), (-0.38, 0.46), (-0.42, 0.32))):
        p.box("sign_blue", (ln, 0.008, 0.016), (x, -0.022, z1 - 0.1 - k * 0.09), 0.003, 1)
    p.tube("food_c", [(0.25, -0.022, 0.95), (0.35, -0.022, 0.83), (0.5, -0.022, 0.98)], 0.007, 0.01, n=6)
    return p


def armchair():
    """0.75 x 0.75 soft armchair for counselling, seat top about 0.3, the
    sitter facing the front (Godot +z)."""
    p = Prop("armchair")
    _armchair(p)
    return p


def _armchair(p, fabric="fabric", dx=0.0, dy=0.0):
    p.box(fabric, (0.66, 0.6, 0.2), (dx, dy + 0.02, 0.15), 0.06, 3)  # base
    p.box(fabric, (0.46, 0.5, 0.1), (dx, dy - 0.04, 0.26), 0.045, 3)  # seat cushion
    p.box(fabric, (0.6, 0.18, 0.46), (dx, dy + 0.24, 0.42), 0.08, 3, rot=(-8, 0, 0))  # back
    for x in (-0.28, 0.28):
        p.box(fabric, (0.13, 0.62, 0.3), (dx + x, dy, 0.3), 0.06, 3)  # arms
    for x in (-0.27, 0.27):
        for y in (-0.24, 0.27):
            p.cyl("wood", 0.025, 0.06, (dx + x, dy + y, 0.03), r2=0.03, bevel=0.008, n=12)


def postcard_board():
    """1 x 0.1 corkboard against the wall behind, 0.6 tall, its bottom 0.6 m
    up. Six cards, meshes card_1 to card_6, so the game can show and hide
    them one by one."""
    p = Prop("postcard_board")
    y, z0, z1 = 0.035, 0.6, 1.2
    p.box("wood", (0.92, 0.03, z1 - z0), (0, y, (z0 + z1) / 2), 0.01, 2)
    p.box("cork", (0.84, 0.032, z1 - z0 - 0.08), (0, y - 0.003, (z0 + z1) / 2), 0.004, 1)
    cards = (("poster_a", -0.26, 1.04, 6), ("paper", 0.0, 1.05, -4), ("poster_b", 0.26, 1.03, 3),
             ("book_d", -0.26, 0.77, -3), ("poster_c", 0.0, 0.76, 5), ("book_b", 0.26, 0.78, -6))
    for k, (mat, x, z, tilt) in enumerate(cards):
        p.group = "card_%d" % (k + 1)
        p.plain.add(p.group)
        p.box(mat, (0.19, 0.008, 0.13), (x, y - 0.02, z), 0.003, 1, rot=(0, tilt, 0))
        p.ball(mat, 0.011, (x, y - 0.026, z + 0.05), u=8, v=6)  # its drawing pin
    p.group = None
    return p


def phone(name="phone", yb=0.08):
    """0.4 x 0.2 wall payphone against the wall behind, about 0.9 m tall:
    a steel phone in a little hood, handset on the left. `yb` is where the
    wall face is, behind."""
    p = Prop(name)
    p.box("steel_dark", (0.38, 0.03, 0.56), (0, yb, 0.62), 0.012, 2)  # back plate
    for x in (-0.18, 0.18):
        p.box("steel_dark", (0.025, 0.17, 0.5), (x, yb - 0.08, 0.64), 0.01, 1)  # hood sides
    p.box("steel_dark", (0.38, 0.17, 0.025), (0, yb - 0.08, 0.89), 0.01, 1)  # hood top
    p.box("steel", (0.2, 0.09, 0.3), (0.02, yb - 0.06, 0.6), 0.02, 2)  # body
    p.box("screen", (0.1, 0.01, 0.035), (0.03, yb - 0.106, 0.71), 0.004, 1)
    for r in range(4):
        for c in range(3):
            p.box("steel_dark", (0.022, 0.012, 0.018), (0.0 + c * 0.03, yb - 0.106, 0.65 - r * 0.028), 0.004, 1)
    p.box("steel_dark", (0.008, 0.012, 0.04), (0.095, yb - 0.106, 0.68), 0.002, 1)  # coin slot
    # Handset hanging on the left side, with a coiled cord.
    p.box("steel", (0.03, 0.05, 0.04), (-0.095, yb - 0.06, 0.62), 0.008, 1)
    p.capsule("bag", 0.025, 0.12, (-0.12, yb - 0.07, 0.6), scale=(1, 1.1, 1))
    for z in (0.69, 0.51):
        p.ball("bag", 0.034, (-0.12, yb - 0.075, z), scale=(1, 1.2, 0.8), u=12, v=8)
    pts = [(-0.11 + 0.012 * math.cos(k * 1.4), yb - 0.06 + 0.012 * math.sin(k * 1.4), 0.5 - k * 0.012)
           for k in range(12)]
    p.tube("steel_dark", pts + [(-0.04, yb - 0.04, 0.47)], 0.005, 0.0, n=6)
    return p



def payphone():
    """1 x 0.5: the wall payphone at the back middle of a footprint with room
    to stand at it, and a little blue sign above."""
    p = phone("payphone", yb=0.235)
    p.box("sign_blue", (0.3, 0.02, 0.14), (0, 0.24, 1.04), 0.01, 2)
    p.capsule("sheet", 0.02, 0.08, (0, 0.228, 1.04), scale=(1, 0.4, 1), rot=(0, 90, 0))
    for x in (-0.06, 0.06):
        p.ball("sheet", 0.026, (x, 0.228, 1.025), scale=(1, 0.4, 0.8), u=10, v=6)
    return p


def planter():
    """1 x 1 raised flower box, about 0.6 m to the tops of the flowers: a
    slatted pine box full of soil, leaves and a few plain flowers."""
    p = Prop("planter")
    h = 0.42
    for k in range(3):  # slats round all four sides
        z = 0.03 + k * 0.13 + 0.06
        for sx, sy, w, d in ((0, -0.44, 0.9, 0.04), (0, 0.44, 0.9, 0.04),
                             (-0.44, 0, 0.04, 0.84), (0.44, 0, 0.04, 0.84)):
            p.box("pine", (w, d, 0.12), (sx, sy, z), 0.012, 2)
    for x in (-0.44, 0.44):
        for y in (-0.44, 0.44):
            p.box("crate", (0.07, 0.07, h + 0.02), (x, y, (h + 0.02) / 2), 0.012, 2)
    p.box("soil", (0.84, 0.84, 0.04), (0, 0, h - 0.04), 0.01, 1)
    rng = random.Random(4)
    for x in (-0.25, 0.0, 0.25):
        for y in (-0.25, 0.0, 0.25):
            cx, cy = x + rng.uniform(-0.04, 0.04), y + rng.uniform(-0.04, 0.04)
            p.ball("leaf", rng.uniform(0.1, 0.13), (cx, cy, h + 0.03), scale=(1, 1, 0.6), u=12, v=8)
            mat = rng.choice(("sheet", "poster_c", "food_c", "book_a"))
            for j in range(rng.randint(2, 3)):
                a = rng.uniform(0, math.tau)
                p.ball(mat, 0.035, (cx + 0.06 * math.cos(a), cy + 0.06 * math.sin(a), h + 0.1 + 0.03 * j),
                       scale=(1, 1, 0.7), u=10, v=6)
    return p


def veg_bed():
    """2 x 1 raised timber bed, about 0.35 m to the tops of the veg: three
    rows along its length, cabbages, carrot tops and lettuces."""
    p = Prop("veg_bed")
    h = 0.22
    for sx, sy, w, d in ((0, -0.45, 1.94, 0.08), (0, 0.45, 1.94, 0.08),
                         (-0.93, 0, 0.08, 0.82), (0.93, 0, 0.08, 0.82)):
        p.box("crate", (w, d, h), (sx, sy, h / 2), 0.015, 2)
    p.box("soil", (1.8, 0.84, 0.05), (0, 0, h - 0.04), 0.012, 1)
    rng = random.Random(9)
    for k in range(7):
        x = -0.75 + k * 0.25
        p.ball("leaf", 0.075, (x, -0.25, h + 0.04), scale=(1, 1, 0.8), u=12, v=8)  # cabbage
        p.ball("food_b", 0.05, (x, -0.25, h + 0.07), u=10, v=8)
        for j in range(3):  # carrot tops: little feathery tufts
            a = rng.uniform(-0.4, 0.4) + (j - 1) * 0.5
            p.tube("stem", [(x, 0, h - 0.01), (x + 0.07 * math.sin(a), 0.02 * j - 0.02, h + 0.1)], 0.01, 0, n=6)
            p.ball("leaf", 0.022, (x + 0.07 * math.sin(a), 0.02 * j - 0.02, h + 0.1), u=8, v=6)
        p.ball("food_b", 0.07, (x, 0.25, h + 0.03), scale=(1, 1, 0.65), u=12, v=8)  # lettuce
        p.ball("leaf", 0.045, (x, 0.25, h + 0.06), scale=(1, 1, 0.8), u=10, v=6)
    return p

# ---------------------------------------------------------------- items and jobs (M4)

def cooker():
    p = Prop("cooker")  # 1 x 1 range: four rings on top, oven door at the front
    p.box("steel", (0.94, 0.86, 0.55), (0, 0, 0.275), 0.03, 3)
    p.box("steel_dark", (0.9, 0.82, 0.02), (0, 0, 0.555), 0.01, 1)
    for x in (-0.22, 0.22):
        for y in (-0.18, 0.2):
            p.cyl("rubber", 0.12, 0.025, (x, y, 0.57), bevel=0.008, n=24)
            p.cyl("steel_dark", 0.06, 0.03, (x, y, 0.575), bevel=0.005, n=16)
    p.box("steel_dark", (0.74, 0.03, 0.3), (0, -0.43, 0.24), 0.02, 2)
    p.box("glass", (0.5, 0.02, 0.16), (0, -0.445, 0.25), 0.01, 1)
    p.tube("steel", [(-0.28, -0.44, 0.42), (-0.28, -0.48, 0.42), (0.28, -0.48, 0.42), (0.28, -0.44, 0.42)], 0.012, 0.02, n=8)
    for k in range(4):
        p.cyl("rubber", 0.025, 0.03, (-0.3 + k * 0.2, -0.44, 0.5), bevel=0.008, n=12, rot=(90, 0, 0))
    return p


def fridge():
    p = Prop("fridge")  # 1 x 0.75 tall double fridge, doors at the front
    h = 1.3
    p.box("white", (0.92, 0.66, h), (0, 0.02, h / 2), 0.04, 3)
    p.box("steel_dark", (0.004, 0.02, h - 0.1), (0, -0.315, h / 2), 0, 0)
    for x in (-0.06, 0.06):
        p.tube("steel", [(x, -0.32, 0.55), (x, -0.36, 0.55), (x, -0.36, 0.85), (x, -0.32, 0.85)], 0.012, 0.02, n=8)
    p.box("steel_dark", (0.9, 0.02, 0.06), (0, -0.315, 0.06), 0.01, 1)
    return p


def serving_counter():
    p = Prop("serving_counter")  # 2 x 1 steel counter with hot trays and a sneeze guard
    p.box("steel", (1.92, 0.7, 0.53), (0, 0.1, 0.265), 0.03, 3)
    p.box("steel_dark", (1.86, 0.6, 0.02), (0, 0.1, 0.535), 0.01, 1)
    for k, food in enumerate(("food_a", "food_b", "food_c", "food_a")):
        x = -0.69 + k * 0.46
        p.box("steel", (0.4, 0.42, 0.04), (x, 0.12, 0.54), 0.01, 1)
        p.box(food, (0.36, 0.38, 0.03), (x, 0.12, 0.555), 0.012, 2)
    # Tray rail along the front, for sliding trays along.
    for x in (-0.85, 0, 0.85):
        p.tube("steel", [(x, -0.25, 0.42), (x, -0.4, 0.42)], 0.015, 0, n=8)
    p.box("steel", (1.92, 0.16, 0.025), (0, -0.35, 0.44), 0.008, 1)
    # Sneeze guard.
    for x in (-0.9, 0.9):
        p.tube("steel", [(x, -0.15, 0.53), (x, -0.15, 0.85)], 0.015, 0, n=8)
    p.box("glass", (1.82, 0.2, 0.02), (0, -0.1, 0.85), 0.008, 1, rot=(20, 0, 0))
    # A stack of clean trays at one end.
    for i in range(4):
        p.box("cream", (0.3, 0.22, 0.012), (0.8, -0.35, 0.46 + i * 0.016), 0.005, 1)
    return p


def washing_machine():
    p = Prop("washing_machine")  # 1 x 0.75 big industrial front-loader
    p.box("white", (0.92, 0.66, 0.68), (0, 0.02, 0.34), 0.045, 3)
    p.box("steel_dark", (0.88, 0.02, 0.1), (0, -0.315, 0.6), 0.01, 1)
    p.box("light", (0.12, 0.02, 0.04), (0.28, -0.325, 0.6), 0.005, 1)
    p.cyl("steel", 0.2, 0.05, (0, -0.31, 0.3), bevel=0.02, segs=3, n=28, rot=(90, 0, 0))
    p.cyl("glass", 0.15, 0.02, (0, -0.34, 0.3), bevel=0.008, n=28, rot=(90, 0, 0))
    p.ball("uniform", 0.09, (0.03, -0.3, 0.26), scale=(1, 0.5, 0.7), u=12, v=8)
    return p


def ironing_board():
    p = Prop("ironing_board")  # 1.5 x 0.5 board on crossed legs, with an iron
    p.box("sheet", (1.3, 0.36, 0.04), (0.02, 0, 0.53), 0.018, 3)
    p.box("sheet", (0.26, 0.24, 0.039), (0.72, 0, 0.53), 0.018, 3)  # narrow end
    for x in (-0.3, 0.3):
        p.tube("paint", [(x, -0.16, 0), (-x, 0.0, 0.52)], 0.015, 0, n=8)
        p.tube("paint", [(x, 0.16, 0), (-x, 0.0, 0.52)], 0.015, 0, n=8)
    p.taper("steel", (0.18, 0.1), (0.14, 0.08), 0.06, (0.3, 0, 0.585), 0.02)
    p.tube("rubber", [(0.25, 0, 0.62), (0.25, 0, 0.66), (0.35, 0, 0.66), (0.35, 0, 0.62)], 0.012, 0.02, n=8)
    return p


def laundry_basket():
    p = Prop("laundry_basket")  # 0.5 x 0.5 plastic basket of clothes
    p.taper("plastic", (0.36, 0.3), (0.44, 0.36), 0.28, (0, 0, 0.14), 0.04, 3)
    p.ball("uniform", 0.13, (-0.07, 0.0, 0.28), scale=(1.2, 1, 0.5), u=14, v=8)
    p.ball("sheet", 0.11, (0.1, 0.03, 0.29), scale=(1.2, 1, 0.5), u=14, v=8)
    return p


def clothes_shelf():
    p = Prop("clothes_shelf")  # 1 x 0.5 open shelves of folded uniforms
    h, w, d = 1.3, 0.96, 0.4
    for x in (-w / 2 + 0.03, w / 2 - 0.03):
        p.box("wood", (0.05, d, h), (x, 0.03, h / 2), 0.015, 2)
    p.box("wood", (w, 0.03, h), (0, d / 2 + 0.015, h / 2), 0.01, 1)
    shelves = (0.04, 0.45, 0.86, h - 0.025)
    for z in shelves:
        p.box("wood", (w - 0.04, d, 0.04), (0, 0.03, z), 0.012, 2)
    for z in shelves[:-1]:
        for k, x in enumerate((-0.28, 0.0, 0.28)):
            for j in range(3 - (k % 2)):
                cloth = "uniform" if (k + j) % 3 else "sheet"
                p.box(cloth, (0.24, 0.28, 0.06), (x, 0.04, z + 0.05 + j * 0.065), 0.02, 2)
    return p


def workbench():
    p = Prop("workbench")  # 2 x 1 sturdy bench with a vice and a few tools
    p.box("wood", (1.9, 0.8, 0.07), (0, 0, 0.52), 0.02, 2)
    for x in (-0.85, 0.85):
        for y in (-0.32, 0.32):
            p.box("paint", (0.07, 0.07, 0.49), (x, y, 0.245), 0.015, 2)
    p.box("wood", (1.76, 0.66, 0.03), (0, 0, 0.12), 0.01, 1)
    p.box("steel_dark", (0.16, 0.14, 0.08), (-0.75, -0.36, 0.6), 0.02, 2)
    p.box("steel_dark", (0.16, 0.04, 0.1), (-0.75, -0.46, 0.6), 0.015, 2)
    p.box("crate", (0.6, 0.12, 0.05), (-0.15, -0.05, 0.58), 0.01, 1, rot=(0, 0, 8))
    p.box("wood", (0.24, 0.03, 0.03), (0.45, -0.1, 0.57), 0.008, 1, rot=(0, 0, -20))
    p.box("steel_dark", (0.05, 0.1, 0.05), (0.56, -0.15, 0.575), 0.01, 1, rot=(0, 0, -20))
    p.box("crate", (0.3, 0.2, 0.06), (0.6, 0.2, 0.585), 0.015, 2)
    return p


def bin_():
    p = Prop("bin")  # 0.5 x 0.5 pedal bin
    p.cyl("paint", 0.17, 0.42, (0, 0, 0.21), r2=0.19, bevel=0.02, n=24)
    p.cyl("paint", 0.2, 0.05, (0, 0, 0.445), bevel=0.02, segs=3, n=24)
    p.box("steel_dark", (0.1, 0.08, 0.02), (0, -0.2, 0.03), 0.008, 1)
    return p


def skip_():
    p = Prop("skip")  # 2 x 1 outdoor skip, rubbish heaped inside
    p.taper("skip", (1.5, 0.82), (1.92, 0.9), 0.62, (0, 0, 0.35), 0.03, 2)
    for x in (-0.55, 0.55):
        p.box("rubber", (0.12, 0.7, 0.06), (x, 0, 0.03), 0.02, 1)
    for x in (-0.95, 0.95):
        p.tube("steel_dark", [(x, -0.2, 0.55), (x * 1.05, -0.2, 0.62), (x * 1.05, 0.2, 0.62), (x, 0.2, 0.55)], 0.02, 0.04, n=8)
    for loc, r in (((-0.4, 0, 0.66), 0.22), ((0.1, 0.1, 0.68), 0.24), ((0.5, -0.1, 0.65), 0.2)):
        p.ball("bag", r, loc, scale=(1.1, 1, 0.7), u=14, v=8)
    p.box("crate", (0.3, 0.25, 0.2), (-0.05, -0.18, 0.72), 0.02, 2, rot=(0, 10, 25))
    return p


def storage_shelf():
    p = Prop("storage_shelf")  # 1 x 0.5 steel shelving stacked with crates
    h = 1.4
    for x in (-0.46, 0.46):
        for y in (-0.2, 0.2):
            p.box("paint", (0.04, 0.04, h), (x, y, h / 2), 0.008, 1)
    for z in (0.08, 0.55, 1.02, h - 0.02):
        p.box("steel", (0.94, 0.42, 0.025), (0, 0, z), 0.006, 1)
    for z, xs in ((0.095, (-0.22, 0.22)), (0.565, (-0.22, 0.2)), (1.035, (0.0,))):
        for x in xs:
            p.box("crate", (0.4, 0.34, 0.3), (x, 0, z + 0.15), 0.02, 2)
            p.box("rubber", (0.12, 0.02, 0.04), (x, -0.172, z + 0.24), 0.008, 1)
    return p


def table_trolley():
    p = Prop("table_trolley")  # 1 x 0.5 steel trolley with trays
    for x in (-0.42, 0.42):
        for y in (-0.18, 0.18):
            p.tube("steel", [(x, y, 0.07), (x, y, 0.6)], 0.015, 0, n=8)
            p.cyl("rubber", 0.04, 0.03, (x, y, 0.04), bevel=0.008, n=12, rot=(90, 0, 0))
    for z in (0.22, 0.58):
        p.box("steel", (0.9, 0.42, 0.03), (0, 0, z), 0.012, 2)
    p.tube("steel", [(0.42, -0.18, 0.6), (0.48, -0.18, 0.7), (0.48, 0.18, 0.7), (0.42, 0.18, 0.6)], 0.015, 0.04, n=8)
    for x in (-0.2, 0.15):
        _tray(p, (x, 0, 0.6))
    return p


def _tray(p, at):
    x, y, z = at
    p.box("cream", (0.34, 0.26, 0.02), (x, y, z + 0.01), 0.008, 1)
    p.cyl("sheet", 0.08, 0.015, (x - 0.06, y, z + 0.028), bevel=0.005, n=20)
    p.ball("food_a", 0.035, (x - 0.08, y + 0.02, z + 0.04), scale=(1, 1, 0.6), u=10, v=6)
    p.ball("food_b", 0.03, (x - 0.04, y - 0.02, z + 0.04), scale=(1, 1, 0.6), u=10, v=6)
    p.box("food_c", (0.08, 0.08, 0.03), (x + 0.09, y, z + 0.035), 0.012, 2)


# Carried things, about 0.4 m, origin at the middle of the bottom.

def food_crate():
    p = Prop("food_crate")
    p.box("crate", (0.4, 0.28, 0.2), (0, 0, 0.1), 0.02, 2)
    p.box("steel_dark", (0.36, 0.24, 0.01), (0, 0, 0.17), 0, 0)
    for k, (x, y) in enumerate(((-0.1, -0.05), (0.0, 0.06), (0.1, -0.04), (-0.05, 0.07), (0.12, 0.07))):
        p.ball(("food_a", "food_b", "food_c")[k % 3], 0.06, (x, y, 0.2), u=12, v=8)
    return p


def meal_tray():
    p = Prop("meal_tray")
    _tray(p, (0, 0, 0))
    return p


def dirty_laundry():
    p = Prop("dirty_laundry")
    p.ball("uniform", 0.17, (0, 0, 0.14), scale=(1.15, 0.9, 0.85), u=16, v=10)
    p.ball("sheet", 0.1, (0.1, -0.08, 0.2), scale=(1.2, 1, 0.7), u=12, v=8)
    p.ball("uniform", 0.06, (-0.05, 0, 0.29), scale=(1, 1, 1.3), u=12, v=8)
    return p


def clean_laundry():
    p = Prop("clean_laundry")
    for j in range(4):
        p.box("uniform" if j % 2 == 0 else "sheet", (0.32, 0.26, 0.06), (0, 0, 0.03 + j * 0.062), 0.02, 2)
    return p


def rubbish_bag():
    p = Prop("rubbish_bag")
    p.ball("bag", 0.17, (0, 0, 0.16), scale=(1, 0.9, 1.0), u=16, v=10)
    p.cyl("bag", 0.04, 0.08, (0, 0, 0.33), r2=0.02, bevel=0.01, n=12)
    for a in (-30, 30):
        p.ball("bag", 0.04, (math.sin(math.radians(a)) * 0.06, 0, 0.39), scale=(1.3, 0.6, 0.8), u=10, v=6)
    return p


def wooden_toy():
    p = Prop("wooden_toy")  # a little wooden car
    p.box("wood", (0.3, 0.14, 0.08), (0, 0, 0.08), 0.03, 3)
    p.box("crate", (0.15, 0.12, 0.07), (-0.02, 0, 0.155), 0.025, 3)
    for x in (-0.09, 0.09):
        for y in (-0.08, 0.08):
            p.cyl("food_c", 0.04, 0.03, (x, y, 0.04), bevel=0.01, n=16, rot=(90, 0, 0))
    return p


def birdhouse():
    p = Prop("birdhouse")
    p.box("wood", (0.2, 0.2, 0.22), (0, 0, 0.11), 0.015, 2)
    for side in (-1, 1):
        p.box("crate", (0.17, 0.27, 0.02), (side * 0.065, 0, 0.27), 0.008, 1, rot=(0, side * 40, 0))
    p.cyl("rubber", 0.035, 0.01, (0, -0.1, 0.14), bevel=0, n=16, rot=(90, 0, 0))
    p.tube("crate", [(0, -0.1, 0.08), (0, -0.15, 0.08)], 0.008, 0, n=6)
    return p


# Floor litter: small and flat, origin on the floor.

def litter_paper():
    p = Prop("litter_paper")
    p.ball("sheet", 0.05, (0, 0, 0.035), scale=(1, 0.9, 0.8), u=8, v=6)
    return p


def litter_can():
    p = Prop("litter_can")
    p.cyl("food_c", 0.03, 0.11, (0, 0, 0.03), bevel=0.008, n=14, rot=(90, 0, 30))
    return p


def litter_wrapper():
    p = Prop("litter_wrapper")
    p.box("food_a", (0.12, 0.08, 0.008), (0, 0, 0.004), 0.003, 1, rot=(0, 0, 20))
    p.box("paper", (0.04, 0.081, 0.009), (0.02, 0.01, 0.004), 0, 0, rot=(0, 0, 20))
    return p


def lorry():
    """A cute delivery lorry, 2 x 5 tiles, cab at the front (-y, Godot +z)."""
    p = Prop("lorry")
    # Box body.
    p.box("lorry", (1.7, 3.0, 1.6), (0, 0.85, 1.25), 0.08, 3)
    p.box("stripe", (1.72, 2.6, 0.18), (0, 0.85, 1.2), 0.02, 2)
    p.box("steel_dark", (1.6, 0.04, 1.4), (0, 2.36, 1.25), 0.02, 1)
    # Cab: a soft rounded box with a big windscreen.
    p.box("lorry", (1.72, 1.3, 1.3), (0, -1.25, 1.05), 0.22, 4)
    p.box("glass", (1.5, 0.2, 0.5), (0, -1.86, 1.35), 0.06, 2, rot=(-12, 0, 0))
    for side in (-1, 1):
        p.box("glass", (0.04, 0.6, 0.42), (side * 0.86, -1.3, 1.35), 0.02, 1)
        p.cyl("light", 0.09, 0.05, (side * 0.6, -1.9, 0.72), bevel=0.02, n=16, rot=(90, 0, 0))
        p.box("steel_dark", (0.06, 0.12, 0.2), (side * 0.94, -1.72, 1.4), 0.02, 2)
    p.box("steel_dark", (1.7, 0.16, 0.18), (0, -1.92, 0.48), 0.06, 2)
    p.box("steel_dark", (1.6, 4.2, 0.2), (0, 0.15, 0.45), 0.05, 2)
    # Chunky wheels.
    for y in (-1.25, 1.4):
        for side in (-1, 1):
            p.cyl("rubber", 0.36, 0.28, (side * 0.78, y, 0.36), bevel=0.06, segs=3, n=28, rot=(0, 90, 0))
            p.cyl("steel", 0.17, 0.3, (side * 0.78, y, 0.36), bevel=0.03, n=20, rot=(0, 90, 0))
    return p


MODELS = dict(ferry=ferry, helicopter=helicopter, jetty=jetty, easel=easel, piano=piano, knitting_chair=knitting_chair, till=till,
              pet_cage=pet_cage, visit_table=visit_table, cat=cat, rabbit=rabbit, budgie=budgie, hen=hen,
              therapy_dog=therapy_dog, **_looks(meeting_table), snack_machine=snack_machine, mobile_phone=mobile_phone, sweets=sweets,
              fruit=fruit, fizzy_pop=fizzy_pop,
              payphone=payphone, planter=planter, veg_bed=veg_bed,
              filing_cabinet=filing_cabinet, paper_stack_small=paper_stack_small,
              paper_stack_tall=paper_stack_tall, paper_stack_teetering=paper_stack_teetering,
              class_desk=class_desk, whiteboard=whiteboard, armchair=armchair,
              postcard_board=postcard_board, phone=phone,
              metal_detector=metal_detector, memorial_plaque=memorial_plaque,
              cctv_camera=cctv_camera, people_gate=people_gate, vehicle_gate=vehicle_gate, biscuit=biscuit, spoon=spoon, rolling_pin=rolling_pin, frying_pan=frying_pan,
              screwdriver=screwdriver, mallet=mallet, soap_sock=soap_sock,
              infirmary_bed=infirmary_bed, medicine_cabinet=medicine_cabinet, dust_cloud=dust_cloud,
              tunnel_portal=tunnel_portal, car=car, car_red=lambda: car("car_red", "car_red"),
              car_blue=lambda: car("car_blue", "car_blue"),
              car_cream=lambda: car("car_cream", "car_cream"), bus_stop=bus_stop,
              **_looks(desk), **_looks(office_desk), **_looks(games_table),
              chair=chair, chair_cushioned=chair_cushioned, chair_pine=chair_pine,
              office_chair=office_chair, chess_board=chess_board, cctv_monitor=cctv_monitor,
              nameplate=nameplate, in_tray=in_tray, desk_plant=desk_plant, mug=mug,
              bed=bed, toilet=toilet, shower=shower, table=table, lift=lift, door=door,
              cell_door=cell_door, person=person, tree=tree, bush=bush, flower=flower,
              radio=radio, tv=tv, bookshelf=bookshelf,
              weights_bench=weights_bench, basketball_hoop=basketball_hoop, bench=bench, sink=sink,
              rug=rug, poster=poster, plant_pot=plant_pot, wall_shelf=wall_shelf,
              cooker=cooker, fridge=fridge, serving_counter=serving_counter,
              washing_machine=washing_machine, ironing_board=ironing_board,
              laundry_basket=laundry_basket, clothes_shelf=clothes_shelf, workbench=workbench,
              bin=bin_, skip=skip_, storage_shelf=storage_shelf, table_trolley=table_trolley,
              food_crate=food_crate, meal_tray=meal_tray, dirty_laundry=dirty_laundry,
              clean_laundry=clean_laundry, rubbish_bag=rubbish_bag, wooden_toy=wooden_toy,
              birdhouse=birdhouse, litter_paper=litter_paper, litter_can=litter_can,
              litter_wrapper=litter_wrapper, lorry=lorry,
              coffee_machine=coffee_machine, security_gate=security_gate, guard_desk=guard_desk,
              reception_desk=reception_desk, bus=bus)


# ---------------------------------------------------------------- line-up

def lineup(folder, names=None):
    scene.render.engine = "BLENDER_EEVEE_NEXT" if hasattr(bpy.types, "EEVEE_NEXT") else "CYCLES"
    try:
        scene.render.engine = "CYCLES"
        scene.cycles.samples = 48
        scene.cycles.use_denoising = True
    except Exception:
        pass
    spots = [("bed", (-3.2, 0, 0), 90), ("table", (-1.0, 0.2, 0), 0), ("toilet", (0.6, 0.2, 0), 180),
             ("shower", (1.5, 0.2, 0), 180), ("lift", (2.8, 0.2, 0), 0), ("door", (-2.8, 1.8, 0), 0),
             ("cell_door", (-1.4, 1.8, 0), 0), ("desk", (0.1, 1.6, 0), 180), ("person", (1.1, 1.4, 0), 200),
             ("tree", (2.2, 1.9, 0), 0), ("bush", (3.4, 1.7, 0), 0), ("flower", (3.6, 0.9, 0), 0)]
    if names:  # just these, in rows of four
        spots = [(n, (-3.0 + (k % 4) * 2.0, -0.4 + (k // 4) * 1.9, 0), 0) for k, n in enumerate(names)]
    for name, loc, rz in spots:
        MODELS[name]().build(loc, rz)
    floor = Prop("floor")
    floor.box("sheet", (30, 30, 0.05), (0, 0, -0.025), 0)
    floor.build()
    cam_d = bpy.data.cameras.new("cam")
    cam_d.lens_unit = "FOV"
    cam_d.angle = math.radians(40)
    cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam)
    target, yaw, pitch, dist = Vector((0.2, 0.9, 0.4)), -90, 35, 9.0
    if names:
        rows = (len(names) + 3) // 4
        target, dist = Vector((0.0, -0.4 + (rows - 1) * 0.95, 0.4)), 7.5 + rows * 1.8
    d = Vector((math.cos(math.radians(yaw)) * math.cos(math.radians(pitch)),
                math.sin(math.radians(yaw)) * math.cos(math.radians(pitch)), math.sin(math.radians(pitch))))
    cam.location = target + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun_d = bpy.data.lights.new("sun", "SUN")
    sun_d.energy, sun_d.color, sun_d.angle = 3.2, (1.0, 0.92, 0.8), math.radians(8)
    sun = bpy.data.objects.new("sun", sun_d)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(yaw + 125))
    world = bpy.data.worlds.new("sky")
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    world.node_tree.nodes["Background"].inputs["Color"].default_value = hexc("#bcd6ec")
    scene.world = world
    # Tint the recoloured parts as the game would, just for the picture.
    for name, colour in (("outfit", "#e8894a"), ("skin", "#e9c4a4"), ("hair", "#6b4a35"),
                         ("trunk", "#80604a"), ("canopy", "#5f9a52"), ("bloom", "#f2a0b8")):
        M(name).node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = hexc(colour)
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.render.filepath = os.path.join(folder, "lineup.png")
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    out = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(__file__), "..", "models"))
    os.makedirs(out, exist_ok=True)
    names = args[1:] or list(MODELS)
    if names[:1] == ["lineup"]:
        lineup(out, names[1:])
    else:
        for name in names:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            scene = bpy.context.scene
            _mats.clear()
            MODELS[name]().build().export(out)
            print("exported", name)
