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
const SCREEN_H := 1280.0           # UI design height; gameplay uses the live _view_h
const CAR_BOTTOM := 300.0          # the car sits this far up from the bottom of the view
const CAR_W := 50.0
const CAR_H := 90.0
const CAR_HALF_W := CAR_W * 0.5
const CAR_HALF_H := CAR_H * 0.5
# Canonical collision footprint used by the GENERATION fairness maths (gap sizes,
# fork widths). The live collision box is _pl_hw/_pl_hh, which is this clamped DOWN
# to the loaded sprite's opaque content (see _content_half) — so collisions follow
# the visible car, never the transparent rect, and never exceed what generation
# already guaranteed passable.
const COL_HALF_W := 19.0          # collision half-extents (smaller than the art = fairer)
const COL_HALF_H := 36.0
const ROAD_CENTER_X := 360.0

# ---------------- retro / pixel-art look ----------------
# VFX pixel grid. Matched to the vehicle art's native resolution (~24x42 source px
# drawn at 2x => 2px per art-pixel), so blocky effects read at the same scale as
# the car instead of as coarse chunks. Road EDGES are drawn smooth (see _draw_road).
const PIX := 2.0

# ---------------- camera ----------------
const CAM_FOLLOW := 6.0
const CAM_MAX_OFF := 150.0
const CAM_LOOKAHEAD := 240.0
const CAM_LOOK_W := 0.30
const GRID := 110.0               # parallax ground grid spacing

# ---------------- difficulty ----------------
const BASE_SPEED := 330.0
const SPEED_PER_SEC := 2.6        # climbs to MAX sooner, so the run gets exciting faster
const MAX_SPEED := 560.0
const START_HALF_WIDTH := 200.0
const MIN_HALF_WIDTH := 120.0
const NARROW_PER_DIST := 0.0007   # road narrows by distance (visible ahead, fair)
const RAMP_SECONDS := 220.0
const INTRO_DIST := 800.0         # straight, hazard-free start (short: the first decision comes fast)
const MAX_STRAIGHT_RUN := 820.0   # it's "Twisty Roads": force a bend if the road runs this straight

# Rhythm curve: periodic "breather" sections where the road widens (speed stays
# linear — no slowdown).
const RHYTHM_FREQ := 0.0013        # ~4800px between breathers
const RHYTHM_WIDTH_AMP := 55.0

# Real-world feel: 8 world-pixels = 1 metre.
const PX_PER_METER := 8.0

# Jump = high-risk/high-reward: clear obstacles, +2 coins on landing, speed boost.
const BOOST_MULT := 1.45
const BOOST_TIME := 2.2
const BOOST_WARN := 0.7           # last stretch of boost: flash + chirp so you know it's ending
const JUMP_COINS := 2
const NEAR_MISS_DX := 94.0        # lateral gap that counts as a near miss (crash is ~44)
const NEAR_MISS_COINS := 2
const COL_BOOST := Color("ffe27a")

# Resume countdown
const COUNT_TIME := 3.0

# ---------------- menu attract mode ----------------
# Behind the menus, a demo driver cruises the last selected theme's road, lazily
# weaving from edge to edge, under a slight blur (see _build_menu_blur) that keeps
# the UI readable. It reuses the live world: same track generator, same theme art,
# same trail VFX — just no hazards, coins or scoring.
const MENU_DRIVE_SPEED := 300.0   # demo cruise speed (a touch under base speed)
const MENU_SWAY_SMOOTH := 2.6     # how eagerly the demo driver chases its weave target

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
const DASH_SPLIT_EPS := 2.0       # lane centres must part by this (px) before the 2nd centre line is painted — below it the two lanes coincide and a single line is drawn (no double-paint flicker)

# ---------------- forks ----------------
# road_center/road_half_width describe ONE continuous centerline. A "fork"
# turns a straight stretch into two lanes (symmetric about a straightened chord)
# that separate around a grass median and then merge back — pick a lane, grab
# the coins, rejoin. Forks are the multi-lane "segments" layered on top of the
# centerline, which is what lets the road split without the centerline having to
# be multi-valued.
const BRANCH_SPACING := 7000.0    # min gap between one fork ending and the next starting
const FORK_LEN_MIN := 700.0       # forks are short, technical sections — not long straights
# Ceiling kept high enough that it never clamps a fork BELOW its sweep-cap minimum
# length: now that forks run at the real boosted top speed, the fairness-minimum
# length grew ~BOOST_MULT, so a lower ceiling would have silently produced forks
# that peel faster than the player can steer. Typical forks still land ~1.4–1.8k.
const FORK_LEN_MAX := 2300.0
const BRANCH_RAMP := 0.30         # fraction of a fork's length spent splitting / merging
const LANE_FRAC := 0.62           # split-lane half-width as a fraction of the local road
const LANE_HW_MIN := 84.0         # lanes never narrower than this (keeps a passing corridor + steer room)
const LANE_HW_MAX := 98.0         # ...nor wider than this, so wide early roads still make SHORT forks
const FORK_MEDIAN_FRAC := 0.12    # fork median half-width as a fraction of the local road
const FORK_SWEEP_CAP := 320.0     # peak sideways peel speed of a lane: forks are LENGTH-sized so this holds even at the real (boosted) top speed they're now driven at — a sideways-trackability fairness bound, not a forward-speed cap
const BRANCH_STRAIGHT_DELTA := 48.0  # entry must be at least this straight (per 300px)
const BRANCH_MAX_DRIFT := 150.0   # max sideways drift of the road across a fork; small => the straightened chord barely deviates, so the axis transient stays gentle on short forks
# The track generator holds the road straight in a window around wherever the next
# branch is due. The straightness/drift gates above are hard fairness rules, but
# the road seeds bends on most segments, so left alone the two systems fought:
# ~95% of placement attempts failed the gates, branches ran at well over their
# intended spacing, and the rarer set-pieces (roundabout islands) practically
# never appeared. Straightening the road exactly where a branch wants to live
# makes the generator PRODUCE what the placement rules demand — same rules, no
# forcing — and restores the intended branch cadence.
const BRANCH_STRAIGHT_LEAD := 600.0   # straight starts this far before the due point (covers the entry gate)
const BRANCH_STRAIGHT_SPAN := 4600.0  # give up this far past it and let the road bend again
const BRANCH_COINS := 4           # coins seeded along the scenic lane

# Fork variety: a branch picks a STYLE and randomises its geometry so no two read
# the same. The two lanes of a fork are described independently now (their own
# separation, width and split-ramp), so a fork can be a clean mirror split or a
# lopsided one (a fat lane beside a thin one). Length varies too — a longer fork
# only peels more gently, so it stays within the sweep cap and is always fair.
const FORK_LEN_VARY_MAX := 1.25   # fork length multiplier (>=1 keeps peel within the sweep cap)
const FORK_OFF_VARY := 0.30       # +/- fraction jittered onto each lane's separation
const FORK_HW_VARY := 0.22        # +/- fraction jittered onto each lane's half-width
const FORK_RAMP_VARY := 0.25      # +/- fraction jittered onto each lane's split ramp
const FORK_ASYM_CHANCE := 0.5     # chance a fork is lopsided rather than mirror-symmetric
const SHOULDER_CHANCE := 0.4      # chance a branch is a bailout shoulder instead of a fork

# Forks aren't dead-straight cruises: a gentle sideways WAVE (faded in/out at the
# merges so it stays seamless) makes the split wind. The wave is kept small enough
# that a lane never moves sideways faster than the player can track even at the real
# top speed forks are now driven at. Forks no longer carry their own SCRIPTED
# traffic/oil — hazards inside a fork come from the same systemic generator as the
# rest of the road (see _try_fork_hazard), so a fork reads as ordinary road that
# happens to split, not a separate mini-game with bespoke obstacles.
const FORK_WAVE_AMP := 8.0        # max sideways wander added across a fork
const FORK_WAVE_LEN := 820.0      # wavelength of that wander
const FORK_WAVE_CHANCE := 0.8     # chance a fork winds rather than running straight
const FORK_ISLAND_CHANCE := 0.32  # chance a fork is a roundabout-style island instead
const ISLAND_MEDIAN_MULT := 2.6   # islands open a much wider grass middle...
                                  # ...and run at the minimum fair length with fully
                                  # bowed lanes (ramp 0.5 -> a sine arch, no straight
                                  # middle), so they read as a proper ROUNDABOUT you
                                  # sweep around, not a long parallel fork

# ---------------- curated formations ----------------
# Hand-authored centerline set-pieces stitched into the procedural generation at
# random intervals: recognizable shapes (slalom gates, a smooth wave, a double
# hairpin, a long sweeper, a chicane flick, a hard zigzag, a tightening spiral,
# a figure-eight, an orbit bulge) that give the road moments of intent.
# Each step is {dx: fraction of the formation's amplitude, len: authored segment
# length}; the whole shape is mirrored at random and scaled by the difficulty ramp.
const FORMATION_CHANCE := 0.5     # chance a seeded pattern uses a formation instead
const FORMATIONS := [
	{ "name": "slalom", "amp": 185.0, "steps": [
		{ "dx": 1.0, "len": 185.0 }, { "dx": -1.0, "len": 185.0 }, { "dx": 1.0, "len": 185.0 },
		{ "dx": -1.0, "len": 185.0 }, { "dx": 0.0, "len": 200.0 } ] },
	{ "name": "wave", "amp": 240.0, "steps": [
		{ "dx": 0.7, "len": 210.0 }, { "dx": 1.0, "len": 210.0 }, { "dx": 0.7, "len": 210.0 },
		{ "dx": 0.0, "len": 210.0 }, { "dx": -0.7, "len": 210.0 }, { "dx": -1.0, "len": 210.0 },
		{ "dx": -0.7, "len": 210.0 }, { "dx": 0.0, "len": 210.0 } ] },
	{ "name": "double_hairpin", "amp": 360.0, "steps": [
		{ "dx": 1.0, "len": 300.0 }, { "dx": 1.0, "len": 200.0 }, { "dx": -1.0, "len": 420.0 },
		{ "dx": -1.0, "len": 200.0 }, { "dx": 0.0, "len": 320.0 } ] },
	{ "name": "sweeper", "amp": 330.0, "steps": [
		{ "dx": 0.55, "len": 260.0 }, { "dx": 1.0, "len": 300.0 }, { "dx": 1.0, "len": 260.0 },
		{ "dx": 0.45, "len": 260.0 } ] },
	{ "name": "chicane_flick", "amp": 210.0, "steps": [
		{ "dx": 1.0, "len": 170.0 }, { "dx": -1.0, "len": 190.0 }, { "dx": -0.2, "len": 210.0 } ] },
	# hard zigzag: sharper and longer than the inline zigzag pattern — a sawtooth
	# of full-amplitude cuts with barely a breath between them
	{ "name": "zigzag", "amp": 250.0, "steps": [
		{ "dx": 1.0, "len": 165.0 }, { "dx": -1.0, "len": 165.0 }, { "dx": 1.0, "len": 165.0 },
		{ "dx": -1.0, "len": 165.0 }, { "dx": 1.0, "len": 165.0 }, { "dx": -1.0, "len": 165.0 },
		{ "dx": 0.0, "len": 190.0 } ] },
	# figure-eight: two big opposed loops joined by a hard crossover through the
	# middle — the road bulges far out one way, whips across, and bulges back out
	# the other before returning
	{ "name": "figure_eight", "amp": 360.0, "steps": [
		{ "dx": 0.85, "len": 220.0 }, { "dx": 1.0, "len": 190.0 }, { "dx": 0.55, "len": 190.0 },
		{ "dx": -0.55, "len": 210.0 }, { "dx": -1.0, "len": 190.0 }, { "dx": -0.85, "len": 190.0 },
		{ "dx": 0.0, "len": 230.0 } ] },
	# spiral: turns that wind progressively tighter — each swing is smaller and
	# quicker than the last, corkscrewing in before flicking straight
	{ "name": "spiral", "amp": 330.0, "steps": [
		{ "dx": 1.0, "len": 300.0 }, { "dx": -0.78, "len": 235.0 }, { "dx": 0.6, "len": 185.0 },
		{ "dx": -0.44, "len": 145.0 }, { "dx": 0.3, "len": 115.0 }, { "dx": -0.18, "len": 95.0 },
		{ "dx": 0.0, "len": 130.0 } ] },
	# orbit: skirt the rim of a circle — swing out, ride the arc, swing home
	# (the centerline cousin of the island-fork roundabout)
	{ "name": "orbit", "amp": 300.0, "steps": [
		{ "dx": 0.9, "len": 180.0 }, { "dx": 1.0, "len": 150.0 }, { "dx": 1.0, "len": 170.0 },
		{ "dx": 0.9, "len": 150.0 }, { "dx": 0.0, "len": 180.0 } ] },
]

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
# Fairness buffers: never drop a hazard right after a forced high-friction move.
# A fork's exit merge is a "blind sweep" (lanes folding back together) and a jump
# landing eats a reserved runway — both get a clear stretch so the player is never
# punished the instant a forced sequence ends. (Jump runways are also reserved at
# spawn time; this is the belt-and-braces rule applied uniformly to forks.)
const POST_BRANCH_CLEAR := 520.0  # clear road after a fork merges back
const PRE_BRANCH_CLEAR := 280.0   # clear road just before a fork splits (so the choice reads clean)
const FORK_HAZARD_GUARD := 0.06   # extra margin past a lane's ramp before a fork may host a hazard (keeps hazards out of the peel sweep)
const BLOCK_W := 60.0             # reference width (near-miss margin is derived from it)
const BLOCK_H := 42.0
# Roadblocks come in variable widths (zapper-style): anywhere between these two,
# further capped at spawn time so the guaranteed GAP_MIN corridor always remains.
const BLOCK_W_MIN := 46.0
const BLOCK_W_MAX := 210.0
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

# ---------------- combo ----------------
# Chained scoring: every scoring action (coin, near miss, jump landing, smash)
# performed within COMBO_TIME of the previous one banks +COMBO_BONUS on top of its
# own reward and refills the window. A ramp boost FREEZES the clock instead of
# resetting it, so a smash-through spree carries its chain across the whole boost.
const COMBO_TIME := 3.0
const COMBO_BONUS := 1
const COL_COMBO := Color("6ef3ff")

# ---------------- lucky run ----------------
# 1-in-100 runs are LUCKY: everything that pays coins pays double for the whole
# run (all gains funnel through _grant_coins), announced by a gold banner and a
# pulsing gold frame so it can't be missed.
const LUCKY_CHANCE := 0.01

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
# Barrier styling: blocks have no sprite slot, so they're drawn as a proper piece
# of street furniture — a warning-yellow board on dark feet with a SYMMETRIC
# mirrored stripe pattern and blinking end lamps. The stripe count per half is
# FIXED (repeats, not a per-20px fill), so a barrier of any random width carries
# the same uniform pattern, just scaled.
const BLOCK_STRIPES := 3          # stripe repeats per half, mirrored about the centre
const COL_BLOCK_HI := Color("ffe08a")     # top lip highlight
const COL_BLOCK_SHADE := Color("b88d07")  # bottom lip shade
const COL_BLOCK_LAMP := Color("ffb03a")   # end lamp, lit phase
const COL_BLOCK_LAMP_OFF := Color("7a2717")  # end lamp, dark phase
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

# ---------------- trail VFX ----------------
# What the car leaves behind, keyed by each theme's "vfx" name. A vfx is either a
# path trail — the tail-light streaks (synthwave) or the jetski's water wake, both
# drawn as fading polylines along the car's actual path — or a set of spray LAYERS:
# exhaust smoke puffs from the centre pipe and/or terrain kicked up from the rear
# wheels (dust/sand/mud/snow), so rally reads smoke+dust and frostbite smoke+snow.
# The wake also keeps a sparse splash layer on top, so it reads as displaced water
# with the odd spray kick rather than a smoke column. Enemies emit from the same
# per-theme sets (see _enemy_fx_layers), so traffic matches its world.
const SPRAY_SMOKE  := { "cols": ["8a8a8a", "a8a8a8", "6e6e6e"], "wheels": false, "rmin": 3.5, "rmax": 7.0, "lmin": 0.50, "lmax": 0.90 }
const SPRAY_DUST   := { "cols": ["b8a888", "9c8c6c", "cfc0a0"], "wheels": true,  "rmin": 2.5, "rmax": 5.0, "lmin": 0.35, "lmax": 0.60 }
const SPRAY_SAND   := { "cols": ["e0c88c", "c2a45e", "efe0b0"], "wheels": true,  "rmin": 2.5, "rmax": 5.5, "lmin": 0.35, "lmax": 0.65 }
const SPRAY_MUD    := { "cols": ["4a3520", "5b432a", "33240f"], "wheels": true,  "rmin": 3.0, "rmax": 6.0, "lmin": 0.40, "lmax": 0.70 }
const SPRAY_SNOW   := { "cols": ["ffffff", "e8f2fa", "cfe0ee"], "wheels": true,  "rmin": 2.5, "rmax": 5.5, "lmin": 0.50, "lmax": 0.90 }
const SPRAY_SPLASH := { "cols": ["bfeeff", "ffffff", "7fd4ec"], "wheels": true,  "rmin": 3.0, "rmax": 6.5, "lmin": 0.30, "lmax": 0.55 }
# what synthwave ENEMIES shed (the player's taillight polylines don't scale to
# traffic): tiny fading tail-light embers
const SPRAY_TAIL   := { "cols": ["ff2433", "ff6a3d"], "wheels": false, "rmin": 2.0, "rmax": 3.5, "lmin": 0.22, "lmax": 0.40 }
const VFX := {
	"smoke":      { "layers": [SPRAY_SMOKE] },
	"smoke_dust": { "layers": [SPRAY_SMOKE, SPRAY_DUST] },
	"smoke_sand": { "layers": [SPRAY_SMOKE, SPRAY_SAND] },
	# mud_bike = the enduro bike: same smoke+mud spray, but kicked from a SINGLE
	# rear wheel, plus a continuous one-line oil groove along the path (see
	# _emit_trail / _draw_oil_trail)
	"mud_bike":   { "layers": [SPRAY_SMOKE, SPRAY_MUD] },
	"smoke_snow": { "layers": [SPRAY_SMOKE, SPRAY_SNOW] },
	"wake":       { "layers": [SPRAY_SPLASH] },
	"taillight":  { "layers": [] },
}
const COL_TAILLIGHT := Color("ff2433")   # the smooth red streak colour
const TAILLIGHT_LEN := 240.0             # how far back (world px) the streaks reach
const TAILLIGHT_MAX_PTS := 72            # history cap (samples are per-frame)
# The jetski's water wake: two foam streaks that spread outward and fade with age.
const COL_WAKE := Color("dff6ff")
const WAKE_LEN := 230.0                  # how far back (world px) the wake reaches
const WAKE_MAX_PTS := 64
const WAKE_SPREAD := 30.0                # extra half-spread the streaks gain at the tail
# The mud enduro bike rides on ONE wheel track, so instead of twin marks it drips
# a single oily groove along its actual path: a dark core in a wider wet smear,
# with a faint violet sheen on the freshest stretch (oil-slick shimmer).
const COL_OILTRAIL := Color(0.07, 0.06, 0.09)
const COL_OILTRAIL_SHEEN := Color(0.52, 0.42, 0.66)
const OILTRAIL_LEN := 260.0              # how far back (world px) the groove reaches
const OILTRAIL_MAX_PTS := 72

# ---------------- object shadows ----------------
# Soft offset drop shadows under everything that sits ON the road/terrain, so
# objects stay readable on flat or busy surfaces (rainbow especially).
const SHADOW_COL := Color(0.0, 0.0, 0.0, 0.20)
const SHADOW_OFF := Vector2(5.0, 7.0)

# ---------------- crash ----------------
const CRASH_TIME := 1.0
const COL_SPEED_MAX := Color("ff5a5f")
const COL_SPEED := Color("e8e8e8")
# Brief screen shake on impact: the whole WORLD node jolts (the HUD lives on a
# CanvasLayer, so it stays put) with an amplitude that decays quadratically.
# DRAW_PAD over-paints every full-screen surface by the max shake offset, so the
# jolt never exposes a bare strip of clear-colour at the edges.
const SHAKE_TIME := 0.45
const SHAKE_AMP := 14.0
const DRAW_PAD := 16.0

# ---------------- speedometer gauge ----------------
# Rendered retro-instrument style: a ring of chunky PIX-snapped segments that
# light with speed and a blocky needle, so the tachometer sits in the same
# pixel-art language as the rest of the game (see _draw_speedometer).
const GAUGE_CENTER := Vector2(118.0, 156.0)
const GAUGE_R := 84.0
const GAUGE_START_DEG := 140.0
const GAUGE_END_DEG := 400.0
const GAUGE_MIN_KMH := 90.0       # dial floor (just below start speed) so the needle has room to climb
const GAUGE_MAX_KMH := 370.0      # ~MAX_SPEED * BOOST_MULT converted to km/h
const GAUGE_SEGS := 24            # pixel segments around the dial
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
const ART_LIST_MAX := 32          # highest index scanned for numbered series (enemy_0..enemy_31); gaps are fine
# Road AND background textures render at a fixed 256x256 world footprint (matching
# the 256x256 reference art) and are anchored to WORLD coordinates on both axes —
# the ground scrolls 1:1 with the road, so the world reads as one cohesive surface
# instead of sliding parallax layers. Between them a whisper of darkening (see
# BG_DARKEN) lifts the road plane without touching the pixel-art look.
const WORLD_TEX_TILE := 256.0
const BG_DARKEN := 0.05

# ---------------- font ----------------
# Convention-based, like the art/audio: drop a TTF/OTF at res://fonts/<name> and
# it's used for the whole UI; missing -> the engine default. The retro art
# direction wants DotGothic16, so it's tried first. Loaded with load_dynamic_font
# so it works at runtime without an editor import step, and rendered with
# antialiasing OFF so it stays crisp and pixel-true.
const FONT_DIR := "res://fonts/"
const FONT_NAMES := ["DotGothic16-Regular", "DotGothic16", "dotgothic16"]
const FONT_EXTS := ["ttf", "otf"]

# ---------------- themes ----------------
# Palettes are placeholders that approximate each theme until real sprites land.
# "vehicle"/"enemy" name the vehicles, "vfx" names the effect set, "stripes" says
# whether the road carries a painted centre line (off-road / track surfaces don't)
# — these are the slots the art pipeline keys off (e.g. res://art/<id>/car.png).
# Prices are sized against the combo-era income (chained bonuses + the odd Lucky
# Run raise a typical run's take by roughly a third over the pre-combo economy),
# so themes still land at about the same number of runs as before.
const THEME_ORDER := ["default", "synthwave", "track", "rally", "jdm", "jetski", "sand", "mud", "rainbow", "frostbite"]
const THEMES := {
	"default":   { "name": "Standard",     "price": 0,    "offroad": "2e5d34", "road": "3c4146", "edge": "e8e8e8", "dash": "f2c14e", "stripes": true,  "car": "1f6fd0", "car_dark": "0d4a99", "vehicle": "BMW E46",          "enemy": "Toyota RAV4",       "vfx": "smoke" },
	"synthwave": { "name": "Synthwave",    "price": 400,  "offroad": "1a0b2e", "road": "241341", "edge": "ff2e97", "dash": "00f0ff", "stripes": true,  "car": "ffd319", "car_dark": "ff5f1f", "vehicle": "Lamborghini Countach", "enemy": "Sports coupes", "vfx": "taillight" },
	"track":     { "name": "Track Attack", "price": 550,  "offroad": "2e7d32", "road": "3a3a3a", "edge": "e03131", "dash": "ffffff", "stripes": false, "car": "e10600", "car_dark": "8a0400", "vehicle": "Open-wheel racer", "enemy": "Open-wheel racers", "vfx": "smoke" },
	"rally":     { "name": "Rally Rush",   "price": 700,  "offroad": "234a25", "road": "6b4f2a", "edge": "caa15a", "dash": "ffffff", "stripes": false, "car": "1565c0", "car_dark": "0d47a1", "vehicle": "Subaru Impreza",   "enemy": "Mitsubishi Lancer", "vfx": "smoke_dust" },
	"jdm":       { "name": "JDM",          "price": 850,  "offroad": "0d1b2a", "road": "23272e", "edge": "f72585", "dash": "4cc9f0", "stripes": true,  "car": "e6552a", "car_dark": "a83419", "vehicle": "Toyota Supra",     "enemy": "Mazda Miata",       "vfx": "smoke" },
	"jetski":    { "name": "Jetski Escape","price": 1000, "offroad": "e3c98f", "road": "1f7a8c", "edge": "9be7ff", "dash": "ffffff", "stripes": false, "car": "ff5252", "car_dark": "b71c1c", "vehicle": "Jetski",          "enemy": "Jetskis",           "vfx": "wake" },
	"sand":      { "name": "Sand Rally",   "price": 1150, "offroad": "c2954e", "road": "9c7a3c", "edge": "e8d6a0", "dash": "ffffff", "stripes": false, "car": "2e7d32", "car_dark": "1b5e20", "vehicle": "Rally buggy",      "enemy": "Porsche Safari",    "vfx": "smoke_sand" },
	"mud":       { "name": "Mud Sprint",   "price": 1300, "offroad": "3b5323", "road": "5b432a", "edge": "8a6d3b", "dash": "ffffff", "stripes": false, "car": "d32f2f", "car_dark": "9a1f1f", "vehicle": "Enduro bike",      "enemy": "Enduro bikes",      "vfx": "mud_bike" },
	"rainbow":   { "name": "Rainbow Lane", "price": 1500, "offroad": "0b0b2a", "road": "3a2f5e", "edge": "ff5ec7", "dash": "ffffff", "stripes": true,  "car": "ffeb3b", "car_dark": "fbc02d", "vehicle": "Kart",            "enemy": "Karts",             "vfx": "smoke" },
	"frostbite": { "name": "Frostbite Run","price": 1800, "offroad": "dfe9f0", "road": "8fa8bf", "edge": "5b86b0", "dash": "ffffff", "stripes": false, "car": "455a64", "car_dark": "263238", "vehicle": "Ford F-150",      "enemy": "Porsche Cayenne",   "vfx": "smoke_snow" },
}
# Themes removed from the store. Anyone who had bought one gets its price refunded
# on load, so no coins are ever lost to a retired theme.
const REMOVED_THEMES := { "wiped": 1500 }

# ---------------- challenges ----------------
const DEFAULT_STATS := {
	"total_time": 0.0, "total_distance": 0.0, "total_runs": 0,
	"best_run_time": 0.0, "best_distance": 0.0, "best_streak": 0,
	"best_no_coin_time": 0.0, "runs_over_2min": 0,
	"total_boost_time": 0.0, "total_coins": 0, "total_near_miss": 0, "total_smashed": 0,
	# one-time achievement flags (0/1), set the moment their condition is met
	"ach_grounded": 0, "ach_safe": 0, "ach_oily": 0, "ach_quick_end": 0,
	"ach_forks": 0, "ach_rampage": 0, "ach_collector": 0, "ach_saver": 0,
}
# Challenge ladders: five escalating stages per tracked statistic. Each stage is
# [goal, coin reward]; the challenge list itself is generated in _make_challenges
# (id = "<family>_<stage>", description formatted from the goal via _fmt_goal).
const CHALLENGE_LADDERS := [
	{ "id": "runs",  "stat": "total_runs",       "desc": "Complete %s runs",               "fmt": "int",  "stages": [[1, 20, "Finish your first run"], [10, 60], [25, 150], [60, 300], [150, 600]] },
	{ "id": "surv",  "stat": "best_run_time",    "desc": "Survive %s in a run",            "fmt": "time", "stages": [[60, 50], [120, 100], [180, 160], [300, 300], [480, 600]] },
	{ "id": "over2", "stat": "runs_over_2min",   "desc": "Finish %s runs over 2 minutes",  "fmt": "int",  "stages": [[1, 40, "Finish a run over 2 minutes"], [5, 120], [15, 250], [30, 450], [60, 800]] },
	{ "id": "ttime", "stat": "total_time",       "desc": "Drive %s in total",              "fmt": "time", "stages": [[900, 50], [2700, 120], [7200, 250], [18000, 450], [54000, 900]] },
	{ "id": "tdist", "stat": "total_distance",   "desc": "Drive %s km in total",           "fmt": "km",   "stages": [[200000, 60], [800000, 150], [2000000, 300], [4800000, 600], [12000000, 1200]] },
	{ "id": "rdist", "stat": "best_distance",    "desc": "Reach %s km in one run",         "fmt": "km",   "stages": [[16000, 30], [40000, 60], [96000, 160], [160000, 320], [280000, 700]] },
	{ "id": "boost", "stat": "total_boost_time", "desc": "Stay boosted for %s in total",   "fmt": "time", "stages": [[30, 40], [120, 100], [300, 220], [900, 450], [2400, 900]] },
	{ "id": "coins", "stat": "total_coins",      "desc": "Collect %s coins in total",      "fmt": "int",  "stages": [[100, 30], [500, 80], [2000, 200], [8000, 450], [25000, 1000]] },
	{ "id": "nmiss", "stat": "total_near_miss",  "desc": "Score %s near misses",           "fmt": "int",  "stages": [[10, 30], [50, 80], [200, 200], [800, 500], [2500, 1000]] },
	{ "id": "smash", "stat": "total_smashed",    "desc": "Destroy %s obstacles",           "fmt": "int",  "stages": [[5, 40], [25, 100], [100, 250], [400, 600], [1200, 1200]] },
]
# One-time feats layered on top of the ladders.
const CHALLENGE_SPECIALS := [
	{ "id": "ascetic",     "desc": "Drive 30 s without collecting a coin",                 "stat": "best_no_coin_time", "goal": 30, "reward": 90 },
	{ "id": "grounded",    "desc": "Drive 3 km in a run without taking an optional ramp",  "stat": "ach_grounded",      "goal": 1,  "reward": 150 },
	{ "id": "untouchable", "desc": "Drive 2 km in a run with zero near misses",            "stat": "ach_safe",          "goal": 1,  "reward": 120 },
	{ "id": "slippery",    "desc": "Hit 3 oil slicks in one run",                          "stat": "ach_oily",          "goal": 1,  "reward": 100 },
	{ "id": "any_percent", "desc": "Crash within 3 seconds of setting off",                "stat": "ach_quick_end",     "goal": 1,  "reward": 30 },
	{ "id": "fork_vet",    "desc": "Pass 5 road splits in one run",                        "stat": "ach_forks",         "goal": 1,  "reward": 150 },
	{ "id": "rampage",     "desc": "Smash 3 obstacles during a single boost",              "stat": "ach_rampage",       "goal": 1,  "reward": 200 },
	{ "id": "collector",   "desc": "Own 3 paint themes",                                   "stat": "ach_collector",     "goal": 1,  "reward": 150 },
	{ "id": "saver",       "desc": "Hold 1500 coins at once",                              "stat": "ach_saver",         "goal": 1,  "reward": 200 },
]
var CHALLENGES: Array[Dictionary] = _make_challenges()


static func _make_challenges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fam in CHALLENGE_LADDERS:
		var stages: Array = fam["stages"]
		for si in range(stages.size()):
			var st: Array = stages[si]
			var goal := float(st[0])
			# a stage may carry its own wording as a third entry (e.g. the goal-1
			# stages, where "Complete 1 runs" would read wrong)
			var desc := String(st[2]) if st.size() > 2 else String(fam["desc"]) % _fmt_goal(goal, String(fam["fmt"]))
			out.append({
				"id": "%s_%d" % [fam["id"], si + 1],
				"desc": desc,
				"stat": fam["stat"], "goal": goal, "reward": int(st[1]),
			})
	for sp in CHALLENGE_SPECIALS:
		out.append(sp)
	return out


# Pretty goal for a challenge description: km from world px, seconds into
# s / min / h at natural breakpoints, else a plain count.
static func _fmt_goal(goal: float, fmt: String) -> String:
	match fmt:
		"km":
			return str(int(roundf(goal / (PX_PER_METER * 1000.0))))
		"time":
			if goal >= 3600.0:
				return "%d h" % int(goal / 3600.0)
			if goal >= 120.0:
				return "%d min" % int(goal / 60.0)
			return "%d s" % int(goal)
	return str(int(goal))

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

# Per-run tallies for the challenge/achievement system, committed into the
# persistent stats in _game_over (so abandoning a run mid-way commits nothing,
# same as the time/distance stats).
var _run_near_miss := 0
var _run_smashed := 0
var _run_boost_time := 0.0
var _run_oil := 0
var _run_forks := 0
var _run_opt_jumps := 0            # optional ramps taken (gap-escape ramps excluded)
var _boost_chain := 0              # obstacles smashed during the CURRENT boost
var _boost_chain_best := 0
var _was_in_branch := false        # edge detector for counting traversed splits

var col_offroad: Color
var col_road: Color
var col_edge: Color
var col_dash: Color
var col_car: Color
var col_car_dark: Color
var col_deco: Color                # tint for primitive background props
var _theme_stripes := true         # does the current theme paint a centre line?
var _theme_rainbow := false        # Rainbow Lane paints the road surface itself as a rainbow
var _theme_vfx := "smoke"          # which trail effect the car leaves (see VFX / _emit_trail)

# Convention-loaded theme art (null = use the primitive fallback). Mirrors audio.
var _tex_road: Texture2D
var _tex_bg: Texture2D
var _tex_car: Texture2D
var _tex_enemy: Array[Texture2D] = []
var _tex_deco: Array[Texture2D] = []
var _tex_logo: Texture2D           # menu logo art (slot "logo"); null = drawn fallback
# Built once, theme-independent: the Rainbow Lane stripe palette (see _fill_rainbow).
var _tex_rainbow: ImageTexture
# Cached triangle-strip index buffer for the road-band renderer (see _strip_indices).
var _strip_idx := PackedInt32Array()

# Live collision half-extents. Default to the canonical footprint; once a sprite is
# loaded they shrink to its opaque content so collisions ignore transparent pixels
# (see _load_theme_art / _content_half). Always <= COL_HALF_*, so every generation
# fairness guarantee (which assumes the canonical box) still holds.
var _pl_hw := COL_HALF_W
var _pl_hh := COL_HALF_H
var _enemy_col: Array = []         # per enemy-sprite collision half-extents (Vector2)
# Aspect-true draw sizes: sprites are never stretched to the canonical boxes, they
# are uniformly scaled to fit them (integer pixel scale when close — see _fit_sprite).
var _car_size := Vector2(CAR_W, CAR_H)
var _enemy_size: Array = []        # per enemy-sprite draw size (Vector2)

var _pt_d := PackedFloat32Array()
var _pt_x := PackedFloat32Array()
var _track_frontier_d := 0.0
var _track_last_x := ROAD_CENTER_X
var _bias := 0.0
# responsive layout: gameplay fills the real viewport height (width stays 720 via
# the "expand" stretch), so the game fits every phone aspect (see _relayout)
var _view_w := SCREEN_W
var _view_h := SCREEN_H
var _car_y := SCREEN_H - CAR_BOTTOM
var _gen_ahead := 1400.0           # how far ahead to generate (covers the visible road)
var _straight_run := 0.0           # distance since the road last took a real bend
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
# Tail-light streak history: one sample per frame of (left-lamp wx, right-lamp wx,
# wd). Drawn as two fading polylines along the car's real path (see _draw_taillights).
var _taillights: Array[Vector3] = []
# Wake history (jetski): one (hull wx, unused, wd) sample per frame, drawn as two
# spreading foam streaks along the real path (see _draw_wake).
var _wake: Array[Vector3] = []
# Oil-groove history (mud enduro bike): one (rear-wheel wx, unused, wd) sample per
# frame, drawn as a SINGLE dark oily line along the real path (see _draw_oil_trail).
var _oil_trail: Array[Vector3] = []
var _oil_timer := 0.0
var _air_timer := 0.0
var _boost_timer := 0.0
var _boost_warned := false         # has the "boost ending" cue fired for this boost?
var _crash_timer := 0.0
var _shake_t := 0.0                # crash screen-shake time remaining
var _count_timer := 0.0
var _popups: Array = []
var _ui_font: Font
var _menu_time := 0.0              # attract-mode clock (drives the weave + logo wobble)

# combo chain state (see the COMBO constants)
var _combo := 0                    # actions in the current chain (1 = chain armed)
var _combo_timer := 0.0            # time left in the window; boost freezes it
var _combo_flash := 0.0            # 1 -> 0 pulse driving the chain-bump ring/UI pop
# lucky run (rolled once per run in _start_run)
var _lucky_run := false

# ---------------- audio ----------------
# Convention-based, like the art slots: drop a file at res://audio/<name>.ogg
# (or .wav/.mp3) and it plays automatically. Missing files are a silent no-op,
# so the game runs identically with or without audio assets present.
# Engine is two crossfaded loops (engine_low/engine_high) rather than one
# loop with a wide pitch shift, so going fast changes the engine's timbre
# instead of just speeding up its pitch — avoids the droney/chipmunk effect.
# Expected slots: crash, coin, land, near_miss, jump, smash, boost_end,
# oil_squeal, horn, purchase, challenge, combo, ui_tap, engine_low, engine_high.
var _sfx_crash: AudioStreamPlayer
var _sfx_coin: AudioStreamPlayer
var _sfx_land: AudioStreamPlayer
var _sfx_near_miss: AudioStreamPlayer
var _sfx_jump: AudioStreamPlayer
var _sfx_smash: AudioStreamPlayer
var _sfx_boost_end: AudioStreamPlayer
var _sfx_oil: AudioStreamPlayer
var _sfx_beep: AudioStreamPlayer
var _sfx_purchase: AudioStreamPlayer
var _sfx_challenge: AudioStreamPlayer
var _sfx_combo: AudioStreamPlayer
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
var _menu_blur: ColorRect          # slight screen blur between the attract drive and the menus
var _logo: Control                 # the wobbling title logo (see _draw_logo)
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
	_ui_font = _load_ui_font()
	_micro_noise.frequency = 0.01
	_load_save()
	_apply_theme(selected)
	_build_audio()
	_build_ui()
	_relayout()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_relayout)
	_goto_menu()


# Fit gameplay + UI to the device's screen aspect. Width is locked to 720 by the
# "expand" stretch; the height is whatever that yields, so the car drives a fixed
# distance up from the real bottom, we generate enough road to fill the view, and
# the menu panels are vertically centred (the HUD stays anchored to the top).
func _relayout() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	_view_w = vp.x
	_view_h = vp.y
	_car_y = _view_h - CAR_BOTTOM
	_gen_ahead = maxf(1400.0, _car_y + 200.0)
	# centre the menu panels in whatever extra space the device aspect gives us;
	# never negative, so on a screen shorter than the design height the menu tops
	# stay on-screen rather than clipping. The HUD only shifts horizontally.
	var off := Vector2(maxf(0.0, (_view_w - SCREEN_W) * 0.5), maxf(0.0, (_view_h - SCREEN_H) * 0.5))
	for p in [_menu, _store, _challenges, _pause, _gameover]:
		if p != null:
			p.position = off
	if _hud != null:
		_hud.position = Vector2(off.x, 0.0)
	queue_redraw()


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
			elif REMOVED_THEMES.has(k):
				# retired theme: give the purchase price back (idempotent — the theme
				# is dropped from owned, so the next save stops this repeating)
				coins_total += int(REMOVED_THEMES[k])
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
	_theme_rainbow = id == "rainbow"
	_theme_vfx = String(t.get("vfx", "smoke"))
	# Rainbow Lane is the road itself (a rainbow surface), so it paints no centre line
	_theme_stripes = bool(t.get("stripes", true)) and not _theme_rainbow
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
# The numbered scan covers a fixed range and COLLECTS whatever exists, so a series
# with gaps (e.g. only enemy_1.png) still loads instead of stopping at the first
# missing index.
func _load_tex_list(theme_id: String, slot: String) -> Array[Texture2D]:
	for tid in [theme_id, "default"]:
		var out: Array[Texture2D] = []
		var single := _load_tex_exact(tid, slot)
		if single != null:
			out.append(single)
		for i in range(ART_LIST_MAX):
			var t := _load_tex_exact(tid, "%s_%d" % [slot, i])
			if t != null:
				out.append(t)
		if out.size() > 0:
			return out
	return []


func _load_theme_art(id: String) -> void:
	_tex_road = _load_tex(id, "road")
	_tex_bg = _load_tex(id, "background")
	_tex_car = _load_tex(id, "car")
	_tex_enemy = _load_tex_list(id, "enemy")
	_tex_deco = _load_tex_list(id, "deco")
	_tex_logo = _load_tex(id, "logo")
	# Derive the aspect-true draw size of every vehicle sprite, then its collision
	# box from the opaque content WITHIN that size, clamped down to the canonical
	# footprint so generation fairness is preserved (see _pl_hw note).
	_pl_hw = COL_HALF_W
	_pl_hh = COL_HALF_H
	_car_size = Vector2(CAR_W, CAR_H)
	if _tex_car != null:
		_car_size = _fit_sprite(_tex_car, CAR_W, CAR_H)
		var e := _content_half(_tex_car, _car_size.x, _car_size.y)
		_pl_hw = minf(COL_HALF_W, e.x)
		_pl_hh = minf(COL_HALF_H, e.y)
	_enemy_col.clear()
	_enemy_size.clear()
	for t in _tex_enemy:
		var esz := _fit_sprite(t, TRAFFIC_W, TRAFFIC_H)
		_enemy_size.append(esz)
		var ee := _content_half(t, esz.x, esz.y)
		_enemy_col.append(Vector2(minf(TRAFFIC_W * 0.5, ee.x), minf(TRAFFIC_H * 0.5, ee.y)))


# Draw size for a vehicle sprite: one uniform scale that fits the canonical box —
# never a stretch, whatever the texture's own aspect ratio is. The scale snaps to
# the nearest integer when it's close (the shipped 24x40..47 sprites land on an
# exact 2x), so nearest-filtered art pixels stay even instead of shimmering.
func _fit_sprite(tex: Texture2D, box_w: float, box_h: float) -> Vector2:
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Vector2(box_w, box_h)
	var s := minf(box_w / ts.x, box_h / ts.y)
	var snap := roundf(s)
	if snap >= 1.0 and absf(snap - s) <= s * 0.2:
		s = snap
	return ts * s


# Half-extents (world px) of a sprite's OPAQUE content, mapped into the on-screen
# draw rect (full_w x full_h). Transparent margins are excluded, so a hitbox built
# from this follows the visible vehicle rather than its bounding rectangle. Falls
# back to the full half-rect if the image can't be inspected.
func _content_half(tex: Texture2D, full_w: float, full_h: float) -> Vector2:
	var fallback := Vector2(full_w * 0.5, full_h * 0.5)
	if tex == null:
		return fallback
	var img := tex.get_image()
	if img == null:
		return fallback
	if img.is_compressed():
		img = img.duplicate()
		if img.decompress() != OK:
			return fallback
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return fallback
	var minx := w
	var maxx := -1
	var miny := h
	var maxy := -1
	var step := maxi(1, int(maxf(float(w), float(h)) / 64.0))   # subsample large sprites for speed
	for yy in range(0, h, step):
		for xx in range(0, w, step):
			if img.get_pixel(xx, yy).a > 0.30:
				minx = mini(minx, xx)
				maxx = maxi(maxx, xx)
				miny = mini(miny, yy)
				maxy = maxi(maxy, yy)
	if maxx < 0:
		return fallback   # fully transparent — keep the full box rather than a zero one
	var fx := clampf(float(maxx - minx + step) / float(w), 0.15, 1.0)
	var fy := clampf(float(maxy - miny + step) / float(h), 0.15, 1.0)
	return Vector2(full_w * 0.5 * fx, full_h * 0.5 * fy)


func _enemy_half(idx: int) -> Vector2:
	if _enemy_col.is_empty():
		return Vector2(TRAFFIC_W * 0.5, TRAFFIC_H * 0.5)
	return _enemy_col[idx % _enemy_col.size()]


# Convention-loaded UI font (DotGothic16 if present). load_dynamic_font means it
# works at runtime with no editor import. Antialiasing is left ON (grayscale): with
# it off, this pixel font's glyphs snap unevenly at non-native sizes and the text
# looks lumpy/inconsistent — AA keeps letter sizing and spacing uniform.
func _load_ui_font() -> Font:
	for nm in FONT_NAMES:
		for ext in FONT_EXTS:
			var p := "%s%s.%s" % [FONT_DIR, nm, ext]
			if FileAccess.file_exists(p):
				var f := FontFile.new()
				if f.load_dynamic_font(p) == OK:
					f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
					f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
					return f
	return ThemeDB.fallback_font


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
	_sfx_boost_end = _make_player("boost_end", "Master", -3.0)
	_sfx_oil = _make_player("oil_squeal", "Master", -3.0)
	_sfx_beep = _make_player("horn", "Master", -6.0)
	_sfx_purchase = _make_player("purchase", "Master", -3.0)
	_sfx_challenge = _make_player("challenge", "Master", -2.0)
	_sfx_combo = _make_player("combo", "Master", -3.0)
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
# Bubbly pixel button: a rounded-pixel slab floating over its own base and soft
# shadow, gently bobbing on a per-button phase. PRESS & HOLD sinks the slab onto
# the base (the shadow tightens underneath); PRESS & COMPLETE (release inside)
# fires the action with a squash-and-pop bounce; release outside just floats it
# back up — a visible cancel. Built on BaseButton, so all press/disable/signal
# behaviour is stock and every pixel of the look is drawn here.
class PixelButton extends BaseButton:
	const COL_OUTLINE := Color("141414")
	const COL_SHADOW := Color(0.0, 0.0, 0.0, 0.28)
	const LIFT := 7.0                # how high the slab floats above its base

	var text := "":
		set(v):
			text = v
			queue_redraw()
	var base_col := Color("e8433f"):
		set(v):
			base_col = v
			queue_redraw()
	var font: Font
	var font_size := 40

	var _t := randf() * TAU          # bob phase — randomised so buttons never sync
	var _hold := 0.0                 # 0 = floating, 1 = fully sunk (press & hold)
	var _pop := 0.0                  # 1 -> 0 after a completed press (the bounce)

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE   # SPACE steers the car; it must never re-fire a button

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t += delta
		_hold = move_toward(_hold, 1.0 if button_pressed else 0.0, delta * 14.0)
		_pop = maxf(_pop - delta * 3.2, 0.0)
		queue_redraw()

	func _pressed() -> void:
		_pop = 1.0   # press completed: bounce

	func _draw() -> void:
		var sz := size
		var bob := 0.0 if disabled else sin(_t * 2.2) * 3.0
		var squash := sin(_pop * PI)
		# squash about the centre: wider and flatter at the bounce's peak
		draw_set_transform(sz * 0.5 + Vector2(0.0, bob), 0.0, Vector2(1.0 + 0.06 * squash, 1.0 - 0.08 * squash))
		var w := sz.x
		var h := sz.y - LIFT
		var sink := _hold * (LIFT - 1.0)
		var slab := Rect2(-w * 0.5, -sz.y * 0.5 + sink, w, h)
		var base := Rect2(-w * 0.5, -sz.y * 0.5 + LIFT, w, h)
		var body := base_col
		if disabled:
			body = base_col.darkened(0.25)
		elif is_hovered():
			body = base_col.lightened(0.08)
		# floating shadow: pinned to the panel (counter-bob) and tightening as the
		# slab sinks, so height reads even before anything moves
		var sh := base
		sh.position += Vector2(4.0, 9.0 - bob) * (1.0 - _hold * 0.55)
		_bubble(sh, COL_SHADOW)
		_bubble(base.grow(3.0), COL_OUTLINE)
		_bubble(base, base_col.darkened(0.5))
		_bubble(slab.grow(3.0), COL_OUTLINE)
		_bubble(slab, body)
		# top light + a corner shine speck sell the "bubble"
		draw_rect(Rect2(slab.position.x + 12.0, slab.position.y + 4.0, slab.size.x - 24.0, 5.0), body.lightened(0.33))
		draw_rect(Rect2(slab.position.x + 12.0, slab.position.y + 12.0, 14.0, 5.0), Color(1, 1, 1, 0.5))
		if font != null and text != "":
			var tcol := Color(1, 1, 1, 0.75 if disabled else 0.97)
			var slab_cy := slab.position.y + slab.size.y * 0.5
			var by := slab_cy - font.get_height(font_size) * 0.5 + font.get_ascent(font_size)
			draw_string(font, Vector2(-w * 0.5 + 2.0, by + 3.0), text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, Color(0, 0, 0, 0.55))
			draw_string(font, Vector2(-w * 0.5, by), text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, tcol)

	# A rect with stepped two-radius corners — round enough to read bubbly, chunky
	# enough to stay pixel-art.
	func _bubble(r: Rect2, col: Color) -> void:
		var c1 := minf(10.0, r.size.y * 0.24)
		var c2 := minf(4.0, c1 * 0.5)
		draw_rect(Rect2(r.position.x + c1, r.position.y, r.size.x - 2.0 * c1, c2), col)
		draw_rect(Rect2(r.position.x + c2, r.position.y + c2, r.size.x - 2.0 * c2, c1 - c2), col)
		draw_rect(Rect2(r.position.x, r.position.y + c1, r.size.x, r.size.y - 2.0 * c1), col)
		draw_rect(Rect2(r.position.x + c2, r.end.y - c1, r.size.x - 2.0 * c2, c1 - c2), col)
		draw_rect(Rect2(r.position.x + c1, r.end.y - c2, r.size.x - 2.0 * c1, c2), col)


# The slight blur between the attract-mode drive and the menu UI: a full-screen
# ColorRect whose shader samples the already-drawn frame (the world lives on the
# canvas below this CanvasLayer) with a small 9-tap gaussian, then pulls it a
# touch toward a dark tone — softened and dimmed just enough that the pixel-art
# drive reads as a backdrop and the white UI text stays readable on any theme.
func _build_menu_blur(layer: CanvasLayer) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur_px = 2.4;
uniform float scrim = 0.30;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * blur_px;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * 0.22;
	c += texture(screen_tex, SCREEN_UV + vec2( px.x, 0.0)).rgb * 0.11;
	c += texture(screen_tex, SCREEN_UV + vec2(-px.x, 0.0)).rgb * 0.11;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0,  px.y)).rgb * 0.11;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, -px.y)).rgb * 0.11;
	c += texture(screen_tex, SCREEN_UV + vec2( px.x,  px.y)).rgb * 0.085;
	c += texture(screen_tex, SCREEN_UV + vec2( px.x, -px.y)).rgb * 0.085;
	c += texture(screen_tex, SCREEN_UV + vec2(-px.x,  px.y)).rgb * 0.085;
	c += texture(screen_tex, SCREEN_UV + vec2(-px.x, -px.y)).rgb * 0.085;
	COLOR = vec4(mix(c, vec3(0.03, 0.03, 0.05), scrim), 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_menu_blur = ColorRect.new()
	_menu_blur.material = mat
	_menu_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_menu_blur)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_build_menu_blur(layer)   # first child: blurs the world, sits under every panel

	_menu = _make_panel(layer)
	# the title logo: art slot "logo" if shipped, else the drawn wordmark — either
	# way it hangs on this control, which _update_attract rocks gently (the wobble)
	_logo = Control.new()
	_logo.position = Vector2(40, 96)
	_logo.size = Vector2(SCREEN_W - 80.0, 260)
	_logo.pivot_offset = _logo.size * 0.5
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.draw.connect(_draw_logo)
	_menu.add_child(_logo)
	_menu_coins = _make_label(_menu, "Coins: 0", Vector2(0, 420), Vector2(SCREEN_W, 60), 40)
	_make_button(_menu, "PLAY", Vector2(180, 540), Vector2(360, 96), 46).pressed.connect(_start_run)
	_make_button(_menu, "STORE", Vector2(180, 656), Vector2(360, 96), 46, Color("f2a007")).pressed.connect(_open_store)
	_make_button(_menu, "CHALLENGES", Vector2(180, 772), Vector2(360, 96), 38, Color("2fa7c7")).pressed.connect(_open_challenges)
	_make_label(_menu, "Hold anywhere to steer left, release to drift right", Vector2(20, 920), Vector2(SCREEN_W - 40, 60), 26)

	_store = _make_panel(layer)
	_make_label(_store, "STORE", Vector2(0, 50), Vector2(SCREEN_W, 80), 56)
	_store_coins = _make_label(_store, "Coins: 0", Vector2(0, 140), Vector2(SCREEN_W, 50), 34)
	var sy := 210.0
	for id in THEME_ORDER:
		var b := _make_button(_store, "", Vector2(70, sy), Vector2(580, 74), 24, Color("3a4252"))
		b.pressed.connect(_on_theme_pressed.bind(id))
		_theme_buttons[id] = b
		sy += 84.0
	_make_button(_store, "BACK", Vector2(180, sy + 6.0), Vector2(360, 78), 36, Color("5a6474")).pressed.connect(_goto_menu)

	_challenges = _make_panel(layer)
	_make_label(_challenges, "CHALLENGES", Vector2(0, 50), Vector2(SCREEN_W, 80), 56)
	# the list far outgrows the screen now (10 five-stage ladders + the one-time
	# feats), so it lives in a ScrollContainer instead of fixed label rows
	var sc := ScrollContainer.new()
	sc.position = Vector2(40, 150)
	sc.size = Vector2(SCREEN_W - 80, 910)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_challenges.add_child(sc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	sc.add_child(vb)
	for i in range(CHALLENGES.size()):
		var lbl := Label.new()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(SCREEN_W - 120, 74)
		lbl.add_theme_font_size_override("font_size", 24)
		if _ui_font != null:
			lbl.add_theme_font_override("font", _ui_font)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(lbl)
		_challenge_labels.append(lbl)
	_make_button(_challenges, "BACK", Vector2(180, 1090), Vector2(360, 90), 40, Color("5a6474")).pressed.connect(_goto_menu)

	_hud = _make_panel(layer)
	_hud_score = _make_label(_hud, "0", Vector2(0, 36), Vector2(SCREEN_W, 80), 64)
	_hud_coins = _make_label(_hud, "Coins: 0", Vector2(0, 124), Vector2(SCREEN_W, 50), 34)
	_hud_prompt = _make_label(_hud, "Tap to begin\nHold to steer", Vector2(0, 540), Vector2(SCREEN_W, 200), 52)
	_make_button(_hud, "II", Vector2(600, 30), Vector2(96, 72), 40, Color("5a6474")).pressed.connect(_pause_game)

	_pause = _make_panel(layer)
	_make_label(_pause, "PAUSED", Vector2(0, 360), Vector2(SCREEN_W, 90), 64)
	_make_button(_pause, "RESUME", Vector2(180, 520), Vector2(360, 96), 46, Color("43b04a")).pressed.connect(_resume)
	_make_button(_pause, "RESTART", Vector2(180, 636), Vector2(360, 96), 46, Color("f2a007")).pressed.connect(_start_run)
	_make_button(_pause, "MENU", Vector2(180, 752), Vector2(360, 96), 40, Color("5a6474")).pressed.connect(_goto_menu)

	_gameover = _make_panel(layer)
	_make_label(_gameover, "GAME OVER", Vector2(0, 280), Vector2(SCREEN_W, 90), 64)
	_go_score = _make_label(_gameover, "Score: 0", Vector2(0, 400), Vector2(SCREEN_W, 60), 40)
	_go_coins = _make_label(_gameover, "Coins earned: 0", Vector2(0, 468), Vector2(SCREEN_W, 60), 36)
	_go_challenge = _make_label(_gameover, "", Vector2(30, 540), Vector2(SCREEN_W - 60, 90), 28)
	_make_button(_gameover, "RESTART", Vector2(180, 660), Vector2(360, 100), 48).pressed.connect(_start_run)
	_make_button(_gameover, "MENU", Vector2(180, 790), Vector2(360, 90), 40, Color("5a6474")).pressed.connect(_goto_menu)


# The menu logo, drawn on the _logo control. A shipped res://art/<theme>/logo.png
# (or art/default/logo.png) is used as-is, fitted with its aspect kept; otherwise a
# stylized wordmark is drawn: "TWISTY" as chunky red letters with a thick dark
# outline, each rocking on its own beat, over "ROADS" as asphalt-grey letters each
# carrying a yellow centre-line dash — tiny roads. The whole control also sways
# (rotation set in _update_attract): the logo's slight wobble.
func _draw_logo() -> void:
	if _tex_logo != null:
		var ts := _tex_logo.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			var s := minf(_logo.size.x / ts.x, _logo.size.y / ts.y)
			var sz := ts * s
			_logo.draw_texture_rect(_tex_logo, Rect2((_logo.size - sz) * 0.5, sz), false)
		return
	if _ui_font == null:
		return
	_draw_logo_word("TWISTY", 118, 112.0, 6.0, Color("e02828"), Color("141414"), true)
	_draw_logo_word("ROADS", 88, 222.0, 12.0, Color("9aa1ab"), Color("17181c"), false)


# One line of the drawn wordmark, centred in the logo control. jumble=true gives
# each letter a fixed alternating tilt plus a slow rock and bob (the playful red
# line); jumble=false keeps the letters near-still with a road dash through each.
func _draw_logo_word(word: String, fs: int, baseline: float, tracking: float, fill: Color, outline: Color, jumble: bool) -> void:
	var widths := PackedFloat32Array()
	var total := 0.0
	for i in range(word.length()):
		var w := _ui_font.get_string_size(word[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total += w
	total += tracking * float(word.length() - 1)
	var x := (_logo.size.x - total) * 0.5
	for i in range(word.length()):
		var ch := word[i]
		var cw := widths[i]
		var rot := 0.0
		var bob := 0.0
		if jumble:
			rot = (0.055 if i % 2 == 0 else -0.05) + sin(_menu_time * 2.3 + float(i) * 1.7) * 0.045
			bob = sin(_menu_time * 2.9 + float(i) * 1.1) * 3.0
		else:
			bob = sin(_menu_time * 2.1 + float(i) * 0.9) * 1.4
		_logo.draw_set_transform(Vector2(x + cw * 0.5, baseline + bob), rot, Vector2.ONE)
		var org := Vector2(-cw * 0.5, 0.0)
		# every pass is drawn 4x on a 2px lattice: DotGothic's thin strokes become
		# the fat slab letters the logo wants (a cheap faux-bold)
		var bold := [Vector2(0, 0), Vector2(2, 0), Vector2(0, 2), Vector2(2, 2)]
		# chunky drop shadow, an 8-direction outline, then the fill
		for bd: Vector2 in bold:
			_logo.draw_char(_ui_font, org + Vector2(8, 8) + bd, ch, fs, Color(0, 0, 0, 0.8))
		for off in [Vector2(-5, 0), Vector2(5, 0), Vector2(0, -5), Vector2(0, 5),
				Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4)]:
			for bd: Vector2 in bold:
				_logo.draw_char(_ui_font, org + off + bd, ch, fs, outline)
		for bd: Vector2 in bold:
			_logo.draw_char(_ui_font, org + bd, ch, fs, fill)
		if jumble:
			# a white speck of light on each letter's shoulder
			_logo.draw_rect(Rect2(org.x + cw * 0.16, -fs * 0.62, cw * 0.24, 6.0), Color(1, 1, 1, 0.85))
		else:
			# the yellow centre-line dash that makes each grey letter a tiny road
			_logo.draw_rect(Rect2(org.x + cw * 0.22, -fs * 0.34, cw * 0.5, 5.0), Color("f2c14e"))
		x += cw + tracking
	_logo.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	if _ui_font != null:
		l.add_theme_font_override("font", _ui_font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _make_button(parent: Control, text: String, pos: Vector2, size: Vector2, fsize: int, col := Color("e8433f")) -> PixelButton:
	var b := PixelButton.new()
	b.font = _ui_font
	b.font_size = fsize
	b.text = text
	b.base_col = col
	b.position = pos
	b.size = size
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
	_menu_blur.visible = _in_menu_state()


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
	_boost_warned = false
	_crash_timer = 0.0
	_shake_t = 0.0
	position = Vector2.ZERO
	_count_timer = 0.0
	_bias = 0.0
	_coins.clear()
	_hazards.clear()
	_decos.clear()
	_tire_marks.clear()
	_particles.clear()
	_boom.clear()
	_popups.clear()
	_taillights.clear()
	_wake.clear()
	_oil_trail.clear()
	_combo = 0
	_combo_timer = 0.0
	_combo_flash = 0.0
	_lucky_run = false
	_run_near_miss = 0
	_run_smashed = 0
	_run_boost_time = 0.0
	_run_oil = 0
	_run_forks = 0
	_run_opt_jumps = 0
	_boost_chain = 0
	_boost_chain_best = 0
	_was_in_branch = false
	_pattern_queue.clear()
	_coin_frontier_d = 0.0
	_hazard_frontier_d = 0.0
	_deco_frontier_d = 0.0
	_branches.clear()
	_branch_frontier_d = 0.0
	# first fork comes soon after the (now short) intro, so the first real decision
	# lands within a few seconds of the run starting
	_next_branch_d = INTRO_DIST + 500.0
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
	_lucky_run = randf() < LUCKY_CHANCE
	_engine_low.stop()
	_engine_high.stop()
	_ensure_track(distance + _gen_ahead)
	_ensure_branches(distance + _gen_ahead)
	_ensure_hazards(distance + _gen_ahead)
	_ensure_coins(distance + _gen_ahead)
	_ensure_decos(distance + _gen_ahead)
	_hud_score.text = "0"
	_hud_coins.text = "Coins: 0"
	_hud_prompt.visible = false   # the start prompt is painted on the road (see _draw_track_hints)
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
	_shake_t = SHAKE_TIME
	Input.vibrate_handheld(220)
	_spawn_explosion(car_x, distance)   # world-anchored: plays where the car hit
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
	stats["total_boost_time"] = float(stats["total_boost_time"]) + _run_boost_time
	stats["total_coins"] = int(stats["total_coins"]) + session_coins
	stats["total_near_miss"] = int(stats["total_near_miss"]) + _run_near_miss
	stats["total_smashed"] = int(stats["total_smashed"]) + _run_smashed
	# one-time feats earned this run
	if distance >= 24000.0 and _run_opt_jumps == 0:
		stats["ach_grounded"] = 1
	if distance >= 16000.0 and _run_near_miss == 0:
		stats["ach_safe"] = 1
	if _run_oil >= 3:
		stats["ach_oily"] = 1
	if time_alive < 3.0:
		stats["ach_quick_end"] = 1
	if _run_forks >= 5:
		stats["ach_forks"] = 1
	if _boost_chain_best >= 3:
		stats["ach_rampage"] = 1
	if owned.size() >= 3:
		stats["ach_collector"] = 1
	coins_total += session_coins
	if coins_total >= 1500:
		stats["ach_saver"] = 1
	var newly := _evaluate_challenges()
	_save()
	_go_score.text = "Distance: %.2f KM" % _dist_km()
	_go_coins.text = "Coins earned: %d%s" % [session_coins, "   (LUCKY RUN 2x)" if _lucky_run else ""]
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
			if owned.size() >= 3:
				stats["ach_collector"] = 1
			if not _evaluate_challenges().is_empty():
				_play_sfx(_sfx_challenge)
			_save()
			_play_sfx(_sfx_purchase)
	_refresh_store()
	queue_redraw()


func _refresh_store() -> void:
	_store_coins.text = "Coins: %d" % coins_total
	for id in THEME_ORDER:
		var b: PixelButton = _theme_buttons[id]
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
		# the equipped theme's row sits gold instead of greying out
		b.base_col = Color("caa53d") if selected == id else Color("3a4252")


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
	elif _in_menu_state():
		_update_attract(delta)
		queue_redraw()


func _in_menu_state() -> bool:
	return state == State.MENU or state == State.STORE or state == State.CHALLENGES


# The menus' living background: a demo driver cruising the selected theme's road,
# weaving lazily from one edge to the other (two blended sines, so the sway never
# looks metronomic). It advances the same world the game plays in — track, forks,
# decorations, trail VFX — but seeds no hazards or coins, and _reset_world wipes
# it all when a real run starts.
func _update_attract(delta: float) -> void:
	_menu_time += delta
	time_alive += delta            # drives the shared shimmer/pulse animations
	var prev := car_x
	distance += MENU_DRIVE_SPEED * delta
	_ensure_track(distance + _gen_ahead)
	_ensure_branches(distance + _gen_ahead)
	_ensure_decos(distance + _gen_ahead)
	_drop_old()
	var sway := sin(_menu_time * 1.1) * 0.8 + sin(_menu_time * 0.47 + 1.3) * 0.2
	var target := road_center(distance) + sway * maxf(road_half_width(distance) - COL_HALF_W - 30.0, 0.0) * 0.85
	target = _clamp_to_nearest_lane(distance, target)
	car_x = lerpf(car_x, target, clampf(MENU_SWAY_SMOOTH * delta, 0.0, 1.0))
	lateral_velocity = clampf((car_x - prev) / maxf(delta, 0.0001), -STEER_SPEED, STEER_SPEED)
	camera_x = lerpf(camera_x, car_x, clampf(CAM_FOLLOW * 0.7 * delta, 0.0, 1.0))
	camera_x = clampf(camera_x, car_x - CAM_MAX_OFF, car_x + CAM_MAX_OFF)
	_emit_trail(delta)
	_update_particles(delta)
	# the logo's slight wobble: a slow sway plus per-letter life inside _draw_logo
	if _logo != null and _menu.visible:
		_logo.rotation = sin(_menu_time * 1.7) * 0.04
		_logo.queue_redraw()


func _update_crash(delta: float) -> void:
	_crash_timer -= delta
	_update_boom(delta)
	_update_particles(delta)
	# brief screen shake: jolt the world node, decaying quadratically to rest
	if _shake_t > 0.0:
		_shake_t = maxf(_shake_t - delta, 0.0)
		var k := _shake_t / SHAKE_TIME
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_AMP * k * k
		if _shake_t <= 0.0:
			position = Vector2.ZERO
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

	_ensure_track(distance + _gen_ahead)
	_ensure_branches(distance + _gen_ahead)
	_ensure_hazards(distance + _gen_ahead)
	_ensure_coins(distance + _gen_ahead)
	_ensure_decos(distance + _gen_ahead)
	_drop_old()

	# count each fork/shoulder the car makes it through (rear edge crossed alive)
	var in_branch_now := _in_branch(distance)
	if _was_in_branch and not in_branch_now:
		_run_forks += 1
	_was_in_branch = in_branch_now

	# camera follows the car (with a little look-ahead toward the upcoming road)
	var look := _nearest_lane_center(distance + CAM_LOOKAHEAD, car_x)
	var cam_target := lerpf(car_x, look, CAM_LOOK_W)
	camera_x = lerpf(camera_x, cam_target, clampf(CAM_FOLLOW * delta, 0.0, 1.0))
	camera_x = clampf(camera_x, car_x - CAM_MAX_OFF, car_x + CAM_MAX_OFF)

	var airborne := _air_timer > 0.0
	if _oil_timer > 0.0:
		_oil_timer -= delta
	if _boost_timer > 0.0:
		_run_boost_time += delta
		_boost_timer -= delta
		# cue the player that boost (and its smash-through power) is about to lapse
		if not _boost_warned and _boost_timer > 0.0 and _boost_timer < BOOST_WARN:
			_boost_warned = true
			_play_sfx(_sfx_boost_end)
			Input.vibrate_handheld(25)
	# combo window: any scoring action refills it (see _combo_hit); a live ramp
	# boost FREEZES the countdown instead of resetting it
	if _combo_timer > 0.0 and _boost_timer <= 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo = 0
	_combo_flash = maxf(_combo_flash - 3.5 * delta, 0.0)
	if airborne:
		_air_timer -= delta
		if _air_timer <= 0.0:
			# landed a jump: reward + speed boost
			Input.vibrate_handheld(60)
			var amt := _grant_coins(JUMP_COINS + _combo_hit())
			_boost_timer = BOOST_TIME
			_boost_warned = false
			_boost_chain = 0   # a fresh boost starts a fresh smash chain (rampage feat)
			_add_popup(_sx(car_x), _car_y - 30.0, "+%d" % amt, true)
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
		if _theme_vfx == "mud_bike":
			# the bike skids on its single wheel track
			_tire_marks.append({ "d": distance, "x": car_x, "age": 0.0 })
		else:
			_tire_marks.append({ "d": distance, "x": car_x - 12.0, "age": 0.0 })
			_tire_marks.append({ "d": distance, "x": car_x + 12.0, "age": 0.0 })

	_emit_trail(delta)
	_update_particles(delta)
	_update_boom(delta)        # smash debris from ram-throughs animates during play too
	_update_tire_marks(delta)

	_no_coin_timer += delta
	if _no_coin_timer > _no_coin_best:
		_no_coin_best = _no_coin_timer

	# Boost only lets you smash THROUGH objects (see _update_hazards) — it grants no
	# immunity to driving off the road. Forks are sized so even a boosted peel never
	# out-runs your steering (see _make_fork), so no special in-fork speed cap is needed.
	if not airborne and not _on_any_lane(distance, car_x):
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
			_streak += 1
			if _streak > _streak_best:
				_streak_best = _streak
			_no_coin_timer = 0.0
			var amt := _grant_coins(1 + _combo_hit())
			_add_popup(_sx(cx), _car_y - (cd - distance), "+%d" % amt, true)
			_play_sfx(_sfx_coin)
		elif cd < distance - (COL_HALF_H + COIN_R) and not coin.get("missed", false):
			coin["missed"] = true
			_streak = 0

	score = int(distance / 10.0)
	_hud_score.text = "%.2f KM" % _dist_km()
	_hud_coins.text = "Coins: %d  (2x)" % session_coins if _lucky_run else "Coins: %d" % session_coins


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
		var b := _branch_at(d)
		if not b.is_empty():
			# Inside a fork the same generator runs, just placed against a lane's
			# geometry instead of the centerline — so a fork carries ordinary road
			# hazards (organically, fairly) rather than its own scripted set.
			_try_fork_hazard(b, d)
			continue
		# never the instant a forced sequence (a fork sweep) ends or begins
		if _hazard_blocked_near_branch(d):
			continue
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
			# variable-width roadblock (zapper-style): any width the fairness bound
			# allows, flush to one side so a clean gap (>= GAP_MIN) always remains
			var bw := _roll_block_w(bandh)
			if bw > 0.0:
				var eff := bw * 0.5 + COL_HALF_W
				_hazards.append({ "d": d, "x": bc + _flush_side(bandh, eff), "type": "block", "w": bw, "lane": 0.0, "ang": 0.0, "hit": false, "scored": false })
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


# Random roadblock width for a band of half-width bandh (car-room already
# subtracted): capped so a GAP_MIN corridor always survives beside it, or 0.0 if
# even the narrowest block wouldn't leave one (the fairness gate).
func _roll_block_w(bandh: float) -> float:
	var wmax := minf(BLOCK_W_MAX, 2.0 * bandh - 2.0 * COL_HALF_W - GAP_MIN)
	if wmax < BLOCK_W_MIN:
		return 0.0
	return randf_range(BLOCK_W_MIN, wmax)


# True if d sits in the clear stretch just after a fork merges (a "blind sweep"
# ending) or just before one splits — keeps ordinary hazards from ambushing the
# player the instant a forced sequence begins or ends.
func _hazard_blocked_near_branch(d: float) -> bool:
	for b in _branches:
		var d0 := float(b["d0"])
		var d1 := float(b["d1"])
		if d > d1 - 1.0 and d < d1 + POST_BRANCH_CLEAR:
			return true
		if d > d0 - PRE_BRANCH_CLEAR and d < d0:
			return true
	return false


# True if a hazard footprint at (d, x) would overlap an existing (uncollected)
# coin — used so fork hazards never bury a fork's reward coins.
func _hazard_hits_coin(d: float, x: float, half_w: float, half_h: float) -> bool:
	for coin in _coins:
		if bool(coin.get("got", false)):
			continue
		if absf(float(coin["d"]) - d) < half_h + COIN_R and absf(float(coin["x"]) - x) < half_w + COIN_R:
			return true
	return false


# One organic hazard inside a fork, placed against a chosen lane's geometry. Same
# hazard vocabulary, spacing and gap guarantee as the open road — only the frame of
# reference changes (a lane instead of the centerline). It only fires in the fork's
# fully-split, NON-sweeping middle, leaves a clean passing gap in that lane, and
# never lands on a coin — so whichever side the player commits to stays drivable.
func _try_fork_hazard(b: Dictionary, d: float) -> void:
	if String(b.get("kind", "")) != "fork":
		return   # shoulders keep a full-width safe through-lane; leave it clean
	var d0 := float(b["d0"])
	var d1 := float(b["d1"])
	var t := (d - d0) / maxf(d1 - d0, 1.0)
	# stay clear of both lanes' peel ramps so we never spawn during a sideways sweep
	var rmax := maxf(float(b["lane0"].get("ramp", BRANCH_RAMP)), float(b["lane1"].get("ramp", BRANCH_RAMP)))
	var guard := clampf(rmax + FORK_HAZARD_GUARD, 0.0, 0.49)
	if t < guard or t > 1.0 - guard:
		return
	var li := randi() % 2
	var lane: Dictionary = b["lane%d" % li]
	var g := _lane_geom(b, lane, d, _branch_axis(b, d), road_half_width(d))
	var c := float(g["c"])
	var hw := float(g["hw"])
	var bandh := hw - COL_HALF_W
	var roll := randf()
	if roll < 0.45:
		# avoidable traffic hugging one edge of the lane; the in_fork tracker holds
		# the gap open the whole way down (committed-but-avoidable)
		if 2.0 * hw - TRAFFIC_W < 2.0 * COL_HALF_W + GAP_MIN:
			return
		var side := 1.0 if randf() < 0.5 else -1.0
		var hx := c + side * maxf(hw - TRAFFIC_W * 0.5 - 2.0, 0.0)
		if _hazard_hits_coin(d, hx, TRAFFIC_W * 0.5, TRAFFIC_H * 0.5):
			return
		_hazards.append({ "d": d, "x": hx, "type": "traffic", "lane": 0.0, "ang": 0.0,
			"hit": false, "scored": false, "spd": randf_range(TRAFFIC_REL_MIN, TRAFFIC_REL_MAX),
			"sprite": randi(), "in_fork": true, "fork_lane": li, "fork_side": side })
	elif roll < 0.75:
		# static variable-width block flush to one side, clean gap on the other
		var bw := _roll_block_w(bandh)
		if bw <= 0.0:
			return
		var bx := c + _flush_side(bandh, bw * 0.5 + COL_HALF_W)
		if _hazard_hits_coin(d, bx, bw * 0.5, BLOCK_H * 0.5):
			return
		_hazards.append({ "d": d, "x": bx, "type": "block", "w": bw, "lane": 0.0, "ang": 0.0, "hit": false, "scored": false })
	else:
		# oil slick: makes you slip, never blocks
		if bandh < OIL_R * 0.6 + 20.0:
			return
		var ox := c + randf_range(-0.3, 0.3) * maxf(bandh - OIL_R * 0.4, 0.0)
		if _hazard_hits_coin(d, ox, OIL_R, OIL_R):
			return
		_hazards.append({ "d": d, "x": ox, "type": "oil", "lane": 0.0, "ang": 0.0, "hit": false, "in_fork": true })


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


# Every coin gain funnels through here, so a Lucky Run doubles ALL of a run's
# income (pickups, action rewards, combo bonuses) in one place. Returns the
# amount actually banked, which is what the popups show.
func _grant_coins(n: int) -> int:
	if _lucky_run:
		n *= 2
	session_coins += n
	return n


# One scoring action (coin / near miss / jump landing / smash). Chained actions
# inside the window bank +COMBO_BONUS each; ANY action refills the window to full.
# Returns the bonus to fold into the action's own reward, so each popup shows one
# combined amount instead of two overlapping ones.
func _combo_hit() -> int:
	var chained := _combo_timer > 0.0
	_combo = _combo + 1 if chained else 1
	_combo_timer = COMBO_TIME
	if not chained:
		return 0
	_combo_flash = 1.0
	if _sfx_combo != null and _sfx_combo.stream != null:
		# pitch climbs with the chain, so the streak is audible without a glance
		_sfx_combo.pitch_scale = minf(1.0 + 0.06 * float(_combo), 1.9)
		_sfx_combo.play()
	return COMBO_BONUS


# Ploughing through a blocker/car while boosting from a ramp: destroy it, bank
# RAM_COINS, and throw an explosion where it was. The hazard is flagged dead so it
# stops colliding and drawing, then _drop_old clears it.
func _smash_hazard(h: Dictionary) -> void:
	h["dead"] = true
	_run_smashed += 1
	_boost_chain += 1
	_boost_chain_best = maxi(_boost_chain_best, _boost_chain)
	var amt := _grant_coins(RAM_COINS + _combo_hit())
	# explosion is anchored to the WORLD point it happened at, so it stays on the
	# road as the camera scrolls past instead of sliding across the screen
	_spawn_explosion(float(h["x"]), float(h["d"]))
	_add_popup(_sx(float(h["x"])), _car_y - (float(h["d"]) - distance) - 24.0, "SMASH! +%d" % amt, true, 240.0, true)
	Input.vibrate_handheld(40)
	_play_sfx(_sfx_smash)


func _update_hazards(delta: float, airborne: bool) -> void:
	var ramming := _boost_timer > 0.0
	for h in _hazards:
		if bool(h.get("dead", false)):
			continue
		var htype: String = h["type"]
		if htype == "traffic":
			# Each car has its own (varied) closing speed that scales only with the
			# difficulty ramp, NOT with the player's boost — so boosting never drags
			# the traffic along with you.
			h["d"] = float(h["d"]) - _ramp_speed() * float(h["spd"]) * delta
			var td := float(h["d"])
			var oldx := float(h["x"])
			var nx: float
			if h.get("in_fork", false):
				# fork traffic holds its lane and the edge it hugs, so the passing
				# gap never closes — committed-but-avoidable rather than a trap
				var fb := _branch_at(td)
				if not fb.is_empty() and String(fb.get("kind", "")) == "fork":
					var fl: Dictionary = fb["lane%d" % int(h["fork_lane"])]
					var fg := _lane_geom(fb, fl, td, _branch_axis(fb, td), road_half_width(td))
					nx = float(fg["c"]) + float(h["fork_side"]) * maxf(float(fg["hw"]) - TRAFFIC_W * 0.5 - 2.0, 0.0)
				else:
					nx = oldx   # past the fork's ends: just carry on straight
			else:
				var tgt := road_center(td) + float(h["lane"]) * road_half_width(td)
				nx = move_toward(oldx, tgt, TRAFFIC_LAT_SPEED * delta)
				nx = _clamp_to_nearest_lane(td, nx)   # keep it on an actual lane
			h["x"] = nx
			h["ang"] = clampf((nx - oldx) / maxf(TRAFFIC_LAT_SPEED * delta, 0.001), -1.0, 1.0) * 0.4
		var hd := float(h["d"])
		var hx := float(h["x"])
		var dy := absf(hd - distance)
		var dx := absf(hx - car_x)
		if htype == "block":
			var bw: float = float(h.get("w", BLOCK_W))
			if not airborne and dy < _pl_hh + BLOCK_H * 0.5 and dx < _pl_hw + bw * 0.5:
				if ramming:
					_smash_hazard(h)
					continue
				_crash()
				return
			# near miss: squeezed past a static block without crashing -> reward
			# (never while ramming — a smash already paid out for this one). The
			# window rides the block's edge, so wide blocks are no easier to score.
			if not ramming and not h["scored"] and dy < _pl_hh + BLOCK_H * 0.5 + 20.0 and dx < bw * 0.5 + NEAR_MISS_DX - BLOCK_W * 0.5:
				h["scored"] = true
				_run_near_miss += 1
				var amt := _grant_coins(NEAR_MISS_COINS + _combo_hit())
				_add_popup(_sx(car_x), _car_y - 60.0, "Near Miss! +%d" % amt, true, 220.0, true)
				_play_sfx(_sfx_near_miss)
		elif htype == "traffic":
			# hitbox follows this enemy sprite's opaque content (and the player's), so
			# nothing collides on transparent corners
			var eh := _enemy_half(int(h.get("sprite", 0)))
			if not airborne and dy < _pl_hh + eh.y and dx < _pl_hw + eh.x:
				if ramming:
					_smash_hazard(h)
					continue
				_crash()
				return
			# near miss: passed close alongside without crashing -> reward
			# (never while ramming — a smash already paid out for this one)
			if not ramming and not h["scored"] and dy < _pl_hh + 20.0 and dx < NEAR_MISS_DX:
				h["scored"] = true
				_run_near_miss += 1
				var amt := _grant_coins(NEAR_MISS_COINS + _combo_hit())
				_add_popup(_sx(car_x), _car_y - 60.0, "Near Miss! +%d" % amt, true, 220.0, true)
				_play_sfx(_sfx_near_miss)
			# random oncoming horn while the car is on screen ahead/behind
			var bt: float = float(h.get("beep_t", randf_range(0.8, 2.4))) - delta
			if bt <= 0.0 and dy < 650.0:
				bt = randf_range(1.6, 3.6)
				_play_sfx(_sfx_beep)
			h["beep_t"] = bt
			# themed trail behind the enemy (same effect family as the player's),
			# rate-limited per car and only while it's on screen
			if hd - distance > _car_y - _view_h - 140.0 and hd - distance < _car_y + 140.0:
				var ft: float = float(h.get("fx_t", randf_range(0.0, 0.12))) - delta
				if ft <= 0.0:
					ft += 0.11
					_emit_enemy_fx(hx, hd)
				h["fx_t"] = ft
		elif htype == "oil":
			if not h["hit"] and dy < OIL_R and dx < OIL_R:
				h["hit"] = true
				_oil_timer = OIL_TIME
				_run_oil += 1
				_play_sfx(_sfx_oil)
		elif htype == "jump":
			var jw: float = float(h.get("w", JUMP_W))
			var jh: float = float(h.get("h", JUMP_H))
			if not h["hit"] and dy < _pl_hh + jh * 0.5 and dx < _pl_hw + jw * 0.5:
				h["hit"] = true
				_air_timer = AIR_TIME
				if not bool(h.get("gap_ramp", false)):
					_run_opt_jumps += 1   # gap-escape ramps are forced; only these count against "grounded"
				_play_sfx(_sfx_jump)
		elif htype == "gap":
			# a hole across the whole road: sail over it airborne, or fall in
			if not airborne and dy < float(h["len"]) * 0.5 + _pl_hh:
				_crash()
				return


# ============================================================
#  PARTICLES / TIRE MARKS / EXPLOSION
# ============================================================
# Particles/explosions are anchored to a WORLD point ("wx" world-x, "wd" distance)
# plus a screen-space spread "off" that grows from their velocity — so they stay
# put on the road as the world scrolls (an explosion plays where the crash happened)
# instead of sliding across the screen with the camera. _boom_screen() resolves the
# anchor to the current screen position.
func _boom_screen(e: Dictionary) -> Vector2:
	var base := Vector2(_sx(float(e["wx"])), _car_y - (float(e["wd"]) - distance))
	return base + Vector2(e["off"])


# Per-theme trail behind the car. The tail-light vfx records the rear lamps' world
# positions each frame (drawn later as two smooth fading streaks along the car's
# actual path); spray vfx emit their layers — exhaust smoke from the centre pipe,
# terrain kick from alternating rear wheels — as themed puffs.
func _emit_trail(delta: float) -> void:
	if _theme_vfx == "taillight":
		var rear := distance - CAR_HALF_H * 0.9
		_taillights.append(Vector3(car_x - CAR_HALF_W * 0.6, car_x + CAR_HALF_W * 0.6, rear))
		while _taillights.size() > TAILLIGHT_MAX_PTS or (_taillights.size() > 0 and _taillights[0].z < distance - TAILLIGHT_LEN):
			_taillights.remove_at(0)
		return
	if _theme_vfx == "wake":
		# water wake: record the hull's path (drawn as two spreading foam streaks in
		# _draw_wake); the splash layer below still runs, just sparser, so the trail
		# reads as displaced water with the odd spray kick instead of a puff column.
		_wake.append(Vector3(car_x, 0.0, distance - CAR_HALF_H * 0.8))
		while _wake.size() > WAKE_MAX_PTS or (_wake.size() > 0 and _wake[0].z < distance - WAKE_LEN):
			_wake.remove_at(0)
	if _theme_vfx == "mud_bike":
		# the enduro bike's single rear wheel: record its path as ONE oily groove
		# (drawn in _draw_oil_trail); the smoke/mud spray below still runs, kicked
		# from the same single wheel instead of a car's pair.
		_oil_trail.append(Vector3(car_x, 0.0, distance - CAR_HALF_H * 0.85))
		while _oil_trail.size() > OILTRAIL_MAX_PTS or (_oil_trail.size() > 0 and _oil_trail[0].z < distance - OILTRAIL_LEN):
			_oil_trail.remove_at(0)
	var fx: Dictionary = VFX.get(_theme_vfx, VFX["smoke"])
	var interval := 0.09 if _theme_vfx == "wake" else 0.04
	_exhaust_accum += delta
	while _exhaust_accum > interval:
		_exhaust_accum -= interval
		for layer in fx["layers"]:
			var life := randf_range(float(layer["lmin"]), float(layer["lmax"]))
			var r := randf_range(float(layer["rmin"]), float(layer["rmax"]))
			var cols: Array = layer["cols"]
			var wx := car_x + randf_range(-6.0, 6.0)
			var vel := Vector2(randf_range(-14.0, 14.0), randf_range(36.0, 70.0))
			if bool(layer["wheels"]):
				if _theme_vfx == "mud_bike":
					# a bike has ONE rear wheel: kick terrain from the centre line
					wx = car_x + randf_range(-3.0, 3.0)
					vel = Vector2(randf_range(-30.0, 30.0), randf_range(50.0, 90.0))
				else:
					# terrain kick: from one rear wheel, flung slightly outward
					var side := -1.0 if randf() < 0.5 else 1.0
					wx = car_x + side * CAR_HALF_W * 0.7
					vel = Vector2(side * randf_range(8.0, 34.0), randf_range(50.0, 90.0))
			_particles.append({
				"wx": wx, "wd": distance - CAR_HALF_H * 0.75,
				"off": Vector2.ZERO, "vel": vel,
				"age": 0.0, "life": life, "r": r, "col": Color(cols[randi() % cols.size()]),
			})


# The spray set ENEMIES shed for the current theme — the same per-theme layers the
# player emits, except synthwave, whose polyline tail-lights don't scale to traffic
# and become tiny ember particles instead.
func _enemy_fx_layers() -> Array:
	if _theme_vfx == "taillight":
		return [SPRAY_TAIL]
	var fx: Dictionary = VFX.get(_theme_vfx, VFX["smoke"])
	return fx["layers"]


# One themed trail puff behind an enemy at world (ex, ed). Enemies travel DOWN the
# screen, so the plume is anchored behind them (larger d) and drifts up-screen —
# mirroring the player's emitter with the direction flipped, at ~80% scale.
func _emit_enemy_fx(ex: float, ed: float) -> void:
	var layers := _enemy_fx_layers()
	if layers.is_empty():
		return
	var layer: Dictionary = layers[randi() % layers.size()]
	var wx := ex + randf_range(-5.0, 5.0)
	var vel := Vector2(randf_range(-12.0, 12.0), randf_range(-60.0, -30.0))
	if bool(layer["wheels"]):
		if _theme_vfx == "mud_bike":
			# enemy enduro bikes ride a single wheel track too
			wx = ex + randf_range(-3.0, 3.0)
			vel = Vector2(randf_range(-26.0, 26.0), randf_range(-80.0, -45.0))
		else:
			var side := -1.0 if randf() < 0.5 else 1.0
			wx = ex + side * TRAFFIC_W * 0.34
			vel = Vector2(side * randf_range(8.0, 30.0), randf_range(-80.0, -45.0))
	var cols: Array = layer["cols"]
	_particles.append({
		"wx": wx, "wd": ed + TRAFFIC_H * 0.4,
		"off": Vector2.ZERO, "vel": vel,
		"age": 0.0, "life": randf_range(float(layer["lmin"]), float(layer["lmax"])) * 0.8,
		"r": randf_range(float(layer["rmin"]), float(layer["rmax"])) * 0.8,
		"col": Color(cols[randi() % cols.size()]),
	})


# The synthwave tail-lights: the recorded lamp path drawn as two polylines whose
# alpha fades toward the tail — smooth continuous red streaks that curve with the
# car's real steering, not a chain of particles.
func _draw_taillights() -> void:
	var n := _taillights.size()
	if n < 2:
		return
	var lpts := PackedVector2Array()
	var rpts := PackedVector2Array()
	var cols := PackedColorArray()
	lpts.resize(n)
	rpts.resize(n)
	cols.resize(n)
	for i in range(n):
		var s: Vector3 = _taillights[i]
		var y := _car_y - (s.z - distance)
		lpts[i] = Vector2(_sx(s.x), y)
		rpts[i] = Vector2(_sx(s.y), y)
		var f := float(i) / float(n - 1)   # 0 = oldest (tail) -> 1 = newest (at the car)
		var c := COL_TAILLIGHT
		c.a = f * f * 0.85
		cols[i] = c
	# a wide faint pass under a narrow bright one reads as a neon glow
	var glow := PackedColorArray()
	glow.resize(n)
	for i in range(n):
		var g := cols[i]
		g.a *= 0.35
		glow[i] = g
	draw_polyline_colors(lpts, glow, 10.0, true)
	draw_polyline_colors(rpts, glow, 10.0, true)
	draw_polyline_colors(lpts, cols, 4.0, true)
	draw_polyline_colors(rpts, cols, 4.0, true)


# The jetski's water wake: the recorded hull path drawn as two foam streaks that
# spread outward and fade as they age (wide soft wash under a narrow bright crest,
# same two-pass trick as the tail-lights), with a slow shimmer keyed to world
# distance so the water reads as moving. Pure polylines along an already-kept
# history — no extra per-frame state beyond the two point arrays.
func _draw_wake() -> void:
	var n := _wake.size()
	if n < 2:
		return
	var lpts := PackedVector2Array()
	var rpts := PackedVector2Array()
	var cols := PackedColorArray()
	lpts.resize(n)
	rpts.resize(n)
	cols.resize(n)
	for i in range(n):
		var s: Vector3 = _wake[i]
		var f := float(i) / float(n - 1)   # 0 = oldest (tail) -> 1 = at the hull
		var y := _car_y - (s.z - distance)
		var spread := CAR_HALF_W * 0.55 + (1.0 - f) * WAKE_SPREAD
		spread += sin(s.z * 0.11 + time_alive * 7.0) * 1.6   # water shimmer
		lpts[i] = Vector2(_sx(s.x) - spread, y)
		rpts[i] = Vector2(_sx(s.x) + spread, y)
		var c := COL_WAKE
		c.a = f * f * 0.55
		cols[i] = c
	var wash := PackedColorArray()
	wash.resize(n)
	for i in range(n):
		var w := cols[i]
		w.a *= 0.4
		wash[i] = w
	draw_polyline_colors(lpts, wash, 9.0, true)
	draw_polyline_colors(rpts, wash, 9.0, true)
	draw_polyline_colors(lpts, cols, 3.5, true)
	draw_polyline_colors(rpts, cols, 3.5, true)


# The mud bike's oil groove: the single recorded wheel path drawn as one dark
# line — a wide wet smear under a narrow near-black core (same two-pass trick as
# the other trails), plus a faint violet sheen over the freshest stretch so it
# reads as oil rather than a plain shadow.
func _draw_oil_trail() -> void:
	var n := _oil_trail.size()
	if n < 2:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize(n)
	cols.resize(n)
	for i in range(n):
		var s: Vector3 = _oil_trail[i]
		pts[i] = Vector2(_sx(s.x), _car_y - (s.z - distance))
		var f := float(i) / float(n - 1)   # 0 = oldest (tail) -> 1 = at the wheel
		var c := COL_OILTRAIL
		c.a = f * f * 0.55
		cols[i] = c
	var smear := PackedColorArray()
	smear.resize(n)
	var sheen := PackedColorArray()
	sheen.resize(n)
	for i in range(n):
		var w := cols[i]
		w.a *= 0.35
		smear[i] = w
		var f := float(i) / float(n - 1)
		var g := COL_OILTRAIL_SHEEN
		var fresh := maxf(f - 0.5, 0.0) * 2.0
		g.a = fresh * fresh * 0.22
		sheen[i] = g
	draw_polyline_colors(pts, smear, 9.0, true)
	draw_polyline_colors(pts, cols, 4.0, true)
	draw_polyline_colors(pts, sheen, 2.0, true)


func _update_particles(delta: float) -> void:
	var i := _particles.size() - 1
	while i >= 0:
		var p = _particles[i]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= float(p["life"]):
			_particles.remove_at(i)
		else:
			var vel: Vector2 = p["vel"]
			p["off"] = Vector2(p["off"]) + vel * delta
			p["vel"] = vel * (1.0 - 1.4 * delta)
		i -= 1


func _spawn_explosion(wx: float, wd: float) -> void:
	var cols := [Color("ffd54a"), Color("ff8c1a"), Color("e74c3c"), Color("ffffff")]
	for n in range(34):
		var a := randf() * TAU
		var sp := randf_range(70.0, 340.0)
		_boom.append({
			"wx": wx, "wd": wd, "off": Vector2.ZERO,
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
			var vel: Vector2 = b["vel"]
			b["off"] = Vector2(b["off"]) + vel * delta
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
	# Boost applies everywhere now — forks run at the game's real speed, not a
	# throttled mini-game. Fork lengths are sized (see _make_fork) so a lane never
	# peels sideways faster than you can steer even at this boosted top speed, which
	# is what keeps them fair without an artificial forward-speed cap.
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
	_straight_run = 0.0
	_pattern_queue.clear()


func _push_point(seg_len: float, target_x: float) -> void:
	_track_frontier_d += seg_len
	_pt_d.append(_track_frontier_d)
	_pt_x.append(target_x)
	_track_last_x = target_x


func _slope_cap() -> float:
	return lerpf(0.45, 0.85, _turn_factor())


# Force a definite bend (used when the road has run straight for too long). A
# sweep out and a partial ease-back, slope-capped like everything else so it stays
# followable on the wide road.
func _force_turn() -> void:
	var dir := 1.0 if randf() < 0.5 else -1.0
	var amp := randf_range(200.0, 320.0) * lerpf(0.7, 1.0, _turn_factor())
	_pattern_queue.append({ "x": _track_last_x + dir * amp })
	_pattern_queue.append({ "x": _track_last_x + dir * amp * 0.35 })


# Queue one curated formation: the recipe's authored shape, mirrored at random and
# amplitude-scaled by the difficulty ramp, laid out relative to the current road x.
#
# The whole shape is fitted to the slope cap as ONE unit. The authored steps are
# steeper than the cap allows, and letting the per-step fairness clamp in
# _ensure_track resolve that stretched only the steep steps (2-4x) while the flat
# ones kept their authored length — which warped every formation into anonymous
# wander; this is why the hand-made set-pieces never visibly appeared. Fitting
# here trims the amplitude a little and then stretches EVERY step by one shared
# factor, so the shape survives intact and the cap (fairness) still holds.
func _queue_formation() -> void:
	var f: Dictionary = FORMATIONS[randi() % FORMATIONS.size()]
	var base := _track_last_x
	var dir := -1.0 if randf() < 0.5 else 1.0
	var amp := float(f["amp"]) * lerpf(0.65, 1.0, _turn_factor())
	var cap := _slope_cap()
	var need := 1.0   # stretch the authored pacing would need to respect the cap
	var prev := 0.0
	for st in f["steps"]:
		need = maxf(need, absf(float(st["dx"]) - prev) * amp / (float(st["len"]) * cap))
		prev = float(st["dx"])
	amp *= clampf(1.0 / need, 0.7, 1.0)   # concede up to 30% of the swing first...
	var k := maxf(need * 0.7, 1.0) if need > 1.0 / 0.7 else 1.0   # ...then stretch uniformly
	for st in f["steps"]:
		_pattern_queue.append({ "x": base + dir * amp * float(st["dx"]), "len": float(st["len"]) * k })


func _maybe_seed_pattern() -> void:
	# low skip chance: crafted shapes are the game's identity, so most stretches
	# carry an authored pattern rather than plain drift
	if randf() < 0.2:
		return
	if randf() < FORMATION_CHANCE:
		_queue_formation()
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

		# a branch is due around here: run out the current pattern, then hold the
		# road straight so the branch gates can pass (see BRANCH_STRAIGHT_LEAD)
		if _pattern_queue.is_empty() and _branch_wants_straight(_track_frontier_d):
			_push_point(220.0, _track_last_x)
			_straight_run = 0.0   # intentional straight — don't trip the forced bend
			continue

		var tf := _turn_factor()
		var target := _track_last_x
		if _pattern_queue.is_empty():
			# gone too long without a real bend? force one — this is Twisty Roads
			if _straight_run > MAX_STRAIGHT_RUN:
				_force_turn()
			else:
				_maybe_seed_pattern()

		var step_len := -1.0   # >0 = a curated formation step with authored pacing
		if _pattern_queue.is_empty():
			# drift gives the road momentum so it travels somewhere
			_bias = clampf(_bias * 0.92 + randf_range(-30.0, 30.0), -150.0, 150.0)
			var mag := randf_range(110.0, lerpf(180.0, 250.0, tf))
			var dir := 1.0
			if randf() < 0.5:
				dir = -1.0
			target = _track_last_x + _bias + dir * mag
		else:
			var mv: Dictionary = _pattern_queue.pop_front()
			target = float(mv["x"])
			step_len = float(mv.get("len", -1.0))

		# slope cap: make the segment long enough that the turn isn't pinched
		# and you have time to steer into it. A formation step keeps its authored
		# pacing (no length jitter, so the shape stays crisp) but never beats the
		# slope cap — fairness first.
		var move := absf(target - _track_last_x)
		var seg_len: float
		if step_len > 0.0:
			seg_len = maxf(step_len, move / _slope_cap())
		else:
			seg_len = maxf(lerpf(220.0, 150.0, tf), move / _slope_cap()) * randf_range(0.95, 1.1)
		# track how far the road has run nearly straight, so we can force a bend
		_straight_run = 0.0 if move > 95.0 else _straight_run + seg_len
		_push_point(seg_len, target)


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


# True if the car's footprint lies entirely on the painted road surface. Lane
# surfaces are merged into continuous spans first, so where two fork lanes are
# close enough that their edges touch (the gore tapering shut) a car bridging them
# still counts as on-road. Collisions therefore happen only on real contact with a
# visible edge — never on a phantom median that closed before the lanes met.
func _on_any_lane(d: float, x: float) -> bool:
	var lo := x - _pl_hw
	var hi := x + _pl_hw
	for span in _road_spans(d):
		if lo >= span.x - 0.01 and hi <= span.y + 0.01:
			return true
	return false


# Lane surfaces at d as sorted [left,right] spans (Vector2), with overlapping or
# touching lanes merged into one span.
func _road_spans(d: float) -> Array:
	var ivs: Array = []
	for lane in road_lanes(d):
		ivs.append(Vector2(float(lane["c"]) - float(lane["hw"]), float(lane["c"]) + float(lane["hw"])))
	ivs.sort_custom(func(a, b): return a.x < b.x)
	var merged: Array = []
	for iv in ivs:
		if merged.is_empty() or iv.x > float(merged[-1].y):
			merged.append(iv)
		else:
			merged[-1] = Vector2(float(merged[-1].x), maxf(float(merged[-1].y), iv.y))
	return merged


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


# True while d sits in the hold-straight window around the next branch's due
# point. Once the branch is placed _next_branch_d jumps ahead and the window
# closes; if placement keeps failing anyway, the span bound lets the road bend
# again rather than running straight forever.
func _branch_wants_straight(d: float) -> bool:
	return d > _next_branch_d - BRANCH_STRAIGHT_LEAD and d < _next_branch_d + BRANCH_STRAIGHT_SPAN


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
		_next_branch_d = d1 + BRANCH_SPACING * randf_range(0.85, 1.25)


# A two-lane fork around a median. The two lanes are described INDEPENDENTLY, so a
# fork can be a clean mirror split or lopsided (a fat lane beside a thin one), and
# its length is stretched past the sweep-cap minimum by a random factor — so no
# two forks peel apart the same way or for the same distance.
func _make_fork(d0: float, rhw: float) -> Dictionary:
	# island variant: a roundabout-style split — mirror-symmetric, a much wider
	# grass middle, run at the minimum fair length, and no wander — so it reads as
	# a compact central island you pass on either side rather than a long fork
	var island := randf() < FORK_ISLAND_CHANCE
	var asym := (not island) and randf() < FORK_ASYM_CHANCE
	var hw_cap := minf(rhw - 6.0, LANE_HW_MAX)   # cap width so wide roads still make short forks
	var base_hw := clampf(rhw * LANE_FRAC, LANE_HW_MIN, hw_cap)
	var base_med := rhw * FORK_MEDIAN_FRAC * (ISLAND_MEDIAN_MULT if island else 1.0)
	# per-lane jitter (a symmetric fork keeps both sides equal; a lopsided one does
	# not). Each lane's separation is its own width PLUS a jittered median, so the
	# grass gap between the lanes is always positive however the sides are jittered.
	var hw_l := clampf(base_hw * (1.0 + (randf_range(-FORK_HW_VARY, FORK_HW_VARY) if asym else 0.0)), LANE_HW_MIN, hw_cap)
	var hw_r := clampf(base_hw * (1.0 + (randf_range(-FORK_HW_VARY, FORK_HW_VARY) if asym else 0.0)), LANE_HW_MIN, hw_cap)
	var med_l := maxf(base_med * (1.0 + (randf_range(-FORK_OFF_VARY, FORK_OFF_VARY) if asym else 0.0)), 8.0)
	var med_r := maxf(base_med * (1.0 + (randf_range(-FORK_OFF_VARY, FORK_OFF_VARY) if asym else 0.0)), 8.0)
	var off_l := hw_l + med_l
	var off_r := hw_r + med_r
	# an island's lanes use the maximum ramp (0.5): the split profile becomes a pure
	# rise-and-fall arch with no straight middle, so the two lanes BOW around the
	# grass like the two halves of a roundabout ring instead of running parallel
	var ramp_l := 0.5 if island else BRANCH_RAMP * (1.0 + (randf_range(-FORK_RAMP_VARY, FORK_RAMP_VARY) if asym else 0.0))
	var ramp_r := 0.5 if island else BRANCH_RAMP * (1.0 + (randf_range(-FORK_RAMP_VARY, FORK_RAMP_VARY) if asym else 0.0))
	# length: keep even the widest, fastest-peeling lane within the sweep cap at the
	# REAL top speed a fork is now driven at (boost applies in forks), then stretch it
	# by a small random factor. Sizing against the sweep cap is what lets a fork run at
	# full speed without ever out-peeling your steering — the fairness bound, kept.
	var max_off := maxf(off_l, off_r)
	var min_ramp := clampf(minf(ramp_l, ramp_r), 0.05, 0.5)
	var min_len := maxf(FORK_LEN_MIN, max_off * 1.5 * MAX_SPEED * BOOST_MULT / (min_ramp * FORK_SWEEP_CAP))
	var fork_len := min_len if island else minf(min_len * randf_range(1.0, FORK_LEN_VARY_MAX), FORK_LEN_MAX)
	# gentle wind: amplitude is held under what the player can still track once it is
	# stacked on the split peel (verified in the fairness harness)
	var wave_amp := 0.0
	var wave_phase := 0.0
	if not island and randf() < FORK_WAVE_CHANCE:
		wave_amp = FORK_WAVE_AMP * randf_range(0.55, 1.0)
		wave_phase = randf() * TAU
	return {
		"kind": "fork", "island": island,
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


func distance_at_row(y: float) -> float:
	return distance + (_car_y - y)


func _sx(wx: float) -> float:
	return wx - camera_x + _view_w * 0.5


# ============================================================
#  COINS
# ============================================================
func _ensure_coins(up_to: float) -> void:
	while _coin_frontier_d < up_to:
		_coin_frontier_d += COIN_SPACING * randf_range(0.8, 1.4)
		if _coin_frontier_d < INTRO_DIST:
			continue   # no coins in the opening stretch (avoids restart-farming)
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
			half_w = float(h.get("w", BLOCK_W)) * 0.5
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


# A filled square snapped to the PIX grid — the building block for the blocky VFX.
func _draw_pix_square(center: Vector2, half: float, col: Color) -> void:
	var s := maxf(PIX, roundf(half * 2.0 / PIX) * PIX)
	var x := roundf((center.x - s * 0.5) / PIX) * PIX
	var y := roundf((center.y - s * 0.5) / PIX) * PIX
	draw_rect(Rect2(x, y, s, s), col)


# Opening-stretch coaching painted on the road itself (the first stretch carries no
# centre line, so it stays clear): the start prompt up front, then a left arrow
# ("HOLD = LEFT") and a right arrow ("RELEASE = RIGHT") with the side matching the
# live input lit up. Teaches the scheme through the track, not just HUD text, and
# fades out as the intro ends so it never clutters real play.
func _draw_track_hints() -> void:
	if not (state == State.PLAYING or state == State.COUNTDOWN):
		return
	var fade := clampf((INTRO_DIST + 120.0 - distance) / 320.0, 0.0, 1.0)
	if fade <= 0.0:
		return
	if not _run_started:
		_draw_road_text(235.0, "TAP TO BEGIN", 48, Color(1, 1, 1, fade))
		_draw_road_text(175.0, "hold to steer", 26, Color(1, 1, 1, fade * 0.8))
	var holding := _input_down()
	_draw_hint_arrow(400.0, -1.0, "HOLD", "= LEFT", holding, fade)
	_draw_hint_arrow(620.0, 1.0, "RELEASE", "= RIGHT", not holding, fade)


# Centred text drawn on the road surface at world-distance d, with a dark drop
# shadow so it stays legible over any theme's asphalt.
func _draw_road_text(d: float, text: String, size: int, col: Color) -> void:
	if _ui_font == null:
		return
	var y := _car_y - (d - distance)
	if y < -40.0 or y > _view_h + 40.0:
		return
	var cx := _sx(road_center(d))
	var w := 520.0
	draw_string(_ui_font, Vector2(cx - w * 0.5 + 2.0, y + 2.0), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(0, 0, 0, col.a * 0.6))
	draw_string(_ui_font, Vector2(cx - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)


func _draw_hint_arrow(d: float, dir: float, word: String, sub: String, active: bool, fade: float) -> void:
	var y := _car_y - (d - distance)
	if y < -70.0 or y > _view_h + 70.0:
		return
	var ax := _sx(road_center(d) + dir * 64.0)
	var alpha := fade * (1.0 if active else 0.32)
	var col := Color(1, 1, 1, alpha)
	var dark := Color(0, 0, 0, alpha * 0.7)
	var tip := Vector2(ax + dir * 30.0, y)
	var a := Vector2(ax - dir * 12.0, y - 26.0)
	var b := Vector2(ax - dir * 12.0, y + 26.0)
	draw_polyline(PackedVector2Array([tip, a, b, tip]), dark, 6.0)
	draw_colored_polygon(PackedVector2Array([tip, a, b]), col)
	if _ui_font != null:
		draw_string(_ui_font, Vector2(ax - 90.0, y + 48.0), word, HORIZONTAL_ALIGNMENT_CENTER, 180.0, 24, col)
		draw_string(_ui_font, Vector2(ax - 90.0, y + 72.0), sub, HORIZONTAL_ALIGNMENT_CENTER, 180.0, 18, col)


# Speed gauge, retro-instrument style: a ring of chunky PIX-snapped segments that
# light up with speed (green -> yellow -> red, the redline zone keyed red even
# unlit), a blocky needle built from pixel squares, and the km/h readout in the
# pixel font. Same dial geometry and read as the old smooth version — only the
# rendering changed, so it finally speaks the game's pixel-art language.
func _draw_speedometer() -> void:
	var kmh := current_speed() / PX_PER_METER * 3.6
	var span := GAUGE_MAX_KMH - GAUGE_MIN_KMH
	var frac := clampf((kmh - GAUGE_MIN_KMH) / span, 0.0, 1.0)
	var redline_frac := clampf((MAX_SPEED / PX_PER_METER * 3.6 - GAUGE_MIN_KMH) / span, 0.0, 1.0)

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

	_draw_pix_disc(GAUGE_CENTER, GAUGE_R + 16.0, COL_GAUGE_BG)

	# segment ring: lit up to the current speed, dim ring/red-keyed beyond it
	var pulse := 0.5 + 0.5 * sin(time_alive * 16.0)
	var lit := int(roundf(frac * GAUGE_SEGS))
	for i in range(GAUGE_SEGS):
		var t := (float(i) + 0.5) / float(GAUGE_SEGS)
		var rad := deg_to_rad(lerpf(GAUGE_START_DEG, GAUGE_END_DEG, t))
		var p := GAUGE_CENTER + Vector2(cos(rad), sin(rad)) * GAUGE_R
		var col: Color
		if i < lit:
			col = Color(0.25, 0.9, 0.45).lerp(Color(1.0, 0.82, 0.2), clampf(t * 1.6, 0.0, 1.0))
			col = col.lerp(Color(1.0, 0.32, 0.26), clampf((t - 0.55) * 2.2, 0.0, 1.0))
			if hot:
				col = fill_col
				col.a = 0.55 + 0.45 * pulse
		else:
			col = COL_GAUGE_REDZONE if t >= redline_frac else COL_GAUGE_RING
			col.a = 0.3
		_draw_pix_square(p, 4.0, col)

	# major tick blocks just outside the segment ring
	for i in range(7):
		var tt := i / 6.0
		var trad := deg_to_rad(lerpf(GAUGE_START_DEG, GAUGE_END_DEG, tt))
		_draw_pix_square(GAUGE_CENTER + Vector2(cos(trad), sin(trad)) * (GAUGE_R + 11.0), 2.0, COL_GAUGE_TICK)

	# blocky needle: a run of pixel squares from the hub out (with the old
	# top-end vibration so the gauge still feels alive when it's pinned)
	var jitter := sin(time_alive * 42.0) * 0.013 if hot else 0.0
	var needle_rad := deg_to_rad(lerpf(GAUGE_START_DEG, GAUGE_END_DEG, frac)) + jitter
	var ndir := Vector2(cos(needle_rad), sin(needle_rad))
	var nr := 8.0
	while nr < GAUGE_R - 14.0:
		_draw_pix_square(GAUGE_CENTER + ndir * nr, 2.6, fill_col)
		nr += PIX * 2.0
	_draw_pix_square(GAUGE_CENTER, 5.0, fill_col)
	_draw_pix_square(GAUGE_CENTER, 2.5, Color(0, 0, 0, 0.6))

	if _ui_font != null:
		draw_string(_ui_font, GAUGE_CENTER + Vector2(-54, GAUGE_R + 30.0), "%d" % int(kmh), HORIZONTAL_ALIGNMENT_CENTER, 108, 38, fill_col)
		draw_string(_ui_font, GAUGE_CENTER + Vector2(-54, GAUGE_R + 58.0), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 108, 16, Color(1, 1, 1, 0.55))


# A filled disc built from PIX-grid rows, so even the gauge's backing plate obeys
# the pixel grid instead of being a smooth circle.
func _draw_pix_disc(center: Vector2, r: float, col: Color) -> void:
	var q := PIX * 2.0
	var y := -r
	while y <= r:
		var half := sqrt(maxf(r * r - y * y, 0.0))
		var yy := roundf((center.y + y) / q) * q
		var x0 := roundf((center.x - half) / q) * q
		var x1 := roundf((center.x + half) / q) * q
		draw_rect(Rect2(x0, yy, maxf(x1 - x0, q), q), col)
		y += q


func _draw() -> void:
	_draw_background()
	_draw_parallax()
	_draw_decos()        # off-road props sit behind the road surface
	# a whisper of darkening over everything off-road (the road is painted on top
	# at full brightness) lifts the driving plane for depth — one flat rect, so it
	# costs nothing and can't soften the pixel art
	draw_rect(Rect2(-DRAW_PAD, -DRAW_PAD, SCREEN_W + 2.0 * DRAW_PAD, _view_h + 2.0 * DRAW_PAD), Color(0, 0, 0, BG_DARKEN))
	_draw_road()

	# menus: the world above is the attract-mode backdrop — add the demo driver's
	# trail and vehicle, then stop (no hazards/HUD; the blur overlay sits on top)
	if _in_menu_state():
		_draw_particles()
		_draw_player()
		return

	var in_game := state == State.PLAYING or state == State.CRASH or state == State.GAME_OVER or state == State.COUNTDOWN
	if not in_game:
		return

	_draw_track_hints()   # on-road control prompts during the opening (under the car)

	for m in _tire_marks:
		var my := _car_y - (float(m["d"]) - distance)
		var a := 1.0 - float(m["age"]) / TIRE_LIFE
		if a > 0.0:
			var tc := COL_TIRE
			tc.a = 0.5 * a
			draw_rect(Rect2(_sx(float(m["x"])) - 3.0, my - 4.0, 6.0, 8.0), tc)

	for h in _hazards:
		if bool(h.get("dead", false)):
			continue
		var hd := float(h["d"])
		var hy := _car_y - (hd - distance)
		if hy < -160.0 or hy > _view_h + 160.0:
			continue
		var hx := _sx(float(h["x"]))
		var ht: String = h["type"]
		if ht == "oil":
			draw_circle(Vector2(hx, hy), OIL_R, COL_OIL)
			draw_circle(Vector2(hx - OIL_R * 0.3, hy - OIL_R * 0.3), OIL_R * 0.35, COL_OIL_HI)
		elif ht == "block":
			_draw_barrier(hx, hy, float(h.get("w", BLOCK_W)), hd)
		elif ht == "traffic":
			# Enemies are ONCOMING (they travel down-screen, toward the player), so
			# their sprite must face DOWN — the art is authored nose-up like the
			# player, so flip it vertically (and negate the steer-lean to match the
			# flip) instead of drawing it driving backwards.
			if _tex_enemy.size() > 0:
				var idx := int(h.get("sprite", 0)) % _tex_enemy.size()
				var et: Texture2D = _tex_enemy[idx]
				var esz: Vector2 = _enemy_size[idx]
				var erect := Rect2(-esz.x * 0.5, -esz.y * 0.5, esz.x, esz.y)
				# the shadow is the sprite itself tinted, so it hugs the opaque pixels
				draw_set_transform(Vector2(hx, hy) + SHADOW_OFF, -float(h["ang"]), Vector2(1.0, -1.0))
				draw_texture_rect(et, erect, false, SHADOW_COL)
				draw_set_transform(Vector2(hx, hy), -float(h["ang"]), Vector2(1.0, -1.0))
				draw_texture_rect(et, erect, false)
			else:
				draw_set_transform(Vector2(hx, hy) + SHADOW_OFF, float(h["ang"]), Vector2.ONE)
				draw_rect(Rect2(-TRAFFIC_W * 0.5, -TRAFFIC_H * 0.5, TRAFFIC_W, TRAFFIC_H), SHADOW_COL)
				draw_set_transform(Vector2(hx, hy), float(h["ang"]), Vector2.ONE)
				draw_rect(Rect2(-TRAFFIC_W * 0.5, -TRAFFIC_H * 0.5, TRAFFIC_W, TRAFFIC_H), COL_TRAFFIC)
				# windshield toward the player (front of the oncoming car)
				draw_rect(Rect2(-TRAFFIC_W * 0.5 + 8.0, TRAFFIC_H * 0.5 - 30.0, TRAFFIC_W - 16.0, 22.0), COL_TRAFFIC_DARK)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif ht == "jump":
			var jw: float = float(h.get("w", JUMP_W))
			var jh: float = float(h.get("h", JUMP_H))
			var ramp := PackedVector2Array()
			ramp.append(Vector2(hx - jw * 0.5, hy + jh * 0.5))
			ramp.append(Vector2(hx + jw * 0.5, hy + jh * 0.5))
			ramp.append(Vector2(hx + jw * 0.35, hy - jh * 0.5))
			ramp.append(Vector2(hx - jw * 0.35, hy - jh * 0.5))
			var rsh := PackedVector2Array()
			for rp in ramp:
				rsh.append(rp + SHADOW_OFF)
			draw_colored_polygon(rsh, SHADOW_COL)
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
		var cy := _car_y - (float(coin["d"]) - distance)
		if cy > -COIN_R and cy < _view_h + COIN_R:
			var cx := _sx(float(coin["x"]))
			draw_circle(Vector2(cx, cy) + SHADOW_OFF * 0.7, COIN_R, SHADOW_COL)
			draw_circle(Vector2(cx, cy), COIN_R, COL_COIN)
			draw_circle(Vector2(cx, cy), COIN_R * 0.55, COL_COIN_HI)

	_draw_particles()

	# car (hidden once it has exploded; shown frozen during the resume countdown)
	if state == State.PLAYING or state == State.COUNTDOWN:
		_draw_player()

	# explosion — pixel debris (world-anchored, so it stays where the crash happened)
	for b in _boom:
		var brem := 1.0 - float(b["age"]) / float(b["life"])
		if brem > 0.0:
			var bcol: Color = b["col"]
			bcol.a = brem
			_draw_pix_square(_boom_screen(b), float(b["r"]) * (0.5 + brem * 0.8), bcol)

	if state == State.PLAYING or state == State.COUNTDOWN or state == State.CRASH:
		_draw_speedometer()
		_draw_combo_hud()
		_draw_lucky()

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
		draw_rect(Rect2(0, 0, SCREEN_W, _view_h), Color(0, 0, 0, 0.35))
		if _ui_font != null:
			var n := ceili(_count_timer)
			draw_string(_ui_font, Vector2(0, _view_h * 0.5), str(n), HORIZONTAL_ALIGNMENT_CENTER, SCREEN_W, 160, Color(1, 1, 1, 0.95))

	# crash flash (padded: it plays while the screen shake is at full amplitude)
	if state == State.CRASH:
		var f := clampf((_crash_timer - (CRASH_TIME - 0.15)) / 0.15, 0.0, 1.0)
		if f > 0.0:
			draw_rect(Rect2(-DRAW_PAD, -DRAW_PAD, SCREEN_W + 2.0 * DRAW_PAD, _view_h + 2.0 * DRAW_PAD), Color(1, 1, 1, f * 0.6))


# Themed spray/exhaust puffs (world-anchored pixel squares fading out).
func _draw_particles() -> void:
	for pp in _particles:
		var life := float(pp["life"])
		var rem := 1.0 - float(pp["age"]) / life
		if rem > 0.0:
			var ec: Color = pp.get("col", COL_EXHAUST)
			ec.a = rem * 0.42
			_draw_pix_square(_boom_screen(pp), float(pp["r"]) * (0.6 + rem * 0.6), ec)


# The player vehicle with its path trail, boost glow, combo ring and shadow.
# Shared by live play, the resume countdown, and the menu's attract-mode drive
# (where boost/combo/air are simply zero).
func _draw_player() -> void:
	# path trail under the car, over the road
	if _theme_vfx == "wake":
		_draw_wake()
	elif _theme_vfx == "mud_bike":
		_draw_oil_trail()
	else:
		_draw_taillights()
	# boost glow — flashes faster and reddens in its final BOOST_WARN seconds so
	# you can read at a glance whether the smash-through is still live
	if _boost_timer > 0.0:
		var ending := _boost_timer < BOOST_WARN
		var pulse := 0.6 + 0.4 * sin(time_alive * (46.0 if ending else 18.0))
		var gcol := COL_BOOST.lerp(Color(1.0, 0.3, 0.22), 0.6) if ending else COL_BOOST
		gcol.a = (0.5 if ending else 0.35) * pulse
		draw_circle(Vector2(_sx(car_x), _car_y), CAR_W * (0.95 + 0.12 * pulse), gcol)
	# chain bump: an expanding ring of pixel squares pops off the car
	if _combo_flash > 0.0:
		var cr := CAR_W * (0.8 + (1.0 - _combo_flash) * 1.2)
		var rc := COL_COMBO
		rc.a = _combo_flash * 0.8
		for i in range(10):
			var ra := TAU * float(i) / 10.0
			_draw_pix_square(Vector2(_sx(car_x), _car_y) + Vector2(cos(ra), sin(ra)) * cr, 2.5, rc)
	var ang := _car_angle()
	var lift := 0.0
	var sc := 1.0
	var sh_off := SHADOW_OFF
	if _air_timer > 0.0:
		var phase := 1.0 - _air_timer / AIR_TIME
		var hop := sin(phase * PI)
		lift = hop * 26.0
		sc = 1.0 + hop * 0.18
		sh_off = SHADOW_OFF * (1.0 + hop * 2.2)   # the shadow falls away with height
	var chw := _car_size.x * 0.5
	var chh := _car_size.y * 0.5
	if _tex_car != null:
		# the shadow is the sprite itself tinted, so it hugs the opaque pixels
		draw_set_transform(Vector2(_sx(car_x), _car_y) + sh_off, ang, Vector2.ONE)
		draw_texture_rect(_tex_car, Rect2(-chw, -chh, _car_size.x, _car_size.y), false, SHADOW_COL)
		draw_set_transform(Vector2(_sx(car_x), _car_y - lift), ang, Vector2(sc, sc))
		draw_texture_rect(_tex_car, Rect2(-chw, -chh, _car_size.x, _car_size.y), false)
	else:
		draw_set_transform(Vector2(_sx(car_x), _car_y) + sh_off, ang, Vector2.ONE)
		draw_rect(Rect2(-CAR_HALF_W, -CAR_HALF_H, CAR_W, CAR_H), SHADOW_COL)
		draw_set_transform(Vector2(_sx(car_x), _car_y - lift), ang, Vector2(sc, sc))
		draw_rect(Rect2(-CAR_HALF_W, -CAR_HALF_H, CAR_W, CAR_H), col_car)
		draw_rect(Rect2(-CAR_HALF_W + 8.0, -CAR_HALF_H + 18.0, CAR_W - 16.0, 30.0), col_car_dark)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Combo chain readout, centred under the coin counter: multiplier text that pops
# on every chain bump plus a segmented pixel bar draining with the 3s window. The
# bar turns boost-gold while a ramp boost is freezing the clock, so "paused" is
# visibly different from "running out".
func _draw_combo_hud() -> void:
	if _combo < 2 or _combo_timer <= 0.0:
		return
	var cx := _view_w * 0.5
	var y := 200.0
	var paused := _boost_timer > 0.0
	var col := COL_BOOST if paused else COL_COMBO
	if _ui_font != null:
		var pop := int(30.0 * (1.0 + _combo_flash * 0.4))
		draw_string(_ui_font, Vector2(cx - 160.0, y), "COMBO x%d" % _combo, HORIZONTAL_ALIGNMENT_CENTER, 320.0, pop, col)
	var cells := 10
	var on_cells := ceili(_combo_timer / COMBO_TIME * float(cells))
	for i in range(cells):
		var c := col if i < on_cells else Color(1, 1, 1, 0.15)
		draw_rect(Rect2(cx - 70.0 + float(i) * 14.0, y + 10.0, 10.0, 8.0), c)


# The Lucky Run announcement: a pulsing gold headline plus a thin gold frame
# around the whole view, alive for the entire run — unmissable, but out of the
# road's way.
func _draw_lucky() -> void:
	if not _lucky_run:
		return
	var pulse := 0.75 + 0.25 * sin(time_alive * 6.0)
	var gc := COL_COIN
	gc.a = 0.9 * pulse
	if _ui_font != null:
		draw_string(_ui_font, Vector2(_view_w * 0.5 - 220.0, 248.0), "LUCKY RUN! 2x COINS", HORIZONTAL_ALIGNMENT_CENTER, 440.0, 30, gc)
	var fc := COL_COIN
	fc.a = 0.28 * pulse
	var th := 6.0
	draw_rect(Rect2(0, 0, _view_w, th), fc)
	draw_rect(Rect2(0, _view_h - th, _view_w, th), fc)
	draw_rect(Rect2(0, th, th, _view_h - 2.0 * th), fc)
	draw_rect(Rect2(_view_w - th, th, th, _view_h - 2.0 * th), fc)


# A roadblock barrier. No sprite slot — this IS the art: a chunky outlined
# warning board standing on two feet, a mirrored diagonal stripe pattern with a
# FIXED number of repeats per half (so every random width reads as the same
# uniform barrier, only scaled), a lit top lip, and two end lamps that blink in
# alternation. Width bw is the collision width; the lamps/outline overhang is
# cosmetic only.
func _draw_barrier(hx: float, hy: float, bw: float, hd: float) -> void:
	var hh := BLOCK_H * 0.5
	var half := bw * 0.5
	draw_rect(Rect2(hx - half + SHADOW_OFF.x, hy - hh + SHADOW_OFF.y, bw, BLOCK_H), SHADOW_COL)
	# feet, symmetric, poking out under the board
	var fw := 9.0
	for s: float in [-1.0, 1.0]:
		var fx := hx + s * (half - fw * 1.2)
		draw_rect(Rect2(fx - fw * 0.5, hy + hh - 2.0, fw, 8.0), COL_BLOCK_DARK)
	# chunky dark outline, then the board
	draw_rect(Rect2(hx - half - 3.0, hy - hh - 3.0, bw + 6.0, BLOCK_H + 6.0), COL_BLOCK_DARK)
	draw_rect(Rect2(hx - half, hy - hh, bw, BLOCK_H), COL_BLOCK)
	# mirrored stripes: BLOCK_STRIPES per half, leaning toward the centre from both
	# sides so the pattern is symmetric whatever the board's width
	var inset := 5.0
	var innw := half - inset * 2.0
	if innw > 4.0:
		var pitch := innw / float(BLOCK_STRIPES)
		var sw := pitch * 0.52
		var lean := minf(pitch * 0.55, 14.0)
		var y0 := hy - hh + inset
		var y1 := hy + hh - inset
		for k in range(BLOCK_STRIPES):
			for s: float in [-1.0, 1.0]:
				var bx := hx + s * (half - inset - (float(k) + 0.5) * pitch)
				draw_colored_polygon(PackedVector2Array([
					Vector2(bx - sw * 0.5 * s, y1), Vector2(bx + sw * 0.5 * s, y1),
					Vector2(bx + (sw * 0.5 + lean) * s, y0), Vector2(bx + (lean - sw * 0.5) * s, y0),
				]), COL_BLOCK_DARK)
	# rounded-board read: a lit lip on top, a shaded lip below (drawn over the
	# stripes so both run unbroken across the width)
	draw_rect(Rect2(hx - half, hy - hh, bw, 4.0), COL_BLOCK_HI)
	draw_rect(Rect2(hx - half, hy + hh - 4.0, bw, 4.0), COL_BLOCK_SHADE)
	# end lamps, blinking in alternation (phase keyed to world distance so two
	# barriers on screen never flash in lockstep)
	for s: float in [-1.0, 1.0]:
		var lit := fposmod(time_alive * 2.0 + hd * 0.002 + (0.5 if s > 0.0 else 0.0), 1.0) < 0.55
		var lx := hx + s * (half - 8.0)
		draw_rect(Rect2(lx - 5.0, hy - hh - 8.0, 10.0, 10.0), COL_BLOCK_DARK)
		draw_rect(Rect2(lx - 3.0, hy - hh - 6.0, 6.0, 6.0), COL_BLOCK_LAMP if lit else COL_BLOCK_LAMP_OFF)


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
		var yy := _car_y - (dd - distance)
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
	var ny := _car_y - (g0 - distance)
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
	var bot_d := distance_at_row(_view_h + DRAW_PAD)
	var top_d := distance_at_row(-DRAW_PAD)

	var any_branch := false
	for b in _branches:
		if not (float(b["d1"]) < bot_d or float(b["d0"]) > top_d):
			any_branch = true
			break

	if not any_branch:
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var vs := PackedFloat32Array()
		var centers := PackedVector3Array()
		var y := -DRAW_PAD
		while y <= _view_h + DRAW_PAD:
			var d := distance_at_row(y)
			var c := road_center(d)
			var hw := road_half_width(d)
			left.append(Vector2(_sx(c - hw), y))
			right.append(Vector2(_sx(c + hw), y))
			vs.append(d / WORLD_TEX_TILE)
			centers.append(Vector3(_sx(c), y, d))
			y += step
		_fill_band(left, right, vs)
		draw_polyline(left, col_edge, 5.0, true)
		draw_polyline(right, col_edge, 5.0, true)
		_draw_dashes(centers)
		return

	# branch path: two lane bands around an (optional) grass median. The gap between
	# them is left unpainted so the off-road shows through. Outer edges are drawn
	# continuously; the inner (median) edges are stroked as a single outline that
	# tapers to a point at each gore tip, so a fork opens and closes like a real
	# road split rather than popping a kerb + nose-dot in and out at a hard cutoff.
	var l0 := PackedVector2Array()
	var r0 := PackedVector2Array()
	var l1 := PackedVector2Array()
	var r1 := PackedVector2Array()
	var cen0 := PackedVector3Array()
	var cen1 := PackedVector3Array()
	var vs := PackedFloat32Array()
	var split := PackedInt32Array()   # 1 where the two lane centres have parted — see DASH_SPLIT_EPS
	var yy := -DRAW_PAD
	while yy <= _view_h + DRAW_PAD:
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
		split.append(1 if absf(c1 - c0) > DASH_SPLIT_EPS else 0)
		vs.append(d / WORLD_TEX_TILE)
		yy += step
	_fill_band(l0, r0, vs)
	_fill_band(l1, r1, vs)
	draw_polyline(l0, col_edge, 5.0, true)   # outer-left  (always a boundary)
	draw_polyline(r1, col_edge, 5.0, true)   # outer-right (always a boundary)
	_draw_gore(r0, l1)                        # median kerb, tapered to a point at each tip
	_draw_dashes(cen0)                        # through / left-lane centre line (always present)
	_draw_dashes(cen1, split)                 # right-lane centre line, only where it has parted


# Fills a road band, textured (world-anchored 256x256 tiling when a road texture
# is loaded — see _draw_band_strip's world_u mode), rainbow-surfaced, or
# flat-coloured.
#
# All three paths render as ONE indexed triangle strip (two triangles per sample
# row) instead of one huge concave polygon. draw_colored_polygon ear-clips its
# input every frame, and on a road band — hundreds of nearly-collinear edge points
# that pinch to zero width at fork merges — that triangulation both glitched
# (sliver/flipped triangles flashing on bends and forks) and burned CPU. A strip
# needs no triangulation at all, and a pinched row just makes two zero-area
# triangles, which render as nothing.
func _fill_band(left: PackedVector2Array, right: PackedVector2Array, vs := PackedFloat32Array()) -> void:
	if _tex_road != null and vs.size() == left.size() and left.size() == right.size():
		_draw_band_strip(left, right, Color.WHITE, _tex_road, vs, 0.0, 1.0, true)
		return
	if _theme_rainbow:
		_fill_rainbow(left, right)
		return
	_draw_band_strip(left, right, col_road)


# The shared strip renderer: rows of (left, right) vertex pairs, two triangles per
# row gap, optional texture with per-row v and u either spanning the band (u0->u1
# — the rainbow surface) or anchored to WORLD x at the fixed 256px tile (world_u —
# the road surface, so its texture never squashes with the road width and lines up
# with the identically-tiled background for one cohesive ground plane).
func _draw_band_strip(left: PackedVector2Array, right: PackedVector2Array, col: Color, tex: Texture2D = null, vs := PackedFloat32Array(), u0 := 0.0, u1 := 1.0, world_u := false) -> void:
	var n := left.size()
	if n < 2 or right.size() != n:
		return
	var pts := PackedVector2Array()
	pts.resize(n * 2)
	var cols := PackedColorArray()
	cols.resize(n * 2)
	cols.fill(col)
	var use_tex := tex != null and vs.size() == n
	var uvs := PackedVector2Array()
	if use_tex:
		uvs.resize(n * 2)
	var wox := camera_x - _view_w * 0.5   # screen-x -> world-x offset (see _sx)
	for i in range(n):
		pts[i * 2] = left[i]
		pts[i * 2 + 1] = right[i]
		if use_tex:
			if world_u:
				uvs[i * 2] = Vector2((left[i].x + wox) / WORLD_TEX_TILE, vs[i])
				uvs[i * 2 + 1] = Vector2((right[i].x + wox) / WORLD_TEX_TILE, vs[i])
			else:
				uvs[i * 2] = Vector2(u0, vs[i])
				uvs[i * 2 + 1] = Vector2(u1, vs[i])
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _strip_indices(n), pts, cols, uvs,
		PackedInt32Array(), PackedFloat32Array(),
		tex.get_rid() if use_tex else RID())


# Index buffer for an n-row strip, cached — every band drawn in a frame has the
# same row count (one sample per screen step), so this rebuilds only on resize.
func _strip_indices(rows: int) -> PackedInt32Array:
	var need := (rows - 1) * 6
	if _strip_idx.size() != need:
		_strip_idx.resize(need)
		var w := 0
		for i in range(rows - 1):
			var a := i * 2
			_strip_idx[w] = a
			_strip_idx[w + 1] = a + 1
			_strip_idx[w + 2] = a + 2
			_strip_idx[w + 3] = a + 1
			_strip_idx[w + 4] = a + 3
			_strip_idx[w + 5] = a + 2
			w += 6
	return _strip_idx


# Rainbow Lane surface: longitudinal ROYGBIV stripes running down the road (à la
# Mario Kart's Rainbow Road), following the road through every bend, with a slow
# hue scroll keyed to world-distance so the colours shimmer toward the player.
#
# The stripes live in a tiny precomputed texture (one column per stripe, one row
# per cycle phase) and the surface renders through the same triangle strip as every
# other band: u crosses the road width (nearest-sampled into 7 hard stripes, inset
# off the exact 0/1 texel edges so the repeat wrap never bleeds a stray column) and
# v picks the current cycle phase. One strip, no per-frame triangulation — this is
# what removed both the fork/turn glitches and the per-frame polygon cost.
func _fill_rainbow(left: PackedVector2Array, right: PackedVector2Array) -> void:
	var n := left.size()
	if n < 2 or right.size() != n:
		return
	if _tex_rainbow == null:
		_build_rainbow_tex()
	var v := fposmod(distance * 0.0012, 1.0)   # palette cycle phase
	var vs := PackedFloat32Array()
	vs.resize(n)
	vs.fill(v)
	_draw_band_strip(left, right, Color.WHITE, _tex_rainbow, vs, 0.001, 0.999)


# RAINBOW_BANDS stripes across the width × 256 cycle phases down the rows. Sampled
# nearest (the project's default filter), so u gives crisp hard stripes and v cycles
# each stripe's hue through the wheel exactly as the old per-band shift did.
func _build_rainbow_tex() -> void:
	var bands := 7
	var rows := 256
	var img := Image.create(bands, rows, false, Image.FORMAT_RGBA8)
	for t in range(rows):
		var shift := float(t) / float(rows)
		for k in range(bands):
			var hue := fposmod(float(k) / float(bands) + shift, 1.0)
			img.set_pixel(k, t, Color.from_hsv(hue, 0.85, 1.0))
	_tex_rainbow = ImageTexture.create_from_image(img)


# Centre line. Off-road / track themes paint none. Each dash is drawn as ONE
# grouped polyline over its "on" run instead of a stack of tiny per-sample lines —
# that overlap of antialiased stubs was what made the old stripes blotchy on bends.
# An optional mask suppresses samples (used so a fork's second lane line is painted
# only where that lane has actually parted from the first — where they coincide a
# single line is drawn, instead of two overlapping ones that flickered bolder).
#
# Each dash starts/ends at the EXACT world-distance where the on/off phase flips,
# interpolated between the bracketing samples, rather than snapping to whichever
# 3px sample happened to be "on". Snapping made every dash end jump by up to a
# sample each frame as the road scrolled — the residual twitch in the lane lines.
func _draw_dashes(centers: PackedVector3Array, mask := PackedInt32Array()) -> void:
	if not _theme_stripes:
		return
	var use_mask := mask.size() == centers.size()
	var seg := PackedVector2Array()
	var prev := Vector3.ZERO
	var prev_on := false
	var prev_gate := false
	for i in range(centers.size()):
		var p: Vector3 = centers[i]
		# the opening stretch and (for the 2nd lane line) un-parted rows are gated off
		var gate := p.z >= INTRO_DIST and (not use_mask or mask[i] == 1)
		var phase_on := fposmod(p.z, DASH_PERIOD) < DASH_PERIOD * 0.5
		var on := gate and phase_on
		if i > 0 and on != prev_on and gate and prev_gate:
			# a phase flip between two live samples: split exactly at the boundary
			var edge := _dash_edge(prev, p)
			if on:
				if seg.size() >= 2:
					draw_polyline(seg, col_dash, 5.0, true)
				seg = PackedVector2Array()
				seg.append(edge)
			else:
				seg.append(edge)
				if seg.size() >= 2:
					draw_polyline(seg, col_dash, 5.0, true)
				seg = PackedVector2Array()
		elif on != prev_on and not on:
			# gated off (intro / un-parted lane): just cut at the sample
			if seg.size() >= 2:
				draw_polyline(seg, col_dash, 5.0, true)
			seg = PackedVector2Array()
		if on:
			seg.append(Vector2(p.x, p.y))
		prev = p
		prev_on = on
		prev_gate = gate
	if seg.size() >= 2:
		draw_polyline(seg, col_dash, 5.0, true)


# Exact point between samples a and b (each Vector3 of screen-x, screen-y, world-d)
# where the dash on/off phase boundary falls — the nearest DASH_PERIOD/2 multiple
# between their world-distances. Interpolating to it keeps dash ends sub-pixel
# stable instead of snapping to the sampling grid.
func _dash_edge(a: Vector3, b: Vector3) -> Vector2:
	var half := DASH_PERIOD * 0.5
	var m := ceilf(minf(a.z, b.z) / half) * half
	var span := a.z - b.z
	var t := 0.5 if absf(span) < 0.0001 else clampf((a.z - m) / span, 0.0, 1.0)
	return Vector2(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t))


# Median kerb around a fork's grass gore. The gore is where the right lane's inner
# edge (l1) sits to the RIGHT of the left lane's inner edge (r0), so real off-road
# shows between them. Each contiguous open run is stroked as ONE closed outline
# whose two ends taper to the exact point where the inner edges cross (median width
# 0), so the split opens and closes to a clean nose instead of popping a kerb and a
# nose-dot in and out at a hard threshold. Runs are kept separate, so unrelated
# open regions (two branches on screen at once) are never joined by a stray line.
func _draw_gore(r0: PackedVector2Array, l1: PackedVector2Array) -> void:
	var n := r0.size()
	if n == 0 or l1.size() != n:
		return
	var i := 0
	while i < n:
		if l1[i].x - r0[i].x <= 0.0:
			i += 1
			continue
		var j := i
		while j < n and (l1[j].x - r0[j].x) > 0.0:
			j += 1
		# tips: where the inner edges meet (zero median width), interpolated against
		# the bracketing closed sample so the nose is sharp rather than step-quantised
		var head := _gore_tip(r0, l1, i, -1) if i > 0 else (r0[0] + l1[0]) * 0.5
		var tail := _gore_tip(r0, l1, j - 1, 1) if j < n else (r0[n - 1] + l1[n - 1]) * 0.5
		var loop := PackedVector2Array()
		loop.append(head)
		for k in range(i, j):
			loop.append(r0[k])
		loop.append(tail)
		for k in range(j - 1, i - 1, -1):
			loop.append(l1[k])
		loop.append(head)
		draw_polyline(loop, col_edge, 5.0, true)
		i = j


# Point where the median's two inner edges cross (width 0), found by interpolating
# between an open sample (idx) and its closed neighbour (idx + dir) — the gore tip.
func _gore_tip(r0: PackedVector2Array, l1: PackedVector2Array, idx: int, dir: int) -> Vector2:
	var nb := idx + dir
	var m_open := l1[idx].x - r0[idx].x       # > 0
	var m_closed := l1[nb].x - r0[nb].x        # <= 0
	var denom := m_open - m_closed
	var s := 0.0 if denom == 0.0 else clampf(-m_closed / denom, 0.0, 1.0)
	return (r0[nb].lerp(r0[idx], s) + l1[nb].lerp(l1[idx], s)) * 0.5


# Off-road background: a per-theme texture tiled 1:1 with the world (same 256px
# lattice, same scroll as the road surface — no parallax), or the flat theme
# colour when no texture is present. The offsets are chosen so a background tile
# corner sits exactly on every WORLD multiple of 256 on both axes, which is the
# same lattice the road texture's world-anchored UVs sample — one cohesive ground.
func _draw_background() -> void:
	if _tex_bg != null:
		_draw_tiled(_tex_bg, camera_x - _view_w * 0.5, -(distance + _car_y))
	else:
		draw_rect(Rect2(-DRAW_PAD, -DRAW_PAD, SCREEN_W + 2.0 * DRAW_PAD, _view_h + 2.0 * DRAW_PAD), col_offroad)


# Tiles a texture across the whole screen at the given world-scroll offset, each
# tile drawn at the fixed 256x256 world footprint (whatever the texture's own
# pixel size or import flags), so ground art always matches the road's scale.
func _draw_tiled(tex: Texture2D, scroll_x: float, scroll_y: float) -> void:
	# one extra ring of tiles beyond the view (DRAW_PAD), so the crash shake can
	# jolt the world without exposing unpainted edges
	var ts := WORLD_TEX_TILE
	var y := -fposmod(scroll_y, ts) - ts
	while y < _view_h + DRAW_PAD:
		var x := -fposmod(scroll_x, ts) - ts
		while x < SCREEN_W + DRAW_PAD:
			draw_texture_rect(tex, Rect2(x, y, ts, ts), false)
			x += ts
		y += ts


# Background props: per-theme sprite for the variant, else the primitive stand-in.
func _draw_decos() -> void:
	for deco in _decos:
		var dy := _car_y - (float(deco["d"]) - distance)
		if dy < -90.0 or dy > _view_h + 90.0:
			continue
		var pos := Vector2(_sx(float(deco["x"])), dy)
		var variant := int(deco["variant"])
		var s := float(deco["scale"])
		if _tex_deco.size() > 0:
			var tex: Texture2D = _tex_deco[variant % _tex_deco.size()]
			var sz := tex.get_size() * s
			# the shadow is the sprite itself tinted, so it hugs the opaque pixels
			draw_texture_rect(tex, Rect2(pos - sz * 0.5 + SHADOW_OFF, sz), false, SHADOW_COL)
			draw_texture_rect(tex, Rect2(pos - sz * 0.5, sz), false)
		else:
			draw_circle(pos + SHADOW_OFF, 13.0 * s, SHADOW_COL)
			_draw_deco_primitive(pos, variant, s)


func _draw_parallax() -> void:
	var gcol := Color(1, 1, 1, 0.045)
	var gx := floorf((camera_x - SCREEN_W) / GRID) * GRID
	while gx < camera_x + SCREEN_W:
		var x := _sx(gx)
		draw_line(Vector2(x, -DRAW_PAD), Vector2(x, _view_h + DRAW_PAD), gcol, 1.0)
		gx += GRID
	var gd := floorf((distance + _car_y - _view_h - DRAW_PAD) / GRID) * GRID
	while gd < distance + _car_y + DRAW_PAD:
		var yy := _car_y + distance - gd
		draw_line(Vector2(-DRAW_PAD, yy), Vector2(SCREEN_W + DRAW_PAD, yy), gcol, 1.0)
		gd += GRID
