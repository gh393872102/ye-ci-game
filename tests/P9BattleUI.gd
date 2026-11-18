extends SceneTree
## Native viewport input and fixed-step battle fixtures. The Night host is covered separately.

var output: String
var native: bool
var data: Node
var clock: Node
var combat: Node2D
var sim: Node2D
var session: Node
var panel: CanvasLayer
var world: Node2D
var camera: Camera2D
var hud: Control
var rows: Array[Dictionary] = []
var screenshots: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ""
	data = root.get_node("Data")
	clock = root.get_node("Clock")
	var temp_output := output.simplify_path()
	var prefix_ok := temp_output.begins_with("/tmp/ye-ci-p9-") or temp_output.begins_with("/private/tmp/ye-ci-p9-")
	var settings: Script = root.get_node("Settings").get_script()
	var settings_path: String = settings.get_script_constant_map().get("PATH", "")
	if not prefix_ok or data.codex_store.path != temp_output + "/state/codex.json" or settings_path != temp_output + "/state/settings.cfg":
		print("FAIL P9 battle UI requires isolated temporary player paths")
		quit(2)
		return
	native = DisplayServer.get_name() != "headless"
	if native:
		root.size = Vector2i(1920, 1080)
		await process_frame
		await process_frame
	combat = load("res://scenes/combat/Combat.tscn").instantiate()
	root.add_child(combat)
	if not combat.has_node("Simulation") or not combat.has_node("Decisions") or not combat.has_node("CanvasLayer/HUD"):
		print("FAIL Battle scene could not create simulation, decision or HUD nodes")
		quit(2)
		return
	sim = combat.get_node("Simulation")
	session = combat.get_node("Session")
	panel = combat.get_node("Decisions")
	world = combat.get_node("ReferenceMap")
	camera = combat.get_node("BattleCamera")
	hud = combat.get_node("CanvasLayer/HUD")
	sim.set_physics_process(false)
	_start("shouxiang")
	session.configure_growth("p9-interface-fixture", {"inventory":{"I17":1}})
	session.configure_roster("p9-interface-fixture")
	await process_frame
	var exact_view := _view()
	check(data.errors.is_empty(), "Source and Chinese table validation")
	check(hud.ritual.text == _tr("RITUAL") and hud.goal_label.text == "04:00", "Entry HUD reads current ritual and duration")
	check(not hud.register_status.text.is_empty() and not hud.incense.text.is_empty() and not hud.names.text.is_empty() and not hud.door_status.text.is_empty() and not hud.upper_status.text.is_empty(), "Five simultaneous book, economy, door and upper-floor text values")
	check(hud.command_bar.get_child_count() == 6 and not _text(hud.command_bar).contains("变异"), "Shouxiang shows six commands without mutation")
	check(camera.zoom == Vector2.ONE and is_equal_approx(hud.minimap.camera_rect().size.x / hud.minimap.MAP_RECT.size.x, 0.2), "Default camera stays far; minimap spans the exact one-fifth slice")
	await _shot("01-hud")

	await _key(KEY_Q)
	check(panel.current_panel == "purchase" and clock.paused and _view() == exact_view, "Q opens paused purchase without moving the camera")
	check(_text(panel.content).contains("生命") and _text(panel.content).contains("攻击") and _text(panel.content).contains("射程") and panel.buttons.buy_T01.text.contains("5"), "Purchase cards show live source price and core combat stats")
	await _shot("14-purchase")
	await _click(panel.buttons.purchase_next)
	check(panel.purchase_page == 1 and not panel.offer_status.has("T01"), "The second offer page uses new scoped entries")
	await _click(panel.buttons.purchase_prev)
	var funds: float = session.incense
	await _click(panel.buttons.buy_T01)
	check(panel.current_panel == "deploy" and session.pending_purchase == "T01" and is_equal_approx(session.incense, funds - 5.0), "Real purchase reserves exactly one offer")
	check(panel.legal_post_ids.all(func(id): return world.can_deploy_at(id) and session.deployment_reason(id, "T01").is_empty()), "Only real cover posts receive legal markers")
	await _shot("14-deployment")
	camera.set_left((world.get_node("door_outer").position.x) - 300)
	await _mouse_world(world.get_node("door_outer").position - Vector2(165, 24), false)
	check(panel.target_hint.text == _tr("P9_DEPLOY_OUTSIDE"), "Cursor gives an explicit outer-gate rejection")
	var court: Array = world.layout.base_region.court_intervals[0]
	var court_point := Vector2((float(court[0]) + float(court[1])) * 40.0, 688.0)
	await _mouse_world(court_point, true)
	check(panel.target_hint.text == _tr("P9_DEPLOY_COURT") and session.pending_purchase == "T01" and is_equal_approx(session.incense, funds - 5.0), "Courtyard click explains rejection and keeps the paid reservation intact")
	await _pad(JOY_BUTTON_B)
	check(session.pending_purchase.is_empty() and is_equal_approx(session.incense, funds), "Controller cancel refunds the reservation")
	camera.set_left(float(exact_view[0].position.x))
	await _pad(JOY_BUTTON_X)
	check(panel.current_panel == "commands" and panel.buttons.command_BUY.has_focus(), "Controller X opens the full command list with focus")
	await _pad(JOY_BUTTON_A)
	check(panel.current_panel == "purchase" and panel.buttons.buy_T01.has_focus(), "Controller A opens purchase and focuses a legal offer")
	await _pad(JOY_BUTTON_A)
	var post_button := root.gui_get_focus_owner()
	check(post_button != null and str(post_button.name).begins_with("post_post_"), "Controller offer confirmation focuses a legal cover post")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	var next_post := root.gui_get_focus_owner()
	check(is_instance_valid(next_post) and next_post != post_button and panel.legal_post_ids.has(str(next_post.name).trim_prefix("post_")), "Controller D-pad can choose another exact legal cover post")
	await _pad(JOY_BUTTON_A)
	check(session.pending_purchase.is_empty() and is_instance_valid(panel.selected) and panel.selected.unit_id == "T01", "Controller places the reserved unit by confirming the focused post")
	check(_view() == exact_view, "Controller purchase and deployment preserve the original viewport")

	panel.close_panel()
	var actor := _human("H17")
	camera.set_left(actor.position.x - 1040)
	await process_frame
	var card_view := _view()
	clock.set_paused(false)
	await _mouse_world(actor.aim_point(), true)
	check(panel.selected == actor and clock.paused and panel.unit_panel.visible, "Clicking a live actor pauses and opens the full card")
	var shared: Dictionary = load("res://src/ui/UnitCardContent.gd").format(actor.unit_id, actor)
	check(["title", "affiliation", "stats", "skill", "trait", "tags", "slots"].all(func(key): return panel.details.text.contains(shared[key])), "Battle card reads the same complete fields as Codex")
	check(panel.portrait.texture != null and _view() == card_view, "Portrait appears in the card and leaves world geometry unchanged")
	await _shot("17-unit-card")

	await _key(KEY_E)
	check(panel.current_panel == "upgrade" and panel.buttons.upgrade_confirm.visible and _text(panel.content).contains("名帖") and _text(panel.content).contains("→"), "Upgrade shows current stats, preview and four equipment slots")
	await _shot("15-upgrade")
	await _click(panel.buttons.upgrade_confirm)
	check(actor.upgrade_level == 1, "Real upgrade confirm increments the selected actor once")
	await _key(KEY_V)
	check(panel.growth_panel.surface.visible and panel.growth_panel.slot_picker.item_count == 4 and _view() == card_view, "Equipment shortcut exposes one censer, two arts and one nameplate at the same zoom")
	await _shot("15-equipment")
	await _click(panel.growth_panel.buttons.equip_item)
	check(actor.growth.slots.censer == "I17" and panel.details.text.contains("册底针"), "Equipment spends real inventory and updates the card")

	await _ritual_fixture()
	await _group_fixture()
	if native:
		root.size = Vector2i(1280, 720)
		await process_frame
		await process_frame
		_start("shouxiang")
		session.configure_roster("p9-purchase-720")
		panel.open_purchase()
		await process_frame
		check(not panel.warning_plate.visible, "A fresh battle clears prior interruption warnings")
		var first_card: Button = panel.buttons.buy_T01
		check(panel.panel_scroll.get_global_rect().encloses(first_card.get_global_rect()), "At 720p the full first purchase button fits in the unscrolled panel")
		await _shot("14-purchase-720")
	if is_instance_valid(combat):
		combat.free()
	var report := {
		"scope":"Isolated battle and authored read/interruption/pressure/selection fixtures exercised through native Godot viewport events. Ordinary Night progression is covered by P9InputNight.",
		"engine":Engine.get_version_info().string, "display":DisplayServer.get_name(),
		"connected_controllers":Input.get_connected_joypads(), "checks":rows.size(),
		"failures":failures, "results":rows, "screenshots":screenshots
	}
	FileAccess.open(output + "/battle-ui.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("P9 BATTLE UI RESULT: %d checks, %d failures" % [rows.size(), failures])
	quit(1 if failures > 0 else 0)

func _ritual_fixture() -> void:
	panel.close_panel()
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.config.waves = []
	session.incense = 24
	var caster := _human("H01")
	var target := _ghost(caster.position.x - 100)
	var unentered := _ghost(87.2 * 80)
	var guard := _human("H09")
	var skirmisher := _ghost(guard.position.x - 50)
	sim._update_units()
	camera.set_left(6900)
	await _key(KEY_R)
	check(panel.current_panel == "ritual" and panel.legal_ritual_targets.size() == 1 and panel.legal_ritual_targets[0] == target, "Point-rite picker only offers the legal ghost already in hall")
	var funds: float = session.incense
	await _mouse_world(unentered.aim_point(), true)
	check(panel.target_hint.text == _tr("P9_RITUAL_WAIT_HALL") and session.incense == funds and not caster.brain.channel.active, "Click on an unentered ghost explains legal range without charging")
	camera.set_left(7680)
	var ritual_view := _view()
	await _mouse_world(target.aim_point(), true)
	check(caster.brain.channel.active and session.incense < funds and _view() == ritual_view, "Click on an entered legal ghost starts the real paid channel with unchanged viewport")
	var position_before: Vector2 = caster.position
	var hp_before: float = skirmisher.hp
	await _key(KEY_SPACE)
	_tick(0.5)
	await _key(KEY_SPACE)
	check(caster.brain.channel.active and caster.position == position_before and caster.brain.channel.elapsed > 0, "Reading stays at the original cover and advances on continue")
	check(skirmisher.hp < hp_before, "The other guard continues real combat during reading")
	check(panel.activity_plate.visible and panel.channel_progress.value > 0 and panel.activity.text.contains("可打断"), "A visible progress strip reports both elapsed time and interruptibility")
	await _shot("16-read-progress")
	sim.deal_damage(target, caster, "fixture", 1.0)
	await process_frame
	await process_frame
	check(not caster.brain.channel.active and panel.warnings.text.contains("中断") and not panel.activity_plate.visible, "Damage stops the channel and produces a corner warning")

	world.get_node("door_outer").durability = 19.0
	session.names = 2
	session.remaining = 23
	var upper := _ghost(98 * 80)
	upper.position.y = world.floor_y(1)
	upper.floor_id = 1
	sim._update_units()
	session._update_warnings()
	await process_frame
	await process_frame
	check(hud.door_heading.text.contains("门将破") and hud.register_status.text.contains("告急") and hud.upper_status.text.contains("来犯") and hud.goal_label.text.contains("天亮将至"), "Danger, book, tide above and dawn read in text at the same time")
	check(panel.warning_plate.visible and panel.warning_plate.position.x < 30 and panel.warning_plate.size.x < 540 and panel.warning_plate.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Warnings are nonmodal and confined to a corner")
	await _shot("23-pressure")

func _group_fixture() -> void:
	camera.set_left(7000)
	var funds: float = session.incense
	var positions: Array = sim.humans.map(func(unit): return unit.position)
	var entries: int = session.ledger.size()
	var a := _ghost(camera.left() + 310)
	var b := _ghost(camera.left() + 375)
	sim._update_units()
	await _drag_group(a, b)
	check(panel.current_panel == "group" and panel.selected_group.size() >= 2 and not panel.buttons.has("group_mutate"), "Controlled-shouxiang drag only opens multi-unit inspection")
	check(session.incense == funds and session.ledger.size() == entries and positions == sim.humans.map(func(unit): return unit.position), "Box selection never issues orders, moves or charges")
	_start("duoming")
	session.configure_roster("p9-duoming-fixture")
	session.incense = 13
	sim.clear_targets()
	var ghost_a := _ghost(camera.left() + 260)
	var ghost_b := _ghost(camera.left() + 342)
	sim._update_units()
	await process_frame
	check(hud.command_bar.get_child_count() == 3 and _text(hud.command_bar).contains("融契"), "Duoming toolbar shows mutation, fusion and reinforcement")
	await _drag_group(ghost_a, ghost_b)
	check(panel.selected_group.size() == 2 and panel.buttons.group_mutate.visible, "Duoming drag exposes batch mutation without movement controls")
	await _click(panel.buttons.group_mutate)
	check(panel.current_panel == "batch" and panel.buttons.batch_V01.text.contains("1 / 2"), "Batch preview counts the one affordable ghost in an eligible pair")
	await _shot("15-batch-mutation")
	await _click(panel.buttons.batch_V01)
	check((ghost_a.unit_id == "G11" or ghost_b.unit_id == "G11") and (ghost_a.unit_id == "G01" or ghost_b.unit_id == "G01") and is_equal_approx(session.incense, 5.0), "Batch mutates and charges only the valid affordable member")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(is_instance_valid(panel.selected) and panel.selected.side == "yegui" and panel.unit_panel.visible, "Controller unit cycle starts with the player's seat and shows its card")

func _start(seat: String) -> void:
	panel.close_panel()
	session.enter_debug()
	panel.start_battle(seat)
	clock.set_paused(true)
	clock.set_speed(1.0)
	camera.set_left(6080)

func _tr(key: String) -> String:
	return TranslationServer.translate(key)

func _view() -> Array:
	return [camera.world_rect(), camera.zoom, hud.minimap.camera_rect()]

func _tick(seconds: float) -> void:
	for index in ceili(seconds * 60.0):
		sim.advance(1.0 / 60.0)

func _human(id: String) -> Node2D:
	for actor in sim.humans:
		if actor.unit_id == id:
			return actor
	return null

func _ghost(x: float) -> Node2D:
	var ghost: Node2D = sim.tide.spawn("G01", 0, x)
	ghost.motion_enabled = false
	ghost.attacks_enabled = false
	return ghost

func _drag_group(first: Node2D, second: Node2D) -> void:
	var transform := root.get_canvas_transform()
	var origin := transform * (first.position - Vector2(33, 74))
	var finish := transform * (second.position + Vector2(33, -12))
	await _mouse(origin, MOUSE_BUTTON_LEFT, true)
	await _motion(finish)
	await _mouse(finish, MOUSE_BUTTON_LEFT, false)
	await process_frame

func _mouse_world(point: Vector2, click_it: bool) -> void:
	var screen := root.get_canvas_transform() * point
	await _motion(screen)
	if click_it:
		await _mouse(screen, MOUSE_BUTTON_LEFT, true)
		await _mouse(screen, MOUSE_BUTTON_LEFT, false)

func _motion(screen: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = screen
	root.push_input(event, true)
	await process_frame

func _mouse(screen: Vector2, button: MouseButton, state: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.button_index = button
	event.pressed = state
	root.push_input(event, true)
	await process_frame

func _click(control: BaseButton) -> void:
	if not is_instance_valid(control) or not control.is_visible_in_tree() or control.disabled:
		check(false, "Expected an enabled on-screen button")
		return
	var center := control.get_global_rect().get_center()
	await _motion(center)
	await _mouse(center, MOUSE_BUTTON_LEFT, true)
	await _mouse(center, MOUSE_BUTTON_LEFT, false)

func _key(code: Key) -> void:
	for state in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = state
		root.push_input(event, true)
		await process_frame

func _pad(code: JoyButton) -> void:
	for state in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = code
		event.pressed = state
		root.push_input(event, true)
		await process_frame

func _text(node: Node) -> String:
	var result := ""
	if node is Label or node is BaseButton:
		result += node.text + "\n"
	for child in node.get_children():
		result += _text(child)
	return result

func check(passed: bool, label: String) -> void:
	rows.append({"passed":passed, "check":label})
	if not passed:
		failures += 1
	print(("%s %s" % ["PASS" if passed else "FAIL", label]))

func _shot(label: String) -> void:
	if not native:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var pose := root.get_texture().get_image()
	var filename := label + ".png"
	var path := output + "/" + filename
	check(pose != null and pose.save_png(path) == OK, "Native viewport screenshot " + label)
	screenshots.append({"file":filename, "width":pose.get_width(), "height":pose.get_height(), "sha256":FileAccess.get_sha256(path)})
