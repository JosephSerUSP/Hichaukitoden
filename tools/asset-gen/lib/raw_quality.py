"""Cheap diagnostics for catching malformed SD output before post-processing.

The pixel pipeline can turn a broken, high-chroma latent decode into a
plausible-looking 64px texture. Keep this check on the raw model PNG so reports
show when the source itself was unhealthy.
"""

import numpy
from PIL import Image, ImageFilter


def blank_bands(image, tolerance=3.0, min_fraction=0.06):
    """Fraction of the image taken by featureless bands at its edges.

    SD sometimes returns a texture with a dead strip along one side -- most
    often the bottom, flat white or flat black -- while the rest of the tile is
    perfectly good. It is a framing artefact, not a material fault, and it is
    worth separating from both: the seam metric ignores it, the chroma check
    ignores it, and left unmeasured it costs a checkpoint a low score for
    something the prompt caused.

    Measured as rows or columns whose own standard deviation is near zero,
    counted inward from each edge only. An interior flat region is a legitimate
    plaster panel; a flat strip that runs off the edge is a margin.
    """
    grey = numpy.asarray(image.convert("L"), dtype=numpy.float32)
    height, width = grey.shape

    def dead_run(lines):
        run = 0
        for line in lines:
            if float(line.std()) > tolerance:
                break
            run += 1
        return run

    rows = dead_run(grey) + dead_run(grey[::-1])
    columns = dead_run(grey.T) + dead_run(grey.T[::-1])
    fraction = max(rows / height, columns / width)
    return {
        "blankEdgeFraction": round(float(fraction), 4),
        "blankRows": int(rows),
        "blankColumns": int(columns),
        "blank": bool(fraction >= min_fraction),
    }


def analyze(image):
    """Return raw chroma/outlier ratios and a conservative verdict."""
    rgb = numpy.asarray(image.convert("RGB"), dtype=numpy.float32)
    maximum = rgb.max(axis=2)
    minimum = rgb.min(axis=2)
    saturation = (maximum - minimum) / numpy.maximum(maximum, 1.0)
    median = numpy.asarray(
        image.convert("RGB").filter(ImageFilter.MedianFilter(3)), dtype=numpy.float32)
    local_delta = numpy.abs(rgb - median).mean(axis=2)
    high_chroma = float((saturation > 0.65).mean())
    chroma_outliers = float(((saturation > 0.65) & (local_delta > 70)).mean())
    # Broad saturation can be legitimate moss, cloth, hair, or painted magic.
    # Local saturated outliers are the useful failure signal: the broken Forge
    # decodes produced isolated neon spikes and chroma specks among smooth areas.
    bands = blank_bands(image)
    if chroma_outliers > 0.005:
        verdict = "reject"
    elif chroma_outliers > 0.001 or bands["blank"]:
        # A dead margin is "review", never "reject": the rest of the tile is
        # often the best result in its group, and the fix is a reroll or a
        # prompt change rather than dropping the checkpoint that produced it.
        verdict = "review"
    else:
        verdict = "pass"
    return {
        "highChromaRatio": round(high_chroma, 6),
        "chromaOutlierRatio": round(chroma_outliers, 6),
        "blankEdgeFraction": bands["blankEdgeFraction"],
        "blank": bands["blank"],
        "verdict": verdict,
    }
