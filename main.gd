extends Node2D
## Twisty Roads — a one-button arcade driving game (prototype-art build).
##
## NOTE ON ART: everything here is drawn with primitives as placeholder art.
## Moving to pixel art means replacing _draw() with sprites + a low-res viewport;
## the gameplay logic below is art-agnostic and will survive that switch.
##
## COORDINATES: the road lives in unbounded WORLD-x (it can wander anywhere, so
## it feels like you're going somewhere). A horizontal CAMERA follows the car,
## so the car and road are always on screen. screen_x = world_x - camera_x + W/2.

# ---------------- layout ----------------
const SCREEN_W := 720.0
const SCREEN_H := 1280.0
const CAR_Y := 980.0
const CAR_W := 50.0
const CAR_H := 90.0
const CAR_HALF_W := CAR_W * 0.5
const CAR_HALF_H := CAR_H * 0.5
const COL_HALF_W := 19.0          # collision half-extents (smaller than the art = fairer)
const COL_HALF_H := 36.0
const ROAD_CENTER_X := 360.0

# ---------------- camera ----------------
const CAM_FOLLOW := 6.0
const CAM_MAX_OFF := 150.0
const CAM_LOOKAHEAD := 240.0
const CAM_LOOK_W := 0.30
const GRID := 110.0               # parallax ground grid spacing

# ---------------- difficulty ----------------
const BASE_SPEED := 290.0
const SPEED_PER_SEC := 1.8        # climbs to MAX over ~2 min, so acceleration is actually felt
const MAX_SPEED := 520.0
const START_HALF_WIDTH := 200.0
const MIN_HALF_WIDTH := 120.0
const NARROW_PER_DIST := 0.0007   # road narrows by distance (visible ahead, fair)
const RAMP_SECONDS := 220.0
const INTRO_DIST := 1500.0        # straight, hazard-free start

# Rhythm curve: periodic "breather" sections where the road widens (speed stays
# linear — no slowdown).
const RHYTHM_FREQ := 0.0013        # ~4800px between breathers
const RHYTHM_WIDTH_AMP := 55.0

# Real-world feel: 8 world-pixels = 1 metre.
const PX_PER_METER := 8.0

# Jump = high-risk/high-reward: clear obstacles, +2 coins on landing, speed boost.
const BOOST_MULT := 1.45
const BOOST_TIME := 2.2
const JUMP_COINS := 2
const NEAR_MISS_DX := 94.0        # lateral gap that counts as a near miss (crash is ~44)
const NEAR_MISS_COINS := 2
const COL_BOOST := Color("ffe27a")

# Resume countdown
const COUNT_TIME := 3.0

# Floating pickup popups
const POPUP_LIFE := 0.9
const POPUP_RISE := 90.0

# ---------------- steering ----------------
const STEER_SPEED := 430.0
const RETURN_SPEED := 300.0
const STEER_ACCEL := 2600.0
const MAX_TILT := 0.45

# ---------------- road shape ----------------
const MICRO_AMP := 0.0            # 0 = perfectly smooth edges
const DASH_PERIOD := 90.0

# ---------------- forks ----------------
# road_center/road_half_width describe ONE continuous centerline. A "fork"
# turns a straight stretch into two lanes (symmetric about a straightened chord)
# that separate around a grass median and then merge back — pick a lane, grab
# the coins, rejoin. Forks are the multi-lane "segments" layered on top of the
# centerline, which is what lets the road split without the centerline having to
# be multi-valued.
const BRANCH_SPACING := 7000.0    # min gap between one fork ending and the next starting
const FORK_LEN_MIN := 1300.0
const BRANCH_RAMP := 0.22         # fraction of a fork's length spent splitting / merging
const LANE_FRAC := 0.62           # split-lane half-width as a fraction of the local road
const LANE_HW_MIN := 76.0
const FORK_MEDIAN_FRAC := 0.2     # fork median half-width as a fraction of the local road
const FORK_SWEEP_CAP := 320.0     # how fast lanes may peel apart; lower => longer, gentler forks a player can still track at boosted top speed
const BRANCH_STRAIGHT_DELTA := 70.0  # entry must be at least this straight (per 300px)
const BRANCH_MAX_DRIFT := 280.0   # max sideways drift of the road across a fork (chord stays gentle)
const BRANCH_COINS := 4           # coins seeded along the scenic lane

# Fork variety: a branch picks a STYLE and randomises its geometry so no two read
# the same. The two lanes of a fork are described independently now (their own
# separation, width and split-ramp), so a fork can be a clean mirror split or a
# lopsided one (a fat lane beside a thin one). Length varies too — a longer fork
# only peels more gently, so it stays within the sweep cap and is always fair.
const FORK_LEN_VARY_MAX := 1.85   # fork length multiplier (>=1 keeps peel within the sweep cap)
const FORK_OFF_VARY := 0.30       # +/- fraction jittered onto each lane's separation
const FORK_HW_VARY := 0.22        # +/- fraction jittered onto each lane's half-width
const FORK_RAMP_VARY := 0.45      # +/- fraction jittered onto each lane's split ramp
const FORK_ASYM_CHANCE := 0.5     # chance a fork is lopsided rather than mirror-symmetric
const SHOULDER_CHANCE := 0.4      # chance a branch is a bailout shoulder instead of a fork

# Forks aren't dead-straight chords any more: a gentle sideways WAVE (faded in/out
# at the merges so it stays seamless) makes the split wind, and each fork can carry
# OIL slicks in its lanes so committing to one is a real test, not a cruise. The
# wave is kept small enough that a lane never moves sideways faster than the player
# can track, even stacked on top of the split peel.
const FORK_WAVE_AMP := 14.0       # max sideways wander added across a fork
const FORK_WAVE_LEN := 1050.0     # wavelength of that wander
const FORK_WAVE_CHANCE := 0.8     # chance a fork winds rather than running straight
const FORK_OIL_CHANCE := 0.6      # chance a fork is seeded with oil slicks
const FORK_OIL_MAX := 3           # up to this many oil slicks across a fork's lanes

# Bailout shoulder: the main road stays full width and a narrower coin lane
# sprouts from ONE shoulder, bulges out around a grass median, then merges back —
# an optional scenic/greedy detour rather than a commit-to-a-lane fork.
const SHOULDER_HW_MIN := 70.0
const SHOULDER_HW_FRAC := 0.5     # shoulder half-width as a fraction of the road
const SHOULDER_BULGE_MIN := 130.0 # how far the shoulder's far edge sits beyond the road edge
const SHOULDER_BULGE_FRAC := 1.0  # bulge as a fraction of the road half-width
const SHOULDER_RAMP := 0.3        # fraction of the shoulder spent sprouting / rejoining
const SHOULDER_LEN_MIN := 1100.0
const SHOULDER_LEN_VARY := 0.9    # +/- fraction jittered onto the shoulder length
const SHOULDER_COINS := 5

# ---------------- coins ----------------
const COIN_SPACING := 1900.0
const COIN_R := 15.0
const COL_COIN := Color("ffd54a")
const COL_COIN_HI := Color("fff3c4")

# ---------------- hazards ----------------
const HAZARD_SPACING := 560.0
const STRAIGHT_DELTA := 30.0      # only spawn where the road is this straight
const GAP_MIN := 50.0             # guaranteed passable gap (car-center room)
const BLOCK_W := 60.0
const BLOCK_H := 42.0
const TRAFFIC_W := 50.0
const TRAFFIC_H := 90.0
const TRAFFIC_REL_MIN := 0.30     # enemy closing speed as a fraction of player speed
const TRAFFIC_REL_MAX := 0.75     # (so enemies get faster as you do)
const TRAFFIC_LAT_SPEED := 320.0  # how fast traffic steers sideways
const OIL_R := 56.0
const OIL_TIME := 1.4
const OIL_STEER_MULT := 0.30
const JUMP_W := 150.0
const JUMP_H := 48.0
const AIR_TIME := 0.6
const TIRE_LIFE := 2.0

# Jump-the-gap: a hole spans the WHOLE road and a full-width ramp is planted just
# ahead of it, so the only way past is to launch off the ramp and sail over the
# hole (the ramp is wider than the road, so staying on the road guarantees the
# launch). Geometry is sized so the arc clears the hole even at base speed: the
# launch fires COL_HALF_H + JUMP_H/2 (~60px) before the ramp, leaving ~114px of
# air past it at base speed, so AHEAD + HALF + COL_HALF_H is kept well under that.
const JUMP_GAP_CHANCE := 0.16     # share of (eligible) hazard rolls that become a jump-the-gap
const JUMP_GAP_MIN_DIST := 3200.0 # only once the run is underway (speed has climbed; room to react)
const JUMP_GAP_AHEAD := 44.0      # ramp-centre -> hole-centre distance
const JUMP_GAP_HALF := 20.0       # half the hole's length along the road
const JUMP_GAP_RUNWAY := 460.0    # clear road reserved past the hole for the landing (covers max-speed arc)
const RAMP_GAP_INSET := 6.0       # ramp half-width = road half-width minus this

# ---------------- ramming ----------------
# Landing a ramp grants a short boost; while it's active the car ploughs straight
# THROUGH blockers and traffic instead of crashing, banking RAM_COINS per smash.
const RAM_COINS := 2

# ---------------- background decorations ----------------
# Purely cosmetic props scattered in the off-road on both sides (rocks/trees/etc.).
# They carry a stable variant index so the art pipeline can map each to a per-theme
# sprite later; until then they draw as simple themed primitives.
const DECO_SPACING := 150.0       # avg world-distance between props on one side
const DECO_MARGIN := 26.0         # min gap from the road edge to a prop
const DECO_BAND := 230.0          # how far out into the off-road props may sit
const DECO_VARIANTS := 3          # number of primitive prop shapes / sprite slots

const COL_BLOCK := Color("f4c20d")
const COL_BLOCK_DARK := Color("141414")
const COL_TRAFFIC := Color("e74c3c")
const COL_TRAFFIC_DARK := Color("7b241c")
const COL_OIL := Color(0.02, 0.02, 0.05, 0.72)
const COL_OIL_HI := Color(0.55, 0.55, 0.62, 0.22)
const COL_JUMP := Color("9aa7b8")
const COL_JUMP_HI := Color("e8edf2")
const COL_TIRE := Color(0.04, 0.04, 0.04, 1.0)
const COL_EXHAUST := Color(0.72, 0.72, 0.78)
const COL_GAP := Color("070708")          # the hole itself (reads as a void in the road)
const COL_GAP_RIM := Color("f4c20d")      # hazard-striped lip on the near edge

# ---------------- crash ----------------
const CRASH_TIME := 1.0
const COL_SPEED_MAX := Color("ff5a5f")
const COL_SPEED := Color("e8e8e8")

# ---------------- speedometer gauge ----------------
const GAUGE_CENTER := Vector2(118.0, 156.0)
const GAUGE_R := 84.0
const GAUGE_START_DEG := 140.0
const GAUGE_END_DEG := 400.0
const GAUGE_MIN_KMH := 90.0       # dial floor (just below start speed) so the needle has room to climb
const GAUGE_MAX_KMH := 340.0      # ~MAX_SPEED * BOOST_MULT converted to km/h
const COL_GAUGE_BG := Color(0, 0, 0, 0.35)
const COL_GAUGE_RING := Color(1, 1, 1, 0.25)
const COL_GAUGE_TICK := Color(1, 1, 1, 0.4)
const COL_GAUGE_REDZONE := Color("ff5a5f")

# ---------------- save ----------------
const SAVE_PATH := "user://twisty_roads.cfg"

# ---------------- art pipeline ----------------
# Convention-based, exactly like the audio: drop a texture at
# res://art/<theme>/<slot>.<ext> and it's used automatically; if it's missing the
# matching res://art/default/<slot> is tried, and failing that the primitive
# _draw fallback runs — so the game looks identical with or without art present.
# Slots: road, background (both tiled), car (player), enemy_0/1/.. (random per
# car), deco_0/1/.. (background props). "enemy" and "deco" also accept an
# unnumbered single file. Lists let a theme ship several car/prop variants.
const ART_DIR := "res://art/"
const ART_EXTS := ["png", "webp", "jpg", "jpeg", "svg"]
const ROAD_TEX_TILE := 220.0      # world-distance the road texture spans before repeating
const BG_TEX_PARALLAX := 0.45     # how much the background texture scrolls vs the world

# ---------------- themes ----------------
# Palettes are placeholders that approximate each theme until real sprites land.
# "vehicle"/"enemy" name the vehicles, "vfx" names the effect set, "stripes" says
# whether the road carries a painted centre line (off-road / track surfaces don't)
# — these are the slots the art pipeline keys off (e.g. res://art/<id>/car.png).
const THEME_ORDER := ["default", "synthwave", "track", "rally", "jdm", "jetski", "sand", "mud", "rainbow", "frostbite", "wiped"]
const THEMES := {
	"default":   { "name": "Standard",     "price": 0,    "offroad": "2e5d34", "road": "3c4146", "edge": "e8e8e8", "dash": "f2c14e", "stripes": true,  "car": "1f6fd0", "car_dark": "0d4a99", "vehicle": "BMW E46",          "enemy": "Toyota RAV4",       "vfx": "dust" },
	"synthwave": { "name": "Synthwave",    "price": 300,  "offroad": "1a0b2e", "road": "241341", "edge": "ff2e97", "dash": "00f0ff", "stripes": true,  "car": "ffd319", "car_dark": "ff5f1f", "vehicle": "Lamborghini Countach", "enemy": "Sports coupes", "vfx": "neon" },
	"track":     { "name": "Track Attack", "price": 400,  "offroad": "2e7d32", "road": "3a3a3a", "edge": "e03131", "dash": "ffffff", "stripes": false, "car": "e10600", "car_dark": "8a0400", "vehicle": "Open-wheel racer", "enemy": "Open-wheel racers", "vfx": "smoke" },
	"rally":     { "name": "Rally Rush",   "price": 500,  "offroad": "234a25", "road": "6b4f2a", "edge": "caa15a", "dash": "ffffff", "stripes": false, "car": "1565c0", "car_dark": "0d47a1", "vehicle": "Subaru Impreza",   "enemy": "Mitsubishi Lancer", "vfx": "gravel" },
	"jdm":       { "name": "JDM",          "price": 600,  "offroad": "0d1b2a", "road": "23272e", "edge": "f72585", "dash": "4cc9f0", "stripes": true,  "car": "e6552a", "car_dark": "a83419", "vehicle": "Toyota Supra",     "enemy": "Mazda Miata",       "vfx": "underglow" },
	"jetski":    { "name": "Jetski Escape","price": 700,  "offroad": "e3c98f", "road": "1f7a8c", "edge": "9be7ff", "dash": "ffffff", "stripes": false, "car": "ff5252", "car_dark": "b71c1c", "vehicle": "Jetski",          "enemy": "Jetskis",           "vfx": "splash" },
	"sand":      { "name": "Sand Rally",   "price": 800,  "offroad": "c2954e", "road": "9c7a3c", "edge": "e8d6a0", "dash": "ffffff", "stripes": false, "car": "2e7d32", "car_dark": "1b5e20", "vehicle": "Rally buggy",      "enemy": "Porsche Safari",    "vfx": "sand" },
	"mud":       { "name": "Mud Sprint",   "price": 900,  "offroad": "3b5323", "road": "5b432a", "edge": "8a6d3b", "dash": "ffffff", "stripes": false, "car": "d32f2f", "car_dark": "9a1f1f", "vehicle": "Enduro bike",      "enemy": "Enduro bikes",      "vfx": "mud" },
	"rainbow":   { "name": "Rainbow Lane", "price": 1000, "offroad": "0b0b2a", "road": "3a2f5e", "edge": "ff5ec7", "dash": "ffffff", "stripes": true,  "car": "ffeb3b", "car_dark": "fbc02d", "vehicle": "Kart",            "enemy": "Karts",             "vfx": "rainbow" },
	"frostbite": { "name": "Frostbite Run","price": 1200, "offroad": "dfe9f0", "road": "8fa8bf", "edge": "5b86b0", "dash": "ffffff", "stripes": false, "car": "455a64", "car_dark": "263238", "vehicle": "Ford F-150",      "enemy": "Porsche Cayenne",   "vfx": "snow" },
	"wiped":     { "name": "Wiped Out",    "price": 1500, "offroad": "0a1226", "road": "13294b", "edge": "39c0ff", "dash": "8affff", "stripes": true,  "car": "00e5ff", "car_dark": "0091a7", "vehicle": "Hover racer",      "enemy": "Hover racers",      "vfx": "energy" },
}

# ---------------- challenges ----------------
const DEFAULT_STATS := {
	"total_time": 0.0, "total_distance": 0.0, "total_runs": 0,
	"best_run_time": 0.0, "best_distance": 0.0, "best_streak": 0,
	"best_no_coin_time": 0.0, "runs_over_2min": 0,
}
const CHALLENGES := [
	{ "id": "first",    "desc": "Finish your first run",        "stat": "total_runs",        "goal": 1,      "reward": 20 },
	{ "id": "reg",      "desc": "Complete 25 runs",             "stat": "total_runs",        "goal": 25,     "reward": 150 },
	{ "id": "two_min",  "desc": "Survive 2 minutes in a run",   "stat": "best_run_time",     "goal": 120,    "reward": 100 },
	{ "id": "five_2m",  "desc": "Complete 5 runs over 2 min",   "stat": "runs_over_2min",    "goal": 5,      "reward": 200 },
	{ "id": "halfhour", "desc": "Drive 30 minutes total",       "stat": "total_time",        "goal": 1800,   "reward": 150 },
	{ "id": "far",      "desc": "Reach 5 km in one run",        "stat": "best_distance",     "goal": 40000,  "reward": 60 },
	{ "id": "farther",  "desc": "Reach 12 km in one run",       "stat": "best_distance",     "goal": 96000,  "reward": 160 },
	{ "id": "total10k", "desc": "Drive 100 km total",           "stat": "total_distance",    "goal": 800000, "reward": 200 },
	{ "id": "streak10", "desc": "Collect 10 coins in a row",    "stat": "best_streak",       "goal": 10,     "reward": 80 },
	{ "id": "ascetic",  "desc": "Drive 30s without a coin",     "stat": "best_no_coin_time", "goal": 30,     "reward": 90 },
]

enum State { MENU, STORE, CHALLENGES, PLAYING, PAUSED, COUNTDOWN, CRASH, GAME_OVER }

# ---------------- runtime ----------------
var state: int = State.MENU
var distance := 0.0
var time_alive := 0.0
var car_x := ROAD_CENTER_X
var camera_x := ROAD_CENTER_X
var lateral_velocity := 0.0
var score := 0
var session_coins := 0

var coins_total := 0
var owned := { "default": true }
var selected := "default"
var stats: Dictionary = {}
var completed: Dictionary = {}

var _streak := 0
var _streak_best := 0
var _no_coin_timer := 0.0
var _no_coin_best := 0.0

var col_offroad: Color
var col_road: Color
var col_edge: Color
var col_dash: Color
var col_car: Color
var col_car_dark: Color
var col_deco: Color                # tint for primitive background props
var _theme_stripes := true         # does the current theme paint a centre line?

# Convention-loaded theme art (null = use the primitive fallback). Mirrors audio.
var _tex_road: Texture2D
var _tex_bg: Texture2D
var _tex_car: Texture2D
var _tex_enemy: Array[Texture2D] = []
var _tex_deco: Array[Texture2D] = []

var _pt_d := PackedFloat32Array()
var _pt_x := PackedFloat32Array()
var _track_frontier_d := 0.0
var _track_last_x := ROAD_CENTER_X
var _bias := 0.0
var _pattern_queue: Array = []

# forks layered on the centerline (see FORKS section)
var _branches: Array[Dictionary] = []
var _branch_frontier_d := 0.0
var _next_branch_d := 0.0          # earliest distance the next branch may start

var _coins: Array = []
var _coin_frontier_d := 0.0
var _hazards: Array = []
var _hazard_frontier_d := 0.0
var _decos: Array = []             # background props {d, x, side, variant, scale}
var _deco_frontier_d := 0.0
var _tire_marks: Array = []
var _particles: Array = []
var _boom: Array = []
var _exhaust_accum := 0.0
var _oil_timer := 0.0
var _air_timer := 0.0
var _boost_timer := 0.0
var _crash_timer := 0.0
var _count_timer := 0.0
var _popups: Array = []
var _ui_font: Font

# ---------------- audio ----------------
# Convention-based, like the art slots: drop a file at res://audio/<name>.ogg
# (or .wav/.mp3) and it plays automatically. Missing files are a silent no-op,
# so the game runs identically with or without audio assets present.
# Engine is two crossfaded loops (engine_low/engine_high) rather than one
# loop with a wide pitch shift, so going fast changes the engine's timbre
# instead of just speeding up its pitch — avoids the droney/chipmunk effect.
# Expected slots: crash, coin, land, near_miss, jump, smash, oil_squeal, horn,
# purchase, challenge, ui_tap, engine_low, engine_high.
var _sfx_crash: AudioStreamPlayer
var _sfx_coin: AudioStreamPlayer
var _sfx_land: AudioStreamPlayer
var _sfx_near_miss: AudioStreamPlayer
var _sfx_jump: AudioStreamPlayer
var _sfx_smash: AudioStreamPlayer
var _sfx_oil: AudioStreamPlayer
var _sfx_beep: AudioStreamPlayer
var _sfx_purchase: AudioStreamPlayer
var _sfx_challenge: AudioStreamPlayer
var _sfx_ui: AudioStreamPlayer
var _engine_low: AudioStreamPlayer
var _engine_high: AudioStreamPlayer

var _micro_noise := FastNoiseLite.new()
var _touch_ids: Dictionary = {}
var _steer_armed := false
var _run_started := false

# UI
var _menu: Control
var _store: Control
var _challenges: Control
var _hud: Control
var _pause: Control
var _gameover: Control
var _menu_coins: Label
var _store_coins: Label
var _theme_buttons := {}
var _challenge_labels: Array = []
var _hud_score: Label
var _hud_coins: Label
var _hud_prompt: Label
var _go_score: Label
var _go_coins: Label
var _go_challenge: Label


func _ready() -> void:
	randomize()
	# lets a road texture tile along its length via UVs > 1 (see _fill_band)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ui_font = ThemeDB.fallback_font
	_micro_noise.frequency = 0.01
	_load_save()
	_apply_theme(selected)
	_build_audio()
	_build_ui()
	_goto_menu()


# ============================================================
#  SAVE / THEMES
# ============================================================
func _load_save() -> void:
	stats = DEFAULT_STATS.duplicate(true)
	completed = {}
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		coins_total = int(cfg.get_value("data", "coins", 0))
		selected = str(cfg.get_value("data", "selected", "default"))
		owned = { "default": true }
		for k in cfg.get_value("data", "owned", ["default"]):
			if THEMES.has(k):
				owned[k] = true
		if not THEMES.has(selected) or not owned.has(selected):
			selected = "default"
		var s = cfg.get_value("data", "stats", {})
		for key in s:
			stats[key] = s[key]
		var c = cfg.get_value("data", "completed", {})
		for key in c:
			completed[key] = true


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("data", "coins", coins_total)
	cfg.set_value("data", "selected", selected)
	cfg.set_value("data", "owned", owned.keys())
	cfg.set_value("data", "stats", stats)
	cfg.set_value("data", "completed", completed)
	cfg.save(SAVE_PATH)


func _apply_theme(id: String) -> void:
	if not THEMES.has(id):
		id = "default"
	var t: Dictionary = THEMES[id]
	col_offroad = Color(t["offroad"])
	col_road = Color(t["road"])
	col_edge = Color(t["edge"])
	col_dash = Color(t["dash"])
	col_car = Color(t["car"])
	col_car_dark = Color(t["car_dark"])
	_theme_stripes = bool(t.get("stripes", true))
	# primitive prop tint: keep it readable whatever the ground colour is
	if col_offroad.get_luminance() < 0.4:
		col_deco = col_offroad.lightened(0.32)
	else:
		col_deco = col_offroad.darkened(0.42)
	_load_theme_art(id)


# ============================================================
#  ART (convention-based textures; mirrors the audio loader below)
# ============================================================
# Texture for one slot in one theme, or null. Single slots (road/background/car)
# fall back to the default theme's texture; lists fall back as a whole set.
func _load_tex_exact(theme_id: String, slot: String) -> Texture2D:
	for ext in ART_EXTS:
		var path := "%s%s/%s.%s" % [ART_DIR, theme_id, slot, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _load_tex(theme_id: String, slot: String) -> Texture2D:
	var tex := _load_tex_exact(theme_id, slot)
	if tex == null and theme_id != "default":
		tex = _load_tex_exact("default", slot)
	return tex


# A slot may ship as a single file (slot.png) or a numbered series
# (slot_0.png, slot_1.png, ...). Returns the theme's own set, else the default's.
func _load_tex_list(theme_id: String, slot: String) -> Array[Texture2D]:
	for tid in [theme_id, "default"]:
		var out: Array[Texture2D] = []
		var single := _load_tex_exact(tid, slot)
		if single != null:
			out.append(single)
		var i := 0
		while true:
			var t := _load_tex_exact(tid, "%s_%d" % [slot, i])
			if t == null:
				break
			out.append(t)
			i += 1
		if out.size() > 0:
			return out
	return []


func _load_theme_art(id: String) -> void:
	_tex_road = _load_tex(id, "road")
	_tex_bg = _load_tex(id, "background")
	_tex_car = _load_tex(id, "car")
	_tex_enemy = _load_tex_list(id, "enemy")
	_tex_deco = _load_tex_list(id, "deco")


# ============================================================
#  AUDIO (convention-based; see slot comment above)
# ============================================================
const AUDIO_DIR := "res://audio/"

func _load_sfx(name: String) -> AudioStream:
	for ext in ["ogg", "wav", "mp3"]:
		var path := "%s%s.%s" % [AUDIO_DIR, name, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _make_player(name: String, bus: String, loop_volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _load_sfx(name)
	p.bus = bus
	p.volume_db = loop_volume_db
	add_child(p)
	return p


func _build_audio() -> void:
	_sfx_crash = _make_player("crash", "Master", 0.0)
	_sfx_coin = _make_player("coin", "Master", -4.0)
	_sfx_land = _make_player("land", "Master", -2.0)
	_sfx_near_miss = _make_player("near_miss", "Master", -2.0)
	_sfx_jump = _make_player("jump", "Master", -2.0)
	_sfx_smash = _make_player("smash", "Master", -1.0)
	_sfx_oil = _make_player("oil_squeal", "Master", -3.0)
	_sfx_beep = _make_player("horn", "Master", -6.0)
	_sfx_purchase = _make_player("purchase", "Master", -3.0)
	_sfx_challenge = _make_player("challenge", "Master", -2.0)
	_sfx_ui = _make_player("ui_tap", "Master", -6.0)
	_engine_low = _make_player("engine_low", "Master", -10.0)
	_engine_high = _make_player("engine_high", "Master", -10.0)


func _play_sfx(p: AudioStreamPlayer) -> void:
	if p != null and p.stream != null:
		p.play()


# Crossfades two engine loops by speed instead of pitch-shifting one loop
# across a wide range, so the engine note changes character rather than
# turning into an irritating chipmunk/drone at the extremes.
func _update_engine_audio() -> void:
	var frac := clampf((current_speed() - BASE_SPEED) / (MAX_SPEED * BOOST_MULT - BASE_SPEED), 0.0, 1.0)
	_engine_low.volume_db = lerpf(-6.0, -26.0, frac)
	_engine_high.volume_db = lerpf(-26.0, -6.0, frac)
	_engine_low.pitch_scale = lerpf(0.85, 1.15, frac)
	_engine_high.pitch_scale = lerpf(0.95, 1.25, frac)


# ============================================================
#  UI
# ============================================================
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_menu = _make_panel(layer)
	_make_label(_menu, "TWISTY\nROADS", Vector2(0, 140), Vector2(SCREEN_W, 200), 80)
	_menu_coins = _make_label(_menu, "Coins: 0", Vector2(0, 420), Vector2(SCREEN_W, 60), 40)
	_make_button(_menu, "PLAY", Vector2(180, 540), Vector2(360, 96), 46).pressed.connect(_start_run)
	_make_button(_menu, "STORE", Vector2(180, 656), Vector2(360, 96), 46).pressed.connect(_open_store)
	_make_button(_menu, "CHALLENGES", Vector2(180, 772), Vector2(360, 96), 38).pressed.connect(_open_challenges)
	_make_label(_menu, "Hold anywhere to steer left, release to drift right", Vector2(20, 920), Vector2(SCREEN_W - 40, 60), 26)

	_store = _make_panel(layer)
	_make_label(_store, "STORE", Vector2(0, 50), Vector2(SCREEN_W, 80), 56)
	_store_coins = _make_label(_store, "Coins: 0", Vector2(0, 140), Vector2(SCREEN_W, 50), 34)
	var sy := 210.0
	for id in THEME_ORDER:
		var b := _make_button(_store, "", Vector2(70, sy), Vector2(580, 74), 24)
		b.pressed.connect(_on_theme_pressed.bind(id))
		_theme_buttons[id] = b
		sy += 84.0
	_make_button(_store, "BACK", Vector2(180, sy + 6.0), Vector2(360, 78), 36).pressed.connect(_goto_menu)

	_challenges = _make_panel(layer)
	_make_label(_challenges, "CHALLENGES", Vector2(0, 50), Vector2(SCREEN_W, 80), 56)
	var cy := 160.0
	for i in range(CHALLENGES.size()):
		var lbl := _make_label(_challenges, "", Vector2(40, cy), Vector2(SCREEN_W - 80, 84), 24)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_challenge_labels.append(lbl)
		cy += 92.0
	_make_button(_challenges, "BACK", Vector2(180, 1090), Vector2(360, 90), 40).pressed.connect(_goto_menu)

	_hud = _make_panel(layer)
	_hud_score = _make_label(_hud, "0", Vector2(0, 36), Vector2(SCREEN_W, 80), 64)
	_hud_coins = _make_label(_hud, "Coins: 0", Vector2(0, 124), Vector2(SCREEN_W, 50), 34)
	_hud_prompt = _make_label(_hud, "Tap to begin\nHold to steer", Vector2(0, 540), Vector2(SCREEN_W, 200), 52)
	_make_button(_hud, "II", Vector2(600, 30), Vector2(96, 72), 40).pressed.connect(_pause_game)

	_pause = _make_panel(layer)
	_make_label(_pause, "PAUSED", Vector2(0, 360), Vector2(SCREEN_W, 90), 64)
	_make_button(_pause, "RESUME", Vector2(180, 520), Vector2(360, 96), 46).pressed.connect(_resume)
	_make_button(_pause, "RESTART", Vector2(180, 636), Vector2(360, 96), 46).pressed.connect(_start_run)
	_make_button(_pause, "MENU", Vector2(180, 752), Vector2(360, 96), 40).pressed.connect(_goto_menu)

	_gameover = _make_panel(layer)
	_make_label(_gameover, "GAME OVER", Vector2(0, 280), Vector2(SCREEN_W, 90), 64)
	_go_score = _make_label(_gameover, "Score: 0", Vector2(0, 400), Vector2(SCREEN_W, 60), 40)
	_go_coins = _make_label(_gameover, "Coins earned: 0", Vector2(0, 468), Vector2(SCREEN_W, 60), 36)
	_go_challenge = _make_label(_gameover, "", Vector2(30, 540), Vector2(SCREEN_W - 60, 90), 28)
	_make_button(_gameover, "RESTART", Vector2(180, 660), Vector2(360, 100), 48).pressed.connect(_start_run)
	_make_button(_gameover, "MENU", Vector2(180, 790), Vector2(360, 90), 40).pressed.connect(_goto_menu)


func _make_panel(layer: CanvasLayer) -> Control:
	var c := Control.new()
	c.position = Vector2.ZERO
	c.size = Vector2(SCREEN_W, SCREEN_H)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(c)
	return c


func _make_label(parent: Control, text: String, pos: Vector2, size: Vector2, fsize: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", fsize)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _make_button(parent: Control, text: String, pos: Vector2, size: Vector2, fsize: int) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.add_theme_font_size_override("font_size", fsize)
	b.pressed.connect(func(): _play_sfx(_sfx_ui))
	parent.add_child(b)
	return b


func _show_screen() -> void:
	_menu.visible = state == State.MENU
	_store.visible = state == State.STORE
	_challenges.visible = state == State.CHALLENGES
	_hud.visible = state == State.PLAYING or state == State.CRASH or state == State.COUNTDOWN
	_pause.visible = state == State.PAUSED
	_gameover.visible = state == State.GAME_OVER


# ============================================================
#  TRANSITIONS
# ============================================================
func _reset_world() -> void:
	distance = 0.0
	time_alive = 0.0
	lateral_velocity = 0.0
	car_x = ROAD_CENTER_X
	camera_x = ROAD_CENTER_X
	_oil_timer = 0.0
	_air_timer = 0.0
	_boost_timer = 0.0
	_crash_timer = 0.0
	_count_timer = 0.0
	_bias = 0.0
	_coins.clear()
	_hazards.clear()
	_decos.clear()
	_tire_marks.clear()
	_particles.clear()
	_boom.clear()
	_popups.clear()
	_pattern_queue.clear()
	_coin_frontier_d = 0.0
	_hazard_frontier_d = 0.0
	_deco_frontier_d = 0.0
	_branches.clear()
	_branch_frontier_d = 0.0
	_next_branch_d = INTRO_DIST + 1200.0
	_streak = 0
	_streak_best = 0
	_no_coin_timer = 0.0
	_no_coin_best = 0.0
	_reset_track()


func _goto_menu() -> void:
	state = State.MENU
	_reset_world()
	_menu_coins.text = "Coins: %d" % coins_total
	_show_screen()
	queue_redraw()


func _open_store() -> void:
	state = State.STORE
	_refresh_store()
	_show_screen()
	queue_redraw()


func _open_challenges() -> void:
	state = State.CHALLENGES
	_refresh_challenges()
	_show_screen()
	queue_redraw()


func _start_run() -> void:
	state = State.PLAYING
	score = 0
	session_coins = 0
	_steer_armed = false
	_run_started = false
	_apply_theme(selected)
	_reset_world()
	_engine_low.stop()
	_engine_high.stop()
	_ensure_track(distance + 1400.0)
	_ensure_branches(distance + 1400.0)
	_ensure_hazards(distance + 1400.0)
	_ensure_coins(distance + 1400.0)
	_ensure_decos(distance + 1400.0)
	_hud_score.text = "0"
	_hud_coins.text = "Coins: 0"
	_hud_prompt.visible = true
	_show_screen()


func _pause_game() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	_engine_low.stream_paused = true
	_engine_high.stream_paused = true
	_show_screen()
	queue_redraw()


func _resume() -> void:
	state = State.COUNTDOWN
	_count_timer = COUNT_TIME
	_steer_armed = false
	_hud_prompt.visible = false
	_engine_low.stream_paused = false
	_engine_high.stream_paused = false
	_show_screen()
	queue_redraw()


func _crash() -> void:
	if state != State.PLAYING:
		return
	state = State.CRASH
	_crash_timer = CRASH_TIME
	Input.vibrate_handheld(220)
	_spawn_explosion(_sx(car_x), CAR_Y)
	_engine_low.stop()
	_engine_high.stop()
	_play_sfx(_sfx_crash)


func _game_over() -> void:
	state = State.GAME_OVER
	stats["total_runs"] = int(stats["total_runs"]) + 1
	stats["total_time"] = float(stats["total_time"]) + time_alive
	stats["total_distance"] = float(stats["total_distance"]) + distance
	stats["best_run_time"] = maxf(float(stats["best_run_time"]), time_alive)
	stats["best_distance"] = maxf(float(stats["best_distance"]), distance)
	stats["best_streak"] = maxi(int(stats["best_streak"]), _streak_best)
	stats["best_no_coin_time"] = maxf(float(stats["best_no_coin_time"]), maxf(_no_coin_best, _no_coin_timer))
	if time_alive >= 120.0:
		stats["runs_over_2min"] = int(stats["runs_over_2min"]) + 1
	coins_total += session_coins
	var newly := _evaluate_challenges()
	_save()
	_go_score.text = "Distance: %.2f KM" % _dist_km()
	_go_coins.text = "Coins earned: %d" % session_coins
	if newly.is_empty():
		_go_challenge.text = ""
	else:
		var bonus := 0
		var names: Array = []
		for ch in newly:
			bonus += int(ch["reward"])
			names.append(str(ch["desc"]))
		_go_challenge.text = "Challenge complete! +%d coins\n%s" % [bonus, ", ".join(names)]
		_play_sfx(_sfx_challenge)
	_show_screen()


func _on_theme_pressed(id: String) -> void:
	if owned.has(id):
		selected = id
		_apply_theme(id)
		_save()
	else:
		var price: int = THEMES[id]["price"]
		if coins_total >= price:
			coins_total -= price
			owned[id] = true
			selected = id
			_apply_theme(id)
			_save()
			_play_sfx(_sfx_purchase)
	_refresh_store()
	queue_redraw()


func _refresh_store() -> void:
	_store_coins.text = "Coins: %d" % coins_total
	for id in THEME_ORDER:
		var b: Button = _theme_buttons[id]
		var t: Dictionary = THEMES[id]
		var label: String = t["name"]
		if not owned.has(id):
			label += "   -   %d coins" % int(t["price"])
		elif selected == id:
			label += "   -   Selected"
		else:
			label += "   -   Owned"
		b.text = label
		b.disabled = selected == id


func _refresh_challenges() -> void:
	for i in range(CHALLENGES.size()):
		var ch: Dictionary = CHALLENGES[i]
		var lbl: Label = _challenge_labels[i]
		var line2 := ""
		if completed.has(ch["id"]):
			line2 = "[DONE]   (+%d coins)" % int(ch["reward"])
		else:
			var val := float(stats.get(ch["stat"], 0.0))
			var goal := float(ch["goal"])
			var pct := clampi(int(val / goal * 100.0), 0, 100)
			line2 = "progress %d%%    reward: %d coins" % [pct, int(ch["reward"])]
		lbl.text = str(ch["desc"]) + "\n" + line2


func _evaluate_challenges() -> Array:
	var done: Array = []
	for ch in CHALLENGES:
		if completed.has(ch["id"]):
			continue
		var val := float(stats.get(ch["stat"], 0.0))
		if val >= float(ch["goal"]):
			completed[ch["id"]] = true
			coins_total += int(ch["reward"])
			done.append(ch)
	return done


# ============================================================
#  INPUT
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_ids[event.index] = true
		else:
			_touch_ids.erase(event.index)


func _input_down() -> bool:
	return not _touch_ids.is_empty() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)


func _steer_down() -> bool:
	var raw := _input_down()
	if not _steer_armed:
		if not raw:
			_steer_armed = true
		return false
	return raw


# ============================================================
#  MAIN LOOP
# ============================================================
func _process(delta: float) -> void:
	if state == State.PLAYING:
		_update_play(delta)
		queue_redraw()
	elif state == State.COUNTDOWN:
		_count_timer -= delta
		if _count_timer <= 0.0:
			state = State.PLAYING
			_steer_armed = false
			_show_screen()
		queue_redraw()
	elif state == State.CRASH:
		_update_crash(delta)
		queue_redraw()


func _update_crash(delta: float) -> void:
	_crash_timer -= delta
	_update_boom(delta)
	_update_particles(delta)
	if _crash_timer <= 0.0:
		_game_over()


func _update_play(delta: float) -> void:
	var down := _steer_down()

	# Tap to begin: the world is frozen until the first hold.
	if not _run_started:
		if down:
			_run_started = true
			_hud_prompt.visible = false
			if _engine_low.stream != null:
				_engine_low.play()
			if _engine_high.stream != null:
				_engine_high.play()
		else:
			camera_x = car_x
			return

	time_alive += delta
	distance += current_speed() * delta
	_update_engine_audio()

	_ensure_track(distance + 1400.0)
	_ensure_branches(distance + 1400.0)
	_ensure_hazards(distance + 1400.0)
	_ensure_coins(distance + 1400.0)
	_ensure_decos(distance + 1400.0)
	_drop_old()

	# camera follows the car (with a little look-ahead toward the upcoming road)
	var look := _nearest_lane_center(distance + CAM_LOOKAHEAD, car_x)
	var cam_target := lerpf(car_x, look, CAM_LOOK_W)
	camera_x = lerpf(camera_x, cam_target, clampf(CAM_FOLLOW * delta, 0.0, 1.0))
	camera_x = clampf(camera_x, car_x - CAM_MAX_OFF, car_x + CAM_MAX_OFF)

	var airborne := _air_timer > 0.0
	if _oil_timer > 0.0:
		_oil_timer -= delta
	if _boost_timer > 0.0:
		_boost_timer -= delta
	if airborne:
		_air_timer -= delta
		if _air_timer <= 0.0:
			# landed a jump: reward + speed boost
			Input.vibrate_handheld(60)
			session_coins += JUMP_COINS
			_boost_timer = BOOST_TIME
			_add_popup(_sx(car_x), CAR_Y - 30.0, "+%d" % JUMP_COINS, true)
			_play_sfx(_sfx_land)

	if airborne:
		car_x += lateral_velocity * delta
	else:
		var steer_accel := STEER_ACCEL
		if _oil_timer > 0.0:
			steer_accel = STEER_ACCEL * OIL_STEER_MULT
		var target := RETURN_SPEED
		if down:
			target = -STEER_SPEED
		lateral_velocity = move_toward(lateral_velocity, target, steer_accel * delta)
		car_x += lateral_velocity * delta

	if _oil_timer > 0.0:
		_tire_marks.append({ "d": distance, "x": car_x - 12.0, "age": 0.0 })
		_tire_marks.append({ "d": distance, "x": car_x + 12.0, "age": 0.0 })

	_emit_exhaust(delta)
	_update_particles(delta)
	_update_boom(delta)        # smash debris from ram-throughs animates during play too
	_update_tire_marks(delta)

	_no_coin_timer += delta
	if _no_coin_timer > _no_coin_best:
		_no_coin_best = _no_coin_timer

	# Ramp boost makes the car unstoppable: it ploughs through blockers/traffic
	# (see _update_hazards) AND rides straight over the off-road, so a fork that
	# peels faster than you can steer at boosted top speed never punishes you. The
	# jump-the-gap hole is the one thing boost can't cheat — you still must ramp it.
	if not airborne and _boost_timer <= 0.0 and not _on_any_lane(distance, car_x):
		_crash()
		return

	_update_hazards(delta, airborne)
	if state != State.PLAYING:
		return

	_update_popups(delta)

	for coin in _coins:
		if coin["got"]:
			continue
		var cd := float(coin["d"])
		var cx := float(coin["x"])
		if absf(cd - distance) < COL_HALF_H + COIN_R and absf(cx - car_x) < COL_HALF_W + COIN_R:
			coin["got"] = true
			session_coins += 1
			_streak += 1
			if _streak > _streak_best:
				_streak_best = _streak
			_no_coin_timer = 0.0
			_add_popup(_sx(cx), CAR_Y - (cd - distance), "+1", true)
			_play_sfx(_sfx_coin)
		elif cd < distance - (COL_HALF_H + COIN_R) and not coin.get("missed", false):
			coin["missed"] = true
			_streak = 0

	score = int(distance / 10.0)
	_hud_score.text = "%.2f KM" % _dist_km()
	_hud_coins.text = "Coins: %d" % session_coins


func _drop_old() -> void:
	while _pt_d.size() > 2 and _pt_d[1] < distance - 500.0:
		_pt_d.remove_at(0)
		_pt_x.remove_at(0)
	# coins can be seeded out of distance-order (branch coins), so scan all
	var ci := _coins.size() - 1
	while ci >= 0:
		if float(_coins[ci]["d"]) < distance - 500.0:
			_coins.remove_at(ci)
		ci -= 1
	var i := _hazards.size() - 1
	while i >= 0:
		# drop hazards once behind, or as soon as they've been smashed by a ram
		if float(_hazards[i]["d"]) < distance - 600.0 or bool(_hazards[i].get("dead", false)):
			_hazards.remove_at(i)
		i -= 1
	# decorations are seeded both sides out of order, so scan all
	var di := _decos.size() - 1
	while di >= 0:
		if float(_decos[di]["d"]) < distance - 600.0:
			_decos.remove_at(di)
		di -= 1
	var bi := _branches.size() - 1
	while bi >= 0:
		if float(_branches[bi]["d1"]) < distance - 700.0:
			_branches.remove_at(bi)
		bi -= 1


# ============================================================
#  HAZARDS (fair: straight sections only, guaranteed gap, sized to road)
# ============================================================
func _ensure_hazards(up_to: float) -> void:
	while _hazard_frontier_d < up_to:
		var tf := _turn_factor()
		_hazard_frontier_d += HAZARD_SPACING * randf_range(0.6, 1.2) * lerpf(1.2, 0.75, tf)
		var d := _hazard_frontier_d
		if d < INTRO_DIST:
			continue
		if _in_branch(d):
			continue   # the fork itself is the challenge here
		# only place where the road is roughly straight, so it's always avoidable
		if absf(road_center(d + 50.0) - road_center(d - 50.0)) > STRAIGHT_DELTA:
			continue
		# jump-the-gap: a hole across the whole road that can only be cleared by
		# launching off a ramp planted ahead of it. Rolled before the ordinary
		# hazards because it claims a long stretch (ramp + hole + landing runway);
		# if there isn't room it falls through to an ordinary hazard at this slot.
		if d >= JUMP_GAP_MIN_DIST and randf() < JUMP_GAP_CHANCE:
			var jf := _spawn_jump_gap(d)
			if jf > 0.0:
				_hazard_frontier_d = jf
				continue
		var bc := road_center(d)
		var bandh := road_half_width(d) - COL_HALF_W
		var roll := randf()
		if roll < 0.20:
			var eff := BLOCK_W * 0.5 + COL_HALF_W
			if 2.0 * bandh >= 2.0 * eff + GAP_MIN:
				_hazards.append({ "d": d, "x": bc + _flush_side(bandh, eff), "type": "block", "lane": 0.0, "ang": 0.0, "hit": false, "scored": false })
		elif roll < 0.58:
			var eff2 := TRAFFIC_W * 0.5 + COL_HALF_W
			if 2.0 * bandh >= 2.0 * eff2 + GAP_MIN:
				var sgn := 1.0
				if randf() < 0.5:
					sgn = -1.0
				var lane := sgn * randf_range(0.24, 0.44)
				_hazards.append({ "d": d, "x": bc + lane * road_half_width(d), "type": "traffic", "lane": lane, "ang": 0.0, "hit": false, "spd": randf_range(TRAFFIC_REL_MIN, TRAFFIC_REL_MAX), "scored": false, "sprite": randi() })
		elif roll < 0.78:
			if bandh >= OIL_R * 0.6 + 30.0:
				var ox := bc + randf_range(-0.35, 0.35) * (bandh - OIL_R * 0.4)
				_hazards.append({ "d": d, "x": ox, "type": "oil", "lane": 0.0, "ang": 0.0, "hit": false })
		else:
			var jx := bc + randf_range(-0.25, 0.25) * (bandh * 0.6)
			_hazards.append({ "d": d, "x": jx, "type": "jump", "lane": 0.0, "ang": 0.0, "hit": false })


# Offset from center that puts the forbidden zone flush against one side,
# leaving a single clean gap (>= GAP_MIN) on the other.
func _flush_side(bandh: float, eff: float) -> float:
	if randf() < 0.5:
		return bandh - eff
	return -(bandh - eff)


# Plant a jump-the-gap set: a full-width ramp at d, a hole spanning the whole road
# just ahead, and a clear runway reserved past it for the landing. The ramp is
# wider than the road, so simply staying on the road guarantees the launch; the
# arc clears the hole even at base speed. Returns the distance the hazard frontier
# should jump to so nothing else spawns in the landing zone, or -1.0 if no room.
func _spawn_jump_gap(d: float) -> float:
	var reserve := JUMP_GAP_AHEAD + JUMP_GAP_RUNWAY
	_ensure_track(d + reserve + 50.0)
	# the whole set (ramp, hole, landing) must sit on plain, branch-free road
	if _in_branch(d) or _in_branch(d + JUMP_GAP_AHEAD) or _in_branch(d + reserve * 0.5) or _in_branch(d + reserve):
		return -1.0
	# you can't steer mid-air, so the landing zone must stay roughly aligned with
	# the launch — only commit the set where the road ahead barely drifts
	if absf(road_center(d + 280.0) - road_center(d)) > 90.0:
		return -1.0
	var hw := road_half_width(d)
	_hazards.append({ "d": d, "x": road_center(d), "type": "jump", "w": 2.0 * (hw - RAMP_GAP_INSET), "h": JUMP_H, "lane": 0.0, "ang": 0.0, "hit": false, "gap_ramp": true })
	var gd := d + JUMP_GAP_AHEAD
	_hazards.append({ "d": gd, "x": road_center(gd), "type": "gap", "len": 2.0 * JUMP_GAP_HALF, "lane": 0.0, "ang": 0.0, "hit": false })
	# keep upcoming branches out of the landing zone as well
	_next_branch_d = maxf(_next_branch_d, d + reserve)
	return d + reserve


# Ploughing through a blocker/car while boosting from a ramp: destroy it, bank
# RAM_COINS, and throw an explosion where it was. The hazard is flagged dead so it
# stops colliding and drawing, then _drop_old clears it.
func _smash_hazard(h: Dictionary) -> void:
	h["dead"] = true
	session_coins += RAM_COINS
	var sxp := _sx(float(h["x"]))
	var syp := CAR_Y - (float(h["d"]) - distance)
	_spawn_explosion(sxp, syp)
	_add_popup(sxp, syp - 24.0, "SMASH! +%d" % RAM_COINS, true, 240.0, true)
	Input.vibrate_handheld(40)
	_play_sfx(_sfx_smash)


func _update_hazards(delta: float, airborne: bool) -> void:
	var ramming := _boost_timer > 0.0
	for h in _hazards:
		if bool(h.get("dead", false)):
			continue
		var htype: String = h["type"]
		if htype == "traffic":
			# closing speed scales with the player's speed (enemies get faster too)
			h["d"] = float(h["d"]) - current_speed() * float(h["spd"]) * delta
			var td := float(h["d"])
			var hwt := road_half_width(td)
			var tgt := road_center(td) + float(h["lane"]) * hwt
			var oldx := float(h["x"])
			var nx := move_toward(oldx, tgt, TRAFFIC_LAT_SPEED * delta)
			# keep it on an actual lane (matters through forks)
			nx = _clamp_to_nearest_lane(td, nx)
			h["x"] = nx
			h["ang"] = clampf((nx - oldx) / maxf(TRAFFIC_LAT_SPEED * delta, 0.001), -1.0, 1.0) * 0.4
		var hd := float(h["d"])
		var hx := float(h["x"])
		var dy := absf(hd - distance)
		var dx := absf(hx - car_x)
		if htype == "block":
			if not airborne and dy < COL_HALF_H + BLOCK_H * 0.5 and dx < COL_HALF_W + BLOCK_W * 0.5:
				if ramming:
					_smash_hazard(h)
					continue
				_crash()
				return
			# near miss: squeezed past a static block without crashing -> reward
			if not h["scored"] and dy < COL_HALF_H + BLOCK_H * 0.5 + 20.0 and dx < NEAR_MISS_DX:
				h["scored"] = true
				session_coins += NEAR_MISS_COINS
				_add_popup(_sx(car_x), CAR_Y - 60.0, "Near Miss! +%d" % NEAR_MISS_COINS, true, 220.0, true)
				_play_sfx(_sfx_near_miss)
		elif htype == "traffic":
			if not airborne and dy < COL_HALF_H + TRAFFIC_H * 0.5 and dx < COL_HALF_W + TRAFFIC_W * 0.5:
				if ramming:
					_smash_hazard(h)
					continue
				_crash()
				return
			# near miss: passed close alongside without crashing -> reward
			if not h["scored"] and dy < COL_HALF_H + 20.0 and dx < NEAR_MISS_DX:
				h["scored"] = true
				session_coins += NEAR_MISS_COINS
				_add_popup(_sx(car_x), CAR_Y - 60.0, "Near Miss! +%d" % NEAR_MISS_COINS, true, 220.0, true)
				_play_sfx(_sfx_near_miss)
			# random oncoming horn while the car is on screen ahead/behind
			var bt: float = float(h.get("beep_t", randf_range(0.8, 2.4))) - delta
			if bt <= 0.0 and dy < 650.0:
				bt = randf_range(1.6, 3.6)
				_play_sfx(_sfx_beep)
			h["beep_t"] = bt
		elif htype == "oil":
			if not h["hit"] and dy < OIL_R and dx < OIL_R:
				h["hit"] = true
				_oil_timer = OIL_TIME
				_play_sfx(_sfx_oil)
		elif htype == "jump":
			var jw: float = float(h.get("w", JUMP_W))
			var jh: float = float(h.get("h", JUMP_H))
			if not h["hit"] and dy < COL_HALF_H + jh * 0.5 and dx < COL_HALF_W + jw * 0.5:
				h["hit"] = true
				_air_timer = AIR_TIME
				_play_sfx(_sfx_jump)
		elif htype == "gap":
			# a hole across the whole road: sail over it airborne, or fall in
			if not airborne and dy < float(h["len"]) * 0.5 + COL_HALF_H:
				_crash()
				return


# ============================================================
#  PARTICLES / TIRE MARKS / EXPLOSION
# ============================================================
func _emit_exhaust(delta: float) -> void:
	_exhaust_accum += delta
	while _exhaust_accum > 0.04:
		_exhaust_accum -= 0.04
		var rear := Vector2(_sx(car_x) + randf_range(-6.0, 6.0), CAR_Y + CAR_HALF_H * 0.7)
		var vel := Vector2(randf_range(-14.0, 14.0), randf_range(36.0, 70.0))
		_particles.append({ "pos": rear, "vel": vel, "age": 0.0, "life": randf_range(0.4, 0.7), "r": randf_range(3.0, 6.0) })


func _update_particles(delta: float) -> void:
	var i := _particles.size() - 1
	while i >= 0:
		var p = _particles[i]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= float(p["life"]):
			_particles.remove_at(i)
		else:
			var pos: Vector2 = p["pos"]
			var vel: Vector2 = p["vel"]
			p["pos"] = pos + vel * delta
			p["vel"] = vel * (1.0 - 1.4 * delta)
		i -= 1


func _spawn_explosion(sx_pos: float, sy_pos: float) -> void:
	var cols := [Color("ffd54a"), Color("ff8c1a"), Color("e74c3c"), Color("ffffff")]
	for n in range(34):
		var a := randf() * TAU
		var sp := randf_range(70.0, 340.0)
		_boom.append({
			"pos": Vector2(sx_pos, sy_pos),
			"vel": Vector2(cos(a), sin(a)) * sp,
			"age": 0.0, "life": randf_range(0.4, 0.95),
			"r": randf_range(4.0, 11.0),
			"col": cols[randi() % cols.size()],
		})


func _update_boom(delta: float) -> void:
	var i := _boom.size() - 1
	while i >= 0:
		var b = _boom[i]
		b["age"] = float(b["age"]) + delta
		if float(b["age"]) >= float(b["life"]):
			_boom.remove_at(i)
		else:
			var pos: Vector2 = b["pos"]
			var vel: Vector2 = b["vel"]
			b["pos"] = pos + vel * delta
			b["vel"] = vel * (1.0 - 2.2 * delta)
		i -= 1


func _update_tire_marks(delta: float) -> void:
	var i := _tire_marks.size() - 1
	while i >= 0:
		var m = _tire_marks[i]
		m["age"] = float(m["age"]) + delta
		if float(m["age"]) > TIRE_LIFE or float(m["d"]) < distance - 700.0:
			_tire_marks.remove_at(i)
		i -= 1


func _add_popup(sx_pos: float, sy_pos: float, text: String, coin: bool, width: float = 160.0, inline: bool = false) -> void:
	_popups.append({ "pos": Vector2(sx_pos, sy_pos), "text": text, "age": 0.0, "coin": coin, "width": width, "inline": inline })


func _update_popups(delta: float) -> void:
	var i := _popups.size() - 1
	while i >= 0:
		var p = _popups[i]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= POPUP_LIFE:
			_popups.remove_at(i)
		else:
			var pos: Vector2 = p["pos"]
			p["pos"] = Vector2(pos.x, pos.y - POPUP_RISE * delta)
		i -= 1


# ============================================================
#  DIFFICULTY
# ============================================================
func _ramp_speed() -> float:
	return minf(BASE_SPEED + time_alive * SPEED_PER_SEC, MAX_SPEED)


# 0 normally, rising toward 1 inside a "breather" stretch.
func _breather(d: float) -> float:
	return maxf(0.0, sin(d * RHYTHM_FREQ))


func current_speed() -> float:
	var s := _ramp_speed()
	if _boost_timer > 0.0:
		s *= BOOST_MULT
	return s


func _dist_km() -> float:
	return distance / PX_PER_METER / 1000.0


# Width is a function of distance: it narrows as you travel (difficulty), with
# periodic breather bulges layered on top (rhythm). Same value when you reach a
# given point, so hazards placed there stay fair.
func road_half_width(d: float) -> float:
	var base := clampf(START_HALF_WIDTH - d * NARROW_PER_DIST, MIN_HALF_WIDTH, START_HALF_WIDTH)
	return base + _breather(d) * RHYTHM_WIDTH_AMP


func _turn_factor() -> float:
	return clampf(time_alive / RAMP_SECONDS, 0.0, 1.0)


# ============================================================
#  TRACK (unbounded world; intro straight; drift; slope-capped turns)
# ============================================================
func _reset_track() -> void:
	_pt_d = PackedFloat32Array()
	_pt_x = PackedFloat32Array()
	_pt_d.append(-800.0)
	_pt_x.append(ROAD_CENTER_X)
	_pt_d.append(0.0)
	_pt_x.append(ROAD_CENTER_X)
	_track_frontier_d = 0.0
	_track_last_x = ROAD_CENTER_X
	_pattern_queue.clear()


func _push_point(seg_len: float, target_x: float) -> void:
	_track_frontier_d += seg_len
	_pt_d.append(_track_frontier_d)
	_pt_x.append(target_x)
	_track_last_x = target_x


func _slope_cap() -> float:
	return lerpf(0.45, 0.85, _turn_factor())


func _maybe_seed_pattern() -> void:
	if randf() < 0.5:
		return
	var base := _track_last_x
	var amp_scale := lerpf(0.6, 1.0, _turn_factor())
	var r := randf()
	if r < 0.35:
		var a := randf_range(170.0, 250.0) * amp_scale       # zigzag
		_pattern_queue.append({ "x": base + a })
		_pattern_queue.append({ "x": base - a })
		_pattern_queue.append({ "x": base + a })
		_pattern_queue.append({ "x": base - a })
	elif r < 0.65:
		var m := randf_range(140.0, 210.0) * amp_scale       # chicane
		_pattern_queue.append({ "x": base + m })
		_pattern_queue.append({ "x": base - m })
		_pattern_queue.append({ "x": base })
	elif r < 0.85:
		var dir := 1.0                                        # hairpin
		if randf() < 0.5:
			dir = -1.0
		var ex := base + dir * 340.0 * amp_scale
		_pattern_queue.append({ "x": ex })
		_pattern_queue.append({ "x": ex })
		_pattern_queue.append({ "x": base })
	else:
		var dir2 := 1.0                                       # long sweep
		if randf() < 0.5:
			dir2 = -1.0
		_pattern_queue.append({ "x": base + dir2 * 260.0 * amp_scale })


func _ensure_track(up_to: float) -> void:
	while _track_frontier_d < up_to:
		# intro: dead-straight, no patterns, hazard-free (set elsewhere)
		if _track_frontier_d < INTRO_DIST:
			_push_point(200.0, ROAD_CENTER_X)
			continue

		var tf := _turn_factor()
		var target := _track_last_x
		if _pattern_queue.is_empty():
			_maybe_seed_pattern()

		if _pattern_queue.is_empty():
			# drift gives the road momentum so it travels somewhere
			_bias = clampf(_bias * 0.92 + randf_range(-26.0, 26.0), -140.0, 140.0)
			var mag := randf_range(70.0, lerpf(150.0, 240.0, tf))
			var dir := 1.0
			if randf() < 0.5:
				dir = -1.0
			target = _track_last_x + _bias + dir * mag
		else:
			var mv: Dictionary = _pattern_queue.pop_front()
			target = float(mv["x"])

		# slope cap: make the segment long enough that the turn isn't pinched
		# and you have time to steer into it
		var move := absf(target - _track_last_x)
		var seg_len := maxf(lerpf(220.0, 150.0, tf), move / _slope_cap())
		_push_point(seg_len * randf_range(0.95, 1.1), target)


func road_center(d: float) -> float:
	var n := _pt_d.size()
	if n == 0:
		return ROAD_CENTER_X
	if d <= _pt_d[0]:
		return _pt_x[0]
	if d >= _pt_d[n - 1]:
		return _pt_x[n - 1]
	for i in range(n - 1):
		if d <= _pt_d[i + 1]:
			var t := (d - _pt_d[i]) / (_pt_d[i + 1] - _pt_d[i])
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(_pt_x[i], _pt_x[i + 1], t)
	return _pt_x[n - 1]


# ============================================================
#  FORKS (two lanes around a median, layered on the centerline)
# ============================================================
# road_lanes() is the multi-lane view the rest of the game queries. Normally it
# returns one lane twice (the plain road); inside a branch it returns the two
# split lanes. road_center()/road_half_width() stay the single continuous
# centerline the branches ride on.
func road_lanes(d: float) -> Array[Dictionary]:
	var fullhw := road_half_width(d)
	var b := _branch_at(d)
	if b.is_empty():
		var c := road_center(d)
		return [{ "c": c, "hw": fullhw }, { "c": c, "hw": fullhw }]
	# lane0 is always the LEFT lane and lane1 the RIGHT lane, so the two-lane road
	# drawing (outer edges + median between them) keeps working for every style.
	var axis := _branch_axis(b, d)                     # straightened reference line
	return [_lane_geom(b, b["lane0"], d, axis, fullhw), _lane_geom(b, b["lane1"], d, axis, fullhw)]


# Geometry {c, hw} of one branch lane at distance d. Each lane carries its own
# split schedule (t0..t1 + ramp) and shape, which is what lets a single branch be
# a clean symmetric fork, a lopsided fork, or a one-sided bailout shoulder.
func _lane_geom(b: Dictionary, lane: Dictionary, d: float, axis: float, fullhw: float) -> Dictionary:
	# the full-width through lane of a bailout shoulder rides the road unchanged
	if lane.get("main", false):
		return { "c": axis, "hw": fullhw }
	var span := float(b["d1"]) - float(b["d0"])
	var t := (d - float(b["d0"])) / maxf(span, 1.0)
	var t0 := float(lane["t0"])
	var t1 := float(lane["t1"])
	var u := clampf((t - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
	var a := _branch_arch_ramped(u, float(lane["ramp"]))
	var side := float(lane["side"])
	if lane.get("shoulder", false):
		# starts as the road's OUTER STRIP (a=0, overlapping the road so it's
		# reachable from it) and translates outward to a bulge beyond the edge
		# (a=1), at constant width — so the coin lane is always drivable and the
		# road's outer boundary simply bulges out and back around it.
		var sh := float(lane["hw"])
		var reach := (fullhw - sh) + (float(lane["bulge"]) + sh) * a
		return { "c": axis + side * reach, "hw": sh }
	# fork lane: peels off the axis; widen-from-the-inside keeps the outer edge put
	# (axis ± fullhw) while the median opens, so edges never retreat into the car.
	var sep := a * float(lane["off"])
	return { "c": axis + side * sep, "hw": maxf(float(lane["hw"]), fullhw - sep) }


# The local reference line the branch's lanes ride on: it blends from the actual
# (possibly curving) centerline at the merge points to a straight chord across
# the middle, in step with how far the lanes have separated — so a thin split
# lane is never dragged sideways by a bend in the underlying road. A gentle wave
# is layered on so forks wind instead of running dead-straight (both lanes ride
# the same axis, so the median stays intact and the wander reads as one curve).
func _branch_axis(b: Dictionary, d: float) -> float:
	var d0 := float(b["d0"])
	var t := (d - d0) / (float(b["d1"]) - d0)
	var chord := lerpf(float(b["cx0"]), float(b["cx1"]), t)
	var frac := clampf(_branch_sep(b, d) / maxf(float(b["off"]), 1.0), 0.0, 1.0)
	return lerpf(road_center(d), chord, frac) + _branch_wave(b, d)


# Sideways wander added across a fork, faded to zero at both merges (via the same
# arch the split uses) so the entry/exit stay seamless. Amplitude/wavelength are
# capped at fork-build time to keep a lane trackable even stacked on the peel.
func _branch_wave(b: Dictionary, d: float) -> float:
	var amp := float(b.get("wave_amp", 0.0))
	if amp == 0.0:
		return 0.0
	var d0 := float(b["d0"])
	var env := _branch_arch((d - d0) / (float(b["d1"]) - d0))
	return sin((d - d0) / float(b["wave_len"]) * TAU + float(b["wave_phase"])) * amp * env


# Lane-center offset from the axis at distance d: the smoothstep arch ramps the
# lanes out to a flat parallel split across the middle, then back together.
func _branch_sep(b: Dictionary, d: float) -> float:
	var t := (d - float(b["d0"])) / (float(b["d1"]) - float(b["d0"]))
	return _branch_arch(t) * float(b["off"])


func _branch_at(d: float) -> Dictionary:
	for b in _branches:
		if d >= float(b["d0"]) and d <= float(b["d1"]):
			return b
	return {}


# Separation profile: 0 at the ends (lanes merged into the centerline), ramping
# smoothly to 1 across the middle (lanes fully split). This is what makes a fork
# open out of, and close back into, a single road seamlessly.
func _branch_arch(t: float) -> float:
	return _branch_arch_ramped(t, BRANCH_RAMP)


# Same 0→1→0 profile as _branch_arch but with a caller-supplied ramp fraction, so
# each lane can open and close at its own pace (the source of varied fork shapes).
func _branch_arch_ramped(t: float, ramp: float) -> float:
	if t <= 0.0 or t >= 1.0:
		return 0.0
	var r := clampf(ramp, 0.05, 0.5)
	if t < r:
		return smoothstep(0.0, 1.0, t / r)
	if t > 1.0 - r:
		return smoothstep(0.0, 1.0, (1.0 - t) / r)
	return 1.0


# True anywhere inside a branch feature (entry/exit ramps included). Standard
# hazards and coins stay out of the whole thing — they'd be placed against the
# single centerline, which is wrong once the lanes start separating — so the
# fork stays its own clean navigation test.
func _in_branch(d: float) -> bool:
	return not _branch_at(d).is_empty()


func _on_any_lane(d: float, x: float) -> bool:
	for lane in road_lanes(d):
		if absf(x - float(lane["c"])) <= float(lane["hw"]) - COL_HALF_W:
			return true
	return false


func _nearest_lane_center(d: float, x: float) -> float:
	var lanes := road_lanes(d)
	var best := float(lanes[0]["c"])
	for lane in lanes:
		if absf(x - float(lane["c"])) < absf(x - best):
			best = float(lane["c"])
	return best


func _clamp_to_nearest_lane(d: float, x: float) -> float:
	var lanes := road_lanes(d)
	var best: Dictionary = lanes[0]
	for lane in lanes:
		if absf(x - float(lane["c"])) < absf(x - float(best["c"])):
			best = lane
	var m := float(best["hw"]) - COL_HALF_W
	return clampf(x, float(best["c"]) - m, float(best["c"]) + m)


func _ensure_branches(up_to: float) -> void:
	# scan forward in small steps; once we're past the spacing gate, drop a branch
	# at the first stretch straight enough to make committing to a lane fair
	while _branch_frontier_d < up_to:
		_branch_frontier_d += 200.0
		var d0 := _branch_frontier_d
		if d0 < _next_branch_d:
			continue
		_ensure_track(d0 + 250.0)
		if absf(road_center(d0 + 150.0) - road_center(d0 - 150.0)) > BRANCH_STRAIGHT_DELTA:
			continue
		# geometry scales with the road's current width, so branches keep pace with
		# the narrowing road instead of being a fixed (and eventually oversized) size.
		# Style is rolled per branch so the forks vary instead of all reading the same.
		var rhw := road_half_width(d0)
		var b := _make_shoulder(d0, rhw) if randf() < SHOULDER_CHANCE else _make_fork(d0, rhw)
		var d1 := float(b["d1"])
		_ensure_track(d1 + 200.0)
		# the branch rides a straight chord, so only the road's NET drift across it
		# matters — skip spots where that drift would make the chord too steep
		if absf(road_center(d1) - road_center(d0)) > BRANCH_MAX_DRIFT:
			continue
		b["cx0"] = road_center(d0)
		b["cx1"] = road_center(d1)
		_branches.append(b)
		_seed_branch_coins(b)
		_seed_fork_hazards(b)
		_next_branch_d = d1 + BRANCH_SPACING * randf_range(0.85, 1.25)


# A two-lane fork around a median. The two lanes are described INDEPENDENTLY, so a
# fork can be a clean mirror split or lopsided (a fat lane beside a thin one), and
# its length is stretched past the sweep-cap minimum by a random factor — so no
# two forks peel apart the same way or for the same distance.
func _make_fork(d0: float, rhw: float) -> Dictionary:
	var asym := randf() < FORK_ASYM_CHANCE
	var base_hw := clampf(rhw * LANE_FRAC, LANE_HW_MIN, rhw - 6.0)
	var base_med := rhw * FORK_MEDIAN_FRAC
	# per-lane jitter (a symmetric fork keeps both sides equal; a lopsided one does
	# not). Each lane's separation is its own width PLUS a jittered median, so the
	# grass gap between the lanes is always positive however the sides are jittered.
	var hw_l := clampf(base_hw * (1.0 + (randf_range(-FORK_HW_VARY, FORK_HW_VARY) if asym else 0.0)), LANE_HW_MIN, rhw - 6.0)
	var hw_r := clampf(base_hw * (1.0 + (randf_range(-FORK_HW_VARY, FORK_HW_VARY) if asym else 0.0)), LANE_HW_MIN, rhw - 6.0)
	var med_l := maxf(base_med * (1.0 + (randf_range(-FORK_OFF_VARY, FORK_OFF_VARY) if asym else 0.0)), 8.0)
	var med_r := maxf(base_med * (1.0 + (randf_range(-FORK_OFF_VARY, FORK_OFF_VARY) if asym else 0.0)), 8.0)
	var off_l := hw_l + med_l
	var off_r := hw_r + med_r
	var ramp_l := BRANCH_RAMP * (1.0 + (randf_range(-FORK_RAMP_VARY, FORK_RAMP_VARY) if asym else 0.0))
	var ramp_r := BRANCH_RAMP * (1.0 + (randf_range(-FORK_RAMP_VARY, FORK_RAMP_VARY) if asym else 0.0))
	# length: keep even the widest, fastest-peeling lane within the sweep cap, then
	# stretch it by a random factor (longer only ever peels more gently — still fair)
	var max_off := maxf(off_l, off_r)
	var min_ramp := clampf(minf(ramp_l, ramp_r), 0.05, 0.5)
	var min_len := maxf(FORK_LEN_MIN, max_off * 1.5 * MAX_SPEED * BOOST_MULT / (min_ramp * FORK_SWEEP_CAP))
	var fork_len := min_len * randf_range(1.0, FORK_LEN_VARY_MAX)
	# gentle wind: amplitude is held under what the player can still track once it is
	# stacked on the split peel (verified in the fairness harness)
	var wave_amp := 0.0
	var wave_phase := 0.0
	if randf() < FORK_WAVE_CHANCE:
		wave_amp = FORK_WAVE_AMP * randf_range(0.55, 1.0)
		wave_phase = randf() * TAU
	return {
		"kind": "fork",
		"d0": d0, "d1": d0 + fork_len, "off": max_off,
		"wave_amp": wave_amp, "wave_len": FORK_WAVE_LEN * randf_range(0.8, 1.3), "wave_phase": wave_phase,
		"lane0": { "side": -1.0, "off": off_l, "hw": hw_l, "t0": 0.0, "t1": 1.0, "ramp": ramp_l },
		"lane1": { "side": 1.0, "off": off_r, "hw": hw_r, "t0": 0.0, "t1": 1.0, "ramp": ramp_r },
		"coin_lane": 1 if randf() < 0.5 else 0,
	}


# A bailout shoulder: the main road stays full width (the through lane) while a
# narrower coin lane sprouts from ONE shoulder, bulges out past the road edge
# around a grass median, and rejoins. It's an optional reward detour, not a
# commit-to-a-lane fork, so the safe line is always available.
func _make_shoulder(d0: float, rhw: float) -> Dictionary:
	var sh_hw := maxf(SHOULDER_HW_MIN, rhw * SHOULDER_HW_FRAC)
	var bulge := maxf(SHOULDER_BULGE_MIN, rhw * SHOULDER_BULGE_FRAC)
	var sh_len := SHOULDER_LEN_MIN * randf_range(1.0, 1.0 + SHOULDER_LEN_VARY)
	# keep the shoulder's sideways speed within the sweep cap (it travels the full
	# bulge + its own width as it moves from the road's edge out to the bulge)
	sh_len = maxf(sh_len, (bulge + sh_hw) * 1.5 * MAX_SPEED * BOOST_MULT / (SHOULDER_RAMP * FORK_SWEEP_CAP))
	var right := randf() < 0.5
	var shoulder_lane := { "shoulder": true, "side": (1.0 if right else -1.0), "hw": sh_hw, "bulge": bulge, "t0": 0.0, "t1": 1.0, "ramp": SHOULDER_RAMP }
	var main_lane := { "main": true }
	var b := { "kind": "shoulder", "d0": d0, "d1": d0 + sh_len, "off": bulge }
	# keep lane0 LEFT / lane1 RIGHT so the road drawing stays correct
	if right:
		b["lane0"] = main_lane
		b["lane1"] = shoulder_lane
		b["coin_lane"] = 1
	else:
		b["lane0"] = shoulder_lane
		b["lane1"] = main_lane
		b["coin_lane"] = 0
	return b


# Line the branch's coin lane with coins — the payoff for leaving the safe line:
# the scenic side of a fork, or out along the bulge of a bailout shoulder.
func _seed_branch_coins(b: Dictionary) -> void:
	var lane: Dictionary = b["lane0"] if int(b["coin_lane"]) == 0 else b["lane1"]
	if lane.get("main", false):
		return
	var d0 := float(b["d0"])
	var d1 := float(b["d1"])
	var n: int = SHOULDER_COINS if String(b.get("kind", "fork")) == "shoulder" else BRANCH_COINS
	var t0 := float(lane["t0"])
	var t1 := float(lane["t1"])
	for k in range(n):
		# spread across the lane's active window, where it has actually peeled out
		var f := lerpf(0.28, 0.72, float(k) / float(maxi(n - 1, 1)))
		var dd := lerpf(d0, d1, lerpf(t0, t1, f))
		var axis := _branch_axis(b, dd)
		var g := _lane_geom(b, lane, dd, axis, road_half_width(dd))
		_coins.append({ "d": dd, "x": float(g["c"]), "got": false, "missed": false })


# Scatter OIL slicks down a fork's lanes so committing to a side is a real test,
# not a straight cruise. Oil only makes you slip (never blocks), so whichever lane
# you pick is always passable — the fork stays fair while feeling alive.
func _seed_fork_hazards(b: Dictionary) -> void:
	if String(b.get("kind", "")) != "fork":
		return
	if randf() > FORK_OIL_CHANCE:
		return
	var d0 := float(b["d0"])
	var d1 := float(b["d1"])
	for k in range(randi_range(1, FORK_OIL_MAX)):
		var lane: Dictionary = b["lane%d" % (randi() % 2)]
		var dd := lerpf(d0, d1, randf_range(0.28, 0.72))
		var g := _lane_geom(b, lane, dd, _branch_axis(b, dd), road_half_width(dd))
		# nudge within the lane so the slick isn't always dead-centre
		var nudge := randf_range(-0.4, 0.4) * maxf(float(g["hw"]) - OIL_R * 0.5, 0.0)
		_hazards.append({ "d": dd, "x": float(g["c"]) + nudge, "type": "oil", "lane": 0.0, "ang": 0.0, "hit": false, "in_fork": true })


func distance_at_row(y: float) -> float:
	return distance + (CAR_Y - y)


func _sx(wx: float) -> float:
	return wx - camera_x + SCREEN_W * 0.5


# ============================================================
#  COINS
# ============================================================
func _ensure_coins(up_to: float) -> void:
	while _coin_frontier_d < up_to:
		_coin_frontier_d += COIN_SPACING * randf_range(0.8, 1.4)
		if _coin_frontier_d < INTRO_DIST * 0.5:
			continue
		var d := _coin_frontier_d
		if _in_branch(d):
			continue   # branches seed their own coins along the scenic lane
		var bc := road_center(d)
		# reach is reduced on curves (where the road shifts across the coin's height)
		var slope := absf(road_center(d + 30.0) - road_center(d - 30.0)) / 60.0
		var curve_fade := clampf(1.0 - slope, 0.45, 1.0)
		var reach := (road_half_width(d) - COL_HALF_W - COIN_R) * 0.8 * curve_fade
		var cx := bc + randf_range(-1.0, 1.0) * maxf(reach, 0.0)
		if _coin_blocked(d, cx):
			var alt := bc - (cx - bc)
			if not _coin_blocked(d, alt):
				cx = alt
			else:
				continue   # no clean spot here; skip rather than place an unfair coin
		_coins.append({ "d": d, "x": cx, "got": false, "missed": false })


# True if a coin at (d, x) would sit on/inside a stationary hazard's footprint
# (block/oil/jump). Traffic is excluded: it moves, so grabbing a coin near a
# lane it might pass through is normal risk/reward, not an unfair placement.
func _coin_blocked(d: float, x: float) -> bool:
	for h in _hazards:
		var htype: String = h["type"]
		var half_w: float
		var half_h: float
		if htype == "block":
			half_w = BLOCK_W * 0.5
			half_h = BLOCK_H * 0.5
		elif htype == "oil":
			half_w = OIL_R
			half_h = OIL_R
		elif htype == "jump":
			half_w = float(h.get("w", JUMP_W)) * 0.5
			half_h = float(h.get("h", JUMP_H)) * 0.5
		elif htype == "gap":
			# the hole spans the whole road, so block any coin within its length
			half_w = road_half_width(d) + COIN_R
			half_h = float(h["len"]) * 0.5
		else:
			continue
		if absf(float(h["d"]) - d) < half_h + COIN_R and absf(float(h["x"]) - x) < half_w + COIN_R:
			return true
	return false


# ============================================================
#  BACKGROUND DECORATIONS (cosmetic props in the off-road, both sides)
# ============================================================
# Each prop carries a stable variant index + scale so the art pipeline can later
# swap it for a per-theme sprite (res://art/<theme>/deco_<variant>.png); until
# then they draw as simple themed primitives. They never touch the road.
func _ensure_decos(up_to: float) -> void:
	while _deco_frontier_d < up_to:
		_deco_frontier_d += DECO_SPACING * randf_range(0.55, 1.45)
		var base_d := _deco_frontier_d
		_ensure_track(base_d + 60.0)
		for sgn in [-1.0, 1.0]:
			if randf() < 0.45:
				continue   # leave gaps so the off-road isn't a solid wall of props
			var side := float(sgn)
			var d := base_d + randf_range(-DECO_SPACING * 0.4, DECO_SPACING * 0.4)
			var edge := road_center(d) + side * (road_half_width(d) + DECO_MARGIN)
			_decos.append({
				"d": d,
				"x": edge + side * randf_range(0.0, DECO_BAND),
				"side": side,
				"variant": randi() % DECO_VARIANTS,
				"scale": randf_range(0.8, 1.5),
			})


# Primitive stand-in for a decoration sprite. Variants read as a tree, a rock and
# a marker post — placeholders sized/keyed so per-theme sprites can drop straight in.
func _draw_deco_primitive(pos: Vector2, variant: int, s: float) -> void:
	match variant:
		0:   # tree: trunk + canopy
			draw_rect(Rect2(pos.x - 3.0 * s, pos.y - 6.0 * s, 6.0 * s, 16.0 * s), col_deco.darkened(0.25))
			draw_circle(pos + Vector2(0, -16.0 * s), 14.0 * s, col_deco)
			draw_circle(pos + Vector2(-7.0 * s, -10.0 * s), 9.0 * s, col_deco)
			draw_circle(pos + Vector2(7.0 * s, -10.0 * s), 9.0 * s, col_deco)
		1:   # rock: chunky polygon
			var r := PackedVector2Array([
				pos + Vector2(-14.0 * s, 6.0 * s), pos + Vector2(-9.0 * s, -9.0 * s),
				pos + Vector2(5.0 * s, -12.0 * s), pos + Vector2(15.0 * s, -2.0 * s),
				pos + Vector2(11.0 * s, 7.0 * s),
			])
			draw_colored_polygon(r, col_deco)
			draw_line(pos + Vector2(-9.0 * s, -9.0 * s), pos + Vector2(2.0 * s, 2.0 * s), col_deco.darkened(0.3), 2.0)
		_:   # marker post
			draw_rect(Rect2(pos.x - 3.0 * s, pos.y - 22.0 * s, 6.0 * s, 28.0 * s), col_deco)
			draw_circle(pos + Vector2(0, -22.0 * s), 5.0 * s, col_edge)


# ============================================================
#  DRAWING
# ============================================================
func _car_angle() -> float:
	return clampf(lateral_velocity / STEER_SPEED, -1.0, 1.0) * MAX_TILT


# Speed gauge: a swept dial (gap at the bottom) with a redline zone, tick
# marks, and a needle, drawn in fixed screen space like the other HUD overlays.
func _draw_speedometer() -> void:
	var kmh := current_speed() / PX_PER_METER * 3.6
	var span := GAUGE_MAX_KMH - GAUGE_MIN_KMH
	var frac := clampf((kmh - GAUGE_MIN_KMH) / span, 0.0, 1.0)
	var redline_frac := clampf((MAX_SPEED / PX_PER_METER * 3.6 - GAUGE_MIN_KMH) / span, 0.0, 1.0)
	var start_rad := deg_to_rad(GAUGE_START_DEG)
	var end_rad := deg_to_rad(GAUGE_END_DEG)

	# colour grades green -> yellow -> red as the dial fills; locks to the state
	# colours at the top end so MAX/BOOST read at a glance
	var fill_col := Color(0.25, 0.9, 0.45).lerp(Color(1.0, 0.82, 0.2), clampf(frac * 1.6, 0.0, 1.0))
	fill_col = fill_col.lerp(Color(1.0, 0.32, 0.26), clampf((frac - 0.55) * 2.2, 0.0, 1.0))
	var hot := false
	if _boost_timer > 0.0:
		fill_col = COL_BOOST
		hot = true
	elif _ramp_speed() >= MAX_SPEED - 0.5:
		fill_col = COL_SPEED_MAX
		hot = true

	# a tiny needle vibration at the top end makes the gauge feel alive
	var jitter := 0.0
	if hot:
		jitter = sin(time_alive * 42.0) * 0.013
	var needle_rad := deg_to_rad(lerpf(GAUGE_START_DEG, GAUGE_END_DEG, frac)) + jitter

	# backing dial + redline zone
	draw_circle(GAUGE_CENTER, GAUGE_R + 14.0, COL_GAUGE_BG)
	draw_arc(GAUGE_CENTER, GAUGE_R, start_rad, end_rad, 48, COL_GAUGE_RING, 8.0, true)
	var redline_rad := deg_to_rad(lerpf(GAUGE_START_DEG, GAUGE_END_DEG, redline_frac))
	draw_arc(GAUGE_CENTER, GAUGE_R, redline_rad, end_rad, 16, COL_GAUGE_REDZONE, 8.0, true)

	# filled progress arc — this is the part that visibly sweeps up with speed
	if hot:
		var pulse := 0.5 + 0.5 * sin(time_alive * 16.0)
		var glow := fill_col
		glow.a = 0.22 + 0.22 * pulse
		draw_arc(GAUGE_CENTER, GAUGE_R, start_rad, needle_rad, 40, glow, 17.0, true)
	if needle_rad > start_rad + 0.01:
		draw_arc(GAUGE_CENTER, GAUGE_R, start_rad, needle_rad, 40, fill_col, 9.0, true)

	for i in range(7):
		var t := i / 6.0
		var rad := deg_to_rad(lerpf(GAUGE_START_DEG, GAUGE_END_DEG, t))
		var dir := Vector2(cos(rad), sin(rad))
		draw_line(GAUGE_CENTER + dir * (GAUGE_R - 6.0), GAUGE_CENTER + dir * (GAUGE_R + 8.0), COL_GAUGE_TICK, 3.0)

	# needle (counter-weighted) + hub
	var ndir := Vector2(cos(needle_rad), sin(needle_rad))
	draw_line(GAUGE_CENTER - ndir * 11.0, GAUGE_CENTER + ndir * (GAUGE_R - 14.0), fill_col, 5.0, true)
	draw_circle(GAUGE_CENTER, 10.0, fill_col)
	draw_circle(GAUGE_CENTER, 5.0, Color(0, 0, 0, 0.6))

	if _ui_font != null:
		draw_string(_ui_font, GAUGE_CENTER + Vector2(-54, GAUGE_R + 30.0), "%d" % int(kmh), HORIZONTAL_ALIGNMENT_CENTER, 108, 38, fill_col)
		draw_string(_ui_font, GAUGE_CENTER + Vector2(-54, GAUGE_R + 58.0), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 108, 16, Color(1, 1, 1, 0.55))


func _draw() -> void:
	_draw_background()
	_draw_parallax()
	_draw_decos()        # off-road props sit behind the road surface
	_draw_road()

	var in_game := state == State.PLAYING or state == State.CRASH or state == State.GAME_OVER or state == State.COUNTDOWN
	if not in_game:
		return

	for m in _tire_marks:
		var my := CAR_Y - (float(m["d"]) - distance)
		var a := 1.0 - float(m["age"]) / TIRE_LIFE
		if a > 0.0:
			var tc := COL_TIRE
			tc.a = 0.5 * a
			draw_rect(Rect2(_sx(float(m["x"])) - 3.0, my - 4.0, 6.0, 8.0), tc)

	for h in _hazards:
		if bool(h.get("dead", false)):
			continue
		var hd := float(h["d"])
		var hy := CAR_Y - (hd - distance)
		if hy < -160.0 or hy > SCREEN_H + 160.0:
			continue
		var hx := _sx(float(h["x"]))
		var ht: String = h["type"]
		if ht == "oil":
			draw_circle(Vector2(hx, hy), OIL_R, COL_OIL)
			draw_circle(Vector2(hx - OIL_R * 0.3, hy - OIL_R * 0.3), OIL_R * 0.35, COL_OIL_HI)
		elif ht == "block":
			draw_rect(Rect2(hx - BLOCK_W * 0.5, hy - BLOCK_H * 0.5, BLOCK_W, BLOCK_H), COL_BLOCK)
			for k in range(3):
				draw_rect(Rect2(hx - BLOCK_W * 0.5 + 4.0 + k * 20.0, hy - BLOCK_H * 0.5, 9.0, BLOCK_H), COL_BLOCK_DARK)
		elif ht == "traffic":
			draw_set_transform(Vector2(hx, hy), float(h["ang"]), Vector2.ONE)
			if _tex_enemy.size() > 0:
				var et: Texture2D = _tex_enemy[int(h.get("sprite", 0)) % _tex_enemy.size()]
				draw_texture_rect(et, Rect2(-TRAFFIC_W * 0.5, -TRAFFIC_H * 0.5, TRAFFIC_W, TRAFFIC_H), false)
			else:
				draw_rect(Rect2(-TRAFFIC_W * 0.5, -TRAFFIC_H * 0.5, TRAFFIC_W, TRAFFIC_H), COL_TRAFFIC)
				draw_rect(Rect2(-TRAFFIC_W * 0.5 + 8.0, TRAFFIC_H * 0.5 - 48.0, TRAFFIC_W - 16.0, 30.0), COL_TRAFFIC_DARK)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif ht == "jump":
			var jw: float = float(h.get("w", JUMP_W))
			var jh: float = float(h.get("h", JUMP_H))
			var ramp := PackedVector2Array()
			ramp.append(Vector2(hx - jw * 0.5, hy + jh * 0.5))
			ramp.append(Vector2(hx + jw * 0.5, hy + jh * 0.5))
			ramp.append(Vector2(hx + jw * 0.35, hy - jh * 0.5))
			ramp.append(Vector2(hx - jw * 0.35, hy - jh * 0.5))
			draw_colored_polygon(ramp, COL_JUMP)
			# launch chevrons across the ramp (a wide gap ramp gets several)
			var chev := maxi(1, int(jw / 70.0))
			for c in range(chev):
				var cxr := hx - jw * 0.5 + jw * (float(c) + 0.5) / float(chev)
				draw_line(Vector2(cxr - 24.0, hy + 10.0), Vector2(cxr, hy - 12.0), COL_JUMP_HI, 4.0)
				draw_line(Vector2(cxr + 24.0, hy + 10.0), Vector2(cxr, hy - 12.0), COL_JUMP_HI, 4.0)
		elif ht == "gap":
			_draw_gap(h, hd)

	for coin in _coins:
		if coin["got"]:
			continue
		var cy := CAR_Y - (float(coin["d"]) - distance)
		if cy > -COIN_R and cy < SCREEN_H + COIN_R:
			var cx := _sx(float(coin["x"]))
			draw_circle(Vector2(cx, cy), COIN_R, COL_COIN)
			draw_circle(Vector2(cx, cy), COIN_R * 0.55, COL_COIN_HI)

	for pp in _particles:
		var life := float(pp["life"])
		var rem := 1.0 - float(pp["age"]) / life
		if rem > 0.0:
			var ec := COL_EXHAUST
			ec.a = rem * 0.35
			var ppos: Vector2 = pp["pos"]
			draw_circle(ppos, float(pp["r"]) * (0.6 + rem * 0.6), ec)

	# car (hidden once it has exploded; shown frozen during the resume countdown)
	if state == State.PLAYING or state == State.COUNTDOWN:
		# boost glow
		if _boost_timer > 0.0:
			var pulse := 0.6 + 0.4 * sin(time_alive * 18.0)
			var gcol := COL_BOOST
			gcol.a = 0.35 * pulse
			draw_circle(Vector2(_sx(car_x), CAR_Y), CAR_W * (0.95 + 0.12 * pulse), gcol)
		var ang := _car_angle()
		var lift := 0.0
		var sc := 1.0
		if _air_timer > 0.0:
			var phase := 1.0 - _air_timer / AIR_TIME
			var hop := sin(phase * PI)
			lift = hop * 26.0
			sc = 1.0 + hop * 0.18
			draw_circle(Vector2(_sx(car_x), CAR_Y), CAR_HALF_W * 1.1, Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2(_sx(car_x), CAR_Y - lift), ang, Vector2(sc, sc))
		if _tex_car != null:
			draw_texture_rect(_tex_car, Rect2(-CAR_HALF_W, -CAR_HALF_H, CAR_W, CAR_H), false)
		else:
			draw_rect(Rect2(-CAR_HALF_W, -CAR_HALF_H, CAR_W, CAR_H), col_car)
			draw_rect(Rect2(-CAR_HALF_W + 8.0, -CAR_HALF_H + 18.0, CAR_W - 16.0, 30.0), col_car_dark)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# explosion
	for b in _boom:
		var brem := 1.0 - float(b["age"]) / float(b["life"])
		if brem > 0.0:
			var bcol: Color = b["col"]
			bcol.a = brem
			var bpos: Vector2 = b["pos"]
			draw_circle(bpos, float(b["r"]) * (0.5 + brem * 0.8), bcol)

	if state == State.PLAYING or state == State.COUNTDOWN or state == State.CRASH:
		_draw_speedometer()

	# floating pickup popups
	for p in _popups:
		var prem := 1.0 - float(p["age"]) / POPUP_LIFE
		if prem <= 0.0:
			continue
		var pp2: Vector2 = p["pos"]
		var pw: float = p["width"]
		var inline: bool = p["inline"]
		if bool(p["coin"]):
			var cc := COL_COIN
			cc.a = prem
			if inline:
				draw_circle(pp2 + Vector2(-pw * 0.5 + 14.0, 2), COIN_R * 0.7, cc)
			else:
				draw_circle(pp2 + Vector2(0, 2), COIN_R * 0.7, cc)
		if _ui_font != null:
			var txt: String = p["text"]
			if inline:
				draw_string(_ui_font, pp2 + Vector2(-pw * 0.5 + 34.0, -14), txt, HORIZONTAL_ALIGNMENT_LEFT, pw - 34.0, 28, Color(1, 1, 1, prem))
			else:
				draw_string(_ui_font, pp2 + Vector2(-pw * 0.5, -14), txt, HORIZONTAL_ALIGNMENT_CENTER, pw, 30, Color(1, 1, 1, prem))

	# resume countdown
	if state == State.COUNTDOWN:
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.35))
		if _ui_font != null:
			var n := ceili(_count_timer)
			draw_string(_ui_font, Vector2(0, SCREEN_H * 0.5), str(n), HORIZONTAL_ALIGNMENT_CENTER, SCREEN_W, 160, Color(1, 1, 1, 0.95))

	# crash flash
	if state == State.CRASH:
		var f := clampf((_crash_timer - (CRASH_TIME - 0.15)) / 0.15, 0.0, 1.0)
		if f > 0.0:
			draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(1, 1, 1, f * 0.6))


# The jump-the-gap hole: a void that follows the road across its length, with a
# hazard-striped lip on the near edge so it reads as "ramp over this, don't drive in".
func _draw_gap(h: Dictionary, hd: float) -> void:
	var glen: float = float(h["len"])
	var g0 := hd - glen * 0.5
	var g1 := hd + glen * 0.5
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var dd := g0
	while dd <= g1 + 0.01:
		var c := road_center(dd)
		var hwd := road_half_width(dd)
		var yy := CAR_Y - (dd - distance)
		left.append(Vector2(_sx(c - hwd), yy))
		right.append(Vector2(_sx(c + hwd), yy))
		dd += 6.0
	var poly := PackedVector2Array()
	poly.append_array(left)
	for ri in range(right.size() - 1, -1, -1):
		poly.append(right[ri])
	if poly.size() >= 3:
		draw_colored_polygon(poly, COL_GAP)
	# striped lip on the NEAR edge (closest to the car = the larger-y, g0 end)
	var nc := road_center(g0)
	var nhw := road_half_width(g0)
	var lx := _sx(nc - nhw)
	var rx := _sx(nc + nhw)
	var ny := CAR_Y - (g0 - distance)
	var sw := 22.0
	var x := lx
	var on := true
	while x < rx:
		if on:
			draw_rect(Rect2(x, ny - 4.0, minf(sw, rx - x), 8.0), COL_GAP_RIM)
		on = not on
		x += sw


# Draws the road surface, edges and centre dashes. Off branches it's one
# continuous band (the common case, unchanged); on a branch it draws the two
# split lanes and lets the off-road show through the gap as the median.
func _draw_road() -> void:
	var step := 3.0   # finer sampling keeps the polyline smooth through sharp turns
	var bot_d := distance_at_row(SCREEN_H)
	var top_d := distance_at_row(0.0)

	var any_branch := false
	for b in _branches:
		if not (float(b["d1"]) < bot_d or float(b["d0"]) > top_d):
			any_branch = true
			break

	if not any_branch:
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var vs := PackedFloat32Array()
		var centers: Array = []
		var y := 0.0
		while y <= SCREEN_H:
			var d := distance_at_row(y)
			var c := road_center(d)
			var hw := road_half_width(d)
			left.append(Vector2(_sx(c - hw), y))
			right.append(Vector2(_sx(c + hw), y))
			vs.append(d / ROAD_TEX_TILE)
			centers.append(Vector3(_sx(c), y, d))
			y += step
		_fill_band(left, right, vs)
		draw_polyline(left, col_edge, 5.0, true)
		draw_polyline(right, col_edge, 5.0, true)
		_draw_dashes(centers)
		return

	# branch path: two lane bands. The gap between them is left unpainted so the
	# off-road shows through as the median. Only the OUTER edges are drawn
	# continuously; the inner (median) edges are drawn only where the lanes have
	# actually separated — that's what stops the edges intertwining at merges.
	var l0 := PackedVector2Array()
	var r0 := PackedVector2Array()
	var l1 := PackedVector2Array()
	var r1 := PackedVector2Array()
	var cen0: Array = []
	var cen1: Array = []
	var vs := PackedFloat32Array()
	var open := PackedInt32Array()
	var yy := 0.0
	while yy <= SCREEN_H:
		var d := distance_at_row(yy)
		var lanes := road_lanes(d)
		var c0 := float(lanes[0]["c"])
		var hw0 := float(lanes[0]["hw"])
		var c1 := float(lanes[1]["c"])
		var hw1 := float(lanes[1]["hw"])
		l0.append(Vector2(_sx(c0 - hw0), yy))
		r0.append(Vector2(_sx(c0 + hw0), yy))
		l1.append(Vector2(_sx(c1 - hw1), yy))
		r1.append(Vector2(_sx(c1 + hw1), yy))
		cen0.append(Vector3(_sx(c0), yy, d))
		cen1.append(Vector3(_sx(c1), yy, d))
		vs.append(d / ROAD_TEX_TILE)
		open.append(1 if (c1 - hw1) > (c0 + hw0) + 4.0 else 0)
		yy += step
	_fill_band(l0, r0, vs)
	_fill_band(l1, r1, vs)
	draw_polyline(l0, col_edge, 5.0, true)   # outer-left  (always a boundary)
	draw_polyline(r1, col_edge, 5.0, true)   # outer-right (always a boundary)
	_draw_open_edge(r0, open)                # inner edges (median kerb) only where open
	_draw_open_edge(l1, open)
	_draw_median(r0, l1, open)               # painted nose caps at the gore tips
	_draw_dashes(cen0)
	_draw_dashes(cen1)


# Fills a road band, textured (tiling along its length via the vs/UV-v values when
# a road texture is loaded) or flat-coloured otherwise.
func _fill_band(left: PackedVector2Array, right: PackedVector2Array, vs := PackedFloat32Array()) -> void:
	var poly := PackedVector2Array()
	poly.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	if _tex_road != null and vs.size() == left.size() and left.size() == right.size():
		var uvs := PackedVector2Array()
		for i in range(left.size()):
			uvs.append(Vector2(0.0, vs[i]))
		for i in range(right.size() - 1, -1, -1):
			uvs.append(Vector2(1.0, vs[i]))
		draw_colored_polygon(poly, Color.WHITE, uvs, _tex_road)
	else:
		draw_colored_polygon(poly, col_road)


# Centre line. Off-road / track themes paint none. Each dash is drawn as ONE
# grouped polyline over its "on" run instead of a stack of tiny per-sample lines —
# that overlap of antialiased stubs was what made the old stripes blotchy on bends.
func _draw_dashes(centers: Array) -> void:
	if not _theme_stripes:
		return
	var seg := PackedVector2Array()
	for i in range(centers.size()):
		var p: Vector3 = centers[i]
		if fposmod(p.z, DASH_PERIOD) < DASH_PERIOD * 0.5:
			seg.append(Vector2(p.x, p.y))
		else:
			if seg.size() >= 2:
				draw_polyline(seg, col_dash, 5.0, true)
			seg = PackedVector2Array()
	if seg.size() >= 2:
		draw_polyline(seg, col_dash, 5.0, true)


# Draws an inner (median) edge only across rows where the median is open,
# splitting into separate strokes so unrelated open regions (e.g. two branches
# on screen at once) are never joined by a stray line — which is what produced
# the intertwining edges before.
func _draw_open_edge(pts: PackedVector2Array, open: PackedInt32Array) -> void:
	var seg := PackedVector2Array()
	for i in range(pts.size()):
		if open[i] == 1:
			seg.append(pts[i])
		else:
			if seg.size() >= 2:
				draw_polyline(seg, col_edge, 5.0, true)
			seg = PackedVector2Array()
	if seg.size() >= 2:
		draw_polyline(seg, col_edge, 5.0, true)


# Marks the grass median where the road forks with a small painted nose cap at
# each tip of an open run, so the split reads as an intentional road feature. (The
# old hazard chevrons down the gore read as obstacles and were removed.)
func _draw_median(r0: PackedVector2Array, l1: PackedVector2Array, open: PackedInt32Array) -> void:
	var n := open.size()
	var i := 0
	while i < n:
		if open[i] == 0:
			i += 1
			continue
		var j := i
		while j < n and open[j] == 1:
			j += 1
		draw_circle((r0[i] + l1[i]) * 0.5, 6.0, col_edge)
		draw_circle((r0[j - 1] + l1[j - 1]) * 0.5, 6.0, col_edge)
		i = j


# Off-road background: a per-theme texture tiled with parallax scroll, or the flat
# theme colour when no texture is present.
func _draw_background() -> void:
	if _tex_bg != null:
		_draw_tiled(_tex_bg, camera_x * BG_TEX_PARALLAX, -distance * BG_TEX_PARALLAX)
	else:
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), col_offroad)


# Tiles a texture across the whole screen at the given world-scroll offset, so it
# works regardless of the texture's import/repeat flags.
func _draw_tiled(tex: Texture2D, scroll_x: float, scroll_y: float) -> void:
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var y := -fposmod(scroll_y, ts.y)
	while y < SCREEN_H:
		var x := -fposmod(scroll_x, ts.x)
		while x < SCREEN_W:
			draw_texture(tex, Vector2(x, y))
			x += ts.x
		y += ts.y


# Background props: per-theme sprite for the variant, else the primitive stand-in.
func _draw_decos() -> void:
	for deco in _decos:
		var dy := CAR_Y - (float(deco["d"]) - distance)
		if dy < -90.0 or dy > SCREEN_H + 90.0:
			continue
		var pos := Vector2(_sx(float(deco["x"])), dy)
		var variant := int(deco["variant"])
		var s := float(deco["scale"])
		if _tex_deco.size() > 0:
			var tex: Texture2D = _tex_deco[variant % _tex_deco.size()]
			var sz := tex.get_size() * s
			draw_texture_rect(tex, Rect2(pos - sz * 0.5, sz), false)
		else:
			_draw_deco_primitive(pos, variant, s)


func _draw_parallax() -> void:
	var gcol := Color(1, 1, 1, 0.045)
	var gx := floorf((camera_x - SCREEN_W) / GRID) * GRID
	while gx < camera_x + SCREEN_W:
		var x := _sx(gx)
		draw_line(Vector2(x, 0), Vector2(x, SCREEN_H), gcol, 1.0)
		gx += GRID
	var gd := floorf((distance + CAR_Y - SCREEN_H) / GRID) * GRID
	while gd < distance + CAR_Y:
		var yy := CAR_Y + distance - gd
		draw_line(Vector2(0, yy), Vector2(SCREEN_W, yy), gcol, 1.0)
		gd += GRID
