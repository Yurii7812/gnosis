#!/usr/bin/env python3
"""他ノートの本文・見出し・ブロックの取り込み表示（トランスクルージョン。ED05）。循環を検出して止める。

書き方（ノートの中。1 行まるごと）:
  {{include: 相手.md}}                 … 相手の本文（題と関係ブロックを除く）
  {{include: 相手.md#見出し}}           … その節
  {{include: 相手.md#^abc123}}         … そのブロック（`blocks.py add-id` で ID を付けた段落）
**元のノートは書き換えない**。展開した結果を返すだけ（画面に出す・新しいノートに書き出す）。展開した内容は引用（`> `）にし、末尾に出典のリンクを付ける。
循環（A が B を取り込み、B が A を取り込む）・深すぎる入れ子（既定 5 段）・見つからない先は、その場に ⚠ の注意を出して、そこで止める（無限に広がらない）。

CLI（JSON。--md なら展開後のテキスト）:
  transclude.py ROOT expand NOTE [--depth N]     展開したテキスト
  transclude.py ROOT check                       vault 全体の {{include}} の問題（循環・欠落・深すぎ）
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blocks as bk  # noqa: E402
import tasks as tk  # noqa: E402

INC = re.compile(r"^\s*\{\{include:\s*(.+?)\s*\}\}\s*$")
REL_HEADS = bk.REL_HEADS


def _split(spec: str) -> tuple[str, str]:
    path, _, anchor = spec.partition("#")
    return unquote(path.strip()), anchor.strip()


def _whole_body(lines: list[str]) -> list[str]:
    body = lines[bk._body_start(lines):]
    # 先頭の題(H1)と、末尾の関係ブロックを除く
    while body and not body[0].strip():
        body.pop(0)
    if body and re.match(r"^#\s", body[0]):
        body.pop(0)
    for i, ln in enumerate(body):
        if ln.strip() in REL_HEADS and ln == ln.lstrip():
            body = body[:i]
            break
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    return body


def _target(root: Path, base: Path, path: str) -> Path | None:
    for cand in ((base.parent / path), (root / path)):
        if cand.is_file():
            return cand.resolve()
    for q in sorted(root.rglob("*.md")):
        if q.name == path or q.stem == path:
            return q.resolve()
    return None


def _expand(root: Path, note: Path, depth: int, max_depth: int, stack: tuple[Path, ...], problems: list[dict]) -> list[str]:
    text = note.read_text(encoding="utf-8")
    out, fence = [], False
    lines = text.split("\n")
    start = bk._body_start(lines)
    for no, ln in enumerate(lines, 1):
        if no <= start or ln.lstrip().startswith(("```", "~~~")):
            if ln.lstrip().startswith(("```", "~~~")):
                fence = not fence
            out.append(ln)
            continue
        m = None if fence else INC.match(ln)
        if not m:
            out.append(ln)
            continue
        spec = m.group(1)
        path, anchor = _split(spec)
        here = note.relative_to(root).as_posix()
        def warn(msg, kind):
            problems.append({"file": here, "line": no, "include": spec, "problem": kind, "message": msg})
            out.append(f"> ⚠ {msg}（{spec}）")
        dest = _target(root, note, path)
        if dest is None:
            warn("取り込み先のノートが見つかりません", "missing")
            continue
        if dest in stack or dest == note:
            warn("循環しているので展開しません", "cycle")
            continue
        if depth >= max_depth:
            warn("入れ子が深すぎるので展開しません", "depth")
            continue
        dlines = dest.read_text(encoding="utf-8").split("\n")
        body = bk.resolve(dlines, anchor) if anchor else _whole_body(dlines)
        if body is None:
            warn("取り込み先の見出し／ブロックが見つかりません", "anchor")
            continue
        body = [bk.BLOCK_ID.sub("", x) for x in body]                      # 取り込み先の ^id の印は表示に出さない
        # 取り込んだ本文の中の {{include}} も展開(入れ子)。一時ファイルを作らず、本文だけ再帰的に処理する
        inner = _expand_lines(root, dest, body, depth + 1, max_depth, stack + (note,), problems)
        title = next((re.sub(r"^title:\s*", "", x) for x in dlines[:12] if x.startswith("title:")), dest.stem)
        link = dest.relative_to(root).as_posix().replace(" ", "%20") + (("#" + anchor) if anchor else "")
        out += ["> " + x if x.strip() else ">" for x in inner] + [f"> — 出典: [{title}]({link})"]
    return out


def _expand_lines(root: Path, base: Path, body: list[str], depth: int, max_depth: int, stack: tuple[Path, ...], problems: list[dict]) -> list[str]:
    out = []
    for ln in body:
        m = INC.match(ln)
        if not m:
            out.append(ln)
            continue
        spec = m.group(1)
        path, anchor = _split(spec)
        here = base.relative_to(root).as_posix()
        def warn(msg, kind):
            problems.append({"file": here, "line": 0, "include": spec, "problem": kind, "message": msg})
            out.append(f"> ⚠ {msg}（{spec}）")
        dest = _target(root, base, path)
        if dest is None:
            warn("取り込み先のノートが見つかりません", "missing"); continue
        if dest in stack or dest == base:
            warn("循環しているので展開しません", "cycle"); continue
        if depth >= max_depth:
            warn("入れ子が深すぎるので展開しません", "depth"); continue
        dl = dest.read_text(encoding="utf-8").split("\n")
        b = bk.resolve(dl, anchor) if anchor else _whole_body(dl)
        if b is None:
            warn("取り込み先の見出し／ブロックが見つかりません", "anchor"); continue
        b = [bk.BLOCK_ID.sub("", x) for x in b]
        inner = _expand_lines(root, dest, b, depth + 1, max_depth, stack + (base,), problems)
        out += ["> " + x if x.strip() else ">" for x in inner]
    return out


def expand(root: str | Path, note: str, max_depth: int = 5) -> dict:
    root = Path(root).resolve()
    p = _target(root, root / "x", note)
    if p is None:
        raise ValueError("ノートが見つかりません: " + note)
    problems: list[dict] = []
    lines = _expand(root, p, 0, max_depth, (), problems)
    return {"note": p.relative_to(root).as_posix(), "text": "\n".join(lines), "problems": problems}


def check(root: str | Path, max_depth: int = 5) -> dict:
    root = Path(root).resolve()
    probs, n = [], 0
    for p in tk.iter_notes(root):
        if "{{include:" not in p.read_text(encoding="utf-8"):
            continue
        n += 1
        probs += expand(root, p.relative_to(root).as_posix(), max_depth)["problems"]
    seen, uniq = set(), []
    for x in probs:                                                 # 入れ子の中で同じ問題が重複して出るので 1 つにまとめる
        k = (x["file"], x["line"], x["include"], x["problem"])
        if k not in seen:
            seen.add(k); uniq.append(x)
    return {"notes_with_includes": n, "problems": uniq}


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        depth = 5
        a = []
        it = iter([x for x in argv if x != "--md"])
        for x in it:
            if x == "--depth":
                depth = int(next(it))
            else:
                a.append(x)
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "expand":
            r = expand(root, rest[0], depth)
            print(r["text"] + "\n", end="") if md else print(json.dumps(r, ensure_ascii=False))
        elif cmd == "check":
            r = check(root, depth)
            if md:
                L = ["# {{include}} の検査", "", f"取り込みを含むノート {r['notes_with_includes']} 件・問題 {len(r['problems'])} 件", ""]
                L += [f"- [{x['file']}]({x['file'].replace(' ', '%20')}):{x['line']} {x['message']}（{x['include']}）" for x in r["problems"]]
                print("\n".join(L))
            else:
                print(json.dumps(r, ensure_ascii=False))
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
