extends RefCounted
## Ordinary defending pairs, each worth 17 incense at the existing shop prices.
const PAIRS := {
	"守香司":["H03","H06"],
	"武卫司":["H10","H11"],
	"符法司":["H21","H23"],
	"奇人司":["H27","H32"],
}

# Entry slots per actor are a tuning budget for these ordinary attack routes.
const FAMILIES := {
	"无名潮":{"id":"G01","slots":1}, "习俗厉":{"id":"G09","slots":2},
	"大形":{"id":"G17","slots":4}, "无册谱":{"id":"G25","slots":2},
}

static func accepts(mode: String, faction: String) -> bool:
	return (mode == "shouxiang" and PAIRS.has(faction)) or (mode == "duoming" and FAMILIES.has(faction))

static func family_waves(waves: Array, family: Dictionary) -> Array:
	var converted := []
	var remainder := 0
	for wave in waves:
		for key in wave:
			if str(key).begins_with("G"): remainder += int(wave[key])
		var group := {"at":wave.at}
		group[family.id] = floori(float(remainder) / int(family.slots))
		remainder %= int(family.slots)
		converted.append(group)
	return converted

# A depleted ordinary watch can give up rest and pay for a living faction reserve.
const REST_RESERVES := {
	"守香司":["H02","H08"], "武卫司":["H12","H14"],
	"符法司":["H18","H20"], "奇人司":["H26","H29"],
}
const RESERVE_FEE := 12

static func apply(config: Dictionary, faction: String) -> void:
	if FAMILIES.has(faction):
		var family: Dictionary = FAMILIES[faction]
		config.initial_roster.duoming = [{"id":family.id,"count":floori(16.0 / family.slots),"post":"ghost_main_path"}]
		config.initial_roster_note = faction + "夺名"
		return
	var members := []
	for i in 2:
		var id: String = PAIRS[faction][i]
		var post := preload("res://src/growth/GrowthNight.gd").legal_post(id, ["post_register","post_hall_door"][i])
		members.append({"id":id,"post":post,"count":1})
	config.initial_roster.shouxiang = members
	config.initial_roster_note = faction + "守册"
