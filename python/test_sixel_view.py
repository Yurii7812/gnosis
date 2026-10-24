import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sixel_view
from PIL import Image


class SixelViewTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR"))
        self.dir = Path(self.d.name)
        Image.new("RGB", (400, 300), (200, 30, 30)).save(self.dir / "a.jpg")
        Image.new("RGB", (40, 30), (30, 30, 200)).save(self.dir / "b c.png")
        self.note = self.dir / "n.md"
        self.note.write_text("# t\n\n![](a.jpg)\n\n![x](b%20c.png) ![](gone.png) ![](https://e.com/z.png)\n", encoding="utf-8")

    def tearDown(self):
        self.d.cleanup()

    def test_list_marks_missing_and_skips_remote(self):
        items = sixel_view.list_images(str(self.note))
        self.assertEqual([i["label"] for i in items], ["a.jpg", "b c.png", "gone.png"])
        self.assertEqual([i["exists"] for i in items], [True, True, False])

    def test_list_reads_unsaved_text_file(self):
        tmp = self.dir / "buf.txt"
        tmp.write_text("![](b%20c.png)\n", encoding="utf-8")
        items = sixel_view.list_images(str(self.note), str(tmp))
        self.assertEqual([i["label"] for i in items], ["b c.png"])

    def test_render_fits_in_cells_and_is_sixel(self):
        os.environ["GNOSIS_CELL_PX"] = "10x20"
        out = sixel_view.render(str(self.dir / "a.jpg"), 30, 10)
        head, body = out.split("\n", 1)
        w, h = map(int, head.split())
        self.assertLessEqual(w, 30)
        self.assertLessEqual(h, 10)
        self.assertTrue(body.startswith("\x1bP0;1;0q"))
        self.assertTrue(body.endswith("\x1b\\"))

    def test_small_image_is_not_enlarged(self):
        os.environ["GNOSIS_CELL_PX"] = "10x20"
        head = sixel_view.render(str(self.dir / "b c.png"), 100, 40).split("\n", 1)[0]
        self.assertEqual(head, "4 2")

    def test_inline_makes_cache_and_reuses_it(self):
        os.environ["GNOSIS_CELL_PX"] = "10x20"
        cache = self.dir / "cache"
        a = str(self.dir / "a.jpg")
        out = sixel_view.inline(str(cache), 30, 10, [a, str(self.dir / "none.png")])
        self.assertEqual(list(out), [a])  # 無い画像は飛ばす
        self.assertLessEqual(out[a]["cols"], 30)
        self.assertLessEqual(out[a]["rows"], 10)
        six = Path(out[a]["file"])
        self.assertTrue(six.read_text(encoding="latin-1").startswith("\x1bP0;1;0q"))
        mtime = six.stat().st_mtime_ns
        again = sixel_view.inline(str(cache), 30, 10, [a])
        self.assertEqual(again[a]["file"], out[a]["file"])
        self.assertEqual(six.stat().st_mtime_ns, mtime)  # 作り直さない

    def test_cell_env_override(self):
        os.environ["GNOSIS_CELL_PX"] = "8x16"
        self.assertEqual(sixel_view.cell_px(), (8, 16))


if __name__ == "__main__":
    unittest.main()
