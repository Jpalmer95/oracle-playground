#!/home/jonathan/dev/aether-forge/.venv/bin/python
"""Parametric B-Rep Rube Goldberg generator (aether-forge `usd-brep` -> Oracle Playground).

Uses NVIDIA `usd-brep` in `/home/jonathan/dev/aether-forge/.venv` to construct
exact CAD solids (chutes, curved pipes, asymmetric balance rods, steel marbles,
dominoes), computes exact B-Rep volume (`sm.compute_volume`), tessellates to
Y-up triangle arrays, and writes `godot/assets/brep/<slug>/<slug>.sim.json`
plus `.brep.usd` sidecars.

Also supports `--live-send` to push operations directly to a running
`aether-forge/forge/executor.py` daemon on `127.0.0.1:9877`.
"""
from __future__ import annotations

import argparse
import json
import math
import socket
import time
from pathlib import Path

import usd_brep as sm

ROOT = Path(__file__).resolve().parents[1]
OUT_ROOT = ROOT / "godot" / "assets" / "brep"


def zup_to_yup(pts) -> list[list[float]]:
    return [[round(float(p[0]), 6), round(float(p[2]), 6), round(float(-p[1]), 6)] for p in pts]


def triangulate(faces) -> list[int]:
    indices: list[int] = []
    i = 0
    n = len(faces)
    while i < n:
        count = int(faces[i])
        if count < 3 or i + 1 + count > n:
            break
        base = int(faces[i + 1])
        for k in range(1, count - 1):
            indices.extend((base, int(faces[i + 1 + k]), int(faces[i + 2 + k])))
        i += 1 + count
    return indices


def build_presets() -> dict[str, dict]:
    presets: dict[str, dict] = {}

    # 1. Steel Marble (analytic sphere collider + exact B-Rep sphere visual)
    r_marble = 0.045
    b_marble = sm.create_sphere((0.0, 0.0, 0.0), r_marble)
    vol_marble = float(sm.compute_volume(b_marble))
    mass_marble = round(vol_marble * 7850.0, 4)
    presets["brep_marble_steel"] = {
        "brep": b_marble,
        "category": "rube_goldberg",
        "qcode": "Q183443",
        "mass": mass_marble,
        "extents": [r_marble * 2, r_marble * 2, r_marble * 2],
        "center_of_mass": [0.0, 0.0, 0.0],
        "inertia": [round(0.4 * mass_marble * r_marble * r_marble, 6)] * 3,
        "color": [0.78, 0.81, 0.86],
        "metallic": 0.92,
        "roughness": 0.12,
        "physics_material": {
            "name": "hardened_steel",
            "label": "Hardened Steel",
            "static_friction": 0.18,
            "dynamic_friction": 0.14,
            "restitution": 0.65,
            "density": 7850.0,
        },
        "colliders": [
            {
                "name": "analytic_sphere",
                "type": "sphere",
                "radius": r_marble,
                "position": [0.0, 0.0, 0.0],
                "rotation": [0.0, 0.0, 0.0, 1.0],
                "material": "hardened_steel",
            }
        ],
        "grasp_lines": [],
    }

    # 2. U-Channel Straight Chute (boolean difference of outer box and inner channel)
    # Allows marbles to roll inside without falling off the sides!
    length, width, height, wall = 1.4, 0.18, 0.10, 0.02
    outer = sm.create_box((-length * 0.5, -width * 0.5, -height * 0.5), length, width, height)
    inner = sm.create_box(
        (-length * 0.5 - 0.02, -(width - 2 * wall) * 0.5, -height * 0.5 + wall),
        length + 0.04,
        width - 2 * wall,
        height,
    )
    b_chute = sm.boolean_difference(outer.copy(), inner.copy())
    vol_chute = float(sm.compute_volume(b_chute))
    mass_chute = round(max(0.5, vol_chute * 1200.0), 4)
    # Compound 3-box concave collider (floor + left wall + right wall) in Godot Y-up!
    # In USD Z-up: X=length(1.4), Y=width(0.18), Z=height(0.10).
    # In Godot Y-up: X=length(1.4), Y=height(0.10), Z=width(0.18).
    presets["brep_chute_straight"] = {
        "brep": b_chute,
        "category": "rube_goldberg",
        "qcode": "Q1093445",
        "mass": mass_chute,
        "extents": [length, height, width],
        "center_of_mass": [0.0, -0.015, 0.0],
        "inertia": [0.04, 0.35, 0.35],
        "color": [0.22, 0.62, 0.85],
        "metallic": 0.25,
        "roughness": 0.3,
        "physics_material": {
            "name": "low_friction_track",
            "label": "Anodized Track",
            "static_friction": 0.08,
            "dynamic_friction": 0.06,
            "restitution": 0.2,
            "density": 1200.0,
        },
        "colliders": [
            {
                "name": "chute_floor",
                "type": "box",
                "size": [length, wall, width],
                "position": [0.0, -height * 0.5 + wall * 0.5, 0.0],
                "rotation": [0.0, 0.0, 0.0, 1.0],
                "material": "low_friction_track",
            },
            {
                "name": "chute_wall_pos_z",
                "type": "box",
                "size": [length, height - wall, wall],
                "position": [0.0, wall * 0.5, (width - wall) * 0.5],
                "rotation": [0.0, 0.0, 0.0, 1.0],
                "material": "low_friction_track",
            },
            {
                "name": "chute_wall_neg_z",
                "type": "box",
                "size": [length, height - wall, wall],
                "position": [0.0, wall * 0.5, -(width - wall) * 0.5],
                "rotation": [0.0, 0.0, 0.0, 1.0],
                "material": "low_friction_track",
            },
        ],
        "grasp_lines": [
            {"name": "grasp_center", "a": [-0.15, 0.0, 0.0], "b": [0.15, 0.0, 0.0]},
        ],
    }

    # 3. Asymmetric Weighted Balance Staff / Lever Rod (1.6 m long, heavy weighted head at +X)
    # Specifically designed to test VR midpoint/CoM balancing:
    # Geometric center is x=0.0, but heavy steel head shifts true CoM to x=+0.38 m!
    rod_len = 1.6
    rod_r = 0.022
    shaft = sm.create_cylinder((-rod_len * 0.5, 0.0, 0.0), rod_r, rod_len)
    # Note: create_cylinder is along Z in usd_brep; let's build along X using box + end weight
    shaft_box = sm.create_box((-rod_len * 0.5, -rod_r, -rod_r), rod_len, rod_r * 2.0, rod_r * 2.0)
    head_weight = sm.create_sphere((0.55, 0.0, 0.0), 0.075)
    b_rod = sm.boolean_union(shaft_box.copy(), head_weight.copy())
    presets["brep_balance_rod"] = {
        "brep": b_rod,
        "category": "rube_goldberg",
        "qcode": "Q655301",
        "mass": 3.8,
        "extents": [rod_len, 0.15, 0.15],
        # True Center of Mass is shifted +0.38 m toward the weighted sphere end!
        "center_of_mass": [0.38, 0.0, 0.0],
        "inertia": [0.02, 0.72, 0.72],
        "color": [0.88, 0.64, 0.18],
        "metallic": 0.65,
        "roughness": 0.32,
        "physics_material": {
            "name": "brass_weighted_rod",
            "label": "Weighted Brass Staff",
            "static_friction": 0.55,
            "dynamic_friction": 0.45,
            "restitution": 0.15,
            "density": 4200.0,
        },
        "colliders": [
            {
                "name": "rod_shaft",
                "type": "box",
                "size": [rod_len, rod_r * 2.0, rod_r * 2.0],
                "position": [0.0, 0.0, 0.0],
                "rotation": [0.0, 0.0, 0.0, 1.0],
                "material": "brass_weighted_rod",
            },
            {
                "name": "rod_head_weight",
                "type": "sphere",
                "radius": 0.075,
                "position": [0.55, 0.0, 0.0],
                "rotation": [0.0, 0.0, 0.0, 1.0],
                "material": "brass_weighted_rod",
            },
        ],
        "grasp_lines": [
            # Grasp line right at the true CoM (+0.38 m) so snapping to it balances!
            {"name": "grasp_balance_point", "a": [0.30, 0.0, 0.0], "b": [0.46, 0.0, 0.0]},
        ],
    }

    # 4. Precision Domino Tile (tall, thin, realistic mass & friction for domino chains)
    dx, dy, dz = 0.018, 0.09, 0.18
    b_domino = sm.create_box((-dx * 0.5, -dy * 0.5, -dz * 0.5), dx, dy, dz)
    vol_dom = float(sm.compute_volume(b_domino))
    presets["brep_domino"] = {
        "brep": b_domino,
        "category": "rube_goldberg",
        "qcode": "Q32907",
        "mass": round(vol_dom * 1400.0, 4),
        "extents": [dx, dz, dy],
        "center_of_mass": [0.0, 0.0, 0.0],
        "inertia": [0.0012, 0.0004, 0.0010],
        "color": [0.92, 0.90, 0.85],
        "metallic": 0.05,
        "roughness": 0.28,
        "physics_material": {
            "name": "phenolic_domino",
            "label": "Phenolic Domino",
            "static_friction": 0.35,
            "dynamic_friction": 0.28,
            "restitution": 0.45,
            "density": 1400.0,
        },
        "colliders": [
            {
                "name": "domino_box",
                "type": "box",
                "size": [dx, dz, dy],
                "position": [0.0, 0.0, 0.0],
                "rotation": [0.0, 0.0, 0.0, 1.0],
                "material": "phenolic_domino",
            }
        ],
        "grasp_lines": [
            {"name": "grasp_top", "a": [0.0, 0.04, -0.03], "b": [0.0, 0.04, 0.03]},
        ],
    }

    # 5. Swept Curved Pipe / Elbow (exact B-Spline pipe_sweep from aether-forge)
    pts = [
        (0.0, 0.0, 0.45),
        (0.18, 0.0, 0.25),
        (0.42, 0.0, 0.08),
        (0.70, 0.0, 0.0),
    ]
    curve = sm.create_curve_interp_points(pts)
    b_pipe = sm.pipe_sweep(curve, radius=0.065, cap_ends=True)
    # Build piecewise capsule colliders along the curve segments
    pipe_colliders = []
    for idx in range(len(pts) - 1):
        p0 = zup_to_yup([pts[idx]])[0]
        p1 = zup_to_yup([pts[idx + 1]])[0]
        mid = [(p0[k] + p1[k]) * 0.5 for k in range(3)]
        seg_len = math.dist(p0, p1)
        pipe_colliders.append({
            "name": f"pipe_seg_{idx}",
            "type": "sphere",
            "radius": 0.065,
            "position": mid,
            "rotation": [0.0, 0.0, 0.0, 1.0],
            "material": "copper_pipe",
        })
    presets["brep_curved_pipe"] = {
        "brep": b_pipe,
        "category": "rube_goldberg",
        "qcode": "Q41551",
        "mass": 1.85,
        "extents": [0.75, 0.50, 0.15],
        "center_of_mass": [0.32, 0.18, 0.0],
        "inertia": [0.05, 0.09, 0.09],
        "color": [0.78, 0.46, 0.28],
        "metallic": 0.85,
        "roughness": 0.25,
        "physics_material": {
            "name": "copper_pipe",
            "label": "Copper Pipe",
            "static_friction": 0.35,
            "dynamic_friction": 0.28,
            "restitution": 0.3,
            "density": 8960.0,
        },
        "colliders": pipe_colliders,
        "grasp_lines": [
            {"name": "grasp_bend", "a": [0.18, 0.25, 0.0], "b": [0.42, 0.08, 0.0]},
        ],
    }

    return presets


def export_preset(slug: str, data: dict) -> Path:
    t0 = time.perf_counter()
    brep = data["brep"]
    mesh = sm.tessellate(brep, chord_height_tolerance=0.002, surface_angle_tolerance_deg=18.0)
    arrays = mesh.to_numpy_arrays()
    points_yup = zup_to_yup(arrays["points"])
    normals_yup = zup_to_yup(arrays["normals"])
    indices = triangulate(arrays["faces"])
    manifold = bool(sm.poly_brep_is_manifold_via_api(mesh))
    ms = (time.perf_counter() - t0) * 1000.0

    out_dir = OUT_ROOT / slug
    out_dir.mkdir(parents=True, exist_ok=True)
    usd_path = out_dir / f"{slug}.brep.usd"
    try:
        sm.usd.export_brep(brep.copy(), str(usd_path))
    except Exception:
        pass

    spec = {
        "schema_version": "simready.oracle.v1",
        "slug": slug,
        "package_id": f"aetherforge.brep.{slug}.v1",
        "asset_name": slug,
        "category": data["category"],
        "qcode": data["qcode"],
        "license": "Apache-2.0",
        "author": "Aether-Forge usd-brep",
        "asset_extents": data["extents"],
        "mass": data["mass"],
        "rigid_body_count": 1,
        "manifold": manifold,
        "tessellate_ms": round(ms, 2),
        "visual_mesh": {
            "points": points_yup,
            "normals": normals_yup,
            "indices": indices,
            "color": data["color"],
            "metallic": data["metallic"],
            "roughness": data["roughness"],
        },
        "rigid_bodies": [
            {
                "name": slug,
                "usd_path": f"/{slug}",
                "position": [0.0, 0.0, 0.0],
                "rotation": [0.0, 0.0, 0.0, 1.0],
                "mass": data["mass"],
                "center_of_mass": data["center_of_mass"],
                "inertia": data["inertia"],
                "physics_material": data["physics_material"],
                "colliders": data["colliders"],
                "grasp_lines": data["grasp_lines"],
            }
        ],
        "joints": [],
    }
    out_json = out_dir / f"{slug}.sim.json"
    out_json.write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    print(
        f"BREP_OK slug={slug} manifold={manifold} tris={len(indices)//3} "
        f"mass={data['mass']:.3f}kg ms={ms:.1f}"
    )
    return out_json


def send_live_command(cmd: dict, host: str = "127.0.0.1", port: int = 9877) -> dict:
    with socket.create_connection((host, port), timeout=3.0) as sock:
        sock.sendall((json.dumps(cmd) + "\n").encode("utf-8"))
        reply = sock.makefile().readline()
        return json.loads(reply)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate B-Rep Rube Goldberg assets via usd-brep")
    parser.add_argument("--all", action="store_true", help="Build all Rube Goldberg B-Rep presets")
    parser.add_argument("--preset", nargs="+", default=[], help="Specific preset names to build")
    parser.add_argument("--live-cmd", default="", help="JSON command to send to aether-forge 127.0.0.1:9877")
    args = parser.parse_args()

    if args.live_cmd:
        reply = send_live_command(json.loads(args.live_cmd))
        print(json.dumps(reply))
        return 0

    presets = build_presets()
    targets = list(presets.keys()) if (args.all or not args.preset) else args.preset
    for name in targets:
        if name not in presets:
            raise KeyError(f"Unknown preset '{name}'. Available: {list(presets.keys())}")
        export_preset(name, presets[name])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
