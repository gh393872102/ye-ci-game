extends "res://tools/faction_baseline/OrdinaryOpening.gd"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2,3]:
		quit(2)
		return
	if args.size()==3 and args[2]=="replay":
		await check_replays(args[0])
		return
	var trials := []
	probe_boss_gate = true
	var plans := ["同守一次","后厢一次","同守连读","后厢连读","后厢配装","后厢训练"]
	if args.size()==3 and args[2]=="pure":
		plans = ["同守连读","同守训练"]
		purify_only = true
	elif args.size()==3 and args[2] in ["relief","relief-click"]:
		plans = ["一人时接守","空岗即接守","被占八秒接守"]
		purify_only = true
		if args[2]=="relief-click":
			if DisplayServer.get_name()=="headless":
				quit(2)
				return
			plans = ["空岗即接守"]
			capture_relief_click = true
	elif args.size()==3 and args[2]=="forward":
		plans = ["同守训练","同守配装","殿门连读"]
	elif args.size()==3:
		if args[2]!="native" or DisplayServer.get_name()=="headless":
			quit(2)
			return
		plans = ["同守连读"]
		capture_breaker_shortcut = true
		purify_only = true
	for plan in plans:
		var night: RefCounted = load("res://src/night/NightRun.gd").new()
		if not night.load_save(args[1]).ok or night.state.seed!=args[0] or night.state.opening_faction!="守香司":
			quit(2)
			return
		var before: Array = night.state.roster.duplicate(true)
		var wan: Dictionary = before.filter(func(u):return u.id=="H01")[0]
		var post := "post_register"
		if plan.begins_with("后厢"): post = "post_rear"
		if plan.begins_with("殿门"): post = "post_hall_door"
		if post!=wan.post and not night.reserve_post(wan.uid,post).ok:
			quit(2)
			return
		if not night.choose_node("n10").ok:
			quit(2)
			return
		reading_limit = 1 if plan.ends_with("一次") else 2
		use_breaker_shortcut = reading_limit==2
		var gear := []
		if plan.ends_with("配装"):
			for id in ["I08","I04"]:
				if night.state.growth.inventory.get(id,0)>0:
					gear.append(id)
					break
			if gear.is_empty(): continue
		var train := "H08" if plan.ends_with("训练") else ""
		var relief: bool = plan.ends_with("接守")
		var delay := 8.0 if plan=="被占八秒接守" else 0.0
		var b := await fight(night,"守香司",args[0],false,"",false,"H03" if relief else "",true,false,1,gear,false,delay if relief else -1.0,train,"H08",true,"破门",0.0,plan=="一人时接守")
		if not b.get("settled",false) or b.posts.size()!=3:
			quit(2)
			return
		if relief:
			var receipt: Dictionary = b.get("relief",{})
			var recruit: Dictionary = receipt.get("new_guard",{})
			if not receipt.get("placed",false) or recruit.is_empty() or receipt.paid!=receipt.catalog_price or not is_equal_approx(receipt.balance_before-receipt.paid,receipt.balance_after):
				printerr("Missing or inconsistent relief receipt: ",receipt)
				quit(2)
				return
			if not b.foreign_units.is_empty() or b.opening_guards.any(func(guard): return guard.instance==recruit.instance) or receipt.quote!="到岗后余 %d 香火" % floori(receipt.balance_after) or (capture_relief_click and (not receipt.get("arrival_visible",false) or "青笺" not in receipt.get("register_text",""))):
				printerr("Relief identity, budget or input check failed: ",receipt)
				quit(2)
				return
		if capture_breaker_shortcut and (b.read_orders.is_empty() or not b.read_orders.all(func(order): return order.ok and order.has("click_ms"))):
			quit(2)
			return
		if not gear.is_empty() and (b.get("gear",[]).size()!=1 or not b.gear[0].ok):
			quit(2)
			return
		trials.append({"plan":plan,"before":before,"battle":b,"pure":b.foreign_units.is_empty()})
	var file := FileAccess.open("res://tools/faction_baseline/last-watch-%s.json"%(args[0]+("-"+args[2] if args.size()==3 else "")),FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed":args[0],"save_sha256":FileAccess.get_sha256(args[1]),"trials":trials},"\t")+"\n")
	quit(0)

func check_replays(seed_text: String) -> void:
	var archive = load("res://src/replay/ReplayArchive.gd")
	var rows := []
	for entry in archive.list_seed(seed_text):
		if entry.node_id!="n10" or not entry.complete: continue
		var saved: Dictionary = archive.load_record(entry.id)
		if not saved.ok:
			quit(2)
			return
		var combat: Node = load("res://scenes/combat/Combat.tscn").instantiate()
		root.add_child(combat)
		var player = load("res://src/replay/ReplayPlayer.gd").new()
		var verified: bool = player.start(combat,saved.record).ok
		if verified:
			player.advance(400)
			verified = player.done and player.verified
		var pure_count := 0
		for action in saved.record.actions:
			if action.arguments.get("purify_only",false): pure_count+=1
		rows.append({"record":entry.id,"pure_orders":pure_count,"verified":verified})
		combat.free()
		await process_frame
	FileAccess.open("res://tools/faction_baseline/last-watch-"+seed_text+"-replay.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t")+"\n")
	quit(0 if not rows.is_empty() and rows.all(func(r):return r.verified) else 1)
