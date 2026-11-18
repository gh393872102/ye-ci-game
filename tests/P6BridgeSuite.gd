extends SceneTree
var checks:=0
var failures:Array[String]=[]
var results:Array[Dictionary]=[]
var report_prefix := "p6-bridge"
var Run
var Bridge
var Record
var Player
var Archive
func check(value:bool,label:String)->void:
	checks+=1
	results.append({"label":label,"passed":value})
	print(("PASS: " if value else "FAIL: ")+label)
	if not value:failures.append(label)
func _initialize()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report-prefix="):
			report_prefix=argument.trim_prefix("--report-prefix=")
	call_deferred("run")
func scene():
	var value=load("res://scenes/combat/Combat.tscn").instantiate()
	root.add_child(value)
	value.get_node("Simulation").set_physics_process(false)
	return value
func night(mode:String,seed:String):
	var value=Run.new()
	value.new_run(mode,"example",seed)
	value.choose_node("n01")
	return value
func rejected_unchanged(bridge,combat,run,bad:Dictionary,label:String)->void:
	var recorder=bridge.recording
	var before=Record.digest(Record.fingerprint(combat))
	check(not bridge.restore(combat,run,bad).ok,label+" rejected")
	check(bridge.recording==recorder and bridge.recording.capturing and Record.digest(Record.fingerprint(combat))==before,label+" preserves scene and recording")
func run()->void:
	await process_frame
	Run=load("res://src/night/NightRun.gd")
	Bridge=load("res://src/night/NightBattleBridge.gd")
	Record=load("res://src/replay/BattleRecord.gd")
	Player=load("res://src/replay/ReplayPlayer.gd")
	Archive=load("res://src/replay/ReplayArchive.gd")
	Archive.directory="/tmp/p6-bridge-review-archives"
	var run1=night("shouxiang","review-disk-continue")
	var c1=scene()
	var b1=Bridge.new()
	check(b1.start(c1,run1).ok,"reference node starts")
	var s1=c1.get_node("Simulation")
	var session=c1.get_node("Session")
	for unit in s1.humans:
		if unit.unit_id=="H09":check(session.upgrade(unit).ok,"real paid upgrade before recording checkpoint")
	for tick in 2700:s1.advance(1.0/60.0)
	var snapshot=b1.snapshot(c1)
	check(snapshot.bridge.has("current_exact") and snapshot.bridge.has("carry_queue_exact"),"current world and carry queue have exact mirrors")
	var bad=snapshot.duplicate(true)
	bad.bridge.recording.steps=[]
	bad.bridge.recording.steps_exact=Marshalls.raw_to_base64(var_to_bytes([]))
	bad.bridge.recording.actions=[]
	rejected_unchanged(b1,c1,run1,bad,"well-typed truncated recording")
	bad=snapshot.duplicate(true);bad.bridge.recording.metadata.node_id="n10"
	rejected_unchanged(b1,c1,run1,bad,"foreign node recording")
	bad=snapshot.duplicate(true);bad.bridge.recording.metadata.seed="foreign"
	rejected_unchanged(b1,c1,run1,bad,"foreign seed recording")
	bad=snapshot.duplicate(true);bad.bridge.carry_queue=["bad"]
	rejected_unchanged(b1,c1,run1,bad,"malformed carry queue")
	bad=snapshot.duplicate(true);bad.bridge.tracked={"bad":"bad"}
	rejected_unchanged(b1,c1,run1,bad,"malformed tracked roster")
	bad=snapshot.duplicate(true);bad.bridge.encountered=[{}]
	rejected_unchanged(b1,c1,run1,bad,"malformed encountered id")
	bad=snapshot.duplicate(true);bad.bridge.starting_roster=["bad"]
	rejected_unchanged(b1,c1,run1,bad,"malformed starting roster")
	bad=snapshot.duplicate(true);bad.bridge.battle_profile={"id":"entry"}
	rejected_unchanged(b1,c1,run1,bad,"partial battle profile")
	bad=snapshot.duplicate(true);bad.bridge.current_exact=Marshalls.raw_to_base64(var_to_bytes({"bad":true}))
	rejected_unchanged(b1,c1,run1,bad,"mismatched exact current")
	run1.state.battle_snapshot=snapshot
	check(run1.save("/tmp/p6-bridge-disk.save").ok,"midbattle save written through real codec")
	var run2=Run.new()
	check(run2.load_save("/tmp/p6-bridge-disk.save").ok,"midbattle save read through real codec")
	var c2=scene()
	var b2=Bridge.new()
	check(b2.start(c2,run2).ok and b2.restore(c2,run2,run2.state.battle_snapshot).ok,"disk continuation restores same node")
	check(Record.digest(Record.fingerprint(c1))==Record.digest(Record.fingerprint(c2)),"restored current fingerprint agrees")
	var s2=c2.get_node("Simulation")
	for tick in 1200:
		s1.advance(1.0/60.0)
		s2.advance(1.0/60.0)
	check(Record.digest(Record.fingerprint(c1))==Record.digest(Record.fingerprint(c2)),"20-second continued trajectory agrees after disk restore")
	check(Record.digest(Record.key_events(c1))==Record.digest(Record.key_events(c2)),"continued key-event ledger agrees")
	b1.recording.stop();b2.recording.stop()
	c1.free();c2.free()
	var run3=night("duoming","review-owned-queue")
	var carried=run3.state.roster[4]
	var row=root.get_node("Data").get_unit("G12")
	carried.id="G12";carried.max_hp=float(row["生命"])+15;carried.hp=carried.max_hp*.6137
	carried.attack=float(row["攻击"])+2;carried.defense=float(row["防御"])+1
	carried.upgrade_level=1;carried.equipment_id="ritual_incense";carried.mutation_count=1
	var c3=scene()
	var b3=Bridge.new()
	check(b3.start(c3,run3).ok and b3.carry_queue.size()>0,"damaged upgraded elite remains in source queue at initial recording")
	var s3=c3.get_node("Simulation")
	for tick in 1900:
		if not c3.get_node("Session").running:break
		s3.advance(.1)
	check(not c3.get_node("Session").result.is_empty(),"source queued-roster battle reaches real result")
	var saved=b3.recording.finish()
	var receipt=Archive.store_record(saved)
	check(receipt.ok,"complete queued-roster battle archives")
	var loaded=Archive.load_record(receipt.get("id",""))
	check(loaded.ok,"complete queued-roster archive loads from disk")
	var c4=scene()
	var player=Player.new()
	check(player.start(c4,loaded.record).ok,"queued-roster replay starts")
	for tick in 2000:
		if player.done:break
		player.advance(.1)
	check(player.done and player.verified,"complete damaged upgraded carry replay fingerprint and events verify")
	var report := {"phase":"P6Bridge","engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"results":results,"queued_result":c3.get_node("Session").result,"replay":player.status(),"fixture_policy":"Isolated bridge/save/replay fixtures. Corrupt checkpoints are deliberately constructed. The queued elite is initialized with damage, upgrades and equipment to test carrying, not to claim a full-night victory. Source battles use the real shared simulator and paid commands; replay executes recorded inputs and exact step deltas."}
	var file := FileAccess.open("res://docs/phase-reports/"+report_prefix+"-results.json",FileAccess.WRITE)
	if file != null:file.store_string(JSON.stringify(report,"\t"))
	DirAccess.remove_absolute("/tmp/p6-bridge-disk.save")
	print("P6Bridge RESULT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
