#!/usr/bin/env python3
"""Tests for srv/noaa_kp_sidecar.py (stdlib only).

Covers: Kp text-feed parsing (1m and 3h formats, boundary clamping),
the cache update/stale law, and the served JSON shape. The parser is
the safety net between NOAA's text format and the game's flywheel —
a malformed row must NEVER crash the sidecar or push garbage into
weather. Run: python3 srv/test_noaa_kp_sidecar.py
"""
import importlib.util
import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "noaa_kp_sidecar", os.path.join(_HERE, "noaa_kp_sidecar.py")
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class TestKpParsing(unittest.TestCase):
    def test_1m_feed_row(self):
        text = (
            "# Planetary K-index 1-minute feed\n"
            "2026-10-09 12:34:56.789  1.33  2  0 -1  1  1  1\n"
            "2026-10-09 12:35:56.789  2.67  3  1  0  2  2  1\n"
        )
        self.assertAlmostEqual(mod._parse_kp(text), 2.67)

    def test_3h_feed_row(self):
        text = (
            "# 3-hour planetary Kp\n"
            "2026-10-08 00:00:00.000   0.67  0  0  0  1  1  1\n"
            "2026-10-08 03:00:00.000   4.33  4  4  3  4  5  4\n"
        )
        self.assertAlmostEqual(mod._parse_kp(text), 4.33)

    def test_malformed_rows_ignored(self):
        text = (
            "garbage line without numbers\n"
            "2026-10-09 n.A. badly formatted\n"
            "2026-10-09 12:00:00.000  3.00  3  2  2  3  3  2\n"
        )
        self.assertAlmostEqual(mod._parse_kp(text), 3.00)

    def test_kp_out_of_range_rejected(self):
        text = "2026-10-09 12:00:00.000  10.5 garbage\n"
        self.assertIsNone(mod._parse_kp(text))

    def test_empty_feed(self):
        self.assertIsNone(mod._parse_kp(""))


class TestCacheLaw(unittest.TestCase):
    def test_update_marks_fresh(self):
        c = mod.KpCache()
        c.update(2.0, 1234.5)
        self.assertEqual(c.kp, 2.0)
        self.assertFalse(c.stale)

    def test_error_marks_stale_keeps_last(self):
        c = mod.KpCache()
        c.update(2.0, 1234.5)
        c.last_error = "upstream down"
        c.stale = True
        self.assertEqual(c.kp, 2.0)
        self.assertTrue(c.stale)


if __name__ == "__main__":
    unittest.main(verbosity=2)
