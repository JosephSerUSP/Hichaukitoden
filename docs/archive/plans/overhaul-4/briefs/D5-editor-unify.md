# D5: Editor: Unify Flows/Scenes

**Context:** SPEC S8. Merges the "Custom Scenes" property form and the "Phase Flows" command-list editor into a single unified tab.

**Role:** Jules-shippable.

## Acceptance Criteria
- [ ] Collapse Custom Scenes and Phase Flows into a single unified "Flows" editor tab.
- [ ] List scene hooks as phases, editable via `renderCommandList` and the command palette.
- [ ] Filter the command palette to only show commands with `contexts: ["scene"]` when editing scene hooks.
- [ ] Move scene `config` into a small property panel inside the scene editor.
- [ ] Provide a `{ } JSON` toggle per hook.

**Gates:** G1, G3.
