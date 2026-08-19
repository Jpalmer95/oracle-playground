#!/usr/bin/env python3
"""Copy a TRELLIS/Blender GLB into the hangar import folder.

Usage:
  python3 tools/import_trellis.py path/to/model.glb [--name slug]
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "godot" / "assets" / "imported"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("glb", type=Path)
    parser.add_argument("--name", default="")
    args = parser.parse_args()
    src: Path = args.glb.expanduser().resolve()
    if not src.is_file():
        print(f"missing: {src}", file=sys.stderr)
        return 1
    if src.suffix.lower() not in {".glb", ".gltf"}:
        print("expected .glb/.gltf", file=sys.stderr)
        return 1
    DEST.mkdir(parents=True, exist_ok=True)
    dest_name = (args.name or src.stem) + src.suffix.lower()
    dest = DEST / dest_name
    shutil.copy2(src, dest)
    print(f"copied {src} -> {dest}")
    print("Restart the game or press I in-play to instantiate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
