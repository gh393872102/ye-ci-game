extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Both variants start on the same saved map and can purchase from the ordinary full shop.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=2 or not FileAccess.file_exists(args[1]):
		quit(2)
		return
	var rows := []
	var ok := true
	for plan in ["就近下针","专守册房","训练问灯"]:
		var equipped: bool = plan=="专守册房"
		var night: RefCounted = load("res://src/night/NightRun.gd").new()
		if not night.load_save(args[1]).ok or night.state.seed!=args[0] or night.state.get("opening_faction","")!="符法司" or not night.choose_node("n10").ok:
			quit(2)
			return
		if plan=="训练问灯":
			var trained: Dictionary = await fight(night,"符法司",args[0],true,"",false,"",true)
			ok = ok and trained.settled and trained.hold and trained.foreign_units.is_empty() and trained.get("upgrades",[])==[{"id":"H19","ok":true,"paid":8.0}]
			rows.append({"plan":plan,"battle":trained})
			continue
		var b := await fight_pin(night,args[0],equipped)
		ok = ok and b.settled and b.hold and b.foreign_units.is_empty()
		var offers: Array = b.same_faction_offers.filter(func(x):return x.id=="H24")
		ok = ok and offers.size()==1 and offers[0].allowed and "post_register" in offers[0].posts and b.aid.placed and b.aid.paid==8
		if equipped: ok = ok and b.get("recruit_gear",{}).get("ok",false) and b.recruit_gear.before-b.recruit_gear.after==1 and b.recruit_gear.paid==0
		rows.append({"plan":plan,"equipped":equipped,"battle":b})
	var r := {"passed":ok,"seed":args[0],"map_sha256":FileAccess.get_sha256(args[1]),"trials":rows}
	FileAccess.open("res://tools/faction_baseline/pin-final-"+args[0]+".json",FileAccess.WRITE).store_string(JSON.stringify(r,"\t")+"\n")
	quit(0 if ok else 1)
