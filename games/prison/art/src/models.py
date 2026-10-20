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
    # Recoloured by the game: kept white-ish so a tint reads true.
    outfit=("#ffffff", 0.85, 0),
    skin=("#ffffff", 0.7, 0),
    hair=("#ffffff", 0.8, 0),
    shoes=("#3b3a3c", 0.7, 0),
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
    joined into one mesh named after it."""

    def __init__(self, name, turn=0):
        self.name = name
        self.turn = turn  # degrees about z, baked in when built
        self.parts = {}  # material name -> [bmesh]

    def add(self, material, bm, bevel=0.0, segs=3, xf=Matrix()):
        _bevel(bm, bevel, segs)
        bm.transform(xf)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        self.parts.setdefault(material, []).append(bm)

    def box(self, material, size, loc, bevel=0.02, segs=3, rot=(0, 0, 0)):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bm.transform(Matrix.Diagonal((*size, 1)))
        self.add(material, bm, bevel, segs, _xf(loc, rot))

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
        for material, bms in self.parts.items():
            joined = bmesh.new()
            for bm in bms:
                me = bpy.data.meshes.new("tmp")
                bm.to_mesh(me)
                joined.from_mesh(me)
                bpy.data.meshes.remove(me)
                bm.free()
            if self.turn:
                joined.transform(Matrix.Rotation(math.radians(self.turn), 4, "Z"))
            me = bpy.data.meshes.new(material)
            joined.to_mesh(me)
            joined.free()
            me.materials.append(M(material))
            me.shade_smooth()
            me.set_sharp_from_angle(angle=math.radians(40))
            ob = bpy.data.objects.new(material, me)
            scene.collection.objects.link(ob)
            ob.parent = root
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
    overalls, stubby arms. Faces +y. The game tints outfit, skin and hair."""
    p = Prop("person")
    # Legs and body: a soft pill, a touch wider at the hips.
    p.capsule("outfit", 0.16, 0.2, (0, 0, 0.38), scale=(1, 0.85, 1))
    for x in (-0.075, 0.075):
        p.capsule("outfit", 0.065, 0.1, (x, 0, 0.14))
        p.ball("shoes", 0.07, (x, 0.025, 0.04), scale=(1, 1.35, 0.7))
    # Arms hang a little out from the body, hands peeking out.
    for side in (-1, 1):
        p.capsule("outfit", 0.05, 0.14, (side * 0.19, 0, 0.42), rot=(0, side * 12, 0))
        p.ball("skin", 0.045, (side * 0.215, 0.0, 0.28))
    # Head, with ears and a soft cap of hair.
    p.ball("skin", 0.165, (0, 0, 0.7), scale=(1, 0.95, 1))
    for side in (-1, 1):
        p.ball("skin", 0.04, (side * 0.16, -0.01, 0.69), scale=(0.6, 1, 1), u=12, v=8)
    p.ball("hair", 0.172, (0, -0.02, 0.73), scale=(1.02, 0.98, 0.88))
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


MODELS = dict(bed=bed, toilet=toilet, shower=shower, table=table, desk=desk, lift=lift, door=door,
              cell_door=cell_door, person=person, tree=tree, bush=bush, flower=flower)


# ---------------------------------------------------------------- line-up

def lineup(folder):
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
    if names == ["lineup"]:
        lineup(out)
    else:
        for name in names:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            scene = bpy.context.scene
            _mats.clear()
            MODELS[name]().build().export(out)
            print("exported", name)
