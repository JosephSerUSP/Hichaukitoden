# Overhaul 6 — Summoner Rework (seed)

Not a formal plan yet — no SPEC.md, no briefs, no PLAYBOOK.md. This is a
scope map written while the design was still being brainstormed with the
owner (12.07.2026), so the shape of the work isn't lost before o5 wraps.
Design source of truth is `docs/game design/Summoner.md` — read that first;
this file only breaks it into implementation-shaped chunks.

Full formal planning (SPEC + briefs, PLAYBOOK sequencing) should happen once
overhaul-5 merges to main. This is very likely the o6 flagship, alongside
the Animation System noted in overhaul-5's `future-animation-system.md`.

## Rough scope map

Ordering is a guess, not a commitment — sequencing belongs in the real
PLAYBOOK once this becomes a formal round.

1. **Summoner exits the battle loop.** Remove summoner HP/command-phase/
   battle-console presence (renderer.drawBattle's summoner status block,
   BATTLE_INPUT's summoner-vs-monster branching, the loss condition check).
   Battle ends on all-active-creatures-dead, not summoner HP reaching 0.
   Golden-log-sensitive — the memory notes' D8/D11 owner-supervision rule
   applies here even harder than usual, this rewrites battle's core loop.

2. **MP becomes the central resource.** Continuous drain from active
   creatures (currently a per-round session-level drain exists for
   something else — audit before reusing), spell costs redirect correctly,
   MP-exhaustion-damage moves from summoner to active creatures. Needs a
   real balancing pass once numbers exist, not just plumbing.

3. **Reserve roster.** New session-data concept: 4 active + 8 reserve
   slots, reserve fully dormant (no drain/actions/targeting). Free swap
   from the field menu — likely lives in the new map scene's per-unit
   popup or a new field-menu command, needs a decision.

4. **Summon.** Species unlock flags (every actors.json entry gated behind
   one, off by default except starting species), diverse unlock sources
   (defeat/contract/negotiation/NPC/etc. — likely several small mechanics,
   not one system), fresh-instance minting at level 1 (or higher for extra
   MP via a formula), MP cost scaling by species tier.

5. **Sacrifice.** Permanent creature removal; MP refund scaled by level;
   conditional item rewards gated by state (HP%, level, conditions) AND
   species/discipline. Overlaps directly with Item Creation's per-species
   discipline identity (`docs/game design/itemCreation.md`) — the two
   systems should probably share a "creature identity" data shape rather
   than duplicating species-flavor tables.

6. **Promotion.** Ritual at the `evolutions[].level` threshold already
   present in actors.json (Pixie -> High Pixie is real data today; Titania
   doesn't exist yet). Cost is flexible per-species: sometimes free,
   sometimes MP, often promotion key items — which sacrifice is one
   source of among several. Needs new item-gating vocabulary (promotion
   key items as a distinct item category/flag) and a ritual UI flow.

7. **Battle command list.** Item joins each creature's own command menu
   (Attack/Skill/Defend/Item/Flee) now that the summoner doesn't act;
   Flee's ownership question resolved the same way.

## Open design questions not yet settled

- Exact unlock-condition data shape for summonable species (needs to
  support "diverse" triggers — defeat count, contract flag, NPC dialogue
  action, item held, etc. — probably a small rules-engine rather than one
  field).
- Where the reserve-swap UI actually lives (map popup vs. a promoted
  Status-scene-style flow).
- Balancing pass for MP costs/refunds/drain rates — explicitly deferred,
  needs real playtesting numbers, not a plumbing decision.
