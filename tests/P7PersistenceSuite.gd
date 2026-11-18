extends SceneTree
## Real commands + disk checkpoints + exact replay; independent of authored effect probes.
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var prefix := "p7-persistence"
var Run
var Bridge
var Snapshot
var Record
var Archive
var Player
var ClockNode
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-prefix="): prefix=arg.trim_prefix("--report-prefix=")
	call_deferred("run")
func check(value: bool,label: String) -> void:
	checks += 1
	rows.append({"label":label,"passed":value})
	print(("PASS: " if value else "FAIL: ")+label)
	if not value: failures.append(label)
func scene():
	var node=load("res://scenes/combat/Combat.tscn").instantiate()
	root.add_child(node)
	node.get_node("Simulation").set_physics_process(false)
	return node
func actor(combat,id:String):
	for unit in combat.get_node("Simulation").humans+combat.get_node("Simulation").targets:
		if unit.unit_id==id:return unit
	return null
func step(combat,count:int) -> void:
	for index in count:combat.get_node("Simulation").advance(1.0/60.0)
func repair_affordability() -> void:
	for budget in [5.0,6.0,4.0]:
		var combat=scene()
		var session=combat.get_node("Session")
		session.start_battle("shouxiang")
		session.configure_growth("P7-repair-affordability",{})
		ClockNode.set_paused(true)
		var sim=combat.get_node("Simulation")
		for unit in sim.humans:unit.free()
		sim.humans.clear()
		var nearer=sim.spawn_human("H09","post_gate_inner")
		var discounted=sim.spawn_human("H25","post_inner_gate")
		var door=sim.world.get_node("door_outer")
		door.set_durability(500)
		session.incense=budget
		var result=session.execute_for("shouxiang","repair",{"door_id":"door_outer"},"player")
		if budget==5.0:
			check(result.ok and result.unit==discounted,"Repair selects a reachable discounted worker when the nearer ordinary worker is unaffordable")
			check(is_equal_approx(session.incense,0.2) and session.repair_jobs.size()==1 and discounted.brain.repair_door==door,"Discounted repair charges 4.8 and dispatches the actual affordable worker")
		elif budget==6.0:
			check(result.ok and result.unit==nearer and is_zero_approx(session.incense),"Repair still selects the nearest worker when both are affordable")
		else:
			check(not result.ok and result.reason=="P4_NO_INCENSE" and session.incense==budget and session.repair_jobs.is_empty(),"Repair rejects atomically when all reachable workers are unaffordable")
		combat.free()
func ritual_purchase_boundary() -> void:
	var combat=scene()
	var session=combat.get_node("Session")
	session.start_battle("shouxiang")
	session.configure_growth("P7-ritual-replacement",{})
	var sim=combat.get_node("Simulation")
	var priest=actor(combat,"H01")
	priest.dead=true
	ClockNode.set_paused(true)
	session.incense=9.48
	session.after_step(1.0/60.0)
	check(session.result.is_empty() and not session._ritual_line_broken(),"Growth night does not lose at 9.48 incense when an eight-incense priest can still be purchased")
	var bought=session.execute_for("shouxiang","purchase",{"id":"H03"},"player")
	check(bought.ok and is_equal_approx(session.incense,1.48) and not session._ritual_line_broken(),"A paid H03 reservation keeps the priest line recoverable before deployment")
	var deployed=session.execute_for("shouxiang","deploy_at",{"post_id":"post_table_hall"},"player")
	check(deployed.ok and not session._ritual_line_broken(),"Actual legal H03 deployment restores a living priest without resurrecting H01")
	deployed.unit.dead=true
	session.incense=7.9
	session.after_step(1.0/60.0)
	check(session.result.get("reason")=="P4_END_RITUAL_LINE_BROKEN","Growth night still loses when no priest is alive and all priest purchases are unaffordable")
	session.result.clear()
	session.dual_enabled=true
	session.player_seat="duoming"
	session.wallets={"shouxiang":9.48,"duoming":0.0}
	check(not session._ritual_line_broken(),"Dual-mode recovery reads the defending wallet even while the player controls attackers")
	session.wallets={"shouxiang":7.9,"duoming":60.0}
	check(session._ritual_line_broken(),"An attacker wallet cannot pay for defending priests")
	session.dual_enabled=false
	session.growth.enabled=false
	session.incense=9.48
	check(session._ritual_line_broken(),"Legacy mode retains the original twelve-incense H01 recovery threshold")
	combat.free()
func run() -> void:
	await process_frame
	Run=load("res://src/night/NightRun.gd")
	Bridge=load("res://src/night/NightBattleBridge.gd")
	Snapshot=load("res://src/night/BattleSnapshot.gd")
	Record=load("res://src/replay/BattleRecord.gd")
	Archive=load("res://src/replay/ReplayArchive.gd")
	Player=load("res://src/replay/ReplayPlayer.gd")
	ClockNode=root.get_node("Clock")
	Archive.directory="/tmp/ye-ci-p7-persistence-archives"
	check(root.get_node("Data").errors.is_empty(),"Current source data passes startup validation")
	repair_affordability()
	ritual_purchase_boundary()
	for mode in ["shouxiang","duoming"]:
		var n=Run.new()
		check(n.new_growth_run(mode,"P7-persistence-"+mode).ok,"Growth night starts for "+mode)
		check(n._valid_state(n.state),"New growth night state validates for "+mode)
		check(n.config.battle_profiles.entry.victory_incense==12 and n.config.battle_profiles.boss.victory_incense==12,"Growth-only victory curve is applied to both early and boss profiles for "+mode)
		var item_count=0
		for card in n.config.rewards.values():
			if card.effect.kind=="growth_item" and not card.effect.id.begins_with("J"):item_count+=1
		check(item_count==48,"All 48 slot items are reachable in this night's reward/market pool")
		check(n.save("/tmp/ye-ci-p7-"+mode+"-before.json").ok,"Fresh night writes a real disk save")
		var loaded=Run.new()
		check(loaded.load_save("/tmp/ye-ci-p7-"+mode+"-before.json").ok and Record.digest(loaded.state)==Record.digest(n.state),"Fresh process model loads the same inventory and rule pool")
	var night=Run.new()
	night.new_growth_run("shouxiang","P7-mixed-clock-disk")
	night.choose_node("n01")
	var first=scene()
	var bridge=Bridge.new()
	check(bridge.start(first,night).ok,"Real growth night battle starts on shared simulator")
	var session=first.get_node("Session")
	check(is_equal_approx(session.rules.incense_regen,0.24),"Ordinary growth battle uses the declared 0.24 incense per second")
	ClockNode.set_paused(true)
	var wan=actor(first,"H01")
	var shoulder=actor(first,"H09")
	check(session.execute_for("shouxiang","equip_item",{"unit_id":wan.instance_id,"item_id":"I17"},"player").ok,"Stocked I17 is equipped through recorded player command")
	check(session.execute_for("shouxiang","equip_item",{"unit_id":wan.instance_id,"item_id":"Y01","slot_index":0},"player").ok,"Stocked Y01 occupies exactly one art slot")
	check(session.execute_for("shouxiang","upgrade",{"unit_id":shoulder.instance_id},"player").ok,"Real paid upgrade and growth base coexist")
	check(session.growth.state.inventory.I17==0 and wan.growth.slots.censer=="I17","Equipment consumes actual night inventory")
	ClockNode.set_speed(1)
	step(first,600)
	ClockNode.set_speed(2)
	step(first,600)
	var saved=bridge.snapshot(first)
	night.state.battle_snapshot=saved
	check(night.save("/tmp/ye-ci-p7-midbattle.json").ok,"20 seconds of paid growth inputs and exact state saved to disk")
	var disk=Run.new()
	check(disk.load_save("/tmp/ye-ci-p7-midbattle.json").ok,"Growth inventory and node survive NightRun disk validation")
	var resumed=scene()
	var restored=Bridge.new()
	check(restored.restore(resumed,disk,disk.state.battle_snapshot).ok,"Bridge restores full growth state and recording from disk")
	check(Record.digest(Record.fingerprint(first))==Record.digest(Record.fingerprint(resumed)),"Restored equipped actors and runtime state match before further input")
	ClockNode.set_speed(1)
	step(first,600)
	step(resumed,600)
	check(Record.digest(Record.fingerprint(first))==Record.digest(Record.fingerprint(resumed)),"Both scenes continue ten seconds with identical effects, RNG, actors and resources")
	var exported=bridge.recording.finish()
	check(Archive.validate(exported).ok,"Mixed-speed growth recording satisfies archive contract")
	var speed_inputs=0
	for action in exported.actions:
		if action.action=="speed":speed_inputs+=1
	check(speed_inputs==2,"Actual 1x→2x→1x changes are captured as business clock inputs")
	var stored=Archive.store_record(exported)
	check(stored.ok,"Growth battle fragment is stored in isolated archive directory")
	var from_disk=Archive.load_record(str(stored.get("id","")))
	check(from_disk.ok,"Growth battle fragment is read from disk and verified")
	var replay=scene()
	var player=Player.new()
	check(from_disk.ok and player.start(replay,from_disk.get("record",{})).ok,"Exact disk recording starts in a clean scene")
	# Viewer speed must not change the recorded Y08 business clock.
	ClockNode.set_speed(2)
	for tick in 4000:
		if player.done:break
		player.advance(1.0/60.0)
	check(player.done and player.verified,"Mixed-speed growth replay matches recorded terminal state and key events")
	check(replay.get_node("Session").simulation_speed==1,"Viewer 2x leaves final recorded business clock at 1x")
	var before=Record.digest(Record.fingerprint(resumed))
	var recorder=restored.recording
	var corrupt=disk.state.battle_snapshot.duplicate(true)
	corrupt.growth.inventory.I17=-1
	check(not restored.restore(resumed,disk,corrupt).ok,"Negative growth inventory is rejected before restore")
	check(restored.recording==recorder and Record.digest(Record.fingerprint(resumed))==before,"Rejected growth save preserves live scene and original recorder")
	corrupt=disk.state.battle_snapshot.duplicate(true)
	corrupt.actors[0].fields.growth={"slots":{"censer":4}}
	check(not Snapshot.restore(resumed,corrupt).ok,"Malformed equipment slots reject atomically")
	for invalid_status in [{"construct":{"left":0}},{"ward":{"left":2,"multiplier":[]}}]:
		corrupt=disk.state.battle_snapshot.duplicate(true)
		corrupt.actors[0].fields.growth.statuses=invalid_status
		var status_name=str(invalid_status.keys()[0])
		check(not restored.restore(resumed,disk,corrupt).ok,"Malformed "+status_name+" payload is rejected before it can reach a runtime consumer")
		check(restored.recording==recorder and Record.digest(Record.fingerprint(resumed))==before,"Rejected "+status_name+" payload preserves live battle and recorder")
	var legacy=Run.new()
	legacy.new_run("shouxiang","example","P7-legacy-compatible")
	legacy.choose_node("n01")
	var old_scene=scene()
	var old_bridge=Bridge.new()
	check(old_bridge.start(old_scene,legacy).ok and not old_scene.get_node("Session").growth.enabled,"Legacy P5 entry keeps growth disabled")
	check(is_equal_approx(old_scene.get_node("Session").rules.incense_regen,0.12) and legacy.config.battle_profiles.entry.victory_incense==8,"Legacy battle and victory resource values remain 0.12 and 8")
	var old_state=Snapshot.capture(old_scene)
	old_state.erase("growth")
	for actor_state in old_state.actors:
		for key in Snapshot.UNIT_EXTRA_FIELDS:actor_state.fields.erase(key)
	old_state.session.erase("simulation_speed")
	check(Snapshot.restore(old_scene,old_state).ok,"Older battle snapshot without optional growth fields remains loadable")
	bridge.recording.stop()
	if restored.recording!=null:restored.recording.stop()
	old_bridge.recording.stop()
	first.free();resumed.free();replay.free();old_scene.free()
	ClockNode.set_speed(1)
	var file=FileAccess.open("res://docs/phase-reports/"+prefix+"-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"phase":"P7Persistence","checks":checks,"failures":failures,"results":rows,"scope":"30-second actual growth battle fragment; not an entire night or completed battle"},"\t"))
	file.close()
	print("P7Persistence RESULT: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
