extends SceneTree
## Actual finite paid commands, isolated disk snapshots, continuation and strict replay.
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var R
var Run
var Bridge
var Snapshot
var Record
var Archive
var Player
var Save
var ClockNode
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
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
func run() -> void:
	await process_frame
	R=root.get_node("Rules")
	ClockNode=root.get_node("Clock")
	Run=load("res://src/night/NightRun.gd")
	Bridge=load("res://src/night/NightBattleBridge.gd")
	Snapshot=load("res://src/night/BattleSnapshot.gd")
	Record=load("res://src/replay/BattleRecord.gd")
	Archive=load("res://src/replay/ReplayArchive.gd")
	Player=load("res://src/replay/ReplayPlayer.gd")
	Save=load("res://src/night/NightSave.gd")
	Archive.directory="/tmp/ye-ci-p8-persistence-archives"
	check(root.get_node("Data").errors.is_empty(),"P8 current data boot validates")
	for mode in ["shouxiang","duoming"]:
		var night=Run.new()
		check(night.new_roster_run(mode,"P8-disk-"+mode).ok,"P8 finite-inventory night starts for "+mode)
		check(night._valid_state(night.state),"New P8 night state validates for "+mode)
		check(night.choose_node("n01").ok,"P8 enters actual first battle for "+mode)
		var live=scene()
		var bridge=Bridge.new()
		check(bridge.start(live,night).ok,"P8 bridge enables full roster in existing simulator for "+mode)
		check(live.get_node("Session").roster.enabled,"Full roster enabled for "+mode)
		ClockNode.set_paused(true)
		step(live,300)
		night.state.battle_snapshot=bridge.snapshot(live)
		var path="/tmp/ye-ci-p8-disk-"+mode+".json"
		check(night.save(path).ok,"P8 night writes actual mid-battle disk save for "+mode)
		var disk=Run.new()
		check(disk.load_save(path).ok,"P8 disk night loads without weakening validation for "+mode)
		var resumed=scene()
		var restored=Bridge.new()
		check(restored.restore(resumed,disk,disk.state.battle_snapshot).ok,"P8 bridge restores actor states and Codex for "+mode)
		check(Record.digest(Record.fingerprint(live))==Record.digest(Record.fingerprint(resumed)),"P8 disk restore equals uninterrupted state for "+mode)
		step(live,180);step(resumed,180)
		check(Record.digest(Record.fingerprint(live))==Record.digest(Record.fingerprint(resumed)),"P8 deterministic continuation matches for "+mode)
		bridge.recording.stop();restored.recording.stop()
		live.free();resumed.free()
	settlement_boundary(false)
	settlement_boundary(true)
	misfire_replay_boundary()
	misrecord_route_boundary()
	# Authored starting contact fixture; subsequent changes all use recorded paid APIs.
	var live=scene()
	var session=live.get_node("Session")
	session.start_battle("shouxiang")
	var sim=live.get_node("Simulation")
	for u in sim.humans+sim.targets+sim.corpses:u.free()
	sim.humans.clear();sim.targets.clear();sim.corpses.clear()
	sim.tide.pending.clear();sim.tide.config.waves=[];sim.tide.wave_index=0
	session.configure_dual({"shouxiang":60.0,"duoming":60.0},"shouxiang")
	session.configure_roster("P8-contact-persistence")
	var hunter=sim.spawn_human("H31","post_gate_inner")
	var guard=sim.spawn_human("H09","post_gate_inner")
	var priest=sim.spawn_human("H01","post_register")
	var target=sim.tide.spawn("G12",3,R.body_to_px(49))
	var scribe=sim.tide.spawn("G29",3,R.body_to_px(48.7))
	sim.world.get_node("door_outer").set_open(true)
	target.motion_enabled=false;scribe.motion_enabled=false
	var recording=Record.new()
	recording.begin(live,{"seed":"P8-contact-persistence","source":"p8_controlled_fixture","node_id":"p8-contact","label":"P8有限香火施术/标记/错录/猎步片段，非普通整夜","mode":"duel","director_limit":0})
	check(session.execute_for("shouxiang","mark_target",{"target_id":target.instance_id},"player").ok,"Mark is a real recorded player command")
	check(session.execute_for("shouxiang","unit_skill",{"unit_id":hunter.instance_id,"target_id":target.instance_id},"player").ok,"H31 paid hunt starts through seat command")
	check(session.execute_for("duoming","unit_skill",{"unit_id":scribe.instance_id,"target_id":guard.instance_id},"ai").ok,"G29 real opposing skill changes side through paid API")
	step(live,10)
	var snapshot=Snapshot.capture(live)
	check(guard.side=="yegui" and guard.roster.statuses.has("misrecord"),"Checkpoint captures active temporary side change")
	check(hunter.roster.has("hunt"),"Checkpoint captures H31 moving job before return")
	var path="/tmp/ye-ci-p8-contact-exact.json"
	check(Save.save(path,{"exact":Marshalls.raw_to_base64(var_to_bytes(snapshot)),"mirror":snapshot}).ok,"Active effects serialize to actual isolated disk file")
	var disk=Save.load_save(path)
	var exact=bytes_to_var(Marshalls.base64_to_raw(disk.state.exact))
	check(Record.digest(exact)==Record.digest(disk.state.mirror),"Exact numeric state agrees with readable disk mirror")
	var resumed=scene()
	check(Snapshot.restore(resumed,exact).ok,"Active hunt and allegiance restore in clean scene")
	check(Record.digest(Record.fingerprint(live))==Record.digest(Record.fingerprint(resumed)),"Active-effect restore exactly matches live state")
	step(live,600);step(resumed,600)
	check(Record.digest(Record.fingerprint(live))==Record.digest(Record.fingerprint(resumed)),"Hunt return and misrecord expiry continue deterministically")
	var saved=recording.finish()
	check(Archive.validate(saved).ok,"New skill and mark actions satisfy replay archive schema")
	var receipt=Archive.store_record(saved)
	check(receipt.ok,"P8 skill fragment written to replay disk")
	var loaded=Archive.load_record(str(receipt.get("id","")))
	var replay=scene()
	var player=Player.new()
	var started=player.start(replay,loaded.get("record",{})) if loaded.ok else {"ok":false}
	check(started.ok,"P8 disk fragment loads into the same replay simulator")
	if started.ok:
		for tick in range(1000):
			if player.done:break
			player.advance(.1)
	check(started.ok and player.done and player.verified,"Actual skill/mark/temporary-side fragment replays with identical final and event hashes")
	var before=Record.digest(Record.fingerprint(resumed))
	var bad=snapshot.duplicate(true)
	bad.roster_engine.time=-1
	check(not Snapshot.restore(resumed,bad).ok and before==Record.digest(Record.fingerprint(resumed)),"Bad roster engine time rejects before mutating live scene")
	bad=snapshot.duplicate(true)
	bad.actors[0].fields.roster.cooldowns.skill=-1
	check(not Snapshot.restore(resumed,bad).ok and before==Record.digest(Record.fingerprint(resumed)),"Bad unit skill cooldown rejects atomically")
	bad=snapshot.duplicate(true)
	bad.codex.progress.H01=4
	check(not Snapshot.restore(resumed,bad).ok,"Bad Codex stage rejects instead of granting progress")
	for node in [live,resumed,replay]:node.free()
	var file=FileAccess.open("res://docs/phase-reports/p8-persistence-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"phase":"P8","checks":checks,"failures":failures.size(),"failed":failures,"results":rows,"scope":"real finite stock first 8 seconds of both nights plus authored contact fragment; not a complete P8 night","rules_hash":Record.rules_hash()},"\t")+"\n")
	file.close()
	print("P8 PERSISTENCE RESULT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func settlement_boundary(expired: bool) -> void:
	for mode in ["shouxiang","duoming"]:
		var night=Run.new()
		night.new_roster_run(mode,"P8-misrecord-settlement-"+mode)
		night.choose_node("n01")
		var live=scene()
		var bridge=Bridge.new()
		check(bridge.start(live,night).ok,"Settlement fixture starts actual P8 bridge for "+mode)
		var session=live.get_node("Session")
		var sim=live.get_node("Simulation")
		var scribe=sim.tide.spawn("G29",3,R.body_to_px(51.5))
		var human=actor(live,"H09") if mode=="shouxiang" else sim.spawn_human("H18","post_gate_inner")
		scribe.motion_enabled=false;human.motion_enabled=false
		if mode=="duoming":
			check(session.roster.cast(human).ok,"Actual mirror prepares reflection before temporary transfer")
		var home_before=str(scribe.get_meta("night_home_post",scribe.current_post))
		var changed=session.roster.cast(scribe,{"target_id":human.instance_id})
		var owned=human if mode=="shouxiang" else scribe
		check(changed.ok and owned.roster.statuses.has("misrecord"),"Owned actor is really temporarily on the opposing side at settlement for "+mode)
		if expired:
			# Tick the real expiry handler while keeping this settlement fixture free of combat deaths.
			var duration=float(owned.roster.statuses.misrecord.get("restore_left",0))
			session.roster.ghosts.advance_world(duration+.1)
			check(not owned.roster.statuses.has("misrecord") and owned.side==("xianghuo" if mode=="shouxiang" else "yegui"),"Temporary allegiance really expires back to its original side before settlement for "+mode)
			check(str(scribe.get_meta("night_home_post",scribe.current_post))==home_before,"Temporary restoration preserves the original night post for "+mode)
		# Authored end-of-round boundary; assertions concern roster ownership, not victory strategy.
		session._finish("victory","P4_END_DAYBREAK")
		var before=Record.digest(Record.fingerprint(live))
		var report=bridge.collect(live,night)
		check(before==Record.digest(Record.fingerprint(live)),"Collecting a temporary-side result leaves the final replay state untouched for "+mode)
		var found=false
		for spec in report.roster:
			if spec.id==owned.unit_id:
				found=spec.get("side")== ("xianghuo" if mode=="shouxiang" else "yegui") and not spec.get("roster",{}).get("statuses",{}).has("misrecord")
		check(found,"Temporary side change settles back to original owner without becoming permanent for "+mode)
		check(night.accept_battle(report).ok,"Actual P8 settlement accepts normalized ownership "+("after expiry " if expired else "while active ")+"for "+mode)
		bridge.recording.stop()
		live.free()

func misfire_replay_boundary() -> void:
	# Explicit starting debuff fixture; only the attempt and following simulation are recorded.
	for id in ["G25","H01"]:
		var live=scene()
		var session=live.get_node("Session")
		var sim=live.get_node("Simulation")
		var seat="duoming" if id=="G25" else "shouxiang"
		session.start_battle(seat)
		for u in sim.humans+sim.targets+sim.corpses:u.free()
		sim.humans.clear();sim.targets.clear();sim.corpses.clear()
		sim.tide.pending.clear();sim.tide.config.waves=[];sim.tide.wave_index=0
		session.configure_dual({"shouxiang":60.0,"duoming":60.0},seat)
		session.configure_roster("P8-misfire-replay-"+id)
		var human=sim.spawn_human("H01","post_register")
		var ghost=sim.tide.spawn("G25",3,R.body_to_px(53))
		var owned=ghost if id=="G25" else human
		owned.motion_enabled=false
		session.roster.status(owned,"misname",10)
		var recording=Record.new()
		recording.begin(live,{"seed":"P8-misfire-"+id,"source":"p8_controlled_fixture","node_id":"p8-misfire","label":"P8既有错名状态下的玩家失手尝试","mode":"duel","director_limit":0})
		var answer=session.execute_for(seat,"unit_skill",{"unit_id":owned.instance_id},"player")
		check(answer.ok and answer.get("effect_applied",true)==false and answer.reason=="P8_SKILL_MISFIRED","Misfire is an applied attempt with a failed skill effect for "+id)
		check(not owned.growth.statuses.has("misname") and float(owned.roster.cooldowns.get("skill",0))>0,"Misfire really consumes its debuff and produces cooldown for "+id)
		check(recording.actions.size()==1 and recording.actions[0].action=="unit_skill","Exactly one misfire command is recorded including H01 for "+id)
		step(live,30)
		var saved=recording.finish()
		recording.stop()
		var receipt=Archive.store_record(saved)
		check(receipt.ok,"Misfire fragment is written to replay disk for "+id)
		var loaded=Archive.load_record(str(receipt.get("id","")))
		var replay=scene()
		var player=Player.new()
		var started=player.start(replay,loaded.get("record",{})) if loaded.ok else {"ok":false}
		if started.ok:
			for tick in range(100):
				if player.done:break
				player.advance(.1)
		check(started.ok and player.done and player.verified,"Misfire disk replay reproduces state and event hashes for "+id)
		live.free();replay.free()

func misrecord_route_boundary() -> void:
	var live=scene()
	var session=live.get_node("Session")
	var sim=live.get_node("Simulation")
	session.start_battle("shouxiang")
	for u in sim.humans+sim.targets+sim.corpses:u.free()
	sim.humans.clear();sim.targets.clear();sim.corpses.clear()
	sim.tide.pending.clear();sim.tide.config.waves=[];sim.tide.wave_index=0
	session.configure_dual({"shouxiang":60.0,"duoming":60.0},"shouxiang")
	session.configure_roster("P8-upper-misrecord")
	var borrower=sim.spawn_human("H19","post_stair_head")
	var ghost=sim.tide.spawn("G07",3,R.body_to_px(102))
	var scribe=sim.tide.spawn("G29",3,R.body_to_px(101.5))
	# Starting upper-floor contact fixture; changes below use the actual two skills.
	for unit in [ghost,scribe]:
		unit.floor_id=2;unit.position.y=sim.world.floor_y(2);unit.brain.stage="upper";unit.sync_meta()
	check(session.execute_for("shouxiang","unit_skill",{"unit_id":borrower.instance_id,"target_id":ghost.instance_id},"player").ok and ghost.side=="xianghuo","Upper ghost is really recruited before misrecord")
	check(session.execute_for("duoming","unit_skill",{"unit_id":scribe.instance_id,"target_id":ghost.instance_id},"ai").ok and ghost.side=="yegui","Misrecord really returns the recruited upper ghost to wild side temporarily")
	check(ghost.brain.stage=="upper","Temporary conversion preserves the current upper-route phase")
	var prior:Vector2=ghost.position
	ghost.attacks_enabled=false;borrower.attacks_enabled=false;scribe.attacks_enabled=false
	ghost.brain.advance(.1);ghost.brain.advance(.1)
	check(ghost.floor_id==2 and ghost.position.x>=prior.x-.01,"Converted upper ghost never climbs backward to the original entry")
	# Returning to wild after the rear descent must not restart the first climb either.
	session.roster.set_allegiance(ghost,"xianghuo",1)
	ghost.floor_id=0;ghost.position=Vector2(R.body_to_px(115),sim.world.floor_y(0))
	session.roster.set_allegiance(ghost,"yegui",0)
	check(ghost.brain.stage=="rear","Conversion beyond the descent resumes the rear route")
	live.free()
