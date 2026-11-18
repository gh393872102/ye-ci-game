extends SceneTree
var rows:Array=[]
var artifact_root:="/tmp/ye-ci-p8-carry-diagnostic-"+str(OS.get_process_id())
var R
func _initialize()->void:
	assert(artifact_root.begins_with("/tmp/"),"Diagnostic artifacts must stay in /tmp")
	DirAccess.make_dir_recursive_absolute(artifact_root)
	call_deferred("run")
func assert_temporary(path:String)->void:
	assert(path.begins_with("/tmp/") or path.begins_with("/private/tmp/"),"Persistent player paths are forbidden in this probe")
func compare(prior:Dictionary,unit:Node2D)->Dictionary:
	var differences:Dictionary={}
	var night_values:Dictionary={}
	var actor_values:Dictionary={}
	for key in ["hp","max_hp","attack","defense","upgrade_level","equipment_id","mutation_count"]:
		var before=prior.get(key);var after=unit.get(key)
		night_values[key]=before;actor_values[key]=after
		var same:bool=is_equal_approx(float(before),float(after)) if typeof(before) in [TYPE_INT,TYPE_FLOAT] and typeof(after) in [TYPE_INT,TYPE_FLOAT] else before==after
		if not same:differences[key]={"night":before,"actor":after}
	for key in ["slots","job_tags"]:
		var before=prior.get("growth",{}).get(key,{} if key=="slots" else [])
		var after=unit.growth.get(key,{} if key=="slots" else [])
		night_values[key]=before.duplicate(true) if before is Dictionary or before is Array else before
		actor_values[key]=after.duplicate(true) if after is Dictionary or after is Array else after
		if before!=after:differences[key]={"night":before.duplicate(true) if before is Dictionary or before is Array else before,"actor":after.duplicate(true) if after is Dictionary or after is Array else after}
	return {"uid":str(prior.uid),"id":str(prior.id),"night_has_growth":prior.has("growth"),"differences":differences,"night_values":night_values,"actor_values":actor_values}
func run()->void:
	await process_frame
	R=root.get_node("Rules")
	var Run=load("res://src/night/NightRun.gd");var Bridge=load("res://src/night/NightBattleBridge.gd")
	var Archive=load("res://src/replay/ReplayArchive.gd");Archive.directory=artifact_root+"/archives";assert_temporary(Archive.directory)
	for mode in ["shouxiang","duoming"]:
		var night=Run.new();var codex_path=artifact_root+"/codex-"+mode+".json";assert_temporary(codex_path)
		var start=night.new_roster_run(mode,"P7-G1-FULL-"+mode,"",codex_path)
		var before:Array=night.state.roster.duplicate(true);night.choose_node("n01")
		var combat=load("res://scenes/combat/Combat.tscn").instantiate();root.add_child(combat);var sim=combat.get_node("Simulation");sim.set_physics_process(false)
		var bridge=Bridge.new();var entered=bridge.start(combat,night);root.get_node("Clock").set_paused(true)
		var session=combat.get_node("Session");session.codex.path=codex_path;session.codex.autosave=false
		var diffs:Array=[]
		for prior in before:
			var unit:Node2D
			for actor in sim.humans+sim.targets:
				if str(actor.get_meta("night_uid",""))==str(prior.uid):unit=actor;break
			if unit!=null:diffs.append(compare(prior,unit))
			else:
				var queued:Dictionary={}
				for spec in bridge.carry_queue:
					if spec.uid==prior.uid:queued=spec;break
				diffs.append({"uid":prior.uid,"id":prior.id,"not_spawned":true,"queued_exact":queued==prior})
		rows.append({"mode":mode,"start":start,"entered":entered,"comparison_before_any_step_or_input":diffs})
		# Independently reapply a real active actor record to a fresh live P8 actor.
		# This is an explicit transfer fixture, not a simulated victory or next-night result.
		if mode=="shouxiang":
			var guard:Node2D
			for actor in sim.humans:
				if actor.unit_id=="H09":guard=actor;break
			var actions:Array=[]
			actions.append(session.execute_for(mode,"equip_item",{"unit_id":guard.instance_id,"item_id":"I17","slot_index":0},"player"))
			actions.append(session.execute_for(mode,"upgrade",{"unit_id":guard.instance_id},"player"))
			guard.receive_damage(7)
			var record:Dictionary=bridge._roster_record(guard)
			var restored=sim.spawn_human(guard.unit_id,guard.current_post);Bridge.apply_carried_unit(restored,record);session.roster.ensure(restored)
			rows.append({"fixture":"actual_paid_equip_and_upgrade_then_real_damage_then_shared_carry_apply","actions":actions.map(func(x):return {"ok":x.ok,"reason":x.reason}),"comparison":compare(record,restored)})
		bridge.recording.stop();combat.free()
	var path=artifact_root+"/results.json";assert_temporary(path)
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(rows,"\t")+"\n")
	print("P8_CARRY_DIAGNOSTIC ",JSON.stringify({"path":path,"rows":rows}));quit()
