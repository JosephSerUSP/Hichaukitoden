# Event-Driven Content — Action Sequences, Quest Hooks, Editor Themes

Status: **planned** (owner decisions taken 17.07.2026). Three
independently-shippable workstreams sharing one unifying pattern. No
implementation has started; this is the execution plan.

## 0. The unifying pattern (name it once, reuse it)

**Default + override command lists.** The engine already instantiates
this three times: map events (inline commands or a `scriptId` into
commonEvents), battle phases (`data/flows.json` — editable defaults,
one command language), and scene hooks. The pattern's rule:

- A **default** command list, exposed in the editor, defines standard
  behavior. Deleting/replacing it changes the game globally.
- Individual entries **override** by naming a shared list ("Common") or
  carrying an inline one ("Custom") — the event/commonEvent split.
- Everything compiles through `engine/interpreter.lua`'s one registry;
  the validator walks it all with `validateCommands` under a
  per-host context.

Workstreams A and B are the 4th and 5th instantiations. When they land,
`docs/SPEC.md` §1.1 gets this pattern written down as a named rule.

**Hard constraint carried from the battle architecture** (SPEC, and the
race-condition lesson of 17.07): command lists run inside the
deterministic simulation and *emit events* for the paced replay. They
orchestrate the event stream; they never block on real-time animation.
G2 (golden battle log) stays the gate proving it.

---

## A. Action Sequences (skills)

Owner decision: **orchestration + APPLY_EFFECT**. `skill.effects` stays
the single source of damage/heal math; sequences decide *when and how
it lands*, Visustella-style, with repeatable APPLY_EFFECT for
multi-hits. No sequence = the default sequence reproduces today's
behavior exactly.

### Schema

- `data/actionSequences.json` — named sequences, shaped like
  commonEvents: `{ "<id>": { "name": ..., "commands": [...] } }`.
  Reserved id **`default`** (validator hard-requires it, same rule as
  `system.*` animation entries). Later: `default_item` (stage A4).
- Skill assignment mirrors map events exactly:
  - `skill.actionSequence = "<id>"` → Common (named) sequence
  - `skill.actionSequenceCommands = [...]` → Custom (inline)
  - neither → reserved `default`
- New registry context `"action_sequence"`. New/extended commands:
  - **`APPLY_EFFECT`** — applies the acting skill's `effects[]` to the
    resolved targets, emitting damage/heal/death events exactly as the
    current inline loop does. Repeatable (multi-hit). v1 applies all
    effects to all targets per invocation; per-index/multiplier params
    can extend later (extensibility rule: unknown optional fields
    ignored).
  - **`PLAY_ANIM`** (exists) — gains an `on = "actor" | "target"`
    param; emits the `play_anim` event with its target ref.
  - **`WAIT`** (exists) — emits the `wait` event; the battle replay
    loop must learn to pause on it (today it would be silently
    skipped by `advanceLog`).
  - `EMIT_TEXT`, `SCRIPT` etc. already work.
- Sequence ctx: `a` (actor), `target`, `skill`, `battle`, `session` —
  the existing formula tokens already cover it.

### Stages

- [ ] **A1 — engine.** `Battle:resolveRound`'s per-turn block (the
      `action` event + `targeting.resolve` + effects loop) is replaced
      by: emit the `action` event engine-side (it carries live object
      refs the log formatter needs), then run the resolved sequence
      through `interpreter.runImmediate` with events appended to
      `roundEvents`. The shipped `default` sequence is exactly
      `[ { APPLY_EFFECT } ]` → **G2 must stay byte-identical**. That
      byte-identity IS the acceptance test for A1.
- [ ] **A2 — replay.** `engine/scenes/battle.lua` processEvent/advanceLog
      handle `wait` (pause the queue for its duration, respecting the
      existing isAnythingPlaying gates) and `play_anim` (play on the
      event's resolved ref). The 500ms hardcoded delay in the `action`
      handler (`animation_player.play(ev.animation, ev.target, 500)`)
      becomes part of the default sequence's authoring surface instead
      of a magic constant — i.e. skill-assigned animations migrate from
      "played implicitly by the action event" to "played by PLAY_ANIM
      in the default sequence". Golden impact: only if the emitted
      stream changes; target is none for defaults.
- [ ] **A3 — editor.** New Database tab "Action Sequences" hosting the
      SAME `renderCommandList` command editor events/commonEvents use
      (palette filtered by the `action_sequence` context). The skill
      form gains a sequence picker: `(Default) / <common list> /
      Custom…` — identical UX to the map event scriptId picker. The
      reserved `default` entry is right there in the tab: "the default
      action sequence(s) are exposed in the editor" (owner direction).
- [ ] **A4 — items.** Same treatment: `item.actionSequence`, reserved
      `default_item`, `Battle:applyItem` routes through it.
- [ ] Validator: sequences walk through `validateCommands` under the
      new context; `skill.actionSequence` refs must resolve; reserved
      `default` present; APPLY_EFFECT rejected outside action-sequence
      context.

---

## B. Quest hooks (and making quest data live)

Owner decision: **default sequence reads quest data**. Finding that
motivated it: `quests.json`'s `requirements`/`rewards` blocks are
currently consumed by *nothing* at runtime — only flags move on
offer/complete; rewards are never granted; graphs hand-roll
`hasItem:` checks. Quests stay (owner supports them); the dead data
comes alive through defaults.

### Schema

- `data/flows.json` gains a **`quest` host**: `quest.offer` and
  `quest.complete` default command lists — flows is already exactly
  "editable defaults per phase".
- Quest entries may override: `quest.hooks = { on_offer = [...],
  on_complete = [...] }` (optional, per-quest Custom).
- New data-driven commands (context `"quest"`):
  - **`QUEST_TAKE_REQUIREMENTS`** — reads `ctx.quest.requirements`,
    verifies and consumes (consume-flagged) items; emits a
    `quest_requirements_failed` event if unmet so the graph can branch.
  - **`QUEST_GRANT_REWARDS`** — reads `ctx.quest.rewards`, grants
    gold/items/xp, sets flags, emits text events for each grant.
  - Existing SET_FLAG/EMIT_TEXT/GAIN_GOLD etc. available for Custom
    hooks.
- Default `quest.complete` = `[ QUEST_TAKE_REQUIREMENTS,
  QUEST_GRANT_REWARDS ]`; default `quest.offer` = flag set + text.

### Stages

- [ ] **B1 — engine.** `main.lua`'s hardcoded `OFFER_QUEST` /
      `COMPLETE_QUEST` walker branches become thin: resolve the
      quest, run per-quest hook or `flow.run("quest.offer"/"quest.
      complete", { session, quest })`, keep the accept/complete node
      routing. The `quest:<id>:active/completed` flag convention is
      preserved (graphs' `questStatus:` conditions keep working).
      Behavior change to REVIEW with owner: quests start actually
      granting their declared rewards — the four shipped quests'
      reward blocks go live. (Graph-side takeItem fields become
      redundant with requirement consumption — audit the four NPC
      graphs for double-consumption when landing.)
- [ ] **B2 — editor.** Quest form gains a hooks editor (same
      `renderCommandList`, context `quest`) beside the existing
      requirements/rewards editors; the `quest` flow defaults are
      editable wherever battle flow defaults are edited today.
- [ ] Validator: hooks walk `validateCommands`; quest flow host
      required; QUEST_* commands rejected outside quest context;
      existing requirement/reward item-ref checks stay.
- Out of scope, noted for later: absorbing the whole conversation-graph
  dialect (ROUTER/ACTION nodes) into the main registry, and a quest-log
  scene (no scene consumes quest summaries/objectives yet).

---

## C. Editor themes ("Studio" surface)

Owner decisions: themes apply to the **editor**, not the game; they
live in a third editor surface (not Database, not Engine); storage is
**tools/editor file + delete from data/**.

### Facts grounding the salvage

- The editor's CSS is already fully variable-driven: ~13 `:root`
  variables (`--win-gray/-white/-shadow/-dark-shadow/-black`,
  `--desktop-teal`, `--title-blue/-light`, `--text-color/-muted/-empty`,
  `--cool-bg`, `--font-family`). Theming = overriding `:root`.
- `data/themes.json` carries 3 complete, well-structured 33-token
  palettes (Original / Classic / Night) — window chrome, bezels,
  terminal, tiles, gauges, semantic text colors, tooltips.
- Known bug to fix in passing: `widgets.js` uses `var(--win-blue)`
  which is never defined.

### Stages

- [ ] **C1 — migrate + delete.** Stock themes move to
      `tools/editor/themes.json` (devtool config; served by server.js
      via `GET/POST /api/editor-themes`, still committable/shareable).
      Then delete the game-side surface entirely: `data/themes.json`,
      `themes` from both DATA_FILES manifests (server.js +
      engine/server.lua), `loader.themes` + its validator dictColls
      entry, and the Database Themes tab (`buildThemeForm`,
      `createNewTheme`, `deleteTheme`, `themeColorKeys` in database.js).
      Quests tab STAYS in Database.
- [ ] **C2 — apply.** A token→variable mapping layer sets `:root`
      variables from the active theme on load:
      `window-bg→--win-gray`, `desktop-bg→--desktop-teal`,
      `window-header-bg-start/end→--title-blue/-light`,
      `window-text→--text-color`, `bezel-light/shadow/dark→--win-white/
      -shadow/-dark-shadow`, `content-bg→--cool-bg`, plus newly-defined
      variables for currently-hardcoded colors as they're found
      (selection, tooltip, and `--win-blue` gets defined from
      `text-highlight`). Unmapped tokens (terminal, tile-*, gauge-*)
      are kept in the file for later surfaces — tile-*/fog naturally
      themes the map-editor canvas in a follow-up.
- [ ] **C3 — Studio surface.** Third top-level area beside Database and
      Engine: a Preferences/Studio dialog hosting the theme picker
      (live preview — just swap `:root` values) and the theme editor
      (reuse the existing color-grid form the Database tab had).
      Active theme id persists in `localStorage`; definitions persist
      in the shared file.

---

## Sequencing

C is small and fully independent — good first ship. A is the core
engine work (A1's byte-identical-G2 gate makes it safe to land early).
B reuses A's editor patterns (command-list pickers on an entity form)
and reads best landed after A3. A and B both end with a SPEC.md update
naming the default+override pattern.

Gates for every stage: G1 `VALIDATE OK`, G2 byte-identical (except
where a stage explicitly declares sanctioned content changes — none
are expected), G3 strict.
