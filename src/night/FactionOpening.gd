extends RefCounted
## Ordinary defending pairs, each worth 17 incense at the existing shop prices.
const PAIRS := {
	"守香司":["H03","H06"],
	"武卫司":["H10","H11"],
	"符法司":["H21","H23"],
	"奇人司":["H27","H32"],
}

static func apply(config: Dictionary, faction: String) -> void:
	var members := []
	for i in 2:
		var id: String = PAIRS[faction][i]
		var post := preload("res://src/growth/GrowthNight.gd").legal_post(id, ["post_register","post_hall_door"][i])
		members.append({"id":id,"post":post,"count":1})
	config.initial_roster.shouxiang = members
	config.initial_roster_note = faction + "守册"
