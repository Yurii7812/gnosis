#!/usr/bin/env python3
"""Regression: relevance should have useful recall for short multilingual notes."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import content_rank as rank


class ContentRecall(unittest.TestCase):
    def test_short_japanese_title_is_a_valid_topic(self):
        docs = {
            "lang": rank.profile("---\ntitle: 言語\n---\n\n# 言語\n", "言語"),
            "grammar": rank.profile("---\n---\n# 言語文法\n", "言語文法"),
            "unrelated": rank.profile("# 火山と地震\n", "火山と地震"),
        }
        got = [name for name, _ in rank.similarities(docs, "lang")]
        self.assertIn("grammar", got)
        self.assertNotIn("unrelated", got)

    def test_short_english_acronym_and_russian_are_indexed(self):
        ai = rank.profile("# AI\n", "AI")
        aiform = rank.profile("# AI research\n", "AI research")
        self.assertIn("ai", ai)
        self.assertIn("ai", aiform)
        ru = rank.profile("# Язык и сознание\n", "Язык и сознание")
        ru2 = rank.profile("# Языковая система\n", "Языковая система")
        self.assertTrue(set(ru) & set(ru2))
        self.assertIn("ru2", [name for name, _ in rank.similarities(
            {"ru": ru, "ru2": ru2}, "ru")])

    def test_topic_group_is_not_a_generic_index(self):
        self.assertTrue(rank.profile("# 植物\n", "植物", "topic.md", is_group=True))
        self.assertEqual(rank.profile("# Index\n", "Index", "index.md", is_group=True), {})
        self.assertEqual(rank.profile("# 2026-10-30\n\n言語について\n", "2026-10-30", "2026-10-30.md"), {})

    def test_links_and_number_only_are_not_topic_evidence(self):
        src = rank.profile("---\nfolgezettel: 1a\n---\n# 物質\nGroup:\n[Index](index.md)\n", "物質")
        other = rank.profile("---\nfolgezettel: 1a1\n---\n# 日食\n[物質](matter.md)\n", "日食")
        self.assertNotIn("other", [name for name, _ in rank.similarities(
            {"src": src, "other": other}, "src")])


if __name__ == "__main__":
    unittest.main()
