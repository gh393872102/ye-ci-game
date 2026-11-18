extends SceneTree
## Exercise the production title, mouse/keyboard, night save and observer on an isolated native desktop.
var snapshot_type: Script
var record_type: Script
var output := ""
var rows: Array = []
var shots: Array = []

func _initialize() -> void:
	run.call_deferred()

func frames(count := 3) -> void:
	for i in count: await process_frame

func check(ok: bool, label: String) -> bool:
	rows.append({"passed":ok,"check":label})
	print(("PASS " if ok else "FAIL ")+label)
	return ok

func click(button: Control) -> void:
	for down in [true,false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = button.get_global_rect().get_center()
		root.push_input(ev,true)
		await frames(2)

func key(window: Viewport, code: Key) -> void:
	for down in [true,false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		if window is PopupMenu:
			ev.window_id = window.get_window_id()
			Input.parse_input_event(ev)
		else:
			window.push_input(ev,true)
		await frames(1)

func choose(picker: OptionButton, index: int) -> bool:
	await click(picker)
	var popup := picker.get_popup()
	if not check(popup.visible,"Mouse opens "+picker.name): return false
	for i in picker.item_count+1:
		if popup.get_focused_item()==index: break
		await key(popup,KEY_DOWN)
	if not check(popup.get_focused_item()==index,"Keyboard reaches dropdown row "+str(index)): return false
	await key(popup,KEY_ENTER)
	await frames()
	return check(picker.selected==index,"Keyboard selects item "+str(index)+" in "+picker.name)

func shot(id: String) -> void:
	await frames()
	RenderingServer.force_draw(true)
	var img := root.get_texture().get_image()
	var path := output.path_join(id+".png")
	if check(img!=null and not img.is_empty() and img.save_png(path)==OK,"Native frame "+id):
		shots.append({"file":path.get_file(),"sha256":FileAccess.get_sha256(path),"width":img.get_width(),"height":img.get_height()})

func finish() -> void:
	var fails := rows.filter(func(r): return not r.passed).size()
	FileAccess.open(output.path_join("p10-host.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":rows.size(),"failures":fails,"results":rows,"screenshots":shots,"input":"Godot native viewport keyboard/mouse events; isolated local state"}, "\t")+"\n")
	quit(0 if fails==0 else 1)

func run() -> void:
	await frames()
	snapshot_type = load("res://src/night/BattleSnapshot.gd")
	record_type = load("res://src/replay/BattleRecord.gd")
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): quit(2); return
	output = args[0]
	if not check(root.get_node("Data").codex_store.path==output+"/state/codex.json" and DisplayServer.get_name()!="headless","Isolated native project"):
		finish();return
	root.size = Vector2i(1280,720)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames(14)
	var host := current_scene
	if not check(is_instance_valid(host) and host.get("shell")!=null,"Official Boot reaches title"):
		finish();return
	var shell: Node = host.shell
	await click(shell.title_buttons.start)
	if not await choose(shell.night_kind,2): finish();return
	if not await choose(shell.ritual_choice,6): finish();return
	await click(shell.modifier_boxes.N02)
	await shot("01-fierce-setup")
	await click(shell.title_buttons.shouxiang)
	if not check(host.run.state.get("ritual")=="R06" and host.run.state.kind=="fierce" and host.run.state.nameless_modifiers==["N02"],"Title starts fierce bridge night with cracked side gate"): finish();return
	var first: Dictionary = host.run.available_nodes()[0]
	check("C07" in first.chunk_ids and "C02" in first.chunk_ids,"Mandatory bridge and side gate in actual first node")
	await shot("02-night-route")
	await click(host.panel.buttons["node_"+str(first.id)])
	if not check(is_instance_valid(host.combat),"Real first map node enters combat"): finish();return
	var world: Node = host.combat.get_node("ReferenceMap")
	var session: Node = host.combat.get_node("Session")
	check(session.ritual.id=="R06" and world.has_node("stone_bridge") and world.has_node("door_side"),"Runtime bridge, side gate and ritual exist")
	await key(root,KEY_ESCAPE)
	if not check(shell.pause.visible,"Keyboard opens pause over live fight"): finish();return
	var before: Dictionary = snapshot_type.capture(host.combat)
	var route: Array = host.run.config.nodes.duplicate(true)
	await click(shell.pause_buttons.exit)
	if not check(shell.title_home.visible,"Mouse saves and returns to title"): finish();return
	await click(shell.title_buttons.continue_run)
	if not check(is_instance_valid(host.combat) and not shell.title.visible,"Continue restores the saved battle"): finish();return
	var after: Dictionary = snapshot_type.capture(host.combat)
	check(record_type.digest(before)==record_type.digest(after),"Battle snapshot including marks, stage, map, actors and wallet survives disk roundtrip")
	check(record_type.digest(route)==record_type.digest(host.run.config.nodes),"Restored seed reconstructs the whole night route")
	await key(root,KEY_ESCAPE)
	await click(shell.pause_buttons.exit)
	await click(shell.title_buttons.observer)
	await frames(6)
	host = current_scene
	if not check(host.has_method("start_observation"),"Title observer opens battle configuration"): finish();return
	var panel: Control = host.panel
	check(panel.human_counts.size()==36 and panel.ghost_counts.size()==32 and panel.ritual.item_count==12,"Observer offers 32 named humans, 4 troops, 32 ghosts and 12 rituals")
	if not await choose(panel.ferocity,2): finish();return
	# Exercise a resource control through its actual SpinBox editor.
	var amount: LineEdit = panel.incense_shouxiang.get_line_edit()
	await click(amount)
	amount.select_all()
	var entry := InputEventKey.new()
	entry.keycode = KEY_3
	entry.unicode = "3".unicode_at(0)
	entry.pressed = true
	root.push_input(entry,true)
	await frames()
	await key(root,KEY_ENTER)
	if not check(is_equal_approx(panel.incense_shouxiang.value,3.0),"Keyboard edits observer incense"): finish();return
	if not await choose(panel.ritual,9): finish();return
	await click(panel.buttons.encounter_setup)
	var editor: Control = panel.encounter_setup
	check(editor.is_ancestor_of(root.gui_get_focus_owner()),"Editor takes keyboard focus from observer setup")
	for tick in 18:
		await key(root,KEY_TAB)
		if not editor.is_ancestor_of(root.gui_get_focus_owner()):
			check(false,"Tab escaped from encounter editor")
			finish();return
	check(true,"Tab traversal stays within the open editor")
	if not await choose(editor.boss_picker,2): finish();return
	await key(root,KEY_ESCAPE)
	check(not editor.visible and root.gui_get_focus_owner()==panel.buttons.encounter_setup,"Escape closes editor and restores focus")
	if not await choose(panel.ritual,11): finish();return
	check(editor.boss_picker.disabled and editor.boss_picker.get_selected_metadata()=="B03","Nameless infiltration requires B03")
	if not await choose(panel.ritual,9): finish();return
	check(not editor.boss_picker.disabled and editor.boss_picker.get_selected_metadata()=="B02","Switching back restores the chosen B02 stage")
	await click(panel.buttons.encounter_setup)
	await click(editor.chunk_boxes.C05)
	check("post_water_sluice" in panel.human_post_ids.T01,"Water alley adds its legal post to initial formation")
	await click(editor.modifier_boxes.N01)
	await shot("03-observer-setup")
	await click(editor.get_node("apply"))
	await click(panel.buttons.start_watch)
	if not check(is_instance_valid(host.combat),"Mouse starts configured observation"): finish();return
	session = host.combat.get_node("Session")
	var cfg: Dictionary = host.controller.config
	check(session.ritual.id=="R10" and cfg.boss_id=="B02" and cfg.nameless_modifiers==["N01"] and "C05" in cfg.chunk_ids,"Observer runs selected ritual, stage, water alley and modifier")
	check(host.combat.get_node("BattleCamera").zoom==Vector2.ONE and session.roster.enabled,"Shared battle camera and P8 roster engine")
	check(cfg.incense.shouxiang==3 and cfg.ferocity=="fierce" and host.controller.brains.shouxiang!=null,"Observer starts chosen resources, AI ferocity and configured roster in the shared simulator")
	await frames(30)
	await shot("04-observer-battle")
	await click(panel.buttons.archive)
	if not check(host.controller.receipt.get("ok",false),"Archive the actual configured observer battle"): finish();return
	var record_id: String = host.controller.receipt.get("id","")
	host.start_replay(record_id)
	await frames(120)
	check(host.is_replay and host.controller.playback.verified,"Disk replay verifies event/result digest of selected stage")
	finish()
