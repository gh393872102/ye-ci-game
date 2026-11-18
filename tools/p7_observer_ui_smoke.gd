extends SceneTree
var host
var checks:=0
var failures:=0
var results: Array[Dictionary] = []
const OUTPUT = "res://docs/phase-reports/p7-ui-smoke-shots/observer-"
func _initialize():call_deferred("run")
func check(ok,label):
	checks+=1;print(("PASS " if ok else "FAIL ")+label)
	results.append({"label":label,"passed":bool(ok)})
	if not ok:failures+=1
func click(button):
	await process_frame
	for pressed in [true,false]:
		var ev=InputEventMouseButton.new();ev.button_index=MOUSE_BUTTON_LEFT;ev.position=button.get_global_rect().get_center();ev.pressed=pressed;root.push_input(ev,true);await process_frame
func shot(id):
	await process_frame;await process_frame;RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+id+".png"))
func actor(id):
	for unit in host.combat.get_node("Simulation").humans+host.combat.get_node("Simulation").targets:
		if unit.unit_id==id:return unit
	return null
func run():
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/phase-reports/p7-ui-smoke-shots"))
	host=load("res://scenes/modes/Observatory.tscn").instantiate();root.add_child(host)
	await process_frame
	load("res://src/replay/ReplayArchive.gd").directory="/tmp/ye-ci-p7-observer-ui-archives"
	var panel=host.panel
	check(not panel.growth_enabled.button_pressed and panel.growth_template.disabled and not panel.make_config("watch","").growth_enabled,"Growth presets default off and picker is disabled")
	await click(panel.growth_enabled)
	check(panel.growth_enabled.button_pressed and not panel.growth_template.disabled and panel.make_config("watch","").growth_template=="ritual_break","Real enable checkbox emits ritual_break config")
	root.size=Vector2i(1920,1080);await shot("setup-1080")
	root.size=Vector2i(1280,720);await shot("setup-720")
	await click(panel.buttons.start_watch)
	check(is_instance_valid(host.combat),"Real watch button starts the configured growth battle")
	if not is_instance_valid(host.combat):
		quit(1)
		return
	var ClockNode=root.get_node("Clock");ClockNode.set_paused(true)
	var wan=actor("H01")
	check(wan.growth.slots.censer=="I17" and wan.growth.slots.arts==["Y01","Y03"] and wan.growth.slots.nameplate=="N05","Configured first H01 receives actual four-slot preset")
	var decision=host.combat.get_node("Decisions")
	decision.select_unit(wan);await click(decision.buttons.card_growth)
	check(decision.growth_panel.buttons.equip_item.disabled and decision.growth_panel.buttons.unequip_item.disabled,"Watch preset remains readonly through complete unit growth card")
	await shot("watch-readonly-720")
	host.return_setup();await process_frame;await process_frame
	panel.growth_template.select(1);panel.growth_template.item_selected.emit(1)
	check(panel.make_config("duel","shouxiang").growth_template=="gate_beam","Second preset is serialized as gate_beam")
	await click(panel.buttons.start_duel_shouxiang)
	check(is_instance_valid(host.combat),"Real duel button starts the second growth template")
	if not is_instance_valid(host.combat):
		quit(1)
		return
	ClockNode.set_paused(true)
	var shoulder=actor("H09")
	check(shoulder.growth.slots.censer=="I01" and actor("H17").growth.slots.censer=="I03","Gate preset actually equips the corresponding configured people")
	decision=host.combat.get_node("Decisions");decision.select_unit(shoulder);await click(decision.buttons.card_growth)
	check(not decision.growth_panel.buttons.unequip_item.disabled,"Controlled duel seat can change its own existing equipment")
	await click(decision.growth_panel.buttons.unequip_item)
	check(shoulder.growth.slots.censer=="" and int(host.combat.get_node("Session").growth.state.inventory.get("I01",0))==1,"Real duel unequip returns the owned preset item to inventory")
	await shot("duel-equipment-720")
	host.return_setup()
	var report = FileAccess.open("res://docs/phase-reports/p7-observer-ui-results.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"suite":"P7ObserverUI","scope":"Native real controls and preset equipment; partial battles, not full-night evidence","checks":checks,"failed":failures,"results":results},"\t")+"\n")
	print("P7ObserverUI RESULT: %d checks, %d failures"%[checks,failures]);quit(failures)
