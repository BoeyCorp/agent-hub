#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path

from scripts import quota_alerts as qa
from scripts import quota_status as qs
from scripts import spend_summary as ss


def groups(left, bucket_id="weekly"):
    return [{"name": "G", "buckets": [{"id": bucket_id, "label": "Weekly Limit", "remainingPercent": left}]}]


class AlertTests(unittest.TestCase):
    def run_alerts(self, d, left, sent, **kw):
        notes = []
        qa.check_alerts(Path(d), {"claude": groups(left)}, warn_pct=25, crit_pct=10,
                        notifier=lambda u, h, t: notes.append((u, h, t)), **kw)
        sent.extend(notes)
        return notes

    def test_levels_and_hysteresis(self):
        self.assertEqual(qa.level_for(50, 25, 10), "ok")
        self.assertEqual(qa.level_for(20, 25, 10), "warning")
        self.assertEqual(qa.level_for(9, 25, 10), "critical")
        # critical -> 11% is still critical until 2 points clear of the line
        self.assertEqual(qa.level_for(11, 25, 10, "critical"), "critical")
        self.assertEqual(qa.level_for(13, 25, 10, "critical"), "warning")
        # warning -> 26% stays warning until above margin
        self.assertEqual(qa.level_for(26, 25, 10, "warning"), "warning")
        self.assertEqual(qa.level_for(28, 25, 10, "warning"), "ok")

    def test_fires_once_then_escalates_then_rearms(self):
        with tempfile.TemporaryDirectory() as d:
            sent = []
            self.assertEqual(self.run_alerts(d, 80, sent), [])
            first = self.run_alerts(d, 20, sent)
            self.assertEqual(len(first), 1)
            self.assertEqual(first[0][0], "normal")
            self.assertEqual(self.run_alerts(d, 18, sent), [])  # no spam while low
            crit = self.run_alerts(d, 8, sent)
            self.assertEqual(len(crit), 1)
            self.assertEqual(crit[0][0], "critical")
            self.assertEqual(self.run_alerts(d, 5, sent), [])  # stays critical quietly
            self.assertEqual(self.run_alerts(d, 20, sent), [])  # easing to warning is quiet
            recovered = self.run_alerts(d, 100, sent)  # reset
            self.assertEqual(len(recovered), 1)
            self.assertIn("replenished", recovered[0][1])
            again = self.run_alerts(d, 15, sent)  # re-armed
            self.assertEqual(len(again), 1)

    def test_replenish_can_be_disabled(self):
        with tempfile.TemporaryDirectory() as d:
            sent = []
            self.run_alerts(d, 5, sent)
            self.assertEqual(self.run_alerts(d, 100, sent, notify_replenish=False), [])

    def test_multiple_buckets_merge_into_one_notification(self):
        with tempfile.TemporaryDirectory() as d:
            two = [{"name": "G", "buckets": [
                {"id": "a", "label": "5h", "remainingPercent": 5},
                {"id": "b", "label": "Weekly", "remainingPercent": 20},
            ]}]
            notes = []
            qa.check_alerts(Path(d), {"codex": two}, 25, 10, notifier=lambda *a: notes.append(a))
            self.assertEqual(len(notes), 1)
            self.assertIn("5h", notes[0][2])
            self.assertIn("Weekly", notes[0][2])


class StatusTests(unittest.TestCase):
    def test_classification(self):
        self.assertEqual(qs.classify_error("token expired"), "expired")
        self.assertEqual(qs.classify_error("HTTP 429 Too Many Requests"), "rateLimited")
        self.assertEqual(qs.classify_error("connection timed out"), "offline")
        self.assertEqual(qs.classify_error("401 unauthorized"), "signin")
        self.assertEqual(qs.classify_error("boom"), "error")

    def test_signin_quotes_the_command(self):
        st = qs.derive_status("claude", False, failure={"last_error": "not logged in", "next_allowed": 0}, now=10)
        self.assertEqual(st["state"], "signin")
        self.assertEqual(st["reason"], "sign in")
        self.assertIn("claude auth login", st["message"])
        self.assertEqual(st["command"], ["claude", "auth", "login"])

    def test_stale_flag_when_limits_still_shown(self):
        st = qs.derive_status("claude", True, failure={"last_error": "network down"}, now=10)
        self.assertEqual(st["state"], "offline")
        self.assertTrue(st["stale"])
        self.assertEqual(st["command"], [])

    def test_missing_credentials_means_signin(self):
        with tempfile.TemporaryDirectory() as d:
            st = qs.derive_status("codex", False, home=Path(d))
            self.assertEqual(st["state"], "signin")
            self.assertEqual(st["command"], ["codex", "login"])
            (Path(d) / ".codex").mkdir()
            (Path(d) / ".codex" / "auth.json").write_text("{}")
            self.assertEqual(qs.derive_status("codex", False, home=Path(d))["state"], "ok")

    def test_recent_failure_read_from_backoff_file(self):
        import json
        with tempfile.TemporaryDirectory() as d:
            cache = Path(d) / "cache"
            cache.mkdir()
            (cache / "quota_backoff.json").write_text(json.dumps({"last_failure": 1000, "last_error": "429", "next_allowed": 1060}))
            st = qs.derive_status("antigravity", True, base_dir=Path(d), now=1010)
            self.assertEqual(st["state"], "rateLimited")
            self.assertIn("50s", st["message"])
            self.assertEqual(qs.derive_status("antigravity", True, base_dir=Path(d), now=1000 + 99999)["state"], "ok")


class SpendTests(unittest.TestCase):
    def analytics(self):
        daily = [{"date": f"d{i}", "cost": float(i), "agents": {"claude": {"cost": float(i)}, "codex": {"cost": 0.0}}} for i in range(1, 31)]
        return {"daily": daily}

    def test_summarize(self):
        s = ss.summarize(self.analytics())
        self.assertEqual(s["todayCost"], 30.0)
        self.assertEqual(s["weekCost"], sum(range(24, 31)))
        self.assertEqual(s["monthCost"], sum(range(1, 31)))
        self.assertEqual(s["avgDailyCost"], round(sum(range(24, 31)) / 7, 2))
        self.assertEqual(s["weekByAgent"]["claude"], float(sum(range(24, 31))))
        self.assertEqual(len(s["dailyHistory"]), 14)
        self.assertEqual(s["peakDailyCost"], 30.0)
        self.assertIn("claude", s["byAgentDetail"])
        self.assertEqual(s["byAgentDetail"]["claude"]["weekCost"], float(sum(range(24, 31))))
        self.assertIn("topModels", s)
        self.assertIn("cacheSavings", s)

    def test_get_spend_caches(self):
        calls = []
        def agg():
            calls.append(1)
            return self.analytics()
        with tempfile.TemporaryDirectory() as d:
            ss.get_spend(Path(d), now=100, aggregate=agg)
            ss.get_spend(Path(d), now=200, aggregate=agg)
            self.assertEqual(len(calls), 1)
            ss.get_spend(Path(d), now=100 + ss.TTL_S + 1, aggregate=agg)
            self.assertEqual(len(calls), 2)


if __name__ == "__main__":
    unittest.main()
