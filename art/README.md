# Art pipeline — textures & sprites per theme

Twisty Roads loads art by **convention**, exactly like the audio. Drop a file at

```
res://art/<theme>/<slot>.<ext>
```

and it is used automatically. If a theme is missing a slot, `res://art/default/<slot>`
is tried; if that's missing too, the built-in primitive drawing runs — so the game
looks correct with or without any art present.

- **`<ext>`** may be `png`, `webp`, `jpg`, `jpeg`, or `svg`.
- **`<theme>`** is one of: `default`, `synthwave`, `track`, `rally`, `jdm`,
  `jetski`, `sand`, `mud`, `rainbow`, `frostbite`.
- After adding files, **open the project in the Godot editor once** (or run an
  export) so they get imported — runtime loading uses the imported resources.

## Slots & authoring resolution

The game is top-down with **no perspective zoom**: 1 art pixel = 1 on-screen pixel
at the 720-wide design canvas, and textures are sampled **nearest** (crisp pixel-art
look). So author at the 1× sizes below — don't upscale, or nearest filtering will
alias it. (If you'd rather author at 2× for detail, also switch
`rendering/textures/canvas_textures/default_texture_filter` to *Linear* in
`project.godot`.)

| Slot | File name(s) | Drawn at | **Author at** | Notes |
|------|--------------|----------|---------------|-------|
| Player car | `car.png` | fit into 50 × 90, **aspect kept** | **~24 × 40–47** (drawn 2×) or 50 × 90 | Nose **up**. The sprite is never stretched: one uniform scale fits it into the 50 × 90 box, snapped to an integer (24-wide art lands on exactly 2×) so nearest-filtered pixels stay even. Hitbox **and shadow** auto-follow the opaque pixels — transparent margins are fine. |
| Enemy cars | `enemy.png` or `enemy_0.png`, `enemy_1.png`, … | fit into 50 × 90, **aspect kept** | **~24 × 40–47** (drawn 2×) or 50 × 90 | Nose **up** too (the engine flips them vertically to face the oncoming player). One file = one variant; numbered = random per car. Same no-stretch fit, opaque-pixel hitbox/shadow as the player. |
| Decorations | `deco.png` or `deco_0.png`, `deco_1.png`, … | native × 0.8–1.5 (random) | **~64 × 64** (small props) up to **~96 × 128** (tall props) | Off-road scenery. Native size = on-screen size at scale 1.0; each prop is randomly scaled 0.8–1.5×. Center the art, transparent background. Keep ≲ 160 px so it fits the off-road band. The shadow is the sprite itself tinted, so it matches the opaque pixels. |
| Road surface | `road.png` | 256 × 256 **world px** per repeat | **256 × 256** | UVs are anchored to WORLD coordinates on **both** axes (no stretching across the road width), so make it **seamless on all four edges** and a **uniform surface** (asphalt/tarmac grain, water, snow…). Avoid baked-in lane lines or anything directional — the road wanders across the tile grid. |
| Background | `background.png` | 256 × 256 **world px** per tile | **256 × 256** | Off-road ground. Tiled on the same 256-px world lattice as the road and scrolled **1:1 with it** (no parallax), so the ground and road read as one surface. Must be **seamless on all four edges**. Other sizes still load — they're drawn at the 256 × 256 world footprint. |

### Quick reference

- **Cars / enemies:** ~24 × 40–47 (shown at 2×), nose up, transparent margins; never stretched — hitbox & shadow follow opaque pixels.
- **Decorations:** ~64 × 64 (or up to ~96 × 128), centered, transparent.
- **Road:** 256 × 256, seamless all four edges, uniform.
- **Background:** 256 × 256, seamless all four edges, scrolls with the road.

## Audio (same convention, for reference)

Sound effects live at `res://audio/<name>.ogg` (or `.wav` / `.mp3`); see the
`_make_player` calls in `main.gd` for the slot names (`crash`, `coin`, `engine_low`,
`engine_high`, …). Missing files are simply silent.
