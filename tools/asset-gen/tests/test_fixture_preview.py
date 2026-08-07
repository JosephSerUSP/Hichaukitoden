from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.fixture_preview import (NEUTRAL, compose_height,
                                 prepare_fixture_albedo)


def rgba(grey: int, alpha: int = 255, size=(4, 4)) -> Image.Image:
    data = np.zeros((size[1], size[0], 4), dtype=np.uint8)
    data[..., :3] = grey
    data[..., 3] = alpha
    return Image.fromarray(data, mode="RGBA")


class FixturePreviewTests(unittest.TestCase):
    def test_alpha_zero_leaves_neutral_base_unchanged(self):
        fixture = rgba(40, 0)
        result = np.asarray(compose_height(rgba(NEUTRAL), fixture, "replace"))
        self.assertTrue(np.all(result[..., 0] == NEUTRAL))
        self.assertTrue(np.all(result[..., 3] == 255))

    def test_negative_replace_stays_below_neutral(self):
        fixture = rgba(64, 255)
        result = np.asarray(compose_height(rgba(NEUTRAL), fixture, "replace"))
        self.assertTrue(np.all(result[..., 0] == 64))

    def test_positive_add_stays_above_neutral(self):
        fixture = rgba(160, 255)
        result = np.asarray(compose_height(rgba(NEUTRAL), fixture, "add"))
        self.assertTrue(np.all(result[..., 0] == 160))

    def test_authoritative_height_alpha_replaces_sd_alpha(self):
        albedo = rgba(180, 255)
        height_data = np.asarray(rgba(100, 255)).copy()
        height_data[:, :2, 3] = 0
        height = Image.fromarray(height_data, mode="RGBA")
        data = np.asarray(prepare_fixture_albedo(albedo, height))
        self.assertTrue(np.all(data[:, :2, 3] == 0))
        self.assertTrue(np.all(data[:, 2:, 3] == 255))


if __name__ == "__main__":
    unittest.main()
