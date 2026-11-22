extends RefCounted
## Authored P7 acceptance starts, played through the ordinary battle simulator.
const IDS := ["chaodu","shoumen","pomen","dengmian","shangliang","wuce"]
const Record = preload("res://src/replay/BattleRecord.gd")
const Archive = preload("res://src/replay/ReplayArchive.gd")
const FACTIONS := ["shouxiangsi", "wuweisi", "fufasi", "qirensi", "wumingchao", "xisuli", "daxing", "wucepu"]
const STEP := 1.0 / 60.0
var combat: Node
var scenario: Dictionary = {}
var recording: RefCounted
var accumulator := 0.0
var receipt: Dictionary = {}
var saved_steps := -1
var saved_actions := -1

static func read_scenario(id: String) -> Dictionary:
	if id not in IDS and id not in FACTIONS: return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string("res://data/nights/accept_" + id + ".json"))
	return value if value is Dictionary else {}

func start(scene: Node, id: String, seed_text := "") -> Dictionary:
	var definition := read_scenario(id)
	var checked := validate(scene,definition)
	if not checked.ok: return checked
	if recording != null: recording.stop()
	combat = scene
	scenario = definition.duplicate(true)
	if not seed_text.strip_edges().is_empty(): scenario.seed = seed_text.strip_edges()
	var sim: Node2D = combat.get_node("Simulation")
	var session: Node = combat.get_node("Session")
	session.running = false
	session.rules = Data.battle_rules.duplicate(true)
	session.rules.duration = float(scenario.duration)
	sim.tide.config = Data.tide_rules.duplicate(true)
	sim.tide.config.waves = scenario.get("waves",[]).duplicate(true)
	sim.tide.config.night_queue_cap = true
	var begun: Dictionary = session.start_battle(str(scenario.seat))
	if not begun.ok: return begun
	for actor in sim.humans + sim.targets + sim.projectiles + sim.corpses: actor.free()
	sim.humans.clear()
	sim.targets.clear()
	sim.projectiles.clear()
	sim.corpses.clear()
	sim.serial = 0
	sim.tide.pending.clear()
	sim.tide.spawn_count = 0
	session.incense = float(scenario.incense)
	session.names = float(scenario.names)
	var inventory: Dictionary = {}
	for item in scenario.inventory:
		inventory[str(item)] = int(inventory.get(str(item),0)) + 1
	var locks: Array = []
	for spec in scenario.get("structures",[]):
		var object: Node2D = sim.world.get_node(str(spec.id))
		if spec.has("durability"): object.set_durability(float(spec.durability))
		if spec.get("locked",false):
			locks.append({"id":str(spec.id),"locked":true})
			object.set_open(false)
	var initial := {"inventory":inventory,"materials":scenario.get("materials",[]).duplicate(),"ritual_flag":str(scenario.get("ritual_flag","")),"environments":scenario.get("environments",[]).duplicate(true),"locked_paths":locks}
	if id in FACTIONS:
		initial.defense_objective = "hold_register"
	if id == "wumingchao":
		initial.water_mutation_trial = true
	session.configure_growth(str(scenario.seed),initial)
	if id in FACTIONS:
		session.configure_roster(str(scenario.seed))
	for spec in scenario.human_roster:
		var actor: Node2D = sim.spawn_human(str(spec.id),str(spec.post))
		actor.position = sim.post_destination(actor,actor.current_post)
		actor.brain.settled_position = actor.position
		if spec.has("items"): _equip_initial(actor,spec.items)
	for spec in scenario.ghost_roster:
		if spec.has("x_body") or int(spec.get("floor_id",0)) != 0:
			for index in int(spec.count):
				var lane: int = (int(spec.get("lane",0)) + index) % 4
				var actor: Node2D = sim.tide.spawn(str(spec.id),lane,Rules.body_to_px(float(spec.get("x_body",0))) - (index / 4) * float(sim.tide.config.spacing))
				actor.floor_id = int(spec.get("floor_id",0))
				actor.position.y = sim.world.floor_y(actor.floor_id) + float(sim.tide.config.lane_offsets[lane])
				if actor.floor_id > 0: actor.brain.stage = "upper"
				actor.sync_meta()
				if spec.has("items"): _equip_initial(actor,spec.items)
		else:
			for index in int(spec.count): sim.tide.pending.append(str(spec.id))
	sim.tide._spawn_pending()
	sim._update_units()
	session._record("growth_scenario_start",0,str(scenario.id))
	session._update_warnings()
	sim.set_physics_process(false)
	var panel: Node = combat.get_node("Decisions")
	panel.managed_by_night = true
	panel.observation_mode = false
	panel.replay_read_only = false
	panel.prebattle.hide()
	panel.ending.hide()
	Clock.set_speed(1)
	Clock.combat_time = 0
	Clock.set_paused(true)
	accumulator = 0
	receipt.clear()
	saved_steps = -1
	saved_actions = -1
	recording = Record.new()
	recording.begin(combat,{"seed":scenario.seed,"source":"p7_build","node_id":scenario.id,"label":"P7 · " + str(scenario.title),"mode":scenario.seat,"director_limit":0,"scenario":scenario.duplicate(true)})
	return {"ok":true,"reason":"P7_SCENARIO_READY"}

func _equip_initial(actor: Node2D, items: Array) -> void:
	# Optional authored starting equipment uses the same stock-consuming command.
	var session: Node = combat.get_node("Session")
	var seat := "duoming" if actor.side == "yegui" else "shouxiang"
	var art_index := 0
	for id in items:
		if not Data.growth_rules.items.has(id): continue
		if int(session.growth.state.inventory.get(id,0)) <= 0: session.growth.state.inventory[id] = 1
		var answer: Dictionary = session.execute_for(seat,"equip_item",{"unit_id":actor.instance_id,"item_id":id,"slot_index":art_index if Data.growth_rules.items[id].slot == "art" else 0},"ai")
		if answer.ok and Data.growth_rules.items[id].slot == "art": art_index += 1

func advance(delta: float) -> void:
	if not is_instance_valid(combat) or delta <= 0: return
	var session: Node = combat.get_node("Session")
	accumulator += delta
	while accumulator + 0.0000001 >= STEP and session.running:
		accumulator = maxf(0,accumulator - STEP)
		combat.get_node("Simulation").advance(STEP)
	if not session.result.is_empty():
		finish_recording()
		Clock.set_paused(true)

func finish_recording() -> Dictionary:
	if recording == null: return {"ok":false,"reason":"P6_ARCHIVE_MISSING"}
	if saved_steps == recording.steps.size() and saved_actions == recording.actions.size(): return receipt
	var record: Dictionary = recording.finish()
	receipt = Archive.store_record(record)
	if receipt.ok:
		receipt.record = record
		saved_steps = recording.steps.size()
		saved_actions = recording.actions.size()
	return receipt

func status() -> Dictionary:
	if not is_instance_valid(combat): return {"phase":"setup"}
	var session: Node = combat.get_node("Session")
	return {"phase":"finished" if not session.result.is_empty() else "battle","scenario":scenario.id,"seed":scenario.seed,"result":session.result.duplicate(true),"archive":receipt,"steps":recording.steps.size() if recording != null else 0}

static func validate(scene: Node, value: Dictionary) -> Dictionary:
	var bad := {"ok":false,"reason":"P7_INVALID_SCENARIO"}
	if (value.get("id") not in IDS and value.get("id") not in FACTIONS) or value.get("seat") not in ["shouxiang","duoming"] or not value.get("title") is String or not value.get("seed") is String: return bad
	for key in ["human_roster","ghost_roster","inventory"]:
		if not value.get(key) is Array: return bad
	for key in ["incense","names","duration"]:
		if typeof(value.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value[key])): return bad
	if value.incense < 0 or value.incense > 60 or value.names < 0 or value.names > 12 or value.duration < 120 or value.duration > 600: return bad
	var world: Node = scene.get_node("Simulation").world
	var posts: Dictionary = {}
	var names: Array[String] = []
	for spec in value.human_roster:
		if not spec is Dictionary or not Data.combat_profiles.has(str(spec.get("id",""))) or str(spec.id).begins_with("G") or not spec.get("post") is String or not world.can_deploy_at(spec.post): return bad
		var role: String = Data.combat_profiles[spec.id].role
		if role == "talisman": role = "crossbow"
		if role not in world.get_node(spec.post).get_meta("allowed_roles"): return bad
		if str(spec.id).begins_with("H") and spec.id in names: return bad
		names.append(str(spec.id))
		posts[spec.post] = int(posts.get(spec.post,0)) + 1
		if int(posts[spec.post]) > 3: return bad
	if names.size() > 12: return bad
	var count := 0
	for spec in value.ghost_roster:
		if not spec is Dictionary or not Data.combat_profiles.has(str(spec.get("id",""))) or not str(spec.id).begins_with("G") or typeof(spec.get("count")) not in [TYPE_INT,TYPE_FLOAT] or int(spec.count) != float(spec.count) or spec.count < 1: return bad
		count += int(spec.count)
		if spec.has("x_body") and (typeof(spec.x_body) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(spec.x_body)) or spec.x_body < 0 or spec.x_body > 124): return bad
		if int(spec.get("floor_id",0)) not in [0,1,2,3]: return bad
	if count > 120: return bad
	for item in value.inventory:
		if not item is String or (not Data.growth_rules.items.has(item) and not Data.growth_rules.jobs.has(item)): return bad
	for spec in value.get("structures",[]):
		if not spec is Dictionary or not spec.get("id") is String: return bad
		var object: Node2D = world.get_node_or_null(str(spec.id))
		if object == null or object not in world.doors + world.obstacles: return bad
		if spec.has("durability") and (typeof(spec.durability) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(spec.durability)) or spec.durability <= 0 or spec.durability > object.max_durability): return bad
		if spec.has("locked") and (not spec.locked is bool or object not in world.doors): return bad
	return {"ok":true,"reason":"P7_SCENARIO_VALID"}
