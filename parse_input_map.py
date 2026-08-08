import re

with open('engine/input_map.lua', 'r') as f:
    content = f.read()

# Replace SELECT = "tab" with SELECT = "lshift"
content = content.replace('SELECT = "tab"', 'SELECT = "lshift"')

# Also replace SELECT = "on_page" with SELECT = "on_inspect"
content = content.replace('SELECT = "on_page"', 'SELECT = "on_inspect"')

with open('engine/input_map.lua', 'w') as f:
    f.write(content)
