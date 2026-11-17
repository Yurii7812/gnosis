"""旧番号 → 新番号の移行（zk_id_migrate）の試験。一時の vault だけを使う（本物の vault には触らない）。"""
import tempfile
import unittest
from pathlib import Path

import folgezettel as fz
import note_format_v2 as nf
import zk_id as zk
import zk_id_migrate as mig


def write(root: Path, name: str, title: str, ident: str = '', body: str = '', extra: str = '') -> Path:
    fm = f'---\ntitle: {title}\n'
    if ident:
        fm += f'folgezettel: {ident}\n'
    fm += extra + '---\n\n'
    p = root / f'{name}.md'
    p.write_text(fm + f'# {title}\n\n{body}\n', encoding='utf-8')
    return p


class ZkIdMigrateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'vault'
        self.root.mkdir()
        self.backup = Path(self.temp.name) / 'backup'

    def test_plan_maps_old_tree_and_skips_paper(self):
        write(self.root, 'a', 'a', '1', body='[b](b.md)')
        write(self.root, 'b', 'b', '1a', body='ParentBranch:\n[a](a.md)')
        write(self.root, 'c', 'c', '1a1', body='ParentBranch:\n[b](b.md)')
        write(self.root, 'paper', '1a2', 'PA-1a2', extra='source: scan\n')      # 紙: 触らない
        write(self.root, 'plain', 'plain')                                       # 番号なし: 触らない
        result = mig.plan(self.root)
        mapping = {r['old']: r['new'] for r in result['rows']}
        self.assertEqual(mapping, {'1': '1a', '1a': '1a1', '1a1': '1a1a'})
        self.assertEqual(result['errors'], [])
        self.assertEqual(result['duplicates'], [])
        self.assertTrue(any(s['value'] == 'PA-1a2' for s in result['skipped']))
        # 親子（Branch）は保たれる
        self.assertEqual(zk.parent(mapping['1a1']), mapping['1a'])

    def test_apply_writes_backup_map_and_is_stable_after_sync(self):
        write(self.root, 'index', 'index', body='[a](a.md)\n[b](b.md)')
        write(self.root, 'a', 'a', '1', body='[b](b.md)')
        write(self.root, 'b', 'b', '1a', body='ParentBranch:\n[a](a.md)')
        out = mig.apply(self.root, self.backup)
        self.assertTrue(Path(out['backup']).exists())
        maps = list(self.backup.glob('zk-id-map-*.json'))
        self.assertEqual(len(maps), 1)
        self.assertEqual(fz.value((self.root / 'a.md').read_text(encoding='utf-8')), '1a')
        self.assertEqual(fz.value((self.root / 'b.md').read_text(encoding='utf-8')), '1a1')
        # 同期しても番号は変わらない（残す・詰めない）
        nf.simple_sync(self.root)
        self.assertEqual(fz.value((self.root / 'a.md').read_text(encoding='utf-8')), '1a')
        self.assertEqual(fz.value((self.root / 'b.md').read_text(encoding='utf-8')), '1a1')

    def test_plan_is_read_only(self):
        p = write(self.root, 'a', 'a', '1')
        before = p.read_text(encoding='utf-8')
        mig.plan(self.root)
        self.assertEqual(p.read_text(encoding='utf-8'), before)


if __name__ == '__main__':
    unittest.main()
