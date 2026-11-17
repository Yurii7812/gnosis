"""区画とトピックの番号（zk_id）の単体試験。2026-11-17 の決定どおりの例。"""
import unittest

import zk_id as z


class ZkIdTest(unittest.TestCase):
    def test_letters_bijective(self):
        self.assertEqual(z.letters(1), 'a')
        self.assertEqual(z.letters(26), 'z')
        self.assertEqual(z.letters(27), 'aa')
        self.assertEqual(z.letter_value('aa'), 27)

    def test_valid_shapes(self):
        for ident in ['1', '1a', '1a1', '1a2a', '51a1a', '1z', '1aa', '1a10']:
            self.assertTrue(z.is_valid(ident), ident)
        for ident in ['', '0', 'a', '1-1', '1a1-', '1a.1', 'PA-1a', '1a 1']:
            self.assertFalse(z.is_valid(ident), ident)

    def test_sort_is_numeric_per_segment(self):
        self.assertLess(z.sort_key('1a2'), z.sort_key('1a10'))
        self.assertLess(z.sort_key('1z'), z.sort_key('1aa'))
        self.assertEqual(sorted(['1a10', '1a2', '1a1a', '1b'], key=z.sort_key),
                         ['1a1a', '1a2', '1a10', '1b'])

    def test_parent(self):
        self.assertEqual(z.parent('1a1a'), '1a1')
        self.assertEqual(z.parent('1a1'), '1a')
        self.assertEqual(z.parent('1a'), '1')
        self.assertEqual(z.parent('51'), '')

    def test_continuation_examples(self):
        self.assertEqual(z.continuation('1a', set()), '1a1')      # 1a → 1a1（その続き）
        self.assertEqual(z.continuation('1a1', set()), '1a2')     # 1a1 → 1a2
        self.assertEqual(z.continuation('1a2', {'1a3'}), '1a4')   # 使用中なら進める
        self.assertEqual(z.continuation('1z', set()), '1z1')      # 文字の段の続きは 1 を足す

    def test_branch_examples(self):
        self.assertEqual(z.branch('1a2', set()), '1a2a')          # 数字 → a を足す
        self.assertEqual(z.branch('1a', set()), '1a1')            # 文字 → 1 を足す
        self.assertEqual(z.branch('1a', {'1a1'}), '1a2')          # 使用中なら進める
        self.assertEqual(z.branch('1a1', set()), '1a1a')
        # 段が z を超えたら aa（x, y, z, aa と続く）
        used = {'1a1' + z.letters(i) for i in range(1, 27)}
        self.assertEqual(z.branch('1a1', used), '1a1aa')

    def test_new_region(self):
        self.assertEqual(z.new_region(set()), '1a')
        self.assertEqual(z.new_region({1, 2, 5}), '6a')

    def test_migrate_examples_from_spec(self):
        # 仕様の表: 旧 → 新
        self.assertEqual(z.migrate_id('1'), '1a')
        self.assertEqual(z.migrate_id('1a'), '1a1')
        self.assertEqual(z.migrate_id('1b'), '1a2')
        self.assertEqual(z.migrate_id('1a1'), '1a1a')
        self.assertEqual(z.migrate_id('1d1'), '1a4a')
        self.assertEqual(z.migrate_id('51a1'), '51a1a')

    def test_migrate_keeps_branch_tree(self):
        # 旧の親子（Branch）は、新でも「親の番号に 1/a を足した」関係のまま
        pairs = [('1', '1a'), ('1a', '1a1'), ('1a1', '1a1a'), ('1a', '1a2'), ('1a2', '1a2a')]
        for old_parent, old_child in pairs:
            new_parent, new_child = z.migrate_id(old_parent), z.migrate_id(old_child)
            self.assertEqual(z.parent(new_child), new_parent, (old_parent, old_child))

    def test_migrate_is_injective(self):
        olds = ['1', '1a', '1b', '1z', '1aa', '1a1', '1a10', '2', '2a1b']
        news = [z.migrate_id(o) for o in olds]
        self.assertEqual(len(set(news)), len(news))
        for n in news:
            self.assertTrue(z.is_valid(n), n)

    def test_migrate_rejects_bad_input(self):
        with self.assertRaises(ValueError):
            z.migrate_id('PA-1a')
        with self.assertRaises(ValueError):
            z.migrate_id('')


if __name__ == '__main__':
    unittest.main()
