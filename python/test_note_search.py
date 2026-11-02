#!/usr/bin/env python3
"""Regression tests for the unified gs / \l search ranking and display."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import note_search as ns


class UnifiedSearch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.note('a', 'ハーブガーデンを作ってみたい',
                  'Group:\n[Index](index.md)\n[G](g.md)\n[Topic](topic.md)\n\nFirst line\nNeedle in body')
        self.note('b', 'Ordinary B', '[incidental](a.md)')
        self.note('g', 'Group G', '[別の呼び名](a.md)', 'attribute: group')
        self.note('index', 'Index',
                  '[ハーブ](a.md)\n[missing](missing.md)\n![image](b.md)\n'
                  '`[incidental code](b.md)`\n```\n[fenced](b.md)\n```\n'
                  'Related:\n[relation](b.md)')
        self.note('topic', 'Topic Index', '[topic alias](a.md)', '属性: 小グループ')

    def note(self, name, title, body, attr=''):
        (self.root / f'{name}.md').write_text(
            f'---\ntitle: {title}\n{attr}\n---\n\n# {title}\n\n{body}\n',
            encoding='utf-8')

    def rows(self, query):
        return ns.search_rows(str(self.root), query)

    def test_index_entries_have_registered_membership(self):
        entries = list(ns.index_entries(dict(ns.load_notes(str(self.root)))))
        self.assertEqual({name for _, name, _ in entries},
                         {'ハーブ', '別の呼び名', 'topic alias'})
        self.assertTrue(all(Path(path).name == 'a.md' for path, _, _ in entries))

    def test_index_entry_label_only_and_destination_title_for_body_hit(self):
        rows = self.rows('別の呼び名')
        self.assertEqual([(r[4], r[7]) for r in rows], [('別の呼び名', 'index')])
        self.assertEqual(rows[0][5], 0)
        body_rows = self.rows('Needle body')
        self.assertEqual([(r[4], r[7]) for r in body_rows],
                         [('ハーブガーデンを作ってみたい', 'note')])
        self.assertEqual(Path(body_rows[0][3]).name, 'a.md')
        self.assertEqual(body_rows[0][5],
                         (self.root / 'a.md').read_text().splitlines().index('Needle in body') + 1)

    def test_global_index_alias_precedes_other_alias_group_and_note(self):
        self.note('g', 'ハーブグループ', '[ハーブ栽培](a.md)', 'attribute: group')
        rows = self.rows('ハーブ')
        self.assertEqual([(r[4], r[7]) for r in rows],
                         [('ハーブ', 'root-index'), ('ハーブ栽培', 'index'),
                          ('ハーブグループ', 'group'), ('ハーブガーデンを作ってみたい', 'note')])

    def test_exact_index_before_folgezettel_index_even_if_alias_is_first_tier(self):
        # Global alias is a substring match. The actual Index title matches exactly.
        p = self.root / 'index.md'
        p.write_text(p.read_text(encoding='utf-8').replace(
            '[ハーブ](a.md)', '[Index-extra](a.md)\n[ハーブ](a.md)'), encoding='utf-8')
        self.note('folger', 'Folgezettel-Index', 'Generated index note')
        rows = self.rows('index')
        self.assertEqual((Path(rows[0][3]).name, rows[0][4], rows[0][7]),
                         ('index.md', 'Index', 'group'))
        self.assertTrue(any(r[4] == 'Folgezettel-Index' for r in rows))
        self.assertTrue(any(r[4] == 'Index-extra' for r in rows))
        self.assertEqual(self.rows('INDEX')[0][4], 'Index')
        self.assertEqual(self.rows('ｉｎｄｅｘ')[0][4], 'Index')

    def test_note_title_before_note_body_and_group_body_not_searched(self):
        self.note('nt', '星空観察', 'unrelated text')
        self.note('nb', '日記', '星空観察をした')
        self.note('ng', 'Group does not match', '星空観察', 'attribute: group')
        got = [(r[4], r[7]) for r in self.rows('星空観察')]
        self.assertEqual(got, [('星空観察', 'note'), ('日記', 'note')])

    def test_no_index_membership_from_incidental_context_or_code(self):
        self.note('a', 'A', 'Context:\n[Index](index.md)\n\n'
                  'BranchGroup:\n[G](g.md)\n\n```\nGroup:\n[Topic](topic.md)\n```')
        self.assertEqual(list(ns.index_entries(dict(ns.load_notes(str(self.root))))), [])

    def test_duplicate_alias_collapses_but_distinct_aliases_remain(self):
        self.note('second', 'Second index',
                  '[ハーブ](a.md)\n[園芸](a.md)', 'attribute: group')
        a = self.root / 'a.md'
        a.write_text(a.read_text(encoding='utf-8').replace(
            'Group:\n', 'Group:\n[Second](second.md)\n', 1), encoding='utf-8')
        rows = self.rows('')
        names = [r[4] for r in rows if Path(r[3]).name == 'a.md']
        self.assertEqual(names.count('ハーブ'), 2)  # Different kind: root vs topic alias
        self.assertIn('園芸', names)
        self.assertIn('別の呼び名', names)

    def test_registered_group_aliases_only(self):
        self.note('loose', 'Loose group', '[unregistered](a.md)', 'attribute: group')
        self.note('registered', 'Registered group', '[registered alias](b.md)', 'attribute: group')
        self.note('b', 'Ordinary B', 'Group:\n[Registered](registered.md)\n\nBody')
        entries = list(ns.index_entries(dict(ns.load_notes(str(self.root)))))
        self.assertNotIn('unregistered', {name for _, name, _ in entries})
        self.assertIn('registered alias', {name for _, name, _ in entries})

    def test_cli_labels_no_switch_modes(self):
        def run(*args):
            return subprocess.check_output(
                [sys.executable, ns.__file__, '--lang', 'ja', *args], text=True)
        self.assertIn('\tIndexの索引', run(str(self.root), 'ハーブ'))
        self.assertIn('\t索引', run(str(self.root), '別の呼び名'))
        self.assertIn('\tグループ', run(str(self.root), 'Index'))
        self.assertIn('\tノート', run(str(self.root), 'Needle'))
        self.assertEqual(run(str(self.root), 'absent-query'), '')
        self.assertIn('index.md', run(str(self.root)))

    def test_only_link_alias_and_title_or_body(self):
        only = {str((self.root / 'b.md').resolve()): 'Local name'}
        rows = ns.search_rows(str(self.root), 'Local name', only=only)
        self.assertEqual(len(rows), 1)
        self.assertEqual((Path(rows[0][3]).name, rows[0][4], rows[0][5]),
                         ('b.md', 'Local name', 0))

    def test_search_operators(self):
        self.assertIn('a.md', [Path(r[3]).name for r in self.rows('ハーブ -別')])
        self.assertTrue(self.rows('ハーブ | 別の呼び名'))
        self.assertEqual(self.rows('unlikely literal'), [])


if __name__ == '__main__':
    unittest.main()
