import re

with open('main.lua', 'r') as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1

for i, line in enumerate(lines):
    if "if cmdDef then" in line and "local cmdDef = registry[id]" in lines[i-3]:
        start_idx = i
        break

if start_idx != -1:
    # Find the corresponding end for this if block
    indent = len(lines[start_idx]) - len(lines[start_idx].lstrip())

    # We want to replace it with:
    # if not cmdDef then goto continue end
    new_lines = lines[:start_idx]
    new_lines.append(" " * indent + "if not cmdDef then\n")
    new_lines.append(" " * indent + "    goto continue\n")
    new_lines.append(" " * indent + "end\n")

    curr = start_idx + 1
    found_end = False

    while curr < len(lines):
        line = lines[curr]
        if line.strip() == "::continue::":
            # The 'end' is presumably the line right before it, or somewhere near.
            # But wait, looking at the original file:
            #            if cmdDef then
            #                ...
            #            end
            #
            #            ::continue::
            break
        curr += 1

    for j in range(start_idx + 1, curr):
        line = lines[j]
        # find the final 'end' for this if block
        if j == curr - 1 and line.strip() == "end":
            continue # Skip the closing end for cmdDef

        # Un-indent
        if line.startswith(" " * (indent + 4)):
            new_lines.append(line[4:])
        else:
            new_lines.append(line)

    new_lines.extend(lines[curr:])

    with open('main.lua.fixed', 'w') as f:
        f.writelines(new_lines)
    print("Fixed file written to main.lua.fixed")
else:
    print("Could not find blocks")
