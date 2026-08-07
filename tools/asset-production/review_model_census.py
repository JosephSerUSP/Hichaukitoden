# tools/asset-production/review_model_census.py
"""
Post-processor for Second Rite in-engine model census captures.
Validates capture integrity, measures paired-state visual difference,
merges CSV review templates non-destructively, and generates decision-slice contact sheets.
"""

import os
import sys
import json
import csv
from PIL import Image, ImageDraw, ImageFont

def process_captures(manifest, index_entries):
    expected_paths = set()
    for asset in manifest.get("assets", []):
        aid = asset["asset_id"]
        for st in asset.get("states", []):
            st_name = st["state"]
            for ctx in st.get("contexts", []):
                for dist in st.get("distances", []):
                    for angle in st.get("angles", []):
                        for light in st.get("lighting", []):
                            rel_path = f"{aid}/{ctx}__{dist}__{angle}__{light}__{st_name}.png"
                            expected_paths.add(rel_path)

    actual_paths = set()
    duplicates = []
    for entry in index_entries:
        p = entry.get("path", "").replace("out/model-census-review/", "")
        if p in actual_paths:
            duplicates.append(p)
        actual_paths.add(p)

    missing = sorted(list(expected_paths - actual_paths))
    return missing, duplicates

def merge_review_csv(csv_path, manifest_assets):
    existing_rows = {}
    fieldnames = ["asset_id", "recognition", "spatialFunction", "styleIntegration", "materialHierarchy", "screenEconomy", "emotionalFunction", "verdict", "notes"]

    if os.path.exists(csv_path):
        with open(csv_path, "r", newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                aid = row.get("asset_id")
                if aid:
                    existing_rows[aid] = row

    rows = []
    for asset in manifest_assets:
        aid = asset["asset_id"] if isinstance(asset, dict) else asset
        if aid in existing_rows:
            rows.append(existing_rows[aid])
        else:
            rows.append({
                "asset_id": aid,
                "recognition": "",
                "spatialFunction": "",
                "styleIntegration": "",
                "materialHierarchy": "",
                "screenEconomy": "",
                "emotionalFunction": "",
                "verdict": "",
                "notes": ""
            })

    os.makedirs(os.path.dirname(csv_path), exist_ok=True)
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

def make_contact_sheet(images_info, output_path, cols=4, tile_w=256, tile_h=240, header_h=30):
    if not images_info:
        # Emit a small blank image if no images provided
        img = Image.new("RGB", (tile_w, tile_h), color=(30, 30, 30))
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        img.save(output_path)
        return

    rows = (len(images_info) + cols - 1) // cols
    sheet_w = cols * tile_w
    sheet_h = rows * (tile_h + header_h)

    sheet = Image.new("RGB", (sheet_w, sheet_h), color=(20, 20, 25))
    draw = ImageDraw.Draw(sheet)

    try:
        font = ImageFont.load_default()
    except Exception:
        font = None

    for idx, info in enumerate(images_info):
        r = idx // cols
        c = idx % cols
        x = c * tile_w
        y = r * (tile_h + header_h)

        img_path = info.get("full_path")
        label = info.get("label", "")

        # Header bar
        draw.rectangle([x, y, x + tile_w, y + header_h], fill=(40, 44, 52))
        draw.text((x + 6, y + 6), label[:40], fill=(220, 220, 220), font=font)

        # Image tile
        if img_path and os.path.exists(img_path):
            try:
                tile_img = Image.open(img_path).convert("RGB")
                if tile_img.size != (tile_w, tile_h):
                    tile_img = tile_img.resize((tile_w, tile_h), Image.Resampling.NEAREST)
                sheet.paste(tile_img, (x, y + header_h))
            except Exception as e:
                draw.rectangle([x, y + header_h, x + tile_w, y + header_h + tile_h], fill=(80, 20, 20))
                draw.text((x + 6, y + header_h + 10), f"Error: {e}", fill=(255, 100, 100), font=font)
        else:
            draw.rectangle([x, y + header_h, x + tile_w, y + header_h + tile_h], fill=(50, 20, 20))
            draw.text((x + 6, y + header_h + 10), "MISSING", fill=(255, 150, 150), font=font)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    sheet.save(output_path)

def generate_all_contact_sheets(out_dir, manifest, index_entries):
    sheets_dir = os.path.join(out_dir, "contact-sheets")
    os.makedirs(sheets_dir, exist_ok=True)

    tier_a = []
    tier_b = []
    tier_c = []
    paired = []
    failures = []

    # Map index entries by (asset_id, state, context, distance, angle, lighting)
    entry_map = {}
    for entry in index_entries:
        key = (entry["asset_id"], entry["state"], entry["context"], entry["distance"], entry["angle"], entry["lighting"])
        entry_map[key] = entry
        if not entry.get("success", True):
            failures.append({
                "full_path": os.path.join(out_dir, entry["path"].replace("out/model-census-review/", "")),
                "label": f"{entry['asset_id']} ({entry['state']}) FAIL"
            })

    for asset in manifest.get("assets", []):
        aid = asset["asset_id"]
        display = asset.get("display_name", aid)
        tier = asset.get("tier", "Tier A")

        for st in asset.get("states", []):
            st_name = st["state"]
            # Decision slice: one_cell, oblique & frontal, first_stratum / functional, normal lighting
            key_oblique = (aid, st_name, "first_stratum", "one_cell", "oblique", "normal")
            key_frontal = (aid, st_name, "first_stratum", "one_cell", "frontal", "normal")
            target_entry = entry_map.get(key_oblique) or entry_map.get(key_frontal)

            full_p = os.path.join(out_dir, aid, f"first_stratum__one_cell__oblique__normal__{st_name}.png")
            if not os.path.exists(full_p):
                full_p = os.path.join(out_dir, aid, f"first_stratum__one_cell__frontal__normal__{st_name}.png")

            tile_info = {
                "full_path": full_p,
                "label": f"{display} [{st_name}]"
            }

            if tier == "Tier A":
                tier_a.append(tile_info)
            elif tier == "Tier B":
                tier_b.append(tile_info)
            elif tier == "Tier C":
                tier_c.append(tile_info)

            # Paired states slice
            if len(asset.get("states", [])) > 1:
                paired.append(tile_info)

    make_contact_sheet(tier_a, os.path.join(sheets_dir, "tier_a_stateful.png"))
    make_contact_sheet(tier_b, os.path.join(sheets_dir, "tier_b_architecture.png"))
    make_contact_sheet(tier_c, os.path.join(sheets_dir, "tier_c_environment.png"))
    make_contact_sheet(paired, os.path.join(sheets_dir, "paired_states.png"))
    make_contact_sheet(failures, os.path.join(sheets_dir, "failures.png"))

def main():
    out_dir = "out/model-census-review"
    manifest_path = "tools/asset-production/review_manifest.json"
    index_path = os.path.join(out_dir, "index.json")
    csv_path = os.path.join(out_dir, "review.csv")

    if not os.path.exists(manifest_path):
        print(f"Manifest not found: {manifest_path}")
        sys.exit(1)

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    index_entries = []
    if os.path.exists(index_path):
        with open(index_path, "r", encoding="utf-8") as f:
            index_entries = json.load(f)

    missing, duplicates = process_captures(manifest, index_entries)
    print(f"[review_model_census] Index entries: {len(index_entries)}, Missing: {len(missing)}, Duplicates: {len(duplicates)}")

    merge_review_csv(csv_path, manifest.get("assets", []))
    print(f"[review_model_census] Merged review template at {csv_path}")

    generate_all_contact_sheets(out_dir, manifest, index_entries)
    print(f"[review_model_census] Contact sheets generated in {os.path.join(out_dir, 'contact-sheets')}")

if __name__ == "__main__":
    main()
