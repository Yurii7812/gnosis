#!/usr/bin/env python3
"""Real Vim + fzf keyboard tests; all state and notes live in a temporary vault."""
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

from keys_pty import Session, ESC

REPO = Path(__file__).resolve().parent.parent
PLUGINS = Path(os.environ.get('GNOSIS_TEST_PLUGINS', str(Path.home() / '.local/share/gnosis/plugins')))
NEXT = ESC + b'[1;5C'
PREV = ESC + b'[1;5D'
DOWN = ESC + b'[1;5B'
UP = ESC + b'[1;5A'


class SearchScreen(unittest.TestCase):
    def setUp(self):
        if not shutil.which('fzf') or not (PLUGINS / 'fzf/plugin/fzf.vim').is_file():
            self.skipTest('fzf / fzf.vim unavailable')
        self.tmp = tempfile.TemporaryDirectory(prefix='gnosis-search-')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.vault = self.work / 'vault'
        self.home = self.work / 'home'
        self.gh = self.work / 'gnosis-home'
        for p in (self.vault, self.home, self.gh / 'plugins'):
            p.mkdir(parents=True)
        for name in ('fzf', 'fzf.vim'):
            (self.gh / 'plugins' / name).symlink_to(PLUGINS / name)
        self.note('a', 'ハーブガーデンを作ってみたい',
                  'Group:\n[Index](index.md)\n[G](g.md)\n\nTarget body\nNeedle hit here')
        self.note('b', 'Ordinary B', 'SELECT ME')
        self.note('g', 'Group G', '[別名](a.md)\n[unregistered](b.md)', True)
        self.note('index', 'Index', '[ハーブ](a.md)\n[ハーブ](a.md)', True)
        self.out = self.work / 'state.json'
        self.rc = self.work / 'vimrc'
        self.rc.write_text(
            f"let g:gnosis_root = '{self.vault}/'\n"
            "let g:gnosis_skip_interactive_mount=1\nlet g:gnosis_start_screen=0\n"
            "let g:gnosis_autosync=0\nlet g:gnosis_diary_auto=0\nlet g:gnosis_language='en'\n"
            f"source {REPO}/vimrc_gnosis\n"
            "set noswapfile\nset nomore\nset eventignore=VimEnter\n"
            f"edit {self.vault}/b.md\n"
            f"nnoremap <F9> <Cmd>call writefile([json_encode({{'file': expand('%:t'), 'line': line('.'), 'lines': getline(1,'$')}})], '{self.out}')<CR>\n")

    def note(self, stem, title, body, group=False):
        (self.vault / f'{stem}.md').write_text(
            f'---\ntitle: {title}\n' + ('attribute: group\n' if group else '') + f'---\n\n# {title}\n\n{body}\n')

    def session(self):
        return Session(str(self.rc), str(self.home), str(self.gh),
                       env={'GNOSIS_ROOT': str(self.vault), 'GNOSIS_VAULT': str(self.vault)}, cols=140, rows=34)

    def picker_text(self, s):
        # fzf is a popup: ignore the still-visible source buffer and preview.
        return '\n'.join(line.split('│')[1] for line in s.text().splitlines() if '│' in line)

    def dump(self, s):
        s.send(ESC + b'[20~', .3)
        self.assertTrue(self.out.exists(), s.text())
        return json.loads(self.out.read_text())

    def test_modes_keep_query_empty_results_and_cancel(self):
        for entry in ('gs', '\\l'):
            with self.subTest(entry=entry), self.session() as s:
                s.send(entry, 1)
                self.assertIn('All |', s.text())
                self.assertIn('Ordinary B', s.text())
                s.send(NEXT, .5)
                self.assertIn('Groups |', s.text())
                self.assertNotIn('Ordinary B', self.picker_text(s))
                s.send(DOWN, .5)
                self.assertIn('Groups + index names |', s.text())
                self.assertIn('ハーブ', s.text())
                self.assertNotIn('unregistered', self.picker_text(s))
                s.send(NEXT, .5)
                self.assertIn('Notes |', s.text())
                self.assertNotIn('Group G', self.picker_text(s))
                s.send(NEXT, .5)
                self.assertIn('All |', s.text())
                s.send('Ordinary', .5)
                s.send(NEXT, .5)
                self.assertIn('Groups |', s.text())
                self.assertIn('Ordinary', s.text())
                self.assertNotIn('Ordinary B', self.picker_text(s))
                s.send(UP, .5)
                self.assertIn('All |', s.text())
                self.assertIn('Ordinary B', s.text())
                s.send(' no-match', .5)
                s.send(PREV, .5)
                self.assertIn('Notes |', s.text())
                self.assertIn('Ordinary no-match', s.text())
                s.send(ESC, .7)
                state = self.dump(s)
                self.assertEqual(state['file'], 'b.md')
                self.assertNotIn('Related:', state['lines'])
                self.assertEqual(state['lines'][-1], 'SELECT ME')

    def test_alias_opens_target_and_link_uses_alias(self):
        for entry in ('gs', '\\l'):
            with self.subTest(entry=entry), self.session() as s:
                s.send(entry, 1)
                s.send(NEXT, .4)
                s.send(NEXT, .4)
                s.send('ハーブ', .5)
                self.assertIn('index name', s.text())
                s.send('\r', .8)
                if entry == '\\l':
                    # This is the real, deferred link-placement menu.
                    self.assertIn('r=Related', s.text())
                    s.send('\r', .4)
                state = self.dump(s)
                if entry == 'gs':
                    self.assertEqual(state['file'], 'a.md')
                else:
                    self.assertEqual(state['file'], 'b.md')
                    self.assertIn('[ハーブ](a.md)', state['lines'])

    def test_link_placement_survives_idle(self):
        self.note('g', 'Group G', '[別名](a.md)', True)
        with self.session() as s:
            s.send(":set updatetime=200\r", .2)
            s.send('\\l', 1)
            s.send('Group G', .5)
            s.send('\r', .8)
            self.assertIn('g=', s.text())
            s.wait(2)
            s.send('g', .3)
            s.send('\r', .5)
            state = self.dump(s)
            self.assertIn('[Group G](g.md)', state['lines'])
            group = (self.vault / 'g.md').read_text().splitlines()
            added = group.index('[Ordinary B](b.md)')
            self.assertEqual(group[added - 1], '[別名](a.md)')

    def test_visual_alias_uses_original_selection(self):
        with self.session() as s:
            s.send(":call cursor(line('$'), 1)\r", .3)
            s.send('v$\\l', 1)
            s.send(NEXT, .4)
            s.send(NEXT, .4)
            s.send('別名', .5)
            s.send('\r', .8)
            state = self.dump(s)
            self.assertEqual(state['file'], 'b.md')
            self.assertEqual(state['lines'][-1], '[SELECT ME](a.md)')

    def test_name_only_alias_and_plain_arrow_navigation(self):
        with self.session() as s:
            s.send('gs', 1)
            s.send(NEXT, .3)
            s.send(NEXT, .3)
            s.send('別名', .4)
            s.send('\r', .7)
            self.assertEqual(self.dump(s)['file'], 'a.md')
        opened = []
        for move in (False, True):
            with self.session() as s:
                s.send('gs', 1)
                if move:
                    s.key('csi', 'up', .3)
                self.assertIn('All |', s.text())
                s.send('\r', .7)
                opened.append(self.dump(s)['file'])
        self.assertNotEqual(opened[0], opened[1], 'plain Up must still move the selection')

    def test_visual_cancel_preserves_selection(self):
        before = (self.vault / 'b.md').read_bytes()
        with self.session() as s:
            s.send(":call cursor(line('$'), 1)\r", .3)
            s.send('v$\\l', 1)
            s.send(NEXT, .3)
            s.send('absent', .4)
            s.send(ESC, .7)
            self.assertEqual(self.dump(s)['lines'][-1], 'SELECT ME')
        self.assertEqual((self.vault / 'b.md').read_bytes(), before)

    def test_fulltext_hit_line_and_plain_arrows(self):
        with self.session() as s:
            s.send('gs', 1)
            s.send('Needle', .5)
            s.key('csi', 'up', .2)
            self.assertIn('All |', s.text())
            s.send('\r', .7)
            state = self.dump(s)
            self.assertEqual(state['file'], 'a.md')
            self.assertEqual(state['lines'][state['line']-1], 'Needle hit here')


if __name__ == '__main__':
    unittest.main()
