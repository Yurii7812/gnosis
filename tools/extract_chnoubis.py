#!/usr/bin/env python3
"""assets/chnoubis/chnoubis.sh から Unicode Braille のアートを取り出し、
サイズごとの静的アセット（chnoubis-44.txt / -60.txt / -80.txt）に書く。

Bash の無い環境（Windows など）でも同じシンボルを表示できるよう、起動画面・
アイコン生成はこのテキストを使う。chnoubis.sh を差し替えたら再実行する:
    python3 tools/extract_chnoubis.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "chnoubis" / "chnoubis.sh"


def extract(text: str) -> dict[str, list[str]]:
    arts = {}
    for m in re.finditer(r"<<'ART_(\d+)'\n(.*?)\nART_\1\n", text, re.S):
        arts[m.group(1)] = m.group(2).split("\n")
    return arts


def main() -> int:
    arts = extract(SRC.read_text(encoding="utf-8"))
    if not arts:
        print("アートが見つかりません: " + str(SRC), file=sys.stderr)
        return 1
    for size, lines in arts.items():
        out = ROOT / "assets" / "chnoubis" / f"chnoubis-{size}.txt"
        out.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"{out.relative_to(ROOT)}: {max(len(l) for l in lines)} 桁 × {len(lines)} 行")
    return 0


if __name__ == "__main__":
    sys.exit(main())
