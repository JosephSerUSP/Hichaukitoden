import requests
import base64
import json
import sys

API_KEY = "AQ.Ab8RN6KaFN3rTUETO8NQE0BPDVi_hqut4o7ftCCx8RHLUGqMsA"
MODEL = "gemini-3.1-flash-lite-image"

PROMPT = (
    "Create a 1024x1024 pixel texture sheet containing a 4x4 grid of 256x256 seamlessly-tiling surface textures "
    "for a PS1-era dungeon crawler game. CRITICAL STYLE REQUIREMENTS: these must look like flat surface textures "
    "photographed head-on with NO perspective, NO 3D depth cues, NO vanishing points. "
    "Think Quake, Doom, King's Field -- raw flat texture maps applied to 3D geometry. "
    "The texture style must be: low-res pixel art, dithered shading, chunky pixels 4-8px, slightly blurry like bilinear PS1 filtering, "
    "harsh contrast, no smooth gradients, limited colour palette (16-32 colors per tile), "
    "realistic but pixelated, dark and gritty, absolutely NO cartoon outlines, NO cel-shading, NO watercolor. "
    "Tile contents: "
    "(row1 col1) rough grey dungeon stone wall bricks viewed perfectly flat head-on, mortar joints, mossy patches, "
    "(row1 col2) darker grey stone wall bricks variation, slight orange torch staining upper-left, "
    "(row1 col3) rough dark grey stone, cracked and worn, "
    "(row1 col4) dark basalt-like stone, nearly black, veined. "
    "(row2 col1) dungeon floor flagstones viewed perfectly flat top-down, worn stone, grime lines, "
    "(row2 col2) mossy flagstone floor, green patches in cracks, "
    "(row2 col3) wet dungeon floor, dark reflective puddles on flagstone, "
    "(row2 col4) rough rubble and broken stone floor, debris. "
    "(row3 col1) dark ceiling stone, rough and pitted, stalactites hinted, "
    "(row3 col2) dark stone with iron chains texture, rust stains, "
    "(row3 col3) carved stone with gothic relief pattern, flat view, "
    "(row3 col4) bone and skull embedded stone wall, horrific, flat. "
    "(row4 col1) red-stained stone wall, dark bloodstains on grey bricks, "
    "(row4 col2) crumbling stone with roots growing through, dungeon wall flat, "
    "(row4 col3) wooden plank floor texture, dark rotting wood, "
    "(row4 col4) pure black abyss texture, slight rock edges. "
    "No borders, no labels, no gaps between tiles. Pure raw texture sheet."
)

payload = {
    "contents": [
        {
            "parts": [
                {"text": PROMPT}
            ]
        }
    ],
    "generationConfig": {
        "responseModalities": ["IMAGE", "TEXT"]
    }
}

url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={API_KEY}"

print(f"Calling Gemini image generation API: {MODEL}")
resp = requests.post(url, json=payload, timeout=120)
print(f"Status code: {resp.status_code}")

if resp.status_code != 200:
    print("Error body:")
    print(resp.text[:2000])
    sys.exit(1)

data = resp.json()

# Find image part in response
for candidate in data.get("candidates", []):
    for part in candidate.get("content", {}).get("parts", []):
        if "inlineData" in part:
            img_data = part["inlineData"]["data"]
            mime = part["inlineData"].get("mimeType", "image/png")
            ext = "png" if "png" in mime else "jpg"
            out_path = f"assets/textures/dungeon_tileset.{ext}"
            import os
            os.makedirs("assets/textures", exist_ok=True)
            with open(out_path, "wb") as f:
                f.write(base64.b64decode(img_data))
            print(f"Saved tileset to: {out_path}")
            sys.exit(0)
        elif "text" in part:
            print("Text response:", part["text"][:500])

print("No image found in response. Full response:")
print(json.dumps(data, indent=2)[:3000])
