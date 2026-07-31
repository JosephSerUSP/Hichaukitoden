# Gate fixture — do not edit

`gate_fixture.efkefc` and everything in `textures/` exist for **G5 only**. They
are a frozen copy of a real effect (`SecondRite/basic_attack.efkefc` as of
30.07.2026) and are deliberately duplicated rather than referenced.

## Why this exists

G5 is the only gate that can see the world view, and the Effekseer integration
has already produced four bugs no other gate could catch:

- effects placed at `(x, 240 - y)` — a Y-position flip
- effects playing upside down — a separate Y-orientation flip
- effects rendering *behind* everything LOVE queued, for want of a batch flush
- LOVE's GL state left corrupted after an effect draw

Every one of those is in the **code path** and is independent of which effect is
playing. So the gate needs *an* effect on screen, permanently — not any
particular one.

## Why it is a duplicate, and frozen

Gating a real, in-use effect would turn G5 red every time that effect is
retouched. A gate that gets recaptured reflexively is worse than no gate: it
manufactures confidence without checking anything. This repo has already lost
~10 commits to a golden log that was red and unread.

The textures are copied rather than shared with `SecondRite/` for the same
reason — a retouch there must not redden this.

Being a copy of a real effect (rather than something minimal and synthetic) is
deliberate: it exercises the particle types, textures and blend modes actually
in use, so the fixture fails when the integration breaks for real content.

## Rules

- **Never edit these files.** Changing them defeats the entire purpose.
- If G5's `battle/battle/99-effekseer-fixture.png` goes red, that is a
  **renderer regression** until proven otherwise. Do not recapture to clear it.
- The only legitimate reason to touch this folder is a deliberate decision to
  re-baseline the fixture, which is owner-signed like any other recapture.

`data/animations.json` -> `system.gate_fixture` references it. That entry is
intentionally unreferenced by any skill, item or flow: it exists solely so the
screenshot harness can play it.
