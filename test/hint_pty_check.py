"""曼荼羅・Folgezettel ビューの上のヒント行（K でオン・オフ）と m のメニューを、実 Vim で確かめる。"""
import tempfile
import unittest
from pathlib import Path
from keys_pty import Session, ESC

REPO = Path(__file__).resolve().parent.parent
NEXT = ESC + b'[1;5C'


class HintMandala(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='gnosis-hint-pty-')
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.vault, self.home, self.gh = root / 'v', root / 'home', root / 'gh'
        for p in (self.vault, self.home, self.gh):
            p.mkdir()
        (self.vault / 'index.md').write_text('---\ntime: 2026-01-01 00:00:00\nattribute: group\n---\n\n# Index\n\n[Alpha](a.md)\n')
        (self.vault / 'a.md').write_text('---\ntime: 2026-01-01 00:00:01\nfolgezettel: "1"\n---\n\n# Alpha\n\nbody\n')
        self.rc = root / 'vimrc'
        self.rc.write_text(
            f"let g:gnosis_root='{self.vault}/'\n"
            "let g:gnosis_skip_interactive_mount=1\nlet g:gnosis_start_screen=0\n"
            "let g:gnosis_autosync=0\nlet g:gnosis_autosave=0\nlet g:gnosis_diary_auto=0\n"
            "let g:gnosis_mview_restore=0\nlet g:gnosis_language='en'\nlet g:gnosis_hint=0\n"
            f"source {REPO}/vimrc_gnosis\nruntime plugin/gnosis.vim\nset eventignore=VimEnter\n"
            f"edit {self.vault}/a.md\nset nomore\n")

    def session(self):
        return Session(str(self.rc), str(self.home), str(self.gh), cols=130, rows=40)

    def test_mandala_hint_toggle_menu_and_highlight_key(self):
        with self.session() as s:
            s.send(' ', .8)
            self.assertNotIn('m:menu', s.text())
            s.send('K', .6)
            top = s.text().splitlines()[0]
            self.assertIn('[a:', top)          # いまのモード（全体）が [ ] で出る
            self.assertIn('m:menu', top)
            self.assertIn('3×3', s.text().splitlines()[1])  # 盤面は 1 行下がる（窓からはみ出さない）
            s.send('m', .7)
            self.assertIn('Mandala', s.text())  # メニュー
            s.send('3\r', .8)                    # 3 番目 = 親と子だけ
            self.assertIn('[d:', s.text().splitlines()[0])
            s.send('H', .6)                      # ハイライトの入力欄（m はメニューになった）
            self.assertTrue('highlight' in s.text().lower() or 'ハイライト' in s.text())
            s.send(ESC, .4)
            s.send('K', .6)
            self.assertNotIn('m:menu', s.text())

    def test_folgezettel_hint_and_menu(self):
        with self.session() as s:
            s.send(' ', .8)
            s.send(NEXT, .7)
            self.assertIn('FOLGEZETTEL', s.text())
            s.send('K', .6)
            top = s.text().splitlines()[0]
            self.assertIn('l:', top)
            self.assertIn('m:menu', top)
            s.send('m', .7)
            self.assertIn('Search', s.text())
            s.send('2\r', .9)                    # 2 番目 = 検索 → 検索語の入力
            s.send(ESC, .5)                      # 何も入れずやめたら Folgezettel に戻る
            self.assertIn('FOLGEZETTEL', s.text())


if __name__ == '__main__':
    unittest.main()
