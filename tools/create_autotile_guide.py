from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGBA', (256, 256), (0, 0, 0, 255))
draw = ImageDraw.Draw(img)

def draw_checkerboard(x0, y0, w, h, size, color1, color2):
    for y in range(y0, y0 + h, size):
        for x in range(x0, x0 + w, size):
            cx1 = x
            cy1 = y
            cx2 = min(x + size, x0 + w)
            cy2 = min(y + size, y0 + h)
            c = color1 if ((x - x0)//size + (y - y0)//size) % 2 == 0 else color2
            draw.rectangle([cx1, cy1, cx2 - 1, cy2 - 1], fill=c)

# Row 0: Ceiling & Sky (Purples & Cyans)
draw_checkerboard(0, 0, 64, 64, 8, (70, 30, 110, 255), (100, 45, 150, 255))
draw_checkerboard(64, 0, 64, 64, 8, (20, 90, 110, 255), (35, 130, 160, 255))
draw_checkerboard(128, 0, 64, 64, 8, (15, 60, 100, 255), (30, 90, 140, 255))
draw_checkerboard(192, 0, 64, 64, 8, (50, 20, 80, 255), (80, 30, 120, 255))

# Row 1: Wall & Wall Autotile Edges (Blues, Reds, Magentas)
draw_checkerboard(0, 64, 64, 64, 8, (20, 60, 140, 255), (40, 90, 190, 255))

# Row 1 Col 1: Autotile Edges (32px Left Edge, 32px Right Edge)
draw_checkerboard(64, 64, 32, 64, 8, (200, 40, 40, 255), (240, 100, 40, 255))  # Left 32px edge
draw_checkerboard(96, 64, 32, 64, 8, (180, 80, 20, 255), (220, 120, 40, 255))  # Right 32px edge

draw_checkerboard(128, 64, 64, 64, 8, (30, 50, 120, 255), (50, 75, 160, 255))

# Col 3: Torch / Feature overlay (100% transparent BG with torch graphic)
draw.rectangle([192, 64, 255, 127], fill=(0, 0, 0, 0))
draw.rectangle([216, 88, 232, 120], fill=(120, 60, 20, 255))
draw.ellipse([212, 72, 236, 96], fill=(255, 160, 20, 230))
draw.ellipse([216, 76, 232, 92], fill=(255, 230, 80, 255))

# Row 2: Doors (Golds & Browns)
draw_checkerboard(0, 128, 64, 64, 8, (160, 110, 20, 255), (210, 150, 30, 255))
draw_checkerboard(64, 128, 64, 64, 8, (140, 90, 15, 255), (180, 120, 25, 255))
draw_checkerboard(128, 128, 64, 64, 8, (120, 75, 10, 255), (160, 105, 20, 255))
draw_checkerboard(192, 128, 64, 64, 8, (100, 60, 10, 255), (130, 80, 15, 255))

# Row 3: Floors (Greens & Limes)
draw_checkerboard(0, 192, 64, 64, 8, (20, 110, 50, 255), (35, 160, 70, 255))
draw_checkerboard(64, 192, 64, 64, 8, (30, 130, 60, 255), (50, 180, 90, 255))
draw_checkerboard(128, 192, 64, 64, 8, (15, 90, 40, 255), (25, 130, 60, 255))
draw_checkerboard(192, 192, 64, 64, 8, (40, 100, 30, 255), (60, 140, 45, 255))

# Draw Grid Lines
for i in range(0, 257, 64):
    draw.line([(i, 0), (i, 256)], fill=(255, 255, 255, 200), width=2)
    draw.line([(0, i), (256, i)], fill=(255, 255, 255, 200), width=2)

# Draw Autotile 32px sub-grid line on Row 1 Col 1
draw.line([(96, 64), (96, 128)], fill=(255, 255, 0, 255), width=2)

# Render Labels
try:
    font = ImageFont.load_default()
except:
    font = None

labels = [
    (10, 24, "ROW 0:\nCEILING"),
    (74, 24, "ROW 0:\nSKY 1"),
    (138, 24, "ROW 0:\nSKY 2"),
    (202, 24, "ROW 0:\nSKY 3"),

    (10, 88, "ROW 1:\nWALL MID"),
    (65, 75, "LEFT\n32px"),
    (97, 75, "RIGHT\n32px"),
    (138, 88, "ROW 1:\nWALL VAR"),
    (202, 100, "TORCH"),

    (10, 152, "ROW 2:\nDOOR 1"),
    (74, 152, "ROW 2:\nDOOR 2"),

    (10, 216, "ROW 3:\nFLOOR 1"),
    (74, 216, "ROW 3:\nFLOOR 2"),
]

for lx, ly, txt in labels:
    if lx == 202 and ly == 100:
        continue # Skip torch tile text background to preserve transparency
    draw.text((lx+1, ly+1), txt, fill=(0, 0, 0, 255), font=font)
    draw.text((lx, ly), txt, fill=(255, 255, 255, 255), font=font)

img.save('assets/tilesets/autotile_guide.png')
print("Successfully generated assets/tilesets/autotile_guide.png")
