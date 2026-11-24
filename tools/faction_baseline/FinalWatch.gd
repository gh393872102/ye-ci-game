extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Compare decisions from the same earned R01 n09 save. Record unavailable choices separately.

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2,3] or (args.size()==3 and args[2]!="reinforcements"):
		quit(2)
		return
	probe_boss_gate = true
	var trials := []
	var extra := args.size()==3
	var camps := ["rest","care","brace_hall","reserve_H18","reserve_H20","rest_pin","care_pin"]
	if extra: camps = ["rest","care","reserve_H20"]
	for camp in camps:
		var aids: Array = ["none"]
		if camp in ["rest","care"]:
			aids.append_array(["H18","H20"])
		if extra:
			aids = ["H24"]
			if camp=="reserve_H20": aids.append_array(["train_H20","train_H20_twice"])
		for aid in aids:
			var trial := await replay(args[0],camp,aid)
			trials.append(trial)
			if not trial.get("checked",false):
				printerr("Unverified replay: ",camp," ",aid," ",trial)
				quit(1)
				return
	var out := FileAccess.open(args[1],FileAccess.WRITE)
	if out == null:
		quit(2)
		return
	out.store_string(JSON.stringify({"camp_sha256":FileAccess.get_sha256(args[0]),"trials":trials}))
	out.close()
	await create_timer(0.6).timeout
	quit()

func replay(path: String, camp: String, aid: String) -> Dictionary:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "user://final-watch-%d.json" % OS.get_process_id()
	root.add_child(host)
	var night: RefCounted = host.run
	var trial := {"camp":camp,"aid":aid,"checked":false}
	if not night.load_save(path).ok or night.state.phase!="rest" or night.state.current_node_id!="n09" or night.state.opening_faction!="符法司":
		host.free()
		return trial
	var original: Dictionary = night.state.duplicate(true)
	host.panel.show_intro = false
	host.refresh()
	trial.seed = original.seed
	trial.before = original.incense
	trial.before_roster = original.roster
	trial.offers = night.rest_reserve_options()
	var key := camp.trim_suffix("_pin")
	if key=="care":
		for unit in original.roster:
			if unit.id=="H24": key = "treat_"+str(unit.uid)
	var button: Button = host.panel.buttons.get(key)
	if not is_instance_valid(button) or button.disabled:
		trial.unavailable = true
		trial.checked = night.state==original and camp.begins_with("reserve_") and not trial.offers.any(func(o): return "reserve_"+str(o.id)==camp and o.allowed)
		host.free()
		return trial
	button.pressed.emit()
	if not night.load_save(host.save_path).ok or night.state.phase!="map":
		host.free()
		return trial
	trial.after = night.state.incense
	trial.after_roster = night.state.roster.duplicate(true)
	trial.camp_fee = 0.0 if key=="rest" else trial.before-trial.after
	var price: float = 0 if key=="rest" else (night.config.rest.treatment_cost if camp.begins_with("care") else load("res://src/night/FactionOpening.gd").RESERVE_FEE)
	host.free()
	if not is_equal_approx(trial.camp_fee,price) or not night.choose_node("n10").ok:
		return trial
	var train := aid.begins_with("train_")
	var delay := -1.0 if aid=="none" or train else 4.0
	var trainee := "H20" if train else ""
	var repeat_training: Array = []
	if aid=="train_H20_twice":
		var cost: float = root.get_node("Data").battle_rules.upgrade.cost
		if trial.after >= 2*cost:
			repeat_training.append("H20")
		else:
			trial.second_training_shortfall = 2*cost-trial.after
	var carried: Array = ["I17"] if camp.ends_with("_pin") else []
	var battle := await fight(night,"符法司",original.seed,false,"",false,aid,true,false,1,carried,false,delay,trainee,"H24",false,"",0,false,false,repeat_training,false,true)
	trial.battle = battle
	trial.checked = battle.get("settled",false) and battle.hold and battle.foreign_units.is_empty()
	if train:
		trial.checked = trial.checked and battle.target_training.ok and is_equal_approx(battle.target_training.paid,8.0)
		if not repeat_training.is_empty(): trial.checked = trial.checked and battle.additional_training[0].ok and is_equal_approx(battle.additional_training[0].paid,8.0)
	if not carried.is_empty():
		var receipt: Dictionary = battle.gear[0]
		trial.checked = trial.checked and receipt.ok and receipt.owner=="H24" and receipt.paid==0 and receipt.before-receipt.after==1
	return trial
