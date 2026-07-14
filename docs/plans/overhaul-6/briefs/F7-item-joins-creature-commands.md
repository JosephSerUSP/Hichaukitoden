# F7: Battle command list — Item joins creature commands

**Context:** Read SPEC.md S8. With the summoner gone from battle (F1),
Item needs a new home on each creature's own command list. **This brief has
a real scope fork buried in it — read the acceptance criteria before
starting, do not just start coding.**

**Role:** OWNER-SUPERVISED. Sequence last (depends on F1 being stable, and
likely wants F3's roster-UI selection conventions for target/member
picking).

## Acceptance Criteria
- [ ] **Before anything else**: confirm with the owner, explicitly, whether
      creature turns become PLAYER-DRIVEN in battle now that creatures are
      the only combatants (Summoner.md's "command list" phrasing implies
      yes — a command *list* only makes sense with a chooser), or whether
      the AI keeps picking Attack/Skill/Defend/Flee automatically and Item
      is simply a new option the **AI** can also select. These are very
      different scopes:
      - Player-driven: build a full interactive per-creature command menu
        (Attack/Skill/Defend/Item/Flee), reusing `commands_summoner`'s old
        UI plumbing where it fits (`engine/scenes/battle.lua`'s state
        machine shape, `presentation/renderer.lua`'s command-bar drawing).
      - AI-driven: extend `getAIAction` (`battle.lua:28-90`) with an Item
        branch in its existing decision logic; no new menu UI at all.
      Do not proceed past this bullet without an explicit owner answer.
- [ ] Whichever path: using an item spends that creature's turn (per
      Summoner.md) — same turn-economy rule either way.
- [ ] If player-driven: target/member selection reuses F3's roster-UI
      conventions rather than a third bespoke selector.
- [ ] `commands_monster` term (`data/terms.json:34-39`, currently vestigial)
      either becomes real (player-driven path) or stays display-only and
      gets a one-line comment explaining why it's unused (AI-driven path) —
      don't leave it silently orphaned either way.

**Gates:** G1, G2 (`battle.log` regeneration permitted here too if the
player-driven path is chosen — same owner-sign-off protocol as F1; NOT
permitted if the AI-driven path is chosen, since that shouldn't change
recorded battle behavior beyond adding one more available AI action, which
should still be deterministic under the golden seed), UI-golden for the
battle scene, G3 visual check, real playtest of a full battle.
