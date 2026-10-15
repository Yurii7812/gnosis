#!/usr/bin/env python3
"""gs / \\l 用: ノートを全文検索して fzf に 1 行ずつ流す。

    <絶対パス> \t <タイトル（ANSI強調）> \t <最初のヒット行、表示名のみのヒットは0> \t <候補種別>

- 検索は「全クエリ語がタイトルか本文にある」AND。**タイトルに当たった語数が多い順**
  （=タイトル優先）に並べる。同じならタイトル名順。
- クエリが空なら全ノートをタイトル順に出す。
- 左（一覧）はタイトルだけ。右（プレビュー）は preview_highlight.py が
  クエリ語を強調し、3列目のヒット行へスクロールする。
- fzf 側は --disabled で検索しない（検索・並び・強調はこのスクリプトが行う）。

使い方: note_search.py [--mode all|groups|index|notes] [--mode-file FILE] [--only <paths-file>] <root> [query...]
  --cycle next|previous … mode-file のモードを切り替えて画面の見出しを出す。
  index はグループと、リンク先の Group: に登録元があるグループ本文のリンク表示名。宛先＋表示名で重複を除く。
  --only <paths-file> … そのファイルに列挙した絶対パスだけを検索対象にする
                        （<Space>=今のノートのリンク先に絞る用）。各行は
                        `絶対パス` か `絶対パス<TAB>リンクの表示名`。表示名があれば、
                        左の一覧にはノートのタイトルではなくその表示名を出し、
                        検索・優先順位にも表示名を使う（そのページでの呼び名で探せる）。
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
from urllib.parse import unquote

import note_format_v2 as nf
import re
import sys

SKIP_DIRS = {".git", ".hg", ".svn", "node_modules", "__pycache__",
             ".venv", "venv", ".mypy_cache", ".pytest_cache"}
MAX_BYTES = 2_000_000
RED = "\033[1;31m"
RESET = "\033[0m"


def split_tokens(query: str) -> list[str]:
    return [t for t in re.split(r"[\s\u3000]+", query) if t]


def title_of(text: str, path: str) -> tuple[str, int]:
    """(タイトル, タイトル行 1 始まり)。YAML title → 先頭 # 見出し → ファイル名。"""
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        for i in range(1, min(len(lines), 40)):
            if lines[i].strip() in ("---", "..."):
                break
            m = re.match(r"\s*title\s*:\s*(.+)", lines[i])
            if m:
                return m.group(1).strip().strip("\"'"), i + 1
    for i, ln in enumerate(lines):
        m = re.match(r"#\s+(.+)", ln)
        if m:
            return m.group(1).strip(), i + 1
    return os.path.splitext(os.path.basename(path))[0], 1


def highlight(text: str, tokens: list[str]) -> str:
    for t in tokens:
        tl = t.lower()
        out: list[str] = []
        start = 0
        while True:
            j = text.lower().find(tl, start)
            if j < 0:
                out.append(text[start:])
                break
            out.append(text[start:j])
            out.append(RED + text[j:j + len(t)] + RESET)
            start = j + len(t)
        text = "".join(out)
    return text


def load_notes(root: str):
    for dp, dns, fns in os.walk(root):
        dns[:] = sorted(d for d in dns if d not in SKIP_DIRS and not d.startswith("."))
        for fn in sorted(fns):
            if not fn.endswith(".md"):
                continue
            p = os.path.join(dp, fn)
            try:
                if os.path.getsize(p) > MAX_BYTES:
                    continue
                with open(p, encoding="utf-8", errors="ignore") as f:
                    text = f.read()
            except OSError:
                continue
            yield os.path.abspath(p), text


def first_hit_line(lines: list[str], tokens: list[str]) -> int:
    for i, ln in enumerate(lines, 1):
        low = ln.lower()
        if any(t.lower() in low for t in tokens):
            return i
    return 1


# Reuse the note-format parser for group attributes and body/relationship boundaries.
# Only registered group body links define index entries; a normal note's incidental links do not.
INDEX_LINK_RE = re.compile(r"(?<!!)\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)")
MODES = ("all", "groups", "index", "notes")


def is_group(path: str, text: str) -> bool:
    fm, _rest = nf._split_front_matter(text.splitlines())
    return Path(path).name == "index.md" or nf._fm_attr(fm) == nf.CATEGORY_ATTR


def index_entries(notes: dict[str, str]):
    """Yield (target path, display name, source group) from group body links."""
    by_name: dict[str, list[Path]] = {}
    known = {Path(p).resolve(): p for p in notes}
    for path in known:
        by_name.setdefault(path.name, []).append(path)
        by_name.setdefault(path.stem, []).append(path)
    # Require the destination's explicit Group relation as well as the group's
    # body entry. Incidental links inside a group are not registered entries.
    parsed = {p: nf._simple_parse_text(Path(p), text) for p, text in notes.items()}
    memberships = {}
    for path, note in parsed.items():
        memberships[Path(path).resolve()] = {
            nf._resolve(unquote(target), Path(path).parent, Path(path).parent, by_name)
            for _label, target in nf._links_from(note["group"])
        }
    for source, text in notes.items():
        if not is_group(source, text):
            continue
        body = parsed[source]["body"]
        # The parser appends BranchGroup to body for rendering; it is a relation,
        # not an index entry, so do not collect it.
        if nf.BRANCH_GROUP_HEAD in body:
            body = body[:body.index(nf.BRANCH_GROUP_HEAD)]
        for line, fenced in zip(body, nf._fenced(body)):
            if fenced:
                continue
            for match in nf._link_iter(INDEX_LINK_RE, line):
                label, target = match.groups()
                label = re.sub(r"\\(.)", r"\1", label).strip()
                target = unquote(target.split("#", 1)[0])
                if not label or not target.lower().endswith(".md"):
                    continue
                resolved = nf._resolve(target, Path(source).parent, Path(source).parent, by_name)
                if resolved in known and Path(source).resolve() in memberships[resolved]:
                    yield known[resolved], label, source


def search_rows(root: str, query: str, mode: str = "all", only: dict[str, str] | None = None):
    """Shared candidate collection/search for gs and both forms of \\l.

    Rows keep the existing path/title/hit-line protocol. Zero means there is no
    hit in the destination (a name supplied by an index is not a body hit).
    """
    tokens = split_tokens(query)
    notes = dict(load_notes(root))
    candidates = []
    for path, text in notes.items():
        if only is not None and os.path.realpath(path) not in only:
            continue
        group = is_group(path, text)
        if (mode in ("groups", "index") and not group) or (mode == "notes" and group):
            continue
        name = only.get(os.path.realpath(path), "") if only is not None else ""
        candidates.append((path, name, ""))
    if mode == "index":
        candidates.extend(index_entries(notes))
    rows = []
    seen = set()
    for path, name, source in candidates:
        key = (os.path.realpath(path), name or title_of(notes[path], path)[0])
        if key in seen:
            continue
        seen.add(key)
        text = notes[path]
        title, _tline = title_of(text, path)
        shown = name or title
        hay = (name + "\n" + text).lower()
        if tokens and not all(t.lower() in hay for t in tokens):
            continue
        name_hits = sum(t.lower() in name.lower() for t in tokens)
        title_hits = sum(t.lower() in title.lower() for t in tokens)
        body_hit = any(t.lower() in text.lower() for t in tokens)
        line = first_hit_line(text.split("\n"), tokens) if body_hit else (0 if tokens else 1)
        rows.append((-name_hits, -title_hits, shown.casefold(), path, shown, line, source))
    rows.sort()
    return rows


MODE_LABELS = {
    "ja": ("全部", "グループだけ", "グループ＋索引の表示名", "ノートだけ"),
    "en": ("All", "Groups", "Groups + index names", "Notes"),
}


def read_mode(path: str | None, fallback: str = "all") -> str:
    if path:
        try:
            value = Path(path).read_text(encoding="utf-8").strip()
            if value in MODES:
                return value
        except OSError:
            pass
    return fallback


def mode_header(mode: str, lang: str) -> str:
    hint = "Ctrl+→/↓ 次・Ctrl+←/↑ 前" if lang == "ja" else "Ctrl+Right/Down next; Ctrl+Left/Up previous"
    return MODE_LABELS[lang][MODES.index(mode)] + " | " + hint


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only")
    parser.add_argument("--mode", choices=MODES, default="all")
    parser.add_argument("--mode-file")
    parser.add_argument("--cycle", choices=("next", "previous"))
    parser.add_argument("--lang", choices=MODE_LABELS, default="en")
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("query", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    mode = read_mode(args.mode_file, args.mode)
    if args.cycle:
        if not args.mode_file:
            parser.error("--cycle requires --mode-file")
        mode = MODES[(MODES.index(mode) + (1 if args.cycle == "next" else -1)) % len(MODES)]
        Path(args.mode_file).write_text(mode, encoding="utf-8")
        print(mode_header(mode, args.lang))
        return 0
    only: dict[str, str] | None = None
    if args.only:
        only = {}
        with open(args.only, encoding="utf-8") as f:
            for ln in f:
                path_part, _, name = ln.rstrip("\n").partition("\t")
                if path_part.strip():
                    only[os.path.realpath(path_part.strip())] = name.strip()
    query = " ".join(args.query)
    rows = search_rows(args.root, query, mode, only)
    out = []
    tokens = split_tokens(query)
    for _nh, _th, _t, path, title, line, _source in rows:
        kind = ("索引名" if args.lang == "ja" else "index name") if _source else ""
        out.append(f"{path}\t{highlight(title.replace(chr(9), ' '), tokens)}\t{line}\t{kind}")
    sys.stdout.write("\n".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
