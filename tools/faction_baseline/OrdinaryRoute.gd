extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Paired ordinary routes. Each policy changes only its documented orders.
const CAMP_POLICIES := ["camp-mirror","camp-fire","camp-mirror-up","camp-fire-up","camp-mirror-veteran","camp-fire-veteran","camp-mirror-relay","camp-fire-relay"]
const RESERVE_POLICIES := ["reserve-hire","reserve-upgrade","reserve-both","reserve-trained"] + CAMP_POLICIES

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [1,2,3] or (args.size() >= 2 and args[1] not in RESERVE_POLICIES and args[1] not in ["upgrade","register","hall","base","aid-register","aid-hall","watch","borrow","dispel","dispel-recall"]) or (args.size() == 3 and args[2] not in ["渡口","灯市","秋社"]) or args[0] not in ["0","1","2","3"]:
		quit(2)
		return
	var policy := args[1] if args.size() >= 2 else "base"
	if (policy in RESERVE_POLICIES or policy in ["borrow","dispel","dispel-recall"]) and args[0] != "2":
		quit(2)
		return
	var camp := policy.begins_with("camp-")
	var relay := policy.ends_with("-relay")
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
				var recall: bool = step.choice == "n05" and (policy == "dispel-recall" or policy in RESERVE_POLICIES)
				if recall or (step.choice == "n03" and policy in ["register","hall"]):
					var post := "post_register" if recall or policy == "register" else "post_hall_door"
					step.orders = []
					for option in night.reserve_post_options():
						if option.to == post:
							var change: Dictionary = night.reserve_post(option.uid,post)
							step.orders.append({"move":option,"accepted":change.ok})
							if not change.ok: ok = false
				ok = ok and night.choose_node(step.choice).ok
			"battle":
				var fifth: bool = night.state.current_node_id == "n05"
				var strengthen: bool = fifth and (camp or policy in ["reserve-upgrade","reserve-both","reserve-trained"])
				var train_reserve: bool = (night.state.current_node_id == "n08" and (policy.ends_with("-up") or two_levels)) or (relay and night.state.current_node_id == "n10")
				var second: bool = night.state.current_node_id == "n03"
				var aid_post := ""
				if second and policy.begins_with("aid-"):
					aid_post = "post_register" if policy == "aid-register" else "post_hall_door"
				var ordered_id := ""
				if paired_talisman:
					if night.state.current_node_id == "n01": ordered_id = "H17"
					if second: ordered_id = "H19" if policy == "borrow" else "H22"
					if fifth and (camp or policy in ["reserve-hire","reserve-both","reserve-trained"]): ordered_id = "H24"
					if not ordered_id.is_empty(): aid_post = "post_register"
				var result: Dictionary = await fight(night,faction,seed_text,(upgraded and second) or strengthen or train_reserve,aid_post,policy == "watch",ordered_id,paired_talisman,fifth and (policy == "reserve-trained" or camp),2 if train_reserve and two_levels else 1)
				step.battle = result
				ok = result.get("settled",false)
				if not ordered_id.is_empty():
					var receipt: Dictionary = result.get("aid",{})
					ok = ok and receipt.get("placed",false) and receipt.get("id") == ordered_id and receipt.get("paid") == (8.0 if fifth else 10.0)
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
				if camp and (night.state.current_node_id == "n06" or (relay and night.state.current_node_id == "n09")):
					if night.state.current_node_id == "n09":
						reserve_id = "H20" if reserve_id == "H18" else "H18"
					var id := reserve_id
					var before: float = night.state.incense
					step.options = night.rest_reserve_options()
					var hired := await rest_via_menu(night,id)
					step.hire = {"id":id,"paid":before-night.state.incense,"saved_and_reloaded":hired}
					ok = hired and step.hire.paid == 12
				else: ok = night.finish_rest().ok
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

func rest_via_menu(night: RefCounted, id: String) -> bool:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "/tmp/ye-ci-route-rest-%d.json" % OS.get_process_id()
	root.add_child(host)
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
		loaded = night.load_save(host.save_path).ok and night.state.phase == "map" and night.state.roster.size() == 1 and night.state.roster[0].id == id
	DirAccess.remove_absolute(host.save_path)
	host.free()
	return loaded
