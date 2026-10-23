#!/usr/bin/env python3
"""題の移行: front matter の `title:` を消して、題は先頭の `# 見出し`（H1）だけにする（2026-10-23 決定）。

  title_migrate.py ROOT [--dry-run]

各ノートについて:
  title: と H1 が同じ     … title: の行を消す
  title: と H1 が違う     … H1 が正。title: の行を消す（違っていた件数と一覧を返す）
  H1 が無い               … title: の題で H1 を front matter の後ろに入れ、title: を消す
  title: が無い           … 何もしない
消すのは title: の行（と、そのせいで空になる front matter）だけ。ほかの行は 1 バイトも変えない。
本物の vault に使う前に、バックアップを取る（index_migrate.py と同じ流儀）。
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_format_v2 as nf  # noqa: E402

_TITLE = re.compile(r"^\s*title\s*:\s*(.*?)\s*$")
_H1 = re.compile(r"^#\s+(\S.*?)\s*#*\s*$")
_FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")


def migrate_text(text: str) -> tuple[str, str, str]:
    """(新しい本文, 種類, 題)。種類: same / diverge / no_h1 / none。"""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return text, "none", ""
    end = next((i for i in range(1, len(lines)) if lines[i].strip() in ("---", "...")), None)
    if end is None:
        return text, "none", ""
    ti = [i for i in range(1, end) if _TITLE.match(lines[i])]
    if not ti:
        return text, "none", ""
    yt = _TITLE.match(lines[ti[0]]).group(1).strip().strip("\"'")
    h1 = None
    fence = False
    for i in range(end + 1, len(lines)):
        if _FENCE.match(lines[i]):
            fence = not fence
            continue
        m = None if fence else _H1.match(lines[i])
        if m:
            h1 = m.group(1).strip()
            break
    fm = [ln for i, ln in enumerate(lines[:end + 1]) if i not in ti]
    rest = lines[end + 1:]
    if h1 is None:
        if rest and rest[0].strip() == "":
            rest = [rest[0], f"# {yt}", ""] + rest[1:]
        else:
            rest = ["", f"# {yt}", ""] + rest
        kind, title = "no_h1", yt
    else:
        kind, title = ("same" if h1 == yt else "diverge"), h1
    if len(fm) == 2:   # 中身の無い front matter は書かない
        fm = []
        while rest and rest[0].strip() == "":
            rest = rest[1:]
    return "\n".join(fm + rest), kind, title


def run(root: str | Path, dry_run: bool = False) -> dict:
    root = Path(root).resolve()
    counts = {"same": 0, "diverge": 0, "no_h1": 0, "none": 0}
    diverged: list[dict] = []
    for p in nf._iter_md(root):
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        new, kind, title = migrate_text(text)
        counts[kind] += 1
        if kind == "diverge":
            m = _TITLE.match(next(ln for ln in text.split("\n")[1:] if _TITLE.match(ln)))
            diverged.append({"path": p.relative_to(root).as_posix(), "title": m.group(1).strip().strip("\"'"), "h1": title})
        if kind != "none" and not dry_run:
            p.write_text(new, encoding="utf-8")
    return {"dry_run": dry_run, "counts": counts, "diverged": diverged[:200]}


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    json.dump(run(argv[1], "--dry-run" in argv[2:]), sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
