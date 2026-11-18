extends RefCounted
## A seat is an input perspective, never a separate set of combat values.
const SEATS := ["shouxiang","duoming"]
const COMMANDS := {
	"shouxiang":["unit_skill","mark_target","purchase","deploy_at","cancel_purchase","upgrade","equip","start_ritual","repair","equip_item","unequip_item","stamp_job","borrow_god","fuse","use_key"],
	"duoming":["unit_skill","mutate","reinforce","equip_item","unequip_item","mutate_form","fuse","use_key"]}
const OBJECTIVES := {
	"shouxiang":["hold_to_daybreak","preserve_names"],
	"duoming":["register_capture","names_drained"]}
static func commands(seat: String) -> Array:
	return COMMANDS.get(seat,[]).duplicate()
static func objective_key(id: String) -> String:
	return "P6_OBJECTIVE_" + id.to_upper()
static func objectives(node: Dictionary, seat: String) -> Dictionary:
	if seat not in SEATS:
		return {}
	return node.get("objectives",{}).get(seat,{"primary":OBJECTIVES[seat][0],"secondary":OBJECTIVES[seat][1]}).duplicate(true)
static func valid_objectives(value) -> bool:
	if not value is Dictionary:
		return false
	for seat in SEATS:
		if not value.get(seat) is Dictionary:
			return false
		var pair: Dictionary = value[seat]
		if pair.get("primary") not in OBJECTIVES[seat] or pair.get("secondary") not in OBJECTIVES[seat] or pair.primary == pair.secondary:
			return false
	return true
static func outcome_for(result: Dictionary, seat: String) -> String:
	if result.is_empty() or seat not in SEATS:
		return ""
	if result.has("winner"):
		return "victory" if result.winner == seat else "defeat"
	return str(result.get("outcome","")) if result.get("mode") == seat else ("defeat" if result.get("outcome") == "victory" else "victory")
