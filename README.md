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
./tools/play-desktop.sh             # mouse/keyboard hangar
./tools/play-vr.sh                  # OpenXR — Steam Link must already be in SteamVR
```

### Desktop

| Input | Action |
| --- | --- |
| Mouse | Look |
| Q or LMB | Left thruster |
| E or RMB | Right thruster |
| Shift | Turbo |
| T | Toggle flight / ground mode |
| F | Toggle upright stabilize |
| 1–5 | Spawn ice / rubber / metal / wood / glass cube |
| 6 | Spawn destructible crate |
| 7 | Spawn hazard crate (imported GLB) |
| 8 | Spawn SimReady Claw Hammer (`Q25294`, off-center CoM + grasp lines) |
| 9 | Spawn SimReady Concave Bowl (`Q153988`, 62 compound convex hulls) |
| 0 | Spawn B-Rep Steel Marble (`usd-brep` analytic sphere) |
| - | Spawn B-Rep U-Channel Chute (`usd-brep` boolean trough) |
| = | Spawn B-Rep Weighted Balance Staff (`+0.38m` shifted CoM) |
| P or / | Open **Scribblenauts Prompt Bar** (type any object name + Enter) |
| U / Backspace | Undo / clear spawned |
| G | Power grab / throw (`grip_pressure = 1.0`, ground mode) |
| B | Light pinch / balance grab (`grip_pressure = 0.25`, ground mode) |
| WASD | Walk (ground mode) / yaw+vertical (flight) |
| R | Reset player pose |
| F12 | Dump `user://agent_view.png` for agents |
| Esc | Release / recapture mouse |

Both thrusters together = SuperSonic-style go. One hand only = torque + turn.

### Modes

**Flight** (default) — Oracle dual-hand thrusters, SuperSonic feel. No grab/throw.

**Ground** — gravity is on, you stand on the floor. Grip a controller to grab
the nearest physics object (any spawned prop), move your hand and release to
throw it at your hand velocity. Faster motion = faster throw. Spawn a **bow**
and an **arrow** from the weapons palette, grab the bow, and pull the trigger
in holding-hand to draw / fire. Object mass tracks material density (metal ≫
ice > wood > glass), so heavy objects knock light ones harder than the reverse.

### Wrist HUD (primary menu hub)

Press **B / Y** in the headset (or **T** to jump straight between modes on
desktop) to open the wrist hub — the nested system menu. It has:

- **Tools** — every palette from `config/tools.json` (Build / Edit / Weapons),
  auto-populated, so new tools/palettes appear without code changes.
- **Mode & Motion** — switch Flight ↔ Ground, plus walk-speed and gravity presets.
- **Radio** — background music streamed from the OpenMusic repo (play/pause,
  next, prev, volume). Same library as the SuperSonic radio.
- **Settings** — stabilize toggle, undo, clear-all.

Point the right-hand beam at a button and pull the trigger to select; the
bottom "Back"/"Close" entry pops the menu. The menu layers on top of whatever
mode you're in — flight and ground controls are suspended while it's open.

### XR (Quest 3 on this Linux PC)

There is no Meta Link / Quest Link on Linux. Steam Link is the path.

1. On the PC, leave Steam running (it already listens on 27036 here).
2. Put on the Quest 3 → **Steam Link** → connect to **jonathan-office**.
3. Wait until SteamVR standing room is up in the headset (not just the Steam 2D desktop).
4. On the PC, from a normal terminal:

```
/home/jonathan/dev/oracle-playground/tools/play-vr.sh
```

Terminal must print `Oracle mode: openxr` (not `desktop`). If it still says desktop, SteamVR did not hand Godot an OpenXR session.

If Steam Link will not find the PC, use ALVR instead (`~/ALVR/alvr_streamer_linux/bin/alvr_dashboard` + ALVR on the Quest), then run the same `play-vr.sh`. Same OpenXR runtime.

Do **not** launch Godot first and then connect the headset — OpenXR is off unless `ORACLE_XR=1` / `play-vr.sh`, and it needs SteamVR already alive.

## Tests

```bash
godot --headless --path godot --xr-mode off --script res://tests/run_tests.gd
```

## Asset loop (SimReady Central + Aether-Forge `usd-brep` + TRELLIS.2)

### 1. NVIDIA SimReady Central OpenUSD Ingest (`tools/simready_ingest.py`)
Search and compile OpenUSD packages from [`nvidia/simready-central`](https://huggingface.co/spaces/nvidia/simready-central) into `godot/assets/simready/<slug>/<slug>.glb` + `<slug>.sim.json` (preserving real-world `asset_extents`, `mass`, `center_of_mass`, `inertia`, `PhysicsMaterial`, analytic/compound convex colliders, `HingeJoint3D`/`SliderJoint3D` articulations, and `GSP.001` grasp lines):

```bash
python3 tools/simready_ingest.py --search "hammer"
python3 tools/simready_ingest.py --ingest hammer screwdriver mug bowl scissors playground_swing_seesaw spiral_parcel_chute
godot --headless --path godot --xr-mode off --import
```

### 2. Parametric B-Rep Rube Goldberg CAD (`tools/brep_rube_goldberg.py`)
Rebuild exact CAD Rube Goldberg solids (`brep_marble_steel`, `brep_chute_straight`, `brep_curved_pipe`, `brep_balance_rod`, `brep_domino`) via `aether-forge`'s `usd-brep` kernel:

```bash
/home/jonathan/dev/aether-forge/.venv/bin/python tools/brep_rube_goldberg.py --all
```

### 3. Scribblenauts 3-Tier Spawner & ZeroGPU 3D Physics Compiler (`tools/scribblenauts_spawn.py`)
Spawn any object by natural language — in-game via **`P`** / **`/`** (Desktop) or **B/Y -> Tools -> Scribblenauts AI** (XR), or from the CLI:

```bash
# Tier 1: Pulls & compiles matching OpenUSD package from NVIDIA SimReady Central
python3 tools/scribblenauts_spawn.py --prompt "drinking glass"

# Tier 2: Synthesizes adjective-scaled B-Rep CAD solid via aether-forge usd-brep
python3 tools/scribblenauts_spawn.py --prompt "heavy brass ball" --mode brep

# Tier 3a: Upgrades any TRELLIS.2 / Blender GLB with SimReady FET_033_STANDARD physics + compound hulls
python3 tools/scribblenauts_spawn.py --prompt "open hollow hazard crate" \
  --from-glb godot/assets/imported/hazard_crate.glb --slug hazard_crate_simready

# Tier 3b: Full ZeroGPU generation (FLUX.1-schnell -> microsoft/TRELLIS.2 -> Blender SimReady Compiler)
python3 tools/scribblenauts_spawn.py --prompt "ancient golden chalice" --mode zerogpu
```

### 4. Direct TRELLIS.2 / Blender GLB Import
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
