from PIL import Image

def make_torch_background_transparent(file_path):
    img = Image.open(file_path).convert('RGBA')
    pix = img.load()
    w, h = img.size

    # Target torch cell in Row 1 Col 3: X from 192 to 255, Y from 64 to 127
    for y in range(64, min(128, h)):
        for x in range(192, min(256, w)):
            r, g, b, a = pix[x, y]
            # If the pixel color is grey/brown stone (similar to 108, 98, 80) and not the flame/bracket
            # Flame is bright yellow/orange (R > 200, G > 100, B < 150)
            # Bracket is dark brown/metal (R < 90, G < 60, B < 40)
            # Stone background is greyish (R around 80-120, G around 80-120, B around 70-110)
            is_flame = (r > 180 and g > 90) or (r > 200)
            is_bracket = (r < 70 and g < 60 and b < 50)
            if not is_flame and not is_bracket:
                pix[x, y] = (0, 0, 0, 0)

    img.save(file_path)
    print(f"Fixed torch transparency in {file_path}")

make_torch_background_transparent('assets/tilesets/dungeon_001.png')
make_torch_background_transparent('assets/tilesets/template_tileset.png')
