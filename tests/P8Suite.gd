extends Node
## P8 fixtures declare their starting positions/resources. They exercise the shared
## battle and real commands; they are not ordinary whole-night timing evidence.
const Archive = preload("res://src/replay/ReplayArchive.gd")
const Codex = preload("res://src/progression/CodexStore.gd")
const Appearance = preload("res://src/units/UnitAppearance.gd")
const PAIRS = [["H01","H02","祝"],["H10","H16","卫"],["H17","H20","符"],["H09","H14","盾"],["G04","G09","上楼"],["G12","G13","破门"],["G25","G28","无册吏"],["G17","G20","大形"]]
const TAGS = ["香火","名面","破门","上楼","水巷","灯","符","金","哭","无册","超度","机关"]
var checks := 0
var failures := 0
var rows: Array[Dictionary] = []
var effects: Dictionary = {}
var shots: Array[String] = []
var capture := false
var prefix := "p8"
var scene: Node2D
var sim: Node2D
var session: Node
var roster: RefCounted
var serial := 0
var card_rows: Array[Dictionary] = []
var codex: RefCounted
var trajectories: Array[Dictionary] = []
var night_failure: Dictionary = {}
var appearance_audit: Array[Dictionary] = []
var ritual_completion_fixture: Dictionary = {}

func _ready() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-prefix="): prefix = arg.trim_prefix("--report-prefix=")
	Archive.directory = "/tmp/ye-ci-p8-acceptance-render-archives" if capture else "/tmp/ye-ci-p8-acceptance-test-archives"
	codex = Codex.new("/tmp/ye-ci-p8-codex-%s-%d.json" % ["render" if capture else "test",OS.get_process_id()],false)
	Data.set("codex_store",codex)
	_run.call_deferred()

func check(ok: bool, label: String, id := "") -> void:
	checks += 1
	rows.append({"check":label,"passed":ok,"unit_id":id})
	if not ok: failures += 1
	if not id.is_empty(): effects[id] = bool(effects.get(id,true)) and ok
	print(("PASS " if ok else "FAIL ") + label)

func near(a: float, b: float, tolerance := .001) -> bool:
	return absf(a-b) <= tolerance

func rig(mode := "shouxiang", initial: Dictionary = {}) -> void:
	if is_instance_valid(scene): scene.free()
	scene = preload("res://scenes/combat/Combat.tscn").instantiate()
	add_child(scene)
	sim = scene.get_node("Simulation")
	sim.set_physics_process(false)
	session = scene.get_node("Session")
	session.running = false
	session.start_battle(mode)
	for unit in sim.humans + sim.targets + sim.corpses + sim.projectiles: unit.free()
	sim.humans.clear(); sim.targets.clear(); sim.corpses.clear(); sim.projectiles.clear()
	sim.tide.pending.clear(); sim.tide.config.waves=[]; sim.tide.wave_index=0
	session.incense=60; session.names=8
	session.configure_growth("P8-isolated-%d" % serial,initial)
	session.call("configure_roster","P8-isolated-%d" % serial)
	serial += 1
	roster = session.get("roster")
	Clock.set_paused(true); Clock.set_speed(1)

func human(id := "H01", post := "post_register", still := true) -> Node2D:
	var unit = sim.spawn_human(id,post)
	if unit == null: return null
	unit.position = sim.post_destination(unit,post)
	unit.brain.settled_position = unit.position
	unit.attacks_enabled = not still; unit.motion_enabled = not still
	return unit

func ghost(id := "G01", x := 114.0, still := true) -> Node2D:
	var unit = sim.tide.spawn(id,0,Rules.body_to_px(x))
	if unit == null: return null
	unit.attacks_enabled = not still; unit.motion_enabled = not still
	return unit

func skill(unit: Node2D, args: Dictionary = {}, seat := "shouxiang") -> Dictionary:
	var command := args.duplicate(true)
	command.unit_id = unit.instance_id
	return session.execute_for(seat,"unit_skill",command,"player")

func tick(seconds: float) -> void:
	for index in ceili(seconds*60): sim.advance(1.0/60)

func hit(attacker: Node2D, victim: Node2D, amount := 10.0, kind := "melee") -> float:
	var before: float = victim.hp if victim.is_in_group("units") else victim.durability
	sim.deal_damage(attacker,victim,kind,amount)
	return before - (victim.hp if victim.is_in_group("units") else victim.durability)

func event(kind: String, unit_id := "") -> bool:
	for entry in sim.events:
		if entry.kind == "roster_"+kind and (unit_id.is_empty() or str(entry.unit) == unit_id): return true
	return false

func _lamp_frame() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1920,1080)
	rig("shouxiang",{"defense_objective":"hold_register","inventory":{"I08":1}})
	var caster := human("H19")
	var foe := ghost("G01",115)
	foe.position = caster.position - Vector2(96,0)
	foe.floor_id = caster.floor_id
	session.execute_for("shouxiang","equip_item",{"unit_id":caster.instance_id,"item_id":"I08"},"player")
	var cast: Dictionary = skill(caster,{"target_id":foe.instance_id})
	var camera := scene.get_node("BattleCamera")
	camera.make_current()
	camera.set_left(caster.position.x-960)
	sim.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	var center: Vector2i = foe.get_global_transform_with_canvas().origin - Vector2(0,108)
	session.growth.state.fields = session.growth.state.fields.filter(func(f): return f.kind != "lamp_reveal")
	sim.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var control := get_viewport().get_texture().get_image()
	var changed := 0
	for y in range(center.y-30,center.y+30):
		for x in range(center.x-30,center.x+30):
			if shot.get_pixel(x,y) != control.get_pixel(x,y): changed += 1
	var ok: bool = cast.ok and changed > 100 and shot.get_size()==Vector2i(1920,1080) and shot.save_jpg("/tmp/r9-lamp.jpg",0.86)==OK
	print("Lamp ring differential pixels ",changed,"; target ",center,"; validated ",ok)
	scene.free()
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0 if ok else 1)

func _drum_reach(frame := false) -> void:
	rig("shouxiang",{"inventory":{"I07":1}})
	var guard := human("H07")
	var foe := ghost("G12")
	foe.position = guard.position - Vector2(Rules.body_to_px(4),0)
	foe.floor_id = guard.floor_id
	var cash: float = session.incense
	check(not skill(guard).ok and near(session.incense,cash),"Four bodies is outside the unequipped drum")
	var equip: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":guard.instance_id,"item_id":"I07","slot_index":0},"player")
	check(equip.ok and not roster.cast(guard,{"watch_for_distress":true}).ok and near(session.incense,cash),"An equipped watchman conserves incense around a visible enemy")
	foe.floor_id += 1
	check(not skill(guard).ok,"A different floor is outside the equipped drum")
	foe.floor_id -= 1
	var ally := human("H08")
	ally.position = foe.position
	ally.floor_id = guard.floor_id
	roster.status(ally,"stun",3,foe)
	var result: Dictionary = roster.cast(guard,{"watch_for_distress":true})
	check(result.ok and result.drum.radius==5 and result.drum.woken==[ally.instance_id] and result.drum.marked==[foe.instance_id] and near(cash-session.incense,3) and not ally.growth.statuses.has("stun"),"Five-body drum wakes and marks across the old boundary for three incense")
	if not frame:
		var partner := human("H31","post_hall_door")
		guard.roster.cooldowns.skill = 0.0
		foe.roster.marked = false
		var bridge: Dictionary = roster.cast(guard,{"watch_for_distress":true})
		check(is_instance_valid(partner) and bridge.ok and foe.roster.marked,"The watchman still automatically marks an elite for a living hunter")
	if frame and result.ok:
		var camera := scene.get_node("BattleCamera")
		camera.make_current()
		camera.set_left(guard.position.x-960)
		for effect in roster.state.effects:
			if effect.kind=="watch_drum": effect.left=effect.duration*0.55
		sim.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		check(shot.get_size()==Vector2i(1920,1080) and shot.save_jpg("/tmp/r23-drum.jpg",0.88)==OK,"Rendered the five-body drum pulse at 1080p")
		guard.roster.cooldowns.skill = 0.0
		var panel := scene.get_node("Decisions")
		panel.select_unit(guard)
		panel.open_unit_skill()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var button: Button = panel.buttons.skill_cast
		var click_at := button.get_global_rect().get_center()
		var before_ms := Time.get_ticks_usec()
		for down in [true,false]:
			var mouse := InputEventMouseButton.new()
			mouse.position = click_at
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.pressed = down
			get_viewport().push_input(mouse,true)
		await RenderingServer.frame_post_draw
		var elapsed_ms := (Time.get_ticks_usec()-before_ms)/1000.0
		check(panel.feedback.text.contains("唤醒 0 人，显出 0 鬼，标记 1 鬼") and near(session.incense,cash-6),"Manual drum marks an already visible enemy and displays the actual counts")
		print("DRUM CLICK ",elapsed_ms," ms ",panel.feedback.text)


func _run() -> void:
	if "--drum-frame" in OS.get_cmdline_user_args():
		get_window().size=Vector2i(1920,1080)
		await _drum_reach(true)
		scene.free()
		await get_tree().create_timer(0.3).timeout
		get_tree().quit(1 if failures else 0)
		return
	if "--lamp-frame" in OS.get_cmdline_user_args():
		await _lamp_frame()
		return
	if capture: get_window().size=Vector2i(1920,1080)
	_catalog()
	_codex_model()
	if session_api_ready():
		if not OS.get_cmdline_user_args().has("--effects-only") and not OS.get_cmdline_user_args().has("--feedback-only"):
			_appearance_data()
			_spawn_all()
		if not OS.get_cmdline_user_args().has("--catalog-only") and not OS.get_cmdline_user_args().has("--feedback-only"):
			await _drum_reach()
			_human_first_eight()
			_human_second_eight()
			_impact_mirror()
			_human_supplementary()
			_departures()
			_codex_battle_events()
			_codex_ritual_completion()
			_troops_and_counters()
			var all_humans:=true
			for number in range(1,33): all_humans=all_humans and bool(effects.get("H%02d" % number,false))
			check(all_humans,"K3 All thirty-two human identities have passing actual skill or reactive behavior evidence")
			var all_troops:=true
			for number in range(1,5): all_troops=all_troops and bool(effects.get("T%02d" % number,false))
			check(all_troops,"K1 All four troop templates execute their actual supported battlefield behavior")
			_register_focus()
			_dispel_selection()
		if capture:
			await _feedback_frames()
			if not OS.get_cmdline_user_args().has("--feedback-only"):
				await _pairs()
				if not OS.get_cmdline_user_args().has("--humans-only"): await _face_codex_frames()
	if is_instance_valid(scene): scene.free()
	var subset:bool=OS.get_cmdline_user_args().has("--effects-only") or OS.get_cmdline_user_args().has("--catalog-only") or OS.get_cmdline_user_args().has("--humans-only") or OS.get_cmdline_user_args().has("--feedback-only")
	var report := {"phase":"P8","coverage_status":"partial_integration" if subset else "full_suite_executed","arguments":OS.get_cmdline_user_args(),"rules_hash":load("res://src/replay/BattleRecord.gd").rules_hash(),"checks":checks,"failures":failures,"results":rows,"effects":effects,"cards":card_rows,"appearance_audit":appearance_audit,"trajectories":trajectories,"night_failure":night_failure,"ritual_completion_fixture":ritual_completion_fixture,"capture":capture,"screenshots":shots,"archive_directory":Archive.directory,"fixture_policy":"Explicit isolated starting positions/resources. Real Session commands and shared Simulation; these fixtures do not claim an ordinary complete night."}
	FileAccess.open("res://docs/phase-reports/"+prefix+("-render" if capture else "-test")+"-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("P8 RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func session_api_ready() -> bool:
	var script: Script = load("res://src/combat/BattleSession.gd")
	for method in script.get_script_method_list():
		if method.name == "configure_roster": return true
	check(false,"P8 Session.configure_roster exists before behavior verification")
	return false

func _catalog() -> void:
	check(Data.errors.is_empty(),"K1 Boot source catalogs have no validation errors")
	check(Data.units.size()==68,"K1 Exact source population is 32 humans, 32 ghosts, four troops")
	var exceptions: Array[String] = []
	for family in ["H","G","T"]:
		for index in range(1,5 if family=="T" else 33):
			var id := "%s%02d" % [family,index]
			var source: Dictionary = Data.get_unit(id)
			var profile: Dictionary = Data.roster_rules.get("profiles",{}).get(id,{})
			check(not source.is_empty() and not profile.is_empty() and Data.combat_profiles.has(id),"K1 %s loads source, base profile and active roster profile" % id)
			if profile.is_empty(): continue
			var behavior_ok := true
			for key in ["skill","trait"]:
				var path: String = str(profile.get(key+"_script",""))
				var method: String = str(profile.get(key+"_method",""))
				if path.is_empty() or method.is_empty() or not ResourceLoader.exists(path):
					behavior_ok=false
					continue
				var handler = load(path)
				var found := false
				for candidate in handler.get_script_method_list():
					if candidate.name == method: found=true
				behavior_ok = behavior_ok and found
			check(behavior_ok,"K1 %s has callable skill and trait handlers" % id)
			if profile.get("may_briefly_leave_base",false): exceptions.append(id)
			if family != "T":
				var tags_ok := true
				for tag in str(source.get("标签","")).split(";",false): tags_ok = tags_ok and tag in TAGS
				check(tags_ok,"K1 %s preserves the twelve source tags" % id)
	check(exceptions==["H25","H31"],"K5 Only H25 and H31 declare departure permission")

func _codex_model() -> void:
	check(codex.entries("humans").size()==32 and codex.entries("ghosts").size()==32 and codex.entries("items").size()==20,"K7 Four books contain exactly 32 humans, 32 ghosts and 20 censers")
	check(codex.entries("customs").size()>=12,"K7 Customs book contains twelve ritual descriptions and block placeholders")
	check(codex.entry("H01").stage==0 and codex.entry("H01").portrait_state=="silhouette" and codex.entry("H01").skill_text=="尚未解明","K7 Unseen entries withhold identity artwork and skill text")
	check(not codex.list_name("H01") and codex.entry("H01").stage==0,"K7 Listed afterword cannot skip unresolved stages")
	check(codex.encounter("H01") and codex.entry("H01").stage==1 and codex.entry("H01").portrait_state=="line","K7 First encounter unlocks name and line-art stage")
	check(codex.resolve("H01","recruited") and codex.entry("H01").stage==2 and codex.entry("H01").skill_text==Data.units.H01["专属技能"],"K7 Successful resolution unlocks full source skill text and color stage")
	check(codex.list_name("H01") and codex.entry("H01").stage==3 and codex.entry("H01").portrait_state=="named","K7 Explicit listed interface advances the fourth stage")
	var before: Dictionary = codex.snapshot()
	check(not codex.encounter("H01") and not codex.resolve("H01") and codex.snapshot()==before,"K7 Duplicate or lower-stage events never downgrade collected progress")
	check(not codex.encounter("H99") and not codex.record_failure("","G25","ERASED"),"K7 Unknown unit and empty-seed failure events are rejected")
	check(codex.record_failure("P8-model-failure","G25","ERASED") and not codex.record_failure("P8-model-failure","G25","ERASED"),"K7 Failure record is idempotent and keeps explicit source ID")
	check(codex.save().ok,"K7 Isolated codex saves through the actual disk envelope")
	var loaded = Codex.new(codex.path,false)
	check(loaded.load_save().ok and int(loaded.entry("H01").stage)==3 and int(loaded.entry("G25").stage)==1 and loaded.failures==codex.failures,"K7 Codex disk round trip preserves all four stages and failure attribution")
	before=codex.snapshot()
	var invalids: Array[Dictionary] = []
	var bad: Dictionary = before.duplicate(true); bad.progress.H99=2; invalids.append(bad)
	bad=before.duplicate(true); bad.progress.H01=4; invalids.append(bad)
	bad=before.duplicate(true); bad.progress.H01=1.5; invalids.append(bad)
	bad=before.duplicate(true); bad.failures.append({"seed":"bad","reason":"bad","killer_id":"G99"}); invalids.append(bad)
	bad=before.duplicate(true); bad.failures.append({"seed":[],"reason":"bad","killer_id":"G25"}); invalids.append(bad)
	for index in invalids.size():
		check(not codex.restore(invalids[index]).ok and codex.snapshot()==before,"K7 Malformed codex case %d is rejected atomically" % index)
	# Clear synthetic model events before the separate real battle event probes.
	codex.restore({"version":1,"progress":{},"failures":[]})

func _spawn_all() -> void:
	for family in ["H","G","T"]:
		if family=="G" and OS.get_cmdline_user_args().has("--humans-only"): continue
		for index in range(1,5 if family=="T" else 33):
			rig()
			var id := "%s%02d" % [family,index]
			var unit = ghost(id) if family=="G" else human(id)
			check(is_instance_valid(unit),"K1 %s actually instantiates in shared battle" % id)
			if not is_instance_valid(unit): continue
			var state = unit.get("roster")
			check(state is Dictionary and state.get("cooldowns") is Dictionary and state.get("statuses") is Dictionary and state.get("counters") is Dictionary,"K1 %s owns serializable runtime ability state" % id)
			var source: Dictionary = Data.units[id]
			check(near(unit.max_hp,float(source["生命"])) and near(unit.attack,float(source["攻击"])) and near(unit.defense,float(source["防御"])) and near(unit.speed_stat,float(source["速度"])),"K1 %s retains all four authoritative source stats" % id)
			var large:bool=bool(Data.roster_rules.profiles[id].get("height_px",80)>80)
			check(unit.height_px>=128 and unit.height_px<=176 and unit.height_px<Rules.DESIGN_HEIGHT*.5 if large else near(unit.height_px,80),"K6 %s retains the locked ordinary or large physical height" % id)
			_card(unit)

func _appearance_data() -> void:
	var groups:Dictionary={
		"zhu":["H01","H02","H03","H08"],"wei":["H10","H12","H13","H16"],"fu":["H17","H18","H19","H20","H21","H22","H23","H24"],
		"jiang":["H25","H26","H27","H29","H32"],"tong":["H04","H07","H30"],"ke":["H31","H28"],"dun":["H09","H11","H14"],"you":["H05","H06","H15"],
		"chao":["G01","G02","G03","G05","G08","G14","G15"],"changzhi":["G06"],"shanglou":["G04","G07","G09"],"pomen":["G12","G13","G16"],"shui":["G10"],"denggu":["G11"],
		"daxing":["G17","G18","G19","G20","G21","G22","G23","G24"],"wuceli":["G25","G26","G27","G28","G29","G30","G31","G32"]}
	var hashes:Dictionary={}
	for skeleton in groups:
		for id in groups[skeleton]:
			if str(id).begins_with("G") and OS.get_cmdline_user_args().has("--humans-only"): continue
			var description:Dictionary=Appearance.describe(id)
			check(description.get("skeleton","")==skeleton and not str(description.get("headgear","")).is_empty() and not str(description.get("weapon","")).is_empty(),"K2 %s declares its exact source skeleton with headgear and weapon" % id)
			var path:String=str(description.get("portrait",""))
			var texture:Texture2D=load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
			var picture=texture.get_image() if texture!=null else null
			var quality:bool=picture!=null and picture.get_width()>=1024 and picture.get_height()>=1024
			check(quality,"K4/S1 %s has an independent high-resolution raster portrait asset" % id)
			var digest:String=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
			check(not digest.is_empty() and not hashes.has(digest),"K2 %s does not reuse another named portrait file" % id)
			hashes[digest]=id
			appearance_audit.append({"id":id,"family":description.get("family",""),"skeleton":skeleton,"headgear":description.get("headgear",""),"weapon":description.get("weapon",""),"portrait":path,"sha256":digest,"dimensions":[picture.get_width(),picture.get_height()] if picture!=null else [],"high_resolution":quality})
	for pair in PAIRS:
		var a:Dictionary=Appearance.describe(pair[0]); var b:Dictionary=Appearance.describe(pair[1])
		check(a.get("skeleton")==b.get("skeleton") and [a.get("headgear"),a.get("weapon"),a.get("variant")]!=[b.get("headgear"),b.get("weapon"),b.get("variant")],"K2/A1 %s/%s have non-palette shape distinctions within the shared skeleton" % [pair[0],pair[1]])
	for id in ["T01","T02","T03","T04"]:
		check(str(Appearance.describe(id).get("portrait","")).is_empty(),"K4 %s has no fabricated named portrait in appearance data" % id)
	check(Rules.BODY_PX==80 and Rules.CAMERA_WIDTH_PX==1920 and Rules.REFERENCE_MAP_WIDTH_PX==9600,"K6 Default unit scale, camera span and world width retain the locked baseline")

func _card(unit: Node2D) -> void:
	var panel = scene.get_node("Decisions")
	Clock.set_paused(false)
	panel.select_unit(unit)
	var text: String = panel.details.text
	var source: Dictionary = Data.get_unit(unit.unit_id)
	var complete: bool = panel.selected == unit and Clock.paused and text.contains(unit.unit_id) and text.contains(unit.display_name)
	for field in ["生命","攻击","防御","速度","香器","技艺","名帖"]:
		complete = complete and text.contains(field)
	if not unit.unit_id.begins_with("T"):
		complete = complete and text.contains(str(source["专属技能"])) and text.contains(str(source["特性"]))
		for tag in unit.tags: complete = complete and text.contains(tag)
	check(complete,"K4 %s real selection pauses and exposes every complete-card field" % unit.unit_id)
	check(panel.portrait.texture == null if unit.unit_id.begins_with("T") else panel.portrait.texture != null,"K4 %s uses a named portrait or a genuine troop template" % unit.unit_id)
	card_rows.append({"id":unit.unit_id,"complete":complete,"text":text,"has_portrait":panel.portrait.texture!=null})
	panel.close_panel()

func _human_first_eight() -> void:
	rig()
	var u=human("H01"); var g=ghost("G04",114)
	var money:float=session.incense
	var result:Dictionary=skill(u,{"target_id":g.instance_id})
	check(result.ok and near(money-session.incense,4) and u.brain.channel.active and g.growth.statuses.has("revealed"),"H01 Actual paid targeted reading reveals its hidden target and starts a real channel","H01")
	var duration:float=u.brain.channel.duration
	tick(duration+.1)
	check(g.dead and session.codex.entry("G04").stage>=2,"H01 The original reader actually completes purification through shared battle steps","H01")
	rig(); u=human("H01","post_gate_inner"); g=ghost("G01",52)
	money=session.incense; result=skill(u,{"target_id":g.instance_id})
	check(not result.ok and near(money,session.incense) and not u.brain.channel.active,"H01 A courtyard target cannot turn an outer guard post into a ritual station","H01")
	rig(); u=human("H02"); session.names=2; money=session.incense
	result=skill(u)
	check(result.ok and near(session.names,4) and near(money-session.incense,5) and event("rekindle",u.instance_id),"H02 Real rekindling raises the book by two names and spends five incense","H02")
	u.receive_damage(999,null,"fixture_lethal")
	var names:float=session.names
	u.receive_damage(999,null,"fixture_lethal")
	check(near(names,6) and near(names,session.names) and event("last_embers",u.instance_id),"H02 Actual death returns remaining embers once","H02")
	rig(); u=human("H03"); var friend=human("H09"); g=ghost("G25",115)
	result=skill(u,{"target_id":friend.instance_id}); names=session.names
	var attack:Dictionary=roster.cast(g,{"target_id":friend.instance_id})
	check(result.ok and attack.ok and near(names,session.names) and not friend.roster.statuses.has("nameless"),"H03 Real named ward blocks a G25 skill instead of merely displaying a mark","H03")
	var second=ghost("G25",115.1)
	attack=roster.cast(second,{"target_id":friend.instance_id})
	check(attack.ok and session.names<names and friend.roster.statuses.has("nameless"),"H03 The consumed name ward does not block a second actual erasure","H03")
	rig(); u=human("H04"); friend=human("H17"); money=session.incense
	result=skill(u,{"target_id":friend.instance_id})
	check(result.ok and near(money-session.incense,2) and near(friend.roster.reserve_incense,2) and event("incense_transfer",u.instance_id),"H04 Incense is really prepaid to the nearby ally using the same currency","H04")
	session.incense=0
	check(roster.pay(friend,2) and near(friend.roster.reserve_incense,0) and near(session.incense,0),"H04 The recipient can actually consume transferred incense with an empty shared purse","H04")
	check(near(float(u.roster.cooldowns.get("skill",0)),5.6),"H04 Book-room work receives its actual thirty-percent cooldown reduction","H04")
	rig(); u=human("H05"); friend=human("H14"); g=ghost("G03",115)
	result=skill(u,{"target_id":g.instance_id})
	var hp:float=g.hp
	attack=roster.cast(g,{"target_id":friend.instance_id})
	var gong:Dictionary=skill(friend)
	check(result.ok and attack.ok and g.hp<hp and gong.ok and g.roster.statuses.has("taunt") and not g.growth.statuses.has("stun"),"H05 Silence affects both the enemy cry and friendly gong with actual backlash/taunt outcomes","H05")
	var blocked:Dictionary=roster.status(u,"misrecord",2,g,{"original_side":u.side,"restore_left":2,"end_stun":1})
	check(blocked.get("blocked",false) and u.side=="xianghuo" and not u.roster.statuses.has("misrecord"),"H05 The speechless trait blocks actual attempted allegiance change","H05")
	rig(); u=human("H06"); g=ghost("G04",115)
	result=skill(u)
	check(result.ok and g.growth.statuses.has("revealed") and g.growth.statuses.has("fear") and not session.growth.is_hidden(g) and event("cold_light",u.instance_id),"H06 The cold-light field really reveals hidden shadow and causes faceless fear","H06")
	rig(); u=human("H07"); friend=human("H09"); g=ghost("G04",115)
	roster.status(friend,"stun",3,g)
	result=skill(u)
	check(result.ok and not friend.growth.statuses.has("stun") and g.growth.statuses.has("revealed") and event("watch_drum",u.instance_id),"H07 The watch drum actually wakes a stunned ally and reveals the nearby shadow","H07")
	var cooldown:float=float(u.roster.cooldowns.get("skill",0))
	session.simulation_speed=2
	roster.advance(2)
	check(near(cooldown-float(u.roster.cooldowns.get("skill",0)),1),"H07 At double speed the two-second skill step preserves one-second watch cadence","H07")
	rig(); u=human("H08"); g=ghost("G25",115)
	names=session.names; var baseline:float=roster.drain_names(2,g)
	session.names=names; result=skill(u)
	var guarded:float=roster.drain_names(2,g)
	check(result.ok and near(baseline,2) and near(guarded,.7) and event("register_guard",u.instance_id),"H08 The real book-drain handler loses only thirty-five percent under guard","H08")
	var high_defense:float=roster.defense_for(u,u.defense)
	session.names=1
	check(roster.defense_for(u,u.defense)>high_defense and roster.speed_multiplier(u)<1,"H08 A damaged register produces real defense growth and slower movement","H08")

func _human_second_eight() -> void:
	rig(); var u=human("H09","post_gate_inner"); var g=ghost("G12",49)
	var door=sim.world.get_node("door_outer")
	var result:Dictionary=skill(u)
	var door_hp:float=door.durability; var hp:float=u.hp
	hit(g,door,4,"structure")
	check(result.ok and near(door.durability,door_hp) and u.hp<hp and event("gate_transferred",u.instance_id),"H09 A real G12 door strike damages Iron Shoulder instead of the guarded door","H09")
	var cooldown:float=float(u.roster.cooldowns.get("skill",0))
	u.position=sim.world.get_node("post_table_hall").position
	roster.advance(1)
	check(near(cooldown-float(u.roster.cooldowns.get("skill",0)),2.0/3),"H09 Leaving the doorway makes the same skill cooldown advance more slowly","H09")
	rig(); u=human("H10"); g=ghost("G12",115.4)
	g.hp=g.max_hp*.35
	var ordinary:float=hit(u,g,5)
	hp=g.hp; result=skill(u,{"target_id":g.instance_id})
	check(result.ok and hp-g.hp>ordinary*2 and event("decisive_slash",u.instance_id),"H10 A real wounded elite receives a decisive slash with distinct feedback","H10")
	rig(); u=human("H11","post_table_hall"); var wall=sim.world.get_node("hall_b")
	var money:float=session.incense
	result=skill(u,{"object_id":"hall_b"})
	check(result.ok and session.incense<money and u.growth.statuses.has("construct") and not wall.occupied,"H11 Earth wall begins actual paid construction in an empty obstacle slot","H11")
	tick(3)
	check(wall.occupied and wall.durability>0 and sim.world.segment_blocked(wall.position-Vector2(70,0),wall.position+Vector2(70,0),wall.floor_id),"H11 Completed earth wall actually blocks a real world segment","H11")
	g=ghost("G12",93)
	hit(g,wall,999,"structure")
	check(wall.durability<=0 and not wall.occupied,"H11 A real G12 structure strike can demolish the constructed earth wall","H11")
	var bonus:float=roster.defense_for(u,u.defense)
	u.position.x+=10
	roster.advance(.1)
	check(bonus>u.defense and near(roster.defense_for(u,u.defense),u.defense),"H11 Moving clears real accumulated rooted defense","H11")
	rig(); u=human("H12","post_hall_door"); u.position.x=Rules.body_to_px(88.5); g=ghost("G09",86.5,false)
	result=skill(u,{"target_id":g.instance_id})
	var point:Vector2=g.position
	tick(.5)
	check(result.ok and g.roster.statuses.has("chain") and g.floor_id==0 and g.position.distance_to(point)<.01,"H12 A real chain prevents a beam ghost from moving into its climb route","H12")
	u.roster.cooldowns.skill=100
	tick(4)
	check(not g.roster.statuses.has("chain") and g.position.distance_to(point)>.1,"H12 The same ghost resumes its existing route after the chain actually expires","H12")
	rig(); u=human("H13"); g=ghost("G01",115.4); g.hp=3
	var names:float=session.names
	result=skill(u,{"target_id":g.instance_id})
	check(result.ok and g.dead and near(names-session.names,1) and event("execution",u.instance_id),"H13 Execution truly kills a purifiable wounded ghost and incurs the name penalty","H13")
	rig(); u=human("H14"); g=ghost("G12",115)
	result=skill(u)
	check(result.ok and g.roster.statuses.has("taunt") and g.growth.statuses.has("stun") and str(g.roster.statuses.taunt.source_id)==u.instance_id,"H14 The gong actually retargets a door-breaker and briefly stuns it","H14")
	rig("shouxiang",{"ritual_flag":"jinsheng"}); u=human("H14"); g=ghost("G12",115)
	result=skill(u)
	check(result.ok and g.roster.statuses.has("taunt") and not g.growth.statuses.has("stun") and event("silent_taunt",u.instance_id),"H14 Silence night preserves real taunt while removing the gong stun","H14")
	rig(); u=human("H15","post_table_hall",false); var friend=human("H09","post_window_1")
	result=skill(u,{"target_id":friend.instance_id})
	point=u.position
	var left:float=session.remaining
	var travelled:=false; var inside:=true
	for index in 1500:
		sim.advance(1.0/60)
		inside=inside and sim.world.inside_base(u.position)
		travelled=travelled or u.position.distance_to(point)>.1
		if u.brain.route.is_empty(): break
	check(result.ok and travelled and inside and u.floor_id==friend.floor_id and u.current_post==friend.current_post and session.remaining<left,"H15 Flying tiles moves through a real indoor route to an upper friendly post without leaving base","H15")
	rig(); u=human("H16"); friend=human("H09"); g=ghost("G12",115.4)
	hp=g.hp; result=skill(u,{"target_id":g.instance_id})
	check(result.ok and g.hp<hp and g.roster.statuses.has("armor_down") and roster.defense_for(g,g.defense)<g.defense and event("opening_staff",u.instance_id),"H16 Opening staff deals actual ghost injury and reduces the victim's effective defense","H16")
	friend.hp=10
	var healed:float=roster.heal(friend,10)
	check(near(healed,7) and near(friend.hp,17),"H16 The same nearby friendly healing really loses thirty percent","H16")

func _impact_mirror() -> void:
	rig("shouxiang",{"defense_objective":"hold_register","inventory":{"Y11":1}})
	var guard := human("H18")
	var common := ghost("G01")
	common.position = guard.position
	var gear: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":guard.instance_id,"item_id":"Y11","slot_index":0},"player")
	var cash: float = session.incense
	check(gear.ok and not skill(guard).ok and near(cash,session.incense),"Cold Gold waits for a breaker when using Impact","H18")
	var breaker := ghost("G12")
	breaker.position = guard.position
	breaker.floor_id = guard.floor_id + 1
	check(not skill(guard).ok and near(cash,session.incense),"Breaker on another floor cannot open the mirror","H18")
	breaker.floor_id = guard.floor_id
	var panel: Node = scene.get_node("Decisions")
	panel.select_unit(guard,true)
	panel.open_unit_skill()
	check(not panel.buttons.skill_cast.disabled and not panel.skill_target_picker.visible,"Self-guard mirror offers one legal cast","H18")
	panel.buttons.skill_cast.pressed.emit()
	check(guard.roster.statuses.has("impact_mirror") and not guard.roster.statuses.has("mirror") and near(cash-session.incense,guard.skill_cost) and panel.feedback.text.contains("承撞护身"),"Paid cast has the correct stance and receipt","H18")
	var hp: float = guard.hp
	guard.receive_damage(4,common,"melee")
	check(guard.hp<hp and guard.roster.statuses.has("impact_mirror"),"Ordinary melee passes the raised mirror","H18")
	hp=guard.hp
	guard.receive_damage(4,breaker,"occult")
	check(guard.hp<hp and guard.roster.statuses.has("impact_mirror"),"Impact stance gives up occult reflection","H18")
	hp=guard.hp
	var enemy_hp: float = breaker.hp
	guard.receive_damage(8,breaker,"melee")
	check(near(hp,guard.hp) and near(enemy_hp,breaker.hp) and not guard.roster.statuses.has("impact_mirror") and event("impact_block",guard.instance_id),"One breaker strike is absorbed without a counterattack","H18")
	guard.receive_damage(8,breaker,"melee")
	check(guard.hp<hp and not skill(guard).ok,"Second strike lands during mirror cooldown","H18")

func _human_supplementary() -> void:
	rig(); var u=human("H17","post_gate_inner"); var g=ghost("G12",49)
	var door=sim.world.get_node("door_outer")
	var seal_panel: Node = scene.get_node("Decisions")
	seal_panel.select_unit(u,true)
	seal_panel.open_unit_skill()
	check(not seal_panel.buttons.skill_cast.disabled and seal_panel.buttons.skill_cast.text=="封住"+tr("DOOR_OUTER") and not seal_panel.skill_target_picker.visible,"Cinnabar panel names the door actually reachable from his post")
	var result:Dictionary=skill(u)
	var hp:float=g.hp; var durability:float=door.durability
	hit(g,door,4,"structure")
	check(result.ok and door.durability==durability and g.hp<hp and event("seal",u.instance_id),"H17 The actual sealed doorway absorbs a real strike and reflects injury","H17")
	rig("duoming"); u=human("H17","post_gate_inner"); g=ghost("G12",49)
	var money:float=session.incense; var npc:float=session.growth.state.npc_incense
	result=roster.cast(u)
	check(result.ok and near(session.incense,money) and session.growth.state.npc_incense<npc,"H17 In an attacking game the opposing priest pays the defender purse without charging the player","H17")
	rig(); u=human("H18"); g=ghost("G12",115)
	result=skill(u); hp=u.hp; var other_hp:float=g.hp
	u.receive_damage(8,g,"occult")
	check(result.ok and near(u.hp,hp) and g.hp<other_hp and g.growth.statuses.has("revealed") and event("gold_reflect",u.instance_id),"H18 The next real directed occult strike is reflected and reveals its source","H18")
	rig("shouxiang",{"defense_objective":"hold_register","inventory":{"I08":1}})
	u=human("H19"); g=ghost("G01",115)
	var lamp_panel: Node = scene.get_node("Decisions")
	lamp_panel.select_unit(u,true)
	lamp_panel.open_unit_skill()
	var before_view: float = session.incense
	lamp_panel.buttons.lamp_equipment.pressed.emit()
	check(lamp_panel.growth_panel.selected_item=="I08" and session.growth.state.inventory.I08==1 and near(before_view,session.incense),"Inspecting the available lamp paper selects the correct item without spending")
	lamp_panel.growth_panel.buttons.equip_item.pressed.emit()
	check(session.growth.has(u,"I08") and session.growth.state.inventory.get("I08",0)==0,"Confirmation equips exactly one paper on the selected lantern bearer")
	var lamp_cost := float(Data.get_unit("H19").get("技能香耗",0))
	var before_lamp: float = session.incense
	var blocker := ghost("G12",115)
	blocker.position = u.position
	g.position = u.position+Vector2(12,0)
	lamp_panel.open_unit_skill()
	check(g.instance_id in lamp_panel.skill_target_ids and blocker.instance_id not in lamp_panel.skill_target_ids,"Lantern picker excludes an ineligible nearer breaker")
	check(not skill(u,{"target_id":blocker.instance_id}).ok and near(before_lamp,session.incense),"Invalid explicit lantern choice never retargets or spends")
	lamp_panel.buttons.skill_auto.pressed.emit()
	check(lamp_panel.feedback.text.contains("照见"+g.display_name),"Auto-cast receipt identifies the actual common ghost behind the breaker")
	check(g in sim.targets and g.side=="yegui" and near(before_lamp-session.incense,lamp_cost),"Equipped Wengdeng pays his normal skill cost and keeps the ghost hostile")
	var beams: Array = session.growth.state.fields.filter(func(f): return f.kind=="lamp_reveal")
	check(beams.size()==1 and beams[0].end==[u.position.x,u.position.y] and beams[0].point==[g.position.x,g.position.y] and event("lamp_reveal",u.instance_id),"One reveal beam travels from the actual lantern to the hostile target")
	check(near(g.growth.statuses.revealed.left,3) and near(g.growth.statuses.stun.left,1.5),"Lamp marks and briefly stuns a valid target")
	check(not skill(u,{"target_id":g.instance_id}).ok,"Repeated lamp command respects cooldown")
	rig(); u=human("H19"); g=ghost("G01",115)
	result=skill(u,{"target_id":g.instance_id})
	check(result.ok and g.side=="xianghuo" and g in sim.humans and g not in sim.targets,"H19 Borrowing actually changes the gray ghost's group and brain ownership","H19")
	check(session.codex.entry("G01").stage==2,"K7 A real successful gray-ghost recruitment resolves its codex entry")
	var clerk=ghost("G25",115.1)
	session.growth.advance(.1)
	check(g.side=="yegui" and g in sim.targets,"H19 A real unregistered clerk contact recaptures the borrowed gray ghost","H19")
	rig(); u=human("H20"); g=ghost("G12",115)
	money=session.incense; hp=g.hp; result=skill(u,{"target_id":g.instance_id})
	check(result.ok and g.hp<hp and near(money-session.incense,float(Data.units.H20["技能香耗"])+float(roster.params(u).extra_incense)) and event("burning_petition",u.instance_id),"H20 Real area fire harms the enemy and pays its explicit additional global incense cost","H20")
	var attack:Dictionary=roster.cast(g)
	check(attack.ok and attack.reason=="P8_SKILL_MISFIRED" and attack.get("effect_applied",true)==false,"H20 The burned target really loses its next active skill attempt","H20")
	rig(); u=human("H21"); g=ghost("G10",115)
	u.growth.environment.water=true; g.growth.environment.water=true
	result=skill(u)
	var wet:float=float(u.roster.statuses.get("lantern",{}).get("left",0))
	check(result.ok and g.growth.statuses.has("water_slow") and g.growth.statuses.has("revealed") and event("river_lantern",u.instance_id),"H21 The real river lantern slows and reveals a water-lane ghost","H21")
	rig(); u=human("H21"); g=ghost("G04",115)
	result=skill(u)
	var dry:float=float(u.roster.statuses.get("lantern",{}).get("left",0))
	check(result.ok and dry>0 and dry<wet,"H21 The same lantern has measurably weaker duration away from the water lane","H21")
	rig(); u=human("H22"); g=ghost("G30",115)
	hp=g.hp; result=skill(u,{"target_id":g.instance_id})
	check(result.ok and g.hp<hp and event("false_god_unmasked",u.instance_id),"H22 The false god is actually exposed and harmed by exorcism","H22")
	var dispel_fx: Dictionary = roster.state.effects.back()
	check(dispel_fx.kind=="false_god_unmasked" and dispel_fx.source[0]==u.position.x and dispel_fx.point[0]==g.position.x,"Three-ring cast records actual caster and false god positions","H22")
	rig(); u=human("H23"); g=ghost("G25",115)
	result=skill(u,{"target_id":g.instance_id})
	var names:float=session.names; attack=roster.cast(g,{"target_id":u.instance_id})
	check(result.ok and attack.ok and attack.reason=="P8_SKILL_MISFIRED" and attack.get("effect_applied",true)==false and near(session.names,names),"H23 Misnaming prevents the next real erasure skill from taking effect","H23")
	rig(); u=human("H24"); g=ghost("G04",115)
	result=skill(u,{"target_id":g.instance_id})
	var small:float=float(g.growth.statuses.get("stun",{}).get("left",0))
	rig(); u=human("H24"); g=ghost("G17",115)
	result=skill(u,{"target_id":g.instance_id})
	check(result.ok and small>float(g.growth.statuses.get("stun",{}).get("left",0)) and small>0,"H24 Actual needle stun lasts longer on a beam shadow than on a large ghost","H24")
	rig(); u=human("H25","post_table_hall"); var wall=sim.world.get_node("hall_b")
	result=skill(u,{"object_id":"hall_b"}); tick(3)
	check(result.ok and wall.occupied and wall.durability>0 and event("barricade_build",u.instance_id),"H25 The carpenter creates a real paid barricade in a world obstacle slot","H25")
	rig(); u=human("H26"); g=ghost("G01",115)
	hp=g.hp; result=skill(u)
	check(result.ok and g.hp<hp and g.growth.statuses.has("fear") and event("firecracker_scatter",u.instance_id),"H26 Firecrackers really scatter a nearby tide member instead of merely adding damage","H26")
	rig(); u=human("H27"); g=ghost("G04",115)
	result=skill(u)
	check(result.ok and g.growth.statuses.has("revealed") and event("crow_path",u.instance_id),"H27 The crow path really reveals a hidden enemy","H27")
	rig(); u=human("H28","post_hall_door")
	var item:String=str(roster.params(u).market_item)
	var stock:int=int(session.growth.state.inventory.get(item,0)); money=session.incense
	result=skill(u,{"confirm_market":true})
	check(result.ok and int(session.growth.state.inventory.get(item,0))==stock+1 and session.incense<money,"H28 Confirming the personal market really pays for one inventory item","H28")
	money=session.incense; u.roster.cooldowns.skill=0
	check(not skill(u,{"confirm_market":true}).ok and near(session.incense,money) and int(session.growth.state.inventory.get(item,0))==stock+1,"H28 The once-per-battle market cannot be purchased twice","H28")
	g=ghost("G12",88); door=sim.world.get_node("door_hall")
	hit(g,door,999,"structure"); u.motion_enabled=true
	var point:Vector2=u.position
	tick(.5)
	check(not u.brain.route.is_empty() or u.position.distance_to(point)>.1,"H28 A real breach sends the timid trader into retreat rather than gate combat","H28")
	rig(); u=human("H29"); g=ghost("G04",115)
	g.growth.counters.invisible=true
	point=g.position; result=skill(u,{"mode":"pull"})
	check(result.ok and g.position.distance_to(point)>.1 and g.roster.statuses.has("taunt") and event("blind_strings",u.instance_id),"H29 Blind strings really displaces an invisible enemy and draws its attention","H29")
	rig(); names=session.names; u=human("H30"); var friend=human("H09"); g=ghost("G25",115)
	check(near(session.names,names+1),"H30 The inherited name is actually credited on entry","H30")
	names=session.names; attack=roster.cast(g,{"target_id":friend.instance_id})
	check(attack.ok and u.dead and near(session.names,names) and not friend.roster.statuses.has("nameless") and event("substitute_name",u.instance_id),"H30 An actual erasure is prevented by consuming the child's real life","H30")
	rig(); u=human("H32"); friend=human("H09"); g=ghost("G28",115)
	attack=roster.cast(g,{"target_id":friend.instance_id})
	check(attack.ok and friend.roster.face_state=="faceless","K8 Actual face theft changes the named actor's persistent face state","G28")
	result=skill(u,{"target_id":friend.instance_id})
	var second=ghost("G28",115.1)
	attack=roster.cast(second,{"target_id":friend.instance_id})
	check(result.ok and friend.roster.face_state=="faced" and int(friend.growth.counters.get("face_ward",0))==0,"H32 Temporary face restores a stolen face and consumes its ward on the next actual theft","H32")
	# Resource-order regression: a rejected no-incense action cannot produce free poison.
	rig(); u=human("H02"); friend=human("H09"); g=ghost("G27",115)
	session.names=float(Data.mode_rules.limits.names_max)
	attack=roster.cast(g,{"target_id":friend.instance_id})
	session.incense=0; hp=friend.hp; other_hp=u.hp
	result=skill(u,{"target_id":friend.instance_id})
	check(attack.ok and not result.ok and near(friend.hp,hp) and near(u.hp,other_hp),"H02 Insufficient-incense rekindling in a poison field has no preflight damage side effect","H02")

func _dispel_selection() -> void:
	rig(); var u:=human("H22")
	var ordinary := ghost("G01")
	var protected := ghost("G12")
	for foe in [ordinary,protected]: foe.floor_id = u.floor_id
	ordinary.position = u.position - Vector2(12,0)
	protected.position = u.position - Vector2(30,0)
	roster.status(protected,"cloth",6,protected,{"multiplier":0.6})
	var panel: Node = scene.get_node("Decisions")
	panel.select_unit(u)
	panel.open_unit_skill()
	check(panel.skill_target_ids==["",protected.instance_id] and panel.skill_target_picker.get_item_text(1).contains("寿衣") and not panel.buttons.skill_cast.disabled,"Three Ring picker identifies the protected enemy behind an ordinary one","H22")
	var before_dispel: float = session.incense
	var result:=skill(u,{"target_id":ordinary.instance_id})
	check(not result.ok and near(session.incense,before_dispel) and roster.ready(u) and protected.roster.statuses.has("cloth"),"Invalid explicit dispel keeps funds, cooldown and enemy status","H22")
	result=skill(u)
	check(result.ok and not protected.roster.statuses.has("cloth") and not roster.ready(u) and session.incense<before_dispel,"Untargeted dispel reaches the closest legal enemy behind the front rank","H22")
	panel.open_unit_skill()
	check(panel.buttons.skill_cast.disabled and panel.skill_target_ids==[""],"Empty dispel list prevents another cast","H22")
	roster.cooldown(u,0)
	session.growth.apply_status(protected,"ward",5,protected)
	protected.floor_id = u.floor_id+1
	check(not skill(u).ok and roster.ready(u),"Dispel cannot reach a ward on another floor","H22")
	protected.floor_id = u.floor_id
	panel.open_unit_skill()
	panel.buttons.skill_cast.pressed.emit()
	check(not protected.growth.statuses.has("ward") and panel.feedback.text.contains("实耗") and panel.feedback.text.contains(protected.display_name),"Dispel button clears a ward and displays the target and real cost","H22")

	rig("shouxiang",{"defense_objective":"hold_register","inventory":{"I12":1}})
	u=human("H22")
	protected=ghost("G12")
	protected.floor_id=u.floor_id
	protected.position=u.position+Vector2(Rules.body_to_px(4),0)
	roster.status(protected,"cloth",6,protected,{"multiplier":0.6})
	var args := {"target_id":protected.instance_id}
	check(not skill(u,args).ok,"Distant cloth requires a worn shard","H22")
	var gear: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":u.instance_id,"item_id":"I12","slot_index":0},"player")
	check(gear.ok and not skill(u).ok and roster.ready(u),"An equipped shard never spends the surcharge automatically","H22")
	var god := ghost("G30")
	god.floor_id=u.floor_id
	god.position=protected.position
	check(not skill(u,{"target_id":god.instance_id}).ok and roster.ready(u),"Distant mirror cannot damage the false god","H22")
	session.incense=u.skill_cost
	check(not skill(u,args).ok and near(session.incense,u.skill_cost) and protected.roster.statuses.has("cloth") and roster.ready(u),"Insufficient incense preserves the protection and cooldown","H22")
	session.incense=30
	panel=scene.get_node("Decisions")
	panel.select_unit(u)
	panel.open_unit_skill()
	check(panel.skill_target_ids==["",protected.instance_id] and panel.skill_target_picker.get_item_text(1).contains("加收 3 香"),"Manual mirror shows the extra cost before confirmation","H22")
	panel.buttons.skill_cast.pressed.emit()
	check(not protected.roster.statuses.has("cloth") and near(session.incense,30-u.skill_cost-3),"Confirming distant dispel takes exactly the quoted surcharge","H22")

	panel.close_panel()
	panel.preferred_faction="符法司"
	panel.open_purchase()
	panel._purchase("H24")
	var posts: Array = panel.content.find_children("*","Label",true,false)
	check(panel.current_panel=="deploy" and posts.any(func(label):return label.text.contains("三戒在册房（64/64 血）") and label.text.contains("后厢")),"Bone Needle deployment identifies the living register guard before choosing a rear post","H24")
	panel._cancel_purchase()

func _register_focus() -> void:
	rig("shouxiang",{"defense_objective":"hold_register"})
	var deploy_panel: Node = scene.get_node("Decisions")
	deploy_panel.preferred_faction="符法司"
	var before: float = session.incense
	deploy_panel.open_purchase()
	deploy_panel._purchase("H22")
	var hints: Array = deploy_panel.content.find_children("*","Label",true,false)
	check(deploy_panel.current_panel=="deploy" and hints.any(func(label):return label.text.contains("另留人守册")) and near(before-session.incense,session.rules.purchases.H22),"Three Ring deployment explains room presence with the correct reserved price")
	deploy_panel._cancel_purchase()
	check(near(before,session.incense) and session.pending_purchase.is_empty(),"Canceling post selection refunds the full reservation")
	var shooter := human("H22")
	shooter.position.x -= 150 # Clear the register desk in this targeting fixture.
	var front := ghost("G01")
	var breaker := ghost("G12")
	for foe in [front,breaker]: foe.floor_id = shooter.floor_id
	front.position = shooter.position - Vector2(48,0)
	breaker.position = shooter.position - Vector2(96,0)
	var cash: float = session.incense
	var panel: Node = scene.get_node("Decisions")
	panel.select_unit(breaker)
	check(sim.nearest_shootable(shooter)==front and panel.buttons.has("card_focus"),"Register guard normally aims at the nearer enemy")
	panel.buttons.card_focus.pressed.emit()
	check(sim.nearest_shootable(shooter)==breaker and panel.feedback.text.contains(breaker.display_name) and panel.buttons.card_focus.text=="解除集火" and not breaker.roster.marked and near(cash,session.incense),"Card order changes ranged aim for free without applying the hunter mark")
	var saved: Dictionary = roster.state.duplicate(true)
	panel.buttons.card_focus.pressed.emit()
	check(sim.nearest_shootable(shooter)==front and not roster.state.has("focus_fire_id"),"Cancel returns the guard to free aim")
	roster.restore(saved)
	check(sim.nearest_shootable(shooter)==breaker,"Restored roster remembers the designated instance")
	breaker.position.x -= Rules.body_to_px(100)
	check(sim.nearest_shootable(shooter)==front,"Out-of-range focus leaves a legal alternate shot")
	var args := {"target_id":front.instance_id,"focus_fire":true}
	check(not session.execute_for("duoming","mark_target",args,"player").ok,"Attacking seat cannot designate defender fire")
	check(session.execute_for("shouxiang","mark_target",args,"player").ok and roster.state.focus_fire_id==front.instance_id,"New order replaces the old enemy")
	roster.set_allegiance(front,"xianghuo",2.0)
	check(not roster.state.has("focus_fire_id"),"Change of allegiance clears focus")
	args = {"target_id":breaker.instance_id,"focus_fire":"yes"}
	check(not session.execute_for("shouxiang","mark_target",args,"player").ok and not roster.state.has("focus_fire_id"),"Malformed order cannot change aim")
	args.focus_fire=true
	session.execute_for("shouxiang","mark_target",args,"player")
	breaker.receive_damage(10000,shooter,"melee")
	sim.advance(1.0/60)
	check(breaker.dead and not roster.state.has("focus_fire_id"),"Fallen enemy releases the order")

func _departures() -> void:
	rig(); var u=human("H31","post_gate_inner",false); var g=ghost("G12",49)
	sim.world.get_node("door_outer").set_open(true)
	var money:float=session.incense
	check(not skill(u,{"target_id":g.instance_id}).ok and near(session.incense,money),"H31 An unmarked elite cannot initiate the paid hunt","H31")
	var mark:Dictionary=session.execute_for("shouxiang","mark_target",{"target_id":g.instance_id},"player")
	var second=ghost("G12",49.2)
	session.execute_for("shouxiang","mark_target",{"target_id":second.instance_id},"player")
	var second_hp:float=second.hp; var hp:float=g.hp
	var result:Dictionary=skill(u,{"target_id":g.instance_id})
	var positions:Array[Dictionary]=[]; var outside:=0.0; var moved_out:=false; var smooth:=true
	var previous:Vector2=u.position
	for index in 250:
		sim.advance(1.0/60)
		var is_outside:bool=not sim.world.inside_base(u.position) or sim.world.is_open_court(u.position)
		if is_outside: outside+=1.0/60
		moved_out=moved_out or u.position.x<Rules.BASE_START_X
		smooth=smooth and u.position.distance_to(previous)<=Rules.body_to_px(float(roster.params("H31").hunt_speed))/60+.1
		previous=u.position
		if index%6==0:positions.append({"time":sim.simulation_time,"x":u.position.x,"y":u.position.y,"outside":is_outside,"state":u.ai_state})
		if not u.roster.has("hunt"): break
	positions.append({"time":sim.simulation_time,"x":u.position.x,"y":u.position.y,"post":u.current_post,"state":u.ai_state,"completed":not u.roster.has("hunt")})
	trajectories.append({"id":"H31","kind":"real_marked_hunt","positions":positions,"outside_seconds":outside})
	check(mark.ok and result.ok and moved_out and g.hp<hp and event("hunt_hit",u.instance_id),"H31 A real marked elite receives the straight-path strike outside the gate","H31")
	check(smooth and outside<=3.017 and not u.roster.has("hunt") and sim.world.inside_base(u.position) and sim.world.can_deploy_at(u.current_post) and event("hunt_returned",u.instance_id),"H31 The actual movement returns to legal cover within three seconds without teleporting","H31")
	check(near(second.hp,second_hp),"H31 The hunt never chases or strikes a second marked elite en route","H31")
	rig(); u=human("H31","post_gate_inner",false); g=ghost("G01",49)
	sim.world.get_node("door_outer").set_open(true)
	session.execute_for("shouxiang","mark_target",{"target_id":g.instance_id},"player")
	money=session.incense
	check(not skill(u,{"target_id":g.instance_id}).ok and near(session.incense,money),"H31 Marking an ordinary tide member does not turn it into an eligible elite","H31")
	rig(); u=human("H25","post_table_hall",false)
	var door=sim.world.get_node("door_outer"); door.set_durability(300)
	var home:Vector2=u.position; money=session.incense
	result=session.repair("door_outer")
	var paid:float=money-session.incense
	var lowest:float=u.position.x; var reached_leaf:=false; var safe:=true; positions=[]
	for index in 4800:
		sim.advance(1.0/60)
		lowest=minf(lowest,u.position.x)
		safe=safe and u.position.x>=Rules.BASE_START_X-.1
		if u.brain.repair_door!=null and u.position.distance_to(door.position)<=Rules.body_to_px(1): reached_leaf=true
		if index%30==0: positions.append({"time":sim.simulation_time,"x":u.position.x,"y":u.position.y,"purpose":u.brain.purpose})
		if session.repair_jobs.is_empty() and u.brain.route.is_empty(): break
	positions.append({"time":sim.simulation_time,"x":u.position.x,"y":u.position.y,"post":u.current_post,"purpose":u.brain.purpose,"completed":session.repair_jobs.is_empty() and u.brain.route.is_empty()})
	trajectories.append({"id":"H25","kind":"real_doorleaf_repair_return","positions":positions,"minimum_x":lowest,"paid":paid,"final_durability":door.durability})
	check(result.ok and result.unit==u and reached_leaf and door.durability>300 and paid>0 and paid<float(session.rules.repair.cost),"H25 The discounted repair uses a real carpenter approach, work and completed durability restoration","H25")
	check(safe and u.position.distance_to(home)<2 and u.current_post=="post_table_hall" and session.repair_jobs.is_empty(),"H25 The carpenter returns to the original legal indoor cover without walking along the ghost road","H25")
	for id in ["H09","H10","H15"]:
		rig(); u=human(id,"post_gate_inner",false); g=ghost("G12",49)
		var inside:=true; positions=[]
		for index in 480:
			sim.advance(1.0/60)
			inside=inside and sim.world.inside_base(u.position) and preload("res://src/ai/GuardPolicy.gd").can_stop(sim.world,u,u.position,u.floor_id)
			if index%30==0: positions.append({"time":sim.simulation_time,"x":u.position.x,"y":u.position.y,"post":u.current_post})
		trajectories.append({"id":id,"kind":"outside_enemy_no_chase","positions":positions})
		check(inside and not u.may_briefly_leave_base and not u.roster.has("hunt"),"K5 %s stays at legal indoor cover throughout an actual outside elite encounter" % id,id)

func _codex_battle_events() -> void:
	rig()
	check(session.codex.entry("G01").stage==0,"K7 Battle-local codex begins unseen before an actual ghost spawn")
	var u=human("H13"); var g=ghost("G01",115.4)
	check(session.codex.entry("H13").stage==1 and session.codex.entry("G01").stage==1,"K7 Actual player and enemy entry events unlock the line-art stage")
	g.hp=3
	var action:Dictionary=skill(u,{"target_id":g.instance_id})
	check(action.ok and session.codex.entry("G01").stage==2 and session.codex.entry("G01").skill_text==Data.units.G01["专属技能"],"K7 An actual execution resolves the defeated ghost's complete codex text")
	# This intentionally lost first node is an authored low-name fixture, not an
	# ordinary full-night balance result. No result, HP or RNG is written by test.
	if is_instance_valid(scene): scene.free()
	var Night=load("res://src/night/NightRun.gd")
	var Bridge=load("res://src/night/NightBattleBridge.gd")
	var path:="/tmp/ye-ci-p8-failed-night-%s-%d.json" % ["render" if capture else "test",OS.get_process_id()]
	var book_path:="/tmp/ye-ci-p8-failed-codex-%s-%d.json" % ["render" if capture else "test",OS.get_process_id()]
	var run=Night.new()
	check(run.new_roster_run("shouxiang","P8-actual-failed-night","",book_path).ok,"K7 A real roster night starts with a separately isolated codex path")
	check(run.codex.entry("ritual_example_incense").stage==1 and run.codex.entry("ritual_kaimian").stage==0,"K7 Entering a real night encounters only its actual current ritual")
	# Declared initial conditions: the book has one name; no scheduled enemy wave.
	run.state.names=1; run.state.incense=0
	for key in run.config.battle_profiles:
		run.config.battle_profiles[key].waves=[]
		run.config.battle_profiles[key].phase_waves=[]
	check(run.choose_node("n01").ok,"K7 The deliberate-loss fixture enters the actual first node")
	scene=preload("res://scenes/combat/Combat.tscn").instantiate(); add_child(scene)
	sim=scene.get_node("Simulation"); sim.set_physics_process(false)
	session=scene.get_node("Session")
	var bridge=Bridge.new()
	check(bridge.start(scene,run).ok,"K7 The real night bridge configures roster rules and live battle")
	# This fixture tests failure/codex, not replay: discard its pre-fixture recorder.
	if bridge.recording!=null: bridge.recording.stop(); bridge.recording=null
	roster=session.roster
	Clock.set_paused(true)
	var reader:Node2D
	for unit in sim.humans:
		if unit.unit_id=="H01": reader=unit
	g=ghost("G25",115)
	check(is_instance_valid(reader),"K7 The failed-night fixture retains the genuine initial H01")
	if not is_instance_valid(reader): return
	action=roster.cast(g,{"target_id":reader.instance_id})
	check(action.ok and session.names==0,"K7 Actual G25 erasure consumes the final name without an injected result")
	tick(11)
	check(session.result.get("outcome","")=="defeat" and session.result.get("reason","")=="P4_END_REGISTER_EXTINGUISHED" and session.result.get("killer_id","")=="G25","K7 The real extinguish window ends in defeat attributed to the actual eraser")
	var collected:Dictionary=bridge.collect(scene,run)
	check(run.accept_battle(collected).ok and run.state.phase=="mercy","K7 The actual failed result settles into the real night recovery decision")
	check(run.leave_node().ok and run.state.phase=="ended" and run.summary().outcome=="defeat","K7 Declining the recovery offer really ends the failed night")
	check(run.codex.entry("ritual_example_incense").stage==1,"K7 A failed night does not falsely resolve its current ritual")
	var recorded:=false
	for failure in run.codex.failures:
		if failure.seed==run.state.seed and failure.killer_id=="G25" and failure.reason=="P4_END_REGISTER_EXTINGUISHED": recorded=true
	check(recorded,"K7 The failed night records who erased the player with the real unit ID")
	check(run.save(path).ok and run.codex.save().ok,"K7 Actual failed-night state and codex save into isolated disk envelopes")
	var restored=Night.new()
	check(restored.load_save(path).ok and restored.state.last_battle.killer_id=="G25" and restored.codex.failures==run.codex.failures,"K7 Disk continuation retains the ended night and its actual eraser attribution")
	night_failure={"fixture":true,"initial_names":1,"initial_incense":0,"enemy":"G25","recording":false,"summary":run.summary(),"result":collected,"codex":run.codex.snapshot(),"save_path":path,"codex_path":book_path}

func _codex_ritual_completion() -> void:
	# An explicit short final-node fixture tests the genuine settlement boundary;
	# it is not evidence for full-night duration, balance or boss performance.
	if is_instance_valid(scene): scene.free()
	var Night=load("res://src/night/NightRun.gd")
	var Bridge=load("res://src/night/NightBattleBridge.gd")
	var rules:Dictionary=Data.night_rules.duplicate(true)
	rules.start_node="n10"
	var run=Night.new(rules)
	check(run.new_roster_run("shouxiang","P8-ritual-final-node-fixture").ok,"K7 An explicitly authored final-node fixture initializes through the normal roster-night API")
	for key in run.config.battle_profiles:
		run.config.battle_profiles[key].duration=.2
		run.config.battle_profiles[key].waves=[]
		run.config.battle_profiles[key].phase_waves=[]
	check(run.choose_node("n10").ok,"K7 The fixture enters the actual final node rather than injecting a victory summary")
	scene=preload("res://scenes/combat/Combat.tscn").instantiate(); add_child(scene)
	sim=scene.get_node("Simulation"); sim.set_physics_process(false); session=scene.get_node("Session")
	var bridge=Bridge.new()
	check(bridge.start(scene,run).ok,"K7 The final-node fixture starts in the shared battle bridge")
	if bridge.recording!=null: bridge.recording.stop(); bridge.recording=null
	roster=session.roster; Clock.set_paused(true)
	tick(.25)
	check(session.result.get("outcome","")=="victory" and session.result.get("reason","")=="P4_END_HELD_TO_DAYBREAK","K7 The declared short fixture reaches real daybreak victory through simulation")
	var result:Dictionary=bridge.collect(scene,run)
	check(run.accept_battle(result).ok and run.state.phase=="reward" and run.codex.entry("ritual_example_incense").stage==1,"K7 A won final battle still waits for the mandatory reward before resolving the ritual")
	var chosen:=false
	for offer in run.reward_options():
		if not bool(offer.get("allowed",false)): continue
		var target:=""
		if bool(offer.get("requires_target",false)):
			var targets:Array=run.target_options(str(offer.id))
			if targets.is_empty(): continue
			target=str(targets[0].uid)
		chosen=run.choose_reward(str(offer.id),target).ok
		if chosen: break
	check(chosen and run.state.phase=="ended" and run.codex.entry("ritual_example_incense").stage==2,"K7 Choosing the real final reward resolves only the genuinely completed current ritual")
	check(run.codex.entry("ritual_kaimian").stage==0,"K7 Other ritual texts are not falsely marked encountered by the completion fixture")
	ritual_completion_fixture={"fixture":true,"ordinary_full_night":false,"node_id":"n10","declared_duration":.2,"scheduled_waves":[],"recording":false,"summary":run.summary(),"codex":run.codex.snapshot()}

func _troops_and_counters() -> void:
	rig(); var u=human("T01"); var g=ghost("G12",115.2)
	var money:float=session.incense; var hp:float=u.hp
	var result:Dictionary=skill(u)
	u.receive_damage(10,g,"melee")
	check(result.ok and hp-u.hp<10 and near(session.incense,money) and event("troop_brace",u.instance_id),"T01 The free militia brace actually reduces an incoming real strike","T01")
	rig(); u=human("T02","post_gate_inner"); u.attacks_enabled=true; g=ghost("G12",52)
	hp=g.hp; result=skill(u,{"target_id":g.instance_id})
	check(result.ok and not sim.projectiles.is_empty(),"T02 The crossbow active produces a real travelling projectile","T02")
	tick(.6)
	check(g.hp<hp,"T02 The projectile really impacts and damages its target","T02")
	rig(); u=human("T03"); var friend=human("H17"); money=session.incense
	result=skill(u,{"target_id":friend.instance_id})
	check(result.ok and friend.roster.reserve_incense>0 and near(money-session.incense,float(friend.roster.reserve_incense)),"T03 The temple attendant really transfers the same incense currency to an adjacent ally","T03")
	rig(); u=human("T04"); g=ghost("G04",115)
	result=skill(u)
	check(result.ok and g.growth.statuses.has("revealed") and event("watch_drum",u.instance_id),"T04 The watch soldier really reveals a nearby hidden shadow","T04")
	rig(); u=human("H01"); g=ghost("G01",114)
	result=skill(u,{"target_id":g.instance_id})
	var ordinary:float=u.brain.channel.duration
	rig(); u=human("H01"); g=ghost("G25",114)
	result=skill(u,{"target_id":g.instance_id})
	check(result.ok and ordinary<u.brain.channel.duration,"K9 Faceless ordinary tide is actually quicker to purify than an unregistered clerk")
	rig(); u=human("H01"); g=ghost("G01",114)
	var blank=ghost("G26",115)
	check(roster.cast(blank).ok,"K9 The real blank page establishes its interference field")
	var names:float=session.names
	result=skill(u,{"target_id":g.instance_id})
	tick(u.brain.channel.duration+.1)
	check(result.ok and g.dead and near(names,session.names),"K9 A completed actual purification inside the blank field grants no name reward")
	# The copied-skill capability is internal to G19; player command arguments
	# cannot turn a cheap human into a free arbitrary caster.
	rig(); u=human("H04"); g=ghost("G12",115)
	money=session.incense; hp=g.hp
	result=skill(u,{"copy_id":"H20","target_id":g.instance_id})
	check(not result.ok and result.reason=="P8_INVALID_ARGUMENT" and near(session.incense,money) and near(g.hp,hp),"K1 Player unit_skill cannot inject an internal copy_id for free foreign abilities")
	result=skill(u,{"target_id":[]})
	check(not result.ok and near(session.incense,money),"K1 Malformed skill target types are rejected without any debit")
	session.input_locked=true
	result=skill(u)
	check(not result.ok and near(session.incense,money),"K1 Watch/replay input lock blocks player unit skills without side effects")

func _shot(name: String, resolution: Vector2i) -> void:
	get_window().size = resolution
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(true)
	var path := "res://docs/phase-reports/"+prefix+"-shots/"+name+".png"
	DirAccess.make_dir_recursive_absolute("res://docs/phase-reports/"+prefix+"-shots")
	var picture := get_viewport().get_texture().get_image()
	check(picture.get_size()==resolution,"Native capture "+name+" has its stated pixel dimensions")
	check(picture.save_png(path)==OK,"Native capture "+name+" saves actual rendered viewport")
	shots.append(path)

func _pairs() -> void:
	for pair in PAIRS:
		if (OS.get_cmdline_user_args().has("--pairs-human-only") or OS.get_cmdline_user_args().has("--humans-only")) and str(pair[0]).begins_with("G"): continue
		rig()
		var first = ghost(pair[0],114) if str(pair[0]).begins_with("G") else human(pair[0])
		var second = ghost(pair[1],115) if str(pair[1]).begins_with("G") else human(pair[1])
		if not is_instance_valid(first) or not is_instance_valid(second): continue
		# Authored side-by-side fixture positions; no runtime outcome is changed.
		first.position.x=Rules.body_to_px(113.5)
		second.position.x=Rules.body_to_px(115)
		scene.get_node("BattleCamera").set_left(Rules.body_to_px(100))
		var panel = scene.get_node("Decisions")
		panel.close_panel()
		scene.get_node("DebugOverlay").flags[2]=true
		await _shot("pair-%s-%s-battle-1080" % [pair[0],pair[1]],Vector2i(1920,1080))
		scene.get_node("DebugOverlay").flags[2]=false
		for unit in [first,second]:
			panel.select_unit(unit)
			await _shot("pair-%s-%s-card-%s-1440" % [pair[0],pair[1],unit.unit_id],Vector2i(2560,1440))
			await _shot("pair-%s-%s-card-%s-1080" % [pair[0],pair[1],unit.unit_id],Vector2i(1920,1080))
			await _shot("pair-%s-%s-card-%s-720" % [pair[0],pair[1],unit.unit_id],Vector2i(1280,720))
			panel.close_panel()

func _fixture_banner(text: String, initial := "初始香60/名8 · 作者预设接触位置") -> void:
	var layer:=CanvasLayer.new(); layer.layer=30; scene.add_child(layer)
	var label:=Label.new(); layer.add_child(label)
	label.position=Vector2(24,78); label.add_theme_font_size_override("font_size",20)
	label.add_theme_color_override("font_shadow_color",Color.BLACK); label.add_theme_constant_override("shadow_outline_size",6)
	label.text="P8 独立技能夹具 · "+initial+"\n"+text

func _feedback_frames() -> void:
	# These are real successful actions at frozen simulation time, separately
	# labelled from ordinary gameplay or complete-night evidence.
	for number in range(1,17):
		var id:="H%02d" % number
		rig()
		var post:="post_gate_inner" if id=="H09" else "post_table_hall" if id in ["H11","H15"] else "post_register"
		var u=human(id,post)
		var target_id:="G03" if id=="H05" else "G04" if id in ["H01","H06","H07"] else "G01" if id=="H13" else "G09" if id=="H12" else "G25" if id=="H08" else "G12"
		var g=ghost(target_id,49 if id=="H09" else 115.4)
		var args:Dictionary={"target_id":g.instance_id}
		var friend:Node2D
		if id in ["H03","H04","H07"]:
			friend=human("H17" if id=="H04" else "H09")
			if id in ["H03","H04"]: args.target_id=friend.instance_id
			if id=="H07": roster.status(friend,"stun",3,g)
		if id=="H02": session.names=2; args={}
		if id=="H10": g.hp=g.max_hp*.3
		if id=="H13": g.hp=3
		if id=="H11": args={"object_id":"hall_b"}
		if id=="H15":
			friend=human("H09","post_window_1"); args={"target_id":friend.instance_id}; u.motion_enabled=true
		var result:Dictionary=skill(u,args)
		check(result.ok,"Native H01–H16 feedback fixture "+id+" comes from an actual successful command")
		if id=="H05": roster.cast(g,{"target_id":u.instance_id})
		if id=="H09": hit(g,sim.world.get_node("door_outer"),4,"structure")
		if id=="H11": tick(2.2)
		if id=="H15": tick(.2)
		scene.get_node("Decisions").close_panel()
		scene.get_node("BattleCamera").set_left(Rules.body_to_px(40 if id=="H09" else 82 if id in ["H11","H15"] else 100))
		var initial:="初始香60/名2 · 作者预设低名册与接触位置" if id=="H02" else "初始香60/名8 · 精英初始30%生命 · 作者预设" if id=="H10" else "初始香60/名8 · 普通鬼初始3生命 · 作者预设" if id=="H13" else "初始香60/名8 · 作者预设接触位置"
		_fixture_banner("%s %s · %s" % [id,u.display_name,str(Data.units[id]["专属技能"])],initial)
		await _shot("skill-"+id+"-actual-1080",Vector2i(1920,1080))

func _face_codex_frames() -> void:
	rig(); var u=human("H09"); var artist=human("H32"); var thief=ghost("G28",115)
	check(roster.cast(thief,{"target_id":u.instance_id}).ok and u.roster.face_state=="faceless","Native face-state evidence starts with actual G28 theft")
	var panel=scene.get_node("Decisions")
	panel.select_unit(u)
	scene.get_node("BattleCamera").set_left(Rules.body_to_px(100))
	_fixture_banner("真实G28夺面 → H09无面 → H32暂面恢复；未直接改写面态")
	await _shot("face-actual-theft-faceless-1080",Vector2i(1920,1080))
	await _shot("face-actual-theft-faceless-720",Vector2i(1280,720))
	check(panel.portrait.material is ShaderMaterial and panel.portrait.material.get_shader_parameter("face_hidden")==true,"K8 The selected stolen portrait actually renders through the faceless interface")
	check(skill(artist,{"target_id":u.instance_id}).ok and u.roster.face_state=="faced","Native face-state evidence restores the face through the actual paid H32 skill")
	await _shot("face-actual-restored-faced-1080",Vector2i(1920,1080))
	await _shot("face-actual-restored-faced-720",Vector2i(1280,720))
	check(panel.portrait.material.get_shader_parameter("face_hidden")==false,"K8 The same portrait returns to its faced rendering without replacing the actor")
	panel.close_panel()
	var troop=human("T03")
	panel.select_unit(troop)
	await _shot("troop-T03-template-1080",Vector2i(1920,1080))
	await _shot("troop-T03-template-720",Vector2i(1280,720))
	check(panel.portrait.texture==null,"K4 Actual troop template has no fabricated named portrait in native rendering")
	panel.close_panel()
	var StorePanel=load("res://src/ui/CodexPanel.gd")
	var catalog_panel=StorePanel.new()
	var source=Codex.new("",false)
	if night_failure.has("codex"): source.restore(night_failure.codex)
	catalog_panel.setup(source)
	scene.add_child(catalog_panel)
	catalog_panel.open()
	for book in ["humans","ghosts","items","customs"]:
		catalog_panel.show_book(book)
		if book=="ghosts" and source.entry("G25").stage>0: catalog_panel.select_entry("G25")
		check(catalog_panel.current_book==book and not catalog_panel.heading.text.is_empty(),"K7 Native codex opens the real "+book+" book")
		await _shot("codex-"+book+"-1080",Vector2i(1920,1080))
		await _shot("codex-"+book+"-720",Vector2i(1280,720))
	check(catalog_panel.failure_text.text.contains("抹名吏"),"K7 Native codex failure history names the actual G25 eraser")
	catalog_panel.close()
