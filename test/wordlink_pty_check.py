"""\\K（単語のリンク化）を実 Vim で確かめる: チェックボックスのポップアップ・Space で外す・Enter で決定・u で戻る。"""
import tempfile
import unittest
from pathlib import Path
from keys_pty import Session, ESC

REPO = Path(__file__).resolve().parent.parent


class WordLink(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='gnosis-wordlink-pty-')
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.vault, self.home, self.gh = root / 'v', root / 'home', root / 'gh'
        for p in (self.vault, self.home, self.gh):
            p.mkdir()
        for name, title in (('apple.md', 'apple'), ('root.md', 'etymology')):
            (self.vault / name).write_text(f'---\ntime: 2026-01-01 00:00:00\n---\n\n# {title}\n\nbody\n')
        self.note = self.vault / 'memo.md'
        self.note.write_text('---\ntime: 2026-01-02 00:00:00\n---\n\n# memo\n\nApple and etymology here.\n')
        self.rc = root / 'vimrc'
        self.rc.write_text(
            f"let g:gnosis_root='{self.vault}/'\n"
            "let g:gnosis_skip_interactive_mount=1\nlet g:gnosis_start_screen=0\n"
            "let g:gnosis_autosync=0\nlet g:gnosis_autosave=0\nlet g:gnosis_diary_auto=0\n"
            "let g:gnosis_mview_restore=0\nlet g:gnosis_language='en'\nlet g:gnosis_hint=0\n"
            f"source {REPO}/vimrc_gnosis\nruntime plugin/gnosis.vim\nset eventignore=VimEnter\n"
            f"edit {self.note}\nset nomore\n")

    def session(self):
        return Session(str(self.rc), str(self.home), str(self.gh), cols=110, rows=30)

    def test_popup_toggle_and_decide(self):
        with self.session() as s:
            s.send('\\K', .8)
            text = s.text()
            self.assertIn('[x] apple', text)
            self.assertIn('[x] etymology', text)
            s.send(' ', .4)                     # 1 つ目（apple）のチェックを外す
            self.assertIn('[ ] apple', s.text())
            s.send('\r', .8)
            s.send(':w\r', .6)
            body = self.note.read_text()
            self.assertIn('[etymology](root.md)', body)
            self.assertNotIn('](apple.md)', body)
            self.assertIn('Apple and', body)
            s.send('u', .4)                     # 取り消せる
            s.send(':w\r', .6)
            self.assertNotIn('](root.md)', self.note.read_text())

    def test_escape_changes_nothing(self):
        with self.session() as s:
            before = self.note.read_text()
            s.send('\\K', .8)
            s.send(ESC, .5)
            s.send(':w\r', .5)
            self.assertEqual(self.note.read_text(), before)


if __name__ == '__main__':
    unittest.main()
