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
    gold=("#e0b65a", 0.35, 0.6),        # staff badge
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
            name = material if group is None else "%s_%s" % (material, group)
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


def desk():
    p = Prop("desk", 180)  # 1 x 0.5, bolted to the wall behind
    p.box("wood", (0.95, 0.46, 0.06), (0, 0, 0.5), 0.025, 3)
    for x in (-0.4, 0.4):
        p.tube("paint", [(x, -0.2, 0.47), (x, 0.15, 0.47), (x, 0.15, 0)], 0.025, 0.1, n=10)
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
    """1.5 x 1 guard post: desk against the wall behind, a CCTV monitor
    facing the chair at the front."""
    p = Prop("guard_desk")
    p.box("wood", (1.45, 0.55, 0.06), (0, 0.2, 0.5), 0.025, 3)
    for x in (-0.66, 0.66):
        p.box("paint", (0.06, 0.5, 0.47), (x, 0.2, 0.235), 0.015, 2)
    p.box("paint", (0.4, 0.5, 0.42), (0.42, 0.2, 0.26), 0.02, 2)  # drawers
    for z in (0.16, 0.34):
        p.box("steel", (0.12, 0.02, 0.03), (0.42, -0.06, z), 0.008, 1)
    # Monitor with a split CCTV picture.
    p.box("steel_dark", (0.52, 0.12, 0.36), (-0.1, 0.32, 0.79), 0.04, 3)
    p.box("screen", (0.44, 0.02, 0.28), (-0.1, 0.255, 0.79), 0.01, 1)
    p.box("light", (0.004, 0.022, 0.28), (-0.1, 0.255, 0.79), 0, 0)
    p.box("light", (0.44, 0.022, 0.004), (-0.1, 0.255, 0.79), 0, 0)
    p.box("steel_dark", (0.08, 0.08, 0.1), (-0.1, 0.34, 0.58), 0.02, 2)
    p.box("steel_dark", (0.36, 0.14, 0.02), (-0.1, 0.0, 0.54), 0.008, 1)  # keyboard
    p.box("paper", (0.18, 0.24, 0.01), (0.35, 0.05, 0.535), 0.003, 1, rot=(0, 0, -12))
    # Swivel chair at the front, facing the desk.
    p.box("vinyl", (0.38, 0.36, 0.07), (0, -0.25, 0.33), 0.03, 3)
    p.box("vinyl", (0.36, 0.06, 0.32), (0, -0.44, 0.52), 0.03, 3)
    p.tube("steel_dark", [(0, -0.25, 0.3), (0, -0.25, 0.06)], 0.025, 0, n=10)
    for a in range(5):
        ang = math.radians(a * 72)
        p.tube("steel_dark", [(0, -0.25, 0.06), (math.sin(ang) * 0.2, -0.25 + math.cos(ang) * 0.2, 0.05)], 0.018, 0, n=8)
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
    peaked cap), *_cook (a chef's hat)."""
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
    p.cyl("gold", 0.035, 0.012, (0.07, -0.126, 0.47), bevel=0.004, n=16, rot=(90, 0, 0))
    # Guards: a peaked cap over the hair.
    p.group = "guard"
    p.ball("navy", 0.178, (0, -0.01, 0.75), scale=(1.02, 1.0, 0.72))
    p.cyl("navy", 0.17, 0.04, (0, 0.0, 0.79), bevel=0.015, n=24)
    p.ball("navy", 0.11, (0, 0.15, 0.77), scale=(1.1, 0.8, 0.18), u=16, v=8)
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


def games_table():
    p = Prop("games_table")  # 1 x 1 small table with a board game on it
    p.box("wood", (0.9, 0.9, 0.05), (0, 0, 0.7), 0.03, 3)
    p.tube("paint", [(0, 0, 0), (0, 0, 0.68)], 0.04, 0, n=12)
    p.cyl("paint", 0.25, 0.03, (0, 0, 0.015), bevel=0.012, n=24)
    p.box("cream", (0.4, 0.4, 0.02), (0, 0, 0.735), 0.006, 1)
    for i in range(4):
        for j in range(4):
            if (i + j) % 2 == 0:
                p.box("book_c", (0.09, 0.09, 0.006), (-0.15 + i * 0.1, -0.15 + j * 0.1, 0.747), 0, 0)
    for k, (x, y) in enumerate(((-0.15, -0.15), (0.05, -0.15), (-0.05, 0.15), (0.15, 0.05))):
        p.cyl("rubber" if k % 2 else "sheet", 0.03, 0.02, (x, y, 0.76), bevel=0.006, n=14)
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


MODELS = dict(bed=bed, toilet=toilet, shower=shower, table=table, desk=desk, lift=lift, door=door,
              cell_door=cell_door, person=person, tree=tree, bush=bush, flower=flower,
              radio=radio, tv=tv, bookshelf=bookshelf, games_table=games_table,
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
              coffee_machine=coffee_machine, security_gate=security_gate, guard_desk=guard_desk)


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
