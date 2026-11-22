extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Counterfactual loadouts from an ordinary map save, before entering n10.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ["渡口","灯市","秋社"]:
		quit(2)
		return
	var seed_text := args[0]
	var packed := FileAccess.get_file_as_bytes(args[1])
	var data := packed.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP) if args[1].ends_with(".gz") else packed
	if data.is_empty():
		quit(2)
		return
	var path := "user://gear-%d.json" % OS.get_process_id()
	var save := FileAccess.open(path,FileAccess.WRITE)
	save.store_buffer(data)
	save.close()
	var rows := []
	var stock := {}
	for levels in [0,1,2]:
		for items in [[],["I08"],["Y11"],["I08","Y11"],["Y14"]]:
			var night: RefCounted = load("res://src/night/NightRun.gd").new()
			if not night.load_save(path).ok or night.state.phase!="map" or night.state.opening_faction!="守香司" or str(night.state.seed)!=seed_text:
				quit(2)
				return
			stock = night.state.growth.inventory.duplicate()
			if not items.all(func(id): return stock.get(id,0)>0): continue
			if not night.choose_node("n10").ok:
				quit(2)
				return
			var b := await fight(night,"守香司",seed_text,levels>0,"",false,"",true,false,levels,items)
			if not valid_trial(b,levels,items):
				quit(2)
				return
			rows.append({"levels":levels,"items":items,"battle":b})
	var file := FileAccess.open("res://tools/faction_baseline/guard-gear-%s.json"%seed_text,FileAccess.WRITE)
	file.store_string(JSON.stringify({"source_sha256":FileAccess.get_sha256(path),"seed":seed_text,"inventory":stock,"trials":rows},"\t")+"\n")
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0)

func valid_trial(battle: Dictionary,levels: int,items: Array) -> bool:
	if not battle.get("settled",false) or not battle.foreign_units.is_empty():
		return false
	var guards: Array = battle.opening_guards
	if guards.size()!=1 or guards[0].id!="H02":
		return false
	var training: Array = battle.get("upgrades",[])
	if training.size()!=levels or not training.all(func(t): return t.ok and t.id=="H02" and t.paid==8):
		return false
	var gear: Array = battle.get("gear",[])
	return gear.map(func(g): return g.id)==items and gear.all(func(g): return g.ok and g.owner=="H02" and g.before-g.after==1 and g.paid==0)
