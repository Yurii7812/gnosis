#!/usr/bin/env python3
"""ユーザーコマンド(`command!`)の名前が、plugin/ 全体で重複していないことを確かめる。

`command!` は同名を黙って上書きするので、後から読み込まれた定義が既存の機能を壊しても気づけない
（実例: 新機能の `:GnosisBackup` が、既存の暗号 vault 7z バックアップ `:GnosisBackup` を上書きした）。
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

root = Path(__file__).resolve().parent.parent
pat = re.compile(r"^\s*command!?\s+((?:-\S+\s+)*)([A-Z][A-Za-z0-9]*)")
seen = defaultdict(list)
for f in sorted((root / "plugin").glob("*.vim")):
    for i, line in enumerate(f.read_text(encoding="utf-8").split("\n"), 1):
        m = pat.match(line)
        if m:
            seen[m.group(2)].append(f"{f.name}:{i}")
dups = {k: v for k, v in seen.items() if len(v) > 1}
for k, v in sorted(dups.items()):
    print(f"NG: コマンド {k} が重複: {', '.join(v)}")
if dups:
    sys.exit(1)
print(f"commands OK ({len(seen)} commands)")
