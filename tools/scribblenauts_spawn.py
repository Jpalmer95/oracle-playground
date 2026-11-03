#!/usr/bin/env python3
"""Phase D — Scribblenauts 3-Tier Asset Resolver & ZeroGPU 3D Physics Compiler.

Resolves any natural-language object prompt into a ready-to-spawn Oracle Playground
SimReady asset (`<slug>.sim.json` + `<slug>.glb` or B-Rep mesh) and registers it in
`godot/config/tools.json`:

  Tier 1 (SimReady Central): Instant match against local cache or live
    `NVIDIA-Omniverse/simready-central` OpenUSD catalog (2,600+ packages).
  Tier 2 (Aether-Forge `usd-brep`): Sub-50ms parametric CAD synthesis on CPU for
    balls, marbles, ramps, U-chutes, curved pipes, balance rods, rings, rollers,
    and dominoes with adjective-driven scale & material physics.
  Tier 3 (ZeroGPU `FLUX.1-schnell` -> `microsoft/TRELLIS.2` -> Blender SimReady
    Physics Compiler): Generates a concept image on HF ZeroGPU, converts to a
    textured GLB via `TRELLIS.2` ZeroGPU (0 local VRAM), and runs Blender 5.0.1
    to rescale to real-world meters, compute `FET_033_STANDARD` mass/CoM/inertia,
    decompose into compound Jolt convex hulls, and author `GSP.001` grasp lines.

Usage:
  python3 tools/scribblenauts_spawn.py --prompt "drinking glass"
  python3 tools/scribblenauts_spawn.py --prompt "heavy brass ball" --mode brep
  python3 tools/scribblenauts_spawn.py --prompt "ancient golden chalice" --mode zerogpu
  python3 tools/scribblenauts_spawn.py --prompt "reinforced hazard crate" --from-glb godot/assets/imported/hazard_crate.glb
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIMREADY_OUT = ROOT / "godot" / "assets" / "simready"
BREP_OUT = ROOT / "godot" / "assets" / "brep"
CONCEPTS_OUT = ROOT / "godot" / "assets" / "concepts"
TOOLS_JSON = ROOT / "godot" / "config" / "tools.json"

BLENDER_BIN = os.environ.get("BLENDER_BIN", str(Path.home() / ".local" / "bin" / "blender"))
AETHER_PYTHON = Path("/home/jonathan/dev/aether-forge/.venv/bin/python")
TRELLIS_SCRIPT = Path.home() / ".hermes" / "skills" / "gaming" / "trellis-image-to-3d" / "scripts" / "trellis_gen.py"


def resolve_gradio_python() -> str:
    for cand in [
        Path("/home/jonathan/dev/idol-3dgs-studio/.venv/bin/python"),
        Path("/home/jonathan/dev/daggr-pipelines/.venv/bin/python"),
        Path(sys.executable),
    ]:
        if cand.is_file():
            res = subprocess.run([str(cand), "-c", "import gradio_client"], capture_output=True)
            if res.returncode == 0:
                return str(cand)
    return sys.executable

sys.path.insert(0, str(ROOT / "tools"))
import simready_ingest  # noqa: E402

# Semantic aliases mapping natural phrases to SimReady Central package slugs
SIMREADY_ALIASES = {
    "hammer": "hammer",
    "claw hammer": "hammer",
    "mallet": "hammer",
    "screwdriver": "screwdriver",
    "mug": "mug",
    "coffee mug": "mug",
    "coffee cup": "mug",
    "cup": "mug",
    "bowl": "bowl",
    "cereal bowl": "bowl",
    "mixing bowl": "bowl",
    "scissors": "scissors",
    "shears": "scissors",
    "seesaw": "playground_swing_seesaw",
    "swing": "playground_swing_seesaw",
    "playground": "playground_swing_seesaw",
    "spiral chute": "spiral_parcel_chute",
    "parcel chute": "spiral_parcel_chute",
    "drinking glass": "drinking_glass",
    "tumbler": "drinking_glass",
    "bar clamp": "bar_clamp",
    "clamp": "bar_clamp",
    "pliers": "pliers_family",
    "balance beam": "balance_beam_set",
    "cardboard box": "box_cardboard_a01",
    "shipping box": "box_cardboard_a01",
    "iron bucket": "cleaning_bucket_iron_a01",
    "mop bucket": "cleaning_bucket_iron_a01",
    "bucket": "cleaning_bucket_iron_a01",
}

# Real-world material physical properties (density kg/m^3, static_mu, dynamic_mu, restitution, RGB, metallic, roughness)
MATERIAL_PROFILES = {
    "steel": (7850.0, 0.45, 0.35, 0.25, [0.68, 0.71, 0.75], 0.88, 0.22),
    "iron": (7200.0, 0.50, 0.40, 0.20, [0.35, 0.36, 0.38], 0.80, 0.38),
    "brass": (8500.0, 0.42, 0.34, 0.28, [0.88, 0.68, 0.22], 0.90, 0.24),
    "gold": (19300.0, 0.45, 0.38, 0.15, [0.96, 0.78, 0.20], 0.95, 0.18),
    "copper": (8960.0, 0.44, 0.36, 0.25, [0.82, 0.46, 0.28], 0.88, 0.25),
    "wood": (680.0, 0.65, 0.50, 0.22, [0.58, 0.38, 0.22], 0.0, 0.65),
    "rubber": (1150.0, 1.35, 1.10, 0.82, [0.18, 0.18, 0.20], 0.02, 0.78),
    "ice": (917.0, 0.02, 0.015, 0.08, [0.74, 0.90, 0.98], 0.10, 0.06),
    "glass": (2500.0, 0.25, 0.20, 0.45, [0.78, 0.90, 0.95], 0.10, 0.08),
    "ceramic": (2400.0, 0.50, 0.40, 0.20, [0.90, 0.88, 0.84], 0.05, 0.25),
    "stone": (2650.0, 0.75, 0.60, 0.15, [0.52, 0.50, 0.48], 0.02, 0.80),
    "plastic": (1050.0, 0.45, 0.38, 0.35, [0.25, 0.58, 0.88], 0.0, 0.38),
}


def slugify(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    return s[:40] or "custom_prop"


def load_hf_token() -> str:
    tok = os.environ.get("HF_TOKEN", "").strip()
    if tok:
        return tok
    env_file = Path.home() / ".hermes" / ".env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if line.startswith("HF_TOKEN="):
                val = line.split("=", 1)[1].strip().strip('"').strip("'")
                if val:
                    os.environ["HF_TOKEN"] = val
                    return val
    return ""


def estimate_simready_physics(prompt: str) -> dict:
    """Estimate real-world dimensions (meters), material profile, mass (kg),
    Wikidata Q-Code, hollowness, and CoM bias following SimReady FET_033_STANDARD@0.4.0.
    """
    low = prompt.lower()

    # 1. Material detection
    mat_key = "wood"
    for k in MATERIAL_PROFILES:
        if k in low:
            mat_key = k
            break
    else:
        if any(w in low for w in ["anvil", "kettle", "sword", "wrench", "dumbbell", "bell", "gear", "anchor"]):
            mat_key = "iron"
        elif any(w in low for w in ["goblet", "chalice", "trophy", "crown", "coin"]):
            mat_key = "gold" if "gold" in low else "brass"
        elif any(w in low for w in ["tire", "ball", "duck", "boot"]):
            mat_key = "rubber"
        elif any(w in low for w in ["bottle", "jar", "flask", "vial"]):
            mat_key = "glass"
        elif any(w in low for w in ["vase", "pot", "mug", "teacup", "plate"]):
            mat_key = "ceramic"
        elif any(w in low for w in ["statue", "boulder", "rock", "pillar", "brick"]):
            mat_key = "stone"

    dens, s_mu, d_mu, bounce, rgb, met, rough = MATERIAL_PROFILES[mat_key]

    # 2. Scale multiplier from adjectives
    scale_mult = 1.0
    if any(w in low for w in ["tiny", "mini", "small", "little"]):
        scale_mult = 0.6
    elif any(w in low for w in ["large", "big", "giant", "huge", "heavy"]):
        scale_mult = 1.45

    # 3. Archetype extents [x, y, z] in Godot Y-up meters, fill factor, hollow flag, CoM shift
    extents = [0.28, 0.28, 0.28]
    fill_factor = 0.42
    is_hollow = False
    com_bias = [0.0, 0.0, 0.0]
    qcode = "Q2424752"
    category = "prop"

    if any(w in low for w in ["crate", "box", "chest", "trunk", "container"]):
        extents = [0.52, 0.48, 0.52]
        fill_factor = 0.28
        is_hollow = "open" in low or "hollow" in low
        qcode = "Q1395006"
        category = "container"
    elif any(w in low for w in ["goblet", "chalice", "cup", "vase", "trophy", "bucket", "pot", "bowl"]):
        extents = [0.16, 0.22, 0.16]
        fill_factor = 0.22
        is_hollow = True
        com_bias = [0.0, -0.03, 0.0]
        qcode = "Q386215"
        category = "tableware"
    elif any(w in low for w in ["kettle", "teapot", "jug", "pitcher", "lantern"]):
        extents = [0.24, 0.26, 0.22]
        fill_factor = 0.35
        com_bias = [0.0, -0.025, 0.0]
        qcode = "Q47107"
        category = "vessel"
    elif any(w in low for w in ["club", "mace", "axe", "hammer", "sledge", "bat", "wand", "staff", "sword"]):
        extents = [0.75, 0.14, 0.14]
        fill_factor = 0.24
        com_bias = [0.18, 0.0, 0.0]
        qcode = "Q25294"
        category = "hand tool"
    elif any(w in low for w in ["pin", "bowling", "bottle", "cone", "statue"]):
        extents = [0.12, 0.38, 0.12]
        fill_factor = 0.36
        com_bias = [0.0, -0.05, 0.0]
        qcode = "Q80228"
        category = "prop"
    elif any(w in low for w in ["anvil", "weight", "kettlebell", "dumbbell"]):
        extents = [0.42, 0.26, 0.20]
        fill_factor = 0.55
        com_bias = [0.0, -0.02, 0.0]
        qcode = "Q104363"
        category = "heavy_prop"

    extents = [round(e * scale_mult, 4) for e in extents]
    com_bias = [round(c * scale_mult, 4) for c in com_bias]
    bbox_vol = extents[0] * extents[1] * extents[2]
    est_mass = round(max(0.05, min(180.0, bbox_vol * fill_factor * dens)), 4)

    # FET_033_STANDARD density plausibility gate (1..23000 kg/m^3)
    implied_density = est_mass / max(1e-6, bbox_vol * fill_factor)
    assert 1.0 <= implied_density <= 23000.0, f"Implausible density: {implied_density}"

    return {
        "material_key": mat_key,
        "density": dens,
        "static_friction": s_mu,
        "dynamic_friction": d_mu,
        "restitution": bounce,
        "color": rgb,
        "metallic": met,
        "roughness": rough,
        "asset_extents": extents,
        "mass": est_mass,
        "is_hollow": is_hollow,
        "com_bias": com_bias,
        "qcode": qcode,
        "category": category,
    }


def register_tool_in_config(slug: str, display_name: str, kind: str, palette_id: str = "scribblenauts") -> None:
    if not TOOLS_JSON.is_file():
        return
    data = json.loads(TOOLS_JSON.read_text(encoding="utf-8"))
    palettes = data.setdefault("palettes", {})
    tools = data.setdefault("tools", {})

    if palette_id not in palettes:
        palettes[palette_id] = {"name": "Scribblenauts", "tools": []}
    tool_id = slug if slug.startswith(("sr_", "brep_", "scb_")) else f"scb_{slug}"
    tools[tool_id] = {
        "name": display_name[:26],
        "category": palette_id,
        "kind": kind,
        "params": {"slug": slug},
    }
    if tool_id not in palettes[palette_id]["tools"]:
        palettes[palette_id]["tools"].append(tool_id)

    tmp = TOOLS_JSON.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(TOOLS_JSON)


def try_tier1_simready(prompt: str) -> tuple[str, Path] | None:
    low = prompt.lower().strip()
    # Direct alias check
    matched_slug = SIMREADY_ALIASES.get(low)
    if not matched_slug:
        for phrase, target in SIMREADY_ALIASES.items():
            if phrase in low:
                matched_slug = target
                break

    # Check if already compiled locally
    if matched_slug:
        local_sim = SIMREADY_OUT / matched_slug / f"{matched_slug}.sim.json"
        if local_sim.is_file():
            register_tool_in_config(matched_slug, prompt.title(), "simready")
            return matched_slug, local_sim
        try:
            out_json = simready_ingest.ingest_remote(matched_slug)
            register_tool_in_config(matched_slug, prompt.title(), "simready")
            return matched_slug, out_json
        except Exception as exc:
            print(f"Tier 1 alias ingest warning: {exc}", file=sys.stderr)

    # Search live SimReady Central catalog for exact slug/token match
    slug_cand = slugify(prompt)
    if (SIMREADY_OUT / slug_cand / f"{slug_cand}.sim.json").is_file():
        return slug_cand, SIMREADY_OUT / slug_cand / f"{slug_cand}.sim.json"

    hits = simready_ingest.search_catalog(slug_cand)
    for s, _url in hits:
        if s.lower() == slug_cand:
            out_json = simready_ingest.ingest_remote(s)
            register_tool_in_config(s, prompt.title(), "simready")
            return s, out_json
    return None


BREP_PARAMETRIC_CODE = r'''
import json
import math
import sys
import time
from pathlib import Path
import usd_brep as sm

spec_in = json.loads(sys.argv[1])
out_dir = Path(sys.argv[2])
slug = spec_in["slug"]
shape = spec_in["shape"]
ext = spec_in["asset_extents"]
mat_key = spec_in["material_key"]


def zup_to_yup(pts):
    return [[round(float(p[0]), 6), round(float(p[2]), 6), round(float(-p[1]), 6)] for p in pts]


def triangulate(faces):
    indices = []
    i = 0
    n = len(faces)
    while i < n:
        c = int(faces[i])
        if c < 3 or i + 1 + c > n:
            break
        base = int(faces[i + 1])
        for k in range(1, c - 1):
            indices.extend((base, int(faces[i + 1 + k]), int(faces[i + 2 + k])))
        i += 1 + c
    return indices


t0 = time.perf_counter()
colliders = []
grasp_lines = []
com = [0.0, 0.0, 0.0]

if shape == "sphere":
    r = max(0.02, ext[0] * 0.5)
    brep = sm.create_sphere((0.0, 0.0, 0.0), r)
    colliders.append({
        "name": "analytic_sphere",
        "type": "sphere",
        "radius": round(r, 5),
        "position": [0.0, 0.0, 0.0],
        "rotation": [0.0, 0.0, 0.0, 1.0],
        "material": mat_key,
    })
elif shape == "cylinder":
    r = max(0.02, ext[0] * 0.5)
    h = max(0.04, ext[1])
    brep = sm.create_cylinder((0.0, 0.0, -h * 0.5), r, h)
    colliders.append({
        "name": "analytic_cylinder",
        "type": "cylinder",
        "radius": round(r, 5),
        "height": round(h, 5),
        "position": [0.0, 0.0, 0.0],
        "rotation": [0.0, 0.0, 0.0, 1.0],
        "material": mat_key,
    })
    grasp_lines.append({"name": "grasp_shaft", "a": [0.0, -h * 0.25, 0.0], "b": [0.0, h * 0.25, 0.0]})
elif shape == "chute":
    length, height, width = ext[0], ext[1], ext[2]
    wall = max(0.015, min(width, height) * 0.16)
    outer = sm.create_box((-length * 0.5, -width * 0.5, -height * 0.5), length, width, height)
    inner = sm.create_box(
        (-length * 0.5 - 0.02, -(width - 2 * wall) * 0.5, -height * 0.5 + wall),
        length + 0.04,
        width - 2 * wall,
        height,
    )
    brep = sm.boolean_difference(outer.copy(), inner.copy())
    colliders = [
        {"name": "floor", "type": "box", "size": [length, wall, width], "position": [0.0, -height * 0.5 + wall * 0.5, 0.0], "rotation": [0.0, 0.0, 0.0, 1.0], "material": mat_key},
        {"name": "wall_l", "type": "box", "size": [length, height - wall, wall], "position": [0.0, wall * 0.5, (width - wall) * 0.5], "rotation": [0.0, 0.0, 0.0, 1.0], "material": mat_key},
        {"name": "wall_r", "type": "box", "size": [length, height - wall, wall], "position": [0.0, wall * 0.5, -(width - wall) * 0.5], "rotation": [0.0, 0.0, 0.0, 1.0], "material": mat_key},
    ]
    grasp_lines.append({"name": "grasp_mid", "a": [-0.15, 0.0, 0.0], "b": [0.15, 0.0, 0.0]})
elif shape == "rod":
    length = max(0.6, ext[0])
    r = max(0.018, ext[1] * 0.2)
    shaft = sm.create_box((-length * 0.5, -r, -r), length, r * 2.0, r * 2.0)
    head_r = r * 3.0
    head = sm.create_sphere((length * 0.35, 0.0, 0.0), head_r)
    brep = sm.boolean_union(shaft.copy(), head.copy())
    com = [round(length * 0.24, 4), 0.0, 0.0]
    colliders = [
        {"name": "shaft", "type": "box", "size": [length, r * 2.0, r * 2.0], "position": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0, 1.0], "material": mat_key},
        {"name": "head", "type": "sphere", "radius": round(head_r, 5), "position": [round(length * 0.35, 4), 0.0, 0.0], "rotation": [0.0, 0.0, 0.0, 1.0], "material": mat_key},
    ]
    grasp_lines.append({"name": "grasp_com", "a": [com[0] - 0.08, 0.0, 0.0], "b": [com[0] + 0.08, 0.0, 0.0]})
else:
    # Default precision block / domino
    lx, ly, lz = ext[0], ext[2], ext[1]
    brep = sm.create_box((-lx * 0.5, -ly * 0.5, -lz * 0.5), lx, ly, lz)
    colliders = [
        {"name": "box", "type": "box", "size": [lx, lz, ly], "position": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0, 1.0], "material": mat_key}
    ]
    grasp_lines.append({"name": "grasp_top", "a": [0.0, lz * 0.25, -ly * 0.25], "b": [0.0, lz * 0.25, ly * 0.25]})

vol = max(1e-5, float(sm.compute_volume(brep)))
mass = round(max(0.05, min(180.0, vol * float(spec_in["density"]))), 4)
mesh = sm.tessellate(brep, chord_height_tolerance=0.002, surface_angle_tolerance_deg=18.0)
arrays = mesh.to_numpy_arrays()
pts_yup = zup_to_yup(arrays["points"])
norms_yup = zup_to_yup(arrays["normals"])
indices = triangulate(arrays["faces"])
ms = (time.perf_counter() - t0) * 1000.0

out_dir.mkdir(parents=True, exist_ok=True)
try:
    sm.usd.export_brep(brep.copy(), str(out_dir / f"{slug}.brep.usd"))
except Exception:
    pass

sim_json = {
    "schema_version": "simready.oracle.v1",
    "slug": slug,
    "package_id": f"aetherforge.brep.{slug}",
    "asset_name": slug,
    "category": "rube_goldberg",
    "qcode": spec_in["qcode"],
    "license": "Apache-2.0",
    "author": "Aether-Forge usd-brep",
    "asset_extents": ext,
    "mass": mass,
    "rigid_body_count": 1,
    "manifold": bool(sm.poly_brep_is_manifold_via_api(mesh)),
    "tessellate_ms": round(ms, 2),
    "visual_mesh": {
        "points": pts_yup,
        "normals": norms_yup,
        "indices": indices,
        "color": spec_in["color"],
        "metallic": spec_in["metallic"],
        "roughness": spec_in["roughness"],
    },
    "rigid_bodies": [
        {
            "name": slug,
            "usd_path": f"/{slug}",
            "position": [0.0, 0.0, 0.0],
            "rotation": [0.0, 0.0, 0.0, 1.0],
            "mass": mass,
            "center_of_mass": com,
            "inertia": [round(mass * 0.04, 5)] * 3,
            "physics_material": {
                "name": mat_key,
                "label": mat_key.title(),
                "static_friction": spec_in["static_friction"],
                "dynamic_friction": spec_in["dynamic_friction"],
                "restitution": spec_in["restitution"],
                "density": spec_in["density"],
            },
            "colliders": colliders,
            "grasp_lines": grasp_lines,
        }
    ],
    "joints": [],
}
out_file = out_dir / f"{slug}.sim.json"
out_file.write_text(json.dumps(sim_json, indent=2) + "\n", encoding="utf-8")
print(f"SCRIBBLENAUTS_BREP_OK slug={slug} mass={mass}kg ms={ms:.1f}")
'''


def try_tier2_brep(prompt: str, force: bool = False) -> tuple[str, Path] | None:
    low = prompt.lower()
    shape = ""
    phys = estimate_simready_physics(prompt)
    if any(w in low for w in ["ball", "sphere", "marble", "orb", "globe"]):
        shape = "sphere"
        phys["asset_extents"] = [0.11, 0.11, 0.11]
    elif any(w in low for w in ["chute", "ramp", "trough", "slide", "track", "halfpipe"]):
        shape = "chute"
        phys["asset_extents"] = [1.4, 0.11, 0.20]
    elif any(w in low for w in ["rod", "staff", "pole", "lever", "bar", "stick", "cane"]):
        shape = "rod"
        phys["asset_extents"] = [1.5, 0.12, 0.12]
    elif any(w in low for w in ["cylinder", "roller", "drum", "pillar", "column"]):
        shape = "cylinder"
        phys["asset_extents"] = [0.16, 0.45, 0.16]
    elif any(w in low for w in ["domino", "tile", "slab", "plank", "brick"]):
        shape = "domino"
        phys["asset_extents"] = [0.022, 0.20, 0.10]
    elif force:
        shape = "domino"

    if not shape or not AETHER_PYTHON.is_file():
        return None

    # Apply size modifier
    mult = 1.0
    if any(w in low for w in ["large", "big", "giant", "long", "heavy"]):
        mult = 1.35
    elif any(w in low for w in ["small", "tiny", "mini", "short"]):
        mult = 0.65
    phys["asset_extents"] = [round(x * mult, 4) for x in phys["asset_extents"]]

    slug = f"brep_{slugify(prompt)}"
    phys["slug"] = slug
    phys["shape"] = shape
    out_dir = BREP_OUT / slug
    res = subprocess.run(
        [str(AETHER_PYTHON), "-c", BREP_PARAMETRIC_CODE, json.dumps(phys), str(out_dir)],
        capture_output=True,
        text=True,
        check=True,
    )
    for line in res.stdout.splitlines():
        if "SCRIBBLENAUTS_BREP_OK" in line:
            print(line)
    out_json = out_dir / f"{slug}.sim.json"
    register_tool_in_config(slug, prompt.title(), "brep")
    return slug, out_json


BLENDER_GLB_SIMREADY_COMPILER = r'''
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
in_glb = Path(argv[0])
out_glb = Path(argv[1])
out_json = Path(argv[2])
slug = argv[3]
phys = json.loads(argv[4])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(in_glb))

mesh_objs = [o for o in bpy.context.scene.objects if o.type == "MESH" and len(o.data.vertices) > 0]
if not mesh_objs:
    raise RuntimeError(f"No mesh objects found in {in_glb}")

# Compute combined world bounding box
min_v = Vector((1e9, 1e9, 1e9))
max_v = Vector((-1e9, -1e9, -1e9))
for obj in mesh_objs:
    for corner in obj.bound_box:
        wc = obj.matrix_world @ Vector(corner)
        min_v.x = min(min_v.x, wc.x)
        min_v.y = min(min_v.y, wc.y)
        min_v.z = min(min_v.z, wc.z)
        max_v.x = max(max_v.x, wc.x)
        max_v.y = max(max_v.y, wc.y)
        max_v.z = max(max_v.z, wc.z)

center = (min_v + max_v) * 0.5
raw_size = max_v - min_v
# Target extents in Godot Y-up [wx, wy, wz] -> Blender Z-up [wx, wz, wy]
target_yup = phys["asset_extents"]
target_blender = Vector((float(target_yup[0]), float(target_yup[2]), float(target_yup[1])))

# Uniform or axis scale so the object matches real-world meters
ratios = [
    target_blender.x / max(1e-4, raw_size.x),
    target_blender.y / max(1e-4, raw_size.y),
    target_blender.z / max(1e-4, raw_size.z),
]
scale_factor = sum(ratios) / 3.0

# Create a single joined evaluation copy to extract compound convex hulls in Y-up
bpy.ops.object.select_all(action="DESELECT")
for obj in mesh_objs:
    obj.location = (obj.location - center) * scale_factor
    obj.scale = obj.scale * scale_factor

# Export rescaled real-world meters GLB
out_glb.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(out_glb),
    export_format="GLB",
    export_yup=True,
    export_apply=True,
)

# Collect all world-space vertices in Godot Y-up: (x_b, z_b, -y_b)
all_yup_pts = []
for obj in mesh_objs:
    mat = obj.matrix_world
    # Account for scale_factor applied above
    for v in obj.data.vertices:
        wv = (mat @ v.co - center) * scale_factor
        all_yup_pts.append([round(float(wv.x), 5), round(float(wv.z), 5), round(float(-wv.y), 5)])

# Partition vertices into octants/quadrants to form compound convex hulls (preserving concavity for hollow props!)
colliders = []
if phys.get("is_hollow") and len(all_yup_pts) >= 32:
    # 8 angular sectors around the Y axis + floor slab so containers/crates/goblets have a hollow interior
    sectors = [[] for _ in range(8)]
    floor_pts = []
    min_y = min(p[1] for p in all_yup_pts)
    max_y = max(p[1] for p in all_yup_pts)
    floor_cut = min_y + (max_y - min_y) * 0.22
    for p in all_yup_pts:
        if p[1] <= floor_cut:
            floor_pts.append(p)
        ang = math.atan2(p[2], p[0])
        sec = int(((ang + math.pi) / (2.0 * math.pi)) * 8.0) % 8
        sectors[sec].append(p)
    if len(floor_pts) >= 4:
        step = max(1, len(floor_pts) // 32)
        colliders.append({"name": "hull_floor", "type": "convex_hull", "points": floor_pts[::step][:36], "material": phys["material_key"]})
    for idx, s_pts in enumerate(sectors):
        if len(s_pts) >= 4:
            step = max(1, len(s_pts) // 28)
            colliders.append({"name": f"hull_sector_{idx}", "type": "convex_hull", "points": s_pts[::step][:32], "material": phys["material_key"]})
else:
    # Split along primary axis into 2 compound hulls (handle + head) so tools have accurate contours
    left_pts = [p for p in all_yup_pts if p[0] <= 0.02]
    right_pts = [p for p in all_yup_pts if p[0] >= -0.02]
    for tag, group in [("hull_a", left_pts), ("hull_b", right_pts)]:
        if len(group) >= 4:
            step = max(1, len(group) // 40)
            colliders.append({"name": tag, "type": "convex_hull", "points": group[::step][:44], "material": phys["material_key"]})

if not colliders:
    step = max(1, len(all_yup_pts) // 48)
    colliders.append({"name": "hull_main", "type": "convex_hull", "points": all_yup_pts[::step][:48], "material": phys["material_key"]})

ext = phys["asset_extents"]
mass = float(phys["mass"])
ix = round(mass * (ext[1] ** 2 + ext[2] ** 2) / 12.0, 5)
iy = round(mass * (ext[0] ** 2 + ext[2] ** 2) / 12.0, 5)
iz = round(mass * (ext[0] ** 2 + ext[1] ** 2) / 12.0, 5)

com = phys.get("com_bias", [0.0, 0.0, 0.0])
grasp_lines = [
    {
        "name": "grasp_identifier_01",
        "a": [round(com[0] - ext[0] * 0.18, 4), round(com[1], 4), 0.0],
        "b": [round(com[0] + ext[0] * 0.18, 4), round(com[1], 4), 0.0],
    }
]

sim_spec = {
    "schema_version": "simready.oracle.v1",
    "slug": slug,
    "package_id": f"simready.zerogpu.{slug}.v1",
    "asset_name": slug,
    "category": phys["category"],
    "qcode": phys["qcode"],
    "license": "Apache-2.0",
    "author": "Oracle Playground ZeroGPU + SimReady Compiler",
    "asset_extents": ext,
    "mass": mass,
    "rigid_body_count": 1,
    "glb_file": out_glb.name,
    "rigid_bodies": [
        {
            "name": slug,
            "usd_path": f"/{slug}",
            "position": [0.0, 0.0, 0.0],
            "rotation": [0.0, 0.0, 0.0, 1.0],
            "mass": mass,
            "center_of_mass": com,
            "inertia": [max(0.0002, ix), max(0.0002, iy), max(0.0002, iz)],
            "physics_material": {
                "name": phys["material_key"],
                "label": phys["material_key"].title(),
                "static_friction": phys["static_friction"],
                "dynamic_friction": phys["dynamic_friction"],
                "restitution": phys["restitution"],
                "density": phys["density"],
            },
            "colliders": colliders,
            "grasp_lines": grasp_lines,
        }
    ],
    "joints": [],
}

out_json.parent.mkdir(parents=True, exist_ok=True)
out_json.write_text(json.dumps(sim_spec, indent=2) + "\n", encoding="utf-8")
print(f"SCRIBBLENAUTS_GLB_OK slug={slug} hulls={len(colliders)} mass={mass:.3f}kg com={com}")
'''


def compile_glb_to_simready(glb_path: Path, prompt: str, slug: str = "") -> tuple[str, Path]:
    slug = slug or slugify(prompt)
    phys = estimate_simready_physics(prompt)
    out_dir = SIMREADY_OUT / slug
    out_glb = out_dir / f"{slug}.glb"
    out_json = out_dir / f"{slug}.sim.json"

    cmd = [
        BLENDER_BIN,
        "-b",
        "--factory-startup",
        "--python-expr",
        BLENDER_GLB_SIMREADY_COMPILER,
        "--",
        str(glb_path.resolve()),
        str(out_glb),
        str(out_json),
        slug,
        json.dumps(phys),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if res.returncode != 0 or not out_json.is_file():
        print(res.stdout, file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        raise RuntimeError(f"Blender GLB->SimReady compilation failed for {slug}")
    for line in res.stdout.splitlines():
        if "SCRIBBLENAUTS_GLB_OK" in line:
            print(line)
    register_tool_in_config(slug, prompt.title(), "simready")
    return slug, out_json


def generate_concept_image_zerogpu(prompt: str, slug: str, token: str) -> Path:
    CONCEPTS_OUT.mkdir(parents=True, exist_ok=True)
    out_png = CONCEPTS_OUT / f"{slug}.png"
    if out_png.is_file() and out_png.stat().st_size > 4096:
        return out_png

    gradio_py = resolve_gradio_python()
    full_prompt = (
        f"{prompt}, single isolated 3D game asset prop, centered with margin, "
        f"clean studio lighting, solid dark background, full silhouette visible"
    )
    helper_code = (
        "import shutil, sys; from gradio_client import Client; "
        "c = Client('black-forest-labs/FLUX.1-schnell', token=sys.argv[1]); "
        "r = c.predict(prompt=sys.argv[2], seed=42, randomize_seed=True, width=1024, height=1024, num_inference_steps=4, api_name='/infer'); "
        "it = r[0] if isinstance(r, (list, tuple)) else r; "
        "p = it.get('path') or it.get('url') if isinstance(it, dict) else it; "
        "shutil.copy2(str(p), sys.argv[3])"
    )
    subprocess.run([gradio_py, "-c", helper_code, token, full_prompt, str(out_png)], check=True)
    return out_png


def run_tier3_zerogpu(prompt: str, slug: str = "") -> tuple[str, Path]:
    slug = slug or slugify(prompt)
    token = load_hf_token()
    if not token:
        raise RuntimeError("HF_TOKEN missing in environment and ~/.hermes/.env")

    gradio_py = resolve_gradio_python()
    concept_png = generate_concept_image_zerogpu(prompt, slug, token)
    with tempfile.TemporaryDirectory(prefix=f"trellis_{slug}_") as tmp:
        raw_glb = Path(tmp) / f"{slug}_raw.glb"
        env = dict(os.environ, HF_TOKEN=token)
        cmd = [
            gradio_py,
            str(TRELLIS_SCRIPT),
            str(concept_png),
            "-o",
            str(raw_glb),
            "--name",
            slug,
            "--preprocess",
            "--target",
            "godot-mobile",
        ]
        subprocess.run(cmd, env=env, check=True)
        return compile_glb_to_simready(raw_glb, prompt, slug=slug)


def resolve_prompt(prompt: str, mode: str = "auto", from_glb: Path | None = None, slug: str = "") -> tuple[str, str, Path]:
    if from_glb is not None:
        s, p = compile_glb_to_simready(from_glb, prompt, slug=slug)
        return "glb_simready", s, p

    if mode in ("auto", "simready"):
        hit = try_tier1_simready(prompt)
        if hit is not None:
            return "simready", hit[0], hit[1]
        if mode == "simready":
            raise ValueError(f"No SimReady Central match for '{prompt}'")

    if mode in ("auto", "brep"):
        hit = try_tier2_brep(prompt, force=(mode == "brep"))
        if hit is not None:
            return "brep", hit[0], hit[1]
        if mode == "brep":
            raise ValueError(f"Could not synthesize B-Rep for '{prompt}'")

    if mode == "zerogpu":
        s, p = run_tier3_zerogpu(prompt, slug=slug)
        return "zerogpu", s, p

    # In auto mode, if novel prompt didn't match SimReady catalog or B-Rep keywords,
    # try ZeroGPU if HF_TOKEN is available and --allow-zerogpu is desired, else B-Rep fallback
    try:
        s, p = run_tier3_zerogpu(prompt, slug=slug)
        return "zerogpu", s, p
    except Exception as exc:
        print(f"ZeroGPU fallback to parametric B-Rep ({exc})", file=sys.stderr)
        hit = try_tier2_brep(prompt, force=True)
        assert hit is not None
        return "brep", hit[0], hit[1]


def main() -> int:
    parser = argparse.ArgumentParser(description="Phase D Scribblenauts 3-Tier Spawner + ZeroGPU Compiler")
    parser.add_argument("--prompt", required=True, help="Natural language description of the object to spawn")
    parser.add_argument("--mode", choices=["auto", "simready", "brep", "zerogpu"], default="auto")
    parser.add_argument("--from-glb", type=Path, default=None, help="Compile an existing GLB with SimReady physics for --prompt")
    parser.add_argument("--slug", default="", help="Optional explicit slug override")
    args = parser.parse_args()

    tier, final_slug, json_path = resolve_prompt(
        args.prompt,
        mode=args.mode,
        from_glb=args.from_glb,
        slug=args.slug,
    )
    result = {
        "ok": True,
        "tier": tier,
        "slug": final_slug,
        "prompt": args.prompt,
        "sim_json": str(json_path),
    }
    print("SCRIBBLENAUTS_RESULT " + json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
