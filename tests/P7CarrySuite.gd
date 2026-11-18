extends SceneTree
## Independent ownership/identity fixtures. No fabricated battle or whole-night outcome.
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var prefix := "p7-carry"
var scenes: Array[Node] = []
var bridges: Array[RefCounted] = []
var Run
var Bridge
var Snapshot
var Record
var Save
var ClockNode
const DISK := "/tmp/ye-ci-p7-carry-checkpoint.json"
const BAD_DISK := "/tmp/ye-ci-p7-carry-invalid.json"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-prefix="): prefix = arg.trim_prefix("--report-prefix=")
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	rows.append({"label":label,"passed":value})
	print(("PASS: " if value else "FAIL: ") + label)
	if not value: failures.append(label)

func scene() -> Node:
	var combat = load("res://scenes/combat/Combat.tscn").instantiate()
	root.add_child(combat)
	combat.get_node("Simulation").set_physics_process(false)
	scenes.append(combat)
	return combat

func actor(combat: Node, id: String) -> Node2D:
	for unit in combat.get_node("Simulation").humans + combat.get_node("Simulation").targets:
		if unit.unit_id == id: return unit
	return null

func actor_uid(combat: Node, uid: String) -> Node2D:
	for unit in combat.get_node("Simulation").humans + combat.get_node("Simulation").targets:
		if str(unit.get_meta("night_uid","")) == uid: return unit
	return null

func contains_uid(records: Array, uid: String) -> bool:
	for record in records:
		if str(record.get("uid","")) == uid: return true
	return false

func start(combat: Node, night: RefCounted) -> RefCounted:
	var bridge = Bridge.new()
	bridges.append(bridge)
	check(bridge.start(combat,night).ok,"Shared battle starts for authored carry fixture")
	ClockNode.set_paused(true)
	return bridge

func growth_night(mode: String, seed_text: String, build_id := "") -> RefCounted:
	var night = Run.new()
	check(night.new_growth_run(mode,seed_text,build_id).ok,"Independent growth night model initializes for " + mode)
	return night

func _run() -> void:
	await process_frame
	Run = load("res://src/night/NightRun.gd")
	Bridge = load("res://src/night/NightBattleBridge.gd")
	Snapshot = load("res://src/night/BattleSnapshot.gd")
	Record = load("res://src/replay/BattleRecord.gd")
	Save = load("res://src/night/NightSave.gd")
	ClockNode = root.get_node("Clock")
	check(root.get_node("Data").errors.is_empty(),"Current data passes startup validation")
	var night = growth_night("shouxiang","P7-carry-identity","wuce")
	# Authored initial stock only; no normal-night reward or battle result is fabricated.
	night.state.growth.inventory.I17 = 1
	check(night.choose_node("n01").ok,"Fixture enters its real first battle node")
	var first = scene()
	var bridge = start(first,night)
	var sim = first.get_node("Simulation")
	var session = first.get_node("Session")
	var growth = session.growth
	var owner = actor(first,"H19")
	check(is_instance_valid(owner),"Authored roster contains the real H19 borrower")
	if not is_instance_valid(owner): return _finish()
	check(session.execute_for("shouxiang","equip_item",{"unit_id":owner.instance_id,"item_id":"I17"},"player").ok,"Actual player command equips stocked I17")
	# Initial elapsed-time fixture: the returned item has exactly ten seconds left.
	growth.state.time = 100.0
	owner.growth.cooldowns.I17 = 10.0
	check(session.execute_for("shouxiang","unequip_item",{"unit_id":owner.instance_id,"slot":"censer"},"player").ok,"Actual unequip returns item with its remaining cooldown")
	var gray = sim.tide.spawn("G12",0,owner.position.x)
	check(is_instance_valid(gray),"Source G12 is spawned through the real tide controller")
	if not is_instance_valid(gray): return _finish()
	gray.position = owner.position
	gray.floor_id = owner.floor_id
	growth._gray(gray,owner,18.0)
	var gray_uid: String = str(gray.get_meta("night_uid",""))
	check(not gray_uid.is_empty() and bridge.tracked.has(gray_uid) and gray in sim.humans,"Actual gray allegiance event enrolls new ally into tracked ownership")
	growth._ungray(gray)
	var left = bridge.collect(first,night)
	check(not gray.dead and not bridge.tracked.has(gray_uid) and contains_uid(left.departed,gray_uid),"Living ally returning to enemy side is departed instead of tracked")
	check(not contains_uid(left.fallen,gray_uid),"Living departed ghost is never reported as fallen")
	growth._gray(gray,owner,18.0)
	check(bridge.tracked.has(gray_uid) and not contains_uid(bridge.departed,gray_uid),"Actual re-enrollment restores tracked and clears this battle's departure")
	# Fractional remaining lifetime is an explicit actor fixture, not simulated night time.
	gray.growth.gray_left = 7.25
	growth.charge(gray,sim.world.get_node("door_inner"))
	check(gray.growth.has("charge_job"),"Real charge hook creates a target-specific pending job")
	var same = Snapshot.capture(first)
	var same_scene = scene()
	check(Snapshot.restore(same_scene,same).ok,"Same-battle snapshot restores the pending charge fixture")
	var same_gray = actor_uid(same_scene,gray_uid)
	check(is_instance_valid(same_gray) and same_gray.growth.get("charge_job",{}) == gray.growth.charge_job,"Same-battle snapshot preserves charge target and elapsed time")
	var collected = bridge.collect(first,night)
	var owner_uid: String = str(owner.get_meta("night_uid"))
	var owner_id: String = owner.instance_id
	var gray_record: Dictionary = {}
	for spec in collected.roster:
		if spec.uid == gray_uid: gray_record = spec
	check(gray_record.get("growth",{}).get("borrower_uid","") == owner_uid,"Collected real roster records stable borrower night_uid")
	var next_night = growth_night("shouxiang","P7-carry-identity","wuce")
	check(next_night.choose_node("n01").ok,"Second independent battle fixture enters the shared node")
	# Cross-battle ownership input is the actual collected roster, with reversed birth order.
	next_night.state.roster = collected.roster.duplicate(true)
	next_night.state.roster.reverse()
	next_night.state.growth = collected.growth.duplicate(true)
	var second = scene()
	var next_bridge = start(second,next_night)
	var next_session = second.get_node("Session")
	var next_growth = next_session.growth
	var next_owner = actor_uid(second,owner_uid)
	var next_gray = actor_uid(second,gray_uid)
	check(is_instance_valid(next_owner) and next_owner.instance_id != owner_id,"Reversed carried birth order genuinely changes H19's scene instance_id")
	check(is_instance_valid(next_gray) and next_gray.side == "xianghuo" and next_gray.growth.gray and is_equal_approx(float(next_gray.growth.gray_left),7.25),"Cross-battle carry preserves gray identity and exact remaining lifetime")
	if not is_instance_valid(next_owner) or not is_instance_valid(next_gray): return _finish()
	check(next_gray.growth.borrower_id == next_owner.instance_id,"Stable borrower_uid rebinds to H19's new scene instance_id")
	check(not next_gray.growth.has("charge_job") and not next_gray.growth.statuses.has("charge"),"Cross-battle carry clears the old battle's charge target and warning")
	check(next_bridge.starting_roster == next_night.state.roster,"Carried opening roster initially equals immutable night ownership input")
	check(next_session.execute_for("shouxiang","equip_item",{"unit_id":next_owner.instance_id,"item_id":"I17"},"player").ok,"Returned I17 can be re-equipped in the second battle")
	check(is_equal_approx(float(next_owner.growth.cooldowns.I17),10.0),"100-second prior time plus ten-second cooldown carries as ten seconds")
	check(next_session.execute_for("shouxiang","unequip_item",{"unit_id":next_owner.instance_id,"slot":"censer"},"player").ok,"Second-battle owned item is unequipped by a real player command")
	check(next_bridge.starting_roster == next_night.state.roster,"Real post-carry inventory changes do not mutate the opening roster")
	var enemy = second.get_node("Simulation").tide.spawn("G25",0,next_gray.position.x)
	check(is_instance_valid(enemy),"Real unregistered G25 contact fixture spawns")
	if is_instance_valid(enemy):
		enemy.position = next_gray.position
		enemy.floor_id = next_gray.floor_id
		next_growth._recapture_contacts()
		check(next_gray.side == "yegui" and next_owner.growth.statuses.has("charm"),"Actual unregistered contact recaptures gray and charms the correct remapped H19")
		var wrong_owner_charmed := false
		for other in second.get_node("Simulation").humans:
			if other != next_owner and other.growth.get("statuses",{}).has("charm"): wrong_owner_charmed = true
		check(not wrong_owner_charmed,"Rebound backlash is never applied to another carried person")
	var saved = next_bridge.snapshot(second)
	check(next_bridge._valid_bridge_state(second,next_night,saved),"Post-carry commands and allegiance changes still produce a valid checkpoint")
	next_night.state.battle_snapshot = saved
	check(next_night.save(DISK).ok,"Real mid-battle ownership checkpoint writes to disk")
	var disk = Run.new()
	check(disk.load_save(DISK).ok,"Mid-battle ownership checkpoint passes disk NightRun validation")
	var resumed = scene()
	var resumed_bridge = Bridge.new()
	bridges.append(resumed_bridge)
	check(resumed_bridge.restore(resumed,disk,disk.state.battle_snapshot).ok,"Bridge restores the real carried ownership checkpoint from disk")
	check(Record.digest(Record.fingerprint(second)) == Record.digest(Record.fingerprint(resumed)),"Disk restore preserves live identity, inventory, effects and timers exactly")
	var before = Record.digest(Record.fingerprint(second))
	var recorder = next_bridge.recording
	var malformed = Snapshot.capture(second)
	malformed.actors[0].fields.profile = {"role":[]}
	check(not Snapshot.restore(second,malformed).ok,"Malformed nested profile rejects before destructive restore")
	check(Record.digest(Record.fingerprint(second)) == before and next_bridge.recording == recorder,"Rejected nested profile preserves all actors and current recorder")
	var invalid = JSON.parse_string(JSON.stringify(next_night.state))
	invalid.before_battle.growth = {"invalid":true}
	check(Save.save(BAD_DISK,invalid).ok,"Invalid nested-growth fixture has a valid disk envelope and checksum")
	var before_run = Record.digest(next_night.state)
	check(not next_night.load_save(BAD_DISK).ok,"Malformed mercy growth rejects even with a valid disk checksum")
	check(Record.digest(next_night.state) == before_run and Record.digest(Record.fingerprint(second)) == before,"Rejected nested mercy growth preserves live night and battle")
	_mutation_limits()
	_finish()

func _mutation_limits() -> void:
	var night = growth_night("duoming","P7-carry-mutation")
	# Independent authored initial resources/material: real commands consume both.
	night.state.incense = 60.0
	night.state.growth.materials = ["H06"]
	night.choose_node("n01")
	var first = scene()
	var bridge = start(first,night)
	var session = first.get_node("Session")
	var ghost = actor(first,"G01")
	check(is_instance_valid(ghost),"Mutation carry fixture begins with an actual ordinary G01")
	if not is_instance_valid(ghost): return
	check(session.execute_for("duoming","mutate_form",{"unit_id":ghost.instance_id,"form_id":"V01"},"player").ok,"Actual paid mutation creates G11 from the carried source")
	check(session.execute_for("duoming","equip_item",{"unit_id":ghost.instance_id,"item_id":"I10"},"player").ok,"Mutated elite consumes its real stocked censer")
	check(session.execute_for("duoming","fuse",{"first_id":ghost.instance_id,"second_id":"","recipe_id":"F03","material_id":"H06"},"player").ok,"Actual paid fusion consumes the authored material")
	var result = bridge.collect(first,night)
	var next = growth_night("duoming","P7-carry-mutation")
	next.choose_node("n01")
	next.state.roster = result.roster.duplicate(true)
	next.state.growth = result.growth.duplicate(true)
	var second = scene()
	start(second,next)
	var carried = actor_uid(second,str(ghost.get_meta("night_uid")))
	var growth = second.get_node("Session").growth
	check(is_instance_valid(carried) and carried.mutation_count == 2 and carried.growth.fusion_id == "F03","Cross-battle elite keeps both mutation uses and its fusion identity")
	check(growth.state.fusion_used == 1 and growth.state.materials.is_empty(),"Cross-battle engine preserves night fusion count and spent material")
	check(is_instance_valid(carried) and carried.growth.slots.censer == "I10" and int(growth.state.inventory.I10) == 0,"Cross-battle inventory cannot duplicate the equipped item")

func _finish() -> void:
	for bridge in bridges:
		if bridge.recording != null: bridge.recording.stop()
	for combat in scenes:
		if is_instance_valid(combat): combat.free()
	for path in [DISK,BAD_DISK]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	ClockNode.set_speed(1)
	ClockNode.set_paused(true)
	var output = FileAccess.open("res://docs/phase-reports/"+prefix+"-results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"phase":"P7Carry","scope":"独立携带状态/身份夹具，不是完整战斗或完整夜程。两场独立初始状态使用真实collect编制；未注入胜负或夜程结局。","fixture_inputs":["守香wuce编制额外预设I17一件；装备冷却初始时钟100秒、剩余10秒","真实灰军事件后预设剩余寿命7.25秒，以检查跨场精确保留","夺名夹具初始香60、H06残名一份，由真实变异/融契命令扣除"],"checks":checks,"failures":failures,"results":rows},"\t")+"\n")
	output.close()
	print("P7Carry RESULT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
