#!/usr/bin/env python3
"""ノートの中の単語を、同じ題のノートへのリンクにする（語源から覚えるときなど）。

    word_link.py candidates ROOT FILE [--lines A B]     … リンクにできる単語の一覧（JSON）。FILE は vault の中のノート
    word_link.py apply ROOT FILE [--lines A B] --words JSON … 選んだ単語（題の配列）をリンクにした全文を出す（ファイルは書き換えない）

- 題は、ほかのノートの先頭の `# 見出し`（H1）。大文字・小文字は区別しない（apple と Apple は同じ）。リンクの文字は文中の書き方のまま。
- 英数字で始まる・終わる題は、前後が英数字でないところだけ当たる（`pineapple` の中の `apple` は当てない）。日本語は前後を見ない。
- 重なるときは長い題が先（`apple pie` と `apple` なら `apple pie`）。
- 当てない所: front matter、コードブロック、`インラインコード`、すでにあるリンク・画像・URL・HTML、見出しの行。
- 自分自身の題と、2 文字より短い題は当てない。同じ題のノートが複数あるときは、パスが短いほう。
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
from note_title import title_of_lines  # noqa: E402

MIN_LEN = 2
_FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
_PROTECT = re.compile(
    r"`[^`\n]*`"                      # インラインコード
    r"|!?\[[^\]\n]*\]\([^)\n]*\)"     # リンク・画像（文字も行き先も）
    r"|<[^>\n]+>"                     # HTML・<URL>
    r"|https?://[^\s)>\]]+"           # URL
)
_ALNUM = r"A-Za-z0-9_"


def vault_titles(root: Path, skip: str = "") -> dict[str, tuple[str, str]]:
    """小文字にした題 → (題, vault 内の相対パス)。ドット始まりのフォルダは見ない。"""
    found: dict[str, tuple[str, str]] = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            p = Path(dirpath) / name
            rel = p.relative_to(root).as_posix()
            if rel == skip:
                continue
            try:
                lines = p.read_text(encoding="utf-8").split("\n")[:80]
            except (OSError, UnicodeDecodeError):
                continue
            title = title_of_lines(lines, p.stem).strip()
            if len(title) < MIN_LEN or "\n" in title or "[" in title or "]" in title:
                continue
            key = title.lower()
            old = found.get(key)
            if old is None or len(rel) < len(old[1]):
                found[key] = (title, rel)
    return found


def _pattern(titles: dict[str, tuple[str, str]]) -> re.Pattern | None:
    if not titles:
        return None
    alts = []
    for key in sorted(titles, key=lambda k: (-len(k), k)):
        t = titles[key][0]
        a = re.escape(t)
        if re.match(f"[{_ALNUM}]", t[0]):
            a = f"(?<![{_ALNUM}])" + a
        if re.match(f"[{_ALNUM}]", t[-1]):
            a = a + f"(?![{_ALNUM}])"
        alts.append(a)
    return re.compile("|".join(alts), re.IGNORECASE)


def _scan(lines: list[str], lo: int, hi: int, pat: re.Pattern):
    """(行番号 0 始まり, 開始, 終了, 文中の文字) を順に出す。lo..hi は対象の行の範囲（0 始まり・hi を含まない）。"""
    start = 0
    if lines and lines[0].strip() == "---":
        for j in range(1, len(lines)):
            if lines[j].strip() in ("---", "..."):
                start = j + 1
                break
    fence = False
    for i, ln in enumerate(lines):
        if _FENCE.match(ln):
            fence = not fence
            continue
        if i < start or fence or not (lo <= i < hi) or ln.lstrip().startswith("#"):
            continue
        spans = [m.span() for m in _PROTECT.finditer(ln)]
        for m in pat.finditer(ln):
            if any(a < m.end() and m.start() < b for a, b in spans):
                continue
            yield i, m.start(), m.end(), m.group(0)


def candidates(root: Path, rel: str, lines_text: list[str], lo: int, hi: int) -> list[dict]:
    titles = vault_titles(root, skip=rel)
    pat = _pattern(titles)
    out: dict[str, dict] = {}
    if pat is None:
        return []
    for i, _a, _b, word in _scan(lines_text, lo, hi, pat):
        title, path = titles[word.lower()]
        c = out.setdefault(title.lower(), {"title": title, "path": path, "count": 0, "line": i + 1,
                                           "sample": lines_text[i].strip()[:60]})
        c["count"] += 1
    return sorted(out.values(), key=lambda c: (c["line"], c["title"].lower()))


def apply(root: Path, rel: str, lines_text: list[str], lo: int, hi: int, words: list[str]) -> list[str]:
    chosen = {w.lower() for w in words}
    titles = vault_titles(root, skip=rel)   # 選ばなかった長い題も含めて探す（apple pie を選ばなくても、その中の apple は当てない）
    pat = _pattern(titles)
    if pat is None:
        return lines_text
    here = (root / rel).parent
    edits: dict[int, list[tuple[int, int, str]]] = {}
    for i, a, b, word in _scan(lines_text, lo, hi, pat):
        _title, path = titles[word.lower()]
        if word.lower() not in chosen:
            continue
        link = quote(os.path.relpath(root / path, here).replace(os.sep, "/"), safe="/")
        edits.setdefault(i, []).append((a, b, f"[{word}]({link})"))
    out = list(lines_text)
    for i, es in edits.items():
        ln = out[i]
        for a, b, new in sorted(es, reverse=True):
            ln = ln[:a] + new + ln[b:]
        out[i] = ln
    return out


def _args(argv: list[str]):
    lo, hi, words = 0, 10 ** 9, []
    rest = []
    it = iter(argv)
    for a in it:
        if a == "--lines":
            lo, hi = int(next(it)) - 1, int(next(it))
        elif a == "--words":
            words = json.loads(next(it))
        else:
            rest.append(a)
    return rest, lo, hi, words


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[0] not in ("candidates", "apply"):
        print(__doc__, file=sys.stderr)
        return 2
    rest, lo, hi, words = _args(argv[1:])
    root = Path(rest[0]).resolve()
    note = Path(rest[1]).resolve()
    try:
        rel = note.relative_to(root).as_posix()
    except ValueError:
        print("vault の外のノートです", file=sys.stderr)
        return 2
    lines = note.read_text(encoding="utf-8").split("\n")
    if argv[0] == "candidates":
        print(json.dumps({"words": candidates(root, rel, lines, lo, hi)}, ensure_ascii=False))
    else:
        print("\n".join(apply(root, rel, lines, lo, hi, words)), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
