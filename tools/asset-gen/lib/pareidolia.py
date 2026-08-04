"""Count face-like structure in a texture, so 'the rock has a face in it' is a
number rather than an impression.

These checkpoints are portrait and figure models pressed into making masonry, so
hallucinated faces are their most characteristic failure, and the owner has been
scoring otherwise-good textures down for it. Measuring it separates "this
checkpoint is bad at stone" from "this checkpoint puts people in stone", which
are different problems with different fixes.

A Haar cascade is used rather than a modern detector on purpose. It is looking
for exactly the thing that matters here -- the coarse light/dark eye-nose-mouth
arrangement that makes a human see a face in a rock -- and it is free of any
learned notion of "is this really a person", which is precisely the judgement we
do NOT want it making. The cost is that it is noisy, so:

  READ THE CONTACT SHEET BEFORE TRUSTING THE NUMBER. `audit` writes one. A rate
  that moves is only meaningful if the crops actually look like faces; this
  module's own history is that the first threshold flagged mortar joints.

MEASURED, 03.08.2026, over 954 staged raw images:

    min_neighbors=6   10.0% of images    ~45% of crops were really faces
    min_neighbors=10   4.8%              ~60%, and still catches the carvings
    min_neighbors=14   3.5%              ~55%, loses genuine hits for no gain

10 is the default on that evidence. The false positives are overwhelmingly
plain block masonry -- the cascade reads a course of bricks as an eye line --
which matters less than it sounds for the job this does: in a paired A/B the
same masonry appears in both arms, so a CHANGE in rate is meaningful even
though the absolute rate is inflated. Quote it as a comparison, never as "this
many textures have faces".
"""

from __future__ import annotations

import os

import cv2
import numpy


_cascade = None


def cascade():
    global _cascade
    if _cascade is None:
        path = os.path.join(cv2.data.haarcascades,
                            "haarcascade_frontalface_default.xml")
        _cascade = cv2.CascadeClassifier(path)
    return _cascade


def detect(path, min_neighbors=10, min_fraction=0.08):
    """Face-like regions in one image, as (x, y, w, h) boxes.

    `min_neighbors` is deliberately above OpenCV's default of 3: at 3 the
    cascade fires on any three-blob arrangement and every masonry texture on
    disk 'has faces'. `min_fraction` drops detections smaller than 8% of the
    image, which on a 256px tile is a 20px face -- below that the cascade is
    reading mortar.
    """
    image = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
    if image is None:
        return []
    image = cv2.equalizeHist(image)
    minimum = int(min(image.shape) * min_fraction)
    boxes = cascade().detectMultiScale(
        image, scaleFactor=1.08, minNeighbors=min_neighbors,
        minSize=(minimum, minimum))
    return [tuple(int(v) for v in box) for box in boxes]


def score(path, **kwargs):
    boxes = detect(path, **kwargs)
    return {"faces": len(boxes), "faceBoxes": boxes}


def audit(paths, out_path, columns=12, crop=96, **kwargs):
    """Write a contact sheet of what was flagged, for the eye to overrule.

    Returns (images_scanned, images_with_a_hit, total_hits). The sheet exists
    because a face count is only as good as what it counted, and looking is the
    only way to find that out.
    """
    crops, hits, scanned = [], 0, 0
    for path in paths:
        scanned += 1
        boxes = detect(path, **kwargs)
        if not boxes:
            continue
        hits += 1
        image = cv2.imread(path, cv2.IMREAD_COLOR)
        for x, y, w, h in boxes:
            patch = image[max(y, 0):y + h, max(x, 0):x + w]
            if patch.size:
                crops.append(cv2.resize(patch, (crop, crop),
                                        interpolation=cv2.INTER_NEAREST))
    if crops:
        rows = (len(crops) + columns - 1) // columns
        sheet = numpy.full((rows * crop, columns * crop, 3), 24, dtype=numpy.uint8)
        for index, patch in enumerate(crops):
            row, column = divmod(index, columns)
            sheet[row * crop:(row + 1) * crop, column * crop:(column + 1) * crop] = patch
        cv2.imwrite(out_path, sheet)
    return scanned, hits, len(crops)
