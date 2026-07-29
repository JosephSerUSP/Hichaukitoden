{{STYLE_BIBLE}}

Draw a surface-texture page named **{{NAME}}**.
{{DESCRIPTION}}

Layout: {{GRID}} of separate square textures, filling the image edge to edge --
no gaps, no borders, no labels, no drop shadows between cells.

CRITICAL: every cell is a FLAT SURFACE TEXTURE photographed perfectly head-on.
No perspective, no vanishing point, no 3D depth, no horizon, no scene, no
objects sitting on a surface. These are texture maps that will be applied to
walls, floors and ceilings by a raycasting engine -- think Doom, Quake, King's
Field texture sheets.

Each cell must tile seamlessly with itself: the left edge continues into the
right edge and the top into the bottom, with no visible seam and no feature
that draws the eye to the centre of the cell.

Bake in NO lighting -- no torch glow, no vignette, no gradient from one corner to
another. The engine lights these at runtime; baked light reads as dirt.

Background: {{BACKGROUND}}

{{EXTRA}}
