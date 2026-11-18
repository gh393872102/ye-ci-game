extends SceneTree
## Native fixture. Inputs enter through the actual scene buttons. Shortened, declared
## battle conditions exercise settlement, while changed fixtures never enter replay storage.
const WIN_SEED := "例夜·灯案"
const LOSS_SEED := "例夜·无名"
var output := ""
var host: Node
var data: Node
var clock: Node
var rules: Node
var checks: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	if OS.get_cmdline_user_args().size() != 1:
		quit(1)
		return
	output = OS.get_cmdline_user_args()[0]
	data = root.get_node("Data")
	clock = root.get_node("Clock")
	rules = root.get_node("Rules")
	var path := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var archive = load("res://src/replay/ReplayArchive.gd")
	var isolated: bool = path == output + "/project" and str(data.codex_store.path) == output + "/state/codex.json" and archive.directory == output + "/state/battle_replays"
	if not _check(isolated, "Project, codex and replay paths point to the current disposable fixture"):
		quit(1)
		return
	host = load("res://scenes/night/Night.tscn").instantiate()
	host.title_shell_enabled = true
	if not _check(host.save_path == output + "/state/night_save.json", "Night host verifies its isolated storage path before start"):
		host.free()
		quit(1)
		return
	root.add_child(host)
	root.size = Vector2i(1920, 1080)
	await process_frame
	_check(data.errors.is_empty(), "All nightly data and translation files load")
	if not await _victory_path():
		_finish()
		return
	await _defeat_path()
	await _duoming_market()
	_finish()

func _victory_path() -> bool:
	await _start_night("shouxiang", WIN_SEED)
	if not _check(host.run.state.get("roster_enabled", false) and host.run.state.seed == WIN_SEED, "Main night host starts a real seeded P8 roster run"):
		return false
	_check(_route_count() == 11 and not host.panel.buttons.node_n01.disabled and host.panel.buttons.node_n10.disabled, "11 map nodes with only the actual first node enabled")
	_check(host.panel.buttons.settings.is_visible_in_tree(), "The product night-map entry exposes its Settings action")
	await _click(host.panel.buttons.codex)
	var codex: CanvasLayer = host.codex_panel
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	await _joy(JOY_BUTTON_A)
	_check(codex.current_book == "ghosts", "Joypad direction and accept reach the ghost book")
	await _joy(JOY_BUTTON_DPAD_DOWN)
	await _joy(JOY_BUTTON_A)
	_check(codex.current_id == "G01" and codex.store.entry("G01").stage == 0 and codex.silhouette.visible, "An unseen entry displays a silhouette and holds back stats, skill and traits")
	await _shot("20-codex-silhouette-720", Vector2i(1280, 720))
	for book in ["items", "customs"]:
		await _click(codex.buttons["book_" + book])
		_check(codex.current_book == book and codex.rows.get_child_count() > 0,
			"Actual tabs open the " + book + " book")
	await _joy(JOY_BUTTON_B)
	_check(not codex.surface.visible and host.panel.buttons.codex.has_focus(), "Joypad cancel closes the codex and restores the map focus")

	_short_battles()
	host.run.state.names = 12.0
	host.run.state.incense = 48.0
	await _click(host.panel.buttons.node_n01)
	if not _check(is_instance_valid(host.combat), "The first node button opens the actual combat scene"):
		return false
	_isolate_battle()
	var session: Node = host.combat.get_node("Session")
	var sim: Node = host.combat.get_node("Simulation")
	var reader: Node2D = _reader(sim)
	var ghost := _ghost(sim, "G01", 115.0)
	if not _check(is_instance_valid(reader) and is_instance_valid(ghost), "Fixture places an actual white-robed ghost beside the legal register post"):
		return false
	var camera: Camera2D = host.combat.get_node("BattleCamera")
	var original_zoom := camera.zoom
	host.open_codex()
	await _click(codex.buttons.book_ghosts)
	_check(codex.store.entry("G01").stage == 1 and codex.portrait.visible and codex.portrait.material.get_shader_parameter("portrait_mode") == 2,
		"Actual ghost spawn advances its entry to visible line art")
	_check(camera.zoom == original_zoom and clock.paused, "Opening codex pauses without changing the battle camera scale")
	await _shot("20-codex-line-720", Vector2i(1280, 720))
	await _click(codex.buttons.close)
	if not _check(session.start_ritual(reader, ghost).ok, "Real paid purification starts at the indoor register"):
		return false
	reader.brain.channel.advance(sim, reader, 12)
	_check(ghost.dead and session.codex.entry("G01").stage == 2, "Actual purification advances G01 from line art to complete color")
	host.open_codex()
	await _click(codex.buttons.book_ghosts)
	var card: Dictionary = load("res://src/ui/UnitCardContent.gd").format("G01")
	_check(codex.portrait.material.get_shader_parameter("portrait_mode") == 0 and codex.details.text.contains(card.skill)
		and codex.details.text.contains(card.trait) and codex.details.text.contains(card.slots)
		and _has_text(codex.surface, card.stats), "The resolved record uses the live card's shared stat, skill, trait and slot format")
	await _shot("20-codex-color-1080", Vector2i(1920, 1080))
	await _click(codex.buttons.close)
	var named_ghost := _ghost(sim, "G32", 114.0)
	if not _check(is_instance_valid(named_ghost) and session.start_ritual(reader, named_ghost).ok, "A real protected read targets the unlisted prior"):
		return false
	reader.brain.channel.advance(sim, reader, 12)
	_check(session.codex.entry("G32").stage == 3, "The existing protected-read naming rule reaches the fourth step")
	if session.start_ritual(reader, named_ghost).ok:
		reader.brain.channel.advance(sim, reader, 12)
	host.open_codex()
	for index in 32:
		await _joy(JOY_BUTTON_DPAD_DOWN)
	await _joy(JOY_BUTTON_A)
	await _settle_frames()
	_check(codex.current_id == "G32" and codex.details.text.contains(str(data.tr("P9_CODEX_NAMED"))),
		"The named ghost displays the fourth stage and a named record")
	await _shot("20-codex-named-720", Vector2i(1280, 720))
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	var detail_view: Control = root.gui_get_focus_owner()
	_check(detail_view is ScrollContainer and detail_view.is_ancestor_of(codex.details),
		"The entry can transfer joypad focus to its complete details")
	await _joy(JOY_BUTTON_DPAD_DOWN)
	if detail_view is ScrollContainer:
		var scroll := (detail_view as ScrollContainer).get_v_scroll_bar()
		_check(not scroll.visible or scroll.value > 0, "Joypad can scroll the overflow of the unit details")
	await _click(codex.buttons.close)

	_tick(sim, 68)
	await _settle_frames()
	if not _check(host.run.state.phase == "reward" and host.run.reward_options().size() == 3 and not host.panel.buttons.has("leave"),
		"An actual battle victory opens mandatory three-choose-one with no skip"):
		return false
	await _shot("19-reward-1080", Vector2i(1920, 1080))
	await _shot("19-reward-720", Vector2i(1280, 720))
	var before: Button = root.gui_get_focus_owner()
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	_check(root.gui_get_focus_owner() != before and str(root.gui_get_focus_owner().name).begins_with("reward_"),
		"Joypad reaches a second reward choice")
	await _joy(JOY_BUTTON_A)
	if not _check(host.run.state.phase == "map" and host.run.state.offers.is_empty() and host.run.state.selected_rewards.size() == 1,
		"A single joypad confirmation records exactly one reward and consumes the other two"):
		return false
	await _click(host.panel.buttons.node_n02)
	if not await _check_market("shouxiang", "22-market-shouxiang-1080", Vector2i(1920, 1080)):
		return false

	for step in 30:
		var phase: String = host.run.state.phase
		match phase:
			"map":
				var next: Array = host.run.available_nodes()
				if next.size() == 2:
					_check(not host.panel.buttons.node_n06.disabled and not host.panel.buttons.node_n06r.disabled
						and host.panel.buttons.node_n05.disabled and _has_text(host.panel, str(data.tr("P5_CURRENT"))),
						"The map shows the current node and both genuine safe and risky alternatives")
					await _shot("18-route-fork-720", Vector2i(1280, 720))
					await _shot("18-route-fork-1080", Vector2i(1920, 1080))
					await _joy(JOY_BUTTON_DPAD_LEFT)
					_check(host.panel.buttons.node_n06r.has_focus(), "Left joypad input inspects the visible risk branch")
				await _click(host.panel.buttons["node_" + str(next[0].id)])
				if is_instance_valid(host.combat):
					_isolate_battle()
					_tick(host.combat.get_node("Simulation"), 1)
					await _settle_frames()
			"reward":
				await _click(_first_action("reward_"))
			"event":
				await _click(_first_action("event_"))
			"rest":
				await _click(host.panel.buttons.rest)
			"ended":
				break
			_:
				return _check(false, "Declared shortened route stopped at an unexpected phase " + phase)
	if not _check(host.run.state.phase == "ended" and host.run.summary().outcome == "victory"
		and host.run.summary().visited.size() == 10 and host.run.codex.entry("ritual_example_incense").stage == 2,
		"Ten-node short fixture completes genuine victory, mandatory final reward and ritual discovery"):
		return false
	_check(_has_text(host.panel, str(data.tr("P9_NIGHT_STILL_LISTED"))) and _has_text(host.panel, WIN_SEED),
		"Victory settlement shows the surviving register and actual seed")
	await _shot("21-summary-victory-1080", Vector2i(1920, 1080))
	await _click(host.panel.buttons.map_history)
	_check(_route_count() == 11 and host.panel.buttons.node_n01.disabled and host.panel.buttons.summary_back.visible,
		"Settlement can return to a read-only trace of the completed route")
	await _click(host.panel.buttons.summary_back)
	_check(host.panel.buttons.copy_seed.visible, "Route history returns to the settlement actions")
	await _click(host.panel.buttons.copy_seed)
	_check(DisplayServer.clipboard_get() == WIN_SEED and host.panel.message == str(data.tr("P5_COPIED")),
		"Native clipboard receives the actual seed after clicking Copy Seed")
	await _click(host.panel.buttons.menu)
	return _check(host.shell.title.visible and not host.shell.title_buttons.continue_run.disabled,
		"Returning to the player title keeps the finished result available")

func _defeat_path() -> void:
	await _start_night("shouxiang", LOSS_SEED)
	_short_battles()
	host.run.state.names = 1.0
	host.run.state.incense = 0.0
	await _click(host.panel.buttons.node_n01)
	_isolate_battle()
	var battle: Node = host.combat.get_node("Session")
	var sim: Node = host.combat.get_node("Simulation")
	var eraser := _ghost(sim, "G25", 115.0)
	if not _check(battle.roster.cast(eraser, {"target_id":_reader(sim).instance_id}).ok and battle.names == 0,
		"A genuine G25 erasure removes the final name in the low-name loss fixture"):
		return
	_tick(sim, 11)
	await _settle_frames()
	_check(host.run.state.phase == "mercy", "Actual loss opens the free-recovery decision")
	await _click(host.panel.buttons.decline)
	if not _check(host.run.state.phase == "ended" and host.run.summary().reason == "P4_END_REGISTER_EXTINGUISHED"
		and host.run.summary().killer_id == "G25", "Declining recovery settles the actual loss with the first broken failure line"):
		return
	_check(_has_text(host.panel, str(data.tr("P4_END_REGISTER_EXTINGUISHED"))) and _has_text(host.panel, "抹名吏"),
		"Defeat names the concrete reason and the actual eraser")
	await _shot("21-summary-defeat-720", Vector2i(1280, 720))
	await _click(host.panel.buttons.codex)
	await _click(host.codex_panel.buttons.failure_log)
	_check(host.codex_panel.failure_text.text.contains(LOSS_SEED) and host.codex_panel.failure_text.text.contains("抹名吏"),
		"Failure register displays the real loss seed and identity")
	await _joy(JOY_BUTTON_B)
	_check(not host.codex_panel.buttons.failure_back.is_visible_in_tree() and host.codex_panel.surface.visible,
		"Joypad cancel closes the failure history without closing its codex")
	await _joy(JOY_BUTTON_B)
	var loaded: Dictionary = data.codex_store.load_save()
	_check(loaded.ok and not data.codex_store.failures.is_empty(), "Failure history is actually saved on the isolated player profile")
	await _click(host.panel.buttons.menu)

func _duoming_market() -> void:
	await _start_night("duoming", "例夜·阴缝")
	_short_battles()
	host.run.state.names = 0.0
	host.run.state.incense = 50.0
	await _click(host.panel.buttons.node_n01)
	if is_instance_valid(host.combat):
		_isolate_battle()
		_tick(host.combat.get_node("Simulation"), 1)
	await _settle_frames()
	if not _check(host.run.state.phase == "reward", "The low-name attacker fixture advances through actual win settlement"):
		return
	await _click(_first_action("reward_"))
	await _click(host.panel.buttons.node_n02)
	await _check_market("duoming", "22-market-duoming-720", Vector2i(1280, 720))

func _check_market(seat: String, shot_id: String, resolution: Vector2i) -> bool:
	if not _check(host.run.state.phase == "market" and host.run.market_options().size() == 4,
		"The " + seat + " night market opens its four seeded offers"):
		return false
	var offers: Array = host.run.market_options()
	var recruits := 0
	for offer in offers:
		if offer.effect.kind == "recruit" and str(offer.effect.unit_id).begins_with("G" if seat == "duoming" else "H"):
			recruits += 1
	_check(recruits >= 1, "The " + seat + " market offers the actual seat-specific roster")
	await _shot(shot_id, resolution)
	var action := _first_action("buy_")
	var offer_id := str(action.name).trim_prefix("buy_")
	var price := 0.0
	for offer in offers:
		if offer.id == offer_id:
			price = float(offer.cost)
	var incense: float = host.run.state.incense
	var names: float = host.run.state.names
	await _joy(JOY_BUTTON_A)
	if not _check(is_equal_approx(float(host.run.state.incense), incense - price) and host.run.state.names == names
		and offer_id in host.run.state.purchased and host.panel.buttons["buy_" + offer_id].disabled,
		"The " + seat + " joypad purchase debits only the visible incense price and prevents duplicate confirmation"):
		return false
	await _joy(JOY_BUTTON_DPAD_DOWN)
	_check(host.panel.buttons.leave.has_focus(), "Joypad can focus Continue Route from the market offers")
	await _joy(JOY_BUTTON_A)
	return _check(host.run.state.phase == "map", "The market exit returns to the genuine next route")

func _short_battles() -> void:
	for id in host.run.config.battle_profiles:
		var profile: Dictionary = host.run.config.battle_profiles[id]
		profile.duration = 60.0 if id == "entry" and host.run.state.mode == "shouxiang" else 0.25
		profile.waves = []
		profile.phase_waves = []

func _start_night(seat: String, seed: String) -> void:
	await _click(host.shell.title_buttons.start)
	host.shell.night_kind.select(0)
	host.shell.seed_input.text = seed
	await _click(host.shell.title_buttons[seat])

func _isolate_battle() -> void:
	clock.set_paused(true)
	host.combat.get_node("Simulation").set_physics_process(false)
	if host.bridge.recording != null:
		host.bridge.recording.stop()
		host.bridge.recording = null

func _reader(sim: Node) -> Node2D:
	for unit in sim.humans:
		if unit.unit_id == "H01":
			return unit
	return null

func _ghost(sim: Node, id: String, x: float) -> Node2D:
	var actor: Node2D = sim.tide.spawn(id, 0, rules.body_to_px(x))
	actor.attacks_enabled = false
	actor.motion_enabled = false
	return actor

func _tick(sim: Node, seconds: float) -> void:
	for index in ceili(seconds * 60):
		if not host.combat.get_node("Session").result.is_empty():
			return
		sim.advance(1.0 / 60)

func _route_count() -> int:
	var count := 0
	for key in host.panel.buttons:
		if str(key).begins_with("node_"):
			count += 1
	return count

func _first_action(prefix: String) -> Button:
	for key in host.panel.buttons:
		if str(key).begins_with(prefix) and not host.panel.buttons[key].disabled:
			return host.panel.buttons[key]
	return null

func _has_text(node: Node, sought: String) -> bool:
	if node is Label and node.is_visible_in_tree() and node.text.contains(sought):
		return true
	for child in node.get_children():
		if _has_text(child, sought):
			return true
	return false

func _check(value: bool, label: String) -> bool:
	checks.append({"test":label, "passed":value})
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1
	return value

func _settle_frames() -> void:
	await process_frame
	await process_frame

func _click(button: Button) -> void:
	if not is_instance_valid(button):
		return
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _settle_frames()

func _joy(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _settle_frames()

func _shot(id: String, resolution: Vector2i) -> void:
	root.size = resolution
	await _settle_frames()
	RenderingServer.force_draw(true)
	var image := root.get_texture().get_image()
	if not _check(is_instance_valid(image), "Native framebuffer exists for " + id):
		return
	var path := output + "/" + id + ".png"
	_check(image.save_png(path) == OK and image.get_size() == resolution, "Native screenshot " + id + " has the requested dimensions")
	captures.append({"id":id, "width":image.get_width(), "height":image.get_height(), "sha256":FileAccess.get_sha256(path)})

func _finish() -> void:
	var source: Dictionary = {}
	for path in ["src/ui/NightPanel.gd", "src/ui/CodexPanel.gd", "src/ui/LedgerInk.gd", "src/ui/UnitCardContent.gd", "resources/p9_theme.tres"]:
		source[path] = FileAccess.get_sha256("res://" + path)
	var report := {
		"engine":Engine.get_version_info().string,
		"scope":"Native UI input and short declared simulation fixtures; not ordinary example-night balance.",
		"procedures":{"battle_profiles":"No scheduled waves; 60-second first defender fixture, other nodes 0.25 seconds.",
			"defeat":"One name, zero incense, genuine G25 erasure and extinguish window.",
			"attacker_market":"Zero initial names advances the attacker through the first real win.",
			"controls":"Mouse plus virtual joypad button events through Viewport.push_input.",
			"storage":"Disposable mirror checks actual night, codex and replay paths before input."},
		"checks":checks, "captures":captures, "total":checks.size(), "failures":failures,
		"source_sha256":source,
	}
	var file := FileAccess.open(output + "/night-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	quit(0 if failures == 0 else 1)
