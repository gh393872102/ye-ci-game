extends SceneTree
var lab: Node
var checks := 0
var failures := 0
var results: Array[Dictionary] = []
const OUTPUT = "res://docs/phase-reports/p7-ui-smoke-shots/"
func _initialize() -> void: _run.call_deferred()
func check(value: bool,text: String) -> void:
	checks += 1
	print(('PASS ' if value else 'FAIL ') + text)
	results.append({"ok":value,"check":text})
	if not value: failures += 1
func shot(id: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + id + '.png'))
func click(button: Button) -> void:
	await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame
func choose_slot(panel: CanvasLayer,index: int) -> void:
	panel.slot_picker.select(index)
	panel.slot_picker.item_selected.emit(index)
	await process_frame
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1920,1080)
	lab = load('res://scenes/modes/GrowthLab.tscn').instantiate()
	root.add_child(lab)
	await process_frame
	await shot('lab-1080')
	root.size = Vector2i(1280,720)
	await shot('lab-720')
	await click(lab.buttons.build_chaodu)
	check(is_instance_valid(lab.combat),'Actual trial button starts shared battle')
	var decisions: CanvasLayer = lab.combat.get_node('Decisions')
	var human: Node2D = lab.combat.get_node('Simulation').humans[0]
	decisions.select_unit(human)
	await click(decisions.buttons.card_growth)
	var panel: CanvasLayer = decisions.growth_panel
	await shot('four-slots-720')
	check(panel.surface.visible and panel.item_ids.has('I17') and not panel.item_ids.has('I10'),'Equipment menu lists authored owned inventory only')
	panel.item_picker.select(panel.item_ids.find('I17'))
	panel.item_picker.item_selected.emit(panel.item_ids.find('I17'))
	await click(panel.buttons.equip_item)
	check(human.growth.slots.censer == 'I17' and decisions.details.text.contains('册底针'),'Actual equip button immediately updates selected unit and full card')
	await choose_slot(panel,1)
	panel.item_picker.select(panel.item_ids.find('Y01'))
	panel.item_picker.item_selected.emit(panel.item_ids.find('Y01'))
	await click(panel.buttons.equip_item)
	await choose_slot(panel,2)
	panel.item_picker.select(panel.item_ids.find('Y03'))
	panel.item_picker.item_selected.emit(panel.item_ids.find('Y03'))
	await click(panel.buttons.equip_item)
	await choose_slot(panel,3)
	panel.item_picker.select(panel.item_ids.find('N01'))
	panel.item_picker.item_selected.emit(panel.item_ids.find('N01'))
	await click(panel.buttons.equip_item)
	check(human.growth.slots.arts[0] == 'Y01' and human.growth.slots.arts[1] == 'Y03' and human.growth.slots.nameplate == 'N01','Two art slots and nameplate fill independently through actual buttons')
	await shot('four-slots-equipped-720')
	root.size = Vector2i(1920,1080)
	await shot('four-slots-equipped-1080')
	root.size = Vector2i(1280,720)
	await click(panel.buttons.unequip_item)
	check(human.growth.slots.nameplate == '' and lab.combat.get_node('Session').growth.state.inventory.N01 == 1,'Unequip returns the selected slot item to current inventory')
	panel.close()
	decisions.open_upgrade()
	check(not decisions.buttons.has('card_mutate'),'Human upgrade retains upgrade preview without mutation as a main command')
	await shot('upgrade-preview-720')
	lab.show_menu()
	await click(lab.buttons.build_pomen)
	decisions = lab.combat.get_node('Decisions')
	var ghost: Node2D = lab.combat.get_node('Simulation').targets[0]
	decisions.select_unit(ghost)
	decisions.open_growth('fusions')
	await shot('fusion-720')
	check(decisions.growth_panel.recipe_ids.has('F01') and decisions.growth_panel.recipe_ids.has('F03'),'Fusion recipe selector exposes explicit named recipes')
	lab.show_menu()
	await click(lab.buttons.build_wuce)
	decisions = lab.combat.get_node('Decisions')
	human = lab.combat.get_node('Simulation').humans[0]
	decisions.select_unit(human)
	decisions.open_growth('vocation')
	await shot('borrow-vocation-720')
	check(decisions.growth_panel.buttons.has('borrow_god'),'Human vocation panel exposes paid risk-aware borrowing')
	var session: Node = lab.combat.get_node("Session")
	var before := JSON.stringify({"state":session.growth.state,"unit":human.growth})
	decisions.observation_mode = true
	decisions.replay_read_only = true
	decisions.open_growth()
	check(decisions.growth_panel.buttons.equip_item.disabled and decisions.growth_panel.buttons.unequip_item.disabled,"Replay full growth card keeps both equipment commands disabled")
	decisions.growth_panel._send("equip_item",{"unit_id":human.instance_id,"item_id":"I17"})
	check(JSON.stringify({"state":session.growth.state,"unit":human.growth}) == before,"Opening and invoking readonly growth panel does not mutate inventory or unit")
	await shot("readonly-720")
	decisions.observation_mode = false
	decisions.replay_read_only = false
	lab.show_menu()
	root.remove_child(lab)
	lab.queue_free()
	var night: Node = load("res://scenes/night/Night.tscn").instantiate()
	root.add_child(night)
	await process_frame
	night.save_path = "user://p7_ui_smoke_night.json"
	await shot("night-entries-720")
	await click(night.panel.buttons.growth_shouxiang)
	check(night.run.state.has("growth") and night.run.state.growth.inventory.size() > 0 and night.run.state.growth.inventory.size() < 48 and night.run.state.phase == "map","Normal growth-night entrance creates a genuine limited inventory")
	var curve_visible := false
	for label in night.panel.find_children("*","Label",true,false):
		if label.text.contains("0.24") and label.text.contains("+12"): curve_visible = true
	check(curve_visible,"Growth night map publicly shows the actual 0.24 regen and 12 victory incense")
	await shot("normal-map-720")
	await click(night.panel.buttons["node_"+str(night.run.available_nodes()[0].id)])
	check(is_instance_valid(night.combat) and night.combat.get_node("Session").growth.enabled,"Normal map node enters the shared battle with growth enabled")
	var normal: CanvasLayer = night.combat.get_node("Decisions")
	normal.select_unit(night.combat.get_node("Simulation").humans[0])
	normal.open_growth()
	check(not normal.growth_panel.item_ids.is_empty() and normal.growth_panel.item_ids.all(func(id): return int(night.combat.get_node("Session").growth.state.inventory.get(id,0)) > 0),"Normal battle growth picker never creates unowned items")
	await shot("normal-night-720")
	var report := FileAccess.open("res://docs/phase-reports/p7-ui-smoke-results.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"suite":"P7 authored trial and normal-night native UI smoke","passed":checks-failures,"failed":failures,"checks":results},"\t")+"\n")
	night._dispose_battle()
	if FileAccess.file_exists(night.save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(night.save_path))
	quit(failures)
