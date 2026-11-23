extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Replay the same earned pair at equal starting cost, with no invented recruits.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var manual := args.size() == 3 and args[2] == "manual-drum"
	if args.size() != 2 and not manual:
		quit(2)
		return
	var rows := []
	for post in ["post_register","post_hall_door"]:
		for timing in ["none","empty","last"]:
			var night: RefCounted = load("res://src/night/NightRun.gd").new()
			if not night.load_save(args[1]).ok or night.state.seed != args[0]:
				quit(2)
				return
			var guard: Dictionary = night.state.roster[0]
			if guard.id != "H08" or night.state.roster.size() != 2 or night.state.roster[1].id != "H02":
				quit(2)
				return
			if guard.post != post and not night.reserve_post(guard.uid,post).ok:
				continue
			if not night.choose_node("n10").ok:
				quit(2)
				return
			var delay := -1.0 if timing == "none" else 0.0
			var b := await fight(night,"守香司",args[0],false,"",false,"@first",true,false,1,[],false,delay,"","",false,"",0.0,timing=="last",manual)
			if not b.get("settled",false) or not b.foreign_units.is_empty():
				quit(2)
				return
			if timing != "none":
				var relief: Dictionary = b.get("relief", {})
				if relief.is_empty() or (relief.offered and (not relief.placed or relief.paid != relief.catalog_price)):
					quit(2)
					return
			rows.append({"post":post,"timing":timing,"battle":b})
	var prefix := "manual-drum" if manual else "last-guard"
	var output := FileAccess.open("res://tools/faction_baseline/%s-%s.json" % [prefix,args[0]],FileAccess.WRITE)
	output.store_string(JSON.stringify({"seed":args[0],"save_sha256":FileAccess.get_sha256(args[1]),"trials":rows},"\t")+"\n")
	output.close()
	quit(0)
