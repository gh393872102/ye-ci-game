extends SceneTree
## Authored isolated fixtures exercise the real P8 runtime, never a completed-night claim.
var D
var C
var R
var combat:Node
var sim:Node
var session:Node
var engine:RefCounted
var checks:=0
var failures:Array[String]=[]
var evidence:Array[Dictionary]=[]
var prefix:="p8-ghost"
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String,id:String)->void:
	checks+=1;evidence.append({"id":id,"label":label,"passed":value,"fixture":true})
	if not value:failures.append(label);print("FAIL ",id," ",label)
func reset(mode:="shouxiang")->void:
	session.enter_debug();session.rules=D.battle_rules.duplicate(true);session.start_battle(mode)
	for unit in sim.humans+sim.targets+sim.corpses+sim.projectiles:unit.free()
	sim.humans.clear();sim.targets.clear();sim.corpses.clear();sim.projectiles.clear();sim.tide.pending.clear();sim.tide.config.waves=[];sim.tide.wave_index=0
	session.incense=100;session.names=12
	session.configure_roster("p8-ghost-fixtures");engine=session.roster
	C.set_paused(true)
func human(id:="H01",x:=114.0,floor_id:=0)->Node2D:
	var unit=sim.spawn_human(id,"post_register");unit.position=Vector2(R.body_to_px(x),sim.world.floor_y(floor_id));unit.floor_id=floor_id
	unit.attacks_enabled=false;unit.motion_enabled=false;engine.ensure(unit);return unit
func ghost(id:String,x:=112.0,floor_id:=0)->Node2D:
	var unit=sim.tide.spawn(id,3,R.body_to_px(x));unit.position=Vector2(R.body_to_px(x),sim.world.floor_y(floor_id));unit.floor_id=floor_id
	unit.attacks_enabled=false;unit.motion_enabled=false;engine.ensure(unit);return unit
func skill(unit:Node2D,target:Node2D=null,args:Dictionary={})->Dictionary:
	if target!=null:args.target_id=target.instance_id
	return engine.cast(unit,args)
func has_status(unit:Node2D,id:String)->bool:return unit.roster.statuses.has(id) or unit.growth.statuses.has(id)
func event_count(kind:String)->int:
	var found:=0
	for event in sim.events:
		if event.kind=="roster_"+kind:found+=1
	return found
func run()->void:
	await process_frame
	D=root.get_node("Data");C=root.get_node("Clock");R=root.get_node("Rules")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-prefix="):prefix=arg.trim_prefix("--report-prefix=")
	combat=load("res://scenes/combat/Combat.tscn").instantiate();root.add_child(combat)
	sim=combat.get_node("Simulation");sim.set_physics_process(false);session=combat.get_node("Session")
	check(D.errors.is_empty(),"all source identities and callable scripts pass boot","catalog")
	for number in range(1,33):
		reset();var id:="G%02d"%number;var actor=ghost(id)
		check(actor!=null and not actor.roster.is_empty() and D.roster_rules.abilities.has(id),"spawn with real source profile and enabled runtime",id)
	reset();var g=ghost("G01",49);g.attacks_enabled=true;var gate=sim.world.get_node("door_outer");var solo:float=sim.tide.door_bonus(g,gate)
	var crowd1=ghost("G01",49.2);var crowd2=ghost("G01",49.4);crowd1.attacks_enabled=true;crowd2.attacks_enabled=true;sim._update_units()
	check(sim.tide.door_bonus(g,gate)>solo,"actual shared door attack multiplier increases with crowd","G01")
	var h=human("H01");check(engine.ritual_duration(h,g,4)<4,"faceless tide has lower genuine reading resistance","G01")
	reset();h=human("H01",116);g=ghost("G02",114)
	var funds:float=session.incense;var npc:float=session.incense_for("duoming")
	check(skill(g).ok and session.incense<funds and session.incense_for("duoming")>npc,"begging transfers actual opposing incense near register","G02")
	g.hp=g.max_hp*.3
	check(engine.ritual_duration(h,g,4)<4,"low health makes begging ghost easier to purify","G02")
	reset();h=human("H09",110);g=ghost("G03",112)
	var defense:float=engine.defense_for(h,h.defense);check(skill(g,h).ok and engine.defense_for(h,h.defense)<defense,"cry really lowers enemy defense","G03")
	engine.cooldown(g,0);session.growth.state.ritual_flag="jinsheng";var hp:float=g.hp;skill(g,h)
	check(g.hp<hp,"silenced cry damages its actual caster","G03")
	reset();h=human("H01",110);g=ghost("G04",112);engine.ghosts.advance(g,.1)
	check(session.growth.is_hidden(g),"unlit wall approach actually becomes hidden","G04")
	session.growth.apply_light(h,3,.2);engine.ghosts.advance(g,.1)
	check(not session.growth.is_hidden(g),"real light reveals and prevents immediate re-hide","G04")
	reset();g=ghost("G05",110);g.hp-=10;g.motion_enabled=true;h=human("H01",108);h.receive_damage(999,g)
	sim.humans.erase(h);sim.corpses.append(h);var start_x:float=g.position.x;hp=g.hp
	check(skill(g).ok,"hungry ghost acquires real fallen unit","G05")
	for step in range(60):engine.ghosts.advance_actor(g,.1)
	check(g.position.x<start_x and g.hp>hp and bool(h.roster.get("eaten",false)),"hungry ghost diverts backward and consumes remains to recover","G05")
	reset();h=human("H01",116);var target=ghost("G01",114);g=ghost("G06",112)
	check(session.start_ritual(h,target).ok and h.brain.channel.active,"fixture starts real paid register reading","G06")
	check(skill(g,h).ok and not h.brain.channel.active,"five-body claw interrupts actual distant reader","G06")
	for hit in range(3):sim.deal_damage(h,g,"melee")
	check(float(g.roster.ghost.get("arm_disabled",0))>0,"repeated real strikes temporarily disable claw","G06")
	reset();g=ghost("G07",45);g.motion_enabled=true
	var window_trace:Array=[]
	for step in range(400):
		sim.advance(.1)
		if step%10==0:window_trace.append({"time":sim.simulation_time,"position":[g.position.x,g.position.y],"floor":g.floor_id})
		if g.floor_id>0:break
	evidence.append({"id":"G07","fixture":true,"window_trace":window_trace})
	check(g.floor_id>0,"narrow-window route actually reaches upper floor","G07")
	var hit_front_gate:=false
	for entry in sim.damage_log:
		if entry.attacker==g.instance_id and entry.target=="door_outer":hit_front_gate=true
	check(not hit_front_gate,"window ghost does not attack the front door","G07")
	reset();h=human("H01",116);g=ghost("G08",114);session.start_ritual(h,g);hp=h.hp
	g.receive_damage(999,h)
	check(h.hp<hp and not h.brain.channel.active,"real lethal hit explodes and interrupts nearby reading","G08")
	var after_hp:float=h.hp;engine.ghosts.on_death(g,h);engine.ghosts.ritual_completed(h,g)
	check(h.hp==after_hp and event_count("scatter_incense")==1,"death and purification callbacks cannot explode twice","G08")
	reset();g=ghost("G09",87.2);g.motion_enabled=true
	for step in range(150):sim.advance(.1)
	check(g.floor_id>0 and g.position.y<sim.world.floor_y(0),"hanged ghost follows real rope/beam route","G09")
	reset();h=human("H01",110);g=ghost("G10",112);session.growth.state.environments=[{"id":"fixture_water","kind":"water","from_body":109,"to_body":113,"floor_id":0}]
	var x:float=h.position.x;hp=h.hp
	check(skill(g,h).ok and h.position.x!=x and h.hp<hp and has_status(h,"drag"),"authored water fixture has real drag displacement damage and interruption","G10")
	var water_speed:float=engine.speed_multiplier(g,session.growth.speed_multiplier(g));session.growth.state.environments=[]
	check(engine.speed_multiplier(g,session.growth.speed_multiplier(g))<water_speed,"water ghost is genuinely slower on land","G10")
	reset();h=human("H01",110);h.roster.face_state="faceless";g=ghost("G11",112);hp=h.hp
	check(skill(g,h).ok and has_status(h,"revealed") and h.hp<hp,"bone lantern reveals and actually burns vulnerable faceless target","G11")
	reset();g=ghost("G12",48);g.attacks_enabled=true;gate=sim.world.get_node("door_outer");var before:float=gate.durability
	sim.deal_damage(g,gate,"structure");var ram_damage:float=before-gate.durability
	var white=ghost("G01",48);before=gate.durability;sim.deal_damage(white,gate,"structure")
	check(ram_damage>before-gate.durability,"real strength corpse door strike beats ordinary tide","G12")
	reset();h=human("H09",105);g=ghost("G13",102);var partner=ghost("G13",101);g.motion_enabled=true;partner.motion_enabled=true;hp=h.hp;x=h.position.x
	check(skill(g,h).ok and partner.roster.ghost.has("charge"),"paired sedan begins genuine charge for both actors","G13")
	for step in range(30):engine.ghosts.advance_actor(g,.1);engine.ghosts.advance_actor(partner,.1)
	check(h.hp<hp and h.position.x!=x,"paired charge collides and displaces actual defenders","G13")
	partner.receive_damage(999,h)
	check(has_status(g,"disorder"),"surviving sedan actor becomes disordered after partner dies","G13")
	reset();h=human("H01",110);var friend=human("H09",110.8);g=ghost("G14",112);hp=friend.hp
	check(skill(g,h).ok and has_status(h,"charm"),"wedding applies real charm via shared resistance path","G14")
	session.growth.advance(.1)
	check(friend.hp<hp,"charmed human really attacks former friend","G14")
	reset();g=ghost("G15",112);partner=ghost("G12",112.8)
	check(skill(g).ok and has_status(partner,"cloth"),"tailor supplies real ally damage-reduction cloth","G15")
	reset();h=human("H01",110);g=ghost("G15",112)
	check(skill(g,h).ok and has_status(h,"slow"),"tailor cannot clothe named human and applies slow instead","G15")
	reset();h=human("H09",110);g=ghost("G16",112);partner=ghost("G01",112.8)
	check(skill(g,h).ok and has_status(partner,"focus") and partner.roster.statuses.focus.target_id==h.instance_id,"warrant redirects actual allied priority toward named target","G16")
	reset();g=ghost("G17",96)
	check(skill(g,null,{"path_id":"stair_main"}).ok and engine.path_broken("stair_main"),"mountain ghost breaks a real authored stair path","G17")
	var route:Array=sim.world.navigation.route(Vector2(R.body_to_px(96),sim.world.floor_y(0)),0,Vector2(R.body_to_px(103.5),sim.world.floor_y(2)),2,true)
	var traverses_broken:=false
	for step in route:
		if bool(step.get("stair",false)) and int(step.floor)==2 and step.point.distance_to(Vector2(R.body_to_px(103.5),sim.world.floor_y(2)))<.1:traverses_broken=true
	check(not traverses_broken,"broken stair is excluded by shared navigation","G17")
	reset();h=human("H01",110);g=ghost("G18",112);g.roster.ghost={"weak_part":1};g.hp=10
	g.receive_damage(999,h,"melee");check(not g.dead,"wrong parade part cannot deliver final defeat","G18")
	g.receive_damage(999,h,"bolt");check(g.dead,"actual vulnerable part accepts final defeat","G18")
	reset();h=human("H20",110);g=ghost("G19",112);hp=h.hp
	check(skill(g,h).ok and h.hp<hp and str(g.roster.ghost.get("copied_id",""))=="H20","mirror guest copies a real burning active skill","G19")
	var reflected:float=engine.before_receive(g,10,h,"reflection");var normal:float=engine.before_receive(g,10,h,"melee")
	check(reflected>normal,"mirror reflection genuinely punishes mirror guest","G19")
	reset();h=human("H32",110);g=ghost("G19",112);hp=g.hp
	check(skill(h,h).ok,"face-crafter fixture uses real protective face skill","G19")
	engine.ghosts.advance(g,.1)
	check(g.hp<hp,"mirror guest genuinely collapses before face-crafter mask","G19")
	reset();h=human("H09",105);g=ghost("G20",102);g.motion_enabled=true;hp=h.hp;x=h.position.x
	check(skill(g,h).ok,"rider begins real main-road charge","G20")
	for step in range(30):engine.ghosts.advance_actor(g,.1)
	check(h.hp<hp and h.position.x!=x,"rider charge hits and pushes actual defender","G20")
	reset();g=ghost("G20",110);g.growth.environment.water=true
	check(skill(g).ok and has_status(g,"stun"),"rider actually falls in water lane","G20")
	reset();h=human("H09",110);g=ghost("G21",112)
	check(skill(g,h).ok and has_status(h,"stun"),"bell mouth causes real area stun","G21")
	engine.cooldown(g,0);session.growth.state.ritual_flag="jinsheng";hp=g.hp;skill(g,h)
	check(g.hp<hp,"silenced bell mouth suffers real backlash","G21")
	reset();h=human("H01",110);g=ghost("G22",112)
	check(skill(g,h).ok and not engine.can_act(h),"womb dream actually blocks actions","G22")
	engine.status(h,"revealed",3,g);engine.ghosts.advance_world(.1)
	check(not has_status(h,"dream") and engine.can_act(h),"real light awakening ends dream","G22")
	reset();h=human("H01",110);g=ghost("G23",112);var attack:float=g.attack;var names:float=session.names
	for hit in range(12):
		if not h.dead:sim.deal_damage(g,h,"melee")
	check(h.dead and g.attack>attack and session.names<names,"actual named human defeat grows face borrower and steals real names","G23")
	names=session.names;engine.ghosts.ritual_completed(h,g)
	check(session.names>names,"purification releases actually stolen names","G23")
	reset();h=human("H09",50);g=ghost("G24",52);gate=sim.world.get_node("door_outer");gate.set_durability(800);h.brain.repair_door=gate
	check(skill(g,h).ok and h.brain.repair_door==null,"servant explicitly targets and interrupts real repairer","G24")
	reset()
	# Explicit already-breached front-line fixture; the large servant must use stairs.
	for door_id in ["door_outer","door_inner","door_hall"]:sim.world.get_node(door_id).set_durability(0)
	g=ghost("G24",90);g.motion_enabled=true;g.attacks_enabled=true
	var gallery_hit:=false
	for step in range(500):
		sim.advance(.1)
		for entry in sim.damage_log:
			if entry.attacker==g.instance_id and entry.target in ["door_gallery","door_incense"]:gallery_hit=true
		if gallery_hit:break
	var front_hit:=false
	for entry in sim.damage_log:
		if entry.attacker==g.instance_id and entry.target in ["door_outer","door_inner"]:front_hit=true
	evidence.append({"id":"G24","fixture":true,"final_position":[g.position.x,g.position.y],"floor":g.floor_id,"stage":g.brain.stage,"priority":g.roster.ghost.get("priority_structure",""),"damage_targets":sim.damage_log.map(func(entry):return entry.target)})
	var used_window:=false
	for entry in sim.events:
		if entry.unit==g.instance_id and entry.kind in ["roster_window_route_started","roster_window_entered"]:used_window=true
	check(gallery_hit and not front_hit and not used_window and event_count("side_access_entered")>0,"large servant walks actual wide stairs to attack side door, never a window","G24")
	reset();h=human("H01",110);g=ghost("G25",112);names=session.names
	check(skill(g,h).ok and has_status(h,"nameless") and session.names<names,"clerk erases an actual named actor and drains names","G25")
	reset();h=human("H01",110);g=ghost("G26",112);skill(g,h)
	check(engine.ghosts.name_reward(h,g,1)==0 and engine.ghosts.heal_modifier(h,10,h)==0,"blank page blocks actual local ritual name reward and recovery","G26")
	reset();h=human("H01",116);g=ghost("G26",114);session.names=5
	skill(g,h);var before_names:float=session.names;var before_funds:float=session.incense
	check(session.start_ritual(h,g).ok and session.incense<before_funds,"blank-page self-purification starts through actual paid command","G26")
	h.brain.channel.advance(sim,h,10)
	check(h.brain.channel.completions==1 and (g.dead or g.growth.gray) and session.names==before_names,"paid purification of active blank page itself earns zero names","G26")
	reset();h=human("H09",110);g=ghost("G27",112);skill(g,h);hp=h.hp;var ghost_hp:float=g.hp
	check(engine.ghosts.heal_modifier(h,10,h,false)==0 and h.hp==hp and g.hp==ghost_hp,"recovery preview never emits actual poison damage","G27")
	engine.heal(h,10,h)
	check(h.hp<hp and g.hp<ghost_hp,"reverse incense recovery becomes smoke that harms both sides","G27")
	reset();h=human("H01",110);g=ghost("G28",112)
	check(skill(g,h).ok and h.roster.face_state=="faceless" and has_status(g,"held_face"),"face theft changes real face interface and empowers holder","G28")
	reset();h=human("H18",110);g=ghost("G28",112)
	check(skill(h).ok and skill(g,h).ok and h.roster.face_state=="faced" and g.roster.face_state=="faceless","actual gold mirror reflects targeted face-theft status","G28")
	reset();h=human("H01",110);g=ghost("G29",112)
	check(skill(g,h).ok and h.side=="yegui" and h in sim.targets,"misrecord really switches allegiance and simulation group","G29")
	engine.ghosts.advance_world(3.1)
	check(h.side=="xianghuo" and h in sim.humans and has_status(h,"stun"),"misrecord expiry restores original side and leaves stun","G29")
	reset("duoming");h=human("H18",110);g=ghost("G29",112)
	skill(h);var recorded:Array=[]
	session.command_applied.connect(func(seat,action,args,origin):recorded.append(action))
	var reflected_cast:Dictionary=session.execute_for("duoming","unit_skill",{"unit_id":g.instance_id,"target_id":h.instance_id},"player")
	check(reflected_cast.ok and g.side=="xianghuo" and g in sim.humans and h.side=="xianghuo" and float(g.roster.cooldowns.get("skill",0))>0 and "unit_skill" in recorded,"actual mirror-reflected misrecord succeeds, cools down and records changed source allegiance","G29")
	engine.ghosts.advance_world(3.1)
	check(g.side=="yegui" and g in sim.targets and has_status(g,"stun"),"reflected misrecord restores source original side after real temporary change","G29")
	reset();h=human("H05",110);g=ghost("G29",112)
	var immune:Dictionary=skill(g,h)
	check(immune.ok and h.side=="xianghuo" and float(g.roster.cooldowns.get("skill",0))>0,"immune target still consumes successful misrecord cast and cooldown","G29")
	reset();h=human("H19",116);g=ghost("G30",114)
	var borrowed:Dictionary=session.execute_for("shouxiang","borrow_god",{"unit_id":h.instance_id},"player");hp=h.hp;names=session.names
	check(borrowed.ok and skill(g,h).ok and h.hp<hp and session.names<names,"false god punishes a real nearby borrowing invocation","G30")
	reset();h=human("H01",110);g=ghost("G31",112);before=g.max_hp
	check(skill(g,h).ok and g.max_hp>before and int(g.roster.ghost.layers)>0,"stolen real name creates real flesh layer","G31")
	check(engine.ghosts.ritual_completed(h,g) and g.max_hp==before and int(g.roster.ghost.layers)==0,"protected purification visibly collapses layers and preserves core","G31")
	reset();h=human("H03",110);g=ghost("G31",112);engine.ghosts.add_layers(g,3);before=g.max_hp
	check(skill(h,g).ok and int(g.roster.ghost.layers)==0 and g.max_hp<before,"actual paid naming skill collapses enemy name layers","G31")
	reset();h=human("H01",116);g=ghost("G32",114)
	check(session.start_ritual(h,g).ok,"boss fixture begins real paid protected reading","G32")
	h.brain.channel.advance(sim,h,10)
	check(not g.dead and float(g.roster.ghost.get("naming_left",0))>0,"completed protected reading opens real naming window instead of deleting boss","G32")
	check(session.start_ritual(h,g).ok,"naming window permits second real ritual","G32");h.brain.channel.advance(sim,h,10)
	check(g.dead,"second protected completion in naming window purifies boss","G32")
	reset();g=ghost("G20",112)
	var valid:Dictionary=g.roster.duplicate(true);valid.ghost={"charge":{"target_id":"world:door_outer","left":1,"push":1,"multiplier":1.8}}
	check(engine.ghosts.valid_state(valid),"valid nested ghost charge state accepted","validation")
	valid.ghost.charge.target_id="world:."
	check(not engine.ghosts.valid_state(valid),"wrong-node ghost charge rejected before restore","validation")
	valid=g.roster.duplicate(true);valid.statuses.misrecord={"left":2,"original_side":[],"restore_left":2,"end_stun":1,"source_id":"x"}
	check(not engine.ghosts.valid_state(valid),"malformed allegiance restore contract rejected","validation")
	reset("duoming");g=ghost("G12",49);partner=ghost("G20",49.4);gate=sim.world.get_node("door_outer")
	var fusion:Dictionary=session.execute_for("duoming","fuse",{"first_id":g.instance_id,"second_id":partner.instance_id,"recipe_id":"F02"},"player")
	sim.advance(.1)
	check(fusion.ok and g.growth.has("charge_job"),"P8 roster preserves real P7 gate-rider fusion charge task","compatibility")
	for unsupported_id in ["H01","H02","H04","H11","H15","H25","H28","H30","H31"]:
		reset();h=human(unsupported_id,110);g=ghost("G19",112)
		var inventory_before:Dictionary=session.growth.state.inventory.duplicate(true)
		var wallet_before:float=session.incense
		var copied:Dictionary=skill(g,h,{"confirm_market":true})
		check(not copied.ok and str(copied.reason)=="P8_COPY_UNSUPPORTED" and session.growth.state.inventory==inventory_before and session.incense==wallet_before and not g.roster.counters.get("market_used",false),"unsupported mirror source "+unsupported_id+" explicitly rejects without resource or market side effects","G19")
	var report:={"suite":"P8Ghost","checks":checks,"failures":failures,"fixture_only":true,"evidence":evidence}
	var path:="res://docs/phase-reports/"+prefix+"-test-results.json";var output=FileAccess.open(path,FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t")+"\n")
	print("P8Ghost RESULT: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
