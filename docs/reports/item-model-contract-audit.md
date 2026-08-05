# 3D Item-Model Integration Contract Audit

**Date:** August 5, 2026  
**Target:** `data/items.json`, `presentation/item_model_view.lua`, `assets/models/items/**`, `engine/validator.lua`, `tests/test_item_model_assignments.lua`

---

## Executive Summary

The 3D item-model integration contract across the item database was audited for path validity, extension standards, MTL/geometry resolution, duplicate mapping classification, orphaned assets, and mechanical enforcement.

* **Total items in database:** 207 items (66 consumable, 124 equipment, 17 quest).
* **Items assigned a model:** 52 items (IDs 1 through 52).
* **Unique OBJ files in `assets/models/items/`:** 53 OBJ files (+ 53 matching MTL files).
* **Referenced OBJ files:** 50 OBJ files.
* **Unreferenced (orphan) OBJ files:** 3 OBJ files (`bottle_family__molten.obj`, `bottle_family__round.obj`, `placeholder_question.obj`).
* **Contract Enforcement Gaps Identified & Fixed:** G1 validator (`engine/validator.lua`) was updated to enforce that `item.model` paths end with `.obj` and that any referenced `.mtl` material file exists on disk.

---

## Audit Verification Results

1. **Path existence:** All 52 referenced model paths exist on disk.
2. **Case-sensitivity:** 100% case-sensitive match between `data/items.json` and filesystem paths.
3. **Extension standard:** All 52 assigned model paths use the `.obj` extension.
4. **MTL resolution:** All 50 referenced `.obj` files declare `mtllib` references that resolve to existing `.mtl` files in `assets/models/items/`.
5. **Material declaration matching:** Every `usemtl` symbol referenced in the OBJ files is declared via `newmtl` in the corresponding MTL file.
6. **Path portability:** Zero machine-specific or absolute paths found. All paths are relative (`assets/models/items/...`).
7. **Runtime geometry parsing:** 100% of referenced OBJ/MTL pairs parse cleanly via `obj_model.load`.
8. **Directory / unsupported file assignment:** Zero assignments to directories or non-OBJ files.
9. **Malformed model failure mode:** Missing or corrupted OBJ files trigger loud warning logs and fall back to `placeholder_question.obj` without crashing the game engine or window renderer.

---

## Model Duplicates & Classification

Only **one** shared model representation exists across the assigned roster:

* **`assets/models/items/wind_charm.obj`** (Used by 3 items):
  - `[7]` **Wind Charm** (equipment)
  - `[8]` **Light Amulet** (equipment)
  - `[9]` **Alert Charm** (equipment)

### Classification
* **Category:** *Shared representation*.
* **Rationale:** Items 7, 8, and 9 currently share the same OBJ/MTL appearance. `iconPalette` affects 2D icon presentation and is not consumed by `item_model_view.lua`; no item-specific 3D palette differentiation was found. Any shared authorial intent remains a hypothesis.
* **Suspicious/Accidental duplications:** 0 found.

---

## Unreferenced OBJ Files in `assets/models/items/`

The directory contains 3 unreferenced OBJ files:

1. **`bottle_family__molten.obj`** (+ `.mtl`): Unassigned variant in the bottle family asset set. Candidate for fire/molten potion items.
2. **`bottle_family__round.obj`** (+ `.mtl`): Unassigned variant in the bottle family asset set. Candidate for round potion bottles.
3. **`placeholder_question.obj`** (+ `.mtl`): Dedicated runtime fallback mesh used by `item_model_view.lua` when an item lacks a model or fails to load. Not assigned to any item in `data/items.json` (as verified by unit test).

---

## Model Coverage Breakdown

### Coverage by Item Type

| Item Type | Total Items | With 3D Model | With Key Art | With Both | Coverage % (Model) |
|---|---:|---:|---:|---:|---:|
| **Consumable** | 66 | 14 | 63 | 14 | 21.2% |
| **Equipment** | 124 | 28 | 120 | 28 | 22.6% |
| **Quest** | 17 | 10 | 15 | 10 | 58.8% |
| **Total** | **207** | **52** | **198** | **52** | **25.1%** |

### Coverage by Tier (`meta.tier`)

| Tier | Total Items | With 3D Model | With Key Art | With Both |
|---|---:|---:|---:|---:|
| **Tier 1** | 14 | 0 | 14 | 0 |
| **Tier 2** | 17 | 0 | 17 | 0 |
| **Tier 3** | 38 | 0 | 37 | 0 |
| **Tier 4** | 16 | 0 | 16 | 0 |
| **Tier 5** | 8 | 0 | 8 | 0 |
| **Untiered (IDs 1–52)** | 52 | 52 | 52 | 52 |
| **Untiered (IDs 53–114)** | 62 | 0 | 56 | 0 |

### Key Art vs. Model Cross-Coverage

* **Items with Key Art but NO Model:** 146 items (e.g. Celestial Fossil `[53]`, Blackroot `[54]`, Iron Knife `[57]`, Steel Sword `[58]`).
* **Items with Model but NO Key Art:** 0 items (every item with a 3D model also defines 2D key art).

---

## Mechanical Enforcement Changes Made

### G1 Validator Upgrade (`engine/validator.lua`)
Updated item model validation in `validator.lua` (lines 1017–1035):
1. Enforces that `item.model` (when specified) ends with `.obj`.
2. Inspects `mtllib` declarations inside `item.model` and validates that the referenced `.mtl` file exists in `assets/models/items/`.

### Automated Verification
Ran:
- `lovec . validate` -> **VALIDATE OK**
- `lovec . unittest` -> **480 passed, 0 failed** (includes `test_item_model_assignments.lua` and `test_item_model_view.lua`)
- `tools/golden/check-state.ps1` -> **Engine state doc matches.**
