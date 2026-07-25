# D6: Convert Menus (Title, Main Menu, Item, Status)

**Context:** SPEC S6. Proves the UI vocabulary generalises across standard list-driven menus. Incorporates menu-specific UI polish from feedback.

**Role:** Jules-shippable.

## Acceptance Criteria
- [ ] Convert `Title`, `Main Menu`, `Item`, and `Status` scenes into data hooks in `scenes.json`.
- [ ] **Feedback Integration (Items Menu):** Ensure the Item menu/inventory list spacing is corrected, and that it uses the full height of its window.
- [ ] **Feedback Integration (Equip Menu):** Add item icons to the Equip scene lists.
- [ ] **Feedback Integration (Status/Menus):** Ensure Levels and Experience are properly displayed in the applicable data-driven menus.
- [ ] The scene UI-golden log must be byte-identical before and after conversion (or explicitly justified if UI feedback tweaks intentionally change the layout events).

**Gates:** G1, G3 + UI-golden.
