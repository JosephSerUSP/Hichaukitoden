# F1: Summoner exits the battle loop

**Context:** Read SPEC.md S0–S2 and `docs/game design/Summoner.md`. The
Summoner currently fights (HP, command phase, loss-on-death). This brief
removes all of that — battle becomes creature-only.

**Role:** OWNER-SUPERVISED, not autonomous. This is the round's core
rewrite of `engine/battle.lua`/`engine/scenes/battle.lua`, exactly the kind
of change ORCHESTRATION.md's D8/D11 rule exists for. Pair with the owner or
have them review every step before committing, not just at the end.

## Acceptance Criteria
- [ ] `session.summoner` no longer appears in `getActiveParty()`
      (`engine/session.lua:170-180`) as a combatant; ally list is the 4
      active creatures only.
- [ ] `Battle:resolveRound` (`engine/battle.lua:94`) no longer takes/uses a
      `summonerAction` — summoner's turn phase is gone.
- [ ] `Battle:isDefeat()` (`engine/battle.lua:388-399`) loses the
      `session.summoner:isDead()` branch entirely; loss = all 4 active
      creatures dead, full stop.
- [ ] AI targeting no longer has a summoner-becomes-targetable-when-alone
      branch (`engine/battle.lua:43-56`).
- [ ] `presentation/renderer.lua`'s summoner status console block (sprite,
      HP/MP bar, spell list, command menu — around lines 659-690) is
      removed; `presentation/battle_layout.lua`'s summoner-specific layout
      constants (`summonerPopupX`, `summonerStatusX`, `summonerMpText/Bar*`)
      are removed or repurposed per your own PR note (don't leave them
      dangling unused).
- [ ] `session.mp`/`session.maxMp` fields are KEPT (still needed, no longer
      tied to a Battler-shaped summoner object).
- [ ] No dangling summoner Item entry point left mid-round — document in the
      PR what happens to Item access for this brief (F7 is where it lands
      properly on creature command lists; this brief just must not crash or
      soft-lock if a player presses whatever key used to open Item).
- [ ] Zero remaining references to the removed summoner-battle-participant
      code anywhere (grep for `summonerAction`, `isSummoner`, `summoner:isDead`
      etc. across engine/ and presentation/ after your changes).

**Gates:** G1, `battle.log` **regeneration is explicitly permitted here and
only here** — get explicit owner sign-off on the new recorded sequence
before committing it (screenshot/transcript the sequence for the owner to
read, don't just regenerate silently). Any UI-golden scene log that shows
summoner display (status/battle scenes) likely needs regeneration too — same
per-file sign-off rule. Do not regenerate any log this brief doesn't touch.
