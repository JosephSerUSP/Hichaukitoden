# Particle sheets — what to draw

These are **placeholder** sheets used by the sample animations in
`data/animations.json`. Each currently shows a growing white ring per cell so
the flipbook visibly animates in the editor; replace them with real art at the
**same dimensions and cell layout**.

## Filename convention
`Name[CELLwxCELLh][Nf].png` — the tokens are read by the animation editor to
prefill cell size and frame count (e.g. `WindSlash[32x32][5f].png` → 32×32
cells, 5 frames). Cells are laid out **left-to-right** in a single row here, but
the engine reads them **row-major**, so a taller grid (multiple rows) also works
as long as the sheet width is a whole number of cells.

- Particles are **tinted** by the track's *Color over lifetime*, so draw the art
  **white / greyscale**; color comes from the animation.
- Backgrounds must be **transparent**.
- Blend is usually **Add (glow)** in these samples — draw bright cores, soft edges.

## Sheets to replace

| File | Size | Cells | Used by | Draw |
|------|------|-------|---------|------|
| `WindSlash[32x32][5f].png` | 160×32 | 5 × 32² | `skill.wind_blade` | A crescent slash arc sweeping/stretching across the 5 frames (thin → wide → fading). Reads as a single fast blade. |
| `HolyBurst[32x32][8f].png` | 256×32 | 8 × 32² | `skill.holy_smite` | A radiant starburst expanding over 8 frames: tight bright core (f0) → full 4/8-point flare (f4) → dissipating (f7). |
| `FlameLoop[16x16][8f].png` | 128×16 | 8 × 16² | `skill.flame_rebirth` | A flame flicker **loop** — 8 frames of a small tongue of fire wobbling so it tiles seamlessly (f7 → f0). |
| `DrainMote[16x16][6f].png` | 96×16 | 6 × 16² | `skill.drain_kiss` | A small pulsing mote / heart / soul-wisp, 6-frame loop (gentle throb). |
| `HealSpark[16x16][8f].png` | 128×16 | 8 × 16² | `item.heal_tonic` | A twinkle: a 4-point sparkle that appears, peaks, and fades over 8 frames. |

`Sparkles_16p.png` (256×256, 16×16 cells) already exists and is referenced by
the `Magic swirl` preset and `demo.particles_mask`.

## Sprites the presets suggest
The editor's particle **Starter presets** each print a recommended sprite when
applied. Most work with the built-in 2px dot; the ones worth a texture:
- **Confetti** — an 8×8 solid square; draw 2–4 color variants across cells.
- **Smoke plume / Puff** — a soft 16–32px round blob (softer = bigger).
- **Bubble rise** — a 16×16 hollow ring.
- **Nova burst** — a 16×16 star.
- **Magic swirl** — pair `Sparkles_16p.png` with a **Vortex Force Field** track.

## Regenerating placeholders
`node <scratchpad>/make_stubs.js assets/animation` rewrites the stub PNGs (only
needed if you want the placeholders back after experimenting).
