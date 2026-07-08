HUMAN FEEDBACK (08.07.2026 at 7.11 AM)

GAME:
1. Text should have a small delay before each character where applicable / in messages. This includes the Show Text command as well as the battle log.

Battle:
1. The summoner's HP is not shown in the battle UI. 
2. Enemy sprites aren't being shown in battle, instead using the default red square, despite most if not all Actor IDs having sprite keys.
3. Items don't have their icons on the Equip scene.
4. Creature Element icons should be displaced by 3 pixels in the x and y directions. 
5. Party members's sprites should also be displayed in battle (and on most menus). I propose a new property for Actors: Small Sprite. 
This is the sprite type that should be displayed in the Window_BattleStatus (or whatever it's called here), and on other menus where there's no room for the full sprite.
Its format is that of an animated sprite, its cell count being composed of its width divided by its height, rounded down. By default (and what the default layout should expect),
these sprites are (24*variable number of frames)x24; Damage popups, shake effects*, animations* (*we don't have these yet.) should display on them.
6. The summoner's battle status should sit at the top, besides the front row of the creature slots, but on the left.
7. The battler commands menu should be its own window, that opens and closes and sits flush with the battle status. 
8. The Battle log should support two lines. 
9. We need a dedicated Victory window. 

Menus:
1. Items menu has an arbitrarily larger list spacing. The "xQty" number should be nudged left by 4 pixels as well, it's currently too flush to the right side of the window.
This should be an universal, not a local, ruling, so any element that is right-aligned sits at ui.tileSize from the right border. 
2. Black border around headers should be removed. 
3. Crafting menu text (options / crafting description) sits too close to the header. This should be a global, not a local, configuration. 
(it is currently different in the main menu and crafting scenes.)
4. Crafting user sprite is oddly upscaled -- I believe 2x?
5. Inventory list doesn't use the full height of its window.
6. Levels and experience are nowhere to be found. 

EDITOR:
1. Descend Stairs is a rather ultra-specific command. We should have a more general Teleport command instead. 
2. The editor still needs visual work. The changes in the Terms tab was great but we similarly need vertical labels for fields in other areas, 
3. Icons should be the top leftmost element in all applicable data tabs. 
4. Image previews should themselves work as the editable element; No need for a dedicated string field or [ ... ] field. Instead, double-clicking on these should open up the selector.
5. The selector should preview in full resolution on the right what the sprite that's currently selected looks like - animated if applicable.