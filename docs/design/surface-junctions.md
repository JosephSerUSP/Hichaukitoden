# Surface junctions

**Intent, not status.** Nothing here is built yet except where noted. What
exists is in `docs/ENGINE-STATE.md`; how the shipped parts work is in
`docs/SPEC.md`.

This document is the design for how two adjacent displaced surfaces meet, and
it exists because the current answer is "by luck". It is written against the
planned Z-axis work (`renderer-3d-roadmap.md` §8.3, multi-height rooms) so the
junction machinery is built once rather than built for flat maps and then
rebuilt for elevation.

## The problem, measured

Rendering a cobble floor at `heightMapScale.floor = 0.1` and counting pixels
that no geometry covered (03.08.2026):

- 589 pixels of pure `(0,0,0)` against a drawn background of `(58,58,58)`.
- Located: the floor's outer perimeter, plus two horizontal bands across it.
- The floor mesh itself is watertight -- a boundary-edge count finds zero
  interior tears. The holes are all *between* meshes.

Three symptoms, and it is worth being precise that they are one cause:

1. **Cell-to-cell cracks.** Two adjacent floor cells sample the same field at
   `v = 1` and `v = 0`. On a tileable map those are *neighbouring texels, not
   the same texel*, so the shared edge is authored at two slightly different
   heights and the cells do not close.
2. **The wall-foot void.** A wall spans exactly `z = 0..1` with straight ends.
   A displaced floor is `z = lift` and displacement is signed about neutral, so
   any joint darker than neutral drops the floor below the wall's foot.
3. **Corner pinholes.** Where four cells meet, pairwise agreement along each of
   the two boundaries still leaves the corner vertex unconstrained. Three cells
   can each agree with their neighbours and still leave a hole at the point
   they share.

The common cause: **the tile is the unit of authorship, and the junction
between tiles is implicit.** A tile is compiled from its own height map with no
knowledge of what it abuts. Two tiles line up when their maps happen to agree,
which is most of the time, which is why this reads as an intermittent artefact
rather than a structural one. It is structural.

Note what is *not* the cause. The decimator was suspected twice and cleared
twice: mirrored tiles decimate their seams identically (a test now pins this),
and the seam machinery already reduces a mesh's own two borders in lockstep.

## Why this must be designed against elevation now

With one floor plane, a junction is a detail; the temptation is to special-case
each symptom -- clamp the floor's rim, or hang a fixed apron off the wall. Both
were considered, and both are the same mistake in different clothes: they treat
the *edge height* as a constant the engine already knows.

With multi-height rooms it is not a constant. A floor's rim height becomes a
property of the boundary -- of which two cells meet there and what elevation
each carries -- and every fix that assumes "the floor is at 0 and the wall
starts at 0" has to be torn out. The version that survives elevation is the one
where a junction is resolved from data on both sides.

The encouraging part: **the wall-foot void is the degenerate case of an
elevation step.** A floor 0.02 below its wall and a floor a whole cell below
its neighbour are the same geometry problem at different scales. Solve the
general one and the flat-map bugs fall out of it.

## Design

### Rule 1 -- sample the field periodically

A tiling surface must sample `v ∈ [0,1)` and reuse the `v = 0` sample for the
vertex at `v = 1`. Today both ends are sampled independently, so a tile does
not even close against a *copy of itself*.

This is free, it is required no matter what else is built, and it closes every
junction where both sides share a material and an elevation -- which is most of
a dungeon. It is the only rule here that should be implemented before the rest
is agreed.

It is also why the existing border test passes while the bug is real: the test
fixture's height map happens to have identical first and last columns, so it
never exercises the case. That fixture should gain a deliberately
non-symmetric map.

### Rule 2 -- every surface declares a rim height, and mismatches get a riser

Each surface edge carries a declared **rim height**: the height of the surface
at that boundary, in world units, independent of its interior relief.

- Where two rims agree, the surfaces join directly. Interior relief is
  untouched, and relief crosses the boundary exactly as authored.
- Where they disagree -- different material, different elevation, or a wall's
  flat foot against a displaced floor -- the junction emits a **riser**: a band
  of geometry spanning from one rim to the other.

A riser is not a patch. It is the step between two floors at different
elevations, the plinth under a wall, and the closure over a rim mismatch, all
as one construct. It is what a stair, a kerb and a ledge are made of.

The current `plane.SKIRT` constant (0.15, hardcoded, wall-only, added
03.08.2026) is a **provisional riser with no data behind it**. It should be
understood as a placeholder for this rule, not as a solution -- and it should
be deleted when the rule lands, not extended. Note it does not even fire in the
case that motivated it: when `heightMapScale.wall` is 0 the wall is not a plane
mesh at all but a plain quad, so it has no skirt to give.

### Rule 3 -- corners are resolved once, for all four cells

A corner is shared by up to four cells and two boundaries. It must be resolved
as a corner, not as the incidental endpoint of two independent edges.

The corner's height is a pure function of the four cells' rim heights. Where
they are not all equal, the corner takes the **lowest**, and each cell that
sits above it contributes a riser down to it. Lowest rather than an average
because a corner that sits above any of its floors is a hole, and a corner that
sits below all of them is hidden.

This is also the answer to the wall-corner seams reported alongside the floor
holes: two wall runs meeting at a right angle are two surfaces sharing a corner
edge, and nothing currently makes them agree about it.

### Rule 4 -- resolution is local and needs no neighbour query

A cell must compute a shared junction **without reading its neighbour's
compiled mesh**. Resolution is a pure function of both cells' *declared* data
-- elevation, material, rim height -- evaluated identically on both sides.

This is the constraint that keeps the system buildable. If a cell had to
inspect its neighbour's mesh, compilation would become order-dependent, one
edit would invalidate a spreading region of cached meshes, and two cells
compiled in different frames could disagree. A pure function of declared data
means both sides reach the same answer independently and caching stays sane.

## What this costs, honestly

**Cache pressure.** Today a surface mesh is cached per (height map, atlas
cell). Junction-aware meshes are cached per (tile, edge context), and the
context multiplies. The mitigation is to keep the *interior* context-free and
put all context in the risers, which are small, flat, and keyed by the pair of
rim heights they bridge. This is a real constraint on the implementation and
the reason Rule 2 puts the variable geometry in a separate construct rather
than deforming the tile.

**A rejected alternative, and why.** The cheapest fix is a canonical rim: force
every surface's displacement to zero at its edges, so all rims are straight
lines at a known height and everything meets everything. It caches perfectly
and kills all three symptoms at once. It was rejected because it flattens
relief at every cell boundary -- a faint grid across every floor -- and because
it would break relief that deliberately crosses a seam, such as a wall whose
pilaster straddles the tile edge. It remains the fallback if riser complexity
proves unmanageable.

**Triangle cost.** Risers only exist where materials or elevations change, so a
uniform room pays nothing. A heavily varied one pays per boundary.

## How elevation drops in

Nothing new is required. Elevation adds one field -- a per-cell floor and
ceiling elevation -- and the existing rules absorb it:

- A cell's rim height becomes `elevation + relief at the rim` instead of
  `0 + relief at the rim`.
- A step between rooms is a riser whose two rim heights differ by the elevation
  change, which is the same construct already generated for a 0.02 mismatch.
- Walls stop spanning `z = 0..1` and span `floorElevation..ceilingElevation`
  for their cell, which is a change to where a wall is placed, not to how it is
  built.
- Corners resolve by Rule 3 unchanged; a corner where three floors at three
  elevations meet is already the case that rule was written for.

**Autotiling and x+y seamless walls** are the same idea applied one level up:
today the *texture* on a boundary is picked per cell, and it should be picked
per junction, by the same pure function of both sides' declared data. The
geometry rules above should be built so that the junction is a named thing with
an identity -- because that identity is what an autotiler needs to key on.

## Staging

1. **Rule 1 now.** Small, self-contained, required regardless, and it removes
   the most visible artefact. Add a non-symmetric fixture map so the border
   test can actually fail.
2. **Rim heights as data, risers not yet.** Make every surface declare its rim
   height and assert that neighbours agree; where they do not, log it. This
   measures how much riser geometry the world actually needs before any is
   built.
3. **Risers, then corners.** In that order -- a corner rule cannot be validated
   while edges are still open.
4. **Elevation.** Only after 1-3 hold on a flat map.

Do **not** build in this order's reverse. Elevation on top of junctions that do
not close is how the flat-map artefacts become permanent: they stop being
visible as bugs and start being load-bearing.

## Open questions

- Where do rim heights live -- derived from the height map's edge rows, or
  declared in `tilesets.json`? Derived is less authoring, declared is checkable
  by G1 and cannot drift when art is regenerated.
- Should a riser inherit the albedo of the higher surface, the lower one, or
  carry its own material? A step between two materials has a visible answer and
  the wrong one will read as a bug.
- Does the raycaster path need any of this, or only the polygonal path? The
  perimeter void appears where walls are *plain quads*, which suggests the
  answer is both.
