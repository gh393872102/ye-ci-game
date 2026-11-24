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
	"rear-camp-ritual": {"train":{"n03":"H01"},"recall":true,"camp":{"n06":"H08","n09":"H02"},"ritual_gear":true},
	"rear-read-gear": {"train":{"n03":"H01"},"recall":true,"camp":{"n06":"H08","n09":"H02"},"ritual_gear":true,"read":true},
	"rear-read-breaker": {"train":{"n03":"H01"},"recall":true,"camp":{"n06":"H08","n09":"H02"},"ritual_gear":true,"read":true,"tag":"破门"},
	"rear-read-beam": {"train":{"n03":"H01"},"recall":true,"camp":{"n06":"H08","n09":"H02"},"ritual_gear":true,"read":true,"tag":"上楼"},
	"rear-read-beam-late": {"train":{"n03":"H01"},"recall":true,"camp":{"n06":"H08","n09":"H02"},"ritual_gear":true,"read":true,"tag":"上楼","after":180},
	"rear-read-bare": {"train":{"n03":"H01"},"recall":true,"camp":{"n06":"H08","n09":"H02"},"read":true},
	"rear-camp-book": {"train": {"n03": "H01"}, "recall": true, "camp": {"n06": "H08"}},
	"rear-camp-pair": {"train": {"n03": "H01"}, "recall": true, "camp": {"n06": "H08", "n09": "H02"}},
	"rear-eighth": {"posts": {"H03": "post_rear", "H06": "post_hall_door"}, "delay": 11, "train": {"n03": "H01", "n08": "H01"}, "recall": true},
}
const FIFTH_TRAIN := {
	"repair-early": [],
	"repair-late": [],
	"repair-inner": [],
	"repair-inner-qing": ["H03"],
	"repair-inner-shuang": ["H06"],
	"repair-inner-pair-eighth": ["H06"],
	"repair-inner-pair-final": ["H06"],
	"repair-inner-pair-final-read": ["H06"],
	"repair-inner-qing-carry": ["H06"],
	"repair-inner-qing-control": ["H06"],
	"repair-inner-qing-hold": ["H06"],
	"repair-inner-pair-both": ["H06"],
	"repair-outer": [],
	"repair-forward": [],
	"repair-forward-control": [],
	"trio-fifth-control": [],
	"trio-fifth-wan": ["H01"],
	"trio-fifth-qing": ["H03"],
	"trio-fifth-shuang": ["H06"],
	"trio-fifth-split": ["H03","H06"],
	"trio-fifth-stack": ["H03","H03"],
	"trio-fifth-cap": ["H03","H03","H03"],
	"trio-fifth-mixed": ["H03","H03","H06"],
	"trio-fifth-lamp-two": ["H06","H06"],
	"trio-fifth-lamp-three": ["H06","H06","H06"],
	"trio-fifth-lamp-mixed": ["H03","H06","H06"],
}
# Buy the same guard at the same price, varying only the eighth battle's posts.
const EIGHTH_GUARD := {
	"repair-inner-eighth-treat": {"rear":false,"aid":false},
	"repair-inner-eighth-rear": {"rear":true,"aid":false},
	"repair-inner-eighth-front": {"rear":false,"aid":true},
	"repair-inner-eighth-drill": {"rear":true,"aid":true},
	"repair-inner-final-guard": {"rear":true,"aid":true,"final":"H02"},
	"repair-inner-final-priest": {"rear":true,"aid":true,"final":"H08"},
	"repair-inner-eighth-reader": {"rear":true,"aid":true},
	"repair-inner-eighth-relay": {"rear":true,"aid":true},
}
const REGROUP_TRAIN := {"trio-regroup":"","trio-train-wan":"H01","trio-train-shen":"H08","trio-gear-shen":""}
const FIFTH_POSTS := {
	"trio-aid": {"H01":"post_register","H03":"post_register","H06":"post_register"},
	"trio-control": {"H01":"post_register","H03":"post_register","H06":"post_register"},
	"reader-stair": {"H01":"post_stair_head","H06":"post_register"},
	"trio-stair": {"H01":"post_stair_head","H03":"post_register","H06":"post_register"},
	"reader-hall": {"H01":"post_hall_door","H06":"post_register"},
	"reader-table": {"H01":"post_table_hall","H06":"post_register"},
	"reader-rear": {"H01":"post_rear","H06":"post_register"},
	"reader-control": {"H01":"post_register","H06":"post_register"},
	"trio-priest": {"H01":"post_register","H03":"post_rear","H06":"post_register"},
	"trio-lamp": {"H01":"post_register","H03":"post_register","H06":"post_rear"},
	"trio-reader": {"H01":"post_rear","H03":"post_register","H06":"post_register"},
	"trio-return": {"H01":"post_rear","H03":"post_register","H06":"post_register"},
	"trio-table": {"H01":"post_table_hall","H03":"post_register","H06":"post_register"},
}
const THIRD_POSTS := {
	"camp-fire-stock-pin-return-early":"post_register",
	"camp-fire-stock-pin-veteran-rear-early":"post_register",
	"camp-fire-stock-pin-veteran4-early":"post_register",
	"camp-fire-stock-pin-veteran8-early":"post_register",
	"camp-fire-stock-pin-late4-early":"post_register",
	"camp-fire-stock-pin-late8-early":"post_register",
	"camp-fire-stock-pin-window-early":"post_register",
	"camp-fire-stock-pin-rear-early":"post_register",
	"camp-fire-stock-hold-window-early":"post_window_1",
	"camp-fire-stock-hold-hall-early":"post_hall_door",
	"camp-fire-stock-hold-stair-early":"post_stair_head",
	"camp-fire-stock-hold-gear-early":"post_register",
}
const SECOND_POSTS := {
	"camp-fire-stock-relieve-early":"post_window_1",
	"camp-fire-stock-window-early":"post_window_1",
	"camp-fire-stock-rear-early":"post_rear",
}
const SECOND_RELIEF := {"camp-fire-stock-aid4-early":4.0,"camp-fire-stock-aid8-early":8.0}
const CAMP_POLICIES := ["camp-mirror","camp-fire","camp-mirror-up","camp-fire-up","camp-mirror-veteran","camp-fire-veteran","camp-mirror-relay","camp-fire-relay","camp-mirror-posts","camp-fire-posts","camp-mirror-lamp","camp-fire-lamp","camp-fire-early","camp-fire-pin-early","camp-fire-pin-single-early","camp-fire-stock-early","camp-fire-stock-window-early","camp-fire-stock-rear-early","camp-fire-stock-relieve-early","camp-fire-stock-aid4-early","camp-fire-stock-aid8-early","camp-mirror-early","camp-fire-duo","camp-mirror-duo"]
const RESERVE_POLICIES := ["reserve-hire","reserve-upgrade","reserve-both","reserve-trained"] + CAMP_POLICIES

const PIN_POLICIES := ["bone-book","bone-book-seal","bone-hall","bone-hall-seal","bone-early","bone-early-seal"]
const MARTIAL_POLICIES := ["martial-base","martial-swap","martial-pair","martial-iron","martial-iron-rear","martial-iron-camp","martial-iron-relay","martial-early-book","martial-early-door","martial-early-gear"]

func run() -> void:
	var rear_policies := REAR_POLICIES.duplicate()
	var placements := FIFTH_POSTS.duplicate()
	for key in FIFTH_TRAIN: placements[key] = FIFTH_POSTS["trio-reader"]
	for key in ["repair-forward","repair-forward-control"]:
		placements[key] = FIFTH_POSTS["trio-reader"].duplicate()
		placements[key].H06 = "post_hall_door"
	placements["repair-inner-qing-carry"] = FIFTH_POSTS["trio-priest"]
	for key in EIGHTH_GUARD: placements[key] = FIFTH_POSTS["trio-priest"]
	for key in REGROUP_TRAIN: placements[key] = FIFTH_POSTS["trio-reader"]
	for key in placements:
		var split: Dictionary = REAR_POLICIES["rear-read-beam"].duplicate(true)
		split.erase("recall")
		split.fifth_posts = placements[key]
		if key in FIFTH_TRAIN and not FIFTH_TRAIN[key].is_empty():
			split.train.n05 = FIFTH_TRAIN[key][0]
		if key in EIGHTH_GUARD: split.train.n05 = "H06"
		if key in REGROUP_TRAIN and REGROUP_TRAIN[key] != "": split.train.n08 = REGROUP_TRAIN[key]
		if key.begins_with("trio-") or key.begins_with("repair-"):
			split.posts = REAR_POLICIES["rear-hall-trained"].posts
			split.delay = REAR_POLICIES["rear-hall-trained"].delay
		rear_policies[key] = split
	var args := OS.get_cmdline_user_args()
	if args.size() not in [1,2,3] or (args.size() >= 2 and args[1] not in rear_policies and args[1] not in RESERVE_POLICIES and args[1] not in THIRD_POSTS and args[1] not in MARTIAL_POLICIES and args[1] not in PIN_POLICIES and args[1] not in ["upgrade","register","hall","base","aid-register","aid-hall","watch","relief-open","relief-1","relief-4","relief-8","relief-10","relief-8-next","relief-8-recall","borrow","dispel","dispel-recall"]) or (args.size() == 3 and args[2] not in ["渡口","灯市","秋社","松溪","槐桥","石埠"]) or args[0] not in ["0","1","2","3"]:
		quit(2)
		return
	var policy := args[1] if args.size() >= 2 else "base"
	if (policy in RESERVE_POLICIES or policy in THIRD_POSTS or policy in PIN_POLICIES or policy in ["borrow","dispel","dispel-recall"]) and args[0] != "2":
		quit(2)
		return
	if policy in rear_policies and args[0]!="0":
		quit(2)
		return
	repair_policy = policy if policy.begins_with("repair-") and policy!="repair-forward-control" else ""
	if policy.begins_with("repair-inner-"): repair_policy = "repair-inner"
	var orders: Dictionary = rear_policies.get(policy,{})
	var martial := policy in MARTIAL_POLICIES
	if martial and args[0]!="1":
		quit(2)
		return
	var timed_veteran := policy in ["camp-fire-stock-pin-veteran4-early","camp-fire-stock-pin-veteran8-early"]
	var keep_pin_rear := policy in ["camp-fire-stock-pin-veteran-rear-early","camp-fire-stock-pin-return-early"]
	var train_third_guard := timed_veteran or keep_pin_rear
	var early_pin := policy.begins_with("bone-early")
	var camp := policy.begins_with("camp-")
	var stock_route := policy == "camp-fire-stock-early" or policy in SECOND_POSTS or policy in SECOND_RELIEF or policy in THIRD_POSTS
	var pin_route := stock_route or policy in ["camp-fire-pin-early","camp-fire-pin-single-early"]
	var compare_lamp := policy.ends_with("-lamp")
	var compare_posts := policy.ends_with("-posts") or compare_lamp
	var duo := policy.ends_with("-duo")
	var early := policy.ends_with("-early") or duo
	var relay := (camp and policy.ends_with("-relay")) or compare_posts or early
	var two_levels := (relay or policy.ends_with("-veteran")) and policy != "camp-fire-pin-single-early"
	var reserve_id := "H18" if policy.begins_with("camp-mirror") else "H20"
	var upgraded := policy == "upgrade"
	var paired_talisman := policy in THIRD_POSTS or policy in RESERVE_POLICIES or policy in PIN_POLICIES or policy in ["borrow","dispel","dispel-recall"]
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
				var recall: bool = step.choice == "n05" and (policy in ["dispel-recall","relief-8-recall"] or orders.get("recall",false) or policy in RESERVE_POLICIES or policy in PIN_POLICIES)
				if step.choice=="n03" and policy=="martial-swap":
					var pair: Array = night.martial_swap_pair()
					if pair.size()!=2 or not night.swap_martial_posts(pair[0].uid,pair[1].uid).ok:
						quit(2)
						return
				var post_orders := {}
				match step.choice:
					"n03": post_orders = orders.get("posts",{})
					"n05": post_orders = orders.get("fifth_posts",{})
					"n08":
						if policy in EIGHTH_GUARD and EIGHTH_GUARD[policy].rear: post_orders = {"H01":"post_rear"}
						if policy in ["trio-return","repair-inner-pair-eighth","repair-inner-pair-both"]: post_orders = {"H01":"post_register"}
					"n10":
						if policy in EIGHTH_GUARD or policy in ["repair-inner-qing-control","repair-inner-qing-carry","repair-inner-qing-hold"]:
							post_orders = {"H01":"post_register","H03":"post_register"}
						elif policy.begins_with("repair-inner-pair-"):
							post_orders = {"H01":"post_rear" if policy.ends_with("-eighth") else "post_register"}
				if step.choice=="n03" and (policy=="camp-fire-stock-relieve-early" or policy in THIRD_POSTS): post_orders = {"H23":"post_register"}
				if step.choice=="n08" and policy=="camp-fire-stock-pin-return-early": post_orders = {"H24":"post_register"}
				if step.choice=="n05" and policy in THIRD_POSTS: post_orders = {"H22":THIRD_POSTS[policy]}
				if not post_orders.is_empty():
					step.orders = []
					for member in night.state.roster:
						var post: String = post_orders.get(member.id,member.post)
						if member.post==post: continue
						var order: Dictionary = night.reserve_post(member.uid,post)
						step.orders.append({"id":member.id,"post":post,"ok":order.ok})
						ok = ok and order.ok
				if recall or (step.choice == "n03" and policy in ["register","hall","martial-pair"]):
					var post := "post_register" if recall or policy in ["register","martial-pair"] else "post_hall_door"
					step.orders = []
					for option in night.reserve_post_options():
						if option.to == post:
							var change: Dictionary = night.reserve_post(option.uid,post)
							step.orders.append({"move":option,"accepted":change.ok})
							if not change.ok: ok = false
				var pin_map := OS.get_environment("YE_CI_PIN_MAP")
				if policy in PIN_POLICIES and step.choice=="n05" and not pin_map.is_empty() and not night.save(pin_map).ok:
					quit(2)
					return
				var patrol_map := OS.get_environment("YE_CI_PATROL_MAP")
				if martial and step.choice=="n05" and not patrol_map.is_empty() and not night.save(patrol_map).ok:
					quit(2)
					return
				var checkpoint := OS.get_environment("YE_CI_FINAL_MAP_SAVE")
				if step.choice=="n10" and not checkpoint.is_empty():
					if not night.save(checkpoint).ok:
						quit(2)
						return
				ok = ok and night.choose_node(step.choice).ok
			"battle":
				var fifth: bool = night.state.current_node_id == "n05"
				var strengthen: bool = fifth and not pin_route and (camp or policy in ["reserve-upgrade","reserve-both","reserve-trained"])
				var train_reserve: bool = (night.state.current_node_id == "n08" and ((camp and policy.ends_with("-up")) or two_levels or pin_route)) or (relay and not early and night.state.current_node_id == "n10")
				var second: bool = night.state.current_node_id == "n03"
				var aid_post := ""
				if second and (policy.begins_with("aid-") or policy=="relief-open"):
					aid_post = "post_register" if policy in ["aid-register","relief-open"] else "post_hall_door"
				var hire_early: bool = early and night.state.current_node_id == "n08"
				var ordered_id := "H19" if hire_early else ""
				if hire_early and stock_route and night.state.growth.inventory.get("I08",0)==0:
					ordered_id = "H17"
				if policy in EIGHTH_GUARD and EIGHTH_GUARD[policy].aid and night.state.current_node_id=="n08":
					ordered_id = "H06"
					aid_post = "post_register"
				if policy in ["martial-iron","martial-iron-rear","martial-iron-camp","martial-iron-relay","martial-early-book","martial-early-door","martial-early-gear"] and second:
					aid_post = "post_register" if policy!="martial-iron" else "post_hall_door"
					ordered_id = "H09"
				if fifth and policy in ["martial-early-book","martial-early-door","martial-early-gear"]:
					ordered_id = "H12"
					aid_post = "post_register" if policy!="martial-early-door" else "post_hall_door"
				if paired_talisman:
					if night.state.current_node_id == "n01": ordered_id = "H17"
					if second: ordered_id = "H24" if early_pin else ("H19" if policy == "borrow" else "H22")
					if fifth and not early_pin and (policy in PIN_POLICIES or camp or policy in ["reserve-hire","reserve-both","reserve-trained"]): ordered_id = "H24"
					if not ordered_id.is_empty(): aid_post = SECOND_POSTS.get(policy,"post_register") if second else "post_register"
					if second and policy in THIRD_POSTS: aid_post = "post_window_1"
					if fifth and policy=="camp-fire-stock-pin-window-early": aid_post = "post_window_1"
					if fifth and (keep_pin_rear or policy=="camp-fire-stock-pin-rear-early"): aid_post = "post_rear"
					if fifth and policy.begins_with("bone-hall"): aid_post = "post_hall_door"
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
				if fifth and (timed_veteran or policy in ["camp-fire-stock-pin-late4-early","camp-fire-stock-pin-late8-early"]):
					delay = 4.0 if policy.ends_with("4-early") else 8.0
					aid_post = ""
				if second and policy in SECOND_RELIEF:
					delay = SECOND_RELIEF[policy]
					aid_post = ""
				if second and policy in ["relief-1","relief-4","relief-8","relief-10","relief-8-next","relief-8-recall"]:
					delay = float(policy.get_slice("-",1))
				if policy in rear_policies and second:
					delay = float(orders.get("delay",8))
				if fifth and policy=="relief-8-next":
					delay = 8.0
					ordered_id = "H02"
				var train_id: String = orders.get("train",{}).get(night.state.current_node_id,"")
				if fifth and train_third_guard: train_id = "H22"
				if policy=="repair-inner-eighth-reader" and night.state.current_node_id=="n08": train_id = "H01"
				var items: Array = []
				if fifth and orders.get("ritual_gear",false):
					for item in ["I17","Y01","Y11"]:
						if policy == "trio-gear-shen" and item == "Y11": continue
						if night.state.growth.inventory.get(item,0)>0: items.append(item)
				var wearer := "H01" if not items.is_empty() else ""
				if fifth and policy=="camp-fire-stock-hold-gear-early":
					wearer = "H22"
					for item in ["I12","Y05"]:
						if night.state.growth.inventory.get(item,0)>0: items.append(item)
				if fifth and policy=="martial-early-gear":
					wearer = "H09"
					for item in ["Y11","I11"]:
						if night.state.growth.inventory.get(item,0)>0: items.append(item)
				if policy == "trio-gear-shen" and night.state.current_node_id == "n08":
					wearer = "H08"
					for item in ["I08","Y11"]:
						if night.state.growth.inventory.get(item,0)>0: items.append(item)
				var additional: Array = FIFTH_TRAIN.get(policy,[]).slice(1) if fifth else []
				if train_reserve and policy in THIRD_POSTS and not night.state.roster.is_empty() and (night.state.roster.size()>1 or night.state.roster[0].id!=reserve_id):
					train_reserve = false
					train_id = reserve_id if night.state.roster.any(func(u): return u.id==reserve_id) else night.state.roster[0].id
					additional = [train_id]
				var final_read: bool = policy=="repair-inner-pair-final-read" and night.state.current_node_id=="n10"
				if final_read: train_id = "H01"
				if (policy in EIGHTH_GUARD or policy in ["repair-inner-qing-control","repair-inner-qing-carry"]) and night.state.current_node_id=="n10":
					final_read = true
					reading_limit = 1
				probe_boss_gate = final_read and night.state.roster.any(func(u): return u.id=="H01")
				var drill_aid: bool = (policy=="repair-inner-eighth-drill" or EIGHTH_GUARD.get(policy,{}).has("final")) and night.state.current_node_id=="n08"
				var result: Dictionary = await fight(night,faction,seed_text,(upgraded and second) or strengthen or train_reserve,aid_post,policy == "watch",ordered_id,paired_talisman,drill_aid or (fifth and not train_third_guard and (policy == "reserve-trained" or camp)),2 if train_reserve and two_levels else 1,items,hire_early and ordered_id=="H19",delay,train_id,wearer,final_read or (fifth and orders.get("read",false)),"破门" if final_read else orders.get("tag",""),orders.get("after",0),false,false,additional,ordered_id=="H24" and policy in PIN_POLICIES and policy.ends_with("-seal"),policy in PIN_POLICIES or pin_route)
				step.battle = result
				ok = result.get("settled",false)
				if not items.is_empty():
					var equipped: Array = result.get("gear",[])
					ok = ok and equipped.size()==items.size() and equipped.all(func(g):return g.ok and g.owner==wearer and g.paid==0 and g.before-g.after==1)
				if not train_id.is_empty(): ok = ok and result.get("target_training",{}).get("paid")==8
				if not additional.is_empty():
					var paid: Array = result.get("additional_training",[])
					ok = ok and paid.size()==additional.size() and paid.all(func(r): return r.ok and r.paid==8 and r.paid_before_confirm==0)
				if delay >= 0:
					ok = ok and result.get("relief",{}).get("placed",false)
				if not ordered_id.is_empty() and delay < 0 and not martial:
					var receipt: Dictionary = result.get("aid",{})
					ok = ok and receipt.get("placed",false) and receipt.get("id") == ordered_id and receipt.get("paid") == (9.0 if ordered_id=="H06" else (8.0 if ordered_id=="H24" or fifth else 10.0))
				if ordered_id=="H24" and policy in PIN_POLICIES and policy.ends_with("-seal"):
					var gear: Dictionary = result.get("recruit_gear",{})
					ok = ok and gear.get("ok",false) and gear.owner=="H24" and gear.before-gear.after==1 and gear.paid==0
				if hire_early and ordered_id=="H19":
					ok = ok and result.get("recruit_gear",{}).get("ok",false)
				if train_reserve:
					var payments: Array = result.get("upgrades",[])
					var expected := {"id":reserve_id,"ok":true,"paid":8.0}
					ok = ok and payments.size() == (2 if two_levels else 1) and payments.all(func(receipt): return receipt == expected)
				if strengthen:
					ok = ok and result.get("upgrades",[]) == [{"id":"H23","ok":true,"paid":8.0}]
				if fifth and not train_third_guard and (policy == "reserve-trained" or camp):
					ok = ok and result.get("aid_upgrade",{}) == {"id":"H24","ok":true,"paid":8.0}
				if martial:
					ok = ok and result.foreign_units.is_empty()
					if ordered_id in ["H09","H12"]:
						ok = ok and result.get("aid",{}) == {"id":ordered_id,"post":aid_post,"placed":true,"paid":12.0}
				report.foreign.append_array(result.get("foreign_units",{}).values())
			"reward":
				if camp: step.offered = night.reward_options().map(func(card): return card.id)
				var chosen := false
				var rewards: Array = night.reward_options().duplicate()
				if stock_route and night.state.growth.inventory.get("I08",0)==0:
					for offer in rewards.duplicate():
						if offer.id=="p7_I08" and offer.allowed:
							rewards.erase(offer)
							rewards.push_front(offer)
							break
				for card in rewards:
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
				var rest_checkpoint := OS.get_environment("YE_CI_EIGHTH_CAMP_SAVE")
				if night.state.current_node_id=="n06" and not rest_checkpoint.is_empty():
					if not night.save(rest_checkpoint).ok:
						quit(2)
						return
				var reserve: String = orders.get("camp",{}).get(night.state.current_node_id,"")
				if policy in ["martial-iron-camp","martial-iron-relay"] and night.state.current_node_id=="n06":
					reserve = "H12"
				if policy=="martial-iron-relay" and night.state.current_node_id=="n09":
					reserve = "H14"
				if policy in FIFTH_POSTS and policy != "trio-aid" and night.state.current_node_id == "n06" and not night.state.roster.is_empty():
					reserve = "" # Post comparisons take the usual heal for a surviving guard.
				if (orders.get("ritual_gear",false) or orders.get("read",false)) and not night.rest_reserve_options().any(func(o): return o.id==reserve and o.allowed): reserve = ""
				if policy=="repair-inner-eighth-drill" and night.state.current_node_id=="n09": reserve = ""
				if night.state.current_node_id=="n09" and EIGHTH_GUARD.get(policy,{}).has("final"):
					reserve = EIGHTH_GUARD[policy].final
				var snapshot := OS.get_environment("YE_CI_LAST_CAMP_SAVE")
				if night.state.current_node_id=="n09" and not snapshot.is_empty() and not night.save(snapshot).ok:
					quit(2)
					return
				if policy=="camp-fire-stock-pin-veteran8-early" and OS.get_environment("YE_CI_TREAT_SOLO")=="rest" and night.state.current_node_id=="n06":
					ok = night.finish_rest().ok
				elif policy=="camp-fire-stock-pin-veteran8-early" and OS.get_environment("YE_CI_TREAT_SOLO")=="1" and night.state.current_node_id=="n06":
					var host: Node = load("res://scenes/night/Night.tscn").instantiate()
					host.save_path = "user://solo-care-%d.json" % OS.get_process_id()
					root.add_child(host)
					ok = night.save(host.save_path).ok
					host.continue_run()
					var member: Dictionary = night.state.roster[0]
					var uid: String = member.uid
					var cash: float = night.state.incense
					var expected: float = night.treatment_health_after(member)
					var button: Button = host.panel.buttons.get("treat_"+uid)
					step.treatment = {"uid":uid,"before":member.hp,"expected":expected,"rest_hp":night.rest_health_after(member)}
					ok = ok and night.state.roster.size()==1 and is_instance_valid(button) and not button.disabled
					if ok:
						button.pressed.emit()
						ok = night.load_save(host.save_path).ok and night.state.phase=="map"
						step.treatment.after = night.state.roster[0].hp
						step.treatment.paid = cash-night.state.incense
						ok = ok and night.state.roster[0].uid==uid and is_equal_approx(step.treatment.after,expected) and is_equal_approx(step.treatment.paid,night.config.rest.treatment_cost)
					host.free()
				elif policy=="repair-inner-eighth-treat" and night.state.current_node_id=="n06":
					var patient: Dictionary = night.state.roster.filter(func(u):return u.id=="H01")[0]
					var before_hp: float = patient.hp
					var before_cash: float = night.state.incense
					ok = night.treat_at_rest(patient.uid).ok
					step.treatment = {"uid":patient.uid,"before":before_hp,"after":patient.hp,"paid":before_cash-night.state.incense}
				elif not reserve.is_empty():
					var id := reserve
					var cash: float = night.state.incense
					var regroup: bool = (policy in REGROUP_TRAIN or policy in FIFTH_TRAIN) and night.state.current_node_id == "n06" and night.rest_reserve_options().any(func(o): return o.id==id and o.can_regroup)
					var accepted := await rest_via_menu(night,id,regroup)
					step.hire = {"regroup":regroup,"id":id,"paid":cash-night.state.incense,"saved_and_reloaded":accepted}
					ok = accepted and is_equal_approx(step.hire.paid,12.0)
				elif policy in THIRD_POSTS and night.state.current_node_id=="n06" and not night.rest_reserve_options().any(func(o): return o.id==reserve_id and o.allowed):
					ok = night.finish_rest().ok
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
		if martial or policy in rear_policies or policy in PIN_POLICIES or pin_route:
			step.survivors = night.state.roster.map(func(u): return {"uid":u.uid,"id":u.id,"post":u.post,"hp":u.hp,"max_hp":u.max_hp})
		if policy.begins_with("relief-") or policy in rear_policies:
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
	if OS.get_environment("YE_CI_TREAT_SOLO")=="1" and policy=="camp-fire-stock-pin-veteran8-early":
		filename = "solo-care-"+filename
	if OS.get_environment("YE_CI_TREAT_SOLO")=="rest" and policy=="camp-fire-stock-pin-veteran8-early":
		filename = "solo-rest-"+filename
	FileAccess.open("res://tools/faction_baseline/" + filename,FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	if OS.get_environment("YE_CI_DEBRIEF_SAVE") != "" and report.policy_finished:
		night.save(OS.get_environment("YE_CI_DEBRIEF_SAVE"))
	print("ROUTE ",faction," ",report.phase," ",report.outcome)
	await create_timer(0.6).timeout
	quit(0 if report.policy_finished else 1)

func rest_via_menu(night: RefCounted, id: String, regroup := false) -> bool:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "user://ye-ci-route-rest-%d.json" % OS.get_process_id()
	root.add_child(host)
	var previous_ids: Array = night.state.roster.map(func(member): return member.uid)
	var expected_seed: String = night.state.seed
	var expected_node: String = night.state.current_node_id
	var saved: bool = night.save(host.save_path).ok
	if saved: host.continue_run()
	var button: Button = host.panel.buttons.get(("regroup_" if regroup else "reserve_")+id)
	var loaded := false
	if host.run.state.get("seed") == expected_seed and host.run.state.get("current_node_id") == expected_node and is_instance_valid(button) and not button.disabled:
		if OS.get_environment("YE_CI_CAPTURE_REST") == "1" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg("/tmp/ye-ci-rest-menu.jpg",0.86)
		if regroup and OS.get_environment("YE_CI_REGROUP_CAPTURE") == "1" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var bounds := button.get_global_rect()
			if not root.get_visible_rect().encloses(bounds): return false
			root.get_texture().get_image().save_webp("/tmp/r21-regroup.webp",true,0.82)
			var sent := Time.get_ticks_usec()
			for down in [true,false]:
				var mouse := InputEventMouseButton.new()
				mouse.button_index = MOUSE_BUTTON_LEFT
				mouse.position = bounds.get_center()
				mouse.pressed = down
				root.push_input(mouse,true)
			await RenderingServer.frame_post_draw
			print("REGROUP_CLICK_MS ",(Time.get_ticks_usec()-sent)/1000.0)
		else:
			button.pressed.emit()
		loaded = night.load_save(host.save_path).ok and night.state.seed == expected_seed and night.state.phase == "map" and night.state.roster.size() == previous_ids.size()+1 and night.state.roster.any(func(member): return member.id == id and member.uid not in previous_ids) and previous_ids.all(func(uid): return night.state.roster.any(func(member): return member.uid == uid))
	if loaded:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	else:
		printerr("Rest reload failed at ",expected_node," / ",expected_seed," (",id,"): ",host.feedback.text,". Fixture: ",ProjectSettings.globalize_path(host.save_path))
	host.free()
	return loaded
