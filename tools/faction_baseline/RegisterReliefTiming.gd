extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Same natural n10 map, same budget. Use real offers and record the adjudicated outcome.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(2)
		return
	var trials := []
	var passed := true
	for id in ["H24","H21"]:
		for policy in ["opening","warning","vacant","occupation_7"]:
			var night: RefCounted = load("res://src/night/NightRun.gd").new()
			if not night.load_save(args[1]).ok or night.state.seed != args[0] or night.state.opening_faction != "符法司" or not night.choose_node("n10").ok:
				quit(2)
				return
			inspect_replacements = policy != "opening"
			var post := "post_register" if policy == "opening" else ""
			var delay := -1.0 if policy == "opening" else (7.0 if policy == "occupation_7" else 0.0)
			var b := await fight(night,"符法司",args[0],false,post,false,id,true,false,1,[],false,delay,"","",false,"",0,policy == "warning")
			var ok: bool = b.settled and b.hold and b.foreign_units.is_empty()
			if policy == "opening":
				ok = ok and b.aid.placed and is_equal_approx(b.aid.paid,8.0)
			else:
				var r: Dictionary = b.get("relief",{})
				ok = ok and r.get("previously_fallen",false) and not r.visible_before_toggle and r.scope_paid == 0 and r.placed and r.has("new_guard") and is_equal_approx(r.paid,8.0)
				ok = ok and r.available.all(func(unit_id): return root.get_node("Data").get_unit(unit_id).get("所属","") == "符法司")
			trials.append({"id":id,"policy":policy,"passed":ok,"battle":b})
			passed = passed and ok
	for policy in ["hold","train","train_then_recruit"]:
		var night: RefCounted = load("res://src/night/NightRun.gd").new()
		if not night.load_save(args[1]).ok or not night.choose_node("n10").ok:
			quit(2)
			return
		inspect_replacements = policy == "train_then_recruit"
		var b := await fight(night,"符法司",args[0],policy != "hold","",false,"H24",true,false,1,[],false,7.0 if inspect_replacements else -1.0)
		var ok: bool = b.settled and b.hold and b.foreign_units.is_empty()
		if policy != "hold":
			ok = ok and b.get("upgrades",[]) == [{"id":"H19","ok":true,"paid":8.0}]
		if inspect_replacements:
			var r: Dictionary = b.get("relief",{})
			ok = ok and r.get("placed",false) and is_equal_approx(r.paid,8.0)
		trials.append({"id":"H19","policy":policy,"passed":ok,"battle":b})
		passed = passed and ok
	var output := FileAccess.open(args[2],FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed":passed,"seed":args[0],"map_sha256":FileAccess.get_sha256(args[1]),"trials":trials},"\t")+"\n")
	output.close()
	quit(0 if passed else 1)
