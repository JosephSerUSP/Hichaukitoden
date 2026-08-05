# Opening Vertical-Slice Gap Audit

**Target:** St. Maria Opening & First Three Incursions (Walkthrough Chapters 01–03)  
**Date:** August 5, 2026

---

## 1. Walkthrough Claims Evidence Matrix

| Claim / Feature | Implementation Evidence (File, ID, Event, Flag) | Assigned Status | Remaining Work Category |
|---|---|---|---|
| **Carriage & Threshold Opening Sequence** | `data/commonEvents.json` (Common Event 42) — 91 commands playing cinematic plates (`arrival_ride.png`, `arrival_bell.png`, `arrival_room.png`, etc.) | `PLAYABLE_AND_VERIFIED` | Authored Content |
| **Passage House Room 3 Start** | `data/commonEvents.json` CE 42 transfers player to Passage House Room 3 text | `PLAYABLE_AND_VERIFIED` | Authored Content |
| **Saban Starter Moa (Actor 61)** | `data/actors.json` (Actor 61 Moa); `commonEvents.json` CE 42 text names Saban. **Note:** `data/system.json` party is null; Saban must be manually added to party | `PARTLY_IMPLEMENTED` | Authored Content |
| **Registration & Crossing Writ** | `data/items.json` Item 198 (`Crossing Writ`); `commonEvents.json` CE 33/34 checks `hasItem:198` before dungeon entry | `PLAYABLE_AND_VERIFIED` | Authored Content |
| **Town Shops (Alicia, Laura, Tankard)** | `data/shops.json` Shops 1 (Bakery), 2 (Forge), 5 (Tankard); `commonEvents.json` CE 37, 38, 39 | `PLAYABLE_AND_VERIFIED` | Authored Content |
| **Laura's Lunch Delivery** | `data/commonEvents.json` CE 38 sets `laura_lunch_carried`; CE 39 receives lunch, pays 25G, sets `laura_lunch_delivered` | `PLAYABLE_AND_VERIFIED` | Authored Content |
| **Cerberus First Contract** | `data/actors.json` Actor 32 (`Cerberus`); `data/maps.json` Map 2 Event 12 (`First Contract`) | `PLAYABLE_AND_VERIFIED` | Balance / Testing |
| **Ines Blue Line Mark** | `data/maps.json` Map 2 Event 11 (`Blue Chalk`); `commonEvents.json` CE 15, 33, 39 dialogue choice "Ines" | `PLAYABLE_AND_VERIFIED` | Presentation |
| **Incursion Counter Flags & Town Shift** | `data/commonEvents.json` CE 40 (Dungeon Entrance Stairs) tracks `incursion_one_completed`, `incursion_two_completed`, and sets `vigil_ready`. Changes Map 1 presentation to `town_003` with purple dusk fog | `PLAYABLE_AND_VERIFIED` | Authored Content |
| **The Vigil Festival & Chapel Ceremony** | `data/commonEvents.json` CE 35 (Chapel and Vigil) runs the 3-bell ceremony, sets `vigil_held`, changes presentation to night fog | `PLAYABLE_AND_VERIFIED` | Presentation |
| **Thestra Unclaimed Lantern** | `data/commonEvents.json` CE 35 inspects lantern with card `THESTRA` in protagonist's handwriting | `PLAYABLE_AND_VERIFIED` | Authored Content |
| **Room 3 Inspection Flags (Feed Bowl, Picture)** | Mentioned in walkthrough 01-arrival; no interactive events in Map 1/4 | `DESIRED_MEMORY_ONLY` | Authored Content |
| **Salt Table Reliquary Trap (Floor 2)** | `data/items.json` Item 207 (`Sealed Reliquary`); `data/maps.json` Map 5 Event 5 (`Misfiled Reliquary`); CE 39 appraises for 800G | `PLAYABLE_AND_VERIFIED` | Authored Content |
| **Saban Absence / Death Reactions in Town** | Walkthrough 02-first-three-incursions describes Alicia asking about unused feed; currently CE 38 lacks individual Saban death state branch | `DESIRED_MEMORY_ONLY` | Authored Content |

---

## 2. Technical Dependency Graph

```
[System Init / New Game]
      │
      ▼
[CommonEvent 42: Cinematic Opening] ──► (Player arrives at St. Maria Room 3)
      │
      ▼
[Registrar Interaction] ──────────────► [Grants Crossing Writ (Item 198)]
      │                                                │
      ▼                                                ▼
[Town Services (Shops 1, 2, 5)] ◄─────── [Gate Guard (CommonEvent 34)]
      │                                                │
      ▼                                                ▼
[Expedition 1: Floor 1 (Map 2)] ◄──────── [Labyrinth Entrance (CommonEvent 43)]
  ├── Cerberus Contract (Ev 12)
  └── Return Stairs (CE 40) ──► Sets incursion_one_completed
      │
      ▼
[Expedition 2: Floor 2 (Map 3)]
  ├── Salt Table / Reliquary (Item 207)
  └── Return Stairs (CE 40) ──► Sets incursion_two_completed & vigil_ready
      │
      ▼
[Town Visual Transformation (town_003 / purple_dusk)]
      │
      ▼
[Chapel Vigil Ceremony (CE 35)] ──► Sets vigil_held & reveals Thestra Lantern
```

---

## 3. Recommended 30–45-Minute Vertical Slice Boundary

The slice boundary encompasses:
1. **Opening:** Cinematic carriage arrival, Pass House Room 3 introduction, receiving Crossing Writ from Registrar.
2. **First Town Loop:** Purchasing supplies at Alicia's bakery, weapons at Laura's forge, accepting Laura's lunch errand.
3. **First Descent:** Entering Floor 1 (Bellroot Depths), encountering optional Cerberus (weighing 6 MPD drain vs combat strength), finding Ines blue chalk mark.
4. **First Return & Delivery:** Returning up stairs, delivering Laura's lunch for 25G, experiencing initial town dialogue updates.
5. **Second Descent:** Reaching Floor 2, encountering the Salt Table reliquary decision.
6. **Town Transformation:** Returning from second descent to find St. Maria transformed for the Vigil (purple dusk, name-cards), ending after attending the Chapel Vigil ceremony.

---

## 4. Key Strategic Questions Answered

* **Where does a new player begin?**  
  In Passage House Room 3 after `CommonEvent 42` cinematic cutscene.
* **Is Saban definitely present, named, and persistent?**  
  Saban is named in narrative text (`CommonEvent 42`) and is Actor 61 (Moa). Currently, `data/system.json` party is null; adding Saban directly to initial party array in `system.json` or `CE 42` ensures he starts in party.
* **Is registration mandatory and reliably communicated?**  
  Yes. `Crossing Writ` (Item 198) is required by Gate Guard (`CommonEvent 34`).
* **Can the player shop, prepare, enter the dungeon, return, save, and resume?**  
  Yes. Bakery (Shop 1), Forge (Shop 2), Tankard (Shop 5) work. Map 2 connects to Map 1 via stairs (`CommonEvent 40`). Save menu (Scene `save_menu`) works cleanly.
* **Is Cerberus recruitment complete and reversible?**  
  Yes. Cerberus is Actor 32 on Map 2 Event 12. Party dismiss handles reserve transfer.
* **What meaningful decision does the first expedition contain?**  
  Contracting Cerberus (massive combat strength vs 6x MPD traversal cost), delivering Laura's lunch, and claiming the Sealed Reliquary vs keeping emergency Bell Salt.
* **What town state recognizes the player's return?**  
  `CommonEvent 40` updates `incursion_one_completed`, `incursion_two_completed`, `vigil_ready`, and swaps town presentation tileset/fog.
* **Earliest point at which content visibly stops?**  
  After the Chapel Vigil ceremony (`CommonEvent 35`) and inspection of the `THESTRA` lantern.
* **Which missing pieces create greatest increase in player attachment per implementation hour?**  
  1. Auto-adding Saban (Actor 61) to party in `CE 42`.  
  2. Adding interactive Room 3 feed bowl event.  
  3. Adding Saban death/absence conditional dialogue at Alicia's bakery.

---

## 5. Prioritized 5–10 Backlog Tasks

1. **Auto-grant Saban on New Game:** Add `ADD_PARTY_MEMBER` (actorId 61) to `CommonEvent 42` so Saban is physically in party from step 1. *(Low risk / High value)*
2. **Room 3 Inspection Events:** Add 2 interactive inspection events to Map 4 (Borrowed Room) for feed bowl and coat hook. *(Low risk / High value)*
3. **Saban Absence Dialogue Branch:** Add conditional branch in `CommonEvent 38` checking if Actor 61 is dead or absent from party to trigger Alicia's feed inquiry. *(Low risk / High value)*
4. **Cerberus Traversal Cost UI Warning:** Add explicit dialogue line in Map 2 Event 12 warning of Cerberus 6 MPD traversal drain before contract confirmation. *(Low risk / Medium value)*
5. **Ines Blue Line Visual Marker:** Add a distinct floor tile / decal for the Ines mark on Map 2 Event 11. *(Low risk / Medium value)*

---

## 6. Systems to Defer

* **Multi-floor procedural dungeon generator:** Hand-authored maps 1–6 provide a superior 30–45 minute slice experience.
* **Advanced Item Creation / Synthesis:** Standard shop buying/selling satisfies the opening vertical slice without complex alchemy menus.
* **Full Permadeath Cemetery Scene:** Basic party death / game over scene is sufficient for the slice.
