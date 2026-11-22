extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Paired ordinary routes. Each policy changes only its documented orders.
const REAR_POLICIES := {
	"rear-priest": {"posts": {"H03": "post_rear", "H06": "post_register"}},
	"rear-mage": {"posts": {"H03": "post_register", "H06": "post_rear"}},
	"rear-control": {},
	"rear-both": {"posts": {"H03": "post_rear", "H06": "post_rear"}},
	"rear-hall": {"posts": {"H03": "post_rear", "H06": "post_hall_door"}},
	"rear-train-watch": {"train": {"n03": "H06"}},
	"rear-train-relief": {"train": {"n03": "H01"}},
	"rear-hall-late": {"posts": {"H03": "post_rear", "H06": "post_hall_door"}, "delay": 11},
	"rear-hall-trained": {"posts": {"H03": "post_rear", "H06": "post_hall_door"}, "delay": 11, "train": {"n03": "H01"}},
	"rear-carry": {"train": {"n03": "H01"}, "recall": true},
	"rear-carry-up": {"train": {"n03": "H01", "n05": "H01"}, "recall": true},
	"rear-hall-return": {"posts": {"H03": "post_rear", "H06": "post_hall_door"}, "delay": 11, "train": {"n03": "H01"}, "recall": true},
	"rear-camp-heal": {"train": {"n03": "H01"}, "recall": true, "camp": {"n06": "H02"}},
	"rear-camp-book": {"train": {"n03": "H01"}, "recall": true, "camp": {"n06": "H08"}},
	"rear-camp-pair": {"train": {"n03": "H01"}, "recall": true, "camp": {"n06": "H08", "n09": "H02"}},
	"rear-eighth": {"posts": {"H03": "post_rear", "H06": "post_hall_door"}, "delay": 11, "train": {"n03": "H01", "n08": "H01"}, "recall": true},
}
const CAMP_POLICIES := ["camp-mirror","camp-fire","camp-mirror-up","camp-fire-up","camp-mirror-veteran","camp-fire-veteran","camp-mirror-relay","camp-fire-relay","camp-mirror-posts","camp-fire-posts","camp-mirror-lamp","camp-fire-lamp","camp-fire-early","camp-mirror-early","camp-fire-duo","camp-mirror-duo"]
const RESERVE_POLICIES := ["reserve-hire","reserve-upgrade","reserve-both","reserve-trained"] + CAMP_POLICIES

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [1,2,3] or (args.size() >= 2 and args[1] not in REAR_POLICIES and args[1] not in RESERVE_POLICIES and args[1] not in ["upgrade","register","hall","base","aid-register","aid-hall","watch","relief-open","relief-1","relief-4","relief-8","relief-10","relief-8-next","relief-8-recall","borrow","dispel","dispel-recall"]) or (args.size() == 3 and args[2] not in ["渡口","灯市","秋社"]) or args[0] not in ["0","1","2","3"]:
		quit(2)
		return
	var policy := args[1] if args.size() >= 2 else "base"
	if (policy in RESERVE_POLICIES or policy in ["borrow","dispel","dispel-recall"]) and args[0] != "2":
		quit(2)
		return
	if policy in REAR_POLICIES and args[0]!="0":
		quit(2)
		return
	var orders: Dictionary = REAR_POLICIES.get(policy,{})
	var camp := policy.begins_with("camp-")
	var compare_lamp := policy.ends_with("-lamp")
	var compare_posts := policy.ends_with("-posts") or compare_lamp
	var duo := policy.ends_with("-duo")
	var early := policy.ends_with("-early") or duo
	var relay := policy.ends_with("-relay") or compare_posts or early
	var two_levels := relay or policy.ends_with("-veteran")
	var reserve_id := "H18" if policy.begins_with("camp-mirror") else "H20"
	var upgraded := policy == "upgrade"
	var paired_talisman := policy in RESERVE_POLICIES or policy in ["borrow","dispel","dispel-recall"]
	var index := int(args[0])
	var faction: String = load("res://src/night/FactionOpening.gd").PAIRS.keys()[index]
	var night: RefCounted = load("res://src/night/NightRun.gd").new()
	var seed_text := args[2] if args.size() == 3 else "渡口"
	var started: Dictionary = night.new_p10_run("shouxiang","example",seed_text,"R01",[],"",faction)
	var report := {"seed":seed_text,"faction":faction,"steps":[],"foreign":[],"upgrade_at_n03":upgraded}
	var ok: bool = started.ok
	for turn in 60:
		if not ok or night.state.phase in ["ended","mercy"]: break
		var phase: String = night.state.phase
		var step := {"phase":phase}
		match phase:
			"map":
				var nodes: Array = night.available_nodes()
				step.choice = nodes[0].id
				var recall: bool = step.choice == "n05" and (policy in ["dispel-recall","relief-8-recall"] or orders.get("recall",false) or policy in RESERVE_POLICIES)
				if step.choice=="n03" and orders.has("posts"):
					step.orders = []
					for member in night.state.roster:
						var post: String = orders.posts.get(member.id,member.post)
						if member.post==post: continue
						var order: Dictionary = night.reserve_post(member.uid,post)
						step.orders.append({"id":member.id,"post":post,"ok":order.ok})
						ok = ok and order.ok
				if recall or (step.choice == "n03" and policy in ["register","hall"]):
					var post := "post_register" if recall or policy == "register" else "post_hall_door"
					step.orders = []
					for option in night.reserve_post_options():
						if option.to == post:
							var change: Dictionary = night.reserve_post(option.uid,post)
							step.orders.append({"move":option,"accepted":change.ok})
							if not change.ok: ok = false
				var checkpoint := OS.get_environment("YE_CI_FINAL_MAP_SAVE")
				if step.choice=="n10" and not checkpoint.is_empty():
					if not night.save(checkpoint).ok:
						quit(2)
						return
				ok = ok and night.choose_node(step.choice).ok
			"battle":
				var fifth: bool = night.state.current_node_id == "n05"
				var strengthen: bool = fifth and (camp or policy in ["reserve-upgrade","reserve-both","reserve-trained"])
				var train_reserve: bool = (night.state.current_node_id == "n08" and ((camp and policy.ends_with("-up")) or two_levels)) or (relay and not early and night.state.current_node_id == "n10")
				var second: bool = night.state.current_node_id == "n03"
				var aid_post := ""
				if second and (policy.begins_with("aid-") or policy=="relief-open"):
					aid_post = "post_register" if policy in ["aid-register","relief-open"] else "post_hall_door"
				var hire_early: bool = early and night.state.current_node_id == "n08"
				var ordered_id := "H19" if hire_early else ""
				if paired_talisman:
					if night.state.current_node_id == "n01": ordered_id = "H17"
					if second: ordered_id = "H19" if policy == "borrow" else "H22"
					if fifth and (camp or policy in ["reserve-hire","reserve-both","reserve-trained"]): ordered_id = "H24"
					if not ordered_id.is_empty(): aid_post = "post_register"
				if compare_posts and night.state.current_node_id == "n10":
					var path := "user://final-posts-%d.json" % OS.get_process_id()
					var saved: bool = night.save(path).ok
					if compare_lamp and not OS.get_environment("YE_CI_LAMP_CHECKPOINT").is_empty():
						night.save(OS.get_environment("YE_CI_LAMP_CHECKPOINT"))
					step.post_trials = []
					for post in ["post_register","post_hall_door"]:
						var branch: RefCounted = load("res://src/night/NightRun.gd").new()
						if not saved or not branch.load_save(path).ok:
							quit(2)
							return
						var trial: Dictionary = await fight(branch,faction,seed_text,false,post,false,"H19",true)
						step.post_trials.append(trial)
						if not trial.get("settled",false) or not trial.get("aid",{}).get("placed",false) or trial.aid.paid != 10:
							quit(2)
							return
					if compare_lamp:
						step.lamp_trials = []
						for post in ["post_register","post_hall_door"]:
							var branch: RefCounted = load("res://src/night/NightRun.gd").new()
							if not branch.load_save(path).ok:
								quit(2)
								return
							var tested: Dictionary = await fight(branch,faction,seed_text,false,post,false,"H19",true,false,1,[],true)
							step.lamp_trials.append(tested)
							if not tested.get("settled",false) or not tested.get("recruit_gear",{}).get("ok",false):
								quit(2)
								return
					step.gear_trials = []
					for items in [["I08"],["Y11"],["I08","Y11"]]:
						if not items.all(func(id): return int(night.state.growth.inventory.get(id,0)) > 0): continue
						var branch: RefCounted = load("res://src/night/NightRun.gd").new()
						if not branch.load_save(path).ok:
							quit(2)
							return
						var trial: Dictionary = await fight(branch,faction,seed_text,true,"",false,"",true,false,2,items)
						step.gear_trials.append(trial)
						if not trial.get("settled",false) or not trial.gear.all(func(r): return r.ok and r.before - r.after == 1 and r.paid == 0):
							quit(2)
							return
					DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
				var delay := -1.0
				if second and policy in ["relief-1","relief-4","relief-8","relief-10","relief-8-next","relief-8-recall"]:
					delay = float(policy.get_slice("-",1))
				if policy in REAR_POLICIES and second:
					delay = float(orders.get("delay",8))
				if fifth and policy=="relief-8-next":
					delay = 8.0
					ordered_id = "H02"
				var train_id: String = orders.get("train",{}).get(night.state.current_node_id,"")
				var result: Dictionary = await fight(night,faction,seed_text,(upgraded and second) or strengthen or train_reserve,aid_post,policy == "watch",ordered_id,paired_talisman,fifth and (policy == "reserve-trained" or camp),2 if train_reserve and two_levels else 1,[],hire_early,delay,train_id)
				step.battle = result
				ok = result.get("settled",false)
				if not train_id.is_empty(): ok = ok and result.get("target_training",{}).get("paid")==8
				if delay >= 0:
					ok = ok and result.get("relief",{}).get("placed",false)
				if not ordered_id.is_empty() and delay < 0:
					var receipt: Dictionary = result.get("aid",{})
					ok = ok and receipt.get("placed",false) and receipt.get("id") == ordered_id and receipt.get("paid") == (8.0 if fifth else 10.0)
				if hire_early:
					ok = ok and result.get("recruit_gear",{}).get("ok",false)
				if train_reserve:
					var payments: Array = result.get("upgrades",[])
					var expected := {"id":reserve_id,"ok":true,"paid":8.0}
					ok = ok and payments.size() == (2 if two_levels else 1) and payments.all(func(receipt): return receipt == expected)
				if strengthen:
					ok = ok and result.get("upgrades",[]) == [{"id":"H23","ok":true,"paid":8.0}]
				if fifth and (policy == "reserve-trained" or camp):
					ok = ok and result.get("aid_upgrade",{}) == {"id":"H24","ok":true,"paid":8.0}
				report.foreign.append_array(result.get("foreign_units",{}).values())
			"reward":
				if camp: step.offered = night.reward_options().map(func(card): return card.id)
				var chosen := false
				for card in night.reward_options():
					if not card.allowed or card.effect.kind in ["mutate","recruit"]: continue
					var targets: Array = night.target_options(card.id)
					if card.requires_target and targets.is_empty(): continue
					step.choice = card.id
					ok = night.choose_reward(card.id,targets[0].uid if card.requires_target else "").ok
					chosen = true
					break
				if not chosen:
					step.blocked_offers = night.state.offers.duplicate(true)
					ok = false
			"event":
				ok = false
				for event in night.event_options():
					if event.allowed:
						step.choice = event.id
						ok = night.resolve_event(event.id).ok
						break
			"market":
				if camp: step.offered = night.state.offers.map(func(card): return card.id)
				ok = night.leave_node().ok
			"rest":
				var reserve: String = orders.get("camp",{}).get(night.state.current_node_id,"")
				if not reserve.is_empty():
					var id := reserve
					var cash: float = night.state.incense
					var accepted := await rest_via_menu(night,id)
					step.hire = {"id":id,"paid":cash-night.state.incense,"saved_and_reloaded":accepted}
					ok = accepted and is_equal_approx(step.hire.paid,12.0)
				elif camp and (night.state.current_node_id == "n06" or (relay and night.state.current_node_id == "n09" and (night.state.roster.is_empty() or duo))):
					if night.state.current_node_id == "n09":
						reserve_id = "H20" if reserve_id == "H18" else "H18"
					var id := reserve_id
					var before: float = night.state.incense
					step.options = night.rest_reserve_options()
					var hired := await rest_via_menu(night,id)
					step.hire = {"id":id,"paid":before-night.state.incense,"saved_and_reloaded":hired}
					ok = hired and is_equal_approx(step.hire.paid,12.0)
				else: ok = night.finish_rest().ok
			_: ok = false
		if policy in REAR_POLICIES:
			step.survivors = night.state.roster.map(func(u): return {"uid":u.uid,"id":u.id,"post":u.post,"hp":u.hp,"max_hp":u.max_hp})
		if policy.begins_with("relief-") or policy in REAR_POLICIES:
			step.roster_after = night.state.roster.map(func(unit): return [unit.uid,unit.id,unit.post])
		for unit in night.state.roster:
			if root.get_node("Data").get_unit(unit.id).get("所属","") != faction and not unit.id in report.foreign:
				report.foreign.append(unit.id)
		report.steps.append(step)
	report.phase = night.state.phase
	report.outcome = night.state.outcome
	report.reason = night.state.reason
	report.policy_finished = ok and night.state.phase in ["ended","mercy"]
	var filename := "ordinary-route-%s%d.json" % ["upgrade-" if upgraded else "",index]
	if args.size() == 3 or policy not in ["base","upgrade"]:
		filename = "post-%s-%s-%d.json" % [seed_text,policy,index]
	FileAccess.open("res://tools/faction_baseline/" + filename,FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	if OS.get_environment("YE_CI_DEBRIEF_SAVE") != "" and report.policy_finished:
		night.save(OS.get_environment("YE_CI_DEBRIEF_SAVE"))
	print("ROUTE ",faction," ",report.phase," ",report.outcome)
	await create_timer(0.6).timeout
	quit(0 if report.policy_finished else 1)

func rest_via_menu(night: RefCounted, id: String) -> bool:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "/tmp/ye-ci-route-rest-%d.json" % OS.get_process_id()
	root.add_child(host)
	var previous_ids: Array = night.state.roster.map(func(member): return member.uid)
	var saved: bool = night.save(host.save_path).ok
	if saved: host.continue_run()
	var button: Button = host.panel.buttons.get("reserve_"+id)
	var loaded := false
	if is_instance_valid(button) and not button.disabled:
		if OS.get_environment("YE_CI_CAPTURE_REST") == "1" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg("/tmp/ye-ci-rest-menu.jpg",0.86)
		button.pressed.emit()
		loaded = night.load_save(host.save_path).ok and night.state.phase == "map" and night.state.roster.size() == previous_ids.size()+1 and night.state.roster.any(func(member): return member.id == id and member.uid not in previous_ids) and previous_ids.all(func(uid): return night.state.roster.any(func(member): return member.uid == uid))
	DirAccess.remove_absolute(host.save_path)
	host.free()
	return loaded
