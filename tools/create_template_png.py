from PIL import Image, ImageDraw

def create_template():
    w, h = 256, 256
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 64x64 grid
    # Row 0: Ceiling (Stone / Roots)
    for x in range(256):
        for y in range(64):
            c = 30 + (x * 7 + y * 13) % 25
            img.putpixel((x, y), (c + 10, c + 5, c + 25, 255))
    # Draw cave root lines in ceiling
    for i in range(4):
        cx = i * 64
        draw.line([cx + 10, 0, cx + 30, 40, cx + 50, 64], fill=(70, 50, 30, 255), width=3)
        draw.line([cx + 40, 10, cx + 20, 50], fill=(60, 40, 25, 255), width=2)

    # Row 1: Walls
    # (1,0): Base Wall Middle (Brick stone)
    for x in range(64):
        for y in range(64, 128):
            c = 50 + (x * 3 + y * 5) % 20
            img.putpixel((x, y), (c, c, c + 5, 255))
    for ry in range(64, 128, 16):
        draw.line([0, ry, 63, ry], fill=(20, 20, 20, 255), width=1)
    for rx in range(0, 64, 16):
        draw.line([rx, 64, rx, 127], fill=(25, 25, 25, 255), width=1)

    # (1,1): Left (0..15) and Right (48..63) Autotile Edges
    for y in range(64, 128):
        for x in range(64, 80):
            c = 70 + (x + y) % 15
            img.putpixel((x, y), (c + 30, c + 20, c, 255)) # Warm edge highlight
        for x in range(112, 128):
            c = 70 + (x + y) % 15
            img.putpixel((x, y), (c + 30, c + 20, c, 255))
    draw.rectangle([64, 64, 79, 127], outline=(200, 150, 50, 255), width=2)
    draw.rectangle([112, 64, 127, 127], outline=(200, 150, 50, 255), width=2)

    # (1,2): Dark Basalt Wall
    for x in range(128, 192):
        for y in range(64, 128):
            c = 25 + (x * 11 + y * 7) % 15
            img.putpixel((x, y), (c, c + 2, c + 5, 255))

    # (1,3): Wall Torch Overlay (Transparent PNG with Torch)
    # Torch wooden bracket
    draw.rectangle([210, 90, 214, 115], fill=(100, 60, 30, 255))
    draw.polygon([(206, 85), (218, 85), (214, 95), (210, 95)], fill=(120, 120, 120, 255))
    # Flame
    draw.ellipse([207, 72, 217, 86], fill=(255, 160, 20, 255))
    draw.ellipse([209, 75, 215, 83], fill=(255, 230, 80, 255))

    # Row 2: Doors
    # (2,0): Wooden Door
    draw.rectangle([0, 128, 63, 191], fill=(45, 40, 40, 255))
    draw.rectangle([8, 134, 55, 191], fill=(90, 55, 30, 255), outline=(50, 30, 15, 255), width=2)
    draw.ellipse([45, 162, 49, 166], fill=(220, 180, 50, 255))

    # (2,1): Arched Stone Door
    draw.rectangle([64, 128, 127, 191], fill=(40, 40, 45, 255))
    draw.arc([72, 134, 119, 180], 180, 360, fill=(150, 150, 150, 255), width=4)
    draw.rectangle([76, 155, 115, 191], fill=(15, 15, 20, 255))

    # Row 3: Floors
    # (3,0): Stone Flagstone Floor
    for x in range(64):
        for y in range(192, 256):
            c = 45 + (x * 5 + y * 9) % 20
            img.putpixel((x, y), (c, c, c, 255))
    for fy in range(192, 256, 16):
        draw.line([0, fy, 63, fy], fill=(25, 25, 25, 255), width=1)

    # (3,1): Floor Puddle Overlay (Transparent)
    draw.ellipse([80, 210, 115, 238], fill=(30, 90, 160, 180), outline=(80, 150, 220, 220), width=1)

    # (3,2): Sunken Water Floor
    for x in range(128, 192):
        for y in range(192, 256):
            c = 40 + (x * 3 + y * 7) % 30
            img.putpixel((x, y), (20, c + 40, c + 120, 255))

    # (3,3): Rubble Overlay (Transparent)
    draw.polygon([(200, 215), (208, 210), (212, 222), (202, 225)], fill=(90, 85, 80, 255))
    draw.polygon([(220, 230), (230, 225), (235, 238), (222, 240)], fill=(75, 70, 65, 255))

    import os
    out_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "tilesets", "template_tileset.png")
    img.save(out_path)
    print(f"Saved {out_path}")

if __name__ == "__main__":
    create_template()
