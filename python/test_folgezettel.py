"""Regression coverage for allocation through real sync and Branch operations."""
import tempfile
import unittest
from pathlib import Path

import branch_ops as bo
import folgezettel as fz
import note_format_v2 as nf


class FolgezettelTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def note(self, name, ident='', body=''):
        p = self.root / (name + '.md')
        text = f'---\ntitle: {name}\n---\n\n# {name}\n\n{body}\n'
        p.write_text(fz.set_value(text, ident) if ident else text)
        return p

    def ident(self, p):
        return fz.value(p.read_text())

    def test_index_sync_and_orphan(self):
        self.note('index', body='[five](five.md)\n[new](new.md)')
        self.note('five', '5')
        new = self.note('new')
        orphan = self.note('orphan')
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(new), '6')
        self.assertEqual(self.ident(orphan), '')
        before = {p: p.read_text() for p in self.root.glob('*.md')}
        nf.simple_sync(self.root)
        self.assertEqual(before, {p: p.read_text() for p in before})

    def test_groups_have_no_id(self):
        # グループは ID を持たない（2026-10-20）: Index にあっても振らず、付いていれば外す。番号は使い回さない
        self.note('index', body='[g](g.md)\n[n](n.md)')
        g = self.note('g', '4', body='[m](m.md)')
        g.write_text(g.read_text().replace('title: g\n', 'title: g\nattribute: group\n'))
        bg = self.note('bg', '5a')
        bg.write_text(bg.read_text().replace('title: bg\n', 'title: bg\nattribute: group\n'))
        n = self.note('n')
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(g), self.ident(bg)], ['', ''])
        self.assertNotIn(self.ident(n), ('', '4'))
        before = {p: p.read_text() for p in self.root.glob('*.md')}
        nf.simple_sync(self.root)
        self.assertEqual(before, {p: p.read_text() for p in before})

    def test_branch_group_takes_parent_id(self):
        # ブランチで作られたグループ（親の BranchGroup: にある）は、親ノートと同じ ID を持つ
        self.note('index', body='[a](a.md)')
        self.note('a', body='BranchGroup:\n[bg](bg.md)\n\nhello')
        bg = self.note('bg', body='ParentBranch:\n[a](a.md)')
        bg.write_text(bg.read_text().replace('title: bg\n', 'title: bg\nattribute: group\n'))
        other = self.note('other', '7')
        other.write_text(other.read_text().replace('title: other\n', 'title: other\nattribute: group\n'))
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(self.root / 'a.md'), '1')
        self.assertEqual(self.ident(bg), '1')
        self.assertEqual(self.ident(other), '')
        before = {p: p.read_text() for p in self.root.glob('*.md')}
        nf.simple_sync(self.root)
        self.assertEqual(before, {p: p.read_text() for p in before})
        self.assertEqual(fz.navigate(self.root, self.root / 'a.md', 'up')['ok'], False)

    def test_one_blank_line_before_sections(self):
        # 本文の最後と ChildBranch: などのあいだの空行は、多くても少なくても 1 つにそろう
        self.note('index', body='[a](a.md)\n[b](b.md)')
        a = self.note('a', body='本文\n\n\n\nChildBranch:\n[b](b.md)')
        b = self.note('b', body='文\nChildBranch:\n[c](c.md)')
        self.note('c')
        nf.simple_sync(self.root)
        for p in (a, b):
            lines = p.read_text().split('\n')
            i = lines.index('ChildBranch:')
            self.assertEqual(lines[i - 1], '', p.name)
            self.assertNotEqual(lines[i - 2], '', p.name)

    def test_reparent_renumbers_subtree(self):
        # 親が変わったら、そのノートと子孫の番号を新しい親の下に振り直す（年ができて月が入る、など）
        self.note('index', body='[d](d.md)')
        d = self.note('d', '1', body='[2026-10](m.md)')
        m = self.note('m', '1a', body='ParentBranch:\n[d](d.md)')
        m.write_text(m.read_text().replace('title: m', 'title: 2026-10').replace('# m', '# 2026-10'))
        day = self.note('day', '1a1', body='ParentBranch:\n[2026-10](m.md)')
        day.write_text(day.read_text().replace('title: day', 'title: 2026-10-19-MO-x').replace('# day', '# 2026-10-19-MO-x'))
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(m), self.ident(day)], ['1a', '1a1'])
        y = self.note('y', body='ParentBranch:\n[d](d.md)\n\n[2026-10](m.md)')
        y.write_text(y.read_text().replace('title: y', 'title: 2026').replace('# y', '# 2026'))
        m.write_text(m.read_text().replace('[d](d.md)', '[2026](y.md)'))
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(y), '1b')
        self.assertEqual([self.ident(m), self.ident(day)], ['1b1', '1b1a'])
        before = {p: p.read_text() for p in self.root.glob('*.md')}
        nf.simple_sync(self.root)
        self.assertEqual(before, {p: p.read_text() for p in before})

    def test_dated_siblings_in_date_order(self):
        # 日付の題のきょうだいは、作った時刻ではなく日付の順（あとで作った過去の日記も日付の位置）
        self.note('index', body='[m](m.md)')
        self.note('m', '3')
        late = self.note('late', body='ParentBranch:\n[m](m.md)')
        early = self.note('early', body='ParentBranch:\n[m](m.md)')
        late.write_text(late.read_text().replace('title: late', 'title: 2026-10-02-FR').replace('---\n', '---\ntime: 2026-10-02 10:00:00\n', 1))
        early.write_text(early.read_text().replace('title: early', 'title: 2026-10-01-TH').replace('---\n', '---\ntime: 2026-10-20 10:00:00\n', 1))
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(early), self.ident(late)], ['3a', '3b'])

    def test_backfill_uses_creation_time_not_index_order(self):
        index = self.note('index', body='[new](a.md)\n[old](z.md)')
        newer, older = self.note('a'), self.note('z')
        for p, date in [(newer, '2026-10-15 12:00:00'), (older, '2026-10-14 12:00:00')]:
            p.write_text(p.read_text().replace('---\n', f'---\ntime: {date}\n', 1))
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(older), self.ident(newer)], ['1', '2'])
        index.write_text(index.read_text().replace('[a](a.md)\n[z](z.md)', '[z](z.md)\n[a](a.md)'))
        late = self.note('late')
        late.write_text(late.read_text().replace('---\n', '---\ntime: 2020-01-01\n', 1))
        index.write_text(index.read_text() + '\n[late](late.md)\n')
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(older), self.ident(newer), self.ident(late)], ['1', '2', '3'])
        self.assertLess(fz.creation_key(Path('261014120000.md'), {'fm': []}),
                        fz.creation_key(Path('261015120000.md'), {'fm': []}))

    def test_branch_assignment_and_navigation(self):
        parent = self.note('parent', '1a')
        a, b, leaf = [self.note(n) for n in ('a', 'b', 'leaf')]
        self.assertTrue(bo.add_branches(self.root, parent, [a, b])['ok'])
        self.assertEqual([self.ident(a), self.ident(b)], ['1a1', '1a2'])
        self.assertTrue(bo.add_branches(self.root, a, [leaf])['ok'])
        self.assertEqual(self.ident(leaf), '1a1a')
        for source, direction, target in [(leaf, 'up', a), (a, 'down', leaf),
                                          (a, 'right', b), (b, 'left', a)]:
            self.assertEqual(fz.navigate(self.root, source, direction)['path'], str(target))
        self.assertFalse(fz.navigate(self.root, b, 'right')['ok'])
        self.note('duplicate', '1a1')
        self.assertIn('重複', fz.navigate(self.root, leaf, 'up')['error'])

    def test_manual_branch_and_no_frontmatter(self):
        parent = self.note('parent', '1a')
        child = self.note('child', body='ParentBranch:\n[parent](parent.md)\n\n本文')
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(child), '1a1')
        plain = self.root / 'plain.md'
        plain.write_text('# Plain\n\nBody\n')
        self.note('index', body='[plain](plain.md)')
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(plain), '1')
        self.assertIn('Body', plain.read_text())

    def test_deferred_tree_and_alphabet_rollover(self):
        p, c, d = [self.note(n) for n in ('p', 'c', 'd')]
        bo.add_branches(self.root, p, [c])
        bo.add_branches(self.root, c, [d])
        self.assertEqual(self.ident(c), '')
        self.note('index', body='[p](p.md)')
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(n) for n in (p, c, d)], ['1', '1a', '1a1'])
        self.assertEqual(fz.next_child('1', ['---\nfolgezettel: 1z\n---']), '1aa')
        self.assertEqual(fz.next_child('1a', ['---\nfolgezettel: 1a10\n---']), '1a11')
        self.assertEqual(fz.parent_id('11'), '')


if __name__ == '__main__':
    unittest.main()
