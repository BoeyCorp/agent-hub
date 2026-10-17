#!/usr/bin/env python3
import json
import os
import tempfile
import time
import unittest
from pathlib import Path

from scripts import pricing

OPENROUTER = {
    "data": [
        {"id": "anthropic/claude-opus-5.5", "pricing": {"prompt": "0.000004", "completion": "0.00002", "input_cache_read": "0.0000002", "input_cache_write": "0.000005"}},
        {"id": "anthropic/claude-opus-5.5:batch", "pricing": {"prompt": "0.000002", "completion": "0.00001"}},
        {"id": "google/gemini-4-argon", "pricing": {"prompt": "0.000002", "completion": "0.00001"}},
        {"id": "openai/gpt-6-luna", "pricing": {"prompt": "0.0000001", "completion": "0.0000005", "input_cache_read": "0.00000001"}},
        {"id": "openrouter/auto", "pricing": {"prompt": "-1", "completion": "-1"}},
    ]
}

LITELLM = {
    "claude-haiku-5-5": {"litellm_provider": "anthropic", "input_cost_per_token": 1e-7, "output_cost_per_token": 5e-7},
    "bedrock/claude-haiku-5-5": {"litellm_provider": "bedrock", "input_cost_per_token": 9, "output_cost_per_token": 9},
    "gpt-6-luna": {"litellm_provider": "openai", "input_cost_per_token": 9e-7, "output_cost_per_token": 9e-7},
}


def tables():
    return {
        "sources": [
            ("OpenRouter", pricing.parse_openrouter(OPENROUTER)),
            ("LiteLLM", pricing.parse_litellm(LITELLM)),
            ("Bundled", {"claude-fable-5-1": (1e-5, 5e-5, 1e-6, 1.25e-5)}),
        ],
        "aliases": {"claude": "claude-opus-5-5"},
        "fetchedAt": "",
        "bundledUpdated": "",
    }


class NormalizeTests(unittest.TestCase):
    def test_local_names_and_price_ids_meet(self):
        for name in ("Claude Opus 5.5 (Medium)", "claude-opus-5-5", "anthropic/claude-opus-5.5",
                     "claude-opus-5-5-20261001", "claude-opus-5-5[1m]", "anthropic/claude-opus-5.5:batch"):
            self.assertEqual(pricing.normalize(name), "claude-opus-5-5", name)

    def test_synthetic(self):
        self.assertEqual(pricing.normalize("<synthetic>"), "synthetic")


class LookupTests(unittest.TestCase):
    def test_openrouter_first(self):
        rates, src = pricing.lookup("GPT-6 Luna", tables())
        self.assertEqual(src, "OpenRouter")
        self.assertAlmostEqual(rates[0], 1e-7)
        self.assertAlmostEqual(rates[2], 1e-8)

    def test_litellm_when_openrouter_lacks_model(self):
        rates, src = pricing.lookup("claude-haiku-5-5", tables())
        self.assertEqual(src, "LiteLLM")
        self.assertAlmostEqual(rates[0], 1e-7)

    def test_bundled_last(self):
        self.assertEqual(pricing.lookup("Claude Fable 5.1", tables())[1], "Bundled")

    def test_effort_suffix_and_longest_prefix(self):
        rates, _ = pricing.lookup("gpt-6-luna-high", tables())
        self.assertAlmostEqual(rates[0], 1e-7)

    def test_alias(self):
        self.assertEqual(pricing.lookup("Claude (Default)", tables())[0][0], 4e-6)

    def test_unknown_is_none(self):
        self.assertIsNone(pricing.lookup("made-up-model", tables()))

    def test_missing_cache_prices_use_usual_ratios(self):
        rates, _ = pricing.lookup("Gemini 4 Argon (Medium)", tables())
        self.assertAlmostEqual(rates[2], 2e-7)
        self.assertAlmostEqual(rates[3], 2.5e-6)

    def test_skips_variants_negative_and_other_providers(self):
        t = pricing.parse_openrouter(OPENROUTER)
        self.assertNotIn("auto", t)
        self.assertEqual(t["claude-opus-5-5"][0], 4e-6)
        self.assertEqual(pricing.parse_litellm(LITELLM)["claude-haiku-5-5"][0], 1e-7)


class CostTests(unittest.TestCase):
    def setUp(self):
        pricing.reset()
        pricing._tables = tables()

    def tearDown(self):
        pricing.reset()

    def test_cost_uses_all_four_rates(self):
        c = pricing.cost("claude-opus-5-5", 1_000_000, 1_000_000, 1_000_000, 1_000_000)
        self.assertAlmostEqual(c, 4 + 20 + 0.2 + 5)

    def test_unknown_costs_zero_and_is_reported(self):
        self.assertEqual(pricing.cost("made-up-model", 1000, 1000), 0.0)
        self.assertIn("made-up-model", pricing.info()["unknownModels"])

    def test_unknown_without_tokens_is_not_reported(self):
        pricing.cost("made-up-model", 0, 0)
        self.assertEqual(pricing.info()["unknownModels"], [])

    def test_synthetic_is_free_not_unknown(self):
        self.assertEqual(pricing.cost("<synthetic>", 1000, 1000), 0.0)
        self.assertEqual(pricing.info()["unknownModels"], [])


class CacheTests(unittest.TestCase):
    def test_needs_refresh(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            now = time.time()
            self.assertTrue(pricing.needs_refresh(d, now))
            (d / pricing.CACHE_FILE).write_text("{}")
            self.assertFalse(pricing.needs_refresh(d, now))
            self.assertTrue(pricing.needs_refresh(d, now + pricing.MAX_AGE_S + 1))
            later = now + pricing.MAX_AGE_S + 1
            (d / pricing.REFRESH_FLAG).touch()
            os.utime(d / pricing.REFRESH_FLAG, (later - 60, later - 60))
            self.assertFalse(pricing.needs_refresh(d, later))

    def test_cached_tables_and_version(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / pricing.CACHE_FILE).write_text(json.dumps({
                "fetchedAt": "2026-10-17T00:00:00+00:00",
                "openrouter": {"gpt-6-luna": [1e-7, 5e-7, 1e-8, 1.25e-7]},
            }))
            t = pricing._tables_for(d)
            self.assertEqual([s for s, _ in t["sources"]], ["OpenRouter", "Bundled"])
            v1 = pricing.version(d)
            (d / pricing.CACHE_FILE).write_text(json.dumps({"openrouter": {"gpt-6-luna": [2e-7, 5e-7, 1e-8, 1.25e-7]}}))
            self.assertNotEqual(v1, pricing.version(d))

    def test_refresh_keeps_previous_list_on_failure(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / pricing.CACHE_FILE).write_text(json.dumps({"fetchedAt": "old", "openrouter": {"x": [1, 1, 1, 1]}}))
            orig = pricing._fetch_json
            pricing._fetch_json = lambda url: (_ for _ in ()).throw(OSError("offline"))
            try:
                res = pricing.refresh(d)
            finally:
                pricing._fetch_json = orig
            self.assertEqual(res["openrouter"], {"x": [1, 1, 1, 1]})
            self.assertEqual(res["fetchedAt"], "old")
            self.assertIn("openrouter", res["errors"])

    def test_bundled_file_is_valid(self):
        b = pricing.load_bundled()
        self.assertTrue(b["updated"])
        self.assertIn("gemini-4-argon", b["models"])
        self.assertIn("claude", b["aliases"])


if __name__ == "__main__":
    unittest.main()
