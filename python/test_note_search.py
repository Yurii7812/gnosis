#!/usr/bin/env python3
"""Search modes use real destination notes, not the index holding their aliases."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import note_search as ns


class SearchModes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.note('a', 'ハーブガーデンを作ってみたい',
                  'Group:\n[Index](index.md)\n[G](g.md)\n[Topic](topic.md)\n\nFirst line\nNeedle in body')
        self.note('b', 'Ordinary B', '[incidental](a.md)')
        self.note('g', 'Group G', '[別の呼び名](a.md)', 'attribute: group')
        self.note('index', 'Global Index', '[ハーブ](a.md)\n[missing](missing.md)\n![image](b.md)\n'
                  '`[inline code](b.md)`\n```\n[fenced](b.md)\n```\n'
                  'Related:\n[relation](b.md)')
        self.note('topic', 'Topic Index', '[topic alias](a.md)', '属性: 小グループ')

    def note(self, name, title, body, attr=''):
        (self.root / f'{name}.md').write_text(
            f'---\ntitle: {title}\n{attr}\n---\n\n# {title}\n\n{body}\n')

    def paths(self, mode):
        return {Path(row[3]).stem for row in ns.search_rows(str(self.root), '', mode)}

    def test_modes(self):
        self.assertEqual(self.paths('all'), {'a', 'b', 'g', 'index', 'topic'})
        self.assertEqual(self.paths('no-index'), {'a', 'b', 'g', 'index', 'topic'})
        self.assertTrue({'a', 'g', 'index', 'topic'} <= self.paths('index'))

    def test_all_includes_aliases_and_no_index_keeps_groups(self):
        for mode in ('all', 'index'):
            rows = ns.search_rows(str(self.root), '別の呼び名', mode)
            self.assertTrue(any(Path(r[3]).name == 'a.md' and r[4] == '別の呼び名'
                                and r[6] for r in rows))
        rows = ns.search_rows(str(self.root), '', 'no-index')
        self.assertTrue(all(not r[6] for r in rows))
        self.assertFalse(any(Path(r[3]).name == 'a.md' for r in
                             ns.search_rows(str(self.root), '別の呼び名', 'no-index')))
        self.assertTrue(any(Path(r[3]).name == 'g.md' for r in rows))
        self.assertTrue(ns.search_rows(str(self.root), 'Needle body', 'no-index'))
        for lang in ('ja', 'en'):
            self.assertEqual(len({ns.mode_header(mode, lang) for mode in ns.MODES}), 3)

    def test_index_entries(self):
        entries = list(ns.index_entries(dict(ns.load_notes(str(self.root)))))
        self.assertEqual({name for _, name, _ in entries}, {'ハーブ', '別の呼び名', 'topic alias'})
        self.assertTrue(all(Path(path).name == 'a.md' for path, _, _ in entries))

    def test_name_only_hit_has_no_destination_hit_line(self):
        rows = [r for r in ns.search_rows(str(self.root), '別の呼び名', 'index')
                if Path(r[3]).name == 'a.md']
        self.assertEqual(len(rows), 1)
        self.assertEqual((Path(rows[0][3]).name, rows[0][4], rows[0][5]),
                         ('a.md', '別の呼び名', 0))

    def test_distinct_aliases_same_target_and_duplicate_pair(self):
        self.note('second', 'Second index', '[ハーブ](a.md)\n[園芸](a.md)', 'attribute: group')
        a = self.root / 'a.md'
        a.write_text(a.read_text().replace('Group:\n', 'Group:\n[Second](second.md)\n', 1))
        rows = [r for r in ns.search_rows(str(self.root), '', 'index') if Path(r[3]).name == 'a.md']
        names = [r[4] for r in rows]
        self.assertEqual(names.count('ハーブ'), 1)
        self.assertIn('園芸', names)
        self.assertIn('別の呼び名', names)

    def test_index_names_require_membership_of_the_source_group(self):
        self.note('loose', 'Loose group', '[unregistered](a.md)', 'attribute: group')
        self.note('registered', 'Registered group', '[registered alias](b.md)', 'attribute: group')
        self.note('b', 'Ordinary B', 'Group:\n[Registered](registered.md)\n\nBody')
        entries = list(ns.index_entries(dict(ns.load_notes(str(self.root)))))
        self.assertNotIn('unregistered', {name for _, name, _ in entries})
        self.assertIn('registered alias', {name for _, name, _ in entries})
        self.assertIn('loose', self.paths('index'), 'group candidates remain available')

    def test_context_branch_and_code_do_not_count_as_membership(self):
        self.note('a', 'A', 'Context:\n[Index](index.md)\n\n'
                  'BranchGroup:\n[G](g.md)\n\n```\nGroup:\n[Topic](topic.md)\n```')
        self.assertEqual(list(ns.index_entries(dict(ns.load_notes(str(self.root))))), [])

    def test_legacy_group_membership(self):
        self.note('a', 'A', 'Body\n\n### Group\n[Index](index.md)')
        entries = list(ns.index_entries(dict(ns.load_notes(str(self.root)))))
        self.assertEqual({name for _, name, _ in entries}, {'ハーブ'})

    def test_regular_body_hit_and_and_search(self):
        rows = ns.search_rows(str(self.root), 'Needle body', 'all')
        self.assertEqual({Path(row[3]).name for row in rows}, {'a.md'})
        self.assertEqual({row[4] for row in rows},
                         {'ハーブガーデンを作ってみたい', 'ハーブ', '別の呼び名', 'topic alias'})
        text = (self.root / 'a.md').read_text().splitlines()
        self.assertTrue(all(row[5] == text.index('Needle in body') + 1 for row in rows))
        self.assertEqual(ns.search_rows(str(self.root), 'Needle absent', 'all'), [])

    def test_cli_mode_state_and_empty_results(self):
        state = self.root / 'search-mode'
        state.write_text('all')
        def run(*args):
            return subprocess.check_output([sys.executable, ns.__file__,
                '--mode-file', str(state), *args], text=True)
        self.assertTrue(run('--cycle', 'next').startswith('Index names + groups |'))
        self.assertEqual(state.read_text(), 'index')
        self.assertEqual(run(str(self.root), 'definitely absent'), '')
        self.assertTrue(run('--cycle', 'previous').startswith('All |'))
        self.assertIn('b.md', run(str(self.root), 'Ordinary B'))
        self.assertTrue(run('--cycle', 'previous').startswith('Without index names |'))
        self.assertIn('index.md', run(str(self.root)))
        self.assertTrue(run('--cycle', 'previous').startswith('Index names + groups |'))
        self.assertTrue(run('--cycle', 'previous').startswith('All |'))

    def test_only_keeps_existing_link_name_search(self):
        only = {str((self.root / 'b.md').resolve()): 'Local name'}
        rows = ns.search_rows(str(self.root), 'Local name', only=only)
        self.assertEqual(len(rows), 1)
        self.assertEqual((Path(rows[0][3]).name, rows[0][4], rows[0][5]), ('b.md', 'Local name', 0))


if __name__ == '__main__':
    unittest.main()
