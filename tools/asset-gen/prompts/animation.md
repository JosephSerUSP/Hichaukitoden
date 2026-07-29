{{STYLE_BIBLE}}

Draw a particle / effect flipbook strip named **{{NAME}}**.
{{DESCRIPTION}}

Layout: {{GRID}}, equal cells, no gaps, no separator lines, no numbering.
The {{FRAMES}} cells are consecutive frames of ONE effect, read left to right --
frame 1 is the start of the effect and the last frame is its end (or, for a
loop, the frame that flows back into frame 1).

Draw the art in WHITE AND GREY ONLY. It is tinted at runtime by the animation's
colour-over-lifetime curve, so any colour drawn in is a bug. Bright hot core,
soft falloff at the edges -- it is usually drawn with additive blending.

Each cell is centred, self-contained and small: the final sheet is
{{FINAL_SIZE}} at {{CELL}} per frame, so the effect must survive extreme
reduction. No ground, no character, no scenery, no motion-blur streaks running
between cells.

Background: {{BACKGROUND}}

{{EXTRA}}
