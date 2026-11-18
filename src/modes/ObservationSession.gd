extends RefCounted
## Configures and drives the existing combat model; policies only submit paid commands.
const Brain = preload("res://src/ai/SeatBrain.gd")
const Record = preload("res://src/replay/BattleRecord.gd")
const Archive = preload("res://src/replay/ReplayArchive.gd")
const Player = preload("res://src/replay/ReplayPlayer.gd")
const STEP := 1.0 / 60.0
var combat: Node
var config: Dictionary = {}
var brains: Dictionary = {}
var director_used := 0
var recording: RefCounted
var playback: RefCounted
var accumulator := 0.0
var receipt: Dictionary = {}
var archived_steps := -1
var archived_actions := -1

func start(scene: Node, options: Dictionary) -> Dictionary:
	if scene.get_node("Session").running: return {"ok":false,"reason":"P4_BATTLE_RUNNING"}
	if options.has("chunk_ids"):
		if not _valid_stage_options(options) or not scene.configure_chunks(options.chunk_ids):
			return {"ok":false,"reason":"P10_INVALID_PLAN"}
	var checked := validate_config(scene,options)
	if not checked.ok: return checked
	var session: Node = scene.get_node("Session")
	if session.running: return {"ok":false,"reason":"P4_BATTLE_RUNNING"}
	combat = scene
	config = options.duplicate(true)
	var sim: Node = combat.get_node("Simulation")
	var profile: Dictionary = Data.night_rules.battle_profiles[config.profile_id]
	sim.tide.config = Data.tide_rules.duplicate(true)
	# The selected roster replaces only the profile's time-zero wave.
	var waves: Array = []
	for wave in profile.get("phase_waves",profile.get("waves",[])):
		if float(wave.at) > 0: waves.append(wave.duplicate(true))
	sim.tide.config.waves = waves
	for key in profile.get("door_durability",{}):
		sim.tide.config.door_durability[key] = profile.door_durability[key]
	sim.tide.config.night_queue_cap = true
	session.rules = Data.battle_rules.duplicate(true)
	session.rules.duration = float(config.duration)
	var answer: Dictionary = session.start_battle("shouxiang")
	if not answer.ok: return answer
	for actor in sim.humans + sim.targets + sim.projectiles + sim.corpses: actor.free()
	sim.humans.clear()
	sim.targets.clear()
	sim.projectiles.clear()
	sim.corpses.clear()
	sim.serial = 0
	sim.tide.pending.clear()
	sim.tide.spawn_count = 0
	session.configure_dual(config.incense,str(config.player_seat) if config.kind == "duel" else "")
	if config.get("growth_enabled",false) or config.has("chunk_ids"):
		var assignments: Array = []
		var presets: Dictionary = Data.growth_templates
		var template: Dictionary = presets[str(config.get("growth_template","ritual_break"))]
		for id in template.loadouts:
			var present := false
			for spec in config.humans + config.ghosts:
				if spec.id == id and int(spec.count) > 0: present = true
			if present and config.get("growth_enabled",false): assignments.append({"id":str(id),"items":template.loadouts[id].duplicate(),"remaining":1})
		session.configure_growth(str(config.seed),{"starting_loadouts":assignments})
	if config.get("roster_enabled",false): session.configure_roster(str(config.seed))
	for spec in config.humans:
		for index in int(spec.count):
			var unit: Node2D = sim.spawn_human(str(spec.id),str(spec.post))
			unit.position = sim.post_destination(unit,unit.current_post)
			unit.brain.settled_position = unit.position
	for spec in config.ghosts:
		for index in int(spec.count): sim.tide.pending.append(str(spec.id))
	sim.tide._spawn_pending()
	session.names = float(config.names)
	if config.has("chunk_ids"):
		if not session.configure_ritual(config.ritual,str(config.seed)) or not preload("res://src/data/StageOptions.gd").start(session,config.boss_id,config.nameless_modifiers,str(config.seed)):
			return {"ok":false,"reason":"P10_INVALID_PLAN"}
	session.input_locked = false
	sim._update_units()
	session._update_warnings()
	sim.set_physics_process(false)
	var panel: Node = combat.get_node("Decisions")
	panel.managed_by_night = true
	panel.observation_mode = true
	panel.prebattle.hide()
	brains.clear()
	for seat in ["shouxiang","duoming"]:
		if config.kind == "watch" or config.player_seat != seat:
			brains[seat] = Brain.new(session,seat,str(config.ferocity),str(config.seed))
	director_used = 0
	accumulator = 0
	receipt.clear()
	archived_steps = -1
	archived_actions = -1
	playback = null
	Clock.combat_time = 0.0
	Clock.set_paused(false)
	recording = Record.new()
	recording.begin(combat,{"seed":config.seed,"source":"observer","node_id":"observation","label":"P6 · " + str(config.kind),"mode":config.kind,"config":config.duplicate(true),"director_limit":int(Data.mode_rules.director_limit) if config.director_enabled else 0})
	return {"ok":true,"reason":"P6_STARTED"}

static func _valid_stage_options(options: Dictionary) -> bool:
	var ritual = options.get("ritual")
	var boss = options.get("boss_id")
	var mods = options.get("nameless_modifiers")
	var ids = options.get("chunk_ids")
	if not ritual is String or not Data.ritual_rules.has(ritual) or not ids is Array or not preload("res://src/data/StageOptions.gd").valid(boss,mods): return false
	var row: Dictionary = Data.ritual_rules[ritual]
	if row.boss_id != "" and boss != row.boss_id: return false
	var required: Array = row.required_chunks.duplicate()
	required.append_array(preload("res://src/data/StageOptions.gd").required_chunks(boss,mods))
	return required.all(func(id): return id in ids)

static func validate_config(scene: Node, options: Dictionary) -> Dictionary:
	var bad := {"ok":false,"reason":"P6_INVALID_CONFIG"}
	if options.has("roster_enabled") and not options.roster_enabled is bool: return bad
	if options.has("growth_enabled") and not options.growth_enabled is bool: return bad
	if options.get("growth_enabled",false):
		var presets: Dictionary = Data.growth_templates
		if not presets is Dictionary or not presets.has(str(options.get("growth_template","ritual_break"))): return bad
	for key in ["kind","player_seat","seed","profile_id","ritual","duration","incense","names","ferocity","director_enabled","humans","ghosts"]:
		if not options.has(key): return bad
	if options.kind not in ["watch","duel"] or options.player_seat not in ["shouxiang","duoming"]: return bad
	if not options.seed is String or options.seed.strip_edges().is_empty() or options.seed.length() > 128: return bad
	if not options.profile_id in Data.mode_rules.profiles or (options.ritual not in Data.mode_rules.rituals and not options.has("chunk_ids")) or not Data.mode_rules.ai_levels.has(options.ferocity): return bad
	if not options.director_enabled is bool or not options.incense is Dictionary or not options.humans is Array or not options.ghosts is Array: return bad
	var limits: Dictionary = Data.mode_rules.limits
	if not _number_in(options.duration,limits.duration_min,limits.duration_max) or not _number_in(options.names,limits.names_min,limits.names_max): return bad
	for seat in ["shouxiang","duoming"]:
		if not _number_in(options.incense.get(seat),limits.incense_min,limits.incense_max): return bad
	var world: Node = scene.get_node("Simulation").world
	var human_count := 0
	var named_count := 0
	var troop_count := 0
	var seen: Dictionary = {}
	var posts: Dictionary = {}
	for spec in options.humans:
		if not spec is Dictionary or not spec.get("id","") in Data.mode_rules.allowed_humans or not _count(spec.get("count"),limits.human_max): return bad
		var id: String = spec.id
		var count := int(spec.count)
		if count == 0: continue
		var post_id: String = str(spec.get("post",""))
		if not world.can_deploy_at(post_id): return bad
		var role: String = Data.combat_profiles[id].role
		if role == "talisman": role = "crossbow"
		if role not in world.get_node(post_id).get_meta("allowed_roles"): return bad
		posts[post_id] = int(posts.get(post_id,0)) + count
		if posts[post_id] > int(limits.post_max): return bad
		human_count += count
		if id.begins_with("H"):
			if count != 1 or seen.has(id): return bad
			seen[id] = true
			named_count += count
		else: troop_count += count
	if human_count == 0 or human_count > int(limits.human_max) or named_count > int(limits.named_max) or troop_count > int(limits.troop_max): return bad
	var ghost_count := 0
	for spec in options.ghosts:
		if not spec is Dictionary or not spec.get("id","") in Data.mode_rules.allowed_ghosts or not _count(spec.get("count"),limits.ghost_max): return bad
		ghost_count += int(spec.count)
	if ghost_count == 0 or ghost_count > int(limits.ghost_max): return bad
	return {"ok":true,"reason":"P6_CONFIG_VALID"}

static func _number_in(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _count(value: Variant, maximum: float) -> bool:
	return _number_in(value,0,maximum) and float(value) == floorf(float(value))

func advance(delta: float) -> void:
	if not is_instance_valid(combat) or delta <= 0: return
	if playback != null:
		playback.advance(delta)
		return
	var session: Node = combat.get_node("Session")
	if not session.running: return
	accumulator += delta
	while accumulator + 0.0000001 >= STEP and session.running:
		accumulator = maxf(0,accumulator - STEP)
		for seat in ["shouxiang","duoming"]:
			if brains.has(seat): brains[seat].advance(STEP)
		combat.get_node("Simulation").advance(STEP)
	if not session.result.is_empty():
		finish_recording()
		Clock.set_paused(true)

func director(action: String, arguments: Dictionary = {}) -> Dictionary:
	if playback != null or not config.get("director_enabled",false): return {"ok":false,"reason":"P6_DIRECTOR_DISABLED"}
	if director_used >= int(Data.mode_rules.director_limit): return {"ok":false,"reason":"P6_DIRECTOR_LIMIT"}
	var session: Node = combat.get_node("Session")
	if not session.running or not session.result.is_empty(): return {"ok":false,"reason":"P4_NOT_RUNNING"}
	var answer: Dictionary
	match action:
		"pause":
			if Clock.paused: return {"ok":false,"reason":"P6_ALREADY_PAUSED"}
			Clock.set_paused(true)
			recording.control("pause")
			answer = {"ok":true,"reason":"P6_DIRECTOR_PAUSED"}
		"reinforce": answer = session.execute_for("duoming","reinforce",arguments,"director")
		"repair": answer = session.execute_for("shouxiang","repair",arguments,"director")
		_: return {"ok":false,"reason":"P6_DIRECTOR_UNKNOWN"}
	if answer.ok: director_used += 1
	return answer

func finish_recording() -> Dictionary:
	if recording == null or playback != null: return {"ok":false,"reason":"P6_ARCHIVE_MISSING"}
	if archived_steps == recording.steps.size() and archived_actions == recording.actions.size(): return receipt
	var record: Dictionary = recording.finish()
	receipt = Archive.store_record(record)
	if receipt.ok:
		receipt.record = record
		receipt.reason = "P6_ARCHIVE_SAVED"
		archived_steps = recording.steps.size()
		archived_actions = recording.actions.size()
	return receipt

func start_replay(scene: Node, record: Dictionary) -> Dictionary:
	var next_player := Player.new()
	var answer := next_player.start(scene,record)
	if not answer.ok: return answer
	combat = scene
	playback = next_player
	config = record.metadata.get("config",{}).duplicate(true)
	config.director_enabled = false
	brains.clear()
	director_used = 0
	recording = null
	var panel: Node = combat.get_node("Decisions")
	panel.managed_by_night = true
	panel.observation_mode = true
	panel.replay_read_only = true
	panel.prebattle.hide()
	return answer

func status() -> Dictionary:
	if combat == null: return {"phase":"setup"}
	var session: Node = combat.get_node("Session")
	var counts: Dictionary = {}
	for seat in brains: counts[seat] = brains[seat].snapshot().decisions
	var output := {"phase":"replay" if playback != null else ("finished" if not session.result.is_empty() else "battle"),"ai_decisions":counts,"wallets":session.wallets.duplicate(true),"director_used":director_used,"director_remaining":maxi(0,int(Data.mode_rules.director_limit)-director_used),"result":session.result.duplicate(true),"archive":receipt}
	if playback != null: output.replay = playback.status()
	return output
