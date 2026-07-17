import re

with open('main.lua', 'r') as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1

for i, line in enumerate(lines):
    if line.strip() == "if cmdDef then":
        if "if cmdDef.deprecatedBy then" in lines[i+1]:
            start_idx = i
            break

for i in range(start_idx, len(lines)):
    if "::continue::" in lines[i]:
        # we need to find the matching end for cmdDef
        # well, we can just replace the block.
        pass

if start_idx != -1:
    new_lines = lines[:start_idx]
    new_lines.append("            if not cmdDef then goto continue end\n\n")

    # We find the end matching this if.
    # The if is at level 12 spaces.
    curr = start_idx + 1
    while curr < len(lines):
        line = lines[curr]
        if line.strip() == "::continue::":
            end_idx = curr - 1
            while end_idx > start_idx and lines[end_idx].strip() != "end":
                end_idx -= 1
            break
        curr += 1

    for j in range(start_idx + 1, end_idx):
        line = lines[j]
        # remove 4 spaces of indentation
        if line.startswith("    "):
            new_lines.append(line[4:])
        else:
            new_lines.append(line)

    new_lines.extend(lines[end_idx+1:])

    with open('main.lua.fixed', 'w') as f:
        f.writelines(new_lines)
    print("Fixed file written to main.lua.fixed")
else:
    print("Could not find blocks")
