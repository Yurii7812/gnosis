import unittest

from merge3 import merge3


class Merge3Test(unittest.TestCase):
    def test_sync_appends_backlink_while_user_edits_body(self):
        base = ["---", "time: x", "---", "", "# t", "", "", ""]
        ours = ["---", "time: x", "---", "", "# t", "", "あ", ""]
        theirs = base + ["BackLink:", "[d](d.md)"]
        self.assertEqual(merge3(base, ours, theirs), ours + ["BackLink:", "[d](d.md)"])

    def test_sync_adds_id_while_user_edits_body(self):
        base = ["---", "time: x", "---", "", "# t", "本文"]
        ours = ["---", "time: x", "---", "", "# t", "本文", "追記"]
        theirs = ["---", "time: x", 'folgezettel: "3"', "---", "", "# t", "本文"]
        self.assertEqual(merge3(base, ours, theirs), ["---", "time: x", 'folgezettel: "3"', "---", "", "# t", "本文", "追記"])

    def test_same_place_conflicts(self):
        base = ["a", "b", "c"]
        self.assertIsNone(merge3(base, ["a", "X", "c"], ["a", "Y", "c"]))

    def test_one_side_unchanged(self):
        base = ["a", "b"]
        self.assertEqual(merge3(base, base, ["a", "b", "c"]), ["a", "b", "c"])
        self.assertEqual(merge3(base, ["a", "b", "c"], base), ["a", "b", "c"])

    def test_same_insert_on_both_sides_is_taken_once(self):
        base = ["a"]
        self.assertEqual(merge3(base, ["a", "z"], ["a", "z"]), ["a", "z"])

    def test_both_append_different_lines_conflict(self):
        self.assertIsNone(merge3(["a"], ["a", "x"], ["a", "y"]))


if __name__ == "__main__":
    unittest.main()
