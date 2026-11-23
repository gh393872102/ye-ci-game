extends Node
## Owns navigation between a serialized NightRun and the unchanged shared battle scene.
const Run = preload("res://src/night/NightRun.gd")
const Bridge = preload("res://src/night/NightBattleBridge.gd")
var run: RefCounted
var bridge: RefCounted
var panel: Control
var combat: Node2D
var save_path := "user://night_save.json"
var auto_continue := false
var title_shell_enabled := false
var shell: CanvasLayer
var battle_controls: HBoxContainer
var battle_heading: Label
var feedback: Label
var buttons: Dictionary = {}
var codex_panel: CanvasLayer
var settling := false
var generation := 0
var _codex_focus: WeakRef

func _ready() -> void:
	title_shell_enabled = title_shell_enabled or get_tree().get_meta("p9_title_shell", false)
	run = Run.new()
	bridge = Bridge.new()
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.name = "NightInterface"
	add_child(layer)
	panel = preload("res://src/ui/NightPanel.gd").new()
	codex_panel = preload("res://src/ui/CodexPanel.gd").new()
	codex_panel.setup(Data.codex_store)
	add_child(codex_panel)
	codex_panel.surface.visibility_changed.connect(_codex_visibility_changed)
	panel.name = "NightPanel"
	panel.host = self
	layer.add_child(panel)
	battle_controls = HBoxContainer.new()
	battle_controls.position = Vector2(1540, 1036)
	battle_controls.add_theme_constant_override("separation", 8)
	layer.add_child(battle_controls)
	for spec in [["save", "P5_SAVE", save_run], ["save_exit", "P5_SAVE_EXIT", save_and_exit]]:
		var button := Button.new()
		button.text = tr(spec[1])
		button.custom_minimum_size = Vector2(160, 36)
		button.pressed.connect(spec[2])
		battle_controls.add_child(button)
		buttons[spec[0]] = button
	battle_heading = Label.new()
	battle_heading.position = Vector2(600, 62)
	battle_heading.add_theme_font_size_override("font_size", 19)
	battle_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(battle_heading)
	feedback = Label.new()
	feedback.position = Vector2(600, 168)
	feedback.add_theme_font_size_override("font_size", 18)
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(feedback)
	if title_shell_enabled:
		shell = preload("res://src/ui/NightShell.gd").new()
		shell.host = self
		add_child(shell)
	Clock.set_paused(true)
	refresh()
	if auto_continue:
		continue_run()

func start_run(mode: String, kind := "example", seed := "") -> void:
	var candidate: RefCounted = Run.new()
	var answer: Dictionary = candidate.new_run(mode, kind, seed)
	_feedback(answer)
	if not answer.ok:
		return
	# Only discovery progress crosses nights; combat stats and resources stay local to the new run.
	var previous: RefCounted = Run.new()
	if previous.load_save(save_path).ok:
		for id in previous.state.unlocks:
			candidate.state.unlocks[id] = previous.state.unlocks[id]
		candidate.carry_story(previous.state)
	_dispose_battle()
	run = candidate
	panel.show_intro = false
	_save_state()
	refresh()

func reserve_post(uid: String, post: String) -> void:
	var answer: Dictionary = run.reserve_post(uid,post)
	if answer.ok: answer = _save_state()
	_feedback(answer)
	refresh()

func choose_node(id: String) -> void:
	var answer: Dictionary = run.choose_node(id)
	_feedback(answer)
	if not answer.ok:
		return
	if run.state.phase == "battle":
		_enter_battle(false)
	else:
		_save_state()
		refresh()

func choose_self_listing() -> void:
	var answer: Dictionary = run.choose_self_listing()
	if answer.ok:
		var saved := _save_state()
		if not saved.ok:
			answer = saved
	_feedback(answer)
	refresh()

func select_reward(id: String, target_uid := "") -> void:
	_feedback(run.choose_reward(id, target_uid))
	_save_state()
	refresh()

func buy_offer(id: String, target_uid := "") -> void:
	_feedback(run.buy_offer(id, target_uid))
	_save_state()
	refresh()

func resolve_event(id: String) -> void:
	_feedback(run.resolve_event(id))
	_save_state()
	refresh()

func treat_at_rest(uid: String) -> void:
	var answer: Dictionary = run.treat_at_rest(uid)
	if answer.ok: answer = _save_state()
	_feedback(answer)
	refresh()

func finish_rest(reserve_id := "", regroup := false) -> void:
	_feedback(run.finish_rest(reserve_id,regroup))
	_save_state()
	refresh()

func leave_node() -> void:
	_feedback(run.leave_node())
	_save_state()
	refresh()

func use_mercy() -> void:
	var answer: Dictionary = run.use_mercy()
	_feedback(answer)
	if answer.ok and run.state.phase == "battle":
		_enter_battle(false)
	else:
		_save_state()
		refresh()

func _clock_state() -> Dictionary:
	return {"paused":Clock.paused,"speed":Clock.resume_scale,"time":Clock.combat_time}

func _restore_clock(saved: Dictionary) -> void:
	Clock.set_speed(float(saved.speed))
	Clock.combat_time = float(saved.time)
	Clock.set_paused(bool(saved.paused))

func _prepare_battle(candidate: RefCounted, restoring: bool) -> Dictionary:
	# Prepare and validate before replacing the live battle or its in-memory night.
	var previous_clock := _clock_state()
	var next_combat: Node2D = preload("res://scenes/combat/Combat.tscn").instantiate()
	if candidate.state.has("nameless_modifiers") and not next_combat.configure_chunks(candidate.current_node().chunk_ids):
		next_combat.free()
		return {"ok":false,"reason":"P10_INVALID_PLAN"}
	next_combat.name = "PreparedCombat"
	add_child(next_combat)
	var decision: CanvasLayer = next_combat.get_node("Decisions")
	decision.managed_by_night = true
	decision.preferred_faction = str(candidate.state.get("opening_faction",""))
	if not decision.preferred_faction.is_empty():
		for member in candidate.state.fallen:
			decision.previous_casualties[member.id] = true
	decision.prebattle.hide()
	var next_bridge: RefCounted = Bridge.new()
	var previous_snapshot: Dictionary = candidate.state.get("battle_snapshot", {}).duplicate(true)
	var answer: Dictionary = next_bridge.start(next_combat, candidate)
	if answer.ok and restoring:
		answer = next_bridge.restore(next_combat, candidate, previous_snapshot)
	if not answer.ok:
		remove_child(next_combat)
		next_combat.queue_free()
		_restore_clock(previous_clock)
		if is_instance_valid(combat):
			combat.get_node("BattleCamera").make_current()
		return answer
	return {"ok":true,"reason":answer.reason,"combat":next_combat,"bridge":next_bridge,"clock":_clock_state()}

func _activate_battle(candidate: RefCounted, prepared: Dictionary) -> void:
	_dispose_battle()
	run = candidate
	combat = prepared.combat
	combat.name = "Combat"
	combat.set_meta("night_ritual", str(run.state.get("ritual", "example_incense")))
	bridge = prepared.bridge
	combat.get_node("BattleCamera").make_current()
	_restore_clock(prepared.clock)
	generation += 1
	settling = false
	panel.show_intro = false
	panel.hide()
	if shell != null:
		shell.hide_title()
	feedback.visible = not title_shell_enabled
	battle_heading.visible = not title_shell_enabled
	battle_controls.visible = not title_shell_enabled
	if title_shell_enabled and run.state.kind == "example" and run.state.visited.size() == 1 and int(run.state.get("guide_step",0)) < 5:
		var tutorial := preload("res://src/ui/ExampleTutorial.gd").new()
		combat.get_node("CanvasLayer").add_child(tutorial)
		tutorial.setup(run)

func _enter_battle(restoring: bool) -> void:
	var prepared := _prepare_battle(run, restoring)
	_feedback(prepared)
	if not prepared.ok:
		refresh()
		return
	_activate_battle(run, prepared)
	if not restoring:
		Clock.set_paused(false)
		_save_state()

func _process(_delta: float) -> void:
	if combat == null or not is_instance_valid(combat) or settling:
		return
	if not title_shell_enabled:
		_update_legacy_battle_heading()
	var session: Node = combat.get_node("Session")
	if session.result.is_empty():
		return
	settling = true
	Clock.set_paused(true)
	var summary: Dictionary = bridge.collect(combat, run)
	var answer: Dictionary = run.accept_battle(summary)
	_feedback(answer)
	if answer.ok:
		_dispose_battle()
		_save_state()
		refresh()
	else:
		settling = false

func _update_legacy_battle_heading() -> void:
	var decision: CanvasLayer = combat.get_node("Decisions")
	var covered: bool = decision.panel.visible or (decision.growth_panel != null and decision.growth_panel.surface.visible)
	battle_heading.visible = not covered
	feedback.visible = not covered
	var profile: Dictionary = combat.get_meta("night_profile", {})
	var node: Dictionary = run.current_node()
	var stage := ""
	var elapsed: float = combat.get_node("Simulation").simulation_time
	for phase in profile.get("phases", []):
		if elapsed >= float(phase.at):
			stage = str(phase.title) + " · " + str(phase.description)
	battle_heading.text = str(node.get("title", "")) + " / " + str(profile.get("title", ""))
	if not stage.is_empty(): battle_heading.text += "\n" + stage
	var objectives: Dictionary = preload("res://src/modes/Seat.gd").objectives(node, run.state.mode)
	battle_heading.text += "\n" + tr("P6_OBJECTIVES_PAIR") % [tr("P6_OBJECTIVE_" + str(objectives.primary).to_upper()),tr("P6_OBJECTIVE_" + str(objectives.secondary).to_upper())]

func _dispose_battle() -> void:
	if shell != null:
		shell.close_pause()
	if is_instance_valid(combat):
		remove_child(combat)
		combat.queue_free()
	combat = null
	Clock.set_paused(true)

func _save_state() -> Dictionary:
	if run.state.is_empty():
		return {"ok":false,"reason":"P5_NO_SAVE"}
	if is_instance_valid(combat):
		run.state.battle_snapshot = bridge.snapshot(combat)
	if run.state.get("roster_enabled",false):
		if is_instance_valid(combat): run.codex.merge(combat.get_node("Session").codex.snapshot())
		Data.codex_store.merge(run.codex.snapshot())
	return run.save(save_path)

func save_run() -> void:
	var answer := _save_state()
	_feedback(answer)
	if answer.ok:
		feedback.text = tr("P5_SAVE_OK")
		panel.message = tr("P5_SAVE_OK")
		if shell != null: shell.response(panel.message)
		if panel.visible: panel.render()

func save_and_exit() -> void:
	var answer := _save_state()
	_feedback(answer)
	if answer.ok:
		_dispose_battle()
		panel.show_intro = true
		refresh()

func continue_run() -> void:
	var candidate: RefCounted = Run.new()
	var answer: Dictionary = candidate.load_save(save_path)
	_feedback(answer)
	if not answer.ok:
		if not is_instance_valid(combat): refresh()
		return
	if candidate.state.get("roster_enabled",false):
		candidate.codex.path = Data.codex_store.path
		candidate.codex.autosave = true
		candidate.codex.merge(Data.codex_store.snapshot())
	if candidate.state.phase == "battle":
		# A saved battle must restore its snapshot; never silently restart a damaged snapshot.
		var prepared := _prepare_battle(candidate, true)
		_feedback(prepared)
		if not prepared.ok:
			if not is_instance_valid(combat): refresh()
			return
		_activate_battle(candidate, prepared)
	else:
		_dispose_battle()
		run = candidate
		panel.show_intro = false
		refresh()

func refresh() -> void:
	if panel == null:
		return
	var in_battle := is_instance_valid(combat)
	var main_title: bool = title_shell_enabled and not in_battle and (panel.show_intro or run.state.is_empty())
	battle_controls.visible = in_battle and not title_shell_enabled
	panel.visible = not in_battle and not main_title
	feedback.visible = in_battle and not title_shell_enabled
	battle_heading.visible = in_battle and not title_shell_enabled
	if shell != null:
		if main_title: shell.show_title()
		else: shell.hide_title()
	if panel.visible:
		Clock.set_paused(true)
		panel.render()

func _feedback(answer: Dictionary) -> void:
	if feedback != null:
		feedback.text = tr(answer.get("reason", ""))
	if panel != null:
		panel.message = tr(answer.get("reason", ""))
	if shell != null:
		shell.response(str(tr(answer.get("reason", ""))))

func copy_seed() -> void:
	DisplayServer.clipboard_set(str(run.state.get("seed", "")))
	panel.message = tr("P5_COPIED")
	panel.render()

func show_intro() -> void:
	_dispose_battle()
	panel.show_intro = true
	refresh()

func open_observer(seed_text := "") -> void:
	if not run.state.is_empty() and run.state.phase != "ended":
		var answer := _save_state()
		if not answer.ok:
			_feedback(answer)
			return
	if not seed_text.is_empty():
		get_tree().set_meta("requested_replay_seed", seed_text)
	_dispose_battle()
	get_tree().change_scene_to_file("res://scenes/modes/Observatory.tscn")

func start_p10_night(mode: String, kind: String, seed_text: String, ritual: String, modifiers: Array, faction := "") -> void:
	var candidate: RefCounted = Run.new()
	var answer: Dictionary = candidate.new_p10_run(mode,kind,seed_text,ritual,modifiers,Data.codex_store.path,faction)
	_start_roster_candidate(candidate,answer)

func start_growth_run(mode: String, seed := "", build_id := "") -> void:
	var candidate: RefCounted = Run.new()
	var answer: Dictionary = candidate.new_roster_run(mode,seed,build_id,Data.codex_store.path)
	_start_roster_candidate(candidate,answer)

func _start_roster_candidate(candidate: RefCounted, answer: Dictionary) -> void:
	_feedback(answer)
	if not answer.ok: return
	var previous: RefCounted = Run.new()
	if previous.load_save(save_path).ok:
		for id in previous.state.unlocks: candidate.state.unlocks[id] = previous.state.unlocks[id]
		candidate.carry_story(previous.state)
	_dispose_battle()
	run = candidate
	panel.show_intro = false
	_save_state()
	refresh()

func open_growth_lab() -> void:
	if not run.state.is_empty() and run.state.phase != "ended":
		var answer := _save_state()
		if not answer.ok:
			_feedback(answer)
			return
	_dispose_battle()
	get_tree().change_scene_to_file("res://scenes/modes/GrowthLab.tscn")

func open_codex() -> void:
	if codex_panel.surface.visible:
		return
	var current := get_viewport().gui_get_focus_owner()
	_codex_focus = weakref(current) if is_instance_valid(current) else null
	Clock.set_paused(true)
	if combat != null and is_instance_valid(combat) and combat.get_node("Session").roster.enabled:
		codex_panel.setup(combat.get_node("Session").codex)
	elif run != null and run.state.get("roster_enabled",false): codex_panel.setup(run.codex)
	else: codex_panel.setup(Data.codex_store)
	codex_panel.open()
	Settings.set_gameplay_modal(codex_panel.surface)

func _codex_visibility_changed() -> void:
	if codex_panel.surface.visible or _codex_focus == null:
		return
	var previous := _codex_focus.get_ref() as Control
	if is_instance_valid(previous) and previous.is_visible_in_tree():
		previous.grab_focus()
	_codex_focus = null

func open_settings() -> void:
	if shell != null:
		shell.open_settings()

func open_pause_menu() -> void:
	if shell != null and is_instance_valid(combat) and not Settings.gameplay_modal_open():
		shell.open_pause()

func resume_from_pause_menu() -> void:
	if shell != null and not Settings.gameplay_modal_open():
		shell.resume_battle()
