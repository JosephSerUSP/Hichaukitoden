# Image-authored geometry

**Intent, not status.** What exists right now is in `docs/ENGINE-STATE.md`; how
the shipped parts work is in `docs/SPEC.md`. This document records the design
decisions behind the image-authored geometry language and the reasoning that
produced them.

Source: *Second Rite — Image-Authored Geometry & Dungeon Surface Pipeline*
(foundation design document, 01.08.2026).

## The goal

A small, image-authored geometry language for dungeon architecture and selected
fixtures: easy to paint, deterministic to compile, and visually distinctive.
The goal is **not** universal image-to-3D reconstruction. It is a constrained
family of representations whose limitations are legible and productive.

Every generated asset is authored from exactly two textures -- one RGBA albedo
PNG and one RGBA height PNG -- plus metadata that determines how those pixels
are interpreted.

The creative advantage is immediate legibility: an artist paints a surface,
silhouette or radial field and can understand what the compiler will build.
Geometry generation becomes a deterministic craft process rather than a
black-box inference task.

## Why the compiler lives in the engine

The design document leaves open "whether wall compositions should be
precompiled during a content build or generated lazily and cached at runtime".
This project answers: **in the engine, at load, cached**.

An offline compiler would create a second authority on the geometry language.
The editor previews through the real engine and the validator checks through
the real validator; a Python compiler would force either shelling out to it or
writing a second implementation in Lua, which is the failure `AGENTS.md` names
directly. Compiling in-engine also lets G1 check masks, dimensions and
registration as ordinary validation failures rather than as a script someone
remembers to run.

The cost is real and should be measured rather than assumed: there is no
cross-run cache, so every launch recompiles. Two things keep that small --
meshing samples the height field only at grid points (a 16x16 wall is 289
samples, not 16,384 pixels), and identical compositions are built once and
reused.

Image tools that *produce* the two PNGs stay in `tools/asset-gen/`. That is
pre-press authoring, not compilation, and is on the right side of the line.

## Non-goals

- Reconstructing arbitrary objects from photographs.
- Replacing OBJ for characters, furniture, branching forms or deeply undercut
  geometry. OBJ is an **equal path**, not a legacy exception.
- A universal voxel, neural or multi-view reconstruction pipeline.
- Making visual relief alter navigation collision.
- Growing the tileset for its own sake. The art direction prefers a small
  number of excellent surfaces over many weak variants.

## Design principles

- **Two-texture discipline.** No generated asset needs more than an albedo PNG
  and a height PNG. Additional meaning comes from metadata.
- **Constraints as style.** Each topology makes a useful promise about what it
  can represent. Assets outside that promise use OBJ rather than forcing the
  format to become universal.
- **Compiler-owned topology.** Pixels describe fields and masks. Code owns
  triangulation, seams, winding, UVs, normals and caching.
- **Renderer simplicity.** The runtime receives an ordinary mesh and needs no
  topology-specific path.
- **Visible failure.** Unsupported masks, mismatched silhouettes and impossible
  geometry produce diagnostics, never silent repair.
- **Art before abstraction.** Validated through a finished showcase room;
  tooling evolves in response to real authoring friction.

## The asset contract

A geometry asset is a directory holding `albedo.png`, `height.png` and
`asset.json`. The metadata is descriptive -- it declares topology, geometric
scale, composition behaviour, mesh density and edge behaviour -- and is never a
third visual map.

| Channel | Albedo | Height |
|---|---|---|
| RGB | Visible surface colour | A grayscale geometric value; the topology decides whether it is signed displacement, outward depth, or radial offset |
| A | Visual opacity, and colour compositing for surface fixtures | Geometric influence for surface layers, or geometric coverage for generated objects |

Opacity stays in the albedo so stained or translucent materials can remain
visually transparent while still possessing geometry.

### Height conventions by topology

| Topology | Grayscale | Alpha |
|---|---|---|
| Plane | Signed displacement about a neutral plane: 128 is neutral, darker recedes, lighter projects | Base surfaces are normally opaque; overlay alpha controls geometric influence |
| Shell | Unsigned distance outward from a central plane: 0 is the central plane, 255 is maximum depth | Coverage mask defining the shared front/back silhouette |
| Radial | Signed or unsigned radius variation about a declared base radius | Coverage of the radial surface at angle and height |

Begin with 8-bit height data and convert to floating point internally. The
low-poly result rarely shows 255 meaningful depth levels. Optional 16-bit
support can arrive later without changing the contract.

## The three topologies

**Plane** displaces a rectangular surface: `P(u,v) = P0 + uT + vB + h(u,v)N`.
It is the basis for walls, floors, ceilings, doors, embedded fixtures and
shallow architectural objects.

**Shell** builds one or two displaced surfaces sharing a parameterization, then
closes or pinches their common boundary. Both depth fields store nonnegative
distance from a shared central plane, so front and back cannot cross by
construction and each is easier to paint than a signed coordinate field. Modes:
`frontOnly`, `mirrorDepth`, `frontBack`. Edges either `stitch` (explicit side
faces -- slabs, idols, chests) or `pinch` (both depths converge near the
silhouette -- leaves, blades, masks).

In `frontBack` mode the height-alpha masks must match. Equal masks do not
themselves create the side surface; they guarantee that the same outer contour
and holes exist on both sides, and the compiler -- not the artist -- guarantees
the watertight stitch. The side strip is generated into the compiled albedo by
sampling front and rear boundary colours, defaulting to `darkenedBlend` because
it reinforces volume and separates the painted faces.

Image-plane bilateral symmetry and front/back reflection are **separate
operations with separate names**, so an asset may be authored from a half, a
face or a quarter while keeping the option to paint asymmetry.

**Radial** converts a cylindrical unwrap: horizontal is angle, vertical is
height, grayscale is distance from the axis. Suitable when each angle and
height has at most one outer radius; not for branching props or deep undercuts.

## Surfaces are composed before they are meshed

A wall fixture conceptually part of its wall should not be an unrelated mesh
floating over it. Base albedo, fixture albedo, base height and fixture height
compose first; the final pair is then meshed as one coherent surface.

Initial height operations, deliberately only three:

| Operation | Behaviour | Use |
|---|---|---|
| `none` | Composite albedo only | Paint, stains, writing |
| `add` | `base + signedOverlay * alpha` | Cracks, inscriptions, erosion, mortar |
| `replace` | `mix(base, overlay, alpha)` | Doors, inset panels, deliberate recesses |

No node graph, no field algebra. Min, max and bevel arrive only when a real
asset cannot be expressed without them.

**Registration is a hard invariant.** Any transform applied to a surface
fixture -- crop, position, scale, rotation, mirroring, atlas selection, edge
treatment -- must affect albedo and height identically.

## Texture resolution is independent of mesh resolution

A 128x128 height image must not imply 16,384 vertices. Each asset declares a
sampling grid appropriate to its visual role.

| Asset | Initial density |
|---|---|
| Wall | 12x12 to 16x16 |
| Floor | 8x8 to 12x12 |
| Ceiling | 8x8 |
| Shell object | ~16x16 to 20x20 per face |
| Radial object | 8-12 angular, 12-16 vertical |

Fixed grids first: predictable, debuggable and aesthetically appropriate.
Adaptive subdivision is an upgrade path, not a prerequisite.

Retro treatment applies *after* meaningful geometry exists. Quantization,
vertex snapping, affine texturing, fog and dithering are presentation controls;
source height data stays continuous rather than pre-posterized.

## Collision stays logical

Wall, floor and ceiling displacement is visual. Grid collision remains
authoritative. Generated object fixtures receive explicit collision metadata --
blocking or not -- rather than deriving gameplay collision from triangles. A
heightfield must never imply traversal the map cannot support.

## Diagnostics

The most important diagnostic is the **final composed albedo beside the final
composed heightfield**: it immediately localizes a problem to source art,
registration, composition, meshing or rendering. Beyond that: height alpha,
wireframe, exaggerated displacement, normals, and bounds against logical
interaction space.

## Deferred

Adaptive subdivision; marching-squares boundaries; multiple disconnected shell
islands; min/max and richer field algebra; vector displacement; layered radial
or layered depth surfaces; multi-view fusion; voxel or SDF compilers; generated
animated character topology.

Each is compatible with the architecture and none should be built before the
showcase room demonstrates a concrete need.

## Definition of done for the foundation

One room mixing composed planar architecture, an independently authored
front/back shell, a mirrored shell, a radial pillar and an OBJ prop; every
generated asset updating reliably from two PNGs plus metadata; invalid masks
failing visibly; and repeated compositions cached.

## Open decisions

- Grid-aligned silhouettes or marching-squares contours.
- Whether 16-bit height PNGs offer a real authoring advantage.
- Whether generated side albedo belongs in a compiled atlas or a dedicated
  material path.
- Whether multiple shell islands are common enough to support directly.
- Whether the next topology is extruded silhouette, richer radial components,
  or simply expanded OBJ tooling.
