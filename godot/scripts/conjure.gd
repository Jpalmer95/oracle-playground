extends Node
## OracleConjure — Phase D natural-language 3-tier object spawner & ZeroGPU bridge.
##
## Resolves any text prompt into a physical Jolt prop via three tiers:
##   Tier 1: Instant SimReady Central catalog match (cached or live OpenUSD ingest)
##   Tier 2: Sub-50ms parametric B-Rep CAD synthesis (`aether-forge` `usd-brep`)
##   Tier 3: Hugging Face ZeroGPU (`FLUX.1-schnell` -> `microsoft/TRELLIS.2` ->
##           Blender 5.0 SimReady `FET_033_STANDARD` physics + CoACD compiler)
##
## Supports both synchronous resolution (`async_bg = false` for headless tests)
## and non-blocking background `Thread` execution (`async_bg = true` for live
## 90-120 Hz VR play) with a glowing grabbable Holo-Placeholder that solidifies
## into the compiled SimReady prop upon completion.

signal prompt_started(prompt: String, placeholder: Node3D)
signal prompt_spawned(prompt: String, slug: String, node: Node3D)
signal prompt_failed(prompt: String, reason: String)

const ALIAS_MAP := {
	"hammer": "hammer",
	"claw hammer": "hammer",
	"screwdriver": "screwdriver",
	"mug": "mug",
	"coffee mug": "mug",
	"bowl": "bowl",
	"scissors": "scissors",
	"seesaw": "playground_swing_seesaw",
	"swing": "playground_swing_seesaw",
	"spiral chute": "spiral_parcel_chute",
	"drinking glass": "drinking_glass",
	"bar clamp": "bar_clamp",
	"clamp": "bar_clamp",
	"heavy brass ball": "brep_heavy_brass_ball",
	"steel marble": "brep_marble_steel",
	"marble": "brep_marble_steel",
	"chute": "brep_chute_straight",
	"curved pipe": "brep_curved_pipe",
	"balance rod": "brep_balance_rod",
	"balance staff": "brep_balance_rod",
	"domino": "brep_domino",
	"hollow hazard crate": "hazard_crate_simready",
	"open hollow hazard crate": "hazard_crate_simready",
}

var _active_jobs: Array = []   # [{thread: Thread, prompt: String, mode: String, placeholder: RigidBody3D, parent: Node3D, at: Vector3}]
var last_status := "Ready"


func _process(_delta: float) -> void:
	if _active_jobs.is_empty():
		return
	var remaining: Array = []
	for job in _active_jobs:
		var th: Thread = job["thread"]
		if not th.is_alive():
			var res: Dictionary = th.wait_to_finish()
			_finalize_job(job, res)
		else:
			remaining.append(job)
	_active_jobs = remaining


func slugify(text: String) -> String:
	var low := text.to_lower().strip_edges()
	var out := ""
	var prev_under := false
	for i in low.length():
		var c := low.unicode_at(i)
		var is_alnum := (c >= 97 and c <= 122) or (c >= 48 and c <= 57)
		if is_alnum:
			out += char(c)
			prev_under = false
		elif not prev_under and out != "":
			out += "_"
			prev_under = true
	return out.trim_suffix("_").left(40)


func resolve_cached_slug(prompt: String) -> String:
	var low := prompt.to_lower().strip_edges()
	if ALIAS_MAP.has(low):
		var target: String = ALIAS_MAP[low]
		if SimReadyLoader.has_asset(target):
			return target
	var cand := slugify(prompt)
	if SimReadyLoader.has_asset(cand):
		return cand
	if SimReadyLoader.has_asset("brep_" + cand):
		return "brep_" + cand
	return ""


func spawn_prompt(
	prompt: String,
	at_world: Vector3,
	mode: String = "auto",
	async_bg: bool = false,
	parent: Node3D = null
) -> Node3D:
	var clean := prompt.strip_edges()
	if clean == "":
		return null
	var target_parent := parent if parent != null else OracleBuilder._target_parent()

	# 1. Instant local cache hit (<1 ms)
	if mode == "auto" or mode == "simready":
		var cached := resolve_cached_slug(clean)
		if cached != "":
			var node := SimReadyLoader.spawn_asset(cached, at_world, target_parent)
			if node != null:
				OracleBuilder._undo.append(node)
				last_status = "Spawned cached '%s'" % cached
				prompt_spawned.emit(clean, cached, node)
				return node

	# 2. Async background thread with Holo-Placeholder (for live VR/Desktop play)
	if async_bg:
		var holder := _make_holo_placeholder(clean, at_world, target_parent)
		var th := Thread.new()
		var job := {
			"thread": th,
			"prompt": clean,
			"mode": mode,
			"placeholder": holder,
			"parent": target_parent,
			"at": at_world,
		}
		_active_jobs.append(job)
		last_status = "Synthesizing '%s' [%s]..." % [clean, mode]
		prompt_started.emit(clean, holder)
		th.start(_run_worker.bind(clean, mode))
		return holder

	# 3. Synchronous execution (for headless tests & immediate CLI scripts)
	var res := _run_worker(clean, mode)
	if not bool(res.get("ok", false)):
		var err_s := str(res.get("error", "unknown error"))
		last_status = "Failed: %s" % err_s
		prompt_failed.emit(clean, err_s)
		return null

	var slug := str(res.get("slug", ""))
	SimReadyLoader.reload_catalog()
	ToolRegistry.reload()
	HUDMenu._build_root()
	HUDMenu._bump()
	var spawned := SimReadyLoader.spawn_asset(slug, at_world, target_parent)
	if spawned != null:
		OracleBuilder._undo.append(spawned)
		last_status = "Spawned '%s' (%s)" % [slug, str(res.get("tier", "auto"))]
		prompt_spawned.emit(clean, slug, spawned)
	return spawned


func _run_worker(prompt: String, mode: String) -> Dictionary:
	var script_abs := ProjectSettings.globalize_path("res://../tools/conjure_spawn.py")
	var out: Array = []
	var args := PackedStringArray(["--prompt", prompt, "--mode", mode])
	var code := OS.execute("python3", PackedStringArray([script_abs]) + args, out, true)
	var combined := "\n".join(out)
	for line in combined.split("\n"):
		var idx := line.find("CONJURE_RESULT ")
		if idx >= 0:
			var json_s := line.substr(idx + "CONJURE_RESULT ".length()).strip_edges()
			var parsed = JSON.parse_string(json_s)
			if parsed is Dictionary:
				return parsed
	return {"ok": false, "exit_code": code, "error": combined.left(300)}


func _finalize_job(job: Dictionary, res: Dictionary) -> void:
	var holder: RigidBody3D = job.get("placeholder")
	var spawn_pos: Vector3 = job.get("at", Vector3(0, 1.5, 0))
	var lin_v := Vector3.ZERO
	var ang_v := Vector3.ZERO
	var parent: Node3D = job.get("parent")
	if holder != null and is_instance_valid(holder):
		spawn_pos = holder.global_position
		lin_v = holder.linear_velocity
		ang_v = holder.angular_velocity
		holder.queue_free()

	var prompt: String = job.get("prompt", "")
	if not bool(res.get("ok", false)):
		var err_s := str(res.get("error", "spawn failed"))
		last_status = "Failed '%s'" % prompt
		prompt_failed.emit(prompt, err_s)
		return

	var slug := str(res.get("slug", ""))
	SimReadyLoader.reload_catalog()
	ToolRegistry.reload()
	HUDMenu._build_root()
	HUDMenu._bump()
	var node := SimReadyLoader.spawn_asset(slug, spawn_pos, parent)
	if node != null:
		if node is RigidBody3D:
			(node as RigidBody3D).linear_velocity = lin_v
			(node as RigidBody3D).angular_velocity = ang_v
		OracleBuilder._undo.append(node)
		last_status = "Spawned '%s' [%s]" % [slug, str(res.get("tier", "auto"))]
		prompt_spawned.emit(prompt, slug, node)


func _make_holo_placeholder(prompt: String, at_world: Vector3, parent: Node3D) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "HoloPlaceholder_%s" % slugify(prompt)
	body.position = at_world
	body.mass = 1.2
	body.gravity_scale = 0.15
	body.linear_damp = 2.5
	body.collision_layer = 4
	body.collision_mask = 7
	body.add_to_group("grabbable")

	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.16
	col.shape = sph
	body.add_child(col)

	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.20, 0.85, 1.0, 0.42)
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.65, 0.95)
	mat.roughness = 0.15
	mi.material_override = mat
	body.add_child(mi)

	var lbl := Label3D.new()
	lbl.text = "Synthesizing:\n%s" % prompt.left(28)
	lbl.font_size = 32
	lbl.pixel_size = 0.0012
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.55, 0.95, 1.0)
	lbl.position = Vector3(0, 0.28, 0)
	body.add_child(lbl)

	if parent != null:
		parent.add_child(body)
	return body
