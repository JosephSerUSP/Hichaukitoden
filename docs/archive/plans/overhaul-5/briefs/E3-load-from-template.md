# E3: Load-from-template / reset-to-default for hooks

**Context:** SPEC S5 item 4. Today, clearing a scene hook or a flow phase's
command list just empties it (or, for battle phases with a legacy fallback,
`renderBattleFlowsEditor`'s "Remove Override" button deletes the override
entirely, reverting to the legacy Lua block — check that mechanism first,
it may already cover the "reset to default behavior" half of this brief for
built-in scenes/phases). This brief adds the other half: loading a named
starter template for hooks/scenes that have **no** legacy fallback (all
"extra" scenes, post-D13).

**Role:** local preferred. **Sequenced after E4**, which owns the template
registry schema and loader — this brief consumes that registry, it does not
define it.

## Acceptance Criteria
- [ ] Confirm and reuse (don't reinvent) the existing "revert to legacy"
      path for built-in scenes/phases with a fallback (`renderBattleFlowsEditor`
      "Remove Override" or equivalent — check whether custom-scene hooks have
      an analogous affordance already; if not, note that gap but don't scope
      it into this brief unless trivial).
- [ ] For hooks/scenes without a legacy fallback: a "Load from Template"
      action (button or context-menu item) that opens a picker of named
      starter templates (e.g. "Empty," "List + Confirm," "Simple Cutscene")
      and replaces the current hook's command list with a deep clone of the
      chosen template.
- [ ] Template data comes from E4's registry
      (`tools/editor/templates/scenes/*.json`) via E4's loader — no inline
      hardcoded JS template objects, no second template mechanism. A scene
      template stores full hook lists; this brief's "Load from Template"
      picker offers each template's individual hooks (or the whole hook set)
      as the source for the hook currently being edited.
- [ ] Loading a template is a destructive replace with confirmation (don't
      silently discard existing hook content).
- [ ] Zero console errors; a save round-trips correctly after loading a
      template.

**Gates:** G1, G3.
