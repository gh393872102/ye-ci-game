extends Node
## Isolated effect probes are explicitly separate from six authored real combat scenarios.
const Build = preload("res://src/growth/BuildScenario.gd")
const Archive = preload("res://src/replay/ReplayArchive.gd")
var checks := 0
var failures := 0
var rows: Array[Dictionary] = []
var effects: Dictionary = {}
var builds: Array[Dictionary] = []
var shots: Array[String] = []
var shared_modes:Array[Dictionary]=[]
var capture := false
var scene: Node2D
var sim: Node2D
var session: Node
var growth: RefCounted
var serial := 0
var feedback_only:=false
var capture_events:=false
func _ready() -> void:
	capture=OS.get_cmdline_user_args().has("--capture")
	Archive.directory="/tmp/ye-ci-p7-effect-render-archives" if capture else "/tmp/ye-ci-p7-effect-test-archives"
	capture_events=OS.get_cmdline_user_args().has("--event-frames")
	_run.call_deferred()
func check(ok:bool,label:String,id:="") -> void:
	checks+=1
	rows.append({"check":label,"passed":ok,"effect":id})
	if not ok:failures+=1
	if id!="":effects[id]=bool(effects.get(id,true)) and ok
	print(("PASS " if ok else "FAIL ")+label)
func near(a:float,b:float)->bool:return absf(a-b)<.001
func _rig(mode:="shouxiang",extra:Dictionary={}) -> void:
	if is_instance_valid(scene):scene.free()
	scene=preload("res://scenes/combat/Combat.tscn").instantiate();add_child(scene)
	sim=scene.get_node("Simulation");sim.set_physics_process(false)
	session=scene.get_node("Session");session.running=false;session.start_battle(mode)
	for unit in sim.humans+sim.targets+sim.corpses+sim.projectiles:unit.free()
	sim.humans.clear();sim.targets.clear();sim.corpses.clear();sim.projectiles.clear()
	sim.tide.pending.clear();sim.tide.config.waves=[];sim.tide.wave_index=0
	session.incense=60;session.names=6
	var inventory:Dictionary={"J01":4,"J02":4}
	for id in Data.growth_rules.items:inventory[id]=5
	var initial={"inventory":inventory,"materials":["H06"],"ritual_flag":""}
	initial.merge(extra,true)
	session.configure_growth("P7-probe-%d"%serial,initial);serial+=1
	growth=session.growth;Clock.set_paused(true);Clock.set_speed(1)
func human(id:="H01",post:="post_register") -> Node2D:
	var u=sim.spawn_human(id,post)
	u.position=sim.post_destination(u,post);u.brain.settled_position=u.position
	u.attacks_enabled=false;u.motion_enabled=false;growth.ensure(u)
	return u
func ghost(id:="G12",x:=114.0,lane:=0)->Node2D:
	var u=sim.tide.spawn(id,lane,Rules.body_to_px(x));u.attacks_enabled=false;u.motion_enabled=false;growth.ensure(u);return u
func equip(u:Node2D,id:String,index:=0)->bool:
	return session.execute_for(growth.seat_of(u),"equip_item",{"unit_id":u.instance_id,"item_id":id,"slot_index":index},"player").ok
func unequip(u:Node2D,slot:String,index:=0)->void:
	session.execute_for(growth.seat_of(u),"unequip_item",{"unit_id":u.instance_id,"slot":slot,"slot_index":index},"player")
func tick(seconds:float,full:=false)->void:
	for index in ceili(seconds*60):
		if full:sim.advance(1.0/60)
		else:growth.advance(1.0/60)
func hit(attacker:Node2D,victim:Node2D,kind:="melee",attack:=10.0)->float:
	var before:float=victim.hp if victim.is_in_group("units") else victim.durability
	sim.deal_damage(attacker,victim,kind,attack)
	return before-(victim.hp if victim.is_in_group("units") else victim.durability)
func event(kind:String)->bool:
	for entry in growth.state.events:
		if entry.kind==kind:return true
	return false
func _run()->void:
	if capture:get_window().size=Vector2i(1920,1080)
	if "--brace-frame" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() == "headless":
			get_tree().quit(2)
			return
		_rig("shouxiang",{"defense_objective":"hold_register"})
		var defender := human("H20")
		var foe := ghost()
		foe.position = defender.position + Vector2(85,0)
		foe.floor_id = defender.floor_id
		equip(defender,"I08");equip(defender,"Y11")
		var camera := scene.get_node("BattleCamera")
		camera.make_current()
		camera.set_left(defender.position.x - 960)
		defender.receive_damage(400,foe)
		growth.advance(0.16)
		sim.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		var valid: bool = shot.get_size() == Vector2i(1920,1080) and event("paper_brace") and not defender.dead
		if valid:
			valid = shot.save_jpg("/tmp/ye-ci-paper-brace.jpg",0.86) == OK
		growth.state.fields.clear()
		sim.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var control := get_viewport().get_texture().get_image()
		var origin: Vector2i = defender.get_global_transform_with_canvas().origin
		var changed := 0
		for y in range(origin.y-155,origin.y-80):
			for x in range(origin.x-42,origin.x+42):
				if shot.get_pixel(x,y) != control.get_pixel(x,y): changed += 1
		valid = valid and changed >= 100
		print("Changed pixels above guard ",changed)
		print("Paper brace rendered ",valid," at ",defender.get_global_transform_with_canvas().origin)
		scene.free()
		await get_tree().create_timer(0.3).timeout
		get_tree().quit(0 if valid else 1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--replay-only="):
			await _disk_replay(arg.trim_prefix("--replay-only="),"chaodu");get_tree().quit(1 if failures else 0);return
	check(Data.errors.is_empty(),"K1 Source catalog and existing stages boot without data errors")
	check(Data.growth_rules.items.size()==48,"K1 Exact catalog contains 20 censers, 16 arts and 12 plates")
	_slots();_censers();_arts();_plates();_transformations();await _jobs_borrow();_extra_effects();_budget_behavior()
	await _scenarios()
	await _observer_growth()
	var censer_ok:=0
	for id in effects:
		if id.begins_with("I") and effects[id]:censer_ok+=1
	check(censer_ok>=18,"K2 At least eighteen censers pass observable effect probes")
	check(effects.get("I10",false) and effects.get("I11",false) and effects.get("I17",false),"K2 Mandatory I10/I11/I17 effects all pass")
	var arts_ok:=0;var plates_ok:=0
	for id in effects:
		if id.begins_with("Y") and effects[id]:arts_ok+=1
		if id.begins_with("N") and effects[id]:plates_ok+=1
	check(arts_ok==16 and plates_ok==12,"K2 All sixteen arts and twelve plates have actual behavior evidence")
	if is_instance_valid(scene):scene.free()
	var prefix:="p7"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-prefix="):prefix=arg.trim_prefix("--report-prefix=")
	FileAccess.open("res://docs/phase-reports/"+prefix+("-render" if capture else "-test")+"-results.json",FileAccess.WRITE).store_string(JSON.stringify({"phase":"P7","rules_hash":load("res://src/replay/BattleRecord.gd").rules_hash(),"archive_directory":Archive.directory,"checks":checks,"failures":failures,"results":rows,"effects":effects,"builds":builds,"shared_modes":shared_modes,"screenshots":shots,"capture":capture,"fixture_policy":"Effect probes may author isolated positions/resources/HP/environment and invoke the same event handlers as AI. Six build battles start declared accept_*.json initial conditions and then use only real commands plus shared Simulation.advance. Source-origin and authored-contact timing are identified per scenario. These fixtures are not ordinary whole-night timing evidence.","deferred":["I20 skill strengthening/name-drain interface","F04 optional fusion"]},"\t")+"\n")
	print("P7 RESULT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
func _slots()->void:
	_rig();var u=human();var g=ghost("G01")
	check(equip(u,"I17") and equip(u,"Y01",0) and equip(u,"Y03",1) and equip(u,"N01"),"K1 Four declared slots accept one censer, two distinct arts and one plate")
	check(not equip(u,"Y01",1) and not equip(u,"Y04",2),"K1 Duplicate art and third art slot are rejected without consumption")
	check(not equip(g,"I10") and growth.state.inventory.I10==5,"K1 Ordinary white ghosts cannot equip any slot")
	var qty:int=growth.state.inventory.I17
	unequip(u,"censer")
	check(growth.state.inventory.I17==qty+1 and u.growth.slots.censer=="","K1 Removal returns the exact inventory item")
	Clock.set_paused(false)
	check(not equip(u,"I17"),"K1 Player cannot change equipment during live time")
	Clock.set_paused(true);growth.state.inventory.I01=1;equip(u,"I01");growth.apply_status(u,"fear",3);unequip(u,"censer");equip(u,"I01");growth.apply_status(u,"fear",3)
	check(u.growth.statuses.has("fear"),"K1 Consumed one-use mask is not recreated by removing its spent slot")
func _censers()->void:
	_rig();var u=human();equip(u,"I01");growth.apply_status(u,"fear",3)
	check(not u.growth.statuses.has("fear"),"I01 First fear is visibly blocked","I01")
	growth.apply_status(u,"face_theft",3);check(u.growth.statuses.has("face_theft"),"I01 Second eligible status is not free immunity","I01")
	_rig();u=human();equip(u,"I02");session.names=0;tick(.1);check(session.names==1 and event("rekindle"),"I02 Zero-name book rekindles once with real name credit","I02");session.names=0;tick(.1);check(session.names==0,"I02 Spent incense cannot rekindle twice","I02")
	_rig();u=human("H17","post_gate_inner");equip(u,"I03");var d=sim.world.get_node("door_outer");growth.seal_door(u,d);check(near(growth.state.seals[str(d.name)].left,6),"I03 Real seal lasts six seconds instead of four","I03")
	var g=ghost("G12",49);var hp:float=g.hp;var door_hp:float=d.durability;hit(g,d,"structure",10);check(d.durability==door_hp and g.hp<hp and event("seal_absorbed"),"I03 Sealed real structure absorbs attack and reflects damage","I03")
	_rig();u=human();g=ghost("G04",114);equip(u,"I04");tick(.1);check(g.growth.statuses.has("revealed") and not growth.is_hidden(g),"I04 Persistent three-body light reveals an actual hidden ghost","I04")
	_rig("duoming");g=ghost("G09",100);g.floor_id=3;g.position.y=sim.world.floor_y(3);equip(g,"I05");growth.knock_from_beam(g);check(not g.dead and g.floor_id>0 and event("beam_nail_saved"),"I05 Beam knock lands at real upper safe post without fall death","I05")
	_rig();u=human();g=ghost();equip(u,"I06");u.growth.environment.bridge=true
	var baseline=hit(u,g,"melee",10);u.growth.environment.bridge=false;var normal=hit(u,g,"melee",10)
	check(near(baseline/normal,1.2),"I06 Bridge attack changes actual damage by twenty percent","I06")
	hp=u.hp;u.receive_damage(10,g,"water");growth.apply_status(u,"drag",4,g);check(near(hp-u.hp,5) and near(u.growth.statuses.drag.left,2),"I06 Water injury and dragging duration are halved","I06")
	_rig();u=human("H07");g=ghost("G04",110);g.position=u.position-Vector2(320,0);growth.drum(u);check(not g.growth.statuses.has("revealed"),"I07 Baseline drum misses a target four bodies away","I07");equip(u,"I07");growth.drum(u);check(g.growth.statuses.has("revealed"),"I07 Equipped drum reveals the same four-body target","I07")
	_rig();u=human();equip(u,"I08");growth.apply_status(u,"name_erase",3);var names:float=session.names;growth.apply_status(u,"name_erase",3);check(names==6 and session.names==5,"I08 Only first name erasure is consumed by blank note","I08")
	_rig();u=human();equip(u,"I09");session.incense=20;hp=u.hp;u.receive_damage(10);check(near(hp-u.hp,7) and session.incense==21,"I09 Actual injury converts thirty percent to one incense","I09");hp=u.hp;u.receive_damage(10);check(near(hp-u.hp,10) and session.incense==21,"I09 Cooldown prevents immediate second conversion","I09")
	for i in 5:u.hp=u.max_hp;tick(20.1);u.receive_damage(1)
	u.hp=u.max_hp;tick(20.1);var money:float=session.incense;u.receive_damage(1);check(u.growth.charges.I09==6 and near(session.incense,money),"I09 Six-use night limit remains after cooldown expires","I09")
	_rig("duoming");g=ghost();d=sim.world.get_node("door_outer");var first=hit(g,d,"structure",5);equip(g,"I10");var second=hit(g,d,"structure",5);check(near(second/first,1.4),"I10 Real G12 structure hit receives forty percent bonus","I10")
	_rig();u=human("H09","post_gate_inner");equip(u,"I10");d=sim.world.get_node("door_outer");d.set_durability(400);var result=session.repair(str(d.name));check(result.ok and near(session.repair_jobs[0].heal,210),"I10 Real paid repair job records seventy percent restoration","I10");u.motion_enabled=true;tick(12,true);check(near(d.durability,610),"I10 Paid repair actually finishes at 210 restored durability","I10")
	_rig();u=human();g=ghost("G12",114);g.growth.environment.water=true;equip(u,"I11");result=session.start_ritual(u,g);check(result.ok and near(u.brain.channel.duration,2.8),"I11 Paid water-target reading uses actual 2.8 second channel","I11")
	_rig();u=human();g=ghost();equip(u,"I12");hp=g.hp;u.receive_damage(8,g,"occult");check(near(hp-g.hp,2) and event("reflection"),"I12 Real targeted occult hit reflects twenty-five percent","I12")
	_rig();u=human();var spare=human("T01");spare.position=u.position;equip(u,"I13");u.hp=1;u.receive_damage(999);check(not u.dead and spare.dead and event("substitute_death"),"I13 Nearby ordinary unit pays one real lethal substitution","I13");u.receive_damage(999);check(u.dead,"I13 Thread cannot substitute twice","I13")
	_rig("shouxiang",{"ritual_flag":"jizao"});u=human();g=ghost();equip(u,"I14");var fire=hit(u,g,"fire",4);var physical=hit(u,g,"occult",4);check(near(fire/physical,1.3),"I14 Ritual flag increases real fire damage thirty percent","I14")
	_rig();u=human();g=ghost();equip(u,"I14");g.hp=10000;var found:=false
	for i in 80:
		hit(u,g,"fire",1)
		if not growth.state.fields.is_empty():found=true;break
	var friend=human("H09");friend.position=g.position;hp=friend.hp;tick(.5);check(found and friend.hp<hp,"I14 Unflagged proc creates real fire that hurts a nearby ally","I14")
	_rig();u=human();g=ghost("G12",114);u.position=Vector2(2000,sim.world.floor_y(0));g.position=Vector2(1840,sim.world.floor_y(0));equip(u,"I15");var x:float=g.position.x;tick(.1);check(near(absf(g.position.x-x),80) and event("attraction"),"I15 Nearest actual enemy is pulled one body with cooldown","I15")
	_rig("duoming");g=ghost("G13",49);d=sim.world.get_node("door_outer");var damage=hit(g,d,"charge_structure",4);equip(g,"I16");var boosted=hit(g,d,"charge_structure",4);check(near(boosted/damage,1.25),"I16 Charge damage against a real structure increases twenty-five percent","I16")
	_rig();u=human();equip(u,"I16");g=ghost("G13",114);growth.charge(g,u);check(event("charge_forewarned") and near(g.growth.charge_job.duration,1.5),"I16 Friendly bearer sees actual 1.5 second charge warning","I16")
	_rig();u=human();g=ghost("G12",114);equip(u,"I17");result=session.start_ritual(u,g);u.brain.channel.advance(sim,u,1);var progress:float=u.brain.channel.elapsed;u.receive_damage(1,g);check(result.ok and u.brain.channel.active and near(u.brain.channel.elapsed,progress*.7),"I17 Ordinary real damage retains channel and removes thirty percent progress","I17");growth.apply_status(u,"drag",3,g);check(not u.brain.channel.active,"I17 Drag still interrupts the guarded channel","I17")
	_rig();u=human();g=ghost();var damage0=hit(u,g,"melee",5);equip(u,"I18");var damage1=hit(u,g,"melee",5);friend=human("H09");friend.position=u.position;friend.hp=1;growth.heal(friend,10);check(near(damage1/damage0,1.2) and near(friend.hp,8),"I18 Real ghost injury rises and nearby character healing falls thirty percent","I18")
	_rig("shouxiang",{"locked_paths":[{"id":"door_gallery","locked":true}]});u=human();d=sim.world.get_node("door_gallery");d.set_open(false);equip(u,"I19");check(d.is_open and not growth.path_locked("door_gallery") and event("key_opened"),"I19 Bone key opens an actual declared path lock once","I19")
	_rig();u=human();var no_lock=session.execute_for("shouxiang","equip_item",{"unit_id":u.instance_id,"item_id":"I19"},"player");check(no_lock.ok and no_lock.reason=="P7_NO_LOCK" and event("no_lock"),"I19 Lock-free scene returns explicit tonight-no-lock feedback","I19")
	check(Data.growth_rules.items.I20.status=="interface","K2/S1 I20 is explicitly deferred instead of claiming a fabricated effect")
func _arts()->void:
	_rig();var u=human();var g=ghost("G01",114);var elite=ghost("G12",114.5);elite.hp=3;equip(u,"Y01");var paid=session.start_ritual(u,g);u.brain.channel.advance(sim,u,4)
	check(paid.ok and event("ritual_release") and elite.hp==1 and not elite.dead,"Y01 Actual completed reading releases incense without killing nearby elite","Y01")
	_rig();u=human("H09","post_gate_inner");g=ghost("G12",49);var d=sim.world.get_node("door_outer");d.set_durability(200);equip(u,"Y02");var a=hit(u,g,"melee",5);d.set_durability(d.max_durability);var b=hit(u,g,"melee",5);check(near(a/b,1.3),"Y02 Actual attack rises only beside a door under thirty percent","Y02")
	_rig();u=human();g=ghost("G01",114);var ally=human("H09");equip(u,"Y03");session.start_ritual(u,g);u.brain.channel.advance(sim,u,4);check(ally.growth.statuses.has("procession") and near(growth.speed_multiplier(ally),1.2),"Y03 Real purification gives a four-second procession to another ally","Y03");tick(4.1);check(not ally.growth.statuses.has("procession"),"Y03 Procession expires","Y03")
	_rig();u=human();g=ghost();equip(u,"Y04");u.floor_id=3;a=hit(u,g,"melee",5);u.floor_id=0;b=hit(u,g,"melee",5);check(near(a/b,1.5),"Y04 Actual beam attack multiplies damage by one and a half","Y04")
	_rig();u=human();u.growth.environment.water=true;u.growth.statuses.landing_weak={"left":4.0};check(growth.speed_multiplier(u)<1,"Y05 Baseline water and landing weakness reduce speed","Y05");equip(u,"Y05");check(near(growth.speed_multiplier(u),1),"Y05 Equipped unit moves without either environmental slowdown","Y05")
	_rig();u=human();equip(u,"Y06");session.incense=20;g=ghost("G01");hit(u,g,"melee",100);check(session.incense==21,"Y06 Actual kill credits one incense","Y06");g=ghost("G01");hit(u,g,"melee",100);check(session.incense==21,"Y06 Eight-second recovery cooldown prevents repeated kill farming","Y06")
	_rig();u=human();equip(u,"Y07");growth.apply_status(u,"charm",8);check(not u.growth.statuses.has("charm") and near(u.growth.statuses.root.left,2),"Y07 Charm becomes two-second immobilization without friendly retarget","Y07")
	_rig();u=human();ally=human("H09");equip(u,"Y08");u.growth.cooldowns.test=4.0;ally.growth.cooldowns.test=4.0;session.simulation_speed=2;tick(2);check(near(u.growth.cooldowns.test,3) and near(ally.growth.cooldowns.test,2),"Y08 Real cooldown ticks at one-clock rate while normal cooldown runs double","Y08")
	_rig();u=human("H09","post_gate_inner");equip(u,"Y09");d=sim.world.get_node("door_outer");d.set_durability(500);paid=session.repair(str(d.name));check(paid.ok and near(session.repair_jobs[0].duration,2.25),"Y09 Actual paid repair job is twenty-five percent shorter","Y09")
	_rig();u=human();g=ghost();equip(u,"Y10");a=hit(u,g,"melee",5);growth.apply_status(g,"revealed",3);b=hit(u,g,"melee",5);check(near(b/a,1.2),"Y10 Real hit against a revealed target gains twenty percent","Y10")
	_rig("shouxiang",{"defense_objective":"hold_register"});u=human();g=ghost()
	equip(u,"I08");equip(u,"Y11")
	u.receive_damage(4,g)
	check(not event("paper_brace"),"Nonlethal hit preserves the blank note")
	var hp_before:float=u.hp
	u.receive_damage(400,g)
	check(near(u.hp,hp_before) and event("paper_brace"),"Register pair cancels one lethal breaker hit")
	var names_before:float=session.names
	growth.apply_status(u,"name_erase",3)
	check(session.names < names_before,"Spent paper no longer protects the name")
	u.receive_damage(400,g)
	check(u.dead,"Second lethal breaker hit kills")
	_rig("shouxiang",{"defense_objective":"hold_register"});u=human();g=ghost();equip(u,"I08");equip(u,"Y11")
	growth.apply_status(u,"name_erase",3)
	u.receive_damage(400,g)
	check(u.dead and not event("paper_brace"),"Erasure spent the shared note before the hit")
	_rig();u=human();g=ghost();equip(u,"I08");equip(u,"Y11")
	u.receive_damage(400,g)
	check(u.dead and not event("paper_brace"),"Other objectives preserve the existing item rules")
	_rig("shouxiang",{"defense_objective":"hold_register"});u=human("H01","post_hall_door");g=ghost();equip(u,"I08");equip(u,"Y11")
	u.receive_damage(400,g)
	check(u.dead and not event("paper_brace"),"The hall does not activate the register pair")
	_rig();u=human();g=ghost();u.receive_damage(4,g);var hp:float=u.hp;equip(u,"Y11");u.receive_damage(4,g);check(near(hp-u.hp,3),"Y11 Actual breaking-tag injury falls twenty-five percent","Y11")
	_rig("duoming");g=ghost("G09",87);equip(g,"Y12");check(near(growth.stair_factor(g,.55),1),"Y12 Ghost stair movement receives unpenalized factor","Y12")
	# Use the genuine GhostBrain climb step for observable movement, with a controlled initial climb contact.
	g.floor_id=0;g.brain.stage="climb";g.motion_enabled=true;var start:Vector2=g.position;g.brain.advance(.1);var moved:float=g.position.distance_to(start);unequip(g,"art");g.position=start;g.brain.stage="climb";g.brain.advance(.1);check(moved>g.position.distance_to(start)*1.5,"Y12 Genuine climb step moves farther without local stair penalty","Y12")
	_rig();u=human();g=ghost("G12",114);equip(u,"Y13");session.names=0;paid=session.start_ritual(u,g);check(paid.ok and near(u.brain.channel.duration,3.2),"Y13 Actual reading in zero-name window takes 3.2 seconds","Y13")
	_rig();u=human("H11","post_barricade_outer_court");equip(u,"Y14");var object=sim.world.obstacles[0];u.position=object.position+Vector2(40,0);object.set_occupied(false);var placed=growth.place_barricade(u,str(object.name));tick(2.2);check(placed.ok and object.occupied and near(object.durability,Data.growth_rules.skills.barricade_durability*1.4),"Y14 Real paid placement finishes with forty percent more durability","Y14")
	_rig();u=human();g=ghost("G01",114);equip(u,"Y15");var x:float=g.position.x;hit(u,g,"melee",2);check(near(absf(g.position.x-x),48),"Y15 Actual melee hit pushes an ordinary unit 0.6 body","Y15");g=ghost("G12",114);x=g.position.x;hit(u,g,"melee",2);check(near(g.position.x,x),"Y15 Large unit is immune to short push","Y15")
	_rig();u=human("H19");g=ghost("G01",114);equip(u,"Y16");growth._gray(g,u,10);check(near(g.growth.gray_left,15) and g.side=="xianghuo","Y16 Actual borrowed allegiance lasts fifty percent longer","Y16")
func _plates()->void:
	_rig();var u=human();var maxhp:float=u.max_hp;equip(u,"N01");check(near(u.max_hp,maxhp*1.15),"N01 Actual maximum HP rises fifteen percent","N01");unequip(u,"nameplate");check(near(u.max_hp,maxhp),"N01 Unequip reverses exact maximum HP bonus","N01")
	_rig();u=human();equip(u,"N02");check(near(growth.speed_multiplier(u),1.12),"N02 Movement hook applies twelve percent speed bonus","N02")
	_rig();u=human();var attack:float=u.attack;equip(u,"N03");check(near(u.attack,attack*1.12),"N03 Actual actor attack rises twelve percent","N03")
	_rig();u=human("H09","post_gate_inner");var g=ghost("G12",49);var d=sim.world.get_node("door_outer");u.position=d.position+Vector2(40,0);var a=hit(g,d,"structure",3);equip(u,"N04");var b=hit(g,d,"structure",3);check(near(b/a,.8),"N04 Actual nearby door receives twenty percent less damage","N04")
	_rig();u=human();g=ghost("G12",114);equip(u,"N05");var money:float=session.incense;var paid=session.start_ritual(u,g);check(paid.ok and near(money-session.incense,3),"N05 Actual paid reading costs three incense rather than four","N05")
	_rig();u=human();equip(u,"N06");session.names=100;var blocked:=0;var applied:=0
	for i in 40:
		var before:float=session.names;growth.apply_status(u,"name_erase",.1)
		if session.names==before:blocked+=1
		else:applied+=1
	check(blocked>0 and applied>0 and blocked+applied==40,"N06 Seeded fifty-percent name defense produces both actual outcomes","N06")
	_rig();u=human();g=ghost();equip(u,"N07");var hp:float=u.hp;u.receive_damage(8,g,"occult");check(near(hp-u.hp,6),"N07 Actual occult injury falls twenty-five percent","N07");hp=u.hp;u.receive_damage(8,g,"reflection");check(near(hp-u.hp,6),"N07 Reflected injury also falls twenty-five percent","N07")
	_rig();u=human();equip(u,"N08");growth.apply_status(u,"cry_stun",5);check(near(u.growth.statuses.cry_stun.left,3),"N08 Real crying debuff lasts three instead of five seconds","N08")
	_rig();u=human();g=ghost("G04");tick(.1);equip(u,"N09");var boosted=hit(u,g,"melee",5);check(g.growth.statuses.has("revealed") and near(g.growth.statuses.revealed.left,2),"N09 Real hidden-target hit reveals for two seconds","N09");var normal=hit(u,g,"melee",5);check(near(boosted/normal,1.3),"N09 Hidden-target injury gains thirty percent","N09")
	_rig();u=human();g=ghost();u.growth.environment.water=true;var defense:float=u.defense;var wet=hit(u,g,"melee",5);equip(u,"N10");var dry=hit(u,g,"melee",5);check(near(dry/wet,1.25) and near(growth.defense_for(u),defense),"N10 Actual water attack and defense retain dry values","N10")
	_rig();u=human();u.floor_id=3;equip(u,"N11");check(near(growth.defense_for(u),u.defense*1.2) and near(growth.landing_duration(u,4),2),"N11 Beam defense rises twenty percent and landing duration halves","N11")
	_rig();u=human();g=ghost("G25");var base=hit(u,g,"melee",5);equip(u,"N12");var bonus=hit(u,g,"melee",5);hp=u.hp;u.receive_damage(5,g);check(near(bonus/base,1.2) and near(hp-u.hp,5.5),"N12 Actual nameless outgoing bonus and incoming penalty both apply","N12")
func _transformations()->void:
	for recipe in ["V01","V02","V03"]:
		_rig("duoming");var g=ghost("G01",0);var cost:float=Data.growth_rules.mutations[recipe].cost;var before:float=session.incense;var answer=session.execute_for("duoming","mutate_form",{"unit_id":g.instance_id,"form_id":recipe},"player")
		check(answer.ok and g.unit_id==Data.growth_rules.mutations[recipe].result_id and near(before-session.incense,cost),"K3 %s genuine form command transforms and pays declared cost"%recipe)
	_rig("duoming");var g=ghost("G13",0);equip(g,"I10");equip(g,"N01");g.hp=g.max_hp*.6;var uid:String=g.instance_id
	var first=session.execute_for("duoming","mutate_form",{"unit_id":uid,"form_id":"V03"},"player")
	check(first.ok and g.instance_id==uid and g.growth.slots.censer=="I10" and near(g.hp/g.max_hp,.6),"K3 Mutation keeps identity, equipment and injury ratio")
	var other=ghost("G20",0);var second=session.execute_for("duoming","fuse",{"first_id":uid,"second_id":other.instance_id,"recipe_id":"F02"},"player")
	check(second.ok and g.mutation_count==2 and other.dead and growth.state.unlocks.F02,"K4 Doorbreaker plus palanquin becomes real unlocked fusion")
	other=ghost("G20",0);var money:float=session.incense;var third=session.execute_for("duoming","fuse",{"first_id":uid,"second_id":other.instance_id,"recipe_id":"F02"},"player")
	check(not third.ok and not other.dead and session.incense==money,"K3 Third transformation is rejected without killing partner or charging")
	_rig();var h=human();check(not session.execute_for("shouxiang","mutate_form",{"unit_id":h.instance_id,"form_id":"V01"},"player").ok,"K5 Humans never use ghost mutation command")
	for recipe in ["F01","F03"]:
		_rig("duoming");var id:String="G09" if recipe=="F01" else "G11";g=ghost(id,0);other=ghost("G04",0) if recipe=="F01" else null
		var answer=session.execute_for("duoming","fuse",{"first_id":g.instance_id,"second_id":other.instance_id if other!=null else "","recipe_id":recipe,"material_id":"H06" if recipe=="F03" else ""},"player")
		check(answer.ok and g.growth.fusion_id==recipe and growth.state.unlocks.has(recipe),"K4 %s actual recipe produces persistent discovery"%recipe)
		if recipe=="F03":check("H06" not in growth.state.materials and g.growth.statuses.has("double_lamp"),"K4 F03 consumes one material and creates real twenty-second double-light state")
	_rig("duoming");var successes:=0
	for i in 3:
		g=ghost("G09",0);other=ghost("G04",0);session.incense=60
		var answer=session.execute_for("duoming","fuse",{"first_id":g.instance_id,"second_id":other.instance_id,"recipe_id":"F01"},"player")
		if answer.ok:successes+=1
	check(successes==2 and growth.state.fusion_used==2,"K4 Night-wide fusion budget allows two and rejects third")
	check(Data.growth_rules.fusions.F04.status=="interface","S3 Optional F04 is visibly deferred")
func _jobs_borrow()->void:
	_rig();var u=human("H09","post_gate_inner");var answer=session.execute_for("shouxiang","stamp_job",{"unit_id":u.instance_id,"job_id":"J01"},"player");var d=sim.world.get_node("door_outer");d.set_durability(500);var before:float=session.incense;var repair=session.repair(str(d.name));check(answer.ok and repair.ok and near(before-session.incense,4.8),"K5 J01 changes a real paid repair to 4.8 incense")
	_rig();u=human("H17","post_gate_inner");var ally=human("H09","post_gate_inner");answer=session.execute_for("shouxiang","stamp_job",{"unit_id":u.instance_id,"job_id":"J02"},"player");d=sim.world.get_node("door_outer");growth.seal_door(u,d);var g=ghost("G12",49);hit(g,d,"structure",1);check(answer.ok and ally.growth.statuses.has("ward") and near(growth.defense_for(ally),ally.defense*1.2),"K5 J02 broken real seal gives nearby ally twenty-percent defense");tick(3.1);check(not ally.growth.statuses.has("ward"),"K5 J02 defense ward expires after three seconds")
	_rig();u=human("H17","post_gate_inner");ally=human("H09","post_gate_inner");session.execute_for("shouxiang","stamp_job",{"unit_id":u.instance_id,"job_id":"J02"},"player");d=sim.world.get_node("door_outer");growth.seal_door(u,d);tick(4.1);check(not ally.growth.statuses.has("ward") and not event("job_defense_ward"),"K5 J02 natural seal timeout never grants the attacked-seal defense reward")
	var outcomes:Dictionary={}
	for attempt in 24:
		_rig("shouxiang",{"ritual_flag":"youshen"});u=human("H23");growth.rng.seed=("borrow-%d"%attempt).hash();before=session.incense;var names:float=session.names;answer=session.execute_for("shouxiang","borrow_god",{"unit_id":u.instance_id},"player");var paid_amount:float=before-session.incense;tick(3.1)
		check(answer.ok and near(paid_amount,12),"K5 Seed %d borrow actually pays twelve incense"%attempt)
		if event("borrow_success"):
			outcomes.success=true
			var god:Node2D=null
			for actor in sim.humans:
				if actor.growth.get("gray",false):god=actor
			check(god!=null and god.side=="xianghuo" and god.growth.gray_left>17 and session.names==names-1,"K5 Success creates an eighteen-second actual friendly deity");scene.get_node("BattleCamera").set_left(7680);await _shot("borrow-success-seed-%d"%attempt)
		else:
			outcomes.failure=true;check(event("borrow_backlash") and session.names==names-3 and not sim.targets.is_empty() and sim.targets[-1].unit_id=="G30","K5 Failure creates actual unregistered deity and extra two-name backlash");scene.get_node("BattleCamera").set_left(7680);await _shot("borrow-backlash-seed-%d"%attempt)
		if outcomes.size()==2:break
	check(outcomes.size()==2,"K5 Both seeded real borrow outcomes are reproducible without outcome override")
	_rig();u=human("H19");g=ghost("G01",114);var retainer=human("H22");growth._gray(g,u,10);answer=session.execute_for("shouxiang","fuse",{"first_id":g.instance_id,"second_id":retainer.instance_id,"recipe_id":"F05"},"player");check(answer.ok and not retainer.dead and not g.growth.temporary and growth.state.unlocks.F05,"K4 F05 makes borrowed gray permanent while retaining H22")
	u.growth.cooldowns.borrow_ghost=100;var enemy=ghost("G25",114);enemy.position=g.position;tick(.1);check(g.side=="yegui" and event("gray_recaptured"),"K5 Real nameless contact recaptures gray army after fusion")
	_rig("duoming");u=human("H17","post_gate_inner");d=sim.world.get_node("door_outer");d.set_durability(500);g=ghost("G12",49);before=session.incense;var npc:float=growth.state.npc_incense;tick(.1);check(event("seal_created") and near(session.incense,before) and growth.state.npc_incense<npc,"K8 Enemy auto-seal pays its own incense wallet, not player's")
	_rig("duoming");u=human("H17","post_gate_inner");d=sim.world.get_node("door_outer");d.set_durability(500);g=ghost("G12",49);growth.state.npc_incense=0;tick(.1);check(not event("seal_created"),"K8 Enemy with insufficient same-resource incense cannot cast free seals")
func actor(id:String)->Node2D:
	for u in sim.humans+sim.targets:
		if u.unit_id==id and not u.dead:return u
	return null
func _shot(id:String)->void:
	if not capture:return
	DirAccess.make_dir_recursive_absolute("res://docs/phase-reports/p7-shots")
	sim.queue_redraw()
	for unit in sim.humans+sim.targets:unit.queue_redraw()
	var layer=CanvasLayer.new();layer.layer=100;var badge=Label.new();badge.text="P7 构筑验收 / 已声明作者预设 / 共享真实战斗";badge.position=Vector2(20,1010);badge.add_theme_font_size_override("font_size",22);layer.add_child(badge);add_child(layer)
	await get_tree().process_frame
	RenderingServer.force_draw(true)
	var path="res://docs/phase-reports/p7-shots/"+id+".png"
	check(get_viewport().get_texture().get_image().save_png(path)==OK,"Actual native viewport capture "+id)
	shots.append(path);layer.free()
func _scenarios()->void:
	for id in Build.IDS:
		var only:=""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--scenario-only="):only=arg.trim_prefix("--scenario-only=")
		if only!="" and id!=only:continue
		if is_instance_valid(scene):scene.free()
		scene=preload("res://scenes/combat/Combat.tscn").instantiate();add_child(scene)
		sim=scene.get_node("Simulation");session=scene.get_node("Session")
		var scenario=Build.new();var started=scenario.start(scene,id);growth=session.growth
		check(started.ok,"K6/K7 Authored %s scenario validates and begins actual combat"%id)
		if not started.ok:continue
		check(Rules.REFERENCE_MAP_WIDTH_PX==9600 and Rules.UNIT_HEIGHT_PX==80 and scene.get_node("BattleCamera").zoom==Vector2.ONE,"K9 %s preserves base geometry, scale and camera"%id)
		var commands:Array=[]
		var target:Node2D
		match id:
			"chaodu":
				target=actor("H21");var raised=session.upgrade(target);check(raised.ok,"K6 Chaodu ritual reader buys a real survival upgrade")
				equip(target,"I17");equip(target,"Y01",0);equip(target,"Y03",1);equip(target,"N01");equip(actor("H01"),"I11")
				commands.append({"action":"upgrade_equip","target":"H21","items":["I17","Y01","Y03","N01"]})
				var response=session.start_ritual(target,actor("G12"));check(response.ok,"K6 Same I17 wearer starts paid reading on actual wet elite")
				commands.append({"action":"start_ritual","caster":"H21","target":"G12","ok":response.ok})
			"shoumen":
				equip(actor("H09"),"N01");equip(actor("H09"),"Y02");equip(actor("H17"),"I03")
				commands.append({"action":"equip","target":"H09/H17","items":["N01","Y02","I03"]})
			"pomen":
				target=actor("G12");equip(target,"I10");equip(target,"Y11");equip(target,"N01")
				commands.append({"action":"equip","target":"G12","items":["I10","Y11","N01"]})
			"dengmian":
				target=actor("H06");equip(target,"I04");equip(target,"Y10");equip(target,"N09")
				commands.append({"action":"equip","target":"H06","items":["I04","Y10","N09"]})
			"shangliang":
				target=actor("G09");equip(target,"I05");equip(target,"Y04");equip(target,"Y12",1);equip(target,"N11")
				commands.append({"action":"equip","target":"G09","items":["I05","Y04","Y12","N11"]})
			"wuce":
				target=actor("H23");equip(target,"I20");equip(target,"N06")
				var response=session.execute_for("shouxiang","borrow_god",{"unit_id":target.instance_id},"player")
				check(response.ok,"K7 Wuce starts actual paid seed-driven god bargain")
				commands.append({"action":"borrow_god","ok":response.ok})
		var safe:=true;var cover:=true;var layers:Dictionary={};var source_ok:=true;var inflow_lanes:Dictionary={}
		var feedback_shots:Dictionary={}
		var ambush_created:=false
		var max_seconds:float=180 if id in ["pomen","shangliang"] else 20
		Clock.set_paused(false)
		for step in int(max_seconds*60):
			if not session.running:break
			scenario.advance(1.0/60)
			if id=="shangliang" and not ambush_created and actor("G04")!=null:
				Clock.set_paused(true)
				var fusion=session.execute_for("duoming","fuse",{"first_id":target.instance_id,"second_id":actor("G04").instance_id,"recipe_id":"F01"},"player")
				check(fusion.ok,"K7 Shangliang performs actual paid F01 beam-ambush fusion after partner emerges from source queue")
				commands.append({"action":"fuse","recipe":"F01","ok":fusion.ok});ambush_created=fusion.ok;Clock.set_paused(false)
			if capture and (feedback_only or capture_events):
				var cues:Array=[]
				match id:
					"chaodu":
						if event("channel_guard"):cues.append("channel_guard")
						if event("ritual_release"):cues.append("ritual_release")
					"shoumen":
						if event("last_gate_hit"):cues.append("last_gate_hit")
					"pomen":
						if sim.world.get_node("door_outer").destroyed:cues.append("door_break")
						var lanes:Dictionary={}
						for u in sim.targets:
							if u.floor_id==0 and u.position.x>sim.world.get_node("door_outer").position.x:lanes[str(u.lane_index)]=true
						if lanes.size()>=2:cues.append("inflow")
					"dengmian":
						if event("light_fear"):cues.append("light_fear")
					"shangliang":
						for u in sim.targets:
							if u.growth.get("fusion_id","")=="F01" and u.floor_id>0 and growth.is_hidden(u):cues.append("upper_ambush");break
					"wuce":
						if event("borrow_success"):cues.append("borrow_success")
						if event("borrow_backlash"):cues.append("borrow_backlash")
				for cue in cues:
					if feedback_shots.has(cue):continue
					feedback_shots[cue]=sim.simulation_time
					var focus:float=sim.world.get_node("door_outer").position.x if id in ["shoumen","pomen"] else Rules.body_to_px(114)
					if id=="wuce":focus=actor("H23").position.x
					if id=="shangliang":
						for u in sim.targets:
							if u.growth.get("fusion_id","")=="F01" and u.floor_id>0:focus=u.position.x;break
					if id=="dengmian":focus=actor("H06").position.x
					scene.get_node("Decisions").close_panel()
					scene.get_node("BattleCamera").set_left(clampf(focus-960,0,7680))
					var before_time:float=sim.simulation_time
					get_window().size=Vector2i(1920,1080);await _shot("feedback-"+id+"-"+cue+"-1080")
					get_window().size=Vector2i(1280,720);await _shot("feedback-"+id+"-"+cue+"-720")
					check(near(sim.simulation_time,before_time),"Native feedback rendering never advances the actual simulation clock")
			if step%60==0:
				for u in sim.humans:
					safe=safe and sim.world.inside_base(u.position)
					if u.role=="ritual":cover=cover and not sim.world.is_open_court(u.position)
				for u in sim.targets:
					layers[str(u.floor_id)]=true
					if u.floor_id==0 and u.position.x>sim.world.get_node("door_outer").position.x:inflow_lanes[str(u.lane_index)]=true
				if id in ["pomen","shangliang"] and sim.simulation_time<1:
					for u in sim.targets:source_ok=source_ok and u.position.x<Rules.body_to_px(2)
		Clock.set_paused(true)
		var feedback:=false
		match id:
			"chaodu":
				var protected:Dictionary={};var released:Dictionary={}
				for e in growth.state.events:
					if e.kind=="channel_guard":protected[e.unit_id]=true
					if e.kind=="ritual_release":released[e.unit_id]=true
				feedback=protected.has(target.instance_id) and released.has(target.instance_id) and target.growth.slots.censer=="I17"
				check(feedback,"K6 Same I17 wearer is actually struck, keeps channel and completes elite purification")
			"shoumen":feedback=event("last_gate_hit") and event("seal_absorbed")
			"pomen":
				for e in sim.tide.milestones:
					if e.kind=="door_break":feedback=true
				feedback=feedback or sim.world.get_node("door_outer").destroyed
			"dengmian":feedback=event("light_fear")
			"shangliang":feedback=ambush_created and (layers.has("3") or layers.has("2") or layers.has("1"))
			"wuce":feedback=event("borrow_backlash") and actor("G30")!=null and session.names<=3
		check(feedback,"K6/K7 %s produces its required actual battle feedback"%id)
		check(safe and cover,"K9 %s sampled humans stay within base and ritual cover"%id)
		if id=="pomen":check(inflow_lanes.size()>=2 and inflow_lanes.size()<=4,"K6 Pomen actual post-breach influx occupies two to four lanes")
		if id in ["pomen","shangliang"]:check(source_ok,"K6/K7 %s timing begins at real tide source without contact teleport"%id)
		scene.get_node("BattleCamera").set_left(7680 if id in ["chaodu","dengmian","wuce","shangliang"] else 3200)
		var panel=scene.get_node("Decisions")
		if is_instance_valid(target) and not target.dead and not feedback_only:panel.select_unit(target)
		if not feedback_only:
			if capture:get_window().size=Vector2i(1920,1080)
			await _shot("build-"+id+"-1080")
		if capture and not feedback_only:
			get_window().size=Vector2i(1280,720);await _shot("build-"+id+"-720");get_window().size=Vector2i(1920,1080)
		var saved=scenario.finish_recording()
		check(saved.ok,"K10 %s actual growth commands and trajectory archive successfully"%id)
		builds.append({"id":id,"authored_initial_state":scenario.scenario,"commands":commands,"simulated_seconds":sim.simulation_time,"growth_events":growth.state.events.duplicate(true),"feedback_frames":feedback_shots,"tide_milestones":sim.tide.milestones.duplicate(true),"layers_observed":layers.keys(),"inflow_lanes":inflow_lanes.keys(),"base_safe":safe,"cover_safe":cover,"source_origin":source_ok if id in ["pomen","shangliang"] else false,"required_feedback":feedback,"archive_id":saved.get("id",""),"result":session.result.duplicate(true)})
		scenario.recording.stop()
		if saved.ok:await _disk_replay(str(saved.get("id","")),id)
func _extra_effects()->void:
	_rig();var u=human();var g=ghost();equip(u,"I09");session.incense=20;u.receive_damage(1);unequip(u,"censer");growth.state.inventory.I09=1;equip(u,"I09");var before:float=session.incense;u.receive_damage(1);check(near(session.incense,before) and u.growth.charges.I09==1,"I09 Same physical returned item retains cooldown and use count after equip","I09")
	_rig();u=human();g=ghost("G12",114);equip(u,"I17");session.start_ritual(u,g);u.brain.channel.advance(sim,u,1);u.receive_damage(1,g);tick(.02,true);check(u.brain.channel.active,"I17 Shared Simulation step keeps guarded damage_revision consistent","I17")
	_rig("duoming");g=ghost("G09",10);g.motion_enabled=true;equip(g,"N02");var start:Vector2=g.position;g.brain.advance(.1);var fast:float=g.position.distance_to(start);unequip(g,"nameplate");g.position=start;g.brain.advance(.1);check(near(fast/g.position.distance_to(start),1.12),"N02 Actual GhostBrain step travels twelve percent farther","N02")
	_rig("duoming");g=ghost("G09",90);equip(g,"N11");g.motion_enabled=true;g.brain.stage="descend";g.floor_id=2;var destination=Vector2(Rules.body_to_px(sim.tide.config.descent.to_x),sim.world.floor_y(int(sim.tide.config.descent.to_floor))+sim.tide.config.lane_offsets[g.lane_index]);g.position=destination;g.brain.advance(.1);check(near(g.brain.landing_left,Data.traits.jing_xian.landing_seconds*.5),"N11 Genuine descent applies half-duration landing weakness","N11")
	_rig("duoming");g=ghost("G12",49);var other=ghost("G20",49);var answer=session.execute_for("duoming","fuse",{"first_id":g.instance_id,"second_id":other.instance_id,"recipe_id":"F02"},"player");var d=sim.world.get_node("door_outer");before=d.durability;growth.charge(g,d);tick(1.6);check(answer.ok and event("charge_hit") and d.durability<before,"K4 F02 actual merged palanquin completes windup and hits a real door")
	_rig("duoming");g=ghost("G11",0);other=ghost("G04",0);before=session.incense;answer=session.execute_for("duoming","fuse",{"first_id":g.instance_id,"second_id":other.instance_id,"recipe_id":"F03","material_id":"H06"},"player");check(not answer.ok and not other.dead and session.incense==before and "H06" in growth.state.materials,"K4 Invalid F03 extra partner is rejected atomically")
	_rig("duoming");g=ghost("G01",0);before=session.incense;answer=session.execute_for("duoming","mutate_form",{"unit_id":g.instance_id,"form_id":"V05"},"player");check(not answer.ok and session.incense==before and g.unit_id=="G01","K3 Locked V05–V07 interface cannot transform or spend")
	_rig();u=human();check(equip(u,"I20") and u.growth.slots.censer=="I20" and not growth.has(u,"I20"),"S1 I20 remains an equipable occupied slot with explicitly inactive effect")
func _budget_behavior()->void:
	_rig();var u=human("H21");session.incense=20;tick(20)
	check(near(session.incense,20) and not u.growth.statuses.has("light_field"),"G1 Auto light never drains incense when no enemy can be affected")
	var g=ghost("G01",114);var before:float=session.incense;tick(.1)
	check(near(session.incense,before) and not u.growth.statuses.has("light_field"),"G1 River-light caster never pays merely to reveal an already visible dry enemy")
	g.growth.environment.water=true;tick(.1)
	check(u.growth.statuses.has("light_field") and near(before-session.incense,u.skill_cost) and g.growth.statuses.has("water_slow"),"G1 River light pays declared cost only when a real wet enemy receives slowdown")
	_rig();u=human("H27");session.incense=20;g=ghost("G01",114);tick(10)
	check(near(session.incense,20),"G1 Reveal-only caster never consumes repair budget against ordinary visible ghosts")
	g=ghost("G04",114);tick(.1)
	check(session.incense<20 and g.growth.statuses.has("revealed"),"G1 Reveal-only caster really spends and exposes an actual hidden ghost")
func _observer_growth()->void:
	for kind in ["watch","duel_shouxiang","duel_duoming"]:
		if is_instance_valid(scene):scene.free()
		scene=preload("res://scenes/combat/Combat.tscn").instantiate();add_child(scene)
		sim=scene.get_node("Simulation");session=scene.get_node("Session");session.running=false
		var config:Dictionary=Data.mode_rules.defaults.duplicate(true)
		config.kind="watch" if kind=="watch" else "duel";config.player_seat="duoming" if kind=="duel_duoming" else "shouxiang"
		config.seed="P7-SHARED-"+kind;config.duration=180;config.incense={"shouxiang":40,"duoming":40};config.growth_enabled=true;config.growth_template="gate_beam"
		config.ghosts=[{"id":"G01","count":12},{"id":"G09","count":1},{"id":"G12","count":1}]
		var observer=load("res://src/modes/ObservationSession.gd").new();var answer=observer.start(scene,config);growth=session.growth
		check(answer.ok and growth.enabled,"G1 Shared %s enters the real growth simulator"%kind)
		if not answer.ok:continue
		var gate=actor("H09");check(gate!=null and gate.growth.get("slots",{}).get("nameplate","")=="N01" and gate.max_hp>float(Data.get_unit("H09")["生命"]),"G1 %s actual template plate changes a spawned actor"%kind)
		var panel=scene.get_node("Decisions");panel.select_unit(gate);var money:float=session.incense_for("shouxiang")
		if kind=="watch":check(not session.execute_for("shouxiang","unequip_item",{"unit_id":gate.instance_id,"slot":"nameplate"},"player").ok and near(session.incense_for("shouxiang"),money),"G1 Watch full-card inspection cannot issue equipment commands")
		var base_safe:=true;var ritual_safe:=true
		Clock.set_paused(false)
		for step in (7200 if kind=="watch" else 1200):
			if not session.running:break
			observer.advance(1.0/60)
			if step%60==0:
				for u in sim.humans:
					base_safe=base_safe and sim.world.inside_base(u.position)
					if u.role=="ritual":ritual_safe=ritual_safe and not sim.world.is_open_court(u.position)
		check(sim.simulation_time>=120-.000001 if kind=="watch" else sim.simulation_time>=20-.000001,"G1 %s growth mode advances actual shared AI combat"%kind)
		check(base_safe and ritual_safe,"K9 Shared growth %s maintains in-base actors and ritual cover"%kind)
		if kind=="watch":
			var paid:Dictionary={"shouxiang":0,"duoming":0}
			for action in observer.recording.actions:
				if action.action in ["purchase","repair","upgrade","mutate_form","reinforce","start_ritual"]:paid[action.seat]+=1
			check(paid.shouxiang>0 and paid.duoming>0,"G1 Growth watch contains actual paid AI decisions on both seats")
		Clock.set_paused(true)
		scene.get_node("BattleCamera").set_left(7680)
		await _shot("shared-"+kind+"-growth-1080")
		var receipt=observer.finish_recording();check(receipt.ok,"G1 %s growth mode records its genuine shared trajectory"%kind)
		if receipt.ok:await _disk_replay(str(receipt.get("id",receipt.get("archive_id",""))),"shared-"+kind)
		shared_modes.append({"kind":kind,"config":config,"simulated_seconds":sim.simulation_time,"status":observer.status(),"growth_events":growth.state.events.duplicate(true),"base_safe":base_safe,"ritual_safe":ritual_safe,"archive_id":receipt.get("id","")})
		observer.recording.stop()
func _disk_replay(id:String,label:String)->void:
	var loaded:Dictionary=Archive.load_record(id);check(loaded.ok,"K10 "+label+" actual growth archive reloads from isolated disk")
	if not loaded.ok:return
	var value=preload("res://scenes/combat/Combat.tscn").instantiate();add_child(value);value.get_node("Simulation").set_physics_process(false)
	var player=load("res://src/replay/ReplayPlayer.gd").new();var answer=player.start(value,loaded.record);check(answer.ok,"K10 "+label+" growth archive starts a clean replay")
	if answer.ok:
		for step in loaded.record.steps.size()+120:
			if player.done:break
			player.advance(1.0/60)
		check(player.done and player.verified and player.error.is_empty(),"K10 "+label+" disk replay preserves growth effects, events and terminal fingerprint")
		if not player.verified:
			FileAccess.open("/tmp/ye-ci-p7-replay-"+label+"-expected.json",FileAccess.WRITE).store_string(JSON.stringify(loaded.record,"\t"))
			FileAccess.open("/tmp/ye-ci-p7-replay-"+label+"-actual.json",FileAccess.WRITE).store_string(JSON.stringify({"status":player.status(),"fingerprint":load("res://src/replay/BattleRecord.gd").fingerprint(value),"events":load("res://src/replay/BattleRecord.gd").key_events(value)},"\t"))
	value.free()
