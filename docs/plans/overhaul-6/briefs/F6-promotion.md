# F6: Promotion

**Context:** Read SPEC.md S7. Ritual at a creature's `evolutions[].level`
threshold (real data for 11/22 actors today), flexible cost (free / MP /
promotion key items). **Depends on F5** if promotion-key items are meant to
drop from Sacrifice for any species — sequence after F5 lands.

**Role:** local agent; the UI-flow placement needs a quick owner check
(see below).

## Acceptance Criteria
- [ ] Promotion triggers at the `evolutions[].level` threshold already in
      `data/actors.json` — reuse that data as-is, don't add a parallel
      threshold field.
- [ ] Cost model supports all three modes per-species: free, MP (formula
      slot, same convention as F4/F5), or promotion key item(s).
- [ ] New item-gating vocabulary: a general-purpose gated-item field/
      category (SPEC S7 suggests something like `category:
      "promotion_key"` over a narrow `promotionKeyFor: <actorId>` field —
      prefer the general form so it's reusable if a similar gated-item need
      shows up elsewhere later).
- [ ] Ritual UI flow: **check with the owner** whether this lives in the
      reserve/roster UI (F3) or the Status scene before building it — don't
      guess a placement.
- [ ] Titania (the Pixie → High Pixie → Titania chain's final target) does
      NOT exist as an actor yet. Creating it is a content task, not this
      engine brief — flag it to the owner separately rather than adding it
      inline as a side effect of this brief.

**Gates:** G1, UI-golden for whichever scene gains the ritual flow, G3
visual check. G2 unaffected unless found otherwise.
