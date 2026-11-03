#!/usr/bin/env python3
"""SimReady Central OpenUSD -> Godot/Jolt (.glb + .sim.json) compiler.

Queries NVIDIA-Omniverse/simready-central on Hugging Face / GitHub, downloads
the lightweight OpenUSD root + physics layers (avoiding multi-hundred-MB 8K
texture bloat unless --with-textures is passed), and uses Blender 5.0's bundled
OpenUSD (`pxr`) + glTF 2.0 exporter to produce:
  godot/assets/simready/<slug>/<slug>.glb
  godot/assets/simready/<slug>/<slug>.sim.json

Usage:
  python3 tools/simready_ingest.py --search "hammer"
  python3 tools/simready_ingest.py --ingest hammer screwdriver mug bowl playground_swing_seesaw spiral_parcel_chute
  python3 tools/simready_ingest.py --local /path/to/asset.usda --slug custom_prop
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_ROOT = ROOT / "godot" / "assets" / "simready"
BLENDER_BIN = os.environ.get("BLENDER_BIN", str(Path.home() / ".local" / "bin" / "blender"))

SUBMISSION_LISTS = [
    "https://raw.githubusercontent.com/NVIDIA-Omniverse/simready-central/main/submissions/ForgeCAD/simready-assets",
    "https://raw.githubusercontent.com/NVIDIA-Omniverse/simready-central/main/submissions/nvidia/simready-assets",
    "https://raw.githubusercontent.com/NVIDIA-Omniverse/simready-central/main/submissions/Robotiq-Official/simready-assets",
]

# Curated fast-lookup catalog from NVIDIA SimReady Central so offline/CI or
# quick CLI invocations resolve immediately without GitHub rate limits.
KNOWN_PACKAGES = {
    "screwdriver": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/828771cf28d7fc2c46a7a29eadfcf7bfcc6958f8/screwdriver/com.nvidia.simready.packaging.json",
    "hammer": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/0573053fa2c9174ca2a4678a462ec4dfd3035d59/hammer/com.nvidia.simready.packaging.json",
    "mug": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/0573053fa2c9174ca2a4678a462ec4dfd3035d59/mug/com.nvidia.simready.packaging.json",
    "bowl": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/0573053fa2c9174ca2a4678a462ec4dfd3035d59/bowl/com.nvidia.simready.packaging.json",
    "drinking_glass": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/0573053fa2c9174ca2a4678a462ec4dfd3035d59/drinking_glass/com.nvidia.simready.packaging.json",
    "bar_clamp": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/0573053fa2c9174ca2a4678a462ec4dfd3035d59/bar_clamp/com.nvidia.simready.packaging.json",
    "pliers_family": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/0573053fa2c9174ca2a4678a462ec4dfd3035d59/pliers_family/com.nvidia.simready.packaging.json",
    "scissors": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/0573053fa2c9174ca2a4678a462ec4dfd3035d59/scissors/com.nvidia.simready.packaging.json",
    "balance_beam_set": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/f800a3ef92684886c7b44bc8abfd105291ea4bba/balance_beam_set/com.nvidia.simready.packaging.json",
    "articulation_test_bench": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/72ba38c2422acaba6875bd9206ddd4976dd7c16b/articulation_test_bench/com.nvidia.simready.packaging.json",
    "playground_swing_seesaw": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/8d73cc70bc5aad2c4811e36e030832eadfacd5fe/playground_swing_seesaw/com.nvidia.simready.packaging.json",
    "spiral_parcel_chute": "https://huggingface.co/datasets/ForgeCAD/simready-assets/resolve/89e7d32a159221dce50eeb25ed294a36340bffb8/spiral_parcel_chute/com.nvidia.simready.packaging.json",
    "box_cardboard_a01": "https://huggingface.co/datasets/nvidia/simready-assets/resolve/653d91e182011f357cf1644013cc94ddf194d349/box_cardboard_a01/com.nvidia.simready.packaging.json",
    "cleaning_bucket_iron_a01": "https://huggingface.co/datasets/nvidia/simready-assets/resolve/653d91e182011f357cf1644013cc94ddf194d349/cleaning_bucket_iron_a01/com.nvidia.simready.packaging.json",
}


BLENDER_EXTRACTOR_CODE = r'''
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector
from pxr import Gf, Sdf, Usd, UsdGeom, UsdPhysics, UsdShade

argv = sys.argv[sys.argv.index("--") + 1:]
root_usd_path = Path(argv[0])
phys_usd_path = Path(argv[1]) if len(argv) > 1 and argv[1] != "NONE" else None
out_glb_path = Path(argv[2])
out_json_path = Path(argv[3])
slug = argv[4]
pkg_meta = json.loads(argv[5])


def zup_vec(v):
    """Convert USD Z-up (x, y, z) to Godot Y-up (x, z, -y)."""
    return [round(float(v[0]), 6), round(float(v[2]), 6), round(float(-v[1]), 6)]


def zup_size(v):
    """Convert USD Z-up extents/scale (dx, dy, dz) to Godot Y-up positive extents (dx, dz, dy)."""
    return [abs(round(float(v[0]), 6)), abs(round(float(v[2]), 6)), abs(round(float(v[1]), 6))]


def zup_quat(q_wxyz):
    """Convert USD quaternion (w, x, y, z) in Z-up to Godot quaternion [x, y, z, w] in Y-up.
    Basis change P: (x, y, z)_godot = (x, z, -y)_usd => rotation axis (rx, ry, rz)_usd -> (rx, rz, -ry)_godot.
    """
    w, x, y, z = float(q_wxyz[0]), float(q_wxyz[1]), float(q_wxyz[2]), float(q_wxyz[3])
    return [round(x, 6), round(z, 6), round(-y, 6), round(w, 6)]


def gf_quat_to_wxyz(val):
    if val is None:
        return [1.0, 0.0, 0.0, 0.0]
    if hasattr(val, "GetReal"):
        im = val.GetImaginary()
        return [float(val.GetReal()), float(im[0]), float(im[1]), float(im[2])]
    return [1.0, 0.0, 0.0, 0.0]


def mat4_to_pos_quat_scale(m: Gf.Matrix4d):
    # USD matrices are row-major (v * M); translation is row 3.
    t = m.ExtractTranslation()
    rot = m.RemoveScaleShear().ExtractRotationQuat()
    # Extract column/row lengths for scale:
    sx = Gf.Vec3d(m[0][0], m[0][1], m[0][2]).GetLength()
    sy = Gf.Vec3d(m[1][0], m[1][1], m[1][2]).GetLength()
    sz = Gf.Vec3d(m[2][0], m[2][1], m[2][2]).GetLength()
    return (
        zup_vec(t),
        zup_quat(gf_quat_to_wxyz(rot)),
        zup_size([sx, sy, sz]),
    )


root_stage = Usd.Stage.Open(str(root_usd_path))
custom_data = root_stage.GetRootLayer().customLayerData or {}
sr_meta = custom_data.get("SimReady_Metadata", {})

extents_raw = sr_meta.get("asset_extents", [0.2, 0.2, 0.2])
asset_extents = zup_size(extents_raw)
total_mass = float(sr_meta.get("mass", 1.0) or 1.0)
qcode = str(sr_meta.get("qcode", ""))
category = str(sr_meta.get("category", "prop"))
asset_license = str(sr_meta.get("asset_license", pkg_meta.get("license", "CC-BY-4.0")))
author = str(sr_meta.get("author", pkg_meta.get("author", "NVIDIA SimReady")))

# Parse visual materials from root stage
visual_materials = {}
for prim in root_stage.TraverseAll():
    if prim.GetTypeName() == "Shader":
        shader = UsdShade.Shader(prim)
        dc = prim.GetAttribute("inputs:diffuseColor").Get()
        met = prim.GetAttribute("inputs:metallic").Get()
        rough = prim.GetAttribute("inputs:roughness").Get()
        mat_prim = prim.GetParent()
        if dc is not None:
            visual_materials[str(mat_prim.GetPath())] = {
                "name": mat_prim.GetName(),
                "color": [float(dc[0]), float(dc[1]), float(dc[2])],
                "metallic": float(met) if met is not None else 0.0,
                "roughness": float(rough) if rough is not None else 0.5,
            }

phys_stage = Usd.Stage.Open(str(phys_usd_path)) if phys_usd_path and phys_usd_path.exists() else root_stage
xform_cache = UsdGeom.XformCache(Usd.TimeCode.Default())

# Parse PhysicsMaterials
physics_materials = {}
for prim in phys_stage.TraverseAll():
    schemas = prim.GetAppliedSchemas()
    if "PhysicsMaterialAPI" in schemas:
        sf = prim.GetAttribute("physics:staticFriction").Get()
        df = prim.GetAttribute("physics:dynamicFriction").Get()
        rest = prim.GetAttribute("physics:restitution").Get()
        dens = prim.GetAttribute("physics:density").Get()
        label_attr = prim.GetAttribute("semantics:labels:material").Get()
        label = str(label_attr[0]) if label_attr and len(label_attr) > 0 else prim.GetName()
        physics_materials[str(prim.GetPath())] = {
            "name": prim.GetName(),
            "label": label,
            "static_friction": round(float(sf if sf is not None else 0.5), 4),
            "dynamic_friction": round(float(df if df is not None else 0.4), 4),
            "restitution": round(float(rest if rest is not None else 0.1), 4),
            "density": round(float(dens if dens is not None else 1000.0), 2),
        }

# Find all rigid body prims
rb_prims = []
for prim in phys_stage.TraverseAll():
    schemas = prim.GetAppliedSchemas()
    if "PhysicsRigidBodyAPI" in schemas:
        rb_prims.append(prim)

rb_paths = {str(p.GetPath()): p for p in rb_prims}


def find_owning_rb(prim):
    cur = prim
    while cur and cur.IsValid():
        p = str(cur.GetPath())
        if p in rb_paths:
            return p
        cur = cur.GetParent()
    return None


def material_color_guess(mat_name: str):
    n = mat_name.lower()
    if "steel" in n or "chrome" in n or "iron" in n or "metal" in n:
        return [0.68, 0.71, 0.75], 0.85, 0.25
    if "rubber" in n or "tpe" in n or "tpr" in n or "epdm" in n or "grip" in n:
        return [0.16, 0.17, 0.19], 0.05, 0.78
    if "wood" in n or "cardboard" in n:
        return [0.62, 0.43, 0.25], 0.0, 0.65
    if "glass" in n:
        return [0.78, 0.90, 0.96], 0.1, 0.08
    if "red" in n or "fibreglass" in n:
        return [0.76, 0.16, 0.14], 0.05, 0.38
    if "hdpe" in n or "poly" in n or "plastic" in n or "abs" in n:
        return [0.85, 0.58, 0.12], 0.0, 0.4
    return [0.72, 0.70, 0.66], 0.1, 0.45


def get_prim_local_matrix(prim) -> Gf.Matrix4d:
    sim_m = prim.GetAttribute("xformOp:transform:simulationWorld").Get()
    if sim_m is not None:
        return Gf.Matrix4d(sim_m)
    xf_m = prim.GetAttribute("xformOp:transform").Get()
    if xf_m is not None:
        return Gf.Matrix4d(xf_m)
    xf = UsdGeom.Xformable(prim)
    if xf:
        res = xf.GetLocalTransformation()
        if isinstance(res, tuple):
            return res[0]
        return res
    t = prim.GetAttribute("xformOp:translate").Get()
    q = prim.GetAttribute("xformOp:orient").Get()
    s = prim.GetAttribute("xformOp:scale").Get()
    m = Gf.Matrix4d(1.0)
    if s is not None:
        ms = Gf.Matrix4d(1.0)
        ms.SetScale(Gf.Vec3d(float(s[0]), float(s[1]), float(s[2])))
        m = m * ms
    if q is not None:
        mr = Gf.Matrix4d(1.0)
        mr.SetRotate(q)
        m = m * mr
    if t is not None:
        mt = Gf.Matrix4d(1.0)
        mt.SetTranslate(Gf.Vec3d(float(t[0]), float(t[1]), float(t[2])))
        m = m * mt
    return m


rigid_bodies_data = {}
for rb in rb_prims:
    rb_path = str(rb.GetPath())
    world_m = get_prim_local_matrix(rb)
    pos, quat, scale = mat4_to_pos_quat_scale(world_m)

    m_val = rb.GetAttribute("physics:mass").Get()
    if m_val is None:
        m_val = rb.GetAttribute("pxr:usd:physics_mass").Get()
    mass_kg = float(m_val) if m_val is not None else total_mass / max(1, len(rb_prims))

    com_val = rb.GetAttribute("physics:centerOfMass").Get()
    if com_val is None:
        com_val = rb.GetAttribute("pxr:usd:physics_centerofmass").Get()
    com_yup = zup_vec(com_val) if com_val is not None else [0.0, 0.0, 0.0]

    in_val = rb.GetAttribute("physics:diagonalInertia").Get()
    if in_val is None:
        in_val = rb.GetAttribute("pxr:usd:physics_inertia").Get()
    inertia_yup = zup_size(in_val) if in_val is not None else [0.01, 0.01, 0.01]

    rigid_bodies_data[rb_path] = {
        "name": rb.GetName(),
        "usd_path": rb_path,
        "position": pos,
        "rotation": quat,
        "mass": round(max(0.01, mass_kg), 6),
        "center_of_mass": com_yup,
        "inertia": inertia_yup,
        "physics_material": None,
        "colliders": [],
        "grasp_lines": [],
    }

# Collect colliders and grasp lines per rigid body
for prim in phys_stage.TraverseAll():
    owner = find_owning_rb(prim)
    if not owner:
        continue
    rb_info = rigid_bodies_data[owner]
    rel_m = get_prim_local_matrix(prim)
    c_pos, c_quat, c_scale = mat4_to_pos_quat_scale(rel_m)

    tname = prim.GetTypeName()
    schemas = prim.GetAppliedSchemas()

    # Check bound physics material
    phys_mat = None
    rel = prim.GetRelationship("material:binding:physics")
    if rel and rel.GetTargets():
        target_path = str(rel.GetTargets()[0])
        phys_mat = physics_materials.get(target_path)
        if phys_mat and rb_info["physics_material"] is None:
            rb_info["physics_material"] = phys_mat

    if tname == "BasisCurves" or "grasp_identifier" in prim.GetName():
        pts = prim.GetAttribute("points").Get()
        if pts and len(pts) >= 2:
            p0 = rel_m.Transform(Gf.Vec3d(pts[0][0], pts[0][1], pts[0][2]))
            p1 = rel_m.Transform(Gf.Vec3d(pts[1][0], pts[1][1], pts[1][2]))
            rb_info["grasp_lines"].append({
                "name": prim.GetName(),
                "a": zup_vec(p0),
                "b": zup_vec(p1),
            })
        continue

    if "PhysicsCollisionAPI" not in schemas:
        continue

    mat_tag = phys_mat["name"] if phys_mat else prim.GetName()

    if tname == "Sphere":
        r = float(prim.GetAttribute("radius").Get() or 0.05)
        rb_info["colliders"].append({
            "name": prim.GetName(),
            "type": "sphere",
            "radius": round(r * max(c_scale), 6),
            "position": c_pos,
            "rotation": c_quat,
            "material": mat_tag,
        })
    elif tname in ("Capsule", "Cylinder"):
        r = float(prim.GetAttribute("radius").Get() or 0.02)
        h = float(prim.GetAttribute("height").Get() or 0.1)
        axis = str(prim.GetAttribute("axis").Get() or "Z")
        rb_info["colliders"].append({
            "name": prim.GetName(),
            "type": tname.lower(),
            "radius": round(r, 6),
            "height": round(h if tname == "Cylinder" else h + 2.0 * r, 6),
            "axis": axis,
            "position": c_pos,
            "rotation": c_quat,
            "scale": c_scale,
            "material": mat_tag,
        })
    elif tname == "Cube":
        sz = float(prim.GetAttribute("size").Get() or 1.0)
        rb_info["colliders"].append({
            "name": prim.GetName(),
            "type": "box",
            "size": [round(sz * c_scale[0], 6), round(sz * c_scale[1], 6), round(sz * c_scale[2], 6)],
            "position": c_pos,
            "rotation": c_quat,
            "material": mat_tag,
        })
    elif tname == "Mesh":
        pts = prim.GetAttribute("points").Get()
        fvc = prim.GetAttribute("faceVertexCounts").Get()
        fvi = prim.GetAttribute("faceVertexIndices").Get()
        if pts and len(pts) >= 4:
            # Transform points into the RigidBody's local Z-up space, then convert to Godot Y-up
            yup_pts = []
            for p in pts:
                tp = rel_m.Transform(Gf.Vec3d(float(p[0]), float(p[1]), float(p[2])))
                yup_pts.append(zup_vec(tp))
            faces = []
            if fvc and fvi:
                idx = 0
                for count in fvc:
                    c = int(count)
                    if c >= 3 and idx + c <= len(fvi):
                        base_i = int(fvi[idx])
                        for k in range(1, c - 1):
                            # Reverse winding (0, k+1, k) if needed, or standard (base, k, k+1) since det(Z->Y) = +1
                            faces.append([base_i, int(fvi[idx + k]), int(fvi[idx + k + 1])])
                    idx += c
            rb_info["colliders"].append({
                "name": prim.GetName(),
                "type": "convex_hull",
                "points": yup_pts,
                "faces": faces,
                "material": mat_tag,
            })

# Fallback default physics material if none bound
default_phys_mat = next(iter(physics_materials.values()), {
    "name": "default",
    "label": category,
    "static_friction": 0.55,
    "dynamic_friction": 0.45,
    "restitution": 0.15,
    "density": 1000.0,
})
for rb_info in rigid_bodies_data.values():
    if rb_info["physics_material"] is None:
        rb_info["physics_material"] = default_phys_mat
    if not rb_info["colliders"]:
        # Fallback box collider from asset_extents
        rb_info["colliders"].append({
            "name": "bounds_box",
            "type": "box",
            "size": asset_extents,
            "position": [0.0, 0.0, 0.0],
            "rotation": [0.0, 0.0, 0.0, 1.0],
            "material": default_phys_mat["name"],
        })

# Parse joints (Revolute / Prismatic / Fixed)
joints_data = []
for prim in phys_stage.TraverseAll():
    tname = prim.GetTypeName()
    if tname in ("PhysicsRevoluteJoint", "PhysicsPrismaticJoint", "PhysicsFixedJoint"):
        b0_rel = prim.GetRelationship("physics:body0")
        b1_rel = prim.GetRelationship("physics:body1")
        b0 = str(b0_rel.GetTargets()[0]) if b0_rel and b0_rel.GetTargets() else ""
        b1 = str(b1_rel.GetTargets()[0]) if b1_rel and b1_rel.GetTargets() else ""
        lp0 = prim.GetAttribute("physics:localPos0").Get() or Gf.Vec3f(0, 0, 0)
        lp1 = prim.GetAttribute("physics:localPos1").Get() or Gf.Vec3f(0, 0, 0)
        axis = str(prim.GetAttribute("physics:axis").Get() or "X")
        low = prim.GetAttribute("physics:lowerLimit").Get()
        high = prim.GetAttribute("physics:upperLimit").Get()
        damp = prim.GetAttribute("drive:angular:physics:damping").Get()
        stiff = prim.GetAttribute("drive:angular:physics:stiffness").Get()

        # Map USD axis (X, Y, Z) rotated by physics:localRot0 into Godot Y-up axis
        lrot0 = prim.GetAttribute("physics:localRot0").Get()
        base_axis_usd = {"X": Gf.Vec3f(1.0, 0.0, 0.0), "Y": Gf.Vec3f(0.0, 1.0, 0.0), "Z": Gf.Vec3f(0.0, 0.0, 1.0)}.get(axis, Gf.Vec3f(1.0, 0.0, 0.0))
        if lrot0 is not None:
            rot_dir_usd = Gf.Rotation(lrot0).TransformDir(base_axis_usd)
        else:
            rot_dir_usd = base_axis_usd
        axis_yup = zup_vec(rot_dir_usd)
        jtype = "hinge" if tname == "PhysicsRevoluteJoint" else ("slider" if tname == "PhysicsPrismaticJoint" else "fixed")
        joints_data.append({
            "name": prim.GetName(),
            "type": jtype,
            "body0": rb_paths[b0].GetName() if b0 in rb_paths else "",
            "body1": rb_paths[b1].GetName() if b1 in rb_paths else "",
            "local_pos0": zup_vec(lp0),
            "local_pos1": zup_vec(lp1),
            "axis": axis_yup,
            "lower_limit": float(low) if low is not None and not math.isinf(float(low)) else -45.0,
            "upper_limit": float(high) if high is not None and not math.isinf(float(high)) else 45.0,
            "damping": float(damp) if damp is not None else 0.05,
            "stiffness": float(stiff) if stiff is not None else 0.0,
        })

# Build visual meshes in Blender (one parent Empty/Mesh per RigidBody) for clean .glb export
bpy.ops.wm.read_factory_settings(use_empty=True)
mat_cache = {}


def get_bmat(mat_tag: str):
    if mat_tag in mat_cache:
        return mat_cache[mat_tag]
    col, met, rough = material_color_guess(mat_tag)
    m = bpy.data.materials.new(name=mat_tag)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
        bsdf.inputs["Metallic"].default_value = met
        bsdf.inputs["Roughness"].default_value = rough
    mat_cache[mat_tag] = m
    return m


# Note: Blender's glTF exporter converts Blender Z-up -> glTF Y-up automatically!
# Since our collider coordinates in `rigid_bodies_data` are ALREADY converted to Godot/glTF Y-up
# `(x_g, y_g, z_g) = (x_u, z_u, -y_u)`, to have Blender export the exact same Y-up coordinates,
# we map `(x_g, y_g, z_g)` back to Blender Z-up `(x_g, -z_g, y_g)` when constructing Blender meshes!
def yup_to_blender(v):
    return (float(v[0]), -float(v[2]), float(v[1]))


def yup_quat_to_blender(q_xyzw):
    # q_xyzw in Y-up -> Blender Quaternion (w, x, y, z) in Z-up
    x, y, z, w = float(q_xyzw[0]), float(q_xyzw[1]), float(q_xyzw[2]), float(q_xyzw[3])
    return Quaternion((w, x, -z, y))


for rb_info in rigid_bodies_data.values():
    rb_empty = bpy.data.objects.new(rb_info["name"], None)
    bpy.context.collection.objects.link(rb_empty)
    rb_empty.location = yup_to_blender(rb_info["position"])
    rb_empty.rotation_mode = "QUATERNION"
    rb_empty.rotation_quaternion = yup_quat_to_blender(rb_info["rotation"])

    for idx, col in enumerate(rb_info["colliders"]):
        ctype = col["type"]
        bmat = get_bmat(col.get("material", "default"))
        obj = None
        if ctype == "convex_hull" and col.get("faces"):
            mesh = bpy.data.meshes.new(f"{rb_info['name']}_{col['name']}_{idx}")
            verts = [yup_to_blender(p) for p in col["points"]]
            mesh.from_pydata(verts, [], col["faces"])
            mesh.update()
            for poly in mesh.polygons:
                poly.use_smooth = True
            obj = bpy.data.objects.new(mesh.name, mesh)
            bpy.context.collection.objects.link(obj)
        elif ctype == "sphere":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=col["radius"], segments=18, ring_count=12)
            obj = bpy.context.active_object
            obj.location = yup_to_blender(col["position"])
        elif ctype in ("cylinder", "capsule"):
            bpy.ops.mesh.primitive_cylinder_add(radius=col["radius"], depth=col["height"], vertices=18)
            obj = bpy.context.active_object
            obj.location = yup_to_blender(col["position"])
            obj.rotation_mode = "QUATERNION"
            obj.rotation_quaternion = yup_quat_to_blender(col["rotation"])
        elif ctype == "box":
            bpy.ops.mesh.primitive_cube_add(size=1.0)
            obj = bpy.context.active_object
            sx, sy, sz = col["size"]
            obj.scale = (sx, sz, sy)
            obj.location = yup_to_blender(col["position"])
            obj.rotation_mode = "QUATERNION"
            obj.rotation_quaternion = yup_quat_to_blender(col["rotation"])

        if obj is not None:
            if obj.data and len(obj.data.materials) == 0:
                obj.data.materials.append(bmat)
            obj.parent = rb_empty
            # Strip primitive faces from JSON after building mesh so .sim.json stays compact
            if "faces" in col:
                del col["faces"]

out_glb_path.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(out_glb_path),
    export_format="GLB",
    export_yup=True,
    export_apply=False,
)

sim_spec = {
    "schema_version": "simready.oracle.v1",
    "slug": slug,
    "package_id": pkg_meta.get("package_id", f"simready.local.{slug}"),
    "asset_name": slug,
    "category": category,
    "qcode": qcode,
    "license": asset_license,
    "author": author,
    "asset_extents": asset_extents,
    "mass": round(total_mass, 6),
    "rigid_body_count": len(rigid_bodies_data),
    "glb_file": out_glb_path.name,
    "rigid_bodies": list(rigid_bodies_data.values()),
    "joints": joints_data,
}

out_json_path.write_text(json.dumps(sim_spec, indent=2) + "\n", encoding="utf-8")
print(f"SIMREADY_INGEST_OK slug={slug} bodies={len(rigid_bodies_data)} joints={len(joints_data)} mass={total_mass:.3f}kg")
'''


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_file(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=30) as resp:
        dest.write_bytes(resp.read())


def search_catalog(query: str) -> list[tuple[str, str]]:
    q = query.lower().strip()
    hits: dict[str, str] = {}
    for slug, url in KNOWN_PACKAGES.items():
        if not q or q in slug.lower():
            hits[slug] = url
    for list_url in SUBMISSION_LISTS:
        try:
            with urllib.request.urlopen(list_url, timeout=12) as resp:
                for line in resp.read().decode("utf-8").splitlines():
                    line = line.strip()
                    if not line or not line.startswith("http"):
                        continue
                    slug = line.rstrip("/").split("/")[-2]
                    if not q or q in slug.lower() or q in line.lower():
                        hits.setdefault(slug, line)
        except Exception as exc:
            print(f"warn: could not query {list_url}: {exc}", file=sys.stderr)
    return sorted(hits.items())


def resolve_package_url(slug_or_url: str) -> tuple[str, str]:
    if slug_or_url.startswith("http"):
        slug = slug_or_url.rstrip("/").split("/")[-2]
        return slug, slug_or_url
    if slug_or_url in KNOWN_PACKAGES:
        return slug_or_url, KNOWN_PACKAGES[slug_or_url]
    hits = search_catalog(slug_or_url)
    for s, u in hits:
        if s.lower() == slug_or_url.lower():
            return s, u
    if hits:
        return hits[0]
    raise ValueError(f"SimReady package '{slug_or_url}' not found in SimReady Central index.")


def ingest_remote(slug_or_url: str) -> Path:
    slug, pkg_url = resolve_package_url(slug_or_url)
    base_url = pkg_url.rsplit("/", 1)[0]
    pkg_meta = fetch_json(pkg_url)
    bom = fetch_json(f"{base_url}/.metadata/com.nvidia.simready.packaging.bom.json")

    with tempfile.TemporaryDirectory(prefix=f"simready_{slug}_") as tmp:
        tmpdir = Path(tmp)
        root_usd: Path | None = None
        phys_usd: Path | None = None

        for item in bom.get("items", []):
            rel: str = item.get("relative_path", "")
            size: int = int(item.get("size", 0))
            low = rel.lower()
            # Download root USD/USDA, physics layers, base layers, and small geometry USD layers
            is_usd = low.endswith((".usd", ".usda", ".usdc"))
            is_heavy_geom = "geometry.usda" in low and size > 4_000_000
            if is_usd and not is_heavy_geom:
                local_file = tmpdir / rel
                download_file(f"{base_url}/{rel}", local_file)
                if rel.count("/") == 1 and low.endswith((".usd", ".usda", ".usdc")):
                    root_usd = local_file
                elif "physics.usda" in low:
                    phys_usd = local_file
                elif "base.usda" in low and root_usd is None:
                    root_usd = local_file

        if root_usd is None:
            raise RuntimeError(f"No root USD found in BOM for {slug}")

        out_dir = OUT_ROOT / slug
        out_glb = out_dir / f"{slug}.glb"
        out_json = out_dir / f"{slug}.sim.json"

        cmd = [
            BLENDER_BIN,
            "-b",
            "--factory-startup",
            "--python-expr",
            BLENDER_EXTRACTOR_CODE,
            "--",
            str(root_usd),
            str(phys_usd) if phys_usd else "NONE",
            str(out_glb),
            str(out_json),
            slug,
            json.dumps(pkg_meta),
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if res.returncode != 0 or not out_json.is_file():
            print(res.stdout, file=sys.stderr)
            print(res.stderr, file=sys.stderr)
            raise RuntimeError(f"Blender USD extraction failed for {slug} (exit {res.returncode})")
        for line in res.stdout.splitlines():
            if "SIMREADY_INGEST_OK" in line:
                print(line)
        return out_json


def ingest_local(usd_path: Path, slug: str) -> Path:
    usd_path = usd_path.expanduser().resolve()
    if not usd_path.is_file():
        raise FileNotFoundError(usd_path)
    slug = slug or usd_path.stem
    phys_candidate = usd_path.parent / "forgecad" / "physics.usda"
    out_dir = OUT_ROOT / slug
    out_glb = out_dir / f"{slug}.glb"
    out_json = out_dir / f"{slug}.sim.json"
    pkg_meta = {"package_id": f"simready.local.{slug}", "license": "Apache-2.0"}
    cmd = [
        BLENDER_BIN,
        "-b",
        "--factory-startup",
        "--python-expr",
        BLENDER_EXTRACTOR_CODE,
        "--",
        str(usd_path),
        str(phys_candidate) if phys_candidate.is_file() else "NONE",
        str(out_glb),
        str(out_json),
        slug,
        json.dumps(pkg_meta),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    for line in res.stdout.splitlines():
        if "SIMREADY_INGEST_OK" in line:
            print(line)
    return out_json


def main() -> int:
    parser = argparse.ArgumentParser(description="SimReady Central -> Godot/Jolt (.glb + .sim.json) compiler")
    parser.add_argument("--search", default="", help="Search SimReady Central catalog by keyword")
    parser.add_argument("--list", action="store_true", help="List known curated SimReady packages")
    parser.add_argument("--ingest", nargs="+", default=[], help="Package slugs or URLs to ingest")
    parser.add_argument("--local", type=Path, default=None, help="Ingest a local .usd/.usda/.usdc file")
    parser.add_argument("--slug", default="", help="Slug override for --local")
    args = parser.parse_args()

    if args.list:
        for k, v in sorted(KNOWN_PACKAGES.items()):
            print(f"{k:28s} {v}")
        return 0

    if args.search:
        hits = search_catalog(args.search)
        print(f"Found {len(hits)} SimReady Central packages matching '{args.search}':")
        for s, u in hits[:40]:
            print(f"  {s:32s} {u}")
        return 0

    if args.local:
        out = ingest_local(args.local, args.slug)
        print(f"Wrote {out}")
        return 0

    if args.ingest:
        for item in args.ingest:
            out = ingest_remote(item)
            print(f"Wrote {out}")
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
