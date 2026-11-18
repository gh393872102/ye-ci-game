extends RefCounted
## A seed identifies a recorded battle; inputs and exact step deltas make it replayable.
const Snapshot = preload("res://src/night/BattleSnapshot.gd")
const RULE_FILES := ["res://data/units/characters.csv","res://data/units/ghosts.csv","res://data/units/troops.csv","res://data/units/p2_combat.json","res://data/levels/p2_defense.json","res://data/levels/p3_tide.json","res://data/levels/p4_battle.json","res://data/levels/reference_gate_court.json","res://src/autoload/Rules.gd","res://src/combat/Formula.gd","res://src/combat/CombatSimulation.gd","res://src/combat/BattleSession.gd","res://src/combat/TideController.gd","res://src/combat/Projectile.gd","res://src/combat/skills/DianCe.gd","res://src/units/CombatUnit.gd","res://src/ai/GuardPolicy.gd","res://src/ai/HumanBrain.gd","res://src/ai/GhostBrain.gd","res://src/ai/BaseExcursion.gd","res://src/world/WalkNetwork.gd","res://src/world/ReferenceMap.gd","res://src/world/WorldDoor.gd","res://src/world/WorldObstacle.gd","res://src/night/BattleSnapshot.gd","res://src/night/NightBattleBridge.gd"]
var combat: Node
var metadata: Dictionary = {}
var initial: Dictionary = {}
var actions: Array[Dictionary] = []
var steps: Array[float] = []
var capturing := false
var recorded_speed := 1.0

func begin(scene: Node, details: Dictionary, resume: Dictionary = {}) -> void:
	combat = scene
	metadata = details.duplicate(true)
	if resume.is_empty():
		initial = Snapshot.capture(scene)
		actions.clear()
		steps.clear()
	else:
		metadata = resume.get("metadata",details).duplicate(true)
		initial = bytes_to_var(Marshalls.base64_to_raw(resume.initial_exact))
		actions.assign(resume.get("actions",[]))
		steps.assign(bytes_to_var(Marshalls.base64_to_raw(resume.steps_exact)))
	recorded_speed = float(initial.session.get("simulation_speed",initial.get("speed",1)))
	for item in actions:
		if item.action == "speed": recorded_speed = float(item.arguments.value)
	capturing = true
	var sim: Node = combat.get_node("Simulation")
	var session: Node = combat.get_node("Session")
	if not sim.step_completed.is_connected(_stepped):
		sim.step_completed.connect(_stepped)
	if not session.command_applied.is_connected(_command):
		session.command_applied.connect(_command)

func _command(seat: String, action: String, arguments: Dictionary, origin: String) -> void:
	if not capturing or origin in ["system","replay"]:
		return
	actions.append({"step":steps.size(),"order":actions.size(),"seat":seat,"action":action,"arguments":arguments.duplicate(true),"origin":origin})

func _stepped(delta: float) -> void:
	if capturing:
		var current: float = combat.get_node("Session").simulation_speed
		if current != recorded_speed:
			# Record the business clock before this step; viewer playback speed is separate.
			actions.append({"step":steps.size(),"order":actions.size(),"seat":"","action":"speed","arguments":{"value":current},"origin":"player"})
			recorded_speed = current
		steps.append(delta)

func control(action: String, args: Dictionary = {}) -> void:
	if capturing:
		actions.append({"step":steps.size(),"order":actions.size(),"seat":"","action":action,"arguments":args.duplicate(true),"origin":"director"})

func stop() -> void:
	capturing = false
	if is_instance_valid(combat):
		var sim: Node = combat.get_node("Simulation")
		var session: Node = combat.get_node("Session")
		if sim.step_completed.is_connected(_stepped): sim.step_completed.disconnect(_stepped)
		if session.command_applied.is_connected(_command): session.command_applied.disconnect(_command)

func checkpoint() -> Dictionary:
	return {"version":1,"engine":Engine.get_version_info().string,"rules_hash":rules_hash(),"metadata":metadata.duplicate(true),"initial":initial.duplicate(true),"initial_exact":Marshalls.raw_to_base64(var_to_bytes(initial)),"actions":actions.duplicate(true),"steps":steps.duplicate(),"steps_exact":Marshalls.raw_to_base64(var_to_bytes(steps))}

func finish() -> Dictionary:
	var output := checkpoint()
	output.version = 1
	output.engine = Engine.get_version_info().string
	output.rules_hash = rules_hash()
	output.final = fingerprint(combat)
	output.key_events = key_events(combat)
	output.event_hash = digest(output.key_events)
	output.complete = not combat.get_node("Session").result.is_empty()
	output.duration = combat.get_node("Simulation").simulation_time - float(initial.simulation.simulation_time)
	output.director_used = 0
	for action in actions:
		if action.origin == "director":
			output.director_used += 1
	return output

static func rules_hash() -> String:
	var content := "P8-combat-replay-v1\n"
	for path in RULE_FILES + ["res://src/combat/P10Stage.gd","res://src/data/ChunkCatalog.gd","res://src/data/StageOptions.gd","res://src/data/RitualCatalog.gd"]:
		content += path + ":" + FileAccess.get_file_as_string(path).sha256_text() + "\n"
	# Growth tables and handlers are part of the simulation contract.
	for folder in ["res://data/items","res://src/growth","res://src/roster","res://src/progression","res://data/rituals","res://data/levels/chunks","res://data/levels/bosses","res://src/rituals"]:
		var files := DirAccess.get_files_at(folder)
		files.sort()
		for file in files:
			if str(file).get_extension() in ["csv","json","gd"]:
				var path: String = folder + "/" + str(file)
				content += path + ":" + FileAccess.get_file_as_string(path).sha256_text() + "\n"
	for path in ["res://data/levels/p8_routes.json","res://data/units/p8_humans.json","res://data/units/p8_ghosts.json","res://data/units/p7_combat.json","res://data/modes/p7_growth_templates.json","res://data/nights/p7_growth_night.json"]:
		content += FileAccess.get_file_as_string(path).sha256_text()
	return content.sha256_text()

static func key_events(scene: Node) -> Array:
	var session: Node = scene.get_node("Session")
	var sim: Node = scene.get_node("Simulation")
	var result: Array = []
	for event in session.ledger:
		var entry: Dictionary = event.duplicate(true)
		entry.erase("origin") # Replay transport differs; actor/action/cost/time still must agree.
		result.append(_normalize(entry))
	for milestone in sim.tide.milestones:
		result.append({"milestone":_normalize(milestone)})
	return result

static func fingerprint(scene: Node) -> Dictionary:
	var snapshot := Snapshot.capture(scene)
	var result := {"actors":snapshot.actors,"structures":snapshot.structures,"shots":snapshot.shots,
		"time":snapshot.simulation.simulation_time,"tide":snapshot.tide,
		"session":snapshot.session.duplicate(true),"growth":snapshot.get("growth",{}),"roster_engine":snapshot.get("roster_engine",{}),"codex":snapshot.get("codex",{})}
	for key in ["chunk_ids","stage","ritual"]:
		if snapshot.has(key): result[key] = snapshot[key]
	# Night bookkeeping has no combat effect and differs for actors born during playback.
	for actor in result.actors:
		actor.erase("night_uid")
		actor.erase("night_home_post")
	result.session.erase("ledger")
	result.session.erase("warnings")
	for key in ["player_seat","_command_seat","_command_origin","control_policy"]:
		result.session.erase(key)
	return _normalize(result)

static func digest(value: Variant) -> String:
	return JSON.stringify(_normalize(value),"",true,true).sha256_text()

static func _normalize(value: Variant) -> Variant:
	if typeof(value) in [TYPE_INT,TYPE_FLOAT]:
		return snappedf(float(value),0.00001)
	if value is Array:
		var list: Array = []
		for item in value:
			list.append(_normalize(item))
		return list
	if value is Dictionary:
		var output: Dictionary = {}
		for key in value:
			output[str(key)] = _normalize(value[key])
		return output
	return value
