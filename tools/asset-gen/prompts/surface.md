{{STYLE_BIBLE}}

Draw ONE seamless surface texture named **{{NAME}}**.
{{DESCRIPTION}}

This is a single material filling the whole image edge to edge: no grid, no
cells, no border, no label, no framing, no object placed on top of it.

CRITICAL: a FLAT SURFACE seen perfectly head-on. No perspective, no vanishing
point, no horizon, no scene, no 3D staging. This is a texture map that will be
wrapped onto a wall, floor or ceiling by the engine -- think Doom, Quake or
King's Field texture sheets.

It must tile seamlessly against COPIES OF ITSELF in every direction: the left
edge continues into the right edge and the top into the bottom, with no visible
join. Keep the detail evenly distributed -- a single dominant feature in the
middle announces the repeat as soon as the texture is laid out across a corridor.

Bake in NO lighting: no torch glow, no vignette, no gradient from one corner to
another, no drop shadow. The engine lights this at runtime, and baked light
reads as dirt once the real light disagrees with it.

This texture is paired with a height map that gives it real relief in 3D, so
paint the MATERIAL, not the illusion of depth: draw the colour and grain of the
stone, brick or timber and let its shape come from the geometry.

Background: {{BACKGROUND}}

{{EXTRA}}
