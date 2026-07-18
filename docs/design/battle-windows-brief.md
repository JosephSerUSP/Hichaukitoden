# Battle Windows Conversion — Brief (rev. 2, matches design rev. 2)

**Context:** `docs/design/summoner-rework.md` (decided 17.07.2026,
rev. 2) and `docs/SPEC.md` §1.2. Converts the last legacy-drawn scene —
battle — to `"draw": "windows"`, then deletes the legacy renderer path.
Stage 1 touches `engine/battle.lua` and is **owner-supervised** (SPEC §5).

## Stage 1 — Engine prerequisites (owner-supervised) — DONE 17.07.2026

Landed with battle.log byte-identical (no sanctioned regen needed: the
golden fixture's summoner-spell cast became the same skill cast by its
owner). Validator gained wave/permadeath/row simulation coverage.

- [x] **Remove summoner spells**: the spell action type and the
      `system.summoner.spells` slot-1 path leave `resolveRound`; the
      config key and its validator check retire. (Skills the list pointed
      at remain valid data — only the battle-casting mechanic goes.)
- [x] **Emergency wave**: when every fielded spirit is down at a round
      boundary and the reserve is non-empty, the reserve wave (up to 4)
      deploys automatically at no MP cost; the party forfeits that round
      (enemies still act). Emits a `wave` event for the UI/log.
- [x] **Permadeath + auto-bank**: at battle end (victory or flee), every
      spirit still down is removed permanently and its EXP value banks at
      `summoner.sacrificeExpRate`; emits events the victory flow surfaces.
      No hardcoded values — rates/formulas from config.
- [x] **Game over** condition becomes: fielded party wiped AND reserve
      empty. (Previously: party wiped.)
- [x] **Row flag**: each fielded spirit carries `row = "front"|"back"`,
      persisted in the session, readable as a formula token. No combat
      math consumes it this round — state + access only.
- [x] Golden impact: battle.log WILL change (spell path removed, wipe
      semantics changed) — regeneration is sanctioned for this stage
      only, owner reads the diff before it lands. Validator updates:
      row values check, retired spell check removed.

## Stage 2 — Windows conversion (presentation only) — DONE 17.07.2026

- [x] **Shared cost/gain gauge preview** — `ui.drawBar`'s `preview` param
      + `buildGaugePreview` in window_renderer.lua (gauge and row-scoped
      list-gauge content blocks). Not yet consumed by battle's MP gauge
      (still the plain shared party-HUD readout) or ritual/shops — the
      widget exists and is validator-checked; wiring it into a specific
      scene is a follow-up.
- [x] battle.draw = "windows"; `data/scenes.json` battle now carries
      `windows`: `battle_enemies` (style enemyRow), `battle_command`
      (style command, listId `v:commandRows` populated by the new
      `refreshConsole` scene script), `battle_help` (frame, shown during
      input), `battle_log` (style battleLog, the reveal-timer panel),
      `battle_victory` (style victoryPanel, the drain animation). Party
      grid/MP, target reticles, and the screen-flash overlay stay
      cross-cutting calls (`drawSharedPartyHud`, `drawTargetReticles`,
      `renderer.drawScreenFlashOverlay`) run unconditionally for the
      battle scene in `main.lua`'s `love.draw`, same treatment as damage
      popups — not any one window's content, matching this doc's final
      classification (target_overlay/popups were never meant to be
      windows).
- [x] Geometry: `enemyRow`/`battleLog`/`victoryPanel` styles dispatch to
      new `presentation/renderer.lua` functions
      (`drawEnemyRowWindow`/`drawBattleLogWindow`/`drawVictoryPanelWindow`)
      that keep reading `battleLayout` (data/engine.json) exactly as
      before — pixel-identical geometry, now existence/visibility-gated
      by data instead of a hardcoded Lua branch. `battle_command` is the
      one piece using genuinely new rect-driven geometry (the generic
      "command" style).
- [x] `renderer.drawBattle` (the old monolithic function) and its
      `main.lua` call site are DELETED. window_renderer.lua's SPEC S2
      fallback rule is now moot for battle (no other scenes referenced
      it specifically; the fallback rule itself stays for future
      conversions of other scenes).
- [x] battle.log byte-identical (no gate-affecting change — this stage
      was presentation-only, as required). UI-golden trace for scene
      'battle' byte-identical too (that trace is structurally minimal —
      it doesn't push a real v.battle — so it wasn't a meaningful visual
      check either way; see verification notes below).
- [ ] **Owner playtest** — a real interactive battle round, watching for:
      command-bar bordered-slot look (intentional style change — see
      note), party grid/MP still showing, target reticles, victory
      drain animation, log reveal timing. Not yet done.

**Verification actually performed (no owner playtest yet):** G1/G2/G3
green; `lovec . preview-scene battle` screenshot confirms the command
console + help panel render with correct content/highlight/cursor
(enemy row is blank in this screenshot only because the headless preview
harness never populates `v.battle` — a pre-existing limitation of the
preview tool, not a bug in this conversion); `lovec . test-battle` run
for 6s with real enemies produced zero Lua errors (exercises the
shader/particle enemy-row path under real state). Party grid, reticles,
and the victory drain animation were NOT visually confirmed — they are
unchanged code paths (same functions, same call sites, still called
unconditionally for battle), but a live playtest is the real check.

**Known visual change (intentional, flag for owner review):** the
command console now uses the shared "command" style (bordered box per
slot, same look as e.g. the reserve swap-target picker) instead of the
old borderless bar with a cursor icon. This is a deliberate reuse of the
existing system-wide option-menu widget rather than a bespoke bar, per
SPEC 2.1. Reverting to the old bare-bar look would be a small follow-up
(a `bordered:false` flag on `drawCommandSlots`) if preferred.

**Gates:** G1 VALIDATE OK; G2 byte-identical; G3 all scenes byte-identical.
