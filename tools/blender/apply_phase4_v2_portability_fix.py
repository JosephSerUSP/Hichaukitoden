#!/usr/bin/env python3
"""Apply the reviewed Phase 4 V2 portability and preview-boundary fix."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(relative: str, old: str, new: str) -> None:
    path = ROOT / relative
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"expected source block not found in {relative}: {old[:100]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def insert_before(relative: str, marker: str, addition: str) -> None:
    replace_once(relative, marker, addition + marker)


def patch_generator() -> None:
    path = "tools/asset-gen/surface_baselines_v2.py"
    replace_once(path, "import math\nimport tempfile\n", "import math\nimport struct\nimport tempfile\n")
    replace_once(path, "GENERATOR_VERSION = 1\n", 'GENERATOR_VERSION = 2\nPNG_SERIALIZER = "second_rite_png_v1_filter0_stored_deflate"\n')
    old = '''def png_bytes(values: list[int], size: int, mode: str) -> bytes:
    from io import BytesIO
    from PIL import Image

    image = Image.new(mode, (size, size))
    image.putdata(values)
    stream = BytesIO()
    image.save(stream, format="PNG", compress_level=9, optimize=False)
    return stream.getvalue()


def source_hash() -> str:
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
'''
    new = '''def _crc32(data: bytes) -> int:
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0xEDB88320 if crc & 1 else 0)
    return crc ^ 0xFFFFFFFF


def _adler32(data: bytes) -> int:
    a = 1
    b = 0
    modulus = 65521
    for start in range(0, len(data), 5552):
        for byte in data[start:start + 5552]:
            a += byte
            b += a
        a %= modulus
        b %= modulus
    return (b << 16) | a


def _stored_zlib(data: bytes) -> bytes:
    output = bytearray(b"\\x78\\x01")
    if not data:
        output.extend(b"\\x01\\x00\\x00\\xff\\xff")
    for start in range(0, len(data), 65535):
        block = data[start:start + 65535]
        final = start + len(block) >= len(data)
        output.append(1 if final else 0)
        length = len(block)
        output.extend(struct.pack("<HH", length, length ^ 0xFFFF))
        output.extend(block)
    output.extend(struct.pack(">I", _adler32(data)))
    return bytes(output)


def _png_chunk(chunk_type: bytes, payload: bytes) -> bytes:
    framed = chunk_type + payload
    return struct.pack(">I", len(payload)) + framed + struct.pack(">I", _crc32(framed))


def png_bytes(values: list[int], size: int, mode: str) -> bytes:
    if len(values) != size * size:
        raise ValueError(f"PNG values have {len(values)} samples; expected {size * size}")
    if mode == "L":
        bit_depth = 8
        row_bytes = size
        sample_bytes = bytes(clamp(value, 0, 255) for value in values)
    elif mode == "I;16":
        bit_depth = 16
        row_bytes = size * 2
        sample_bytes = b"".join(struct.pack(">H", clamp(value, 0, 65535)) for value in values)
    else:
        raise ValueError(f"unsupported canonical PNG mode: {mode}")
    scanlines = bytearray()
    for row in range(size):
        scanlines.append(0)
        start = row * row_bytes
        scanlines.extend(sample_bytes[start:start + row_bytes])
    ihdr = struct.pack(">IIBBBBB", size, size, bit_depth, 0, 0, 0, 0)
    return b"\\x89PNG\\r\\n\\x1a\\n" + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", _stored_zlib(bytes(scanlines))) + _png_chunk(b"IEND", b"")


def normalized_source_bytes(data: bytes | None = None) -> bytes:
    raw = Path(__file__).read_bytes() if data is None else data
    text = raw.decode("utf-8").replace("\\r\\n", "\\n").replace("\\r", "\\n")
    return text.encode("utf-8")


def source_hash() -> str:
    return hashlib.sha256(normalized_source_bytes()).hexdigest()
'''
    replace_once(path, old, new)
    replace_once(path, '            "formula": "round(32768 + clamp(reliefCells / rangeCells, -1, 1) * 32767)",\n        },', '            "formula": "round(32768 + clamp(reliefCells / rangeCells, -1, 1) * 32767)",\n            "serializer": PNG_SERIALIZER,\n        },')
    replace_once(path, '            "p99AbsoluteDeviationQ15": guide_scale,\n        },', '            "p99AbsoluteDeviationQ15": guide_scale,\n            "serializer": PNG_SERIALIZER,\n        },')
    replace_once(path, '        "generatorSourceSha256": source_hash(),\n        "size": size,', '        "generatorSourceSha256": source_hash(),\n        "pngSerializer": PNG_SERIALIZER,\n        "size": size,')
    replace_once(path, '        json.dumps(manifest, indent=2, sort_keys=True) + "\\n", encoding="utf-8")', '        json.dumps(manifest, indent=2, sort_keys=True) + "\\n", encoding="utf-8", newline="\\n")')
    old_compare = '''def compare_directories(expected: Path, actual: Path) -> list[str]:
    expected_files = sorted(path.relative_to(expected) for path in expected.rglob("*") if path.is_file())
    actual_files = sorted(path.relative_to(actual) for path in actual.rglob("*") if path.is_file())
    problems: list[str] = []
    if expected_files != actual_files:
        problems.append(f"file set differs: expected={expected_files}, actual={actual_files}")
    for relative in sorted(set(expected_files) & set(actual_files)):
        if (expected / relative).read_bytes() != (actual / relative).read_bytes():
            problems.append(f"content differs: {relative.as_posix()}")
    return problems
'''
    new_compare = '''def _png_decoded_values(path: Path) -> list[int] | None:
    try:
        from PIL import Image
    except ImportError:
        return None
    with Image.open(path) as image:
        return [int(value) for value in image.getdata()]


def compare_directories(expected: Path, actual: Path) -> list[str]:
    expected_files = sorted(path.relative_to(expected) for path in expected.rglob("*") if path.is_file())
    actual_files = sorted(path.relative_to(actual) for path in actual.rglob("*") if path.is_file())
    problems: list[str] = []
    if expected_files != actual_files:
        problems.append(f"file set differs: expected={expected_files}, actual={actual_files}")
    for relative in sorted(set(expected_files) & set(actual_files)):
        expected_path = expected / relative
        actual_path = actual / relative
        expected_bytes = expected_path.read_bytes()
        actual_bytes = actual_path.read_bytes()
        if expected_bytes == actual_bytes:
            continue
        if relative.suffix.lower() == ".png":
            expected_values = _png_decoded_values(expected_path)
            actual_values = _png_decoded_values(actual_path)
            if expected_values is not None and actual_values is not None:
                if expected_values == actual_values:
                    problems.append(f"container differs but decoded pixels match: {relative.as_posix()}")
                    continue
                changed = sum(a != b for a, b in zip(expected_values, actual_values))
                problems.append(f"decoded pixels differ ({changed} samples): {relative.as_posix()}")
                continue
        if relative.suffix.lower() == ".json":
            try:
                if json.loads(expected_bytes) == json.loads(actual_bytes):
                    problems.append(f"JSON formatting differs but values match: {relative.as_posix()}")
                    continue
            except (UnicodeDecodeError, json.JSONDecodeError):
                pass
        problems.append(f"content differs: {relative.as_posix()}")
    return problems
'''
    replace_once(path, old_compare, new_compare)


def patch_preview() -> None:
    path = "tools/asset-gen/blender/build_surface_v2_preview.py"
    replace_once(path, 'import second_rite_asset_core as asset_core  # noqa: E402\n', 'import second_rite_asset_core as asset_core  # noqa: E402\n\n\nPATCH_TILES = 3\n')
    old_mesh = '''def make_mesh(name: str, field: list[int], source_size: int, mesh_size: int,
              range_cells: float):
    indices = sample_indices(source_size, mesh_size)
    vertices = []
    faces = []
    for row, source_y in enumerate(indices):
        y = row / (mesh_size - 1) - 0.5
        for column, source_x in enumerate(indices):
            x = column / (mesh_size - 1) - 0.5
            value = field[source_y * source_size + source_x]
            z = value / 32767.0 * range_cells
            vertices.append((x, y, z))
    for row in range(mesh_size - 1):
        for column in range(mesh_size - 1):
            a = row * mesh_size + column
            b = a + 1
            c = a + mesh_size + 1
            d = a + mesh_size
            faces.append((a, b, c, d))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj
'''
    new_mesh = '''def _sample_axis(global_index: int, period: int, tileable: bool) -> int:
    if tileable:
        return global_index % period
    return min(period, max(0, global_index))


def make_mesh(name: str, field: list[int], source_size: int, mesh_size: int,
              range_cells: float, tile_axes: str):
    indices = sample_indices(source_size, mesh_size)
    period = mesh_size - 1
    start = -period
    stop = period * 2
    grid_size = stop - start + 1
    vertices = []
    faces = []
    for global_row in range(start, stop + 1):
        local_row = _sample_axis(global_row, period, "y" in tile_axes)
        source_y = indices[local_row]
        y = global_row / period - 0.5
        for global_column in range(start, stop + 1):
            local_column = _sample_axis(global_column, period, "x" in tile_axes)
            source_x = indices[local_column]
            x = global_column / period - 0.5
            value = field[source_y * source_size + source_x]
            z = value / 32767.0 * range_cells
            vertices.append((x, y, z))
    for row in range(grid_size - 1):
        for column in range(grid_size - 1):
            a = row * grid_size + column
            b = a + 1
            c = a + grid_size + 1
            d = a + grid_size
            faces.append((a, b, c, d))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj
'''
    replace_once(path, old_mesh, new_mesh)
    replace_once(path, '        roughness=0.92,', '        roughness=0.88,')
    replace_once(path, '    asset_core.flat_shade(obj)\n\n', '')
    replace_once(path, '    bpy.ops.object.camera_add(location=(1.35, -1.55, 1.25))', '    bpy.ops.object.camera_add(location=(0.0, -0.28, 2.45))')
    replace_once(path, '    camera.data.ortho_scale = 1.42', '    camera.data.ortho_scale = 1.08')
    replace_once(path, '        metadata["rangeCells"],\n    )', '        metadata["rangeCells"],\n        metadata["tileAxes"],\n    )')
    replace_once(path, '            "sr_range_cells": metadata["rangeCells"],\n            "sr_preview_only": True,', '            "sr_range_cells": metadata["rangeCells"],\n            "sr_preview_patch_tiles": PATCH_TILES,\n            "sr_preview_only": True,')
    replace_once(path, '        "meshFaces": len(obj.data.polygons),\n        "canonical": False,', '        "meshFaces": len(obj.data.polygons),\n        "previewPatchTiles": PATCH_TILES,\n        "canonical": False,')


def patch_tests() -> None:
    path = "tools/asset-gen/tests/test_surface_baselines_v2.py"
    marker = '    def test_write_and_verify_complete_set(self):\n'
    addition = '''    def test_canonical_png_encoder_round_trips(self):
        from io import BytesIO
        from PIL import Image
        eight = [0, 1, 127, 255]
        with Image.open(BytesIO(surface.png_bytes(eight, 2, "L"))) as image:
            self.assertEqual([int(value) for value in image.getdata()], eight)
        sixteen = [1, 32768, 40000, 65535]
        with Image.open(BytesIO(surface.png_bytes(sixteen, 2, "I;16"))) as image:
            self.assertEqual([int(value) for value in image.getdata()], sixteen)

    def test_canonical_png_encoder_has_fixed_structure(self):
        data = surface.png_bytes([0, 1, 2, 3], 2, "L")
        self.assertTrue(data.startswith(b"\\x89PNG\\r\\n\\x1a\\n"))
        self.assertTrue(data.endswith(b"IEND\\xaeB`\\x82"))
        idat = data.index(b"IDAT") + 4
        self.assertEqual(data[idat:idat + 2], b"\\x78\\x01")

    def test_source_hash_normalizes_line_endings(self):
        self.assertEqual(surface.normalized_source_bytes(b"one\\r\\ntwo\\rthree\\n"), b"one\\ntwo\\nthree\\n")
        self.assertEqual(surface.sha256(surface.normalized_source_bytes(b"a\\r\\nb\\r\\n")), surface.sha256(surface.normalized_source_bytes(b"a\\nb\\n")))

'''
    insert_before(path, marker, addition)
    replace_once(path, '            self.assertEqual(len(manifest["baselines"]), 4)\n', '            self.assertEqual(len(manifest["baselines"]), 4)\n            self.assertEqual(manifest["pngSerializer"], surface.PNG_SERIALIZER)\n')
    replace_once(path, '        self.assertIn("fieldQ15LeSha256", source)\n        self.assertNotIn("ray_cast", source)', '        self.assertIn("fieldQ15LeSha256", source)\n        self.assertIn("PATCH_TILES = 3", source)\n        self.assertIn("_sample_axis", source)\n        self.assertNotIn("flat_shade", source)\n        self.assertNotIn("ray_cast", source)')


def patch_docs() -> None:
    replace_once("docs/asset-pipeline/SURFACE_BASELINES_V2.md", "Pillow is used only to serialize already-determined integer samples to PNG.\n", "Canonical PNGs use a repository-owned fixed encoder with filter-0 scanlines and uncompressed DEFLATE stored blocks. Source provenance normalizes line endings before hashing, so Windows and Linux checkouts produce identical canonical bytes.\n")
    replace_once("docs/asset-pipeline/SURFACE_BASELINES_V2.md", "4. creates a mesh with `mesh.from_pydata`;\n5. assigns shared contract and material metadata;\n6. saves a `.blend` and render in the requested temporary directory.\n", "4. creates a 3×3 inspection patch with the canonical tile in the centre;\n5. wraps declared tile axes and edge-pads undeclared axes;\n6. keeps every open mesh boundary outside a near-normal camera;\n7. assigns shared contract and material metadata;\n8. saves a `.blend` and render in the requested temporary directory.\n")
    replace_once("docs/asset-pipeline/BLENDER_CORE.md", "Canonical V2 outputs are fixed-point scalar fields serialized as\n`height_metric.png` and `depth_guide.png`. Blender creates preview meshes and\nrenders only after checking the recorded field hash. It never ray-casts the\npreview back into canonical pixels.\n", "Canonical V2 outputs are fixed-point scalar fields serialized as `height_metric.png` and `depth_guide.png` by a repository-owned fixed PNG encoder. Source provenance normalizes line endings. Blender creates a 3×3 repeated or edge-padded preview patch only after checking the recorded field hash, and never ray-casts it back into canonical pixels.\n")
    replace_once(".claude/skills/second-rite-surface-baselines/SKILL.md", "## Encodings\n", "## Canonical serialization\n\nUse only the repository-owned fixed PNG encoder in `surface_baselines_v2.py`. Do not replace it with Pillow, libpng, or Blender image saving. Normalize source line endings before provenance hashing.\n\n## Encodings\n")


def run(*command: str) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    patch_generator()
    patch_preview()
    patch_tests()
    patch_docs()
    run(sys.executable, "tools/asset-gen/surface_baselines_v2.py", "--runs", "3")
    run(sys.executable, "-m", "unittest", "discover", "-s", "tools/asset-gen/tests", "-p", "test_surface_baselines_v2.py", "-v")
    run(sys.executable, "tools/asset-gen/surface_baselines_v2.py", "--runs", "3", "--verify")


if __name__ == "__main__":
    main()
