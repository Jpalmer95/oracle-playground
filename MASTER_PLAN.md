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

- [ ] Grab / throw (physics pickup)
- [ ] Wrist / desktop spawn palette (materials, primitives, imported)
- [ ] Undo stack shared with agent API (`OracleBuilder.spawn`, `.paint`, `.undo`)
- [ ] Simple in-VR HUD (speed, gear, mode)

**Success criteria**

- Same spawn call works from (1) key 1–6, (2) XR button, (3) `OracleBuilder.spawn(...)` headless

---

## Phase 4 — Linux “Operator” v0 (see-what-I-see)

- [ ] Periodic stereo or mono viewport capture
- [ ] Optional VLM caption (`ORACLE_VLM=1`) written beside the PNG
- [ ] Hermes skill `oracle-playground` documenting the capture → prompt loop
- [ ] **Not** a Meta API layer clone; compositor-level later if needed

**Success criteria**

- An agent session can answer “what is in front of the player?” from a fresh capture without a human screenshot

---

## Phase 5 — Graduate XR into HermesForge

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
