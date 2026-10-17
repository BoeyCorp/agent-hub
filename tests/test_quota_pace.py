#!/usr/bin/env python3
import datetime as dt
import tempfile
import unittest
from pathlib import Path

from scripts import quota_pace as qp

NOW = 1_800_000_000.0


def iso(epoch: float) -> str:
    return dt.datetime.fromtimestamp(epoch, tz=dt.timezone.utc).isoformat()


def bucket(window="5h", used=0.4, remaining_s=3 * 3600, win_s=None):
    return {
        "id": "b", "window": window, "label": "Limit",
        "remainingFraction": round(1 - used, 4), "usedPercent": round(used * 100),
        "resetTime": iso(NOW + remaining_s),
    }


def ramp(start_used, end_used, minutes, step=1):
    """Samples ending at NOW with a linear rise over `minutes`."""
    n = minutes // step
    return [[NOW - (n - i) * step * 60, start_used + (end_used - start_used) * i / n, 0.0] for i in range(n + 1)]


class WindowTests(unittest.TestCase):
    def test_window_parsing(self):
        self.assertEqual(qp.window_seconds({"window": "5h"}), 5 * 3600)
        self.assertEqual(qp.window_seconds({"window": "session"}), 5 * 3600)
        self.assertEqual(qp.window_seconds({"window": "weekly"}), 7 * 86400)
        self.assertEqual(qp.window_seconds({"label": "Monthly Limit"}), 30 * 86400)
        self.assertEqual(qp.window_seconds({"label": "5-Hour Limit"}), 5 * 3600)
        self.assertEqual(qp.window_seconds({"label": "3h Limit"}), 3 * 3600)
        self.assertEqual(qp.window_seconds({"windowSeconds": 600}), 600)
        self.assertIsNone(qp.window_seconds({"window": "secondary", "label": "Secondary Limit"}))

    def test_kinds_and_duration(self):
        self.assertEqual(qp.window_kind(5 * 3600), "5h")
        self.assertEqual(qp.window_kind(7 * 86400), "7d")
        self.assertEqual(qp.window_kind(30 * 86400), "30d")
        self.assertEqual(qp.window_kind(None), "other")
        self.assertEqual(qp.format_duration(69 * 60), "1h 9m")
        self.assertEqual(qp.format_duration(40 * 60), "40m")
        self.assertEqual(qp.format_duration(28 * 3600), "1d 4h")


class StatusTests(unittest.TestCase):
    def test_limit_reached(self):
        r = qp.compute_pace(bucket(used=1.0), [], NOW)
        self.assertEqual(r["paceStatus"], "limitReached")
        self.assertEqual(r["paceText"], "Limit reached")

    def test_no_pace_without_reset(self):
        b = bucket()
        b["resetTime"] = ""
        self.assertEqual(qp.compute_pace(b, [], NOW)["paceStatus"], "noPace")
        self.assertEqual(qp.compute_pace(b, [], NOW)["paceText"], "No pace for this limit")

    def test_early_window(self):
        r = qp.compute_pace(bucket(used=0.01, remaining_s=5 * 3600 - 60), [], NOW)
        self.assertEqual(r["paceStatus"], "early")
        self.assertIn("2%", r["paceText"])

    def test_no_usage(self):
        r = qp.compute_pace(bucket(used=0.0), [], NOW)
        self.assertEqual(r["paceStatus"], "noUsage")

    def test_collecting_data(self):
        samples = [[NOW - 120, 0.30, 0.0], [NOW, 0.31, 0.0]]
        r = qp.compute_pace(bucket(used=0.31), samples, NOW)
        self.assertEqual(r["paceStatus"], "collecting")
        self.assertTrue(r["paceText"].startswith("Collecting data · pace "))

    def test_no_recent_data(self):
        r = qp.compute_pace(bucket(used=0.3), ramp(0.1, 0.3, 30), NOW, sample_age_s=7200)
        self.assertEqual(r["paceStatus"], "noData")

    def test_idle(self):
        samples = [[NOW - 7200 + i * 600, 0.4, 0.0] for i in range(13)]
        samples[0][1] = 0.3
        samples[1][1] = 0.4
        r = qp.compute_pace(bucket(used=0.4), samples, NOW)
        self.assertEqual(r["paceStatus"], "idle")
        self.assertTrue(r["paceText"].startswith("Idle 1h 50m"))

    def test_short_window_runs_out(self):
        # 20% -> 60% over 30 minutes: 80%/h, 40% left lasts ~30 minutes, 3h remain
        r = qp.compute_pace(bucket(used=0.6, remaining_s=3 * 3600), ramp(0.2, 0.6, 30), NOW)
        self.assertEqual(r["paceStatus"], "runsOut")
        self.assertTrue(r["paceText"].startswith("Runs out in "))
        self.assertEqual(r["paceSeverity"], "critical")
        self.assertTrue(r["paceAhead"])

    def test_short_window_lasts(self):
        # slow rise: 30% -> 32% in an hour with 4h to reset
        r = qp.compute_pace(bucket(used=0.32, remaining_s=4 * 3600), ramp(0.30, 0.32, 60), NOW)
        self.assertEqual(r["paceStatus"], "lasts")
        self.assertTrue(r["paceText"].startswith("Lasts until reset · pace "))

    def test_weekly_blends_average_with_last_day(self):
        # 3.5 days in, 35% used => average ~0.4%/h. Last 24h flat => blended 0.2%/h,
        # 65% left would last ~325h; far longer than the 84h remaining.
        week = 7 * 86400
        remaining = week / 2
        flat = [[NOW - 24 * 3600 + i * 3600, 0.35, 0.0] for i in range(25)]
        b = bucket(window="weekly", used=0.35, remaining_s=remaining)
        r = qp.compute_pace(b, flat, NOW)
        self.assertEqual(r["paceStatus"], "lasts")
        self.assertAlmostEqual(r["paceMarker"], 0.5, places=3)
        self.assertFalse(r["paceAhead"])

    def test_weekly_busy_day_does_not_predict_run_out_alone(self):
        # Average pace is gentle; a single busy hour raises the blend only by half.
        week = 7 * 86400
        b = bucket(window="weekly", used=0.20, remaining_s=week * 0.75)
        samples = [[NOW - 24 * 3600, 0.15, 0.0], [NOW, 0.20, 0.0]]
        r = qp.compute_pace(b, samples, NOW)
        self.assertEqual(r["paceStatus"], "lasts")

    def test_weekly_heavy_week_runs_out(self):
        week = 7 * 86400
        b = bucket(window="weekly", used=0.80, remaining_s=week * 0.6)
        samples = [[NOW - 24 * 3600, 0.55, 0.0], [NOW, 0.80, 0.0]]
        r = qp.compute_pace(b, samples, NOW)
        self.assertEqual(r["paceStatus"], "runsOut")


class SampleStoreTests(unittest.TestCase):
    def test_reset_clears_history(self):
        s = qp.record_sample([], NOW - 3600, 0.8, None)
        s = qp.record_sample(s, NOW - 1800, 0.9, None)
        s = qp.record_sample(s, NOW, 0.1, None)
        self.assertEqual(len(s), 1)
        self.assertEqual(s[0][1], 0.1)

    def test_close_samples_are_merged(self):
        s = qp.record_sample([], NOW, 0.1, None)
        s = qp.record_sample(s, NOW + 5, 0.2, None)
        self.assertEqual(len(s), 1)
        self.assertEqual(s[0][1], 0.2)

    def test_old_samples_are_thinned(self):
        s = []
        for i in range(60):
            s = qp.record_sample(s, NOW - 6 * 3600 + i * 60, 0.1, None)
        s = qp.record_sample(s, NOW, 0.1, None)
        self.assertLess(len(s), 20)

    def test_apply_pace_persists_and_enriches(self):
        with tempfile.TemporaryDirectory() as d:
            groups = [{"name": "G", "buckets": [bucket(used=0.5)]}]
            qp.apply_pace(Path(d), "claude", groups, now=NOW)
            self.assertIn("paceStatus", groups[0]["buckets"][0])
            self.assertEqual(groups[0]["buckets"][0]["windowKind"], "5h")
            self.assertTrue(qp.load_samples(Path(d)))


if __name__ == "__main__":
    unittest.main()
