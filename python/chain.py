#!/usr/bin/env python3
"""検索 → 選ぶ → 索引案／リンク作成の、安全なコマンドチェーン（SR16）。

  chain.py ROOT index  '検索' NEWFILE [--pick 1,3-5] [--apply]     検索結果から、索引の草稿ノート（新規）を作る
  chain.py ROOT related '検索' TARGET [--pick 1,3-5] [--apply]     検索結果を、TARGET の `Related:` に足す
  chain.py ROOT undo [--force]                                      直前の related を取り消す

- **既定は試走**: 何を書くかを見せるだけで、何も書かない。`--apply` を付けたときだけ書く。
- `--pick` は検索結果の番号（1 から。`1,3-5` の形）。省略すると全部。100 件まで。
- `index` は新しいノートを作るだけ（既存は上書きしない）。`related` は TARGET の `Related:` ブロックの**最後に足すだけ**（同じ相手は足さない・自分自身は足さない）。
  足す前に TARGET を `.state/chain-undo/<日時>/` に控え、`undo` で戻せる（そのあと TARGET が変わっていたら `--force` が要る）。
- vault の外・ドット始まりのフォルダには書かない。検索の書き方は `:GnosisQuery` と同じ（vault_index）。
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import posixpath
import re
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vault_index as vi  # noqa: E402

MAX_PICK = 100
LINK_LINE = re.compile(r"^\s*\[(?:\\.|[^\]\\])*\]\(([^)\s]+)\)\s*$")
UNDO_DIR = ".state/chain-undo"


def parse_pick(spec: str | None, n: int) -> list[int]:
    """'1,3-5' → [1, 3, 4, 5]。範囲外・形の誤りは ValueError。"""
    if not spec:
        return list(range(1, n + 1))
    out: list[int] = []
    for part in spec.split(","):
        part = part.strip()
        m = re.fullmatch(r"(\d+)(?:-(\d+))?", part)
        if not m:
            raise ValueError("--pick は 1,3-5 のような形で指定してください")
        a, b = int(m.group(1)), int(m.group(2) or m.group(1))
        if a < 1 or b < a or b > n:
            raise ValueError(f"--pick の番号が範囲外です（1〜{n}）")
        out += [x for x in range(a, b + 1) if x not in out]
    return out


def _results(root: Path, query: str, limit: int = 200) -> list[dict]:
    if not query.strip():
        raise ValueError("検索の語を指定してください")
    return [{"n": i, "path": r["path"], "title": r["title"]} for i, r in enumerate(vi.search(root, query, limit=limit), 1)]


def _target(root: Path, name: str, must_exist: bool) -> tuple[Path, str]:
    t = (root / name).resolve()
    try:
        rel = t.relative_to(root)
    except ValueError:
        raise ValueError("vault の外は扱いません") from None
    if any(p.startswith(".") for p in rel.parts) or t.suffix != ".md":
        raise ValueError("vault の中の .md（ドット始まりのフォルダ以外）を指定してください")
    if must_exist and not t.is_file():
        raise ValueError("そのノートがありません: " + name)
    if not must_exist and t.exists():
        raise ValueError("すでにあります（上書きしません）: " + str(rel))
    return t, rel.as_posix()


def _rel_link(from_note: str, to_note: str) -> str:
    return posixpath.relpath(to_note, posixpath.dirname(from_note) or ".")


def add_related(text: str, from_note: str, links: list[tuple[str, str]]) -> tuple[str, list[str]]:
    """text の `Related:` ブロックの最後に links（[(表示, vault 相対パス)]）を足す。足したパスを返す。
    ブロックが無ければ、末尾に作る。コードブロックの中の `Related:` は見ない。すでにあるリンク先は足さない。"""
    lines = text.split("\n")
    fence, start = False, None
    for i, ln in enumerate(lines):
        if ln.strip().startswith(("```", "~~~")):
            fence = not fence
        elif not fence and ln.strip() == "Related:" and ln == ln.lstrip():
            start = i
    existing: set[str] = set()
    end = None
    if start is not None:
        end = start
        for j in range(start + 1, len(lines)):
            m = LINK_LINE.match(lines[j])
            if not m:
                break
            existing.add(posixpath.normpath(posixpath.join(posixpath.dirname(from_note), m.group(1).split("#")[0].replace("%20", " "))))
            end = j
    new, added = [], []
    for title, path in links:
        if path == from_note or path in existing or path in added:
            continue
        added.append(path)
        new.append(f"[{title}]({_rel_link(from_note, path).replace(' ', '%20')})")
    if not new:
        return text, []
    if start is not None:
        lines[end + 1:end + 1] = new
        return "\n".join(lines), added
    body = text.rstrip("\n")
    return body + "\n\nRelated:\n" + "\n".join(new) + "\n", added


def plan(root: str | Path, kind: str, query: str, target: str, pick: str | None = None) -> dict:
    root = Path(root).resolve()
    res = _results(root, query)
    if not res:
        raise ValueError("検索結果がありません")
    idx = parse_pick(pick, len(res))
    if len(idx) > MAX_PICK:
        raise ValueError(f"一度に扱えるのは {MAX_PICK} 件までです")
    picked = [res[i - 1] for i in idx]
    out = {"kind": kind, "query": query, "results": res, "picked": [p["n"] for p in picked], "target": target}
    if kind == "index":
        _, rel = _target(root, target, False)
        out["preview"] = [f"[{p['title']}]({_rel_link(rel, p['path']).replace(' ', '%20')})" for p in picked]
        out["target"] = rel
    elif kind == "related":
        t, rel = _target(root, target, True)
        text = t.read_text(encoding="utf-8")
        new_text, added = add_related(text, rel, [(p["title"], p["path"]) for p in picked])
        out["target"] = rel
        out["will_add"] = added
        out["skipped"] = [p["path"] for p in picked if p["path"] not in added]
        out["preview"] = [ln for ln in new_text.split("\n") if ln not in text.split("\n")] if added else []
    else:
        raise ValueError("index か related を指定してください")
    return out


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def _write(p: Path, text: str) -> None:
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, p)


def apply(root: str | Path, kind: str, query: str, target: str, pick: str | None = None, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    p = plan(root, kind, query, target, pick)
    t, rel = _target(root, target, kind == "related")
    if kind == "index":
        now = now or dt.datetime.now()
        title = f"{query.strip()}の索引（案）"
        picked = [r for r in p["results"] if r["n"] in p["picked"]]
        body = "\n".join(f"- [{r['title']}]({_rel_link(rel, r['path']).replace(' ', '%20')})" for r in picked)
        t.parent.mkdir(parents=True, exist_ok=True)
        _write(t, f"---\ntime: {now:%Y-%m-%d %H:%M:%S}\ntitle: {title}\nmoc: true\n---\n\n# {title}\n\n検索「{query.strip()}」の結果から選んだ草稿です。\n\n{body}\n")
        return {**p, "applied": True, "written": rel, "count": len(picked)}
    if not p["will_add"]:
        return {**p, "applied": False, "reason": "足すリンクがありません（すでにある・自分自身）"}
    stamp = time.strftime("%Y%m%d-%H%M%S")
    bdir = root / UNDO_DIR / stamp
    n = 2
    while bdir.exists():
        bdir = root / UNDO_DIR / f"{stamp}-{n}"; n += 1
    (bdir / "files" / Path(rel).parent).mkdir(parents=True, exist_ok=True)
    shutil.copy2(t, bdir / "files" / rel)
    text = t.read_text(encoding="utf-8")
    new_text, added = add_related(text, rel, [(r["title"], r["path"]) for r in p["results"] if r["n"] in p["picked"]])
    _write(t, new_text)
    (bdir / "meta.json").write_text(json.dumps({"target": rel, "after": _sha(t), "added": added}, ensure_ascii=False), encoding="utf-8")
    return {**p, "applied": True, "added": added, "undo": bdir.name}


def undo(root: str | Path, force: bool = False) -> dict:
    root = Path(root).resolve()
    base = root / UNDO_DIR
    ds = sorted(d for d in base.iterdir() if not d.name.endswith(".done") and (d / "meta.json").is_file()) if base.is_dir() else []
    if not ds:
        return {"ok": False, "error": "取り消せる操作がありません"}
    d = ds[-1]
    m = json.loads((d / "meta.json").read_text(encoding="utf-8"))
    t = root / m["target"]
    if not t.is_file() or (_sha(t) != m["after"] and not force):
        return {"ok": False, "error": "そのあとにノートが変わっています（--force で元に戻す）", "target": m["target"]}
    shutil.copy2(d / "files" / m["target"], t)
    shutil.move(str(d), str(d.with_name(d.name + ".done")))
    return {"ok": True, "restored": m["target"], "removed_links": m["added"]}


def to_md(r: dict) -> str:
    L = [f"# コマンドチェーン: {r['query']} → {r['kind']}", "", f"検索結果 {len(r['results'])} 件のうち {len(r['picked'])} 件を選びました。", ""]
    L += [f"{x['n']}. [{x['title']}]({x['path'].replace(' ', '%20')})" + ("　★" if x["n"] in r["picked"] else "") for x in r["results"][:100]]
    L += ["", "## これから書くこと" + ("（試走。何も書いていません）" if not r.get("applied") else "（書きました）"), ""]
    if r["kind"] == "index":
        L += [f"新しいノート `{r['target']}` に:", ""] + [f"- {x}" for x in r["preview"]]
    else:
        L += [f"`{r['target']}` の `Related:` に {len(r.get('will_add', []))} 件を足す" + (f"（すでにある・自分自身のため {len(r['skipped'])} 件は足さない）" if r.get("skipped") else ""), ""] + [f"- {x}" for x in r["preview"]]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        do = "--apply" in argv
        force = "--force" in argv
        a = [x for x in argv if x not in ("--md", "--apply", "--force")]
        pick = None
        if "--pick" in a:
            i = a.index("--pick"); pick = a[i + 1]; del a[i:i + 2]
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "undo":
            r = undo(root, force)
            print(json.dumps(r, ensure_ascii=False))
            return 0 if r["ok"] else 1
        if cmd not in ("index", "related") or len(rest) != 2:
            print(__doc__, file=sys.stderr)
            return 2
        r = apply(root, cmd, rest[0], rest[1], pick) if do else plan(root, cmd, rest[0], rest[1], pick)
        print(to_md(r), end="") if md else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
