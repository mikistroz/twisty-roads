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
  `jetski`, `sand`, `mud`, `rainbow`, `frostbite`, `wiped`.
- After adding files, **open the project in the Godot editor once** (or run an
  export) so they get imported — runtime loading uses the imported resources.

## Slots & authoring resolution

The game is top-down with **no perspective zoom**: 1 art pixel = 1 on-screen pixel
at the 720-wide design canvas, and textures are sampled **nearest** (crisp pixel-art
look). So author at the 1× sizes below — don't upscale, or nearest filtering will
alias it. (If you'd rather author at 2× for detail, also switch
`rendering/textures/canvas_textures/default_texture_filter` to *Linear* in
`project.godot`.)

| Slot | File name(s) | Drawn at | **Author at (1×)** | Notes |
|------|--------------|----------|--------------------|-------|
| Player car | `car.png` | 50 × 90 px | **50 × 90** | Nose **up**. Transparent margins are fine — the hitbox auto-shrinks to the opaque pixels. |
| Enemy cars | `enemy.png` or `enemy_0.png`, `enemy_1.png`, … | 50 × 90 px | **50 × 90** | Nose **up** too (the engine flips them vertically to face the oncoming player). One file = one variant; numbered = random per car. |
| Decorations | `deco.png` or `deco_0.png`, `deco_1.png`, … | native × 0.8–1.5 (random) | **~64 × 64** (small props) up to **~96 × 128** (tall props) | Off-road scenery. Native size = on-screen size at scale 1.0; each prop is randomly scaled 0.8–1.5×. Center the art, transparent background. Keep ≲ 160 px so it fits the off-road band. |
| Road surface | `road.png` | tiles down the road | **512 × 256** | `U` (0→1) stretches across the **road width** (which varies ~240–510 px); `V` repeats every **220 world px** of length. Make it **vertically seamless** and a **uniform surface** (asphalt/tarmac grain, water, snow…). Avoid baked-in lane lines or anything that must keep a fixed width — `U` stretching means it would squash on narrow road and duplicate per-lane through forks. |
| Background | `background.png` | tiled full-screen | **512 × 512** | Off-road ground. Tiled in **both** axes and scrolled at 0.45× parallax, so it must be **seamless on all four edges**. 256×256 is lighter; 512×512 carries more detail. |

### Quick reference

- **Cars / enemies:** 50 × 90, nose up, transparent margins.
- **Decorations:** ~64 × 64 (or up to ~96 × 128), centered, transparent.
- **Road:** 512 × 256, vertically seamless, uniform.
- **Background:** 512 × 512, seamless both directions.

## Audio (same convention, for reference)

Sound effects live at `res://audio/<name>.ogg` (or `.wav` / `.mp3`); see the
`_make_player` calls in `main.gd` for the slot names (`crash`, `coin`, `engine_low`,
`engine_high`, …). Missing files are simply silent.
