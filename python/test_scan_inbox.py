#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path

import paper_pkm as pp
import scan_inbox as si

PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082")


class ScanInboxTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "vault"
        self.root.mkdir()
        pp.create_paper_index(self.root)
        self.src = Path(self.tmp.name) / "scans"
        self.src.mkdir()
        for n in ("a.png", "b.png", "c.png"):
            (self.src / n).write_bytes(PNG + n.encode())

    def test_import_renames_and_lists(self):
        r = si.import_files(self.root, [str(self.src)])
        self.assertEqual(len(r["added"]), 3)
        self.assertTrue(all(n.startswith("paper-scan-") and n.endswith(".png") for n in r["added"]))
        self.assertEqual(si.list_scans(self.root)["scans"], sorted(r["added"]))
        # 並べ替え（画面の s）に使う、更新日時と大きさ
        info = si.list_scans(self.root)["info"]
        self.assertEqual(sorted(info), sorted(r["added"]))
        self.assertTrue(all(v["size"] > 0 and v["mtime"] > 0 for v in info.values()))
        # 同じ名前（paper-scan-…）は二重に取り込まない
        again = si.import_files(self.root, [str(si.inbox(self.root))])
        self.assertEqual(again["added"], [])

    def test_assign_makes_note_and_remembers_last(self):
        names = si.import_files(self.root, [str(self.src)])["added"]
        r = si.assign(self.root, names[0], "1a2")
        self.assertTrue(r["ok"], r)
        self.assertTrue((self.root / "PA-1a2.png").is_file())
        self.assertEqual(si.list_scans(self.root)["last"], "PA-1a2")
        self.assertEqual(len(si.list_scans(self.root)["scans"]), 2)
        note = (self.root / r["note"]).read_text("utf-8")
        self.assertIn("![](PA-1a2.png)", note)

    def test_same_id_overwrites_and_keeps_old_in_trash(self):
        names = si.import_files(self.root, [str(self.src)])["added"]
        si.assign(self.root, names[0], "3")
        old = (self.root / "PA-3.png").read_bytes()
        si.assign(self.root, names[1], "3")
        self.assertNotEqual((self.root / "PA-3.png").read_bytes(), old)
        trashed = [p for p in (self.root / ".trash").iterdir() if p.name.endswith("_PA-3.png")]
        self.assertEqual(len(trashed), 1)
        self.assertEqual(trashed[0].read_bytes(), old)

    def test_bad_id_and_missing_scan(self):
        names = si.import_files(self.root, [str(self.src)])["added"]
        self.assertFalse(si.assign(self.root, names[0], "x!")["ok"])
        self.assertEqual(si.main(["assign", str(self.root), "nothing.png", "1"]), 1)

    def test_phone_scans_are_not_imported_twice(self):
        phone = Path(self.tmp.name) / "phone"
        phone.mkdir()
        (phone / "paper-scan-20261024-090000-01.jpg").write_bytes(PNG)
        r = si.import_files(self.root, [str(phone)])
        self.assertEqual(r["added"], ["paper-scan-20261024-090000-01.jpg"])
        si.assign(self.root, r["added"][0], "7")
        again = si.import_files(self.root, [str(phone)])
        self.assertEqual(again["added"], [])
        self.assertEqual(si.list_scans(self.root)["scans"], [])

    def test_numbers_made_on_the_phone_are_applied(self):
        import json
        phone = Path(self.tmp.name) / "phone2"
        phone.mkdir()
        for i in (1, 2):
            (phone / f"paper-scan-20261024-090000-0{i}.jpg").write_bytes(PNG + bytes([i]))
        (phone / "scans.json").write_text(json.dumps([
            {"name": "paper-scan-20261024-090000-01.jpg", "id": "2a"},
            {"name": "paper-scan-20261024-090000-02.jpg", "id": ""}]))
        r = si.import_files(self.root, [str(phone)])
        self.assertEqual(r["numbered"], ["paper-scan-20261024-090000-01.jpg"])
        self.assertTrue((self.root / "PA-2a.jpg").is_file())
        self.assertEqual(si.list_scans(self.root)["scans"], ["paper-scan-20261024-090000-02.jpg"])

    def test_phone_numbers_keep_their_own_prefix(self):
        import json
        phone = Path(self.tmp.name) / "phone3"
        phone.mkdir()
        for i in (1, 2):
            (phone / f"paper-scan-20261025-090000-0{i}.jpg").write_bytes(PNG + bytes([i + 10]))
        (phone / "scans.json").write_text(json.dumps([
            {"name": "paper-scan-20261025-090000-01.jpg", "id": "PB-2a"},
            {"name": "paper-scan-20261025-090000-02.jpg", "id": "PA-1"}]))
        r = si.import_files(self.root, [str(phone)])
        self.assertEqual(sorted(r["numbered"]), sorted(["paper-scan-20261025-090000-01.jpg", "paper-scan-20261025-090000-02.jpg"]), r)
        self.assertTrue((self.root / "PB-2a.jpg").is_file() and (self.root / "PA-1.jpg").is_file())

    def test_importmove_moves_photos_from_outside_the_vault(self):
        r = si.import_files(self.root, [str(self.src)], move=True)
        self.assertEqual(len(r["added"]), 3)
        self.assertEqual(list(self.src.iterdir()), [])
        self.assertEqual(si.main(["importmove", str(self.root), str(self.src)]), 0)

    def test_diary(self):
        names = si.import_files(self.root, [str(self.src)])["added"]
        r = si.diary(self.root, names[0], "2026/10/24")
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["date"], "2026-10-24")
        self.assertEqual(si.main(["diary", str(self.root), names[1], "あした"]), 1)


if __name__ == "__main__":
    unittest.main()
