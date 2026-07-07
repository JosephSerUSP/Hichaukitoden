# C6 — Cancel reverts modal changes

- Branch: `o3/c6-modal-cancel-revert`  |  Runtime needs: G3
- Read first: SPEC.md Ground rules; FEEDBACK.md round 2, editor item 1

## Goal
Cancel/× on any editor modal must restore the payload to its state when the
modal opened. The Engine window and Damage Popup modal already do this via a
JSON snapshot (see `engineModalSnapshot` in tools/editor/js/engine-editor.js);
the Database modal, Event editor, Map Properties, and command dialog do not.

## Do
- Generalize the snapshot pattern: on open, deep-snapshot the section(s) the
  modal edits; on OK/Apply keep; on Cancel/× restore in place (references
  must stay valid — restore into the existing objects like closeEngineModal
  does) and clear dirty state.
- Apply to: Database modal (snapshot whole dbPayload minus maps? snapshot the
  sections the tabs edit), Event editor modal, Map Properties, command
  add/edit dialog (already rebuilds cmd on OK — just ensure no mutation
  before OK), Change Maximum.
- Keep the existing confirmDiscard prompts.

## Acceptance
- [ ] For each modal: edit a field, Cancel → change gone after re-open AND
      after Save Database (server file untouched)
- [ ] OK/Apply still persists; G3 green; PR checklist filled in
