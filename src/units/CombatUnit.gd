extends Node2D
## Source-backed combat entity. AI and simulation time belong to CombatSimulation.
var unit_id := ""
var instance_id := ""
var display_name := ""
var role := ""
var side := "xianghuo"
var floor_id := 0
var hp := 0.0
var max_hp := 0.0
var attack := 0.0
var defense := 0.0
var speed_stat := 0
var skill_id := ""
var trait_id := ""
var skill_text := ""
var trait_text := ""
var skill_cost := 0
var tags: PackedStringArray
var profile: Dictionary
var current_post := ""
var ai_state := "IdleAtPost"
var current_speed := 0.0
var velocity := Vector2.ZERO
var attack_left := 0.0
var hit_flash := 0.0
var dead := false
var corpse_left := 0.0
var selected := false
var hold_lock := false
var may_briefly_leave_base := false
var return_after := 0.0
var brain: RefCounted
var simulation: Node2D
var attacks_enabled := true
var motion_enabled := true
var lane_index := -1
var progress := 0.0
var height_px := 80.0
var upgrade_level := 0
var equipment_id := ""
var mutation_count := 0
var damage_revision := 0
var growth: Dictionary = {}
var roster: Dictionary = {}

func configure(id: String, unique_id: String, sim: Node2D) -> void:
	unit_id = id
	instance_id = unique_id
	name = unique_id
	simulation = sim
	var row: Dictionary = Data.get_unit(id)
	profile = Data.combat_profiles[id].duplicate(true)
	display_name = row.get("姓名", row.get("名称", id))
	role = profile.role
	side = "yegui" if id.begins_with("G") else "xianghuo"
	height_px = float(profile.get("height_px", Rules.UNIT_HEIGHT_PX))
	max_hp = float(row["生命"])
	hp = max_hp
	attack = float(row["攻击"])
	defense = float(row["防御"])
	speed_stat = int(row["速度"])
	skill_id = profile.skill_id
	trait_id = profile.trait_id
	skill_text = row.get("专属技能", "")
	trait_text = row.get("特性", "")
	skill_cost = int(row.get("技能香耗", "0"))
	tags = str(row.get("标签", "")).split(";", false)
	may_briefly_leave_base = profile.may_briefly_leave_base
	return_after = profile.return_after
	add_to_group("units")
	sync_meta()

func sync_meta() -> void:
	set_meta("unit_id", unit_id)
	set_meta("side", side)
	set_meta("floor_id", floor_id)
	set_meta("current_post", current_post)
	set_meta("ai_state", ai_state)

func set_state(value: String) -> void:
	if ai_state != value:
		simulation.record_event("state", self, value)
	ai_state = value
	sync_meta()

func receive_damage(amount: float, attacker: Node2D = null, kind := "physical") -> void:
	if dead:
		return
	var engine = simulation.growth_engine()
	if simulation.roster_engine() != null:
		amount = simulation.roster_engine().before_receive(self,amount,attacker,kind)
	if engine != null:
		amount = engine.before_receive(self,amount,attacker,kind)
	if amount <= 0:return
	damage_revision += 1
	if side == "xianghuo" and brain != null and brain.channel.active and simulation.session != null and simulation.session.active:
		if engine == null or not engine.channel_damage(self):
			brain.channel.cancel("P4_RITUAL_INTERRUPTED_DAMAGE")
	hp = maxf(0, hp - amount)
	hit_flash = 0.15
	if hp <= 0:
		dead = true
		corpse_left = Rules.CORPSE_SECONDS
		current_speed = 0
		velocity = Vector2.ZERO
		set_state("Broken")
		if simulation.roster_engine() != null: simulation.roster_engine().on_death(self,attacker)
	queue_redraw()

func aim_point() -> Vector2:
	return position - Vector2(0, height_px * 0.525)

func hit_rect() -> Rect2:
	return Rect2(position - Vector2(18, height_px), Vector2(36, height_px))

func _draw() -> void:
	if dead:
		draw_rect(Rect2(-30, -13, 60, 13), Color("59665f"))
		return
	var ink := Color("b8bca9") if hit_flash <= 0 else Color("f0e9cd")
	if selected:
		draw_arc(Vector2(0, -3), 28, 0, TAU, 20, Color("b4d5bc"), 2)
	if simulation.roster_engine()!=null:
		preload("res://src/units/UnitAppearance.gd").draw(self)
	else:
		if side == "yegui":
			draw_set_transform(Vector2.ZERO, 0, Vector2(height_px / 80.0, height_px / 80.0))
			draw_rect(Rect2(-10, -80, 20, 20), ink)
			draw_colored_polygon(PackedVector2Array([Vector2(-11,-60), Vector2(11,-60), Vector2(23,0), Vector2(0,-9), Vector2(-23,0)]), Color("a4b7b9") if hit_flash <= 0 else ink)
			if unit_id == "G12":
				draw_rect(Rect2(-24,-56,48,40), Color("687775"))
				draw_line(Vector2(15,-52), Vector2(35,-30), ink, 8)
			elif unit_id == "G09":
				draw_line(Vector2(0,-76),Vector2(8,-48),Color("a18b76"),3)
				draw_line(Vector2(-10,-54),Vector2(-26,-72),ink,4)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_rect(Rect2(-10,-80,20,17), ink)
			var robe := Color("77514a") if role in ["guard", "talisman"] else Color("526b68")
			draw_rect(Rect2(-15,-63,30,45), robe if hit_flash <= 0 else ink)
			draw_rect(Rect2(-13,-18,10,18), Color("9da499"))
			draw_rect(Rect2(3,-18,10,18), Color("9da499"))
			match role:
				"guard":
					draw_rect(Rect2(-14,-80,28,8), Color("83938e"))
					draw_rect(Rect2(-23,-58,17,38), Color("61776f"))
					draw_line(Vector2(20,-62),Vector2(20,-5),ink,4)
				"crossbow":
					draw_line(Vector2(-28,-44),Vector2(23,-44),ink,5)
					draw_line(Vector2(-20,-59),Vector2(-20,-29),ink,3)
					draw_line(Vector2(-20,-59),Vector2(-8,-44),Color("8b9f96"),2)
					draw_line(Vector2(-20,-29),Vector2(-8,-44),Color("8b9f96"),2)
				"talisman":
					draw_rect(Rect2(-30,-60,13,23),Color("c2ac78"))
					draw_line(Vector2(-24,-57),Vector2(-23,-40),Color("8e4b40"),3)
				"ritual":
					draw_line(Vector2(-24,-78),Vector2(-24,0),Color("b8b29a"),4)
					draw_rect(Rect2(-32,-70,16,20),Color("83afa0"))
					draw_rect(Rect2(8,-48,19,13),Color("baad8a"))
	if bool(growth.get("gray",false)):
		draw_rect(Rect2(-24,-height_px-3,48,height_px+7),Color("a2aca7"),false,3)
	var ratio := hp / max_hp
	draw_rect(Rect2(-24,-height_px-12,48,5),Color("141d20"))
	draw_rect(Rect2(-24,-height_px-12,48 * ratio,5),Color("94b69b") if side == "xianghuo" else Color("a1766c"))
	if hold_lock:
		draw_rect(Rect2(-5,-101,10,6),Color("c5b47c"))
	if role == "ritual" and brain != null and brain.channel.active:
		draw_rect(Rect2(-32,-105,64,5),Color("263438"))
		draw_rect(Rect2(-32,-105,64 * brain.channel.progress(),5),Color("b99e76"))
		draw_rect(Rect2(-36,-56,9,5),Color("bc6a55"))
