import json

with open('data/scenes.json', 'r') as f:
    scenes = json.load(f)

for scene in scenes:
    if scene['id'] == 'battle':
        # Let's fix the bug in "battle_inspector" visible logic:
        # We also need to add it to layer properly. Actually it was already added to `windows`.
        pass
