# Future: the Animation System & Animations Tab (owner direction, 10.07.2026)

**Status:** direction note, not a brief. Likely the flagship of overhaul 6.
Recorded now so nearer-term work (E8's smallBattler damage feedback, the
configurable enemy flash) is built as a *seed* of this system rather than
more one-off hardcoding.

## The owner's framing

An **Animations tab** in the editor, similar to RPG Maker's — but with one
deliberate departure: RPG Maker's animation editor only covers animations
*assigned to skills/items*. Ours must ALSO expose **system animations** as
first-class editable entries:

- the damage **flash** (enemies already flash when targeted — that behavior
  must become configurable data, not a hardcoded renderer constant),
- the damage **shake**,
- the **death animation** (currently a hardcoded purple-tint/fade in
  `drawBattle`),
- smallBattler equivalents of all of the above (E8 hardcodes a first version;
  it should later dissolve into this system),
- and eventually screen/map-level effects (screen shake, fades) as well.

**Everything battler-related that animates should exist in the animation
editor.** Screen/map-related animation is a "perhaps" — design it so the
door stays open, don't force it into v1.

## Shape it will probably take (sketch, not spec)

- `data/animations.json`: named animation entries — timing, color/tint
  curves, offsets/shake amplitude, sprite-sheet references for drawn
  effects. Two entry classes: *assignable* (referenced by skills/items) and
  *system* (referenced by reserved keys: `system.damage_flash`,
  `system.death`, `system.small_damage`, ...).
- An engine-side animation player that renderer call sites consult instead
  of hardcoded timers/colors (today: `battleAnims` flash/death timers and
  constants live inline in `presentation/renderer.lua`).
- Editor tab following the registry pattern (like Effect Types / Trait
  Codes): system keys pre-seeded and always present; assignable entries
  creatable/deletable; skills gain an `animation` field.
- Validator: skill `animation` refs resolve; system keys all present.

## What NOT to do before then

- Don't add more hardcoded animation constants to the renderer when a task
  touches flash/shake/death behavior — put the numbers in data
  (`battleLayout` or a small `battle_screen.animations` block in
  system.json) so the future system has clean values to absorb.
- Don't register animation-related commands (PLAY_ANIM exists for scenes)
  beyond what a task strictly needs — same discipline as audio (o4 SPEC S9).

## Relationship to current work

- **E8** (smallBattler flash/shake + dead display) implements the immediate
  owner ask with configurable values in data — the first entries the future
  system will absorb.
- The existing enemy flash (`anim.flashTimer`, hardcoded 0.35s and colors in
  renderer) should get its constants moved to data during E8 while the file
  is open — "configurable" is the owner's explicit ask.
