import json

with open('data/scenes.json', 'r') as f:
    scenes = json.load(f)

for scene in scenes:
    if scene['id'] == 'battle':
        hooks = scene['hooks']
        # add on_inspect hook handling: cancel goes back from inspection, other buttons are ignored/scroll?
        # But wait, we can just say if inspectingTarget then handle differently in handleInput.
        script = scene['scripts']['handleInput']

        # We need to insert a block for v.inspectingTarget
        new_block = """
if v.inspectingTarget then
    if v.action == "cancel" or v.action == "inspect" then
        v.inspectingTarget = false
    end
    return
end
"""
        # insert right after "if not memberInfo then\n    v.combatState = "log"\n    return\nend\n"
        script = script.replace(
            "if not memberInfo then\n    v.combatState = \"log\"\n    return\nend\n",
            "if not memberInfo then\n    v.combatState = \"log\"\n    return\nend\n" + new_block
        )

        # update targetSelect to handle inspect action
        # we can just add `elseif v.action == "inspect" then v.inspectingTarget = true`
        script = script.replace(
            "elseif v.action == \"cancel\" then\n        v.targetSelect = false\n        v.selectedIndex = v.prevSelectedIndex or 1\n",
            "elseif v.action == \"inspect\" then\n        v.inspectingTarget = true\n    elseif v.action == \"cancel\" then\n        v.targetSelect = false\n        v.selectedIndex = v.prevSelectedIndex or 1\n"
        )

        scene['scripts']['handleInput'] = script
        break

with open('data/scenes.json', 'w') as f:
    json.dump(scenes, f, indent=2)
