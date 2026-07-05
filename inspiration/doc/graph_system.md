# Node-Based Narrative Graph System

This system replaces the legacy `Game_Interpreter` state-map logic for NPC interactions. It uses a directed graph structure where nodes represent content (Text, Choice) or logic (Router, Action), and edges represent transitions.

## Architecture

### 1. Data Layer (`data/graphs/`)
Graph definitions are stored as JSON files in `data/graphs/`. The `data/graphs/index.json` acts as a manifest.

**Graph Structure:**
```json
{
  "id": "npc_example",
  "name": "Example NPC",
  "layout": "visual_novel", // Optional: 'visual_novel' or 'standard'
  "portrait": "NPC_Example", // Default portrait
  "initialNode": "start",
  "nodes": {
    "start": {
      "type": "TEXT",
      "content": "Hello world.",
      "next": "choice_node"
    },
    "choice_node": {
      "type": "CHOICE",
      "options": [
        { "label": "Shop", "target": "shop_action" },
        { "label": "Leave", "action": "close" }
      ]
    }
  }
}
```

**Node Types:**
*   **TEXT**: Displays dialogue.
    *   `content`: The text to display.
    *   `speaker`: (Optional) Name of speaker.
    *   `speakers`: (Optional) Array of `{ id, emotion, active }` for visual novel layout.
    *   `next`: ID of the next node (implicit "Continue").
*   **CHOICE**: Displays a list of options.
    *   `options`: Array of option objects.
        *   `label`: Button text.
        *   `target`: ID of the next node.
        *   `action`: Special action (e.g., `"close"`).
        *   `setFlag`: (Optional) Sets a story flag to true.
*   **ROUTER**: Conditional branching.
    *   `condition`: Condition string (e.g., `flag:met_npc`, `hasItem:potion`).
    *   `trueNode`: Target if condition is met.
    *   `falseNode`: Target if condition is not met.
    *   `branches`: (Optional) Array of `{ condition, target }` for multi-way branching.
*   **ACTION**: Executes a game effect.
    *   `action`: The action type (`OPEN_SHOP`, `TELEPORT`, `OFFER_QUEST`, `COMPLETE_QUEST`).
    *   `next`: Target node after action completes (if applicable).

### 2. Engine Layer (`src/engine/systems/director.js`)
*   **DirectorSystem**: Manages the `GraphWalker` and handles input (`CONTINUE`, `OPTION_SELECTED`). It notifies the observer (Adapter) of node changes.
*   **GraphWalker**: Maintains the current node pointer and history.
*   **TransitionLogic**: Evaluates condition strings against the game session.

### 3. Presentation Layer (`src/adapters/interpreter_adapter.js`)
The `InterpreterAdapter` acts as the observer. It listens to the Director and updates the `Window_Event`.
*   **Dialogue View**: `Window_Event` renders the text and choices.
*   **Action Handling**: The Adapter executes actions like opening shops or managing quests.

## Scope

Currently, the Graph System is implemented for **NPC Interactions** only.

*   **NPCs**: Fully migrated to Graph System.
*   **Shrines**: Use legacy `_openShrineEvent` logic (hardcoded scenarios).
*   **Traps**: Use legacy `_triggerTrap` logic.
*   **Map Events**: Simple events (Treasure, Battle) use standard event handlers.

## Extending the System

To add new actions:
1.  Update `src/adapters/interpreter_adapter.js` inside `_executeGraphAction`.
2.  Update `DirectorSystem` if the action requires pausing/resuming flow control.

To add new conditions:
1.  Update `src/engine/graph/transition.js` inside `TransitionLogic.evaluate`.
