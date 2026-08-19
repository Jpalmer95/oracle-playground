# Oracle Playground

Linux-native VR physics sandbox. Dual-hand **Oracle flight** (independent
thrusters, same idea as [SuperSonic](https://github.com/Jpalmer95/SuperSonic))
inside a Jolt hangar you can smash, float, and restock.

Built for Godot 4.7 on Ubuntu. Desktop works without a headset. OpenXR
(SteamVR → Quest 3 via Steam Link / ALVR) is the VR path. Meta’s XR Operator
does not run on Linux; this repo is where we grow our own see/verify loop.

## Requirements

- Godot 4.7.x on `PATH` (this machine: `~/.local/bin/godot`)
- Optional: SteamVR + Quest 3 for XR
- Optional: `HF_TOKEN` for TRELLIS.2 / SkinTokens imports

## Play

```bash
cd /home/jonathan/dev/oracle-playground
godot --path godot                  # desktop
./tools/play-vr.sh                  # OpenXR after Steam Link is already in the headset
```

### Desktop

| Input | Action |
| --- | --- |
| Mouse | Look |
| Q or LMB | Left thruster |
| E or RMB | Right thruster |
| Shift | Turbo |
| F | Toggle upright stabilize |
| 1–5 | Spawn ice / rubber / metal / wood / glass cube |
| 6 | Spawn destructible crate |
| R | Reset player pose |
| F12 | Dump `user://agent_view.png` for agents |
| Esc | Release / recapture mouse |

Both thrusters together = SuperSonic-style go. One hand only = torque + turn.

### XR (Quest 3 on this Linux PC)

There is no Meta Link / Quest Link on Linux. Steam Link is the path.

1. On the PC, leave Steam running (it already listens on 27036 here).
2. Put on the Quest 3 → **Steam Link** → connect to **jonathan-office**.
3. Wait until SteamVR standing room is up in the headset (not just the Steam 2D desktop).
4. On the PC, from a normal terminal (not SSH-only if you can avoid it):

```
/home/jonathan/dev/oracle-playground/tools/play-vr.sh
```

HUD should say `openxr`. Triggers = independent thrusters, grip = turbo.

If Steam Link will not find the PC, use ALVR instead (`~/ALVR/alvr_streamer_linux/bin/alvr_dashboard` + ALVR on the Quest), then run the same `play-vr.sh`. Same OpenXR runtime.

Do **not** launch Godot first and then connect the headset — OpenXR is off unless `ORACLE_XR=1` / `play-vr.sh`, and it needs SteamVR already alive.

## Tests

```bash
godot --headless --path godot --script res://tests/run_tests.gd
```

## Asset loop

Drop a GLB into `godot/assets/imported/` (or run `tools/import_trellis.py`)
and restart / press I to instantiate imported props as Jolt rigid bodies.

Generate a new mesh (uses your HF ZeroGPU quota):

```bash
set -a; . ~/.hermes/.env; set +a
python3 ~/.hermes/skills/gaming/trellis-image-to-3d/scripts/trellis_gen.py \
  concept.png -o godot/assets/imported/prop.glb --preprocess --target godot
```

Then polish in Blender (`blender-mcp`) if you want — the game only cares
about the GLB on disk.

## Docs

- [MASTER_PLAN.md](MASTER_PLAN.md) — phases, gaps, success criteria
- [AGENTS.md](AGENTS.md) — rules for autonomous agents
- [game_dna.json](game_dna.json) — ForgeDNA intent

## License

MIT. Flight feel inspired by SuperSonic (same author, MIT).
