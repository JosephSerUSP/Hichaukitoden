1. *Bind Inspect command.*
   - Use `replace_with_git_merge_diff` on `engine/input_map.lua` to map `SELECT` to `on_inspect` and set its default key to `lshift`.
2. *Create Battler Inspector UI.*
   - Execute a Python script with the `json` module via `run_in_bash_session` to modify `data/scenes.json`.
   - Add a new `battle_inspector` window widget with style `battlerInspector`.
   - The original `battle_target_info` window remains as the compact recognition surface, but hides when the detailed inspector is open.
3. *Implement `battlerInspector` view.*
   - Use `replace_with_git_merge_diff` on `presentation/window_renderer.lua` to add the `battlerInspector` branch.
   - Use `replace_with_git_merge_diff` on `presentation/renderer.lua` to implement `renderer.drawBattlerInspector(session, bv, x, y, w, h)`.
   - The view renders the battler card on the left and a list of active states (with exact stack counts) and their authored descriptions on the right.
4. *Handle Inputs in Battle Scene.*
   - Execute a Python script with the `json` module via `run_in_bash_session` to modify the `handleInput` script of the battle scene in `data/scenes.json`.
   - Handle the `inspect` action, which toggles `v.inspectingTarget`.
   - When inspecting, the `up` and `down` actions modify `v.inspectStateIdx` to scroll through the active states. `cancel` and `inspect` close the view.
5. *Verify Changes.*
   - Use `run_in_bash_session` with `git diff` and `git diff --cached` to verify the code and JSON modifications were applied correctly.
6. *Run Tests.*
   - Use `run_in_bash_session` with `xvfb-run love . validate` to ensure tests pass.
7. *Complete pre-commit steps to ensure proper testing, verification, review, and reflection are done.*
8. *Submit the change.*
   - Use `submit` to submit the change. (Wait, the memory says "When an execution plan involves creating a pull request using gh pr create, ensure it includes the explicit preceding Git commands". But I usually use the `submit` tool to finish the task. Let's see if the issue requires `gh pr create`. No, the issue doesn't state it, but if it does, I should just use `submit`. Wait, I will use `run_in_bash_session` with `git checkout -b feature/battler-inspection`, `git add .`, `git commit -m "Extend battle target inspection into a full battler information view"`, `git push -u origin feature/battler-inspection`, and `gh pr create --title "Extend battle target inspection into a full battler information view" --body "..."` as suggested). Wait, I don't have `gh` CLI installed. Let's stick with `submit` since I'm acting as the agent. I will specify `submit` tool.
