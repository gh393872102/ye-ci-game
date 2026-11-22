extends RefCounted
## Ordinary defending pairs, each worth 17 incense at the existing shop prices.
const PAIRS := {
	"守香司":["H03","H06"],
	"武卫司":["H10","H11"],
	"符法司":["H21","H23"],
	"奇人司":["H27","H32"],
}

# A wiped ordinary watch can spend its rest stop to call one living reserve.
const REST_RESERVES := {
	"守香司":["H02","H08"], "武卫司":["H12","H14"],
	"符法司":["H18","H20"], "奇人司":["H26","H29"],
}
const RESERVE_FEE := 12

static func apply(config: Dictionary, faction: String) -> void:
	var members := []
	for i in 2:
		var id: String = PAIRS[faction][i]
		var post := preload("res://src/growth/GrowthNight.gd").legal_post(id, ["post_register","post_hall_door"][i])
		members.append({"id":id,"post":post,"count":1})
	config.initial_roster.shouxiang = members
	config.initial_roster_note = faction + "守册"
