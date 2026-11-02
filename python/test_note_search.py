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

    def test_folgezettel_id_in_front_matter_is_searchable(self):
        (self.root / 'fz1.md').write_text(
            '---\ntime: 2026-10-20 14:11:56\nfolgezettel: "37a2l1a1a4b"\n---\n\n'
            '# Plain one\n\nnothing here\n', encoding='utf-8')
        (self.root / 'fz2.md').write_text(
            '---\nfolgezettel: "37a2"\n---\n\n# Plain two\n\nnothing\n', encoding='utf-8')
        titles = {r[4] for r in self.rows('folgezettel 37')}
        self.assertIn('Plain one', titles)
        self.assertIn('Plain two', titles)

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

    def test_cli_square_markers_no_visible_labels(self):
        def run(*args):
            return subprocess.check_output(
                [sys.executable, ns.__file__, '--lang', 'ja', *args], text=True)
        self.assertIn('\troot-index\t' + ns.colored_marker('root-index'), run(str(self.root), 'ハーブ'))
        self.assertIn('\tindex\t' + ns.colored_marker('index'), run(str(self.root), '別の呼び名'))
        self.assertIn('\tgroup\t' + ns.colored_marker('group'), run(str(self.root), 'Index'))
        self.assertIn('\tnote\t' + ns.colored_marker('note'), run(str(self.root), 'Needle'))
        self.assertEqual(run(str(self.root), 'absent-query'), '')
        self.assertIn('index.md', run(str(self.root)))

    def test_search_kind_colors_are_distinct_and_match_text_unchanged(self):
        import re
        colors = [ns.KIND_ANSI[k] for k in ('root-index', 'index', 'group', 'note')]
        self.assertEqual(len(set(colors)), 4)
        for kind in ('root-index', 'index', 'group', 'note'):
            styled = ns.colored_kind(kind, 'ja')
            self.assertTrue(styled.startswith(ns.KIND_ANSI[kind]))
            self.assertTrue(styled.endswith(ns.RESET))
            self.assertEqual(re.sub(r'\x1b\[[0-9;]*m', '', styled),
                             '[' + ns.KIND_LABELS['ja'][kind] + ']')
        out = subprocess.check_output(
            [sys.executable, ns.__file__, '--lang', 'ja', str(self.root), 'ハーブ'], text=True)
        self.assertIn('\troot-index\t' + ns.colored_marker('root-index'), out)
        self.assertIn('\tnote\t' + ns.colored_marker('note'), out)

    def test_colored_marker_is_leftmost_display_field(self):
        import re
        for kind in ('root-index', 'index', 'group', 'note'):
            marker = ns.colored_marker(kind)
            self.assertTrue(marker.startswith(ns.KIND_ANSI[kind]))
            self.assertEqual(re.sub(r'\x1b\[[0-9;]*m', '', marker), '■')
        result = subprocess.check_output(
            [sys.executable, ns.__file__, '--lang', 'ja', str(self.root), 'ハーブ'], text=True)
        rows = result.splitlines()
        self.assertTrue(all(len(row.split('\t')) == 5 for row in rows))
        self.assertTrue(any(row.split('\t')[-1] == ns.colored_marker('root-index') for row in rows))
        self.assertTrue(all('[' + ns.KIND_LABELS['ja'][kind] + ']' not in row
                            for row in rows for kind in ns.KIND_ANSI))

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
