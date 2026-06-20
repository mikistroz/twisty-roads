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
const SPEED_PER_SEC := 0.65
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

# ---------------- crash ----------------
const CRASH_TIME := 1.0
const COL_SPEED_MAX := Color("ff5a5f")
const COL_SPEED := Color("e8e8e8")

# ---------------- save ----------------
const SAVE_PATH := "user://twisty_roads.cfg"

# ---------------- themes ----------------
# Palettes are placeholders that approximate each theme until real sprites land.
# "car"/"enemy" name the vehicles, "vfx" names the effect set — these are the
# slots the art pipeline will key off (e.g. load res://art/<id>/car.png).
const THEME_ORDER := ["default", "synthwave", "track", "rally", "jdm", "jetski", "sand", "mud", "rainbow", "frostbite", "wiped"]
const THEMES := {
	"default":   { "name": "Standard",     "price": 0,    "offroad": "2e5d34", "road": "3c4146", "edge": "e8e8e8", "dash": "f2c14e", "car": "1f6fd0", "car_dark": "0d4a99", "vehicle": "BMW E46",          "enemy": "Toyota RAV4",       "vfx": "dust" },
	"synthwave": { "name": "Synthwave",    "price": 300,  "offroad": "1a0b2e", "road": "241341", "edge": "ff2e97", "dash": "00f0ff", "car": "ffd319", "car_dark": "ff5f1f", "vehicle": "Lamborghini Countach", "enemy": "Sports coupes", "vfx": "neon" },
	"track":     { "name": "Track Attack", "price": 400,  "offroad": "2e7d32", "road": "3a3a3a", "edge": "e03131", "dash": "ffffff", "car": "e10600", "car_dark": "8a0400", "vehicle": "Open-wheel racer", "enemy": "Open-wheel racers", "vfx": "smoke" },
	"rally":     { "name": "Rally Rush",   "price": 500,  "offroad": "234a25", "road": "6b4f2a", "edge": "caa15a", "dash": "ffffff", "car": "1565c0", "car_dark": "0d47a1", "vehicle": "Subaru Impreza",   "enemy": "Mitsubishi Lancer", "vfx": "gravel" },
	"jdm":       { "name": "JDM",          "price": 600,  "offroad": "0d1b2a", "road": "23272e", "edge": "f72585", "dash": "4cc9f0", "car": "e6552a", "car_dark": "a83419", "vehicle": "Toyota Supra",     "enemy": "Mazda Miata",       "vfx": "underglow" },
	"jetski":    { "name": "Jetski Escape","price": 700,  "offroad": "e3c98f", "road": "1f7a8c", "edge": "9be7ff", "dash": "ffffff", "car": "ff5252", "car_dark": "b71c1c", "vehicle": "Jetski",          "enemy": "Jetskis",           "vfx": "splash" },
	"sand":      { "name": "Sand Rally",   "price": 800,  "offroad": "c2954e", "road": "9c7a3c", "edge": "e8d6a0", "dash": "ffffff", "car": "2e7d32", "car_dark": "1b5e20", "vehicle": "Rally buggy",      "enemy": "Porsche Safari",    "vfx": "sand" },
	"mud":       { "name": "Mud Sprint",   "price": 900,  "offroad": "3b5323", "road": "5b432a", "edge": "8a6d3b", "dash": "ffffff", "car": "d32f2f", "car_dark": "9a1f1f", "vehicle": "Enduro bike",      "enemy": "Enduro bikes",      "vfx": "mud" },
	"rainbow":   { "name": "Rainbow Lane", "price": 1000, "offroad": "0b0b2a", "road": "3a2f5e", "edge": "ff5ec7", "dash": "ffffff", "car": "ffeb3b", "car_dark": "fbc02d", "vehicle": "Kart",            "enemy": "Karts",             "vfx": "rainbow" },
	"frostbite": { "name": "Frostbite Run","price": 1200, "offroad": "dfe9f0", "road": "8fa8bf", "edge": "5b86b0", "dash": "ffffff", "car": "455a64", "car_dark": "263238", "vehicle": "Ford F-150",      "enemy": "Porsche Cayenne",   "vfx": "snow" },
	"wiped":     { "name": "Wiped Out",    "price": 1500, "offroad": "0a1226", "road": "13294b", "edge": "39c0ff", "dash": "8affff", "car": "00e5ff", "car_dark": "0091a7", "vehicle": "Hover racer",      "enemy": "Hover racers",      "vfx": "energy" },
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

var _pt_d := PackedFloat32Array()
var _pt_x := PackedFloat32Array()
var _track_frontier_d := 0.0
var _track_last_x := ROAD_CENTER_X
var _bias := 0.0
var _pattern_queue: Array = []

var _coins: Array = []
var _coin_frontier_d := 0.0
var _hazards: Array = []
var _hazard_frontier_d := 0.0
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

var _micro_noise := FastNoiseLite.new()
var _touch_down := false
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
var _hud_speed: Label
var _hud_prompt: Label
var _go_score: Label
var _go_coins: Label
var _go_challenge: Label


func _ready() -> void:
	randomize()
	_ui_font = ThemeDB.fallback_font
	_micro_noise.frequency = 0.01
	_load_save()
	_apply_theme(selected)
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
	_hud_speed = _make_label(_hud, "", Vector2(20, 40), Vector2(280, 50), 30)
	_hud_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	_tire_marks.clear()
	_particles.clear()
	_boom.clear()
	_popups.clear()
	_pattern_queue.clear()
	_coin_frontier_d = 0.0
	_hazard_frontier_d = 0.0
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
	_ensure_track(distance + 1400.0)
	_ensure_coins(distance + 1400.0)
	_ensure_hazards(distance + 1400.0)
	_hud_score.text = "0"
	_hud_coins.text = "Coins: 0"
	_hud_speed.text = ""
	_hud_prompt.visible = true
	_show_screen()


func _pause_game() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	_show_screen()
	queue_redraw()


func _resume() -> void:
	state = State.COUNTDOWN
	_count_timer = COUNT_TIME
	_steer_armed = false
	_hud_prompt.visible = false
	_show_screen()
	queue_redraw()


func _crash() -> void:
	if state != State.PLAYING:
		return
	state = State.CRASH
	_crash_timer = CRASH_TIME
	Input.vibrate_handheld(220)
	_spawn_explosion(_sx(car_x), CAR_Y)


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
		_touch_down = event.pressed


func _input_down() -> bool:
	return _touch_down or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)


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
		else:
			camera_x = car_x
			return

	time_alive += delta
	distance += current_speed() * delta

	_ensure_track(distance + 1400.0)
	_ensure_coins(distance + 1400.0)
	_ensure_hazards(distance + 1400.0)
	_drop_old()

	# camera follows the car (with a little look-ahead toward the upcoming road)
	var look := road_center(distance + CAM_LOOKAHEAD)
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
	_update_tire_marks(delta)

	_no_coin_timer += delta
	if _no_coin_timer > _no_coin_best:
		_no_coin_best = _no_coin_timer

	if not airborne:
		var c := road_center(distance)
		var hw := road_half_width(distance)
		if absf(car_x - c) > hw - COL_HALF_W:
			_crash()
			return

	_update_hazards(delta, airborne)
	if state != State.PLAYING:
		return

	_update_speedometer()
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
	while _coins.size() > 0 and float(_coins[0]["d"]) < distance - 500.0:
		_coins.remove_at(0)
	var i := _hazards.size() - 1
	while i >= 0:
		if float(_hazards[i]["d"]) < distance - 600.0:
			_hazards.remove_at(i)
		i -= 1


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
		# only place where the road is roughly straight, so it's always avoidable
		if absf(road_center(d + 50.0) - road_center(d - 50.0)) > STRAIGHT_DELTA:
			continue
		var bc := road_center(d)
		var bandh := road_half_width(d) - COL_HALF_W
		var roll := randf()
		if roll < 0.20:
			var eff := BLOCK_W * 0.5 + COL_HALF_W
			if 2.0 * bandh >= 2.0 * eff + GAP_MIN:
				_hazards.append({ "d": d, "x": bc + _flush_side(bandh, eff), "type": "block", "lane": 0.0, "ang": 0.0, "hit": false })
		elif roll < 0.58:
			var eff2 := TRAFFIC_W * 0.5 + COL_HALF_W
			if 2.0 * bandh >= 2.0 * eff2 + GAP_MIN:
				var sgn := 1.0
				if randf() < 0.5:
					sgn = -1.0
				var lane := sgn * randf_range(0.24, 0.44)
				_hazards.append({ "d": d, "x": bc + lane * road_half_width(d), "type": "traffic", "lane": lane, "ang": 0.0, "hit": false, "spd": randf_range(TRAFFIC_REL_MIN, TRAFFIC_REL_MAX), "scored": false })
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


func _update_hazards(delta: float, airborne: bool) -> void:
	for h in _hazards:
		var htype: String = h["type"]
		if htype == "traffic":
			# closing speed scales with the player's speed (enemies get faster too)
			h["d"] = float(h["d"]) - current_speed() * float(h["spd"]) * delta
			var td := float(h["d"])
			var hwt := road_half_width(td)
			var tgt := road_center(td) + float(h["lane"]) * hwt
			var oldx := float(h["x"])
			var nx := move_toward(oldx, tgt, TRAFFIC_LAT_SPEED * delta)
			# never let it drift off the road, even on a sharp curve
			nx = clampf(nx, road_center(td) - (hwt - COL_HALF_W), road_center(td) + (hwt - COL_HALF_W))
			h["x"] = nx
			h["ang"] = clampf((nx - oldx) / maxf(TRAFFIC_LAT_SPEED * delta, 0.001), -1.0, 1.0) * 0.4
		var hd := float(h["d"])
		var hx := float(h["x"])
		var dy := absf(hd - distance)
		var dx := absf(hx - car_x)
		if htype == "block":
			if not airborne and dy < COL_HALF_H + BLOCK_H * 0.5 and dx < COL_HALF_W + BLOCK_W * 0.5:
				_crash()
				return
		elif htype == "traffic":
			if not airborne and dy < COL_HALF_H + TRAFFIC_H * 0.5 and dx < COL_HALF_W + TRAFFIC_W * 0.5:
				_crash()
				return
			# near miss: passed close alongside without crashing -> reward
			if not h["scored"] and dy < COL_HALF_H + 20.0 and dx < NEAR_MISS_DX:
				h["scored"] = true
				session_coins += NEAR_MISS_COINS
				_add_popup(_sx(car_x), CAR_Y - 60.0, "NEAR MISS +%d" % NEAR_MISS_COINS, false)
		elif htype == "oil":
			if not h["hit"] and dy < OIL_R and dx < OIL_R:
				h["hit"] = true
				_oil_timer = OIL_TIME
		elif htype == "jump":
			if not h["hit"] and dy < COL_HALF_H + JUMP_H * 0.5 and dx < COL_HALF_W + JUMP_W * 0.5:
				h["hit"] = true
				_air_timer = AIR_TIME


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


func _add_popup(sx_pos: float, sy_pos: float, text: String, coin: bool) -> void:
	_popups.append({ "pos": Vector2(sx_pos, sy_pos), "text": text, "age": 0.0, "coin": coin })


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


func _update_speedometer() -> void:
	var kmh := int(current_speed() / PX_PER_METER * 3.6)
	if _ramp_speed() >= MAX_SPEED - 0.5:
		_hud_speed.text = "MAX  %d KM/H" % kmh
		_hud_speed.add_theme_color_override("font_color", COL_SPEED_MAX)
	elif _boost_timer > 0.0:
		_hud_speed.text = "BOOST  %d KM/H" % kmh
		_hud_speed.add_theme_color_override("font_color", COL_BOOST)
	else:
		_hud_speed.text = "%d KM/H" % kmh
		_hud_speed.add_theme_color_override("font_color", COL_SPEED)


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
		var bc := road_center(d)
		# reach is reduced on curves (where the road shifts across the coin's height)
		var slope := absf(road_center(d + 30.0) - road_center(d - 30.0)) / 60.0
		var curve_fade := clampf(1.0 - slope, 0.45, 1.0)
		var reach := (road_half_width(d) - COL_HALF_W - COIN_R) * 0.8 * curve_fade
		var cx := bc + randf_range(-1.0, 1.0) * maxf(reach, 0.0)
		_coins.append({ "d": d, "x": cx, "got": false, "missed": false })


# ============================================================
#  DRAWING
# ============================================================
func _car_angle() -> float:
	return clampf(lateral_velocity / STEER_SPEED, -1.0, 1.0) * MAX_TILT


func _draw() -> void:
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), col_offroad)
	_draw_parallax()

	var step := 6.0
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var centers: Array = []

	var y := 0.0
	while y <= SCREEN_H:
		var d := distance_at_row(y)
		var c := road_center(d)
		var hw := road_half_width(d)
		left.append(Vector2(_sx(c - hw), y))
		right.append(Vector2(_sx(c + hw), y))
		centers.append(Vector3(_sx(c), y, d))
		y += step

	var poly := PackedVector2Array()
	poly.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	draw_colored_polygon(poly, col_road)

	draw_polyline(left, col_edge, 5.0, true)
	draw_polyline(right, col_edge, 5.0, true)

	# dashed center line as smooth strokes along the curve
	for i in range(centers.size() - 1):
		var p0: Vector3 = centers[i]
		var p1: Vector3 = centers[i + 1]
		if fposmod(p0.z, DASH_PERIOD) < DASH_PERIOD * 0.5:
			draw_line(Vector2(p0.x, p0.y), Vector2(p1.x, p1.y), col_dash, 5.0, true)

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
			draw_rect(Rect2(-TRAFFIC_W * 0.5, -TRAFFIC_H * 0.5, TRAFFIC_W, TRAFFIC_H), COL_TRAFFIC)
			draw_rect(Rect2(-TRAFFIC_W * 0.5 + 8.0, TRAFFIC_H * 0.5 - 48.0, TRAFFIC_W - 16.0, 30.0), COL_TRAFFIC_DARK)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif ht == "jump":
			var ramp := PackedVector2Array()
			ramp.append(Vector2(hx - JUMP_W * 0.5, hy + JUMP_H * 0.5))
			ramp.append(Vector2(hx + JUMP_W * 0.5, hy + JUMP_H * 0.5))
			ramp.append(Vector2(hx + JUMP_W * 0.35, hy - JUMP_H * 0.5))
			ramp.append(Vector2(hx - JUMP_W * 0.35, hy - JUMP_H * 0.5))
			draw_colored_polygon(ramp, COL_JUMP)
			draw_line(Vector2(hx - 24.0, hy + 10.0), Vector2(hx, hy - 12.0), COL_JUMP_HI, 4.0)
			draw_line(Vector2(hx + 24.0, hy + 10.0), Vector2(hx, hy - 12.0), COL_JUMP_HI, 4.0)

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

	# floating pickup popups
	for p in _popups:
		var prem := 1.0 - float(p["age"]) / POPUP_LIFE
		if prem <= 0.0:
			continue
		var pp2: Vector2 = p["pos"]
		if bool(p["coin"]):
			var cc := COL_COIN
			cc.a = prem
			draw_circle(pp2 + Vector2(0, 2), COIN_R * 0.7, cc)
		if _ui_font != null:
			var txt: String = p["text"]
			draw_string(_ui_font, pp2 + Vector2(-60, -14), txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 30, Color(1, 1, 1, prem))

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
