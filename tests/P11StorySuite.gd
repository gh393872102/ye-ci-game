extends SceneTree
## Run through tools/p9_verify.py --native --script tests/P11StorySuite.gd.
## Authored battle positions and accelerated clocks let the actual rules settle each route.
const NIGHT := "res://scenes/night/Night.tscn"
const STEP := 1.0 / 60.0
var output := ""
var clock: Node
var data: Node
var host: Node
var sim: Node
var session: Node
var story: Script
var save_io: Script
var checks: Array[Dictionary] = []
var observations: Dictionary = {}
var shots: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ""
	data = root.get_node("Data")
	var isolated: bool = (output.begins_with("/tmp/ye-ci-p9-") or output.begins_with("/private/tmp/ye-ci-p9-")) and data.codex_store.path == output.path_join("state/codex.json")
	if not isolated:
		print("FAIL P11 story suite requires an isolated acceptance copy")
		quit(2)
		return
	clock = root.get_node("Clock")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1920, 1080)
	story = load("res://src/night/NightStory.gd")
	save_io = load("res://src/night/NightSave.gd")
	check(data.errors.is_empty() and not story.rules().is_empty(), "Boot loads the Chinese string table and the editable story conditions", data.errors)
	await _restore_path()
	await _release_path()
	await _self_path()
	await _loss_path()
	_catalog_strings()
	if is_instance_valid(host):
		host.free()
	var failed := checks.filter(func(row): return not row.ok).size()
	var report := FileAccess.open(output.path_join("p11-story-results.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({
		"checks":checks.size(), "failures":failed, "results":checks, "observations":observations, "screenshots":shots,
		"story_rules_sha256":FileAccess.get_sha256("res://data/story/endings.json"), "engine_version":Engine.get_version_info().string,
		"scope":"Native Night host, battle commands and disk saves. Debug scenarios place enemies and accelerate the timer, while the live battle and three-choice reward settle outcomes."
	}, "\t", true, true) + "\n")
	quit(0 if failed == 0 else 1)

func _host(filename: String) -> void:
	if is_instance_valid(host):
		host.free()
	host = load(NIGHT).instantiate()
	host.save_path = output.path_join("state").path_join(filename + ".json")
	root.add_child(host)

func _restore_path() -> void:
	_host("restore")
	host.start_p10_night("shouxiang", "example", "P11-return-to-rite-1", "R01", [])
	if not check(host.run.story_enabled() and _act() == "P11_ACT_REKINDLE", "Restoration starts in the actual opening act"):
		return
	check(not host.run.choose_self_listing().ok, "Self-listing is rejected away from the designated rite and final node")
	await _shot("p11-act-1-rekindle")
	if not _walk(func(node): return _readings(4, "G01") if node == "n01" else true):
		return
	var first: Dictionary = host.run.summary().story
	check(first.ending.is_empty() and first.flags.exorcise_count == 4 and first.flags.register_held == 5,
		"Four actual exorcisms and five held registers are saved without granting restoration early", first)
	host.start_p10_night("shouxiang", "example", "P11-return-to-rite-2", "R01", [])
	check(host.run.state.story.flags.exorcise_count == 4 and not host.run.state.story.flags.finished_seize_night, "The next hosted night reads its exact prior tally and needs no competing seat")
	if not _walk(func(node): return _restore_behavior(node), "n05"):
		return
	check(_act() == "P11_ACT_RECEIVE", "The night's middle route introduces Receive the Register")
	await _shot("p11-act-2-receive")
	if not _walk(func(node): return _restore_behavior(node), "n10"):
		return
	check(_act() == "P11_ACT_LIST", "The final map moves naturally to List Names")
	await _shot("p11-act-3-list")
	if not _walk():
		return
	var result: Dictionary = host.run.summary()
	check(result.story.ending == "E01" and result.story.flags.exorcise_count == 8 and result.story.flags.slay_exorcisable_count == 1,
		"Eight paid successful readings across two nights and one paid execution qualify for E01", result.story)
	check(result.story.flags.renown >= 8 and result.story.flags.renown_peak >= 10 and result.story.flags.register_held == 10,
		"The actual night preserves final and peak names and held-register history", result.story.flags)
	observations.E01 = _route_evidence(result)
	await _shot("p11-ending-e01")
	await _codex_epilogue("ghosts", "G01", "P11_EPILOGUE_G01", "p11-epilogue-e01")

func _restore_behavior(node: String) -> bool:
	if node != "n01":
		return true
	if not _readings(4, "G01"):
		return false
	var reader := _actor("H01")
	var peak: float = session.names
	if not _erase_to(reader, peak - 2):
		return false
	host.save_run()
	var current: Node = host.combat
	host.continue_run()
	if not check(host.combat != current and is_instance_valid(host.combat), "The live reading ledger and exact renown peak survive a disk reload"):
		return false
	_bind_battle()
	var snapshot: Dictionary = host.bridge.snapshot(host.combat)
	check(snapshot.bridge.renown_peak == peak and session.names == peak - 2, "The live peak holds after real erasure lowers the current balance")
	var older: Dictionary = save_io.load_save(host.save_path).state
	older.erase("story")
	older.battle_snapshot.bridge.erase("renown_peak")
	var old_path := output.path_join("state").path_join("prior-schema.json")
	save_io.save(old_path, older)
	var loaded: RefCounted = load("res://src/night/NightRun.gd").new()
	check(loaded.load_save(old_path).ok and loaded.story_enabled() and loaded.state.story.flags.exorcise_count == 0,
		"A pre-story night save loads with no invented historical activity")
	var bought: Dictionary = session.purchase("H13")
	var deployed: Dictionary = session.deploy_at("post_register")
	if not check(bought.ok and deployed.ok, "The actual purchase and legal register deployment produce an execution caster", [bought.reason, deployed.reason]):
		return false
	var executioner: Node2D = deployed.unit
	executioner.attacks_enabled = false
	executioner.hold_lock = true
	var prisoner := _place_ghost("G01", executioner)
	var arguments := {"unit_id":executioner.instance_id, "target_id":prisoner.instance_id}
	check(not session.roster_command("unit_skill", arguments).ok, "An ineligible attempted execution does not create a choice record")
	prisoner.receive_damage(prisoner.hp - 1.0, executioner, "melee")
	var ordered: Dictionary = session.roster_command("unit_skill", arguments)
	check(ordered.ok and prisoner.dead, "The genuine paid execution takes a living exorcisable target")
	var ordinary := _place_ghost("G01", executioner)
	ordinary.receive_damage(ordinary.hp, executioner, "melee")
	return true

func _release_path() -> void:
	_host("release")
	host.start_p10_night("duoming", "example", "P11-listened-from-the-tide", "R01", [])
	if not _walk():
		return
	var tide: Dictionary = host.run.summary()
	check(tide.story.flags.finished_seize_night and tide.story.ending.is_empty() and tide.visited.back() == "n10",
		"Only a legal terminal result records the other seat, with no Keeper ending", tide.story)
	observations.seize = _route_evidence(tide)
	await _shot("p11-seize-seat")
	host.start_p10_night("shouxiang", "example", "P11-let-the-tide-go", "R01", [])
	check(host.run.state.story.flags.finished_seize_night, "The actual played Seize Name result crosses into the next Keeper night")
	if not _walk(func(node): return _release_behavior(node), "n10"):
		return
	if not _walk(func(node): return _release_behavior(node)):
		return
	var result: Dictionary = host.run.summary()
	check(result.story.ending == "E02" and result.story.flags.release_or_recruit_count >= 1 and result.story.flags.renown >= 4 and result.story.flags.renown <= 7,
		"A real lamp reading, unfinished tide, past Seize Name night and moderate settled names qualify for E02", result.story)
	observations.E02 = _route_evidence(result)
	await _shot("p11-ending-e02")
	await _codex_epilogue("ghosts", "G11", "P11_EPILOGUE_G11", "p11-epilogue-e02")

func _release_behavior(node: String) -> bool:
	if node == "n01":
		return _readings(1, "G11")
	if node == "n10":
		return _erase_to(_actor("H01"), 2.0)
	return true

func _self_path() -> void:
	_host("self")
	host.start_p10_night("shouxiang", "fierce", "P11-name-in-ink", "R08", [])
	if not _walk(Callable(), "n10"):
		return
	var option: Dictionary = host.run.self_listing_choice()
	if not check(option.get("allowed", false) and host.panel.buttons.has("self_listing"), "The live R08 route visibly offers self-listing just before the last real battle", option):
		return
	var names_before: float = host.run.state.names
	await _shot("p11-self-listing-choice")
	await _activate(host.panel.buttons.self_listing)
	var listed: Dictionary = host.run.state.story.self_listing
	if not check(not listed.is_empty() and host.run.state.names == names_before - listed.names_paid and listed.max_hp_after < listed.max_hp_before,
			"The actual choice pays names and wounds Wan on the night roster", listed):
		return
	check(not host.run.choose_self_listing().ok and host.run.state.names == names_before - listed.names_paid, "Repeating the explicit choice cannot pay or wound twice")
	host.continue_run()
	check(host.run.state.story.self_listing == listed and host.run.state.names == names_before - listed.names_paid, "The explicit choice and payment survive a disk reload")
	host.choose_node("n10")
	if not _bind_battle():
		check(false, "Wan enters the restored final route")
		return
	var wan := _actor("H01")
	var replacement: Dictionary = session.purchase("H01")
	check(is_instance_valid(wan) and wan.max_hp == listed.max_hp_after and wan.hp <= wan.max_hp and replacement.reason == "P4_UNKNOWN_PURCHASE",
		"Wan actually fights at the paid lower maximum and cannot be re-bought at full strength", {"max_hp":wan.max_hp, "repurchase":replacement.reason})
	check(host.run.state.story.ending.is_empty(), "Selecting self-listing alone does not grant an ending")
	host.combat.get_node("BattleCamera").set_left(7680.0)
	host.combat.get_node("Decisions").select_unit(wan)
	await _shot("p11-self-listing-battle")
	if not _walk():
		return
	var result: Dictionary = host.run.summary()
	check(result.story.ending == "E03" and result.story.self_listing == listed,
		"The self-listing ending is set only after the real final win and reward", result.story)
	observations.E03 = _route_evidence(result)
	await _shot("p11-ending-e03")
	await _codex_epilogue("humans", "H01", "P11_EPILOGUE_H01", "p11-epilogue-e03")
	await _codex_epilogue("customs", "ritual_lieming", "P11_EPILOGUE_R08", "p11-epilogue-rite")

func _loss_path() -> void:
	_host("loss")
	var rng := RandomNumberGenerator.new()
	var seed_text := ""
	for index in 100:
		seed_text = "P11-empty-seat-%d" % index
		rng.seed = seed_text.hash()
		if rng.randf() < float(data.growth_rules.borrow.failure_rate):
			break
	host.start_p10_night("shouxiang", "example", seed_text, "R01", [])
	host.choose_node("n01")
	if not check(_bind_battle(), "The failure fixture opens the actual first battle"):
		return
	var reader := _actor("H01")
	var borrowed: Dictionary = session.execute_for("shouxiang", "borrow_god", {"unit_id":reader.instance_id}, "player")
	var rejected: Dictionary = session.execute_for("shouxiang", "borrow_god", {"unit_id":reader.instance_id}, "player")
	check(borrowed.ok and not rejected.ok, "A live borrow starts and a repeat while reading is rejected")
	_ticks(190)
	check(session.ledger.any(func(row): return row.action == "growth_borrow_backlash"), "The deterministic borrow resolves to an actual empty seat")
	if not _erase_to(reader, 0.0):
		return
	_ticks(int(ceil(float(session.rules.extinguish_seconds) / STEP)) + 3)
	var before: Dictionary = host.bridge.collect(host.combat, host.run)
	host._process(0)
	if not check(host.run.state.phase == "mercy" and host.run.state.last_battle.killer_id == "G25", "The extinguish timer settles a real loss blamed on its live eraser", before.get("reason")):
		return
	var flags: Dictionary = host.run.state.story.flags
	check(flags.borrow_god_count == 1 and flags.empty_god_count == 1 and flags.register_checked == 1 and flags.register_held == 0,
		"Successful spend, backlash, and failed register count exactly once", flags)
	var stale: Dictionary = host.run.state.last_battle.duplicate(true)
	host.use_mercy()
	var old_flags: Dictionary = host.run.state.story.flags.duplicate(true)
	check(not host.run.accept_battle(stale).ok and host.run.state.story.flags == old_flags,
		"The same node's old settlement is rejected during the real mercy retry")
	if _bind_battle():
		reader = _actor("H01")
		_erase_to(reader, 0.0)
		_ticks(int(ceil(float(session.rules.extinguish_seconds) / STEP)) + 3)
		host._process(0)
	check(host.run.state.phase == "ended" and host.run.state.story.ending.is_empty(), "A failed terminal state records the loss while withholding victory endings")
	host.open_codex()
	await _activate(host.codex_panel.buttons.failure_log)
	check(str(host.codex_panel.failure_text.text).contains("抹名吏") and str(host.codex_panel.failure_text.text).contains(seed_text),
		"The live codex failure window names the actual eraser and the night seed")
	var records: Array = host.run.codex.failures.filter(func(entry): return str(entry.seed).begins_with(seed_text))
	check(records.size() == 1, "The same failure cause is recorded once across battle and night settlement", records)
	observations.loss = {"seed":seed_text, "failure_records":host.run.codex.failures, "flags":host.run.state.story.flags}
	await _shot("p11-failure-record")

func _walk(behavior := Callable(), stop_before := "") -> bool:
	for _step in 32:
		var state: Dictionary = host.run.state
		var node: Dictionary = host.run.current_node()
		match state.phase:
			"ended":
				return true
			"map":
				var next: Array = host.run.available_nodes()
				if next.is_empty():
					break
				if next[0].id == stop_before:
					return true
				host.choose_node(str(next[0].id))
			"battle":
				if not _bind_battle():
					break
				if behavior.is_valid() and not behavior.call(str(node.id)):
					return false
				if state.mode == "duoming":
					_capture_register()
				else:
					session.remaining = STEP
					_ticks(2)
				if not check(not session.result.is_empty(), "Simulator decides the outcome at " + str(node.id), session.result.duplicate()):
					return false
				host._process(0)
			"reward":
				var choice := _option(host.run.reward_options())
				if choice.is_empty():
					break
				check(host.run.state.story.ending.is_empty(), "The reward must settle before any ending at " + str(node.id))
				host.select_reward(str(choice.id), str(choice.get("target_uid", "")))
			"rest":
				host.finish_rest()
			"event":
				var choice := _option(host.run.event_options())
				if choice.is_empty():
					break
				host.resolve_event(str(choice.id))
			"market":
				host.leave_node()
			_:
				break
	return check(false, "A legal route progresses through authored choices", {"phase":host.run.state.phase, "node":host.run.state.current_node_id})

func _option(rows: Array) -> Dictionary:
	for entry in rows:
		if entry.get("allowed", false) and not entry.get("requires_target", false):
			return entry
	return {}

func _bind_battle() -> bool:
	if not is_instance_valid(host.combat):
		return false
	sim = host.combat.get_node("Simulation")
	session = host.combat.get_node("Session")
	sim.set_physics_process(false)
	clock.set_paused(true)
	if host.bridge.recording != null:
		host.bridge.recording.stop()
		host.bridge.recording = null
	for actor in sim.humans + sim.targets:
		actor.attacks_enabled = false
		actor.motion_enabled = false
		actor.hold_lock = true
	return true

func _capture_register() -> void:
	var intruder: Node2D = sim.targets[0]
	var post: Node2D = sim.world.get_node("post_register")
	intruder.position = post.position
	intruder.floor_id = int(post.get_meta("floor_id"))
	intruder.motion_enabled = false
	intruder.attacks_enabled = false
	for guard in sim.humans:
		if sim.world.room_at(guard.position, guard.floor_id) == "register":
			guard.position = sim.world.get_node("post_hall_door").position
	_ticks(int(ceil(float(session.rules.occupation_seconds) / STEP)) + 3)

func _readings(count: int, id: String) -> bool:
	for _index in count:
		var reader := _actor("H01")
		var ghost := _place_ghost(id, reader)
		var started: Dictionary = session.start_ritual(reader, ghost)
		if not check(started.ok, "The actual indoor reader starts a paid reading for " + id, started.reason):
			return false
		_ticks(int(ceil(float(reader.brain.channel.duration) / STEP)) + 2)
		if not check(reader.brain.channel.last_result == "P4_RITUAL_COMPLETED" and (ghost.dead or ghost.side == "xianghuo"),
				"The reading resolves into an actual release or temporary recruitment for " + id):
			return false
	return true

func _erase_to(reader: Node2D, targeted: float) -> bool:
	var initial: float = session.names
	while session.names > targeted:
		var eraser := _place_ghost("G25", reader)
		var before: float = session.names
		var acted: Dictionary = session.roster.cast(eraser, {"target_id":reader.instance_id})
		if not acted.ok or session.names >= before:
			return check(false, "The real eraser can lower names from its authored nearby position", acted.reason)
	return check(session.names == targeted, "Live erasures lower names without injecting the settlement", {"before":initial, "after":session.names})

func _actor(id: String) -> Node2D:
	for actor in sim.humans + sim.targets:
		if actor.unit_id == id and not actor.dead:
			return actor
	return null

func _place_ghost(id: String, near: Node2D) -> Node2D:
	var actor: Node2D = sim.tide.spawn(id, 2, near.position.x - 44)
	actor.position.y = near.position.y
	actor.floor_id = near.floor_id
	actor.motion_enabled = false
	actor.attacks_enabled = false
	return actor

func _ticks(count: int) -> void:
	for _tick in count:
		if not session.running:
			break
		sim.advance(STEP)

func _catalog_strings() -> void:
	var books: Dictionary = data.codex_store.catalog
	var missing: Array[String] = []
	for id in books:
		var row: Dictionary = books[id]
		var prefix := "P11_UNIT_" + str(id)
		var expected := "SKILL"
		if row.book == "items":
			prefix = "P11_ITEM_" + str(id)
			expected = "DETAIL"
		elif row.book == "customs":
			prefix = "P11_CUSTOM_" + str(id).to_upper()
			expected = "DETAIL"
		var name_key := prefix + "_NAME"
		var detail_key := prefix + "_" + expected
		if row.name != TranslationServer.translate(name_key) or row.skill_text != TranslationServer.translate(detail_key):
			missing.append(id)
	check(missing.is_empty() and books.size() == 108, "Every Chinese name and main text in the four displayed books resolves through strings", missing)

func _codex_epilogue(book: String, id: String, key: String, filename: String) -> void:
	host.open_codex()
	host.codex_panel.show_book(book)
	host.codex_panel.select_entry(id)
	check(host.run.codex.entry(id).stage == 3 and str(host.codex_panel.details.text).contains(TranslationServer.translate(key)),
		"The live codex panel exposes the completed epilogue for " + id)
	await _shot(filename)
	host.codex_panel.close()

func _route_evidence(summary: Dictionary) -> Dictionary:
	return {"seed":summary.seed, "visited":summary.visited, "battles":summary.battles, "story":summary.story,
		"mode":summary.mode, "result":summary.outcome, "codex_progress":summary.codex.progress}

func _act() -> String:
	return str(host.run.story_act().get("title_key", ""))

func _activate(button: Button) -> void:
	button.grab_focus()
	await process_frame
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	RenderingServer.force_draw(true)
	var image := root.get_texture().get_image()
	var path := output.path_join(name + ".png")
	if check(not image.is_empty() and image.save_png(path) == OK, "Native frame saved for " + name):
		shots[name] = {"file":path.get_file(), "sha256":FileAccess.get_sha256(path), "width":image.get_width(), "height":image.get_height()}

func check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"ok":ok, "label":label, "detail":detail})
	print(("PASS " if ok else "FAIL ") + label)
	return ok
