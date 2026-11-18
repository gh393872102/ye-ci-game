extends Node
## Observing, dueling and replaying feed the same Combat and validated BattleSession.
const Controller = preload("res://src/modes/ObservationSession.gd")
const Archive = preload("res://src/replay/ReplayArchive.gd")
var controller: RefCounted
var combat: Node2D
var panel: Control
var is_replay := false
var final_archived := false

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	panel = preload("res://src/ui/ObserverPanel.gd").new()
	panel.name = "ObserverPanel"
	panel.host = self
	layer.add_child(panel)
	Clock.set_paused(true)
	if get_tree().has_meta("requested_replay_seed"):
		var seed_text := str(get_tree().get_meta("requested_replay_seed"))
		get_tree().remove_meta("requested_replay_seed")
		panel.replay_seed.text = seed_text
		find_replays(seed_text)

func _new_combat() -> Node2D:
	var candidate: Node2D = preload("res://scenes/combat/Combat.tscn").instantiate()
	candidate.name = "PreparedCombat"
	add_child(candidate)
	var decision: CanvasLayer = candidate.get_node("Decisions")
	decision.managed_by_night = true
	decision.observation_mode = true
	decision.prebattle.hide()
	return candidate

func start_observation(config: Dictionary) -> void:
	var previous_clock := _clock_state()
	var next_controller: RefCounted = Controller.new()
	var candidate := _new_combat()
	var answer: Dictionary = next_controller.start(candidate, config)
	if not answer.ok:
		remove_child(candidate)
		candidate.queue_free()
		_restore_clock(previous_clock)
		_message(answer)
		return
	_dispose()
	controller = next_controller
	combat = candidate
	combat.name = "Combat"
	combat.get_node("BattleCamera").make_current()
	is_replay = false
	final_archived = false
	panel.show_battle(config)
	Clock.set_paused(false)
	_message(answer)

func find_replays(seed_text: String) -> void:
	var records: Array = Archive.list_seed(seed_text)
	panel.show_records(records)
	panel.message.text = tr("P6_LOCAL_ARCHIVES") if not records.is_empty() else tr("P6_ARCHIVE_MISSING")

func start_replay(id: String) -> void:
	var loaded: Dictionary = Archive.load_record(id)
	if not loaded.ok:
		_message(loaded)
		return
	var previous_clock := _clock_state()
	var next_controller: RefCounted = Controller.new()
	var candidate := _new_combat()
	var answer: Dictionary = next_controller.start_replay(candidate, loaded.record)
	if not answer.ok:
		remove_child(candidate)
		candidate.queue_free()
		_restore_clock(previous_clock)
		_message(answer)
		return
	_dispose()
	controller = next_controller
	combat = candidate
	combat.name = "Combat"
	combat.get_node("BattleCamera").make_current()
	combat.get_node("Decisions").replay_read_only = true
	is_replay = true
	final_archived = true
	panel.show_battle({"kind":"replay","seed":loaded.record.metadata.seed,"director_enabled":false})
	Clock.set_paused(false)
	_message(answer)

func director(action: String, arguments: Dictionary = {}) -> void:
	if controller == null or is_replay:
		return
	_message(controller.director(action, arguments))
	_update_status()

func save_recording() -> void:
	if controller == null or is_replay or final_archived:
		return
	var answer: Dictionary = controller.finish_recording()
	_message(answer)
	if answer.ok:
		final_archived = not combat.get_node("Session").result.is_empty()
		panel.replay_seed.text = str(answer.get("seed", controller.config.get("seed", "")))

func _physics_process(_delta: float) -> void:
	if controller != null and is_instance_valid(combat):
		controller.advance(Clock.delta)

func _process(_delta: float) -> void:
	if controller == null or not is_instance_valid(combat): return
	_update_status()
	if not combat.get_node("Session").result.is_empty() and not final_archived and not is_replay:
		save_recording()

func _update_status() -> void:
	if controller == null or not is_instance_valid(combat): return
	panel.update_status(controller.status(), combat.get_node("Session"), is_replay)
	panel.battle_body.visible = not combat.get_node("Decisions").panel.visible

func return_setup() -> void:
	if controller != null and not final_archived and not is_replay:
		save_recording()
	_dispose()
	panel.show_setup()
	Clock.set_paused(true)

func back_to_night() -> void:
	return_setup()
	get_tree().change_scene_to_file("res://scenes/night/Night.tscn")

func _dispose() -> void:
	if is_instance_valid(combat):
		remove_child(combat)
		combat.queue_free()
	combat = null
	controller = null

func _message(answer: Dictionary) -> void:
	panel.message.text = tr(str(answer.get("reason", "")))

func _clock_state() -> Dictionary:
	return {"paused":Clock.paused,"speed":Clock.resume_scale,"time":Clock.combat_time}

func _restore_clock(saved: Dictionary) -> void:
	Clock.set_speed(float(saved.speed))
	Clock.combat_time = float(saved.time)
	Clock.set_paused(bool(saved.paused))
	if is_instance_valid(combat): combat.get_node("BattleCamera").make_current()
