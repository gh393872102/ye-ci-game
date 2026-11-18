extends RefCounted
## Re-executes captured commands and time steps through the same live simulator.
const Archive = preload("res://src/replay/ReplayArchive.gd")
const Record = preload("res://src/replay/BattleRecord.gd")
const Snapshot = preload("res://src/night/BattleSnapshot.gd")
const Bridge = preload("res://src/night/NightBattleBridge.gd")
var carried_queue: Array[Dictionary] = []
var combat: Node
var record: Dictionary = {}
var step_cursor := 0
var action_cursor := 0
var accumulator := 0.0
var done := false
var verified := false
var error := ""
var director_used := 0
var applied: Array[Dictionary] = []

func start(scene: Node, saved: Dictionary) -> Dictionary:
	var answer := Archive.validate(saved)
	if not answer.ok:
		return answer
	var exact := Archive.exact_state(saved)
	var ids = exact.initial.get("chunk_ids",[])
	if not ids is Array or not scene.configure_chunks(ids): return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	answer = Snapshot.restore(scene,exact.initial)
	if not answer.ok:
		return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	if is_instance_valid(combat) and combat.get_node("Simulation").unit_spawned.is_connected(_spawned):
		combat.get_node("Simulation").unit_spawned.disconnect(_spawned)
	combat = scene
	carried_queue.clear()
	if saved.metadata.has("night_queue_exact"):
		carried_queue.assign(bytes_to_var(Marshalls.base64_to_raw(saved.metadata.night_queue_exact)))
	combat.get_node("Simulation").unit_spawned.connect(_spawned)
	record = saved.duplicate(true)
	record.initial = exact.initial
	record.steps = exact.steps
	step_cursor = 0
	action_cursor = 0
	accumulator = 0
	director_used = 0
	done = false
	verified = false
	error = ""
	applied.clear()
	combat.get_node("Simulation").set_physics_process(false)
	combat.get_node("Session").input_locked = true
	Clock.set_paused(true)
	return {"ok":true,"reason":"P6_REPLAY_READY"}

func advance(delta: float) -> void:
	if done or combat == null or delta <= 0:
		return
	accumulator += delta
	var sim: Node = combat.get_node("Simulation")
	# Budgeted stepping preserves both 1x and 2x traces without changing their substeps.
	while not done:
		while action_cursor < record.actions.size() and int(record.actions[action_cursor].step) == step_cursor:
			if not _apply(record.actions[action_cursor]):
				return
			action_cursor += 1
		if step_cursor >= record.steps.size():
			_complete()
			return
		var dt: float = record.steps[step_cursor]
		if accumulator + 0.0000001 < dt:
			break
		if not sim.session.running:
			_fail("P6_REPLAY_DIVERGED")
			return
		accumulator = maxf(0,accumulator - dt)
		sim.advance(dt)
		step_cursor += 1

func _apply(item: Dictionary) -> bool:
	if item.action == "speed":
		combat.get_node("Session").simulation_speed = float(item.arguments.value)
		applied.append(item.duplicate(true))
		return true
	if item.origin == "director":
		director_used += 1
		if director_used > int(record.metadata.get("director_limit",0)):
			_fail("P6_REPLAY_DIVERGED")
			return false
	if item.action == "pause":
		if item.origin != "director":
			_fail("P6_REPLAY_DIVERGED")
			return false
		# Inspection pause has no simulation effect. It is retained in the trace;
		# playback speed/pausing is controlled by the viewer, not by wall-clock input gaps.
		applied.append(item.duplicate(true))
		return true
	var answer: Dictionary = combat.get_node("Session").execute_for(str(item.seat),str(item.action),item.arguments,"replay")
	if not answer.get("ok",false):
		_fail("P6_REPLAY_COMMAND_FAILED")
		return false
	applied.append(item.duplicate(true))
	return true

func _complete() -> void:
	done = true
	verified = Record.digest(Record.fingerprint(combat)) == Record.digest(record.final)
	verified = verified and Record.digest(Record.key_events(combat)) == record.event_hash
	verified = verified and action_cursor == record.actions.size() and director_used == int(record.get("director_used",0))
	if not verified:
		error = "P6_REPLAY_DIVERGED"
	Clock.set_paused(true)

func _fail(reason: String) -> void:
	done = true
	verified = false
	error = reason
	Clock.set_paused(true)

func status() -> Dictionary:
	return {"done":done,"verified":verified,"error":error,"steps":step_cursor,"total_steps":record.get("steps",[]).size(),"commands":action_cursor,"total_commands":record.get("actions",[]).size(),"director_used":director_used,"seed":record.get("metadata",{}).get("seed","")}

func _spawned(unit: Node2D) -> void:
	if unit.side == "yegui" and not carried_queue.is_empty() and (not unit.simulation.world.layout.has("chunk_ids") or (unit.simulation.tide.spawning_pending and carried_queue.front().id == unit.unit_id)):
		Bridge.apply_carried_unit(unit,carried_queue.pop_front())
