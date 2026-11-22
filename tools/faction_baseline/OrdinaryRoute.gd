extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Paired ordinary routes. Each policy changes only its documented orders.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [1,2,3] or (args.size() >= 2 and args[1] not in ["upgrade","register","hall","base","aid-register","aid-hall","watch"]) or (args.size() == 3 and args[2] not in ["渡口","灯市","秋社"]) or args[0] not in ["0","1","2","3"]:
		quit(2)
		return
	var policy := args[1] if args.size() >= 2 else "base"
	var upgraded := policy == "upgrade"
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
				if step.choice == "n03" and policy in ["register","hall"]:
					var post := "post_register" if policy == "register" else "post_hall_door"
					step.orders = []
					for option in night.reserve_post_options():
						if option.to == post:
							var change: Dictionary = night.reserve_post(option.uid,post)
							step.orders.append({"move":option,"accepted":change.ok})
							if not change.ok: ok = false
				ok = ok and night.choose_node(step.choice).ok
			"battle":
				var second: bool = night.state.current_node_id == "n03"
				var aid_post := ""
				if second and policy.begins_with("aid-"):
					aid_post = "post_register" if policy == "aid-register" else "post_hall_door"
				var result: Dictionary = await fight(night,faction,seed_text,upgraded and second,aid_post,policy == "watch")
				step.battle = result
				ok = result.get("settled",false)
				report.foreign.append_array(result.get("foreign_units",{}).values())
			"reward":
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
			"market": ok = night.leave_node().ok
			"rest": ok = night.finish_rest().ok
			_: ok = false
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
	print("ROUTE ",faction," ",report.phase," ",report.outcome)
	await create_timer(0.6).timeout
	quit(0 if report.policy_finished else 1)
