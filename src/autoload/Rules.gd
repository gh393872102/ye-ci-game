extends Node
## GDD v0.2 §19.1/19.6; dev §2.3 and P0 §4.2. World pixels, not scaled art.
const DESIGN_WIDTH = 1920
const DESIGN_HEIGHT = 1080
const BODY_PX = 80
const UNIT_HEIGHT_PX = 80
const LARGE_HEIGHT_MIN_PX = 128
const LARGE_HEIGHT_MAX_PX = 176
const DOOR_HEIGHT_MIN_PX = 96
const DOOR_HEIGHT_MAX_PX = 112
const STORY_HEIGHT_MIN_PX = 176
const STORY_HEIGHT_MAX_PX = 224
const HORIZON_Y = 700
const CAMERA_WIDTH_PX = 1920
const CAMERA_WIDTH_BODY = 24
const REFERENCE_MAP_WIDTH_PX = 9600
const REFERENCE_MAP_WIDTH_BODY = 120
const REFERENCE_MAP_CAMERAS = 5
## GDD §6.5: draft movement/range relationships, not CSV speed-stat conversion.
const WALK_SPEED_MIN = 2.0
const WALK_SPEED_MAX = 2.4
const WALK_SPEED_REF = 2.2
const RETREAT_SPEED_MIN = 2.8
const RETREAT_SPEED_MAX = 3.2
const LARGE_SPEED_MIN = 1.4
const LARGE_SPEED_MAX = 1.8
const STAIR_SPEED_FACTOR_MIN = 0.55
const STAIR_SPEED_FACTOR_MAX = 0.70
const MELEE_RANGE = Vector2(0.8, 1.2)
const SHORT_RANGE = Vector2(1.8, 2.5)
const LONG_RANGE = Vector2(5.0, 8.0)
const PATH_TIME_EMPTY_MIN = 45.0
const PATH_TIME_EMPTY_MAX = 70.0
const PATH_TIME_HELD_MIN = 120.0
const PATH_TIME_HELD_MAX = 180.0
const HUMAN_CHASE_LIMIT = 2.5
const INCENSE_START_SHOU = 20
const INCENSE_START_DUO = 16
## P0 §4.3 placement choices inside the prescribed ranges.
const STORY_HEIGHT_PX = 200
const DOOR_HEIGHT_PX = 104
const TOP_BAR_HEIGHT = 56
const HALL_X = 88 * BODY_PX
const BASE_START_X = 50 * BODY_PX
const REGISTER_X = 116 * BODY_PX
const DEFAULT_CAMERA_LEFT = 76 * BODY_PX
const CAMERA_PAN_SPEED = 960.0
const INITIAL_NAME_DRAFT = 10 # P0 visible placeholder; no resource settlement.
## P1 §4.1/4.3: physical walk-band and facility choices within the locked scale.
const STAIR_SPEED_FACTOR = 0.60
const WALK_BAND_DEPTH_PX = 64.0
const GAP_LANE_OFFSET_PX = 48.0
const FOOT_RADIUS_PX = 18.0
const PATH_CLEARANCE_PX = 24.0
const TABLE_HEIGHT_PX = 48.0
## P2 / GDD 6.5 draft combat parameters. CSV speed stat is not world px/s.
const ATTACK_INTERVAL = 1.1
const RETREAT_SPEED = 3.0
const PROJECTILE_SPEED = 7.0
const PRESSURE_RATIO = 3
const PRESSURE_SECONDS = 2.5
const PRESSURE_RADIUS_BODY = 4.0
const CLOSE_THREAT_BODY = 1.4
const COVER_LEASH_BODY = 0.8
const CORPSE_SECONDS = 0.65
const TARGET_SPACING_PX = 38.0
const DEBUG_TARGET_LIMIT = 20
const DOOR_PASSAGE_GRACE = 0.4

func body_to_px(body: float) -> float:
	return body * BODY_PX

func empty_path_seconds() -> float:
	# P0 mandated whole-map estimate. P3 will measure the actual traversed path.
	return float(REFERENCE_MAP_WIDTH_BODY) / WALK_SPEED_REF
