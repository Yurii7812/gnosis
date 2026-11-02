#!/usr/bin/env python3
"""gs / \\l 用: ノートを全文検索して fzf に 1 行ずつ流す。

    <絶対パス> \t <タイトル（ANSI強調）> \t <最初のヒット行、表示名のみのヒットは0> \t <候補種別>

- 順位: 完全一致 → Index の索引（表示名だけ）→ その他の索引（表示名だけ）→ グループ（タイトルだけ）→ ノートのタイトル → ノートの本文。
- ノート本文の一致では、索引の別名ではなくノートのタイトルを表示する。
- クエリが空なら全ノートをタイトル順に出す。
- 左（一覧）はタイトルだけ。右（プレビュー）は preview_highlight.py が
  クエリ語を強調し、3列目のヒット行へスクロールする。
- fzf 側は --disabled で検索しない（検索・並び・強調はこのスクリプトが行う）。

使い方: note_search.py [--only <paths-file>] [--lang ja|en] <root> [query...]
  索引は、リンク先の Group: に登録元があるグループ本文のリンク表示名。
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
import search_query as sq
import sys

SKIP_DIRS = {".git", ".hg", ".svn", "node_modules", "__pycache__",
             ".venv", "venv", ".mypy_cache", ".pytest_cache"}
MAX_BYTES = 2_000_000
RED = "\033[1;31m"
RESET = "\033[0m"


def split_tokens(query: str) -> list[str]:
    """色をつける語（検索の書き方は search_query.py。肯定の語だけ）。"""
    return sq.terms(query)


def title_of(text: str, path: str) -> tuple[str, int]:
    """(タイトル, タイトル行 1 始まり)。先頭の # 見出し（H1）→ 古いノートの YAML title: → ファイル名。"""
    lines = text.split("\n")
    start = 0
    ytitle, yline = "", 1
    if lines and lines[0].strip() == "---":
        for i in range(1, min(len(lines), 40)):
            if lines[i].strip() in ("---", "..."):
                start = i + 1
                break
            m = re.match(r"\s*title\s*:\s*(.+)", lines[i])
            if m and not ytitle:
                ytitle, yline = m.group(1).strip().strip("\"'"), i + 1
    fence = False
    for i in range(start, len(lines)):
        if re.match(r"\s{0,3}(`{3,}|~{3,})", lines[i]):
            fence = not fence
            continue
        m = None if fence else re.match(r"#\s+(.+)", lines[i])
        if m:
            return m.group(1).strip(), i + 1
    if ytitle:
        return ytitle, yline
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
        low = sq.normalize(ln)
        if any(sq.normalize(t) in low for t in tokens):
            return i
    return 1


# Reuse the note-format parser for group attributes and body/relationship boundaries.
# Only registered group body links define index entries; a normal note's incidental links do not.
INDEX_LINK_RE = re.compile(r"(?<!!)\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)")


def is_group(path: str, text: str) -> bool:
    fm, _rest = nf._split_front_matter(text.splitlines())
    return Path(path).name == "index.md" or nf._fm_attr(fm) == nf.CATEGORY_ATTR


def index_entries(notes: dict[str, str], parsed: dict | None = None):
    """Yield (target path, display name, source group) from group body links."""
    by_name: dict[str, list[Path]] = {}
    known = {Path(p).resolve(): p for p in notes}
    for path in known:
        by_name.setdefault(path.name, []).append(path)
        by_name.setdefault(path.stem, []).append(path)
    # Require the destination's explicit Group relation as well as the group's
    # body entry. Incidental links inside a group are not registered entries.
    if parsed is None:
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


# This is the one search policy for gs and \l. The first category is an
# alias registered directly in the vault's index.md; the second is an alias
# registered in another group. Aliases match *only their displayed names*.
# Groups match only their titles. Ordinary notes match title, then actual body.
# Exact display/title matches outrank partial matches in every category.
KIND_LABELS = {
    "ja": {"root-index": "Indexの索引", "index": "索引", "group": "グループ", "note": "ノート"},
    "en": {"root-index": "From Index", "index": "Index entry", "group": "Group", "note": "Note"},
}

# Adapted to terminal palettes, so these remain distinguishable in most
# light and dark themes. Only the category tag is colored: match highlighting
# in the title remains red and is not overridden.
KIND_ANSI = {
    "root-index": "\033[1;35m",  # magenta: global Index entries
    "index": "\033[1;34m",       # blue: other index entries
    "group": "\033[1;32m",       # green: groups
    "note": "\033[90m",          # grey: ordinary notes
}


def colored_kind(kind: str, lang: str) -> str:
    """fzf --ansi category tag; never insert ANSI sequences into a note path."""
    label = KIND_LABELS[lang][kind]
    return KIND_ANSI[kind] + "[" + label + "]" + RESET



def _match_quality(display: str, words: list[str]) -> int:
    """Smaller is better: exact > starts with > word boundary > substring."""
    if not words:
        return 3
    value = sq.normalize(display).strip()
    joined = " ".join(sq.normalize(word) for word in words)
    if value == joined:
        return 0
    if value.startswith(joined):
        return 1
    if all(re.search(r"(?<!\w)" + re.escape(sq.normalize(w)), value) for w in words):
        return 2
    return 3


def search_rows(root: str, query: str, only: dict[str, str] | None = None):
    """Return (sort-exact, sort-tier, sort-quality, path, shown, hit-line, source, kind).

    Index entries never inherit a match from their destination note; an alias
    is included only when its *own displayed name* matches. One note-body
    hit produces one note row, displayed with the destination's title.
    """
    groups = sq.parse(query)
    notes = dict(load_notes(root))
    parsed = {path: nf._simple_parse_text(Path(path), text) for path, text in notes.items()}
    candidates = []
    for path, text in notes.items():
        realpath = os.path.realpath(path)
        if only is not None and realpath not in only:
            continue
        title, title_line = title_of(text, path)
        group = is_group(path, text)
        label = only.get(realpath, "") if only is not None else ""
        body = parsed[path]["body"]
        if nf.BRANCH_GROUP_HEAD in body:
            body = body[:body.index(nf.BRANCH_GROUP_HEAD)]
        content = "\n".join(body)
        # For --only, preserve a referring page's chosen link display name.
        candidates.append((path, label or title, title, title_line, content,
                           "group" if group else "note", ""))
    if only is None:
        for path, label, source in index_entries(notes, parsed):
            candidates.append((path, label, "", 0, "", "root-index"
                               if Path(source).resolve() == (Path(root) / "index.md").resolve() else "index", source))

    results = []
    seen = set()
    for path, shown, title, title_line, body, kind, source in candidates:
        key = (os.path.realpath(path), shown, kind)
        if key in seen:
            continue
        seen.add(key)
        display = sq.normalize(shown)
        body_hay = sq.normalize(body)
        # The --only link-label counts as the searchable title for that picker.
        primary = sq.normalize(shown if only is not None else title)
        actual_title = sq.normalize(title)
        full = primary + "\n" + actual_title + "\n" + body_hay
        best = None
        best_words = []
        for g in groups or [sq.Group()]:
            # Negative terms always apply to the permitted search fields.
            hay = display if kind in ("root-index", "index", "group") else full
            if any(sq.normalize(w) in hay for w in g.neg):
                continue
            terms = [sq.normalize(w) for w in g.pos]
            if not all(word in hay for word in terms):
                continue
            if kind == "root-index":
                tier = 0
            elif kind == "index":
                tier = 1
            elif kind == "group":
                tier = 2
            elif all(word in primary for word in terms) or (only is not None and all(word in actual_title for word in terms)):
                tier = 3   # Every positive word can be found in the note title.
            else:
                tier = 4   # Content match (potentially with title terms as AND).
            quality = _match_quality(shown, g.pos) if tier < 4 else 4
            # The exact-match flag precedes category: "Index" must beat
            # "Folgezettel-Index" even if the latter is an index alias.
            candidate = (0 if quality == 0 and g.pos else 1, tier, quality)
            if best is None or candidate < best:
                best, best_words = candidate, g.pos
        if best is None:
            continue
        if kind in ("root-index", "index"):
            line = 0
        elif (only is not None and only.get(os.path.realpath(path), "")
              and best[1] == 3 and all(sq.normalize(w) in sq.normalize(shown) for w in best_words)):
            line = 0  # Local link display name may not occur in the destination.
        elif best[1] < 4:
            line = title_line
        else:
            # Preview the destination's matching content, not an index alias.
            line = first_hit_line(notes[path].split("\n"), best_words)
        results.append((*best, path, shown, line, source, kind))
    results.sort(key=lambda r: (r[0], r[1], r[2], sq.normalize(r[4]), r[3]))
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only")
    parser.add_argument("--lang", choices=KIND_LABELS, default="en")
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("query", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    only: dict[str, str] | None = None
    if args.only:
        only = {}
        with open(args.only, encoding="utf-8") as f:
            for ln in f:
                path_part, _, name = ln.rstrip("\n").partition("\t")
                if path_part.strip():
                    only[os.path.realpath(path_part.strip())] = name.strip()
    query = " ".join(args.query)
    rows = search_rows(args.root, query, only)
    out = []
    tokens = split_tokens(query)
    for _exact, _tier, _quality, path, title, line, _source, category in rows:
        kind = colored_kind(category, args.lang)
        out.append(f"{path}\t{highlight(title.replace(chr(9), ' '), tokens)}\t{line}\t{kind}")
    sys.stdout.write("\n".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
