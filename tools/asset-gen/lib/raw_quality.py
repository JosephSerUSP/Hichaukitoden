"""Cheap diagnostics for catching malformed SD output before post-processing.

The pixel pipeline can turn a broken, high-chroma latent decode into a
plausible-looking 64px texture. Keep this check on the raw model PNG so reports
show when the source itself was unhealthy.
"""

import numpy
from PIL import Image, ImageFilter


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
    if chroma_outliers > 0.005:
        verdict = "reject"
    elif chroma_outliers > 0.001:
        verdict = "review"
    else:
        verdict = "pass"
    return {
        "highChromaRatio": round(high_chroma, 6),
        "chromaOutlierRatio": round(chroma_outliers, 6),
        "verdict": verdict,
    }
