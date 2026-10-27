"""リンクの隠し表示・挿入カーソル・元の Markdown を実際の端末で検証する。"""
from pathlib import Path
import tempfile
import unittest

try:
    from keys_pty import Session, ESC
    from wcwidth import wcswidth
except ModuleNotFoundError as exc:
    if exc.name != "pyte":
        raise
    print("link_source_pty skipped (pyte not installed)")
    raise SystemExit(0)

REPO = Path(__file__).resolve().parent.parent


class LinkSource(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="gnosis-source-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.vault = self.root / "v"
        self.vault.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.note = self.vault / "a.md"
        self.note.write_text("---\ntime: 2026-01-01 00:00:00\n---\n\n# A\n\n"
                             "- [ ] [gnosisの修正6](261020131029.md)\n", encoding="utf-8")
        self.rc = self.root / "vimrc"
        self.rc.write_text(
            "set nocompatible\n"
            f"let g:gnosis_root = '{self.vault}/'\n"
            "let g:gnosis_skip_interactive_mount=1\n"
            "let g:gnosis_start_screen=0\n"
            "let g:gnosis_autosync=0\nlet g:gnosis_autosave=0\n"
            "let g:gnosis_diary_auto=0\n"
            f"set runtimepath^={REPO}\nset runtimepath+={REPO}/after\n"
            "filetype plugin on\nsyntax on\nruntime plugin/gnosis.vim\n"
            "set eventignore=VimEnter\nset nonumber norelativenumber\nset ttimeout ttimeoutlen=30\n", encoding="utf-8")

    def session(self):
        return Session(str(self.rc), str(self.home), args=[str(self.note)])

    def assert_cursor_after_text(self, s):
        text = s.line(s.screen.cursor.y)
        self.assertIn("- [ ]", text, s.text())
        self.assertEqual(s.screen.cursor.x, wcswidth(text.rstrip()), s.text())

    def test_append_cursor_and_markdown_preserved(self):
        with self.session() as s:
            for label, target, key in (("gnosisの修正6", "261020131029.md", "A"),
                                       ("Short", "a" * 60 + ".md", "$a")):
                with self.subTest(label=label, key=key):
                    original = f"- [ ] [{label}]({target})"
                    s.send(':call search("^- ")\r', .1)
                    s.send(f":call setline(line('.'), '{original}')\r", .1)
                    s.send(key, .2)
                    self.assertNotIn(target, s.text())
                    self.assert_cursor_after_text(s)
                    s.send(" 追記", .2)
                    self.assert_cursor_after_text(s)
                    s.send(ESC, .1)
                    s.send(":w\r", .2)
                    self.assertIn(original + " 追記", self.note.read_text(encoding="utf-8"))

    def test_explicit_source_mode_and_reapply(self):
        with self.session() as s:
            s.send(':call search("^- ")\r', .1)
            s.send(":GnosisLinkSource on\r", .2)
            self.assertIn("261020131029.md", s.text())
            s.send(":set filetype=markdown\r", .2)
            self.assertIn("261020131029.md", s.text())
            s.send("A", .2)
            self.assert_cursor_after_text(s)
            s.send(ESC, .1)
            s.send(":GnosisLinkSource off\r", .2)
            self.assertNotIn("261020131029.md", s.text())
            s.send("A", .2)
            self.assert_cursor_after_text(s)
            s.send(ESC, .1)

    def test_insert_source_setting_is_respected(self):
        with self.session() as s:
            s.send(':call search("^- ")\r', .1)
            s.send(":call gnosis#settings#set('linkEditInsert', v:true)\r", .2)
            s.send("A", .2)
            self.assertIn("261020131029.md", s.text())
            self.assert_cursor_after_text(s)
            s.send(ESC, .1)
            self.assertNotIn("261020131029.md", s.text())


if __name__ == "__main__":
    unittest.main()
