#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import capture_import as ci


class CaptureImportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.pack = self.base / 'pack'
        self.pack.mkdir()
        self.root = self.base / 'vault'
        self.root.mkdir()
        self.entry = dict(id='261019100000', created=1792371600000, topic='',
                          text='こんにちは今日はいい天気だと思ったけどそうでもないかもしれない\nところで最近はいい感じ。',
                          images=[], parent=None, contexts=[])
        self.write_pack()

    def write_pack(self):
        (self.pack / 'capture.json').write_text(json.dumps(dict(format='gnosis-capture', entries=[self.entry]), ensure_ascii=False))

    def plan(self, root=None):
        return ci.plan(str(self.pack), str(root or self.root))['items'][0]

    def record(self):
        target = self.entry['id'] + '.md'
        (self.root / target).write_text('# PCの原本\n\n本文\n')
        ci.record(str(self.root), [(self.entry['id'], target)], str(self.pack))
        return self.root / target

    def test_title_and_original_body(self):
        item = self.plan()
        self.assertEqual(item['title'], 'こんにちは今日はいい天気だと思ったけどそ...')
        self.assertEqual(item['text'], self.entry['text'])
        self.assertEqual(ci._first_line_title('\n短い文\n次の段落'), '短い文')
        self.assertEqual(ci._first_line_title('😀' * 21), '😀' * 20 + '...')
        self.assertEqual(item['topic'], '')
        self.entry['topic'] = 'メモ'; self.write_pack()
        self.assertEqual(self.plan()['topic'], '')

    def test_separate_vault_and_missing_destination(self):
        dest = self.record()
        self.assertTrue(self.plan()['done'])
        other = self.base / 'other'; other.mkdir()
        self.assertFalse(self.plan(other)['done'])
        self.assertTrue(dest.exists())
        dest.unlink()
        self.assertFalse(self.plan()['done'])

    def test_heal_state_follows_renamed_note(self):
        dest = self.record()
        dest.write_text('---\ntime: ' + ci._time_of(self.entry) + '\n---\n\n# PCの原本\n')
        dest.rename(self.root / 'new-name.md')  # アプリの外（同期など）で名前が変わった
        self.assertEqual(ci.heal_state(self.root), 1)
        self.assertEqual(ci.load_state(self.root)['ids'][self.entry['id']], 'new-name.md')
        self.assertEqual(ci.heal_state(self.root), 0)  # 2 回目は何もしない

    def test_changed_text_is_merge_and_topic_move_preserves_pc_file(self):
        dest = self.record()
        original = dest.read_text()
        self.entry['topic'] = '仕事'; self.entry['edited'] = 42; self.write_pack()
        self.assertTrue(self.plan()['update'])
        self.assertFalse(self.plan()['done'])
        self.assertEqual(dest.read_text(), original)
        self.entry['text'] += '\n追記'; self.write_pack()
        item = self.plan()
        # 本文を書き直したら別版ではなく同じノートへの差分更新（merge）。ここでは何も書き換えない（plan は読むだけ）
        self.assertFalse(item['update'])
        self.assertFalse(item['done'])
        self.assertTrue(item['merge'])
        self.assertEqual(dest.read_text(), original)

    def test_renamed_note_is_found_by_time(self):
        dest = self.record()
        dest.write_text('---\ntime: ' + ci._time_of(self.entry) + '\n---\n\n# PCの原本\n')
        sub = self.root / 'sub'; sub.mkdir()
        moved = sub / 'renamed.md'
        dest.rename(moved)  # PC で名前を変え、フォルダも移した
        item = self.plan()
        self.assertTrue(item['done'])
        self.assertEqual(item['file'], 'sub/renamed.md')
        # 記録（state）を失っても、ノートが実在すれば取り込み済み（重複ノートを作らない）
        (self.root / '.state' / ci.STATE_NAME).unlink()
        self.assertTrue(self.plan()['done'])
        # ドット始まりのフォルダ（ゴミ箱など）の中は探さない
        hidden = self.root / '.trash'; hidden.mkdir()
        moved.rename(hidden / 'x.md')
        self.assertFalse(self.plan()['done'])

    def test_export_flags_do_not_duplicate(self):
        self.record()
        self.entry['exported'] = True; self.entry['edited'] = 123; self.write_pack()
        self.assertTrue(self.plan()['done'])

    def test_missing_image_and_invalid_state_never_acknowledged(self):
        self.entry['images'] = ['missing.jpg']; self.write_pack()
        with self.assertRaises(ValueError): self.plan()
        with self.assertRaises(ValueError):
            ci.record(str(self.root), [(self.entry['id'], 'missing.md')], str(self.pack))
        self.assertFalse(ci._state_path(self.root).exists())
        ci._state_path(self.root).parent.mkdir()
        ci._state_path(self.root).write_text('broken')
        with self.assertRaises(ValueError): ci.load_state(self.root)

    def test_legacy_state_recovers_original_and_diary_missing_is_reimportable(self):
        dest = self.record()
        ci._state_path(self.root).write_text(json.dumps({'ids': {self.entry['id']: dest.name}}))
        self.assertTrue(self.plan()['done'])
        self.assertFalse(self.plan()['update'])
        diary =self.root / 'diary.md'; diary.write_text('# diary')
        (self.root / '.state/diary_days.json').write_text(json.dumps({'days': {'2026-10-19': diary.name}}))
        self.assertTrue(ci._destination_exists(self.root, '(diary:2026-10-19)'))
        diary.unlink()
        self.assertFalse(ci._destination_exists(self.root, '(diary:2026-10-19)'))

    def test_ack_is_scoped_and_does_not_delete_phone_entries(self):
        self.record()
        with patch.object(ci, 'adb_ready', return_value=''), patch.object(ci, '_adb', return_value='adb'), patch.object(ci.subprocess, 'run') as run:
            run.return_value.returncode = 0
            self.assertEqual(ci.adb_mark(str(self.root)), 0)
            command = run.call_args_list[0].args[0]
            self.assertEqual(command[-2:], ['tee', 'files/imported.json.tmp'])
            self.assertEqual(run.call_args.args[0][-3:], ['mv', 'files/imported.json.tmp', 'files/imported.json'])
            self.assertNotIn('entries.json', ' '.join(command))
            data = json.loads(run.call_args_list[0].kwargs['input'])
            self.assertEqual(data['vault'], str(self.root.resolve()))
            self.assertEqual(data['entries'], [self.entry])
            (self.root / (self.entry['id'] + '.md')).unlink()
            run.reset_mock()
            ci.adb_mark(str(self.root))
            self.assertEqual(json.loads(run.call_args_list[0].kwargs['input'])['entries'], [])


if __name__ == '__main__':
    unittest.main()
