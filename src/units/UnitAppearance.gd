extends RefCounted
## Pixel body only. CombatUnit retains gameplay bounds, selection and status overlays.
static var fallback: Dictionary = {}
static var sprite_specs: Dictionary = {}
static var sprite_sheets: Dictionary = {}
static var sprite_catalog_loaded := false
const LAMPLIT := preload("res://assets/sprites/units/p11r/lamplit.tres")
const ATLAS_PATH := "res://data/units/p11_sprite_atlas.json"
const SHEET_PATH := "res://assets/sprites/units/p11r/"
const FRAME_SIZE := Vector2(144, 84)
static var contact_shadow := PackedVector2Array([
	Vector2(-24, 0), Vector2(-15, -3), Vector2(14, -3), Vector2(25, 0),
	Vector2(18, 3), Vector2(-15, 3)
])
static var paper_face := PackedVector2Array([
	Vector2(-3, -5), Vector2(2, -5), Vector2(4, -2), Vector2(4, 1),
	Vector2(1, 5), Vector2(-2, 4), Vector2(-4, 1)
])

static func describe(id: String) -> Dictionary:
	return _appearance_spec(id).duplicate(true)

static func _appearance_spec(id: String) -> Dictionary:
	var rules: Dictionary = Data.appearance_rules
	if rules.is_empty():
		if fallback.is_empty(): fallback = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/p8_appearance.json"))
		rules = fallback
	return rules.get("units",{}).get(id,{})

static func bust_texture(id: String) -> Texture2D:
	if id == "H24": return preload("res://assets/portraits/p8/bone-needle-bust.webp")
	if id == "H11": return preload("res://assets/portraits/p8/stone-mason-bust.webp")
	var index := id.substr(1).to_int()-1
	if not id.begins_with("H") or index < 0 or index >= 32: return null
	var bust := AtlasTexture.new()
	bust.atlas = preload("res://assets/portraits/p8/relief-busts.webp")
	bust.region = Rect2((index % 8)*192, floori(index/8.0)*128, 192, 128)
	return bust

static func portrait_texture(id: String) -> Texture2D:
	if id.begins_with("T"): return null
	var path: String = describe(id).get("portrait","")
	if path.is_empty(): return null
	if ResourceLoader.exists(path): return load(path)
	# Newly authored source PNGs can arrive while the editor is closed. Exported
	# projects use imported resources; this keeps the source-workspace card usable too.
	if FileAccess.file_exists(path):
		var pixels := Image.load_from_file(ProjectSettings.globalize_path(path))
		if pixels != null and not pixels.is_empty(): return ImageTexture.create_from_image(pixels)
	return null

static func face_state(unit: Node2D) -> String:
	var roster = unit.get("roster")
	return str(roster.get("face_state",describe(unit.unit_id).get("default_face","faced"))) if roster is Dictionary else str(describe(unit.unit_id).get("default_face","faced"))

static func draw(unit: Node2D) -> void:
	var spec := _appearance_spec(str(unit.unit_id))
	if spec.is_empty(): return
	if _draw_sprite(unit, spec):
		return
	var palette: Dictionary = spec.palette
	var cloth := Color(str(palette.cloth))
	var trim := Color(str(palette.trim))
	var skin := Color(str(palette.skin))
	var metal := Color(str(palette.metal))
	var glow := Color(str(palette.glow))
	if unit.hit_flash > 0:
		cloth = cloth.lightened(.42)
		skin = skin.lightened(.25)
	var scale := float(unit.height_px) / 80.0
	var facing := -1.0 if unit.side == "xianghuo" else 1.0
	unit.draw_set_transform(Vector2.ZERO,0,Vector2(scale*facing,scale))
	if unit.dead:
		_r(unit,-27,-10,50,8,cloth.darkened(.25))
		_r(unit,-21,-14,13,7,skin.darkened(.2))
		_r(unit,18,-8,17,4,metal.darkened(.3))
		unit.draw_set_transform(Vector2.ZERO)
		return
	var time: float = unit.simulation.simulation_time if is_instance_valid(unit.simulation) else 0.0
	var moving: bool = float(unit.current_speed)>1.0
	var step := 2.0 * signf(sin(time*8.0)) if moving else 0.0
	var cast: bool = unit.attack_left > .2 or unit.ai_state in ["Channel","Ritual","Skill"]
	var skin_visible := face_state(unit) != "faceless"
	var skeleton: String = spec.skeleton
	if spec.family == "ghost":
		_ghost(unit,skeleton,str(spec.variant),cloth,trim,skin,metal,glow,step,skin_visible)
	else:
		_human(unit,skeleton,cloth,trim,skin,metal,step)
		_head(unit,str(spec.headgear),skin,cloth,metal,skin_visible,spec.family == "troop")
		_weapon(unit,str(spec.weapon),cloth,trim,skin,metal,glow,cast)
	unit.draw_set_transform(Vector2.ZERO)

static func _sprite_spec(id: String) -> Dictionary:
	if not sprite_catalog_loaded:
		sprite_catalog_loaded = true
		if FileAccess.file_exists(ATLAS_PATH):
			var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_PATH))
			if catalog is Dictionary:
				sprite_specs = catalog.get("units", {})
	return sprite_specs.get(id, {})

static func pose_texture(id: String, pose: int) -> AtlasTexture:
	var spec := _sprite_spec(id)
	if spec.get("frames", []).is_empty():
		return null
	var sheet := _sprite_sheet(spec.sheet)
	if sheet == null:
		return null
	var frame: Array = spec.frames[pose] if pose >= 0 and pose < spec.frames.size() else spec.frames[0]
	var texture := AtlasTexture.new()
	texture.atlas = sheet
	texture.region = Rect2(Vector2(frame[0], frame[1]) * FRAME_SIZE, FRAME_SIZE)
	return texture

static func _sprite_sheet(sheet: String) -> Texture2D:
	if not sprite_sheets.has(sheet):
		var path := SHEET_PATH + sheet + ".png"
		if ResourceLoader.exists(path):
			sprite_sheets[sheet] = load(path)
		elif FileAccess.file_exists(path):
			var pixels := Image.load_from_file(ProjectSettings.globalize_path(path))
			if pixels != null and not pixels.is_empty():
				sprite_sheets[sheet] = ImageTexture.create_from_image(pixels)
	return sprite_sheets.get(sheet)

static func _draw_sprite(unit: Node2D, appearance: Dictionary) -> bool:
	var sprite := _sprite_spec(unit.unit_id)
	var live := is_instance_valid(unit.simulation)
	if live:
		var fusion: String = unit.growth.get("fusion_id", "")
		if not fusion.is_empty():
			var fused := _sprite_spec(fusion)
			if not fused.is_empty():
				sprite = fused
	if sprite.is_empty():
		return false
	var atlas := _sprite_sheet(sprite.sheet)
	if atlas == null:
		return false
	var advancing: bool = unit.current_speed > 1.0
	var facing := -1.0 if unit.side == "xianghuo" else 1.0
	var scale: float = unit.height_px / 80.0
	var frames: Array = sprite.frames
	if unit.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
		unit.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var at_lamp: bool = live and unit.side == "xianghuo" and unit.floor_id >= 0 and unit.position.x >= Rules.HALL_X
	if at_lamp and unit.material == null:
		unit.material = LAMPLIT
	elif not at_lamp and unit.material == LAMPLIT:
		unit.material = null
	if unit.dead:
		_draw_fallen(unit, atlas, frames[0], facing, scale)
		return true
	var cycle := 0.0
	var depth := 1.0
	if live:
		if advancing and absf(unit.velocity.x) > 6.0:
			facing = signf(unit.velocity.x)
		if unit.lane_index >= 0:
			depth = minf(1.0, 0.78 + float(unit.lane_index) * 0.074)
		cycle = float(unit.simulation.simulation_time) * 21.0 + float(unit.instance_id.hash() % 17)
	var acting: bool = unit.attack_left >= Rules.ATTACK_INTERVAL - 0.25 or unit.ai_state in [
		"Channel", "Ritual", "Skill", "Climb", "WindowCrawl", "Repair"
	] or unit.roster.get("statuses", {}).has("gate_guard")
	var step := sin(cycle)
	var pose := 0
	if frames.size() > 1:
		pose = 2 if acting else (1 if advancing and step > -0.12 else 0)
	var frame: Array = frames[pose]
	var light := Color(depth * 1.05, depth * 1.02, depth)
	if live and unit.side == "yegui" and unit.lane_index >= 0:
		var row: float = clampf(unit.lane_index / 3.0, 0, 1)
		light = Color(.69, .77, .84).lerp(Color(1.10, 1.02, .91), row)
	if unit.hit_flash > 0.0:
		light = Color(1.28, 1.18, 1.10)
	if live:
		unit.draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale, 1.0))
		unit.draw_colored_polygon(contact_shadow, Color(0.03, 0.035, 0.034, 0.43))
	# The feet stay at the route/floor position as the torso leans or rises through a gait.
	var lean := 0.0
	var rise := 1.0
	if frames.size() == 1:
		lean = -0.060 if acting else (-0.038 + step * 0.026 if advancing else 0.0)
		rise = 0.983 + absf(step) * 0.017 if advancing else 1.0
	unit.draw_set_transform_matrix(Transform2D(Vector2(facing * scale, 0.0),
		Vector2(facing * lean * scale, scale * rise), Vector2.ZERO))
	_draw_frame(unit, atlas, frame, light)
	if unit.unit_id=="H20":
		var cd: float = unit.roster.get("cooldowns",{}).get("skill",0)
		var duration: float = Data.roster_rules.abilities.H20.cooldown
		_draw_petition(unit,Color(str(appearance.palette.trim))*light,Color(str(appearance.palette.metal))*light,cd > duration-.45)
	var native_face: String = appearance.get("default_face", "faced")
	var current_face: String = unit.roster.get("face_state", native_face)
	if live and current_face != native_face:
		_draw_face_change(unit, appearance, Vector2(float(frame[2]), float(frame[3])), light, current_face)
	unit.draw_set_transform(Vector2.ZERO)
	return true

static func _draw_frame(unit: Node2D, atlas: Texture2D, frame: Array, light: Color) -> void:
	unit.draw_texture_rect_region(atlas, Rect2(Vector2(-FRAME_SIZE.x / 2.0, -FRAME_SIZE.y), FRAME_SIZE),
		Rect2(Vector2(float(frame[0]), float(frame[1])) * FRAME_SIZE, FRAME_SIZE), light)

static func _draw_fallen(unit: Node2D, atlas: Texture2D, frame: Array, facing: float, scale: float) -> void:
	unit.draw_set_transform_matrix(Transform2D(Vector2(0.0, -0.23 * scale),
		Vector2(-0.72 * facing * scale, 0.08 * scale), Vector2(-facing * 28.0, -12.0) * scale))
	var life := clampf(unit.corpse_left / Rules.CORPSE_SECONDS, 0.18, 1.0)
	_draw_frame(unit, atlas, frame, Color(0.69, 0.68, 0.63, life * 0.8))
	unit.draw_set_transform(Vector2.ZERO)

static func _draw_face_change(unit: Node2D, spec: Dictionary, center: Vector2, light: Color, state: String) -> void:
	var points := PackedVector2Array()
	for point in paper_face:
		points.append(center + point)
	var paper := Color(str(spec.palette.skin)).lerp(Color("d9ccae"), 0.52) * light
	unit.draw_colored_polygon(points, paper)
	if state == "faced":
		unit.draw_rect(Rect2(center + Vector2(1, -2), Vector2(2, 1)), Color("263535"))
		unit.draw_rect(Rect2(center + Vector2(1, 2), Vector2(2, 1)), paper.darkened(0.37))

static func _r(u: Node2D,x: float,y: float,w: float,h: float,c: Color) -> void:
	u.draw_rect(Rect2(x,y,w,h),c)

static func _line(u: Node2D,a: Vector2,b: Vector2,c: Color,width := 2.0) -> void:
	u.draw_line(a,b,c,width,false)

static func _poly(u: Node2D,points: Array,c: Color) -> void:
	var vertices := PackedVector2Array()
	for point in points: vertices.append(Vector2(point[0],point[1]))
	u.draw_colored_polygon(vertices,c)

static func _legs(u: Node2D,width: float,step: float,cloth: Color) -> void:
	_r(u,-width/2,-24+step,8,22-step,cloth.darkened(.35))
	_r(u,width/2-8,-24-step,8,22+step,cloth.darkened(.15))
	_r(u,-width/2-2,-4+step,12,4,Color("333e3c"))
	_r(u,width/2-8,-4-step,12,4,Color("333e3c"))

static func _human(u: Node2D,family: String,c: Color,t: Color,s: Color,m: Color,step: float) -> void:
	match family:
		"zhu":
			_poly(u,[[-12,-62],[12,-62],[20,-4],[8,0],[-18,-2]],c)
			_r(u,-17,-59,10,30,c.darkened(.12));_r(u,9,-58,10,27,c.lightened(.12))
			_r(u,-4,-61,4,55,t.darkened(.15));_r(u,-13,-34,29,4,t)
			_r(u,-13,-3,10,3,m);_r(u,8,-3,10,3,m)
		"wei":
			_legs(u,28,step,c);_r(u,-15,-62,30,37,c)
			_r(u,-21,-63,12,13,m.darkened(.3));_r(u,9,-63,13,13,m.darkened(.1))
			_r(u,-19,-50,8,23,c.darkened(.2));_r(u,13,-49,8,23,c.lightened(.1))
			for y in [-54,-46,-38]:_r(u,-12,y,24,2,t.darkened(.25))
			_r(u,-16,-28,32,5,t)
		"fu":
			_legs(u,22,step,c);_poly(u,[[-12,-62],[12,-62],[21,-20],[-17,-20]],c)
			_poly(u,[[-12,-60],[-24,-34],[-16,-29],[-5,-52]],c.lightened(.15))
			_poly(u,[[11,-59],[24,-34],[16,-28],[4,-52]],c.darkened(.15))
			_r(u,-3,-59,5,34,t);_r(u,-15,-32,30,4,t.darkened(.2))
		"jiang":
			_legs(u,28,step,c);_r(u,-16,-61,32,34,c.darkened(.1))
			_poly(u,[[-11,-58],[12,-58],[16,-18],[-15,-18]],t.darkened(.35))
			_r(u,-21,-55,8,25,s.darkened(.2));_r(u,15,-55,8,25,s)
			_r(u,-12,-35,25,4,m.darkened(.3));_r(u,-8,-30,14,9,c.darkened(.35))
		"tong":
			_legs(u,20,step*1.5,c);_r(u,-11,-57,22,31,c)
			_r(u,-15,-54,7,20,c.lightened(.15));_r(u,9,-54,7,20,c.darkened(.15))
			_r(u,-12,-30,24,5,t);_r(u,-8,-48,16,3,t.darkened(.2))
		"ke":
			_legs(u,24,step,c);_poly(u,[[-13,-64],[9,-63],[26,-6],[10,-14],[-18,-8],[-23,-31]],c.darkened(.12))
			_r(u,-12,-53,23,28,c.lightened(.08));_r(u,-21,-59,10,28,t.darkened(.35))
			_line(u,Vector2(-12,-60),Vector2(10,-27),t,4)
		"dun":
			_legs(u,34,step*.5,c);_r(u,-20,-63,40,39,c)
			_r(u,-25,-65,16,15,m.darkened(.25));_r(u,9,-65,16,15,m.darkened(.1))
			_r(u,-25,-48,10,26,c.darkened(.2));_r(u,17,-49,11,25,c.lightened(.08))
			for x in [-15,-7,1,9]:_r(u,x,-51,5,24,t.darkened(.25))
			_r(u,-21,-27,42,6,t)
		"you":
			_legs(u,28,step*1.5,c);_poly(u,[[-9,-62],[11,-61],[20,-27],[-14,-25]],c)
			_poly(u,[[-12,-36],[-5,-29],[-20,-10],[-24,-13]],c.darkened(.1))
			_poly(u,[[8,-36],[14,-29],[24,-17],[19,-13]],c.lightened(.1))
			_r(u,-17,-57,8,23,s);_r(u,12,-57,7,20,s.darkened(.1))
			_line(u,Vector2(-9,-57),Vector2(11,-33),t,3)

static func _head(u: Node2D,hat: String,s: Color,c: Color,m: Color,faced: bool,troop: bool) -> void:
	var wide := 18.0 if hat in ["iron_helmet","round_helmet","headscarf"] else 14.0
	_r(u,-wide/2,-77,wide,16,s)
	_r(u,-wide/2-2,-77,wide+4,5,c.darkened(.55))
	if faced and not troop:
		_r(u,-4,-69,2,2,Color("273431"));_r(u,3,-69,2,2,Color("273431"))
		_r(u,-2,-63,4,2,s.darkened(.5))
	match hat:
		"foldcap":_r(u,-10,-80,21,7,c.darkened(.2));_r(u,6,-78,8,3,c)
		"braid","artisan_braid":_r(u,7,-73,4,23,c.darkened(.5))
		"tallcap","constable":_r(u,-8,-80,16,10,c.darkened(.4));_r(u,-12,-72,24,3,m.darkened(.5))
		"mouthcloth":_r(u,-8,-67,17,7,m.lightened(.1))
		"hairpin":_line(u,Vector2(-12,-77),Vector2(12,-77),m,2);_r(u,9,-78,5,4,m)
		"headband","white_band":_r(u,-10,-75,20,4,m);_r(u,8,-73,4,13,m)
		"elder","shaved":_r(u,-5,-78,10,3,s.lightened(.1))
		"iron_helmet":_r(u,-12,-80,24,12,m.darkened(.35));_r(u,-15,-71,30,3,m);_r(u,8,-69,5,12,m.darkened(.3))
		"topknot","crown_knot":_r(u,-4,-80,9,5,c.darkened(.6));_r(u,6,-75,3,15,c.darkened(.4))
		"headscarf":_r(u,-11,-79,23,6,m);_r(u,-13,-74,5,21,m.darkened(.2))
		"red_knot","ribbons":_r(u,7,-77,5,5,Color("a05c49"));_r(u,10,-73,3,22,Color("a05c49"))
		"round_helmet":_r(u,-11,-80,23,9,m);_r(u,-14,-74,29,4,m.darkened(.1))
		"mourning_hood","paper_hood":_poly(u,[[-12,-69],[-10,-79],[9,-80],[13,-66],[9,-61],[8,-73],[-7,-73],[-9,-61]],m.lightened(.1))
		"gold_collar":_r(u,-14,-64,28,5,m);_r(u,-10,-76,4,14,m)
		"loose_hair":_r(u,-11,-76,5,28,c.darkened(.55));_r(u,8,-75,5,30,c.darkened(.6))
		"rain_hood","traveler_hood":_poly(u,[[-13,-62],[-11,-77],[-5,-80],[7,-79],[13,-66],[8,-63],[6,-74],[-7,-73],[-8,-61]],c.darkened(.3))
		"crescent":_r(u,-5,-77,12,3,m);_r(u,-5,-75,4,5,m)
		"work_cap","soft_hat","troop_cap":_r(u,-11,-79,23,7,c.darkened(.15));_r(u,-14,-73,28,3,c)
		"goggles":_r(u,-10,-76,20,4,m);_r(u,-7,-76,5,5,Color("293d3f"));_r(u,2,-76,5,5,Color("293d3f"))
		"feather_hood":_poly(u,[[-12,-70],[-10,-80],[1,-77],[7,-80],[13,-68],[10,-60]],c.darkened(.5))
		"blindfold":_r(u,-9,-71,19,5,m);_r(u,8,-71,4,16,m)

static func _draw_petition(u: Node2D,t: Color,m: Color,cast: bool) -> void:
	# Idle: folded memorial at the belt. Casting: raised sheet, red seal and a lit edge.
	if cast:
		_poly(u,[[-34,-63],[-15,-67],[-12,-47],[-30,-44]],t.lightened(.2))
		_line(u,Vector2(-28,-58),Vector2(-18,-60),m,2)
		_r(u,-23,-53,4,4,Color("a04436"))
		_poly(u,[[-34,-63],[-33,-74],[-29,-68],[-26,-78],[-23,-66]],Color("e5a056"))
	else:
		_r(u,-28,-46,22,10,t)
		_line(u,Vector2(-27,-41),Vector2(-9,-41),m,2)
	_r(u,14,-40,17,9,m.darkened(.4))

static func _weapon(u: Node2D,id: String,c: Color,t: Color,s: Color,m: Color,g: Color,cast: bool) -> void:
	var lift := -4.0 if cast else 0.0
	match id:
		"register_book":
			_r(u,5,-45+lift,22,15,t);_r(u,15,-44+lift,2,13,c.darkened(.4));_r(u,-25,-56,3,29,m);_r(u,-30,-58,13,6,g)
		"ember_bowl":
			_poly(u,[[-19,-43],[20,-43],[15,-33],[-14,-33]],m.darkened(.2));_r(u,-15,-46,30,4,t);_poly(u,[[-6,-46],[-3,-59],[1,-52],[6,-60],[7,-46]],g)
		"name_slip":_r(u,18,-65+lift,10,30,t.lightened(.1));_line(u,Vector2(-22,-49),Vector2(-11,-30),m,3);_r(u,-5,-56,12,17,t.darkened(.1))
		"ash_cups":_r(u,-23,-42,13,9,m);_r(u,12,-50,13,9,t);_r(u,7,-42,3,16,g)
		"mute_talisman":_poly(u,[[-29,-56],[-10,-50],[-20,-30],[-35,-38]],t);_r(u,16,-34,9,10,m.darkened(.1));_r(u,17,-26,7,4,m)
		"blue_lantern","cage_lantern":
			_line(u,Vector2(22,-59),Vector2(22,-12),m,3);_r(u,12,-62,20,23,m.darkened(.2));_r(u,15,-59,14,17,g);_r(u,17,-64,10,3,t)
			if id=="cage_lantern":
				for x in [16,21,26]:_r(u,x,-59,2,19,m.darkened(.3))
		"watch_clapper":_r(u,-24,-45,22,8,t);_line(u,Vector2(9,-55),Vector2(25,-30),m,3)
		"heavy_ledger":_r(u,-19,-52,39,29,t.darkened(.35));_r(u,-16,-49,32,23,c.darkened(.15));_r(u,-1,-51,4,28,m)
		"door_shield":_r(u,-30,-63,20,53,c.darkened(.3));_r(u,-27,-59,14,45,m.darkened(.25));_r(u,-21,-56,3,39,t);_line(u,Vector2(25,-67),Vector2(25,-3),m,4)
		"broken_sabre":_line(u,Vector2(13,-36),Vector2(36,-52),m,6);_r(u,23,-50,8,6,c.darkened(.3));_line(u,Vector2(10,-42),Vector2(18,-30),t,3)
		"masonry":_poly(u,[[-27,-53],[-9,-57],[1,-28],[-21,-24],[-31,-36]],m.darkened(.3));_line(u,Vector2(21,-57),Vector2(22,-14),t,5);_r(u,11,-24,24,12,c.darkened(.25))
		"chain":
			for x in range(14,40,6):u.draw_rect(Rect2(x,-44+(x%12),7,7),m,false,2)
			_r(u,-24,-55,4,38,t)
		"axe":_line(u,Vector2(-4,-8),Vector2(27,-63),t,5);_poly(u,[[20,-64],[39,-60],[38,-42],[20,-47]],m)
		"gong":u.draw_circle(Vector2(-17,-39),20,t);u.draw_circle(Vector2(-17,-39),14,m.darkened(.3));u.draw_circle(Vector2(-17,-39),5,t);_line(u,Vector2(18,-57),Vector2(29,-31),t,5);_r(u,22,-35,13,10,m)
		"tile_hook":_poly(u,[[18,-43],[34,-49],[37,-40],[23,-35]],t);_line(u,Vector2(-24,-50),Vector2(-24,-23),m,3);_line(u,Vector2(-24,-50),Vector2(-16,-54),m,3)
		"mourning_staff":_line(u,Vector2(22,-79),Vector2(22,-1),t,5);_r(u,13,-71,21,7,m);_r(u,29,-65,4,20,m.lightened(.1))
		"seal_paper":_r(u,-31,-59+lift,15,30,t);_r(u,-25,-54+lift,3,19,Color("934b40"));_line(u,Vector2(13,-46),Vector2(25,-63),m,3)
		"mirror":u.draw_circle(Vector2(23,-50),13,t);u.draw_circle(Vector2(23,-50),10,Color("91aea9"));_r(u,21,-38,4,17,t);_line(u,Vector2(16,-57),Vector2(27,-46),m.lightened(.3),2)
		"burning_petition":
			_draw_petition(u,t,m,cast)
		"lotus_lamp":_poly(u,[[-22,-44],[-10,-35],[2,-45],[14,-35],[25,-44],[19,-30],[-15,-30]],t);_r(u,-4,-47,7,14,g)
		"three_ring_staff":_line(u,Vector2(24,-75),Vector2(24,0),t,4);u.draw_circle(Vector2(24,-68),7,m,false,2);u.draw_circle(Vector2(15,-64),6,m,false,2);u.draw_circle(Vector2(32,-61),6,m,false,2)
		"almanac":_r(u,-18,-49,22,25,t.darkened(.2));_r(u,-15,-45,16,3,m);_line(u,Vector2(18,-58),Vector2(30,-40),t,3)
		"needles":
			_r(u,-22,-49,10,26,t.darkened(.3))
			for offset in [-6,0,6]:_line(u,Vector2(14,-37),Vector2(20+offset,-67),m,2)
		"mortise_mallet":_r(u,-29,-46,29,23,t.darkened(.25));_r(u,-19,-52,8,35,t);_line(u,Vector2(20,-60),Vector2(20,-17),t,5);_r(u,9,-62,24,14,m.darkened(.2))
		"firecrackers":
			_line(u,Vector2(-21,-61),Vector2(-21,-17),t,2)
			for y in range(-58,-15,8):_r(u,-29,y,8,6,Color("994c3e"));_r(u,-19,y+3,8,6,Color("a05d49"))
			_line(u,Vector2(15,-51),Vector2(29,-34),m,3)
		"crow":_line(u,Vector2(7,-49),Vector2(27,-55),s,5);_poly(u,[[17,-58],[24,-68],[33,-66],[35,-59],[43,-56],[32,-55],[28,-44],[22,-51]],Color("1c2d32"));_r(u,31,-64,2,2,t)
		"market_pole":_line(u,Vector2(-33,-61),Vector2(34,-61),t,4);_line(u,Vector2(-27,-61),Vector2(-27,-47),m,2);_line(u,Vector2(28,-61),Vector2(28,-42),m,2);_r(u,-35,-47,16,22,c.lightened(.2));_r(u,18,-42,21,27,t.darkened(.25))
		"bowed_strings":_r(u,15,-35,14,18,t.darkened(.3));_line(u,Vector2(20,-70),Vector2(20,-18),m,3);_line(u,Vector2(-21,-40),Vector2(35,-50),t,2)
		"name_tablet":_poly(u,[[-16,-52],[-12,-59],[13,-59],[17,-51],[17,-18],[-16,-18]],t);_r(u,-3,-50,4,23,c.darkened(.4))
		"hunting_blade":_line(u,Vector2(14,-40),Vector2(32,-55),m,5);_r(u,-26,-51,13,20,c.lightened(.2));_r(u,-23,-48,7,13,g)
		"mask_tools":_r(u,16,-60,17,22,m.lightened(.1));_r(u,19,-53,3,3,c.darkened(.5));_r(u,27,-53,3,3,c.darkened(.5));_line(u,Vector2(-22,-34),Vector2(-10,-50),m,3)
		"short_spear":_line(u,Vector2(23,-70),Vector2(23,-1),t,3);_poly(u,[[19,-70],[23,-79],[27,-70]],m)
		"crossbow":_line(u,Vector2(-29,-42),Vector2(27,-42),t,5);_line(u,Vector2(20,-57),Vector2(20,-27),m,3);_line(u,Vector2(20,-57),Vector2(7,-42),m,2);_line(u,Vector2(20,-27),Vector2(7,-42),m,2)
		"ash_bucket":_r(u,12,-37,22,20,t.darkened(.3));u.draw_arc(Vector2(23,-38),11,PI,TAU,8,m,2)

static func _ghost(u: Node2D,family: String,v: String,c: Color,t: Color,s: Color,m: Color,g: Color,step: float,faced: bool) -> void:
	match family:
		"chao":
			_poly(u,[[-9,-64],[12,-64],[23,-7],[14,-11],[6,0],[-3,-11],[-18,-2],[-21,-15]],c)
			_r(u,-10,-79,20,18,s);_r(u,-18,-60,7,32,c.darkened(.15));_r(u,12,-59,8,34,c.lightened(.12))
			_ghost_face(u,-10,-79,20,18,s,faced)
			match v:
				"beggar":_r(u,-15,-39,33,10,t.darkened(.3));_poly(u,[[-14,-36],[17,-36],[10,-28],[-8,-28]],m);_r(u,-18,-69,10,8,c.darkened(.1))
				"wailer":_r(u,-9,-68,18,17,c.darkened(.5));_r(u,-4,-70,8,13,Color("233a3b"));_line(u,Vector2(-17,-53),Vector2(-7,-57),s,3);_line(u,Vector2(17,-54),Vector2(7,-57),s,3)
				"hungry":_r(u,-19,-45,37,25,c.darkened(.25));_r(u,-10,-40,20,16,Color("223638"));_r(u,-18,-18,14,7,t)
				"ash_shell":
					for x in [-15,-5,7,17]:_r(u,x,-30+abs(x),3,3,g)
					_r(u,-4,-57,8,25,Color("263c3b"))
				"bride":_poly(u,[[-16,-77],[14,-77],[23,-42],[12,-47],[-14,-46],[-22,-42]],c.darkened(.2));_r(u,-13,-79,28,4,t);_r(u,-3,-54,6,35,t)
				"shroud_tailor":_r(u,-14,-53,28,5,t);_r(u,14,-45,22,24,t.darkened(.15));_line(u,Vector2(-22,-50),Vector2(-13,-32),m,2)
		"changzhi":
			_r(u,-7,-78,14,17,s);_r(u,-8,-60,16,29,c);_legs(u,17,step,c)
			_line(u,Vector2(-8,-58),Vector2(-29,-40),c,6);_line(u,Vector2(-29,-40),Vector2(-34,-6),s,4)
			_line(u,Vector2(8,-58),Vector2(32,-44),c,6);_line(u,Vector2(32,-44),Vector2(38,-10),s,4)
			for x in [-3,1,5]:_line(u,Vector2(38,-10),Vector2(38+x,-1),s,2)
			_ghost_face(u,-7,-78,14,17,s,faced)
		"shanglou":
			if v == "hanging_rope":
				_ghost_face(u,-8,-80,16,15,s,faced)
				_r(u,-4,-66,8,21,s.darkened(.08))
				_poly(u,[[-9,-47],[10,-47],[15,-18],[2,-10],[-13,-17]],c)
				_line(u,Vector2(-8,-43),Vector2(-23,-62),c,5)
				_line(u,Vector2(9,-44),Vector2(23,-67),c,5)
				_line(u,Vector2(22,-80),Vector2(22,-51),t,3)
				_line(u,Vector2(-5,-17),Vector2(-6,-1+step),c,5)
				_line(u,Vector2(6,-17),Vector2(9,-1-step),c,5)
			else:
				_poly(u,[[-7,-61],[10,-62],[16,-35],[-7,-26],[-14,-44]],c)
				_ghost_face(u,-8,-79,16,18,s,faced)
				_line(u,Vector2(-10,-55),Vector2(-28,-76),c,6)
				_line(u,Vector2(10,-55),Vector2(28,-72),c,5)
				_line(u,Vector2(-3,-31),Vector2(-19,-5+step),c,7)
				_line(u,Vector2(10,-34),Vector2(21,-9-step),c,7)
				if v == "wall_shadow":
					_poly(u,[[-13,-65],[-29,-15],[-5,-32],[9,-14],[18,-56]],c.darkened(.3))
					_r(u,5,-71,3,2,g)
				else:
					_r(u,-12,-77,23,7,c.darkened(.35));_r(u,-15,-44,31,15,c)
					_line(u,Vector2(25,-76),Vector2(31,-45),t,2)
		"pomen":
			if v == "paired_porters":
				_ghost_face(u,-26,-79,17,17,s,faced)
				_ghost_face(u,10,-75,18,17,s,faced)
				_r(u,-27,-61,19,36,c);_r(u,10,-57,19,35,c.darkened(.12))
				for x in [-26,-15,10,22]:_r(u,x,-23,6,22,m.darkened(.4))
				_line(u,Vector2(-34,-56),Vector2(36,-56),t,5)
				u.draw_rect(Rect2(-15,-77,31,39),c.darkened(.4),false,3)
				_poly(u,[[-18,-78],[0,-80],[20,-77],[15,-70],[-15,-70]],t.darkened(.2))
				_r(u,-34,-58,7,25,c);_r(u,29,-54,7,24,c.lightened(.12))
			else:
				_legs(u,37,step*.5,c);_r(u,-24,-59,48,36,c)
				_r(u,-31,-55,11,31,c.darkened(.2));_r(u,22,-54,12,29,c.lightened(.1))
				_ghost_face(u,-11,-79,22,19,s,faced);_r(u,-25,-26,50,6,t.darkened(.25))
				if v == "rotten_constable":
					_r(u,-13,-80,26,9,c.darkened(.5));_line(u,Vector2(26,-50),Vector2(36,-33),m,4);_r(u,26,-35,13,5,m)
				else:
					_r(u,-21,-76,42,5,t.darkened(.2));_line(u,Vector2(-17,-46),Vector2(31,-28),m,9)
		"shui":
			_poly(u,[[-13,-62],[10,-65],[18,-15],[32,-2],[5,-5],[-25,-2],[-17,-26]],c);_ghost_face(u,-12,-78,19,17,s,faced)
			_r(u,-17,-79,6,44,c.darkened(.5));_r(u,5,-78,7,39,c.darkened(.4));_line(u,Vector2(14,-52),Vector2(35,-22),s,4);_line(u,Vector2(35,-22),Vector2(17,-2),t,2)
			_r(u,-31,-2,63,2,g.darkened(.2));_r(u,-21,-6,38,2,g.darkened(.35))
		"denggu":
			_ghost_face(u,-9,-79,18,18,s,faced);_r(u,-3,-61,6,34,s);_line(u,Vector2(-12,-54),Vector2(14,-54),s,3)
			for y in [-50,-43,-36]:_line(u,Vector2(-11,y),Vector2(11,y),s,2)
			_legs(u,23,step,c);_poly(u,[[-13,-58],[-8,-25],[0,-35],[9,-24],[15,-58]],c.darkened(.2))
			_line(u,Vector2(13,-55),Vector2(25,-66),s,3);_r(u,19,-78,18,23,m);_r(u,22,-75,12,17,g)
		"daxing":_large(u,v,c,t,s,m,g,step,faced)
		"wuceli":
			if v in ["names_mass","empty_ledger_lord"]:_large(u,v,c,t,s,m,g,step,faced)
			else:
				_poly(u,[[-12,-61],[13,-61],[23,-3],[-20,-3]],c);_r(u,-24,-56,12,32,c.darkened(.2));_r(u,15,-55,12,31,c.lightened(.1));_ghost_face(u,-9,-77,18,17,s,faced)
				_r(u,-12,-80,24,8,c.darkened(.4));_r(u,-18,-74,36,3,t.darkened(.2))
				match v:
					"erasing_clerk":_line(u,Vector2(14,-60),Vector2(33,-25),m,5);_r(u,-27,-51,17,30,t);_r(u,-22,-44,4,21,c)
					"blank_pages":
						for x in [-26,-13,0,13]:_poly(u,[[x,-63],[x+15,-67],[x+13,-5],[x-2,-9]],t.lightened(.2))
					"inverted_censer":_poly(u,[[-16,-72],[16,-72],[11,-80],[-10,-80]],m);_r(u,-11,-70,23,6,m);_r(u,16,-39,20,13,m.darkened(.2));_r(u,21,-25,4,22,g.darkened(.3))
					"stolen_masks":_r(u,10,-69,15,20,t);_r(u,-30,-42,13,17,s);_r(u,22,-35,13,17,s.darkened(.1));_line(u,Vector2(-23,-42),Vector2(-13,-62),m,2)
					"crooked_scribe":_r(u,-22,-49,37,24,t);_r(u,-3,-47,3,20,c);_line(u,Vector2(14,-56),Vector2(34,-29),m,5)
					"false_throne":_r(u,-28,-61,8,54,t);_r(u,22,-61,8,54,t);_r(u,-28,-14,58,7,t);_r(u,-18,-80,36,8,m);_r(u,-11,-78,6,14,t);_r(u,5,-78,6,14,t)

static func _ghost_face(u: Node2D,x: float,y: float,w: float,h: float,s: Color,faced: bool) -> void:
	_r(u,x,y,w,h,s)
	if faced:
		_r(u,x+w*.2,y+h*.4,3,3,Color("273d3a"));_r(u,x+w*.65,y+h*.4,3,3,Color("273d3a"));_r(u,x+w*.35,y+h*.77,w*.3,2,s.darkened(.45))

static func _large(u: Node2D,v: String,c: Color,t: Color,s: Color,m: Color,g: Color,step: float,faced: bool) -> void:
	match v:
		"mountain":
			_poly(u,[[-16,-69],[-31,-51],[-26,-9],[-10,-1],[3,-11],[18,-1],[31,-18],[25,-57],[10,-73]],c)
			_ghost_face(u,-14,-78,27,17,m.darkened(.1),faced);_r(u,-39,-53,16,37,c.darkened(.2));_r(u,24,-50,16,34,c.lightened(.1));_line(u,Vector2(-35,-63),Vector2(35,-47),t.darkened(.2),9)
		"headless_procession":
			_legs(u,32,step,m.darkened(.2));_r(u,-18,-59,37,36,c);_r(u,-10,-64,20,9,Color("182d30"));_r(u,-23,-61,10,32,m);_r(u,17,-60,10,31,m)
			for x in [-26,-10,12,29]:_line(u,Vector2(x,-20),Vector2(x,-80),t,2);_r(u,x,-78,13,19,c.lightened(.25))
			_line(u,Vector2(35,-75),Vector2(35,0),m,3)
		"mirror_body":
			_poly(u,[[-18,-79],[18,-79],[29,-15],[13,0],[-14,-1],[-29,-17]],m);_poly(u,[[-13,-74],[13,-74],[22,-17],[0,-8],[-22,-17]],c.lightened(.12));_line(u,Vector2(-15,-61),Vector2(17,-27),g,2);_ghost_face(u,-9,-70,18,19,s,faced)
		"shadow_horse":
			_r(u,-30,-39,57,23,c.darkened(.3));_poly(u,[[22,-38],[22,-58],[36,-66],[43,-52],[36,-39]],c);_r(u,34,-61,13,11,s.darkened(.3))
			for x in [-25,-11,12,22]:_line(u,Vector2(x,-18),Vector2(x+step,0),m.darkened(.4),6)
			_r(u,-10,-66,22,30,c);_ghost_face(u,-8,-80,16,15,s,faced);_line(u,Vector2(16,-58),Vector2(43,-77),t,3);_line(u,Vector2(-30,-33),Vector2(-44,-18),c,4)
		"bell_body":
			_poly(u,[[-10,-79],[11,-79],[25,-55],[29,-24],[-28,-24],[-25,-55]],m.darkened(.1));_r(u,-31,-29,63,9,t);_r(u,-18,-44,36,15,Color("203632"));_r(u,-3,-75,6,12,t);_legs(u,28,step,c);_line(u,Vector2(28,-58),Vector2(39,-35),t,5)
		"dream_cocoon":
			_poly(u,[[0,-80],[17,-70],[27,-43],[23,-17],[5,-1],[-14,-5],[-26,-35],[-19,-65]],c);_ghost_face(u,-9,-58,18,16,s,faced)
			for y in [-69,-59,-30,-20]:_line(u,Vector2(-16,y),Vector2(18,y+5),t.darkened(.15),3)
			_line(u,Vector2(-22,-47),Vector2(-35,-21),s,4);_line(u,Vector2(23,-44),Vector2(36,-24),s,4)
		"borrowed_faces":
			_poly(u,[[-14,-63],[15,-63],[28,-1],[-24,-2]],c);_legs(u,28,step,c);_ghost_face(u,-11,-79,22,18,s,faced)
			for p in [Vector2(-19,-57),Vector2(7,-47),Vector2(-9,-30)]:_ghost_face(u,p.x,p.y,13,15,s.darkened(.1),true)
			_line(u,Vector2(19,-58),Vector2(34,-38),m,4);_ghost_face(u,28,-46,14,17,s,true)
		"shrine_slave":
			_legs(u,34,step,c);_poly(u,[[-20,-58],[18,-65],[28,-24],[-23,-18]],c);_ghost_face(u,-8,-77,19,17,s,faced);_r(u,-35,-62,70,10,t.darkened(.2));_r(u,-40,-63,8,33,m);_r(u,31,-61,9,34,m);_line(u,Vector2(31,-28),Vector2(43,-8),t,4)
		"names_mass":
			_poly(u,[[-12,-78],[16,-75],[31,-57],[37,-15],[22,0],[-25,-1],[-37,-25],[-29,-59]],c)
			for p in [Vector2(-21,-67),Vector2(2,-72),Vector2(15,-51),Vector2(-27,-45),Vector2(-5,-35),Vector2(16,-22)]:_ghost_face(u,p.x,p.y,13,16,s.darkened(.15),faced)
			for x in [-30,-12,8,25]:_r(u,x,-18,8,14,t.darkened(.25))
		"empty_ledger_lord":
			for x in [-32,-16,0,16]:_poly(u,[[x,-80],[x+20,-75],[x+16,-39],[x-3,-43]],t)
			_poly(u,[[-17,-57],[16,-57],[29,-1],[-29,-1]],c);_r(u,-11,-75,22,20,Color("1d3033"));_r(u,-16,-77,33,4,m);_r(u,-27,-49,9,34,m.darkened(.2));_r(u,20,-48,9,34,m.darkened(.2));_r(u,-9,-36,30,19,t)
