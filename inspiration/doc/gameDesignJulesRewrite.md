# Game Design Document

## 1. Core Philosophy: The Unified System
The game's architecture is built on a unified "Effect & Trait" system. Everything that modifies a battler's state—whether temporary (like a buff), permanent (like equipment), or innate (like stats)—is handled through this system. This ensures maximum flexibility for creating novel mechanics.

---

## 2. Trait Objects (The Sources)
A **Trait Object** is any entity that carries **Traits**. A `Game_Battler` aggregates traits from all its active Trait Objects to calculate its final parameters and state.

All Trait Objects have:
*   `condition`: A condition that must be met for the object's traits to be active (e.g., "HP < 50%").

**Types of Trait Objects:**
1.  **Passives**: Innate or learned abilities.
2.  **Equipment**: Weapons, Armor, Accessories.
    *   `price`: Cost in shops.
3.  **States**: Temporary conditions applied to battlers.
    *   **Expiry**: States expire based on flexible criteria (turn count, probability, triggers).
4.  **Battlers**: The units themselves (Actors/Enemies). They are the base Trait Object for themselves.

---

## 3. Traits (The Modifiers)
**Traits** are static properties attached to Trait Objects. They modify the battler's **Parameters** or trigger **Effects**.

### 3.1. Parameter Modifiers
Traits modify the inputs for the `Game_Battler` parameter system:
*   **Base Parameters (`param`)**: Additive integer modifiers to base stats.
    *   `PARAM_PLUS: 'atk'` (Increases Attack)
*   **Ex-Parameters (`xparam`)**: Additive percentage modifiers.
    *   `HIT`: Hit Rate (Base 0%).
    *   `EVA`: Evasion Rate (Base 0%).
    *   `CRI`: Critical Rate (Base 0%).
*   **Special Parameters (`sparam`)**: Multiplicative rate modifiers.
    *   `TGR`: Target Rate (Aggro).
    *   `GRD`: Guard Effect.

### 3.2. State Modifiers (Non-Numeric)
Some traits alter the logic or state of the battler directly via functional getters:
*   `eleAdd`: Adds an element to the battler's alignment.
*   `eleChg`: Overrides the battler's elemental alignment.
*   `actionMod`: Modifies properties of the battler's actions (e.g., speed boost).

### 3.3. Triggered Traits
Traits can listen for specific triggers (Events) and execute **Effects**:
*   `Mug`: Trigger: "On Damage Dealt". Effect: Gain Gold = Damage.

---

## 4. Effects (The Changes)
**Effects** are the mechanisms that make immediate changes to the game state. They are typically applied by **Actions**.

**Common Effects:**
*   `damage`: Reduces HP.
*   `heal`: Restores HP.
*   `addState`: Applies a State Trait Object.
*   `learnAction`: Unlocks a new Skill.
*   `elementChange`: (Immediate) Permanently changes alignment.

**Flexibility**: The system allows defining novel effects (e.g., `changeMaxActions`) without hardcoding, by mapping Effect Keys to handler functions in the `Game_Action` logic.

---

## 5. Battlers (The Subjects)
Battlers are the entities in combat. Their statistics are derived dynamically using the `param`/`xparam`/`sparam` system.

### 5.1. Core Statistics (`param`)
*   `mhp` (Max HP): Maximum health.
*   `mpd` (MP Drain): Amount of MP drained from Summoner per action.
*   `atk` (Attack): Physical damage multiplier (Base 10 = 100%).
*   `mat` (Magic): Magical damage multiplier (Base 10 = 100%).
*   `def` (Defense): Physical damage reduction (Base 10 = 100%).
*   `mdf` (M.Defense): Magical damage reduction (Base 10 = 100%).
*   `mxa` (Max Actions): Action points per turn (Default 4).
*   `mxp` (Max Passives): Passive slots (Default 2).

### 5.2. Elements
Battlers have an elemental alignment array (`battler.elements`).
*   **Outgoing**: 1.25x damage for each instance of a matching element.
*   **Incoming**: 1.25x damage taken for Weakness matches, 0.75x for Resistance.

---

## 6. Actions (The Mechanics)
All combat maneuvers are encapsulated in the `Game_Action` class.

**Types:**
1.  **Skills**: Used by creatures. Default cost: None.
2.  **Spells**: Used by PC. Default cost: MP.
3.  **Items**: Used by PC. Default cost: Consumes Item.

**Properties:**
*   `speed` (was `asp`): Determines turn order (Battler Speed + Action Speed). PC actions are instant.
*   `element`: The elemental type of the action.
*   `condition` (`canUse`): Predicate for availability (e.g., "Row: Front", "HP < 50%").

**Complex Action Example: "Potion Rain"**
*   **Condition**: Inventory contains specific Item IDs.
*   **Cost**: Consume 1 Unit of that Item.
*   **Scope**: All Allies.
*   **Effect**: Heal HP (Item Value * 0.75 * Target Count).

---

## 7. The Summoner (The Player)
The Player Character (PC) acts as the commander.
*   **MP Management**: MP is the "fuel" for the dungeon run. 0 MP -> progressive party debuffs (`param` penalties).
*   **Turn**: Can perform **one** Action (Spell, Item, Formation) per turn.
*   **Flee**: A special action that does not consume the turn but costs MP/Money.

---

## 8. Dynamic Descriptions
The UI must generate descriptions dynamically by aggregating Traits and Effects.
*   *Example*: A "Mythril Sword" has a base description "Legendary ore." and a trait `PARAM_PLUS: 'atk', value: 5`.
*   *Result*: "Legendary ore. Increases ATK by 5."
*   *Preview*: `(ATK 12 -> 17 (+5))` shown in equipment menus.
