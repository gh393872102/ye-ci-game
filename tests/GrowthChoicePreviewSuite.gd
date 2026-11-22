extends SceneTree
## Run with godot --headless --script tests/GrowthChoicePreviewSuite.gd.
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print(("PASS " if value else "FAIL ") + message)

func pick(panel: CanvasLayer, item: String) -> void:
	var index: int = panel.item_ids.find(item)
	panel.item_picker.select(index)
	panel.item_picker.item_selected.emit(index)

func click(button: Button) -> void:
	await process_frame
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func run() -> void:
	var lab: Node = load("res://scenes/modes/GrowthLab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	lab.buttons.build_chaodu.pressed.emit()
	var session: Node = lab.combat.get_node("Session")
	var decisions: CanvasLayer = lab.combat.get_node("Decisions")
	var unit: Node2D = lab.combat.get_node("Simulation").humans[0]
	decisions.select_unit(unit)
	decisions.open_growth()
	var panel: CanvasLayer = decisions.growth_panel
	var data := root.get_node("Data")
	# Only this process gets nonzero fixture costs. Shipped prices stay intact.
	var items: Dictionary = data.growth_rules.items
	items.I17.remove_cost = 3
	items.I01.equip_cost = 4
	session.growth.state.inventory.I01 = 1
	panel.render()
	pick(panel, "I17")
	check(panel.description.text.contains("当前槽位为空"), "Empty-slot comparison")
	await click(panel.buttons.equip_item)
	check(panel.selected_item.is_empty() and panel.buttons.equip_item.disabled, "An equip click cannot silently arm the next inventory item")
	if unit.role=="ritual":
		var before: float = session.incense
		await click(panel.buttons.inspect_ritual_targets)
		check(decisions.current_panel=="ritual" and decisions.caster==unit and session.incense==before,"Equipment leads to the wearer's target preview without issuing a paid order")
		decisions.select_unit(unit)
		decisions.open_growth()
	session.incense = 6
	pick(panel, "I01")
	check(panel.description.text.contains(items.I17.name) and panel.description.text.contains(items.I01.description), "Old and prospective effects both visible")
	check(panel.buttons.equip_item.disabled and panel.description.text.contains("本次合计 7"), "Insufficient funds at six for combined three-plus-four fee")
	session.incense = 7
	panel.render()
	check(not panel.buttons.equip_item.disabled, "Exact funds allow a replacement")
	await click(panel.buttons.equip_item)
	check(unit.growth.slots.censer == "I01" and session.incense == 0 and session.growth.state.inventory.I17 == 1, "Execution matches quoted price and returns previous item")
	session.growth.state.inventory.I01 = 1
	panel.render()
	pick(panel, "I01")
	check(panel.buttons.equip_item.disabled and panel.description.text.contains(panel.tr("P7_ALREADY_EQUIPPED")), "Duplicate purchase explained")
	# Explicit held slots and stock isolate UI selection from ordinary reward randomness.
	session.growth.state.defense_objective = "hold_register"
	session.incense = 20
	session.growth.state.inventory.I08 = 1
	session.growth.state.inventory.Y11 = 0
	panel.render()
	await click(panel.buttons.inspect_register_item)
	check(panel.selected_item=="I08" and unit.growth.slots.censer=="I01" and session.growth.state.inventory.I08==1,"Inspecting a pair item previews replacement without changing ownership")
	await click(panel.buttons.equip_item)
	check(not panel.buttons.has("inspect_register_item") and panel.content.find_children("*","Label",true,false).any(func(l):return "库存无余件" in l.text),"Missing partner is visible and unavailable stock cannot be equipped")
	session.growth.state.inventory.Y01 = 1
	panel.slot_picker.item_selected.emit(1)
	pick(panel,"Y01")
	await click(panel.buttons.equip_item)
	session.growth.state.inventory.Y11 = 1
	panel.render()
	await click(panel.buttons.inspect_register_item)
	check(panel.selected_item=="Y11" and panel.selected_slot==2,"Existing art stays in slot one when a free art slot exists")
	await click(panel.buttons.equip_item)
	check(unit.growth.slots.arts==["Y01","Y11"] and not panel.buttons.has("inspect_register_item"),"Both arts coexist after confirmation")
	unit.growth.charges.I08 = 1
	panel.render()
	check(panel.content.find_children("*","Label",true,false).any(func(l):return "已耗尽" in l.text),"Shared spent paper charge is shown on reinspection")
	session.growth.state.defense_objective = ""
	panel.render()
	check(not panel.content.find_children("*","Label",true,false).any(func(l):return "守册抵命" in l.text),"Other battle objectives omit the register condition")
	lab.show_menu()
	lab.buttons.build_pomen.pressed.emit()
	decisions = lab.combat.get_node("Decisions")
	session = lab.combat.get_node("Session")
	var ghost: Node2D = lab.combat.get_node("Simulation").tide.spawn("G01", 0, 0.0)
	decisions.select_unit(ghost)
	decisions.open_growth("forms")
	panel = decisions.growth_panel
	var regions := []
	for id in ["V01", "V02", "V03"]:
		var result_id: String = data.growth_rules.mutations[id].result_id
		var preview := panel.content.find_child("preview_" + id, true, false) as TextureRect
		var texture := preview.texture as AtlasTexture
		check(texture.atlas != null and texture.region.size == Vector2(144, 84) and texture.region not in regions, "Distinct combat sprite for " + result_id)
		regions.append(texture.region)
		var role: String = data.get_unit(result_id)["定位"]
		check(preview.get_parent().find_children("*", "Label", true, false).any(func(label): return label.text.contains(role)), "Role visible for " + id)
	var poses := panel.content.find_child("pose_picker", true, false) as OptionButton
	for pose in [1, 2]:
		poses.select(pose)
		poses.item_selected.emit(pose)
		for index in 3:
			var card := panel.content.find_child("preview_V0%d" % (index + 1), true, false) as TextureRect
			var region: Rect2 = card.texture.region
			check(region.position == regions[index].position + Vector2(0, pose * 84), "Pose %d changes the correct card %d" % [pose, index])
	check(ghost.unit_id == "G01", "Inspecting poses keeps original unit")
	session.incense = 8
	panel.render()
	check(not panel.buttons.mutate_V01.disabled and panel.buttons.mutate_V02.disabled and panel.buttons.mutate_V03.disabled, "Eight incense only enables the affordable form")
	await click(panel.buttons.mutate_V01)
	check(ghost.unit_id == "G11" and session.incense == 0, "Command produces the pictured form at the stated price")
	print("GROWTH CHOICE RESULT: %d checks, %d failures" % [checks, failures])
	lab._dispose()
	lab.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	quit(failures)
