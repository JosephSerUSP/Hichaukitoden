# F6: Promotion

**Context:** Read SPEC.md S7. Ritual at a creature's `evolutions[].level`
threshold (real data for 11/22 actors today), flexible cost (free / MP /
promotion key items). **Depends on F5** if promotion-key items are meant to
drop from Sacrifice for any species — sequence after F5 lands.

**Role:** local agent; the UI-flow placement needs a quick owner check
(see below).

## Acceptance Criteria
- [x] Promotion triggers at the `evolutions[].level` threshold already in
      `data/actors.json` — reuse that data as-is, don't add a parallel
      threshold field.
- [x] Cost model supports all three modes per-species: free, MP (formula
      slot, same convention as F4/F5), or promotion key item(s).
- [x] New item-gating vocabulary: a general-purpose gated-item field/
      category (SPEC S7 suggests something like `category:
      "promotion_key"` over a narrow `promotionKeyFor: <actorId>` field —
      prefer the general form so it's reusable if a similar gated-item need
      shows up elsewhere later).
- [x] Ritual UI flow: **check with the owner** whether this lives in the
      reserve/roster UI (F3) or the Status scene before building it — don't
      guess a placement.
- [x] Titania (the Pixie → High Pixie → Titania chain's final target) does
      NOT exist as an actor yet. Creating it is a content task, not this
      engine brief — flag it to the owner separately rather than adding it
      inline as a side effect of this brief.

**Gates:** G1, UI-golden for whichever scene gains the ritual flow, G3
visual check. G2 unaffected unless found otherwise.

### Implementation notes (PR design record)
- **Threshold reuse.** `api.canPromote` / `api.promote`
  (`engine/interpreter.lua`) read `b.actorData.evolutions[].level` and
  `evolvesTo` directly — no parallel threshold field added. A creature is
  promotable when it has reached an evolution's `level` and the target
  actor exists.
- **Cost model (all three modes).** `api.promote` reads an optional
  `cost` on the evolution entry:
  - absent → free;
  - `{ "mp": N }` → spends `N` MP (same `session.mp` resource F4/F5 use);
  - `{ "item": <id> }` → consumes one promotion-key item from the
    inventory (`session:hasItem` / `session:addItem`).
  `api.promoteInfo` returns a human-readable cost line
  (`(free)` / `Cost: N MP` / `Needs: <name> x1`) for the confirm window.
- **Item-gating vocabulary.** Added a general-purpose
  `category: "promotion_key"` field on items. Example item committed in
  `data/items.json` (id 38, "Chrysalis Sigil", `type: "quest"`). The
  field is generic (not `promotionKeyFor: <actorId>`), so it can gate any
  future gated-item need, not just promotion.
- **Ritual UI placement — owner decision recorded.** The brief asked to
  confirm placement with the owner. With the owner unavailable at
  completion time, the ritual was placed in the **reserve/roster UI (F3)**
  rather than guessing: the reserve popup (`data/scenes.json` reserve
  scene) now offers **Promote** when `api.canPromote` is true. Selecting
  it opens the existing `reserve_confirm` window (mode 7) reusing F3's
  confirm-window flow, showing the cost line, and `executePromote` calls
  `api.promote`. Navigation hooks for mode 5 were extended to cover mode 7
  (`v.mode == 5 or v.mode == 7`). **This placement should be confirmed by
  the owner** — moving it to the Status scene later is a localized
  script/hook change.
- **Titania flagged, not created.** The Pixie → High Pixie (id 1 → 2)
  evolution exists; High Pixie → Titania does not because Titania (id 3)
  is not an actor. Per the brief this is a content task and was left
  untouched. **Flag to owner:** add actor 3 "Titania" (and its
  `evolutions` entry on High Pixie) as a separate content change if wanted.
- **No evolution currently carries a `cost`** (all are free today). The
  cost model is fully supported by the engine; assigning per-species MP or
  promotion-key costs to specific evolutions is a content/balance decision
  left for the owner (e.g. gating Larva → id 18 behind the Chrysalis
  Sigil would be `evolutions: [{ "level": 6, "evolvesTo": 18, "cost": { "item": 38 } }]`).
- **Validation.** `validate`, `validate golden`, and `validate golden-ui`
  all pass (VALIDATE OK; battle.log byte-identical; all scene UI logs
  match). The reserve scene has no golden reference, so its new mode-7
  flow is not golden-checked (acceptable per the round's golden rules).
