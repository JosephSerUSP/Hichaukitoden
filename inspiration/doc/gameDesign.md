# Game Design Document

## 1. Core Philosophy: The Unified System
The game's architecture is built on a unified "Effect & Trait" system. Everything that modifies a battler's state—whether temporary (like a buff), permanent (like equipment), or innate (like stats)—is handled through this system. This ensures maximum flexibility for creating novel mechanics.

---

Traits: These modify or change characteristics of battlers, or/and trigger Effects. They are properties of Equipment, Passives and States. 
Some examples:
'hit' - for calculating the chance of hitting enemies with meelee physical attacks. default is 0 (means 100% chance. 10 would mean a 110% chance.)
'eva' - for calculating the chance of evading enemy melee physical attacks. default is 0. (means 0% evasion chance. 10% would mean a 10% chance.)
'cri' - for calculating the chance of inflicting a critical hit on actions that can crit. Default is 0.
-many other RPG Maker MZ traits that make sense in the context of the design of this game.-
'eleAdd' - Adds a new element to the battler's 'ele' array.
'eleChg' - Changes all elements of this battler's 'ele' to instances of the target element, adding one if it would otherwise be empty.
'paramMod' etc - ways to affect a battler's parameters, such as 'mhp', 'mpd', 'mxa'.
'actionMod' etc - ways to affect a battler's Action's properties, such as 'actionSpeed'. 
'trigger: effect' - Traits can execute Effects on certain triggers, such as restoring HP when winning a battle.
Traits should be flexible. I should be able to cover novel traits without needing to hardcode them.


-Effects: These directly affect battlers, such as changing hp, applying states, changing level / xp / parameters, etc. 
'learnAction' - Teaches an action to a creature. 
'learnPassive' - Teaches a passive to a creature. 
'elementAdd' - Adds a new element to the battler.
'elementChange' - Changes all elements of this battler to the target element. If the battler has no elements, it should now have one.
Effects should be flexible. I should be able to cover novel effects without hardcoding them. For example, I should be able to write an effect that changes a battler's maxActions on the fly, even if a 'changeMaxActions' effect doesn't exist.


-


Both Effects and Traits also must generate description strings. These are going to be attached to an object's description. For example, a "Mythril Sword"'s "Description" field might just say "A sword made from legendary ore.", but, dynamically, "Increases ATK by 5." will be appended to its description, and (ATK 12 -> ATK 17 (+5)) will be shown in the equip preview when equipping this item.
Characteristics such as Scope and Condition must also be dynamically shown on the description.

## 2. Trait Objects (The Sources)
A **Trait Object** is any entity that carries **Traits**. A `Game_Battler` aggregates traits from all its active Trait Objects to calculate its final parameters and state.

All Trait Objects have:
*   `condition`: A condition that must be met for the object's traits to be active (e.g., "HP < 50%").

**Types of Trait Objects:**
1.  **Passives**: Innate or learned abilities.
2.  **Equipment**: Only one weapon can be equipped. Any combination of any other equipment type can be equipped. (Most units have only 1 equipment slot.)
    *   `price`: Cost in shops.
3.  **States**: Temporary conditions applied to battlers.
    *   **Expiry**: States expire based on flexible criteria (turn count, probability, triggers).
4.  **Battlers**: The units themselves. They are the base Trait Object for themselves and inherit traits from Passives, Equipment, States and the PC.
    * `lvl`, `exp` etc. 
    * `mHp` - how much hp they can have at maximum.
    * `mpd` - how much mp they drain from the summoner on every action. 
    * `atk` - an outgoing multiplier for physical abilities. default is 10 = 100% damage. 
    * `mat` - an outgoing multiplier for magical abilities. default is 10 = 100% damage.
    * `def` - an incoming multiplier for physical abilities. default is 10 = 100% damage.
    * `mdf` - an incoming multiplier for magical abilities. default is 10 = 100% damage.
    * `mxa` - the maximum amount of abilities this battler can have learned. Default is 4. 
    * `mxp` - the maximum amoutn of passives this battler can have learned. Default is 2.
    * `ele` - an array of elements the creature is aligned with. This can be repeated instances of the same element. It is used as: an outcoing multiplier for all abilities (1.25x for each instance of an 'same' elemental match), 2. an incoming multiplier for all abilities (1.25x for each instance of a 'resistance' or 'weakness' type elemental match )
    * `eqs` - how many equipment slots that unit has. Default is 1.

EFFECT OBJECTS:
1.Actions: Apply Effects to targets. They can be:
1.a.Skills: Used by creatures. They, by default, cost nothing to use.
1.b.Spells: Used exclusively by the PC. They, by default, consume MP on use.
2.Items: Used exclusively by the PC. They, by default, consume themselves on use.

They have the following properties:
-'asp' - The decisive factor in deciding action order. The #1 criteria for defining action execution order is the final 'asp' of actions that are going to be executed on that turn.
PC Actions (Spells and Skills) don't care for this - they're always instant as the PC's turn is out of the regular turn order flow.
-'ele' - actions often have an element. Their damage is increased by *1.25 for every instance of that element that the caster also has, which is separate from resistance and weakness mechanics.
-'cnd' - a condition required for this Action to be available. For example, some Actions require the Battler to be on the Front Row or have less than 50% HP.



-Summoner:
The Player Character. 
'mmp / mp' - for exploration mechanics and spellcasting. 
Performing actions (such as moving) in the dungeon drains their MP. When it hits 0, the creatures get progressively weaker, gaining a penalty to damage and success rates and losing HP with each step. This weakness gets worse every turn the PC has 0 MP.

Instead of acting automatically, after every round the Summoner has access to a direct action:
Use Item, Formation, Spell or Flee.
Flee does not consume a turn and can be attempted unlimitedly; it results in a random loss of money and counts as an action for the purposes of MP loss. Flee chance increases with every attempt.

The summoner will only perform basic attacks if all its creatures are downed or in reserve; Only then will they be targetable by single target enemy attacks. They are targeted by multi-hit skills. 

Summoner Spells: - In exchange for MP (and thus, lasting less in the dungeon), the Summoner can favorably intervene in a battle.
Cure -> Cure All -> Raise  
Protect -> Wall



EXAMPLE COMPLEX ACTIONS: 

Potion Rain: 
Condition: Having one of a few different types of healing items in the inventory.
Cost: Consuming the healing item.
Effect: Restores HP equal to the healing item's normal restoration effect to every party member. Effect is multiplied by 80% for every valid target. (on a )


EXAMPLE COMPLEX TRAITS:

Mug: 
Trigger: On dealing damage.
Effect: Gains gold equal to damage dealt. 

Proficient: 
Trait: Increases the effect of other traits bestowed by equipment by 'value'%. 



Creatures:
They have the following:
Genus: 'Celestial','Demon','Fey','Spirit','Construct','Beast','Undead','Other'
Evolution information
Recruit information