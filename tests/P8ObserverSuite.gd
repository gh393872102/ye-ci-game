extends SceneTree
## P8 makes G32 selectable; the historical illegal-ID case now uses G99.
var checks:=0
var failures:=0
var rows:Array[Dictionary]=[]
var prefix:="p8-observer"
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-prefix="):prefix=arg.trim_prefix("--report-prefix=")
	_run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1;rows.append({"check":label,"passed":value})
	if not value:failures+=1
	print(("PASS " if value else "FAIL ")+label)
func _run()->void:
	await process_frame
	var data=root.get_node("Data")
	var clock=root.get_node("Clock")
	var archive=load("res://src/replay/ReplayArchive.gd")
	archive.directory="/tmp/ye-ci-p8-observer-test-archives"
	var combat=load("res://scenes/combat/Combat.tscn").instantiate();root.add_child(combat)
	combat.get_node("Simulation").set_physics_process(false)
	var config:Dictionary=data.mode_rules.defaults.duplicate(true)
	config.seed="P8-G32-REAL-OBSERVATION";config.roster_enabled=true
	config.ghosts=[{"id":"G32","count":1}]
	var service=load("res://src/modes/ObservationSession.gd").new()
	var result:Dictionary=service.start(combat,config)
	check(result.ok and combat.get_node("Session").roster.enabled,"K1 G32 enters an actual roster-enabled observation through validated public configuration")
	var boss:Node2D
	for unit in combat.get_node("Simulation").targets:
		if unit.unit_id=="G32":boss=unit
	check(is_instance_valid(boss) and boss.roster.get("initialized",false) and boss.height_px>=128 and boss.height_px<=176,"K1/K6 Actual observer source queue spawns the real G32 with large physical height and live ability state")
	for index in 60:service.advance(1.0/60)
	check(combat.get_node("Simulation").simulation_time>.9 and is_instance_valid(boss) and not boss.dead,"K1 G32 participates in shared live observer simulation after configuration")
	check(combat.get_node("BattleCamera").zoom==Vector2.ONE and combat.get_node("Simulation").targets.size()<=int(data.mode_rules.limits.ghost_max),"K5/K6 Full roster selection preserves default camera and source population limits")
	service.recording.stop();service.recording=null
	clock.set_paused(true);combat.free()
	FileAccess.open("res://docs/phase-reports/"+prefix+"-results.json",FileAccess.WRITE).store_string(JSON.stringify({"phase":"P8Observer","checks":checks,"failures":failures,"results":rows,"config":config,"duration":1,"fixture":"Actual public observer start and one second shared simulation; not a complete battle or whole night."},"\t")+"\n")
	print("P8Observer RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
