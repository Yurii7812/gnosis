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
        # 番号は欠番なしに詰める（5 → 1・新しいものは最後）
        self.assertEqual([self.ident(self.root / 'five.md'), self.ident(new)], ['1', '2'])
        self.assertEqual(self.ident(orphan), '')
        before = {p: p.read_text() for p in self.root.glob('*.md')}
        nf.simple_sync(self.root)
        self.assertEqual(before, {p: p.read_text() for p in before})

    def test_paper_infra_notes_get_pa_zero(self):
        # 紙の自動作成の索引は、YAML の folgezettel が PA-0（題は変えない）。デジタルの番号には影響せず、何度同期しても変わらない
        self.note('index', body='[a](a.md)')
        self.note('a')
        apex = self.note('apex')
        apex.write_text(apex.read_text().replace('title: apex', 'title: Paper-Zettelkasten-Index').replace('# apex', '# Paper-Zettelkasten-Index'))
        fidx = self.note('fidx')
        fidx.write_text(fidx.read_text().replace('title: fidx', 'title: folgezettel-Index-1').replace('# fidx', '# folgezettel-Index-1'))
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(self.root / 'a.md'), '1')
        self.assertEqual([self.ident(apex), self.ident(fidx)], ['PA-0', 'PA-0'])
        self.assertIn('# Paper-Zettelkasten-Index', apex.read_text())
        self.assertTrue(fz.ID_RE.fullmatch('PA-0'))
        self.assertEqual(fz.parent_id('PA-0'), '')
        self.assertIsNone(fz.ID_RE.fullmatch('0'))
        before = self.snapshot()
        nf.simple_sync(self.root)
        self.assertEqual(before, self.snapshot())

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
        self.assertEqual(self.ident(y), '1a')
        self.assertEqual([self.ident(m), self.ident(day)], ['1a1', '1a1a'])
        before = {p: p.read_text() for p in self.root.glob('*.md')}
        nf.simple_sync(self.root)
        self.assertEqual(before, {p: p.read_text() for p in before})

    def test_dated_siblings_in_date_order(self):
        # 日付の題のきょうだいは、作った時刻ではなく日付の順（あとで作った過去の日記も日付の位置）
        self.note('index', body='[m](m.md)')
        self.note('m', '3')
        late = self.note('late', body='ParentBranch:\n[m](m.md)')
        early = self.note('early', body='ParentBranch:\n[m](m.md)')
        late.write_text(late.read_text().replace('title: late', 'title: 2026-10-02-FR').replace('# late', '# 2026-10-02-FR').replace('---\n', '---\ntime: 2026-10-02 10:00:00\n', 1))
        early.write_text(early.read_text().replace('title: early', 'title: 2026-10-01-TH').replace('# early', '# 2026-10-01-TH').replace('---\n', '---\ntime: 2026-10-20 10:00:00\n', 1))
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(early), self.ident(late)], ['1a', '1b'])

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

    def snapshot(self):
        return {p.name: p.read_text() for p in self.root.glob('*.md')}

    def test_gaps_are_closed_and_stale_children_follow_parent(self):
        # 3 が無い・親が 3a1a なのに子が 2a のまま、といったズレは、同期で Branch の形にそろう
        self.note('index', body='[a](a.md)\n[b](b.md)\n[c](c.md)')
        self.note('a', '1')
        self.note('b', '4', body='ChildBranch:\n[x](x.md)\n[y](y.md)')
        self.note('c', '9')
        self.note('x', '2a', body='ParentBranch:\n[b](b.md)')       # 親は 4 なのに 2a
        self.note('y', '4d', body='ParentBranch:\n[b](b.md)')       # 4a〜4c が無い
        self.note('z', '4d1', body='ParentBranch:\n[y](y.md)')
        nf.simple_sync(self.root)
        got = {n: fz.value(self.root.joinpath(n + '.md').read_text()) for n in 'abcxyz'}
        self.assertEqual(got, {'a': '1', 'b': '2', 'c': '3', 'x': '2a', 'y': '2b', 'z': '2b1'})
        before = self.snapshot()
        nf.simple_sync(self.root)
        self.assertEqual(before, self.snapshot())

    def test_deleting_a_note_closes_the_gap(self):
        self.note('index', body='[a](a.md)\n[b](b.md)\n[c](c.md)')
        for n in 'abc':
            self.note(n)
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(self.root / f'{n}.md') for n in 'abc'], ['1', '2', '3'])
        (self.root / 'b.md').unlink()
        idx = self.root / 'index.md'
        idx.write_text(idx.read_text().replace('[b](b.md)\n', ''))
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(self.root / f'{n}.md') for n in 'ac'], ['1', '2'])

    def test_note_with_two_parents_follows_one_of_them(self):
        self.note('index', body='[a](a.md)\n[b](b.md)')
        self.note('a', '1', body='ChildBranch:\n[k](k.md)')
        self.note('b', '2')
        self.note('k', '2a', body='ParentBranch:\n[b](b.md)\n\n[a](a.md)')
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(self.root / 'k.md'), '2a')       # 今の番号の親（b）を選ぶ
        before = self.snapshot()
        nf.simple_sync(self.root)
        self.assertEqual(before, self.snapshot())

    def test_paper_generated_notes_share_the_top_note_id(self):
        # 紙の PKM の Paper-Zettelkasten-Index（グループ）・Index-write・Folgezettel-Index は、頂点のノートと同じ番号
        self.note('index', body='[a](a.md)\n[top](top.md)')
        self.note('a')
        top = self.note('top', body='BranchGroup:\n[Paper-Zettelkasten-Index](pidx.md)\n[Index-write](iw.md)\n[Folgezettel-Index](fidx.md)')
        top.write_text(top.read_text().replace('title: top', 'title: Paper-Zettelkasten-Index').replace('# top', '# Paper-Zettelkasten-Index'))
        for name, title, grp in (('pidx', 'Paper-Zettelkasten-Index', True), ('iw', 'Index-write', False), ('fidx', 'Folgezettel-Index', True)):
            p = self.note(name)
            p.write_text(p.read_text().replace(f'title: {name}', f'title: {title}' + ('\nattribute: group' if grp else '')).replace(f'# {name}', f'# {title}'))
        nf.simple_sync(self.root)
        got = [self.ident(self.root / f'{n}.md') for n in ('top', 'pidx', 'iw', 'fidx')]
        self.assertEqual(got, ['2', '2', '2', '2'])
        before = self.snapshot()
        nf.simple_sync(self.root)
        self.assertEqual(before, self.snapshot())

    def test_paper_notes_use_their_own_prefix(self):
        # 紙のスキャンノートの番号は PA- + 題。デジタルの番号とぶつからず、デジタル側に飛び番も作らない。印は設定で変えられる
        self.note('index', body='[a](a.md)\n[b](b.md)')
        self.note('a')
        self.note('b')
        scan = self.note('scan')
        scan.write_text(scan.read_text().replace('title: scan', 'title: 1a2\nsource: scan').replace('# scan', '# 1a2'))
        scan1 = self.note('scan1')
        scan1.write_text(scan1.read_text().replace('title: scan1', 'title: 1\nsource: scan').replace('# scan1', '# 1'))
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(self.root / 'a.md'), self.ident(self.root / 'b.md')], ['1', '2'])
        self.assertEqual([self.ident(scan1), self.ident(scan)], ['PA-1', 'PA-1a2'])
        self.assertEqual(fz.parent_id('PA-1a2'), 'PA-1a')
        self.assertEqual(fz.parent_id('PA-1'), '')
        self.assertTrue(fz.ID_RE.fullmatch('PA-1a2'))
        self.assertLess(fz.natural_key('10'), fz.natural_key('PA-1'))
        before = self.snapshot()
        nf.simple_sync(self.root)
        self.assertEqual(before, self.snapshot())
        # 印を PB に変える
        (self.root / '.gnosis').mkdir()
        (self.root / '.gnosis' / 'settings.json').write_text('{"paperIdPrefix": "PB"}')
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(scan1), self.ident(scan)], ['PB-1', 'PB-1a2'])
        self.assertEqual([self.ident(self.root / 'a.md'), self.ident(self.root / 'b.md')], ['1', '2'])

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
        self.note('index', body='[parent](parent.md)')
        parent = self.note('parent')
        child = self.note('child', body='ParentBranch:\n[parent](parent.md)\n\n本文')
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(parent), self.ident(child)], ['1', '1a'])
        plain = self.root / 'plain.md'
        plain.write_text('# Plain\n\nBody\n')
        self.note('index', body='[parent](parent.md)\n[plain](plain.md)')
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(plain), '2')
        self.assertIn('Body', plain.read_text())

    def test_numbers_are_removed_from_notes_that_lost_their_place(self):
        # Index の本文にも日記にもなく、親もないノートは番号を持たない。親を外す・Index から外すと、番号も外れる
        self.note('index', body='[a](a.md)\n[b](b.md)')
        a = self.note('a')
        b = self.note('b')
        k = self.note('k', body='ParentBranch:\n[b](b.md)\n\n本文')
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(a), self.ident(b), self.ident(k)], ['1', '2', '2a'])
        # k の ParentBranch を消す → 親も Index もない → 番号が外れる
        k.write_text(k.read_text().replace('ParentBranch:\n[b](b.md)\n\n', ''))
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(k), '')
        # b を Index から外す → 番号が外れ、その子（a の下に付け替えていない k2）も外れる
        k2 = self.note('k2', body='ParentBranch:\n[b](b.md)\n\n本文')
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(k2), '2a')
        idx = self.root / 'index.md'
        idx.write_text(idx.read_text().replace('[b](b.md)\n', ''))
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(a), self.ident(b), self.ident(k2)], ['1', '', ''])
        # もう一度 Index に載せると、新しい番号が付く
        idx.write_text(idx.read_text().rstrip('\n') + '\n[b](b.md)\n')
        nf.simple_sync(self.root)
        self.assertEqual([self.ident(b), self.ident(k2)], ['2', '2a'])
        before = self.snapshot()
        nf.simple_sync(self.root)
        self.assertEqual(before, self.snapshot())

    def test_group_only_notes_have_no_number_except_in_the_index(self):
        # グループに入っているだけで親がないノートは、グループが Index（index.md）のときだけ最上位の番号。他のグループなら番号なし
        self.note('index', body='[g](g.md)\n[x](x.md)')
        g = self.note('g')
        g.write_text(g.read_text().replace('title: g', 'title: g\nattribute: group').replace('\n# g', '\n# g'))
        g.write_text(g.read_text() + '[y](y.md)\n')
        x = self.note('x')
        y = self.note('y')
        nf.simple_sync(self.root)
        self.assertEqual(self.ident(x), '1')       # Index の本文にあるので最上位の番号
        self.assertEqual(self.ident(y), '')        # Index ではないグループにあるだけ
        self.assertEqual(self.ident(g), '')

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
