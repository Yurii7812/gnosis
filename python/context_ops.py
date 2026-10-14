#!/usr/bin/env python3
"""Context ブロック（`Context:` の行 + 直下のリンク群）の読み書きと、旧形式（`### Context` 節）からの移行。

新しい形式（H1 タイトルの直後。Markdown の見出しではなく、ふつうのテキスト行）:

    # ノート B

    Context:
    [ノート A](a.md)
    [ノート C](c.md)

    本文。

- `Context:` は H1 の直後（間は空行だけ。H1 が無ければ front matter の直後）にあるものだけを Context とみなす。
  リンク行（`[表示名](パス)`）が続く間がブロック。空行・文章で終わる。コードブロックの中は見ない。
- 追加は既存リンク群の**最後**へ。同じノートへのリンク（相対パスを解決して比べる）は重複させない。
- Context が無いノートでは、H1 の直後に作る（Context リンクを勝手に作ることはしない。足すときだけ）。
- 旧形式 `### Context`（旧 `### Parent`）は読める。足す・移行するときは、リンクを 1 本も失わずに新形式へ寄せる。
  リンクでない行（メモなど）が旧節にあれば、その節をそのまま残す。
- 一括移行は自動では行わない。`migrate_lines()` / CLI `context_ops.py migrate ROOT [--apply] [FILE...]`
  （既定は試走で、書き換えない。`--apply` で、移行前後のリンク集合と他の行が同じことを確かめてから書く）。

CLI:
    context_ops.py migrate ROOT [--apply] [FILE...]
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

try:
    import note_format_v2 as nf
except ImportError:  # 実行ディレクトリ以外から import されたとき
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import note_format_v2 as nf

CONTEXT_HEAD = "Context:"
LEGACY_MARKS = (nf.CONTEXT_MARK, nf.UP_MARK)
SECTION_MARKS = {nf.PARENT_BRANCH_MARK, nf.CONTEXT_MARK, nf.UP_MARK, nf.GROUP_MARK,
                 nf.CHILD_BRANCH_MARK, nf.RELATED_MARK, nf.DOWN_MARK}
_LINK_LINE = nf._SIMPLE_LINK_LINE_RE
_H1 = re.compile(r"^#\s+\S")


def _fm_len(lines: list[str]) -> int:
    fm, _rest = nf._split_front_matter(lines)
    return len(fm)


def find_block(lines: list[str]) -> tuple[int, int] | None:
    """新形式の Context ブロックの (`Context:` の行, リンクの最後の行)（0 始まり）。無ければ None。"""
    return nf.find_context_block(lines, _fm_len(lines))


def legacy_sections(lines: list[str]) -> list[tuple[int, int]]:
    """旧 `### Context`（`### Parent`）節の [見出しの行, 終わりの次の行)。コードブロックの中は見ない。"""
    start = _fm_len(lines)
    fenced = nf._fenced(lines)
    marks = [(i, lines[i].strip()) for i in range(start, len(lines)) if not fenced[i] and lines[i].strip() in SECTION_MARKS]
    out = []
    for k, (i, m) in enumerate(marks):
        if m in LEGACY_MARKS:
            end = marks[k + 1][0] if k + 1 < len(marks) else len(lines)
            out.append((i, end))
    return out


def _target(link_line: str, base: Path) -> str:
    m = nf._SIMPLE_INLINE_LINK.search(link_line)
    if not m:
        return ""
    tg = m.group(2).split("#", 1)[0].strip()
    return os.path.normpath(tg if tg.startswith("/") else os.path.join(str(base), tg))


def context_links(lines: list[str]) -> list[str]:
    """Context のリンク行（新形式 + 旧形式）。"""
    out: list[str] = []
    b = find_block(lines)
    if b:
        out += [lines[k] for k in range(b[0] + 1, b[1] + 1)]
    for s, e in legacy_sections(lines):
        out += [lines[k] for k in range(s + 1, e) if _LINK_LINE.match(lines[k])]
    return out


def _insert_new_block(lines: list[str], links: list[str]) -> list[str]:
    """H1 の直後（無ければ front matter の直後）に `Context:` ブロックを作る。前後に空行を確保する。"""
    out = list(lines)
    start = _fm_len(out)
    fenced = nf._fenced(out)
    h1 = next((i for i in range(start, len(out)) if not fenced[i] and _H1.match(out[i])), None)
    at = (h1 + 1) if h1 is not None else start
    block = [CONTEXT_HEAD] + links
    if at < len(out) and out[at].strip() == "":
        out[at + 1:at + 1] = block + [""]   # H1 の次の空行を、Context の前の空行として使う
    else:
        out[at:at] = [""] + block + [""]
    return out


def add_link(lines: list[str], link: str, base: Path) -> tuple[list[str], bool]:
    """Context に link を足す。戻り値 (新しい行, 足したか)。既にあれば足さない。
    旧形式があれば、リンクを失わずに新形式へ寄せてから足す。"""
    want = _target(link, base)
    existing = context_links(lines)
    if want and any(_target(l, base) == want for l in existing):
        return list(lines), False
    out = migrate_lines(lines)
    b = find_block(out)
    if b:
        out.insert(b[1] + 1, link)
    else:
        out = _insert_new_block(out, [link])
    return out, True


def migrate_lines(lines: list[str]) -> list[str]:
    """旧 `### Context` 節のリンクを新形式の Context ブロックへ移す。旧節が無ければ何もしない。
    リンクは 1 本も失わない（重複は 1 本にまとめる）。リンクでない行が旧節にあれば、その節は残す。"""
    secs = legacy_sections(lines)
    if not secs:
        return list(lines)
    out = list(lines)
    legacy_links: list[str] = []
    for s, e in reversed(secs):
        keep = [out[k] for k in range(s + 1, e) if out[k].strip() and not _LINK_LINE.match(out[k])]
        legacy_links = [out[k] for k in range(s + 1, e) if _LINK_LINE.match(out[k])] + legacy_links
        if keep:
            out[s:e] = [out[s]] + keep
        else:
            at_end = e >= len(out)
            del out[s:e]
            if at_end:
                while out and out[-1].strip() == "":
                    out.pop()
    # 既存のブロックのリンクの後ろに、旧節のリンクを（重複を除いて）足す
    merged: list[str] = []
    b = find_block(out)
    if b:
        for k in range(b[0] + 1, b[1] + 1):
            merged.append(out[k])
    keys = {l.strip() for l in merged}
    for l in legacy_links:
        if l.strip() in keys:
            continue
        keys.add(l.strip())
        merged.append(l)
    if b:
        out[b[0] + 1:b[1] + 1] = merged
    elif merged:
        out = _insert_new_block(out, merged)
    return out


def migrate_text(text: str) -> str:
    lines = text.split("\n")
    had_nl = text.endswith("\n")
    if had_nl:
        lines.pop()
    new = migrate_lines(lines)
    return "\n".join(new) + ("\n" if had_nl or new else "")


def verify_migration(old: str, new: str) -> bool:
    """移行前後で、Context のリンク集合が同じで、Context 以外の行が（順序も）同じか。"""
    ol, nl = old.split("\n"), new.split("\n")
    links = lambda ls: sorted(set(x.strip() for x in context_links(ls)))  # noqa: E731
    if links(ol) != links(nl):
        return False

    def rest(ls: list[str]) -> list[str]:
        drop: set[int] = set()
        b = find_block(ls)
        if b:
            drop |= set(range(b[0], b[1] + 1))
        for s, e in legacy_sections(ls):
            drop |= {s} | {k for k in range(s + 1, e) if _LINK_LINE.match(ls[k])}
        return [x for i, x in enumerate(ls) if i not in drop and x.strip() != ""]
    return rest(ol) == rest(nl)


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "migrate":
        root = Path(argv[2]).resolve()
        apply = "--apply" in argv[3:]
        files = [Path(a) for a in argv[3:] if not a.startswith("--")] or list(nf._iter_md(root))
        report = {"migrated": [], "skipped": [], "failed": []}
        for p in files:
            try:
                old = p.read_text(encoding="utf-8")
            except OSError:
                continue
            if p.name == "index.md" or not legacy_sections(old.split("\n")):
                continue
            new = migrate_text(old)
            if not verify_migration(old, new):
                report["failed"].append(str(p))
                continue
            report["migrated"].append(str(p))
            if apply:
                tmp = p.with_name(f".{p.name}.ctx-{os.getpid()}.tmp")
                tmp.write_text(new, encoding="utf-8")
                if p.read_text(encoding="utf-8") != old:
                    tmp.unlink()
                    report["failed"].append(str(p))
                    report["migrated"].pop()
                    continue
                os.replace(tmp, p)
        report["applied"] = apply
        print(json.dumps(report, ensure_ascii=False))
        return 1 if report["failed"] else 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
