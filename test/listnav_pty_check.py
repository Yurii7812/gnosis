"""実Vimで3ビュー切替・ポップアップなし検索・右のプレビュー・戻るを検証する。"""
import json
from pathlib import Path
import tempfile
import unittest
from keys_pty import Session, ESC

REPO = Path(__file__).resolve().parent.parent
NEXT = ESC + b'[1;5C'
PREV = ESC + b'[1;5D'


class ListView(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='gnosis-list-pty-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.vault = self.root / 'v'
        self.home = self.root / 'home'
        self.gh = self.root / 'gh'
        for p in (self.vault, self.home, self.gh):
            p.mkdir()
        self.note('index', 'Index', '', '[Alpha](a.md)', True)
        self.note('a', 'Alpha', '1', 'Group:\n[Group](g.md)\n\nChildBranch:\n[Beta](b.md)\n\nOriginal body\nOriginal end')
        self.note('b', 'Beta', '1a', 'ParentBranch:\n[Alpha](a.md)\n\nNeedle body')
        self.note('g', 'Group', '2', '[Unique alias](a.md)', True)
        self.out = self.root / 'state.json'
        self.rc = self.root / 'vimrc'
        self.rc.write_text(
            f"let g:gnosis_root='{self.vault}/'\n"
            "let g:gnosis_skip_interactive_mount=1\nlet g:gnosis_start_screen=0\n"
            "let g:gnosis_autosync=0\nlet g:gnosis_autosave=0\nlet g:gnosis_diary_auto=0\n"
            "let g:gnosis_mview_restore=0\nlet g:gnosis_language='en'\nlet g:gnosis_hint=0\n"
            f"source {REPO}/vimrc_gnosis\nruntime plugin/gnosis.vim\nset eventignore=VimEnter\n"
            f"edit {self.vault}/a.md\n"
            "set nomore\n"
            f"nnoremap <F9> <Cmd>call writefile([json_encode({{'view':gnosis#mview#view(), 'file':bufname(winbufnr(gnosis#mview#note_win())), 'center':gnosis#mview#state().center, 'popups':popup_list()}})], '{self.out}')<CR>\n")

    def note(self, stem, title, number, body, group=False):
        (self.vault / f'{stem}.md').write_text(
            f'---\ntime: 2026-01-01 00:00:00\nfolgezettel: "{number}"\n' +
            ('attribute: group\n' if group else '') + f'---\n\n# {title}\n\n{body}\n')

    def session(self):
        return Session(str(self.rc), str(self.home), str(self.gh), cols=130, rows=35)

    def dump(self, s):
        s.send(ESC + b'[20~', .25)
        self.assertTrue(self.out.exists(), s.text())
        return json.loads(self.out.read_text())

    def open_list(self, s):
        s.send(' ', .7)
        s.send(NEXT, .5)
        self.assertIn('FOLGEZETTEL', s.text())
        s.send('l', .5)
        self.assertIn('FOLGEZETTEL / ', s.text())

    def test_hint_line_toggle_and_mode_menu(self):
        with self.session() as s:
            self.open_list(s)
            self.assertNotIn('m:', s.text())  # 既定はこの試験ではオフ
            s.send('K', .5)
            top = s.text().splitlines()[0]
            self.assertIn('[l:', top)  # 今のモードが [ ] で出る
            self.assertIn('m:', top)
            s.send('K', .5)
            self.assertNotIn('[l:', s.text().splitlines()[0])
            s.send('K', .4)
            s.send('m', .6)  # メニュー。3 = 類似
            self.assertIn('Similar', s.text())
            s.send('3\r', .8)
            self.assertIn('[r:', s.text().splitlines()[0])
            s.send('m', .5)
            s.send(ESC, .4)  # やめても何も変わらない
            self.assertIn('[r:', s.text().splitlines()[0])
            self.assertEqual(self.dump(s)['view'], 'list')

    def test_cycles_both_directions_and_plain_list_search(self):
        with self.session() as s:
            self.open_list(s)
            s.send(NEXT, .3)
            self.assertEqual(self.dump(s)['view'], 'mandala')
            s.send(PREV, .3)
            self.assertEqual(self.dump(s)['view'], 'fz')
            s.send('l', .5)
            self.assertEqual(self.dump(s)['view'], 'list')
            s.send('sNeedle\r', 1)
            self.assertIn('Beta', s.text())
            state = self.dump(s)
            self.assertEqual(state['view'], 'list')
            self.assertEqual(state['popups'], [])
            s.send('\r', .6)
            self.assertIn('b.md', self.dump(s)['file'])
            s.send(' ', .3)
            s.send('sGroup\r', .8)  # 別のノートをプレビューしてから o で、Enter で開いた b.md へ戻る
            s.send('G', .6)
            s.send('o', .4)
            self.assertIn('b.md', self.dump(s)['file'])

    def test_filter_preserves_preview_and_alias_search_preview_returns(self):
        with self.session() as s:
            self.open_list(s)
            before = self.dump(s)
            s.send('b', .3)
            self.assertEqual(self.dump(s)['file'], before['file'])
            s.send(b'\x7f', .3)
            s.send('sUnique alias\r', 1)
            s.send('G', .5)
            state = self.dump(s)
            self.assertEqual(state['center'], 'a.md')
            self.assertIn('g.md', state['file'])
            s.send('o', .3)
            self.assertIn('a.md', self.dump(s)['file'])

    def test_enter_reanchors_links_and_q_closes_despite_history(self):
        with self.session() as s:
            self.open_list(s)
            s.send('r', .6)
            s.send('l', .6)
            s.send('j', .3)
            s.send('\r', .8)
            self.assertEqual(self.dump(s)['center'], 'b.md')
            self.assertEqual(self.dump(s)['view'], 'list')  # Enter でも右のノートへカーソルは移らない
            left = '\n'.join(l.split('|')[0] for l in s.text().splitlines())
            self.assertIn('[Parent] Alpha', left)
            self.assertNotIn('[Child] Beta', left)
            s.send('r', .6)
            left = '\n'.join(l.split('|')[0] for l in s.text().splitlines())
            self.assertIn('Alpha', left)
            self.assertNotIn('depth', left.splitlines()[1])
            s.send('q', .6)
            self.assertNotIn('FOLGEZETTEL / ', s.text())

    def test_folgezettel_search_highlight_and_cancel(self):
        with self.session() as s:
            s.send(' ', .7)
            s.send(NEXT, .5)
            s.send('s', .5)
            s.send(ESC, .5)  # 検索語を入れずにやめたら Folgezettel に戻る
            self.assertEqual(self.dump(s)['view'], 'fz')
            s.send('sNeedle\r', .8)
            self.assertIn('Beta', s.text())
            s.send('HBeta\r', .6)
            self.assertIn('H: Beta', s.text())
            s.send('f', .5)
            self.assertEqual(self.dump(s)['view'], 'fz')


if __name__ == '__main__':
    unittest.main()
