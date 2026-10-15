#!/usr/bin/env python3
"""カスタムテーマ編集画面の実画面試験。擬似端末で本物の Vim を動かし、プレビューの文字の色を
画面（pyte）の 1 文字ごとの色で確かめる（24 ビット色）。

  - 設定画面（↑ ↓ で移動）→ カスタム配色 → 編集画面が出る
  - HEX を打つと、保存する前でもプレビューの背景が即座に変わる
  - 取り消すと設定ファイルは書き換わらない・実際の画面（テーマ）も変わらない
  - 保存すると設定に残る。通常の Vim とアプリ（\\A）の配色は別々に保存される
  - アプリ用の編集は白い背景から始まる
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import pyte  # noqa: F401
except ImportError:
    print("skip: pyte が無いためテーマ編集画面の擬似端末試験を省略")
    sys.exit(0)
from keys_pty import ESC, Session  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
TMP_BASE = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
ITEMS = ['fontSize', 'fontFamily', 'lineSpacing', 'terminal', 'language', 'maximized', 'window', 'appearance', 'theme',
         'theme_add', 'custom', 'theme_reset', 'app_theme', 'app_custom', 'app_theme_reset']


class TestThemeEditor(unittest.TestCase):
    def setUp(self) -> None:
        os.makedirs(TMP_BASE, exist_ok=True)
        self.work = Path(tempfile.mkdtemp(dir=TMP_BASE, prefix="theme-"))
        self.addCleanup(shutil.rmtree, self.work, True)
        self.home = self.work / "home"
        self.gh = self.work / "gh"
        self.home.mkdir()
        self.gh.mkdir()
        self.v = self.work / "vault"
        self.v.mkdir()
        (self.v / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n", encoding="utf-8")
        (self.gh / "vaults.json").write_text(json.dumps({"version": 1, "last": str(self.v), "vaults": [{"path": str(self.v), "name": "v"}]}), encoding="utf-8")
        self.settings = self.v / ".gnosis" / "settings.json"
        self.settings.parent.mkdir()
        self.settings.write_text(json.dumps({"version": 1, "language": "ja", "appearance": "dark", "theme": {"kind": "builtin"}, "customThemes": {}}), encoding="utf-8")
        rc = self.work / "vimrc"
        rc.write_text(f"source {REPO}/vimrc_gnosis\n", encoding="utf-8")
        self.rc = str(rc)

    def session(self) -> Session:
        return Session(self.rc, str(self.home), str(self.gh), rows=44, cols=100)

    def goto_item(self, s: Session, item: str) -> None:
        for _ in range(ITEMS.index(item)):
            s.key("ss3", "down", 0.15)

    def cell_bg(self, s: Session, needle: str, offset: int = 0) -> str:
        """画面で needle が出る行の、その文字の背景色（24 ビット色。無ければ default）"""
        for y, line in enumerate(s.screen.display):
            x = line.find(needle)
            if x >= 0:
                return s.screen.buffer[y][x + offset].bg
        raise AssertionError(f"{needle!r} が画面に無い:\n{s.text()}")

    def cell(self, s: Session, needle: str):
        for y, line in enumerate(s.screen.display):
            x = line.find(needle)
            if x >= 0:
                return s.screen.buffer[y][x]
        raise AssertionError(f"{needle!r} が画面に無い")

    def test_live_preview_cancel_save(self) -> None:
        before = self.settings.read_text(encoding="utf-8")
        notes_before = {p.name: p.read_bytes() for p in self.v.glob("*.md")}
        with self.session() as s:
            s.send("s", 0.8)  # 起動画面から設定画面
            self.goto_item(s, "custom")
            s.send("\r", 0.8)
            self.assertIn("プレビュー", s.text())
            self.assertIn("植物について", s.text())
            self.assertIn("ローズマリー", s.text())
            self.assertIn("#0C1D32", s.text())  # HEX が出る
            self.assertNotIn("example.md", s.text())  # リンクは表示名だけ（URL は出さない）
            self.assertEqual(self.cell_bg(s, "植物について"), "0c1d32")  # 最初は今の背景
            link = self.cell(s, "ローズマリー")
            self.assertTrue(link.underscore, "リンクは下線")
            self.assertEqual(link.fg, "e1f4e4")
            self.assertEqual(self.cell(s, "植物について").fg, "eeda77")  # 見出しの色
            # 背景を HEX で打つ。打つたびに反映され、確定前でもプレビューの背景が変わる
            s.send("\r", 0.4)  # 背景の行で Enter
            for ch in "ffffff":
                s.send(ch, 0.2)
            self.assertEqual(self.cell_bg(s, "植物について"), "ffffff", "打っている途中でもプレビューに反映される")
            s.send("\r", 0.5)
            self.assertEqual(self.cell_bg(s, "レモンバーム"), "ffffff")
            # 実際の画面（この編集画面の外側＝本文の背景）は保存するまで変わらない
            self.assertEqual(self.settings.read_text(encoding="utf-8"), before, "保存前に設定ファイルを書かない")
            # 見出しと本文の色も個別に変える
            s.key("ss3", "down", 0.2)
            s.key("ss3", "down", 0.2)
            s.key("ss3", "down", 0.2)  # 見出し
            s.send("\r", 0.3)
            for ch in "7c2d12":
                s.send(ch, 0.15)
            s.send("\r", 0.5)
            self.assertEqual(self.cell(s, "植物について").fg, "7c2d12")
            # 取り消す（確認に y）→ 設定画面へ。何も保存されない
            s.send("q", 0.6)
            self.assertIn("変更を捨てて戻りますか", s.text())
            s.send("y", 0.8)
            self.assertIn("設定", s.text())
            self.assertEqual(self.settings.read_text(encoding="utf-8"), before, "取り消しでは保存されない")
            # もう一度開いて、保存する
            s.send("\r", 0.8)  # 設定画面に戻った直後の選択位置は、編集を始めた項目（custom）のまま
            self.assertEqual(self.cell_bg(s, "植物について"), "0c1d32", "取り消したあと、編集画面は元の色から始まる")
            s.send("\r", 0.4)
            for ch in "ffffff":
                s.send(ch, 0.15)
            s.send("\r", 0.4)
            s.send("s", 1.0)  # 保存して使う
            self.assertIn("設定", s.text())
        self.assertEqual({p.name: p.read_bytes() for p in self.v.glob("*.md")}, notes_before, "プレビューや保存でノートが変わった")
        saved = json.loads(self.settings.read_text(encoding="utf-8"))
        self.assertEqual(saved["theme"], {"kind": "custom", "name": "my-theme"})
        self.assertEqual(saved["customThemes"]["my-theme"]["bg"], "#ffffff")
        self.assertEqual(saved["customThemes"]["my-theme"]["base"], "light")
        self.assertEqual(saved.get("appTheme", {"kind": "builtin"}), {"kind": "builtin"}, "Vim のテーマを保存しても、アプリのテーマは変わらない")
        # 再起動（新しい Vim）しても、保存した配色で始まる（vault を開いたあとの Normal の背景）
        with self.session() as s:
            s.send("\r", 2.0)  # 起動画面から vault を開く
            s.send(":echo 'x'\r", 0.3)
            self.assertEqual(self.cell_bg(s, "Index"), "ffffff", s.text()[:400])

    def test_theme_chooser_uses_arrow_keys(self) -> None:
        custom = {"base": "dark", "bg": "#101010", "fg": "#eeeeee", "link": "#99ccff", "heading": "#ffcc66", "selection": "#333333", "cursorline": "#1a1a1a"}
        self.settings.write_text(json.dumps({"version": 1, "language": "ja", "appearance": "dark", "theme": {"kind": "builtin"},
                                             "customThemes": {"x": custom, "y": custom},
                                             "appTheme": {"kind": "builtin"}, "appCustomThemes": {"z": custom}}), encoding="utf-8")
        for mode in ("ss3", "csi"):
            with self.subTest(mode=mode):
                with self.session() as s:
                    s.send("s", 0.8)
                    self.goto_item(s, "theme")
                    s.send("\r", 0.6)  # テーマの選択（↑ ↓ で選べる一覧）
                    self.assertIn("カスタム: x", s.text())
                    s.key(mode, "down", 0.3)
                    s.key(mode, "down", 0.3)
                    s.key(mode, "down", 0.3)
                    s.key(mode, "up", 0.3)  # 標準 → x → y → (y のまま) → ↑ で x
                    s.send("\r", 0.8)
                    saved = json.loads(self.settings.read_text(encoding="utf-8"))
                    self.assertEqual(saved["theme"], {"kind": "custom", "name": "x"}, saved)
                    self.assertEqual(saved["appTheme"], {"kind": "builtin"})
                    # アプリ用の選択も同じ（別の設定。Vim のテーマは変わらない）
                    self.goto_item_from(s, "theme", "app_theme", mode)
                    s.send("\r", 0.6)
                    self.assertIn("アプリ", s.text())
                    s.key(mode, "down", 0.3)
                    s.send("\r", 0.8)
                    saved = json.loads(self.settings.read_text(encoding="utf-8"))
                    self.assertEqual(saved["appTheme"], {"kind": "custom", "name": "z"}, saved)
                    self.assertEqual(saved["theme"], {"kind": "custom", "name": "x"}, "アプリのテーマを選んでも Vim のテーマは変わらない")
                self.settings.write_text(json.dumps({"version": 1, "language": "ja", "appearance": "dark", "theme": {"kind": "builtin"},
                                                     "customThemes": {"x": custom, "y": custom},
                                                     "appTheme": {"kind": "builtin"}, "appCustomThemes": {"z": custom}}), encoding="utf-8")

    def goto_item_from(self, s: Session, cur: str, item: str, mode: str) -> None:
        for _ in range(ITEMS.index(item) - ITEMS.index(cur)):
            s.key(mode, "down", 0.15)

    def test_app_theme_starts_white_and_is_separate(self) -> None:
        with self.session() as s:
            s.send("s", 0.8)
            self.goto_item(s, "app_custom")
            s.send("\r", 0.8)
            self.assertIn("アプリ", s.text())
            self.assertEqual(self.cell_bg(s, "植物について"), "fafafa", "アプリ用は白い背景から始まる")
            self.assertEqual(self.cell(s, "ローズマリー").fg, "21538c")
            s.send("\r", 0.4)  # 背景の行
            for ch in "f8f4e8":
                s.send(ch, 0.15)
            s.send("\r", 0.5)
            self.assertEqual(self.cell_bg(s, "植物について"), "f8f4e8")
            s.send("s", 1.0)
        saved = json.loads(self.settings.read_text(encoding="utf-8"))
        self.assertEqual(saved["appTheme"], {"kind": "custom", "name": "my-app-theme"})
        self.assertEqual(saved["appCustomThemes"]["my-app-theme"]["bg"], "#f8f4e8")
        self.assertEqual(saved["theme"], {"kind": "builtin"}, "アプリのテーマを保存しても、通常の Vim のテーマは変わらない")
        self.assertFalse(saved.get("customThemes"))

    def test_palette_and_arrows_in_editor(self) -> None:
        for mode in ("ss3", "csi"):
            with self.subTest(mode=mode):
                with self.session() as s:
                    s.send("s", 0.8)
                    self.goto_item(s, "custom")
                    s.send("\r", 0.8)
                    first = self.cell_bg(s, "植物について")
                    # ↓ ↓ で 3 つ目（リンク）。← → で明るさが変わり、プレビューのリンクの色が変わる
                    s.key(mode, "down", 0.2)
                    s.key(mode, "down", 0.2)
                    before = self.cell(s, "ローズマリー").fg
                    s.key(mode, "right", 0.3)
                    after = self.cell(s, "ローズマリー").fg
                    self.assertNotEqual(before, after, "→ でリンクの色が変わる")
                    self.assertEqual(self.cell_bg(s, "植物について"), first)
                    # Tab でパレットへ。矢印で選ぶとすぐ反映
                    s.send("\t", 0.3)
                    p0 = self.cell(s, "ローズマリー").fg
                    s.key(mode, "right", 0.3)
                    p1 = self.cell(s, "ローズマリー").fg
                    self.assertNotEqual(p0, p1, "パレットの選択がすぐ反映")
                    s.send("\t", 0.3)
                    s.send(ESC, 0.9)  # Esc: 変更があるので確認
                    s.send("y", 0.8)
                    self.assertIn("設定", s.text())


if __name__ == "__main__":
    unittest.main(verbosity=1)
