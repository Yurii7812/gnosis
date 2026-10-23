#!/usr/bin/env python3
"""よみの移行: ノートの front matter の `yomi:` を、vault の `.gnosis/yomi/`（JSON Lines）へ移す（2026-10-23 決定）。

  yomi_migrate.py ROOT [--dry-run]

各ノートの `yomi:` のブロックだけを取り除き（ほかの行は 1 バイトも変えない）、JSON に入れる。
JSON にすでにある名前は上書きしない。本物の vault に使う前に、バックアップを取る。
（同期でも、保存のたびに同じ移行が少しずつ行われる。これは一度に全部移すための道具。）
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import japanese_yomi as jy  # noqa: E402
import note_format_v2 as nf  # noqa: E402


def run(root: str | Path, dry_run: bool = False) -> dict:
    root = Path(root).resolve()
    store = jy.YomiStore(root)
    notes = names = 0
    for p in nf._iter_md(root):
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        lines = text.split("\n")
        fm, rest = jy.split_front_matter(lines)
        mapping = jy.parse_yomi_map(fm)
        if not mapping:
            continue
        notes += 1
        names += len(mapping)
        if dry_run:
            continue
        store.import_map(p.relative_to(root).as_posix(), mapping)
        new_fm = jy.set_yomi_map(fm, {})
        p.write_text("\n".join(new_fm + rest), encoding="utf-8")
    return {"dry_run": dry_run, "notes": notes, "names": names}


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    json.dump(run(argv[1], "--dry-run" in argv[2:]), sys.stdout, ensure_ascii=False)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
