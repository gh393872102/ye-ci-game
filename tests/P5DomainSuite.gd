extends Node
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []
var report_prefix := "p5-domain"
var Run
var Save
func check(value:bool,label:String) -> void:
	checks+=1
	results.append({"label":label,"passed":value})
	print(("PASS: " if value else "FAIL: ") + label)
	if not value: failures.append(label)
func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report-prefix="):
			report_prefix = argument.trim_prefix("--report-prefix=")
	call_deferred("run")
func make(mode:String):
	var night = Run.new()
	night.new_run(mode,"example","review-full-cap")
	night.choose_node("n01")
	return night
func cap(night) -> void:
	for key in night.config.build_caps:
		night.state.build[key] = night.config.build_caps[key]
func assert_options(night,label:String) -> void:
	night.state.phase="reward"
	night.state.offers=night._rewards()
	var options = night.reward_options()
	var build := false
	var survives := 0
	check(options.size()==3,label+" exactly three")
	for card in options:
		build = build or card.category=="build"
		survives += 1 if card.category=="survival" else 0
		check(card.allowed,label+" usable "+card.id)
	check(build and survives<=1,label+" build and at most one survival")
func malformed(night,bad:Dictionary,label:String) -> void:
	check(Save.save("/tmp/p5-malformed-nested.save",bad).ok,"malformed encoded "+label)
	var prior = JSON.stringify(night.state)
	check(not night.load_save("/tmp/p5-malformed-nested.save").ok,label+" rejected")
	check(JSON.stringify(night.state)==prior,label+" rejection preserves current state")
func check_reserve_posts() -> void:
	var night = Run.new()
	night.new_p10_run("shouxiang","example","渡口","R01",[],"","守香司")
	var uid: String = night.state.roster[0].uid
	var incense: float = night.state.incense
	for post in ["post_table_hall","post_stair_head"]:
		check(night.reserve_post(uid,post).ok,"ordinary map accepts "+post)
		check(night.state.incense==incense and night.state.roster[0].post==post,"free assignment recorded "+post)
		check(not night.reserve_post(uid,post).ok,"cannot reserve current post twice")
	var path := "user://posts-%d.json"%OS.get_process_id()
	check(night.save(path).ok and night.load_save(path).ok and night.state.roster[0].post=="post_stair_head","upper post survives map reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	night.choose_node("n01")
	check(not night.reserve_post(uid,"post_table_hall").ok,"live battle rejects free map reassignment")
func check_camp_treatment() -> void:
	var night = Run.new()
	night.new_p10_run("shouxiang","example","渡口","R01",[],"","守香司")
	var patient: Dictionary = night.state.roster[0]
	var partner: Dictionary = night.state.roster[1]
	patient.hp = 8.0
	partner.hp = 10.0
	check(not night.treat_at_rest(patient.uid).ok,"treatment rejected outside camp")
	night.state.current_node_id="n06"
	night.state.phase="rest"
	night.state.incense=3
	check(not night.treat_at_rest(patient.uid).ok and patient.hp==8,"insufficient incense preserves health")
	night.state.incense=4
	var names: float = night.state.names
	patient.hp = patient.max_hp-1
	check(not night.treat_at_rest(patient.uid).ok and night.state.incense==4,"normal rest already reaches cap; no needless fee")
	patient.hp = 8.0
	check(not night.treat_at_rest("unknown_uid").ok and night.state.incense==4,"stale treatment target preserves balance")
	check(night.treat_at_rest(patient.uid).ok and patient.hp==8+patient.max_hp*0.5,"focused care restores half maximum health")
	check(partner.hp==10 and night.state.incense==0 and night.state.names==names,"treatment pays four without team heal or supplies")
	check(not night.treat_at_rest(patient.uid).ok and night.state.phase=="map","completed camp rejects second treatment")

func run() -> void:
	await get_tree().process_frame
	Run=load("res://src/night/NightRun.gd")
	Save=load("res://src/night/NightSave.gd")
	check_reserve_posts()
	check_camp_treatment()
	var white = make("duoming")
	white.state.roster=[]
	for index in 120: white.state.roster.append(white._unit("G01","ghost_main_path"))
	cap(white)
	assert_options(white,"full white tide capped build")
	var choice = {}
	for offer in white.state.offers:
		if offer.effect.kind=="mutate": choice=offer
	check(not choice.is_empty(),"full white has real mutation route")
	if not choice.is_empty():
		var unit = white.target_options(choice.id)[0]
		var uid = unit.uid
		white.state.roster[0].hp = white.state.roster[0].max_hp*.4
		check(white.choose_reward(choice.id,uid).ok,"formula reward applies")
		var mutated=white.state.roster[0]
		check(mutated.uid==uid and mutated.id==choice.effect.form_id and mutated.mutation_count==1,"formula identity and count preserved")
		check(is_equal_approx(mutated.hp/mutated.max_hp,.4) and white.state.roster.size()==120,"formula damage ratio and capacity preserved")
	var elites=make("duoming")
	elites.state.roster=[]
	for index in 120:
		var unit=elites._unit("G12","ghost_main_path")
		unit.equipment_id="ritual_incense"
		unit.mutation_count=1
		elites.state.roster.append(unit)
	cap(elites)
	assert_options(elites,"full equipped elite tide capped build")
	var humans=make("shouxiang")
	humans.state.roster.append(humans._unit("T01","post_inner_gate"))
	humans.state.roster.append(humans._unit("T04","post_hall_door"))
	for unit in humans.state.roster: unit.equipment_id="ritual_incense"
	cap(humans)
	assert_options(humans,"full troops equipped humans capped build")
	var packed=make("shouxiang")
	packed.state.roster=packed.state.roster.slice(0,3)
	for unit in packed.state.roster: unit.post="post_gate_inner"
	packed.state.phase="market"
	packed.state.offers=[packed.config.rewards.r_villager.duplicate(true)]
	var funds=packed.state.incense
	check(not packed.buy_offer("r_villager").ok and packed.state.incense==funds,"market rejects fourth post occupant without payment")
	packed.state.phase="reward"
	check(not packed.choose_reward("r_villager").ok and packed.state.roster.size()==3,"reward rejects fourth post occupant")
	check(packed._effect_reason({"kind":"recruit","unit_id":"H09","count":1,"post":"post_inner_gate"},"")=="P5_NAMED_PRESENT","named duplicate rejected")
	var night=make("shouxiang")
	var base=night.state.duplicate(true)
	var bad=base.duplicate(true); bad.stats.battles=["not a battle"]
	malformed(night,bad,"nested battle history")
	bad=base.duplicate(true); bad.before_battle.roster[0].max_hp="broken"
	malformed(night,bad,"before-battle roster")
	bad=base.duplicate(true); bad.ledger[0].detail="broken"
	malformed(night,bad,"ledger detail")
	bad=base.duplicate(true); bad.selected_rewards=[{"id":"r_thick_name","title":"a","node_id":"n01","target_uid":{}}]
	malformed(night,bad,"reward target shape")
	bad=base.duplicate(true); bad.build.incense_regen_delta=999
	malformed(night,bad,"build beyond cap")
	bad=base.duplicate(true); bad.battle_snapshot={"version":1,"actors":[],"structures":[],"shots":[],"session":{},"tide":{},"simulation":{},"bridge":"bad"}
	malformed(night,bad,"snapshot shell")
	bad=base.duplicate(true); bad.fallen=[{"uid":"fallen","id":"H01","hp":1}]
	malformed(night,bad,"fallen still alive")
	bad=base.duplicate(true); bad.roster[0].post="courtyard_middle"
	malformed(night,bad,"unknown post")
	bad=base.duplicate(true); bad.visited=["n01","n10"]; bad.current_node_id="n10"
	malformed(night,bad,"skipped route")
	bad=base.duplicate(true); bad.stats.elapsed={"n":1}
	malformed(night,bad,"elapsed wrong type")
	bad=base.duplicate(true); bad.last_battle={"outcome":"victory"}
	malformed(night,bad,"partial last battle")
	var report := {"phase":"P5Domain","engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"results":results,"fixture_policy":"Isolated domain fixtures construct capped rosters/builds and malformed checksummed saves. These are rule tests, not full-night victory evidence."}
	for suffix in ["-test-results.json","-results.json"]:
		var file := FileAccess.open("res://docs/phase-reports/" + report_prefix + suffix,FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report,"\t"))
	DirAccess.remove_absolute("/tmp/p5-malformed-nested.save")
	print("P5Domain RESULT: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
