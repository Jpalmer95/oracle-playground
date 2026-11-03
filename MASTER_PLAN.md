# Oracle Playground — MASTER_PLAN

> **For Hermes:** Execute phase-by-phase only. Mark `[x]` only after that
> phase's Success Criteria pass. Atomic commits. Never commit secrets
> (`.env`, `HF_TOKEN`). Humans may edit any generated scene/script at any time.

**Vision:** A Linux-native VR physics playground where a human and Hermes
build together — in the Godot editor, in the terminal, and eventually *inside
the headset*. Flight is Oracle mode (two independent hand thrusters, same
feel as [SuperSonic](https://github.com/Jpalmer95/SuperSonic)). The long game
is an open, Linux-first “see what I see” agent loop (our Meta XR Operator
stand-in) plus fully remixable assets (Trellis.2, Blender, music, voice).

**Architecture:** Godot 4.7 + built-in Jolt + OpenXR. Game lives in this
repo. HermesForge (`~/dev/hermesforge`) is the environment/module stack we
consume, not a fork. ForgeDNA (`game_dna.json`) is the engine-agnostic
intent doc. Assets stay portable (glTF/GLB).

**Tech stack:** Godot 4.7.1, Jolt Physics, OpenXR (SteamVR on this PC,
Quest 3 via Steam Link / ALVR), Hermes MCP (godot-ai, blender, hermesforge),
TRELLIS.2 + SkinTokens for generated meshes.

---

## How to use this document

1. Do **one phase** at a time.
2. Run that phase's verification commands.
3. Check every Success Criterion. Only then mark `[x]`.
4. Commit. Push to GitHub.
5. Do not start later phases to “get ahead.”

---

## Current state (2026-08-19)

Honest snapshot, this machine:

| Piece | Status |
| --- | --- |
| Ubuntu 26.04 + RTX 4070 Ti + Quest 3 | working |
| Godot 4.7.1 official | `~/.local/bin/godot` |
| SteamVR as active OpenXR runtime | yes |
| HermesForge (Jolt, water, terrain, foliage, bridge) | Phases 0–4 done, **no XR module** |
| ForgeDNA + harness | Godot adapter only |
| SuperSonic (WebXR Iron Man flight) | reference, Three.js |
| Meta XR Operator | **will not run on Linux** — do not install |
| Godot XR Tools addon | not vendored yet |
| In-headset editor / world-understander | not built |
| Trellis.2 → SkinTokens pipeline | skills exist, not wired into this game yet |

---

## Identified gaps (agentic + human XR building)

These are the real holes vs the long-term vision. Phases close them in order.

1. **No Linux “Operator.”** Agents cannot see the headset or Play viewport.
   Need: deterministic screenshot / stereo grab + optional VLM caption, plus
   a later OpenXR API-layer or compositor tap. Start with `AgentView` PNG dump.
2. **HermesForge has zero XR.** No XROrigin recipes, no OpenXR action map,
   no in-VR tools. This repo is the first XR consumer; useful recipes should
   graduate back into HermesForge as a `modules/xr` later.
3. **Flight is kinematic in SuperSonic, sandbox needs physics.** Oracle
   thrusters must apply *forces* on a Jolt RigidBody (optional torque from
   hand offsets) so crates, water, and debris interact. *(2026-08-19: flight
   feel corrected — XR rig decoupled from body, gravity-free, SuperSonic drag.)*
4. **Desktop fallback is mandatory.** Headless CI and no-headset days must
   still fly (virtual hands). OpenXR is additive, not required to boot.
5. **Asset loop is disconnected.** Trellis / SkinTokens / Blender MCP exist
   as skills but nothing in-game watches `assets/imported/` and wraps GLBs
   in convex RigidBodies.
6. **No in-VR building yet.** Spawn, grab, material-paint, undo — all
   editor/desktop first, then a wrist palette.
7. **Audio/voice/music skills unused.** Wire later; do not block flight.
8. **Destructibles / fluids are stubs vs SOTA.** Phase 1 = shatter-to-shards
   + HermesWater buoyancy. Soft-body / FLIP fluids are a later research track.
9. **Dual-control promise.** Every gameplay verb needs (a) GDScript API for
   agents, (b) desktop binding, (c) XR binding. If a verb has only one, it
   is unfinished.

---

## Phase 0 — Repo + DNA + bootable Godot project

- [x] Public repo scaffold (`MASTER_PLAN.md`, `AGENTS.md`, MIT)
- [x] Valid `game_dna.json` (`forgedna validate`)
- [x] Godot 4.7 project with Jolt + OpenXR *available* (disabled by default so headless/CI does not grab SteamVR; set `ORACLE_XR=1` to start a session)
- [x] `godot --headless --import` succeeds
- [x] README with desktop + VR launch commands

**Success criteria**

- `forgedna validate game_dna.json` exits 0
- `godot --headless --path godot --import` exits 0
- `godot --headless --path godot --quit-after 2` boots `main.tscn` and prints `Oracle Playground boot`

---

## Phase 1 — Oracle flight + physics hangar (this slice)

- [x] Dual independent thrusters (trigger = thrust along that hand’s −Z)
- [x] Grip = turbo (SuperSonic-style ~3.8×)
- [x] Forces applied at each hand (torque) with a central-force fallback
- [x] Desktop virtual hands (Q / E or LMB / RMB + mouse look)
- [x] Upright stabilize (toggle) so first flights are not tumble-only
- [x] Hangar: floor, ramps, material pads (ice / rubber / metal / wood / glass)
- [x] Destructible crates (impulse threshold → shard RigidBodies)
- [x] Water pool using HermesForge wave + buoyancy math
- [x] Headless unit tests for thrust direction + shatter
- [x] `AgentView` writes `user://agent_view.png` (F12 / env `ORACLE_AGENT_VIEW=1`)

**Success criteria**

- `godot --headless --path godot --script res://tests/run_tests.gd` exits 0
- Desktop: hold both thrusters, body accelerates along look-forward
- XR (manual): left-only / right-only thrust yaws/translates independently
- At least one crate shatters under a high-speed impact
- A dumped `agent_view.png` exists after F12 or the test harness

---

## Phase 2 — Trellis / Blender / import loop

- [x] `tools/import_trellis.py` + `assets/imported/` watch folder
- [x] Runtime wrapper: GLB → convex RigidBody + material override
- [x] One dogfood prop generated (TRELLIS.2) and sitting in the hangar (`hazard_crate.glb`)
- [ ] Document: drop a GLB, or send it through Blender MCP, re-import

**Success criteria**

- A real `.glb` (>50 KB) in `godot/assets/imported/` appears as a grabbable/physical prop after import
- README “Asset loop” section is accurate (commands actually run)

---

## Phase 3 — In-VR builder verbs

**Architecture (scalability-by-data):** Tools are *declared in JSON*, not code.
`godot/config/tools.json` lists every tool (id, name, category, `kind`, params)
and every *palette* (a named, ordered list of tool ids for a workflow — Build,
Lighting, Audio, etc.). `ToolRegistry` (autoload) parses it; `OracleBuilder`
(autoload) dispatches a tool id → node via a small set of `kind` handlers.
Adding a tool = add a JSON entry (new `kind` = add one match-branch). Humans and
agents both edit the same JSON; no recompile, no hidden lock files.

Every verb resolves through `OracleBuilder.spawn_tool(id, pos)` whether it came
from a desktop key, an XR ray-select, or a headless GDScript call — this is the
three-door non-negotiable.

- [x] `config/tools.json` + `ToolRegistry` autoload (parse, validate, palette/tool lookup)
- [x] `OracleBuilder` autoload: `spawn_tool` dispatch (material_cube / destructible / glb), undo stack, `undo()`, `clear()`
- [x] Desktop keys route through `OracleBuilder` (1–5 mats, 6 crate, U undo, Backspace clear)
- [x] `WristPalette` XR panel built *from the registry*: ray-select right-hand buttons, trigger spawns, joystick or ray navigates; undo/clear buttons
- [ ] Grab / throw (physics pickup: grip to hold, throw on release)
- [ ] In-headset palette editor (re-order/add/remove tools while wearing the headset, then persist to tools.json)

**Success criteria**

- Same `OracleBuilder.spawn_tool("cube_ice", pos)` call works from (1) key 1, (2) XR ray-select, (3) headless — verified by a unit test that spawns headlessly and asserts the node + undo.
- `ToolRegistry` headless test passes: palette resolves ids, unknown id is rejected, malformed JSON does not crash.
- A fresh `tools.json` edit (add a tool) shows up in the palette on next boot without code change.

---

## Phase 4 — Ground mode: grab/throw, density, bow & arrow

**Mode split:** Oracle flight stays its own clean control scheme (thrusters,
turbo, gear). A separate **ground mode** (gravity on, capsule stands on the
floor, smooth locomotion + turn + jump) owns grab/throw and the bow. Toggling
modes does not share inputs — flight never fires the grabber, ground never
fires thrusters.

**Grab/throw:** per-hand `Grabber3D`. Grip = kinematic-hold nearest grabbable
RigidBody within reach (tracked hand local offset), release = throw with the
hand's smoothed linear velocity (and a light angular term from hand rotation).
Speed on release matters — faster controller motion = faster throw.

**Density:** mass already derives from per-material density
(`MaterialLab.spawn_cube` = size³·200·density, metal >> wood > ice > glass).
Jolt conserves momentum, so a light body knocking a heavy one moves it less
than a heavy knocking a light one — no extra code, but asserted by test.

**Bow & arrow:** a grabbable `BowProp` (basic model, limb+string) and a physics
`ArrowProp` (shaft+tip, sticks on impact). Draw scales launch speed; arrows
inherit bow velocity. Basic arrow only; piercing / splitting / flaming /
explosive are future arrow kinds (same `arrow` tool kind + a payload param).

- [x] `Grabber3D` component: nearest-grabbable pickup, kinematic hold, velocity throw
- [x] `BowProp` + `ArrowProp` physics props
- [x] Player flight/ground mode split + toggle (desktop/XR)
- [x] Ground locomotion (smooth move + turn + jump)
- [x] Builder kinds `bow` / `arrow`; grabbable group registration
- [ ] (future) piercing/splitting/flaming/explosive arrow payloads

**Success criteria**

- Headless: grabber grabs a cube, throws with hand velocity ~ hand speed × throw_scale.
- Headless: metal (heavy) cube knocks ice (light) cube farther than ice knocks metal at equal impact speed.
- Headless: `bow.fire(draw=0.5)` yields an arrow with speed ≈ draw·power.
- Ground mode has gravity and no thrust; flight mode has no grab/throw.

---

## Phase 5 — Wrist HUD hub + radio (primary system menu/settings)

**This becomes the primary system HUD.** The flat WristPalette is replaced by a
**nested, data-driven menu** rendered on the left wrist: a root hub with
submenus for Tools (auto-populated from `ToolRegistry` palettes → so new
palettes/tools appear automatically), Mode & Motion (flight/ground switch +
walk-speed/gravity/jump), Radio (play/pause/prev/next/volume), and Settings.
Navigation: right-hand ray + trigger to select; a persistent "back" entry when
nested. Future plugins register one submenu — no renderer changes.

**Mode switch fix:** the prior XR toggle used `menu_button`, which OpenXR r
serves for the system menu (SteamVR intercepts it — hence no in-game control).
Moved the toggle *into* the hub, and the hub itself opens on `by_button` (B/Y),
which is app-visible. Desktop stays on `T`.

**Radio:** streams MP3 from the public `Jpalmer95/OpenMusic` GitHub repo (same
source as SuperSonic's radio). `Radio` autoload: play/pause/next/prev/volume,
downloads tracks with HTTPRequest and plays via AudioStreamMP3 (no import step).

Menu item kinds: `submenu`, `action` (one-shot, e.g. spawn/undo), `toggle`
(flips a setting, re-labels), `select` (cycles a list of choices — walk speed,
gravity, volume). State changes bump a version counter the renderer watches.

- [x] `HUDMenu` autoload: nested menu tree + navigation stack + dispatch
- [x] `Radio` autoload: OpenMusic MP3 streaming player (state machine testable)
- [x] WristPalette → nested menu renderer (grid layout, back entry, version refresh)
- [x] Mode toggle in-hub + `by_button` open/close; gated inputs while open
- [ ] (future) in-menu plugin registry for third-party tools

**Success criteria**

- Headless: `HUDMenu` builds the tree; activating a palette submenu and a toggle dispatches correctly; navigation pushes/pops.
- Headless: `Radio` playlist state (next/prev/toggle) is correct with injected queue (no network in CI).
- XR: B/Y opens the hub; Tools shows all palettes from tools.json; Mode switches flight↔ground.

---

## Phase A — Generalized Physics Hands, CoM Balancing & Two-Handed Grasping

- [x] Replace kinematic `freeze = true` in `Grabber3D` (`godot/scripts/grabber.gd`) with a contact-anchored 6-DOF PD force/torque drive in Jolt so held objects remain dynamic `RigidBody3D`s.
- [x] Center-of-Mass (`center_of_mass`) leverage + grip-pressure rotational stiffness (`grip_pressure` $\in [0, 1]$): holding a long rod or hammer at its CoM balances horizontally even with a loose pinch (`B` / light grip `0.22`), while holding away from CoM produces gravitational lever torque `(anchor - CoM) x F` that tips the heavy end down.
- [x] Two-handed simultaneous grabbing on the same `RigidBody3D` (doubles lifting force cap and creates a natural two-anchor lever arm).
- [x] SimReady `GSP.001` `grasp_lines` snapping + surface friction slip (`ice` < `rubber`) + procedural 5-finger curl rig.

---

## Phase B — NVIDIA SimReady Central OpenUSD Ingestion Pipeline

- [x] `tools/simready_ingest.py` searches `NVIDIA-Omniverse/simready-central` and compiles OpenUSD packages into `godot/assets/simready/<slug>/<slug>.glb` + `<slug>.sim.json` via Blender 5.0's `pxr` (`Usd`, `UsdGeom`, `UsdPhysics`, `UsdShade`).
- [x] `SimReadyLoader` (`godot/scripts/simready_loader.gd`) autoload spawns single-body and multi-body articulated SimReady assets with exact `mass`, `center_of_mass`, `inertia`, `PhysicsMaterial`, analytic primitives (`Sphere`/`Capsule`/`Cylinder`/`Box`), compound `ConvexPolygonShape3D` concave hulls (`bowl`, `mug`), and `HingeJoint3D`/`SliderJoint3D` articulations (`playground_swing_seesaw`, `scissors`).
- [x] Ingested 7 real SimReady Central packages (`hammer`, `screwdriver`, `mug`, `bowl`, `scissors`, `playground_swing_seesaw`, `spiral_parcel_chute`) and registered the `SimReady Central` palette in `config/tools.json`.

---

## Phase C — Parametric B-Rep Rube Goldberg Kit (`aether-forge` `usd-brep` Bridge)

- [x] `tools/brep_rube_goldberg.py` uses `/home/jonathan/dev/aether-forge/.venv` (`usd-brep`) to construct exact CAD Rube Goldberg solids (`brep_marble_steel`, `brep_chute_straight`, `brep_curved_pipe`, `brep_balance_rod`, `brep_domino`), tessellate them, and export `.sim.json` + `.brep.usd`.
- [x] Registered the `Rube Goldberg CAD` palette in `config/tools.json`, desktop hotkeys (`8` hammer, `9` bowl, `0` marble, `-` chute, `=` balance staff), and built the live SimReady + Rube Goldberg test bench in `arena.gd`.
- [x] Headless verification in `test_runner.gd`: CoM balance vs off-center tipping, 2-hand 38 kg lift, SimReady `Q25294` + `GSP.001` grasp snap, 62-hull concave bowl, hinged `SeesawBeam` articulation, and steel marble rolling down the B-Rep U-channel chute to knock over a domino.

---

## Phase D — Oracle Conjure 3-Tier Spawner & ZeroGPU 3D Physics Compiler

- [x] `tools/conjure_spawn.py` resolves any natural-language prompt across 3 tiers:
  1. **Tier 1 (`simready`):** Matches local cache or live `NVIDIA-Omniverse/simready-central` OpenUSD index (`drinking_glass`, `bar_clamp`, `hammer`, `mug`, `bowl`, `scissors`, `playground_swing_seesaw`, `spiral_parcel_chute`, etc.).
  2. **Tier 2 (`brep`):** Synthesizes adjective-driven (`heavy`/`light`/`large`/`small`/`brass`/`steel`/`ice`/`wood`/`rubber`) parametric B-Rep CAD solids via `aether-forge` `usd-brep` in < 50 ms (`heavy brass ball` $\to$ `14.58 kg` analytic sphere).
  3. **Tier 3 (`zerogpu` / `--from-glb`):** Generates a concept image on HF ZeroGPU (`black-forest-labs/FLUX.1-schnell`), generates a 3D GLB on `microsoft/TRELLIS.2` ZeroGPU (using `HF_TOKEN` from `~/.hermes/.env`, 0 local VRAM), and runs Blender 5.0.1 to rescale to real-world meters, estimate `FET_033_STANDARD` mass/CoM/inertia, decompose into compound convex hulls, and author `GSP.001` grasp lines.
- [x] `OracleConjure` autoload (`godot/scripts/conjure.gd`): supports instant cache spawn, synchronous spawn for headless tests, and non-blocking `Thread` execution with a grabbable glowing Holo-Placeholder that solidifies into the compiled asset via runtime `GLTFDocument` hot-loading.
- [x] Three-door integration: GDScript API (`OracleConjure.spawn_prompt(...)`), Desktop interactive prompt bar (**`P`** or **`/`**), and XR `HUDMenu` -> `Tools` -> `Oracle Conjure AI` submenu.

---

## Phase 6 — Linux “Operator” v0 (see-what-I-see)

- [ ] Periodic stereo or mono viewport capture
- [ ] Optional VLM caption (`ORACLE_VLM=1`) written beside the PNG
- [ ] Hermes skill `oracle-playground` documenting the capture → prompt loop
- [ ] **Not** a Meta API layer clone; compositor-level later if needed

**Success criteria**

- An agent session can answer “what is in front of the player?” from a fresh capture without a human screenshot

---

## Phase 7 — Graduate XR into HermesForge

- [ ] `modules/xr` recipe + AGENT.md (origin, action map, thruster pawn)
- [ ] ForgeDNA `custom_mechanics` → Godot adapter emission
- [ ] Contribute playbook back (public repo + Hermes skill)

---

## Future (do not execute from this plan)

- Soft-body / better fracture / FLIP fluids
- SkinTokens hero characters + animation retarget
- In-headset Blender-style sculpt
- Steam Frame Linux ARM64 export
- Bevy adapter for the same DNA (research only)
- Music / SFX / voice pipelines

---

## Launch / play (Phase 1)

```bash
# desktop (no headset)
godot --path godot
ORACLE_XR=1 godot --path godot

# tests
godot --headless --path godot --script res://tests/run_tests.gd
```

---

*Authoritative. Updated 2026-08-18. Owner: Jonathan Korstad. Status: Phase 0–1 in progress.*
