# AGENTS.md — Oracle Playground

Linux-native VR physics sandbox. Godot 4.7 + Jolt + OpenXR.
Repo: `/home/jonathan/dev/oracle-playground`

## Profiles

- `quick` — docs, DNA tweaks, copy
- `primary` — default for code (`-p primary -w`)
- `heavy` — architecture, Operator / XR reviews

Always use worktree mode (`-w`) when editing this repo.

## Skills to load

- `hermes-3d-mcp` (Godot/Blender MCP)
- `forgedna-dna-creator` / `forgedna-godot-builder` / `forge-dna-pipeline`
- `game-asset-pipeline` + `trellis-image-to-3d` + `skintokens-rigging` for generated meshes
- `linux-pcvr` for SteamVR / Quest 3
- `writing-plans` before multi-phase work
- `systematic-debugging` when Play/headless fails

Do **not** install Meta XR Operator / Unity / Meta XR Simulator on this machine.

## Non-negotiables

1. `MASTER_PLAN.md` is the source of truth. One phase at a time. Mark `[x]` only after Success Criteria pass.
2. Every verb needs three doors: GDScript API, desktop binding, XR binding. Missing a door = unfinished.
3. Humans can edit any generated scene/script. No hidden lock files.
4. Jolt is the 3D physics engine (`physics/3d/physics_engine="Jolt Physics"`). Do not switch.
5. Oracle flight: each hand is an independent thruster. Trigger = thrust along that hand’s −Z. Grip = turbo. Ported from SuperSonic (`~/dev/SuperSonic/index.html` `handleFlightInput`).
6. Headless must stay green: `godot --headless --path godot --script res://tests/run_tests.gd`
7. Secrets stay out of git. `HF_TOKEN` lives in `~/.hermes/.env`.
8. Graduate reusable XR/physics recipes back to `~/dev/hermesforge` — do not fork Godot.

## Layout

```
game_dna.json          ForgeDNA intent
godot/                 playable Godot 4.7 project
  scripts/             player, arena, materials, builder, agent_view
  scenes/main.tscn
  assets/imported/     drop Trellis/Blender GLBs here
  tests/run_tests.gd
tools/                 import helpers
```

## Verify

```bash
godot --version          # 4.7.x
godot --headless --path godot --import
godot --headless --path godot --script res://tests/run_tests.gd
```

## Commit + push

After a phase: commit locally, `git push origin main`. Public repo.
