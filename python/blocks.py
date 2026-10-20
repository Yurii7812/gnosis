#!/usr/bin/env python3
"""見出し・段落（ブロック）単位の安定リンク（ED04）。

  [文字](ノート.md#見出し)     … 見出しの文字で指す（見出しの名前を変えると切れるので、壊れたら `check` が拾う）
  [文字](ノート.md#^abc123)    … ブロック ID で指す。段落の最後の行の末尾に ` ^abc123` を付けた段落が対象。
                                 段落を移動・編集しても ID が付いていれば切れない。ノートの名前変更・移動にも強い（`#…` は rename_note が保つ）。
ID を付けるのは `add-id`（利用者の明示した操作。その行の末尾に ` ^id` を足すだけ）のときだけ。他は読み取り専用。

CLI（JSON。--md なら Markdown）:
  blocks.py ROOT ids NOTE                   そのノートのブロック ID の一覧（行・段落の頭）
  blocks.py ROOT add-id NOTE LINE [ID]      LINE（1 から）を含む段落に ID を付ける。ID を省くと内容から決める。すでにあれば何もしない
  blocks.py ROOT check                      vault 全体の `#見出し`／`#^id` リンクのうち、指す先が無いもの
  blocks.py ROOT show NOTE ANCHOR           見出し／ブロックの中身
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tasks as tk  # noqa: E402

BLOCK_ID = re.compile(r"\s\^([A-Za-z0-9][A-Za-z0-9-]{0,31})\s*$")
HEAD = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
LINK = re.compile(r"(?<!!)\[((?:\\.|[^\]\\])*)\]\(([^)\s#]+)#([^)\s]+)\)")
REL_HEADS = ("ParentBranch:", "ChildBranch:", "BranchGroup:", "Group:", "Context:", "Related:", "BackLink:")


def _body_start(lines: list[str]) -> int:
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return i + 1
    return 0


def _slug(t: str) -> str:
    return re.sub(r"[^\w぀-ヿ一-鿿\-]", "", t.strip().lower().replace(" ", "-"))


def headings(lines: list[str]) -> list[tuple[int, int, str]]:
    out, fence = [], False
    for i in range(_body_start(lines), len(lines)):
        if lines[i].lstrip().startswith(("```", "~~~")):
            fence = not fence
        elif not fence:
            m = HEAD.match(lines[i])
            if m:
                out.append((i, len(m.group(1)), m.group(2)))
    return out


def find_heading(lines: list[str], anchor: str) -> tuple[int, int] | None:
    """見出しの節 [開始行(見出し自身), 終了行) 。anchor は見出しの文字・URL エンコード・小文字ハイフンのどれでも。"""
    a = unquote(anchor)
    hs = headings(lines)
    for i, lv, t in hs:
        if t == a or _slug(t) == _slug(a):
            end = len(lines)
            for j, lv2, _ in hs:
                if j > i and lv2 <= lv:
                    end = j
                    break
            for j in range(i + 1, end):
                if lines[j].strip() in REL_HEADS and lines[j] == lines[j].lstrip():
                    end = j
                    break
            return i, end
    return None


def _paragraphs(lines: list[str]):
    """(開始行, 終了行(含まない), ID or None) のコードブロック外の段落。"""
    out, fence, start = [], False, None
    for i in range(_body_start(lines), len(lines) + 1):
        ln = lines[i] if i < len(lines) else ""
        if ln.lstrip().startswith(("```", "~~~")):
            if start is not None:
                out.append((start, i))
                start = None
            fence = not fence
            continue
        if fence:
            continue
        if ln.strip():
            if start is None:
                start = i
        elif start is not None:
            out.append((start, i))
            start = None
    res = []
    for s, e in out:
        m = BLOCK_ID.search(lines[e - 1])
        res.append((s, e, m.group(1) if m else None))
    return res


def find_block(lines: list[str], bid: str) -> tuple[int, int] | None:
    for s, e, i in _paragraphs(lines):
        if i == bid:
            return s, e
    return None


def ids(lines: list[str]) -> list[dict]:
    return [{"id": i, "line": e, "start": s + 1, "text": lines[s].strip()[:60]} for s, e, i in _paragraphs(lines) if i]


def resolve(lines: list[str], anchor: str) -> list[str] | None:
    """アンカーが指す本文（見出し行は含めない。ブロックは ID の印を外す）。無ければ None。"""
    if anchor.startswith("^"):
        r = find_block(lines, anchor[1:])
        if not r:
            return None
        body = lines[r[0]:r[1]]
        body[-1] = BLOCK_ID.sub("", body[-1])
        return body
    r = find_heading(lines, anchor)
    if not r:
        return None
    body = lines[r[0] + 1:r[1]]
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    return body


def _find_note(root: Path, name: str) -> Path:
    p = (root / name)
    if p.is_file():
        return p
    for q in sorted(root.rglob("*.md")):
        if q.name == name or q.stem == name:
            return q
    raise ValueError("ノートが見つかりません: " + name)


def add_id(root: str | Path, note: str, line: int, bid: str | None = None) -> dict:
    root = Path(root).resolve()
    p = _find_note(root, note)
    text = p.read_text(encoding="utf-8")
    lines = text.split("\n")
    para = next(((s, e, i) for s, e, i in _paragraphs(lines) if s < line <= e), None)
    if not para:
        raise ValueError("その行は段落の中ではありません（空行・コードブロック・front matter）")
    s, e, existing = para
    if existing:
        return {"added": False, "id": existing, "reason": "すでに ID があります", "line": e}
    used = {i for _, _, i in _paragraphs(lines) if i}
    if bid:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,31}", bid):
            raise ValueError("ID は英数字とハイフン（32 文字まで）にしてください")
    else:
        h = hashlib.sha1("\n".join(lines[s:e]).encode("utf-8")).hexdigest()
        n = 6
        bid = h[:n]
        while bid in used:
            n += 1; bid = h[:n]
    if bid in used:
        raise ValueError("その ID はこのノートで使われています: " + bid)
    lines[e - 1] = lines[e - 1].rstrip() + " ^" + bid
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text("\n".join(lines), encoding="utf-8")
    os.replace(tmp, p)
    return {"added": True, "id": bid, "line": e, "link": f"{p.name}#^{bid}"}


def check(root: str | Path) -> dict:
    root = Path(root).resolve()
    cache: dict[Path, list[str]] = {}
    broken, total = [], 0
    for p in tk.iter_notes(root):
        rel = p.relative_to(root).as_posix()
        fence = False
        for no, ln in enumerate(p.read_text(encoding="utf-8").split("\n"), 1):
            if ln.lstrip().startswith(("```", "~~~")):
                fence = not fence
                continue
            if fence:
                continue
            for m in LINK.finditer(ln):
                tgt, anchor = m.group(2), m.group(3)
                if "://" in tgt or not tgt.endswith(".md"):
                    continue
                total += 1
                dest = (p.parent / unquote(tgt)).resolve()
                if not dest.is_file():
                    continue                                  # ファイルが無いのは別の検査(:GnosisCheck)の担当
                if dest not in cache:
                    cache[dest] = dest.read_text(encoding="utf-8").split("\n")
                if resolve(cache[dest], anchor) is None:
                    broken.append({"file": rel, "line": no, "target": dest.relative_to(root).as_posix(), "anchor": anchor, "kind": "ブロック" if anchor.startswith("^") else "見出し"})
    return {"checked": total, "broken": broken}


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    if kind == "ids":
        L = [f"# ブロック ID: {r['note']}", ""] + [f"- ^{x['id']}（{x['line']} 行目・{x['text']}）" for x in r["ids"]] + ([] if r["ids"] else ["なし"])
    elif kind == "check":
        L = ["# 壊れた見出し／ブロックのリンク", "", f"確認したリンク {r['checked']} 件・壊れているもの {len(r['broken'])} 件", ""]
        L += [f"- [{b['file']}]({b['file'].replace(' ', '%20')}):{b['line']} → {b['target']}#{b['anchor']}（{b['kind']}が見つからない）" for b in r["broken"]]
    elif kind == "show":
        L = [f"# {r['note']}#{r['anchor']}", ""] + r["lines"]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        a = [x for x in argv if x != "--md"]
        root, cmd, rest = a[0], a[1], a[2:]
        r: dict
        if cmd == "ids":
            p = _find_note(Path(root).resolve(), rest[0])
            r = {"note": p.name, "ids": ids(p.read_text(encoding="utf-8").split("\n"))}
        elif cmd == "add-id":
            r = add_id(root, rest[0], int(rest[1]), rest[2] if len(rest) > 2 else None)
        elif cmd == "check":
            r = check(root)
        elif cmd == "show":
            p = _find_note(Path(root).resolve(), rest[0])
            body = resolve(p.read_text(encoding="utf-8").split("\n"), rest[1])
            if body is None:
                raise ValueError("そのアンカーはありません: " + rest[1])
            r = {"note": p.name, "anchor": rest[1], "lines": body}
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md and cmd in ("ids", "check", "show") else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
