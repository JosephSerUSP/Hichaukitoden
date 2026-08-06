"""Sample orthographic depth from a scenes.py preset and write a height PNG.

Runs inside Blender:

    blender --background --factory-startup --python render_depth.py -- \
        --preset wall_pilasters --out path.png --size 512

WHY A RAYCAST AND NOT A RENDER. An orthographic depth pass is a raycast with a
render engine wrapped around it. Going through Cycles or EEVEE would add a
compositor node graph, an OpenEXR round trip, a GPU that may or may not be
free, and a set of node socket names that move between Blender versions -- all
of it in service of a number the BVH already has exactly. `scene.ray_cast`
gives the first hit analytically, in one code path, with no sampling noise and
no version surface. The geometry being sampled is the real evaluated mesh,
modifiers and booleans included, so this is still depth from actual 3D
geometry; it is only the pixel transport that is skipped.

Output matches make_height_patterns.py exactly: opaque RGBA, 128 neutral at the
base plane, +-112 for relief, so the two authoring routes are interchangeable
downstream.
"""

import argparse
import json
import os
import sys

import bpy
import numpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scenes                                        # noqa: E402


# High enough to clear the tallest relief, low enough to keep float precision
# in the returned hit coordinates comfortable.
CAMERA_Z = 8.0


def _evaluated_bvhs(depsgraph):
    """Build stable per-object BVHs from the evaluated scene geometry."""
    trees = []
    for obj in sorted(depsgraph.objects, key=lambda item: item.name):
        if obj.type != "MESH" or obj.hide_render:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        vertices = [evaluated.matrix_world @ vertex.co
                    for vertex in mesh.vertices]
        triangles = [tuple(triangle.vertices)
                     for triangle in mesh.loop_triangles]
        polygon_keys = [triangle.polygon_index
                        for triangle in mesh.loop_triangles]
        tree = BVHTree.FromPolygons(vertices, triangles, all_triangles=True)
        evaluated.to_mesh_clear()
        if tree is not None:
            corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
            trees.append((
                obj.name, tree, polygon_keys,
                min(point.x for point in corners), max(point.x for point in corners),
                min(point.y for point in corners), max(point.y for point in corners),
            ))
    if not trees:
        raise SystemExit("depth sampling found no evaluated mesh objects")
    return trees


def _first_hit(bvhs, origin, direction):
    """Return the nearest deterministic evaluated-mesh hit along a ray."""
    best = None
    for (object_name, tree, polygon_keys,
         min_x, max_x, min_y, max_y) in bvhs:
        if origin.x < min_x or origin.x > max_x or origin.y < min_y or origin.y > max_y:
            continue
        location, _, triangle_index, _ = tree.ray_cast(
            origin, direction, 1.0e6)
        if location is None:
            continue
        distance = (location - origin).dot(direction)
        if distance < 0.0:
            continue
        candidate_key = (object_name, polygon_keys[triangle_index])
        if (best is None or distance < best[0] - 1.0e-9 or
                (abs(distance - best[0]) <= 1.0e-9 and
                 candidate_key < best[1])):
            best = (distance, candidate_key, location)
    return None if best is None else best[2]


def sample(size, view="above"):
    """Return a size x size array of surface height toward the viewer.

    `view` places the eye. Sampling always runs from the viewer's side and the
    sign is flipped for a ceiling, so a positive value means "nearer to whoever
    is looking at this surface" for every preset -- which is what 128+ has to
    mean by the time ControlNet reads the PNG.
    """
    depsgraph = bpy.context.evaluated_depsgraph_get()
    toward = -1.0 if view == "above" else 1.0
    origin_z = CAMERA_Z * -toward
    down = Vector((0.0, 0.0, toward))
    bvhs = _evaluated_bvhs(depsgraph)
    heights = numpy.full((size, size), numpy.nan, dtype=numpy.float64)
    # Pixel centres, so the sampled period is exactly [0,1) and column 0 is one
    # step past column size-1 -- the condition for the wrap check to mean what
    # it says.
    coordinates = (numpy.arange(size) + 0.5) / size
    for row in range(size):
        y = float(coordinates[row])
        for col in range(size):
            location = _first_hit(
                bvhs, Vector((float(coordinates[col]), y, origin_z)), down)
            if location is not None:
                heights[row, col] = location.z
    if numpy.isnan(heights).any():
        # The backplane is meant to make this impossible; if it happens the
        # scene is malformed and a silent hole would become a black gash.
        missing = int(numpy.isnan(heights).sum())
        raise SystemExit(f"depth sampling missed {missing} of {size * size} rays")
    return (heights - scenes.BASE_Z) * toward * -1.0


def wrap_error(field, axes):
    """Seam discontinuity across the tile edge, measured two ways.

    RATIO is the seam step against the mean interior step. On a correctly
    periodic tile the first and last columns are just another adjacent pair, so
    a ratio near 1.0 is the CORRECT answer, not a failure -- a genuine break
    reads far higher (an unwrapped groove measured 11.7 here). An earlier
    version of this gate accepted only ratios under 0.25, which happened to hold
    for flat architecture because the seam landed in a flat region, and would
    have rejected every one of the organic presets for tiling properly.

    STEP is the same seam against the map's own relief range, which is what
    decides whether a human sees it. The two together separate "smooth field
    with an ordinary seam" from "small field with a real break".
    """
    span = max(float(field.max() - field.min()), 1e-9)
    report = {}
    for axis in axes:
        array = field if axis == "x" else field.T
        seam = float(numpy.abs(array[:, 0] - array[:, -1]).mean())
        interior = float(numpy.abs(numpy.diff(array, axis=1)).mean())
        report[axis] = {"ratio": round(seam / max(interior, 1e-9), 3),
                        "step": round(seam / span, 4)}
    return report


def write_height(path, field, contrast=1.0):
    # Neutral grey is the DOMINANT surface, not the modelled base plane. A wall
    # whose blocks all stand proud of their joints has every pixel at or above
    # the base plane, so anchoring 128 there throws away the lower half of the
    # range and halves the contrast ControlNet actually sees. The median is the
    # face the eye reads as "the wall", which is what neutral should mean.
    field = field - float(numpy.median(field))
    limit = max(float(numpy.percentile(numpy.abs(field), 99.0)), 1e-9)
    normalized = numpy.clip(field / limit, -1.0, 1.0)
    grey = numpy.clip(numpy.rint(128 + normalized * 112 * contrast),
                      0, 255).astype(numpy.uint8)
    # Blender's +Y is up in the scene; image rows run downward, so the sampled
    # array is flipped once here rather than in every builder.
    grey = numpy.flipud(grey)
    rgba = numpy.dstack([grey, grey, grey,
                         numpy.full(grey.shape, 255, dtype=numpy.uint8)])
    _save_png(path, rgba)
    return grey


def _save_png(path, rgba):
    """Write RGBA through Blender's own image API.

    Blender ships no Pillow, and asking the driver to hand it over would put a
    numpy array through a pipe. Blender can already write a PNG, so it does.
    """
    height, width, _ = rgba.shape
    image = bpy.data.images.new("height", width=width, height=height, alpha=True)
    # Blender pixels are bottom-row-first float RGBA, flat.
    flat = numpy.flipud(rgba).astype(numpy.float32).ravel() / 255.0
    image.pixels.foreach_set(flat)
    image.file_format = "PNG"
    image.filepath_raw = path
    image.save()


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--preset", required=True, choices=sorted(scenes.PRESETS))
    parser.add_argument("--out", required=True)
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument("--contrast", type=float, default=1.0)
    parser.add_argument("--blend", help="also save the built scene as a .blend")
    args = parser.parse_args(argv)

    axes = scenes.build(args.preset)
    view = scenes.VIEW[args.preset]
    if args.blend:
        # Saved AFTER baking and wrapping, so the file opens showing exactly the
        # geometry the sampler measured -- wrap copies included. A file of the
        # pre-bake scene would look tidier and would not be the thing that was
        # rendered, which is the opposite of what an inspection copy is for.
        bpy.ops.wm.save_as_mainfile(filepath=args.blend, compress=True)
    field = sample(args.size, view)
    write_height(args.out, field, args.contrast)
    print("HEIGHTMAP " + json.dumps({
        "coreVersion": scenes.asset_core.CORE_VERSION,
        "contractVersion": scenes.asset_core.contract_value("contractVersion"),
        "preset": args.preset,
        "surface": scenes.SURFACE[args.preset],
        "view": view,
        "representation": "plane",
        "role": "surface_material",
        "authoringSpace": "depth_tile",
        "placementFrame": "surface_domain",
        "depthProduct": "depth_guide",
        "metricDepthDeferred": True,
        "defaultMetricRangeCells": 0.25,
        "path": args.out,
        "size": args.size,
        "blend": args.blend,
        "tileAxes": axes,
        "contrast": args.contrast,
        "reliefMin": round(float(field.min()), 5),
        "reliefMax": round(float(field.max()), 5),
        "wrapError": wrap_error(field, axes),
    }))


if __name__ == "__main__":
    main()
