#!/usr/bin/env python3
"""デジタルの番号を、旧い形（Branch の形の番号）から区画とトピックの番号（1a から）へ移す（2026-11-17）。

対象: front matter の `folgezettel:` を持つデジタルのノート。紙の PKM のノート（題が番号・source: scan・
生成物の索引）と、印つきの番号（PA-…）は触らない（紙は古い番号のまま。仕様）。
変換は zk_id.migrate_id（先頭の数字はそのまま＋a、元の段は文字↔数字を入れ替え）。親子は保たれる。
ファイル名・本文のリンクは、デジタルでは番号を含まない（同期が ParentBranch: などの名前のリンクで親子を持つ）ので書き換えない。

CLI（結果は JSON。対応表も保存する）:
    zk_id_migrate.py plan  ROOT                          何も書かない。旧→新の対応表を出す
    zk_id_migrate.py apply ROOT BACKUP_DIR               バックアップ（tar.gz）と対応表（JSON）を作ってから書き換え、同期で確かめる
実行前に、vault を開いている Vim・アプリが無いこと。暗号化 vault（.crypt）は平文にしてから（利用者が開錠したときだけ）。
"""
from __future__ import annotations

import json
import os
import re
import sys
import tarfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import folgezettel as fz  # noqa: E402
import zk_id as zk  # noqa: E402

_OLD_RE = re.compile(r'[1-9]\d*(?:[a-z]+|\d+)*')
_TITLE_RE = re.compile(r'^title:\s*(.*)$', re.M)
_SCAN_RE = re.compile(r'^source:\s*scan\s*$', re.M)


def _front_matter(text: str) -> str:
    if not text.startswith('---\n'):
        return ''
    end = text.find('\n---', 4)
    return text[4:end] if end >= 0 else ''


def _title(text: str) -> str:
    fm = _front_matter(text)
    m = _TITLE_RE.search(fm)
    if m:
        return m.group(1).strip().strip('"\'')
    h1 = re.search(r'^# (.+)$', text, re.M)
    return h1.group(1).strip() if h1 else ''


def is_paper_or_generated(text: str) -> bool:
    """紙の PKM のノート・紙の生成物は対象外（番号は古いまま）。"""
    title = _title(text)
    if _SCAN_RE.search(_front_matter(text)):
        return True
    if fz.PAPER_TITLE_RE.match(title) and not fz.DATED_TITLE_RE.match(title):
        return True
    return title in (fz.PAPER_TOP_TITLE, 'Folgezettel-Index', 'Index-write') or bool(
        fz._INFRA_SUFFIX_RE.match(title) or fz._PAPER_INFRA_RE.match(title))


def _walk(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]
        for name in filenames:
            if name.endswith('.md'):
                yield Path(dirpath) / name


def plan(root: Path) -> dict:
    """旧 → 新の対応表。何も書かない。"""
    rows, skipped, errors = [], [], []
    for path in sorted(_walk(root)):
        text = path.read_text(encoding='utf-8')
        old = fz.value(text)
        if not old:
            continue
        if is_paper_or_generated(text) or fz.split_prefix(old)[0]:
            skipped.append({'file': path.name, 'value': old})
            continue
        if not _OLD_RE.fullmatch(old):
            errors.append({'file': path.name, 'value': old, 'reason': '旧い番号として解釈できない'})
            continue
        new = zk.migrate_id(old)
        rows.append({'file': path.name, 'old': old, 'new': new})
    news = [r['new'] for r in rows]
    dup = sorted({n for n in news if news.count(n) > 1})
    return {'rows': rows, 'skipped': skipped, 'errors': errors, 'duplicates': dup}


def apply(root: Path, backup_dir: Path) -> dict:
    result = plan(root)
    if result['errors'] or result['duplicates']:
        raise SystemExit('中止: 変換できない番号、または重複がある（' + json.dumps(result, ensure_ascii=False) + '）')
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime('%Y%m%d-%H%M%S')
    archive = backup_dir / f'vault-before-zk-id-{stamp}.tar.gz'
    with tarfile.open(archive, 'w:gz') as tf:
        tf.add(root, arcname=root.name)
    (backup_dir / f'zk-id-map-{stamp}.json').write_text(
        json.dumps(result['rows'], ensure_ascii=False, indent=2), encoding='utf-8')
    for row in result['rows']:
        path = next(root.rglob(row['file']))
        text = path.read_text(encoding='utf-8')
        path.write_text(fz.set_value(text, row['new']), encoding='utf-8')
    result['backup'] = str(archive)
    return result


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == 'plan':
        print(json.dumps(plan(Path(argv[2])), ensure_ascii=False, indent=2))
        return 0
    if len(argv) >= 4 and argv[1] == 'apply':
        out = apply(Path(argv[2]), Path(argv[3]))
        print(json.dumps({'changed': len(out['rows']), 'skipped': len(out['skipped']),
                          'backup': out['backup']}, ensure_ascii=False, indent=2))
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
