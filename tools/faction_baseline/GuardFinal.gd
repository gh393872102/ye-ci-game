extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Replay the ordinary final map saved after paying for the second rest recruit.
func run() -> void:
	var rows := []
	var packed := FileAccess.get_file_as_bytes("res://tools/faction_baseline/rear-final-map.json.gz")
	var data := packed.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP)
	if data.is_empty():
		quit(2)
		return
	var path := "user://guard-final-%d.json" % OS.get_process_id()
	var save := FileAccess.open(path,FileAccess.WRITE)
	save.store_buffer(data)
	save.close()
	for levels in [0,1,2]:
		var night: RefCounted = load("res://src/night/NightRun.gd").new()
		if not night.load_save(path).ok or night.state.phase!="map" or night.state.opening_faction!="守香司" or not night.choose_node("n10").ok:
			quit(2)
			return
		var b: Dictionary = await fight(night,"守香司","渡口",levels>0,"",false,"",true,false,levels)
		if not b.settled or not b.foreign_units.is_empty() or b.get("upgrades",[]).size()!=levels or not b.get("upgrades",[]).all(func(u):return u.ok and u.id=="H02" and u.paid==8):
			quit(2)
			return
		rows.append(b)
	var file := FileAccess.open("res://tools/faction_baseline/rear-final-training.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"source_sha256":FileAccess.get_sha256(path),"levels":[0,1,2],"battles":rows},"\t")+"\n")
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await create_timer(0.3).timeout
	quit(0)
