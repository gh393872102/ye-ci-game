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
	var hp_before := hp
	hp = maxf(0, hp - amount)
	hit_flash = 0.15
	if hp <= 0:
		dead = true
		simulation.lethal_hit.emit(self,attacker,kind,amount,hp_before)
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
	if selected and not dead:
		draw_arc(Vector2(0, -3), 28, 0, TAU, 20, Color("b4d5bc"), 2)
	preload("res://src/units/UnitAppearance.gd").draw(self)
	if dead:
		return
	if unit_id=="H11" and roster.get("counters",{}).has("stationary_seconds"):
		_draw_rooted_stones()
	if roster.get("window_wedge")=="ready":
		var grip := Vector2(10,-height_px*0.46)
		draw_colored_polygon(PackedVector2Array([grip+Vector2(-3,-4),grip+Vector2(5,4),grip+Vector2(19,-18)]),Color("d8a970"))
		draw_line(grip,grip+Vector2(5,-5),Color("983b31"),3)
	elif roster.has("wedge_break_time"):
		var age: float = simulation.simulation_time-float(roster.wedge_break_time)
		if age>=0 and age<0.35:
			for n in range(3):
				var chip := Vector2(18+age*(23+n*12),-height_px*0.46+(n-1)*age*51)
				draw_line(chip,chip+Vector2(6,-4+n*2),Color("e4bd83"),3)
	if unit_id=="G07" and roster.has("window_paper"):
		_draw_window_paper()
	if bool(growth.get("gray",false)):
		draw_rect(Rect2(-24,-height_px-3,48,height_px+7),Color("a2aca7"),false,3)
	if selected or hp < max_hp or simulation.debug_rays:
		var ratio := hp / max_hp
		draw_rect(Rect2(-24,-height_px-12,48,5),Color("141d20"))
		draw_rect(Rect2(-24,-height_px-12,48 * ratio,5),Color("94b69b") if side == "xianghuo" else Color("a1766c"))
	if roster.has("window_strike_at"):
		var elapsed: float = simulation.simulation_time - float(roster.window_strike_at)
		if elapsed >= 0 and elapsed < 0.45:
			var tip := Vector2(0,-height_px-17)
			var spread := 6.0+8.0*elapsed/0.45
			var paper := PackedVector2Array([tip+Vector2(-spread,-16),tip+Vector2(0,-10),tip+Vector2(spread,-16),tip])
			draw_colored_polygon(paper,Color("e4cc9a"))
			draw_line(tip+Vector2(0,-10),tip,Color("aa412e"),3)
	if hold_lock:
		draw_rect(Rect2(-5,-101,10,6),Color("c5b47c"))
	if side == "xianghuo" and role == "ritual" and brain != null and brain.channel.active:
		draw_rect(Rect2(-32,-105,64,5),Color("263438"))
		draw_rect(Rect2(-32,-105,64 * brain.channel.progress(),5),Color("b99e76"))
		draw_rect(Rect2(-36,-56,9,5),Color("bc6a55"))

func _draw_rooted_stones() -> void:
	var engine: RefCounted = simulation.roster_engine()
	if engine==null or not engine.enabled: return
	var bonus: float = engine.humans.rooted_defense_bonus(self)
	var cap: float = engine.params(self).max_defense_bonus
	# Three pairs of foundation stones rise as the sentry settles into place.
	for i in 3:
		var raised := clampf(bonus/cap*3.0-i,0,1)
		if raised<=0: break
		var height := roundf(raised*(6+i*2))
		for side in [-1,1]:
			var foot := Vector2(side*(17+8*i),1)
			draw_rect(Rect2(foot.x-4,foot.y-height,8,height),Color("606b66"))
			draw_line(foot+Vector2(-4,-height),foot+Vector2(3,-height-1),Color("ded0a7"),2)

func _draw_window_paper() -> void:
	var shoulder := Vector2(6,-height_px*0.65)
	if roster.window_paper=="ready":
		var fold := PackedVector2Array([shoulder+Vector2(-6,-15),shoulder+Vector2(12,-18),shoulder+Vector2(19,1),shoulder+Vector2(9,17),shoulder+Vector2(-3,6)])
		draw_colored_polygon(fold,Color("ddcb9d"))
		draw_line(fold[1],fold[3],Color("8d3b2b"),3)
		draw_line(fold[0],fold[2],Color("a98b57"),2)
	else:
		var left: float = float(roster.ghost.get("paper_break_until",-1))-float(simulation.growth_engine().state.time)
		if left<=0: return
		var drift := 1.0-left/0.45
		for i in range(3):
			var tip := shoulder+Vector2(7+drift*(18+i*9),-8+drift*(i-1)*32)
			draw_line(tip,tip+Vector2(5,8-i*3),Color("ddcb9d"),4)
