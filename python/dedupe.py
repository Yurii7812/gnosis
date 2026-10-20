#!/usr/bin/env python3
"""本文の重複の検出と除去(ED07)。

scan [--min N] : vault 全体。(1) 本文がまったく同じノートの組、(2) 複数のノートに同じ段落があるもの。**報告だけ**で何も変えない
                 (統合は `:GnosisMerge` 系、取り消しは `:GnosisMergeUndo`)。
inner NOTE [--apply] : 1 つのノートの中で、同じ段落が繰り返されているのを見つけ、**2 回目以降**を除く。--apply が無ければ見せるだけ。
                 --apply のときは除く前の内容を版として保存する(`versions.py` → `:GnosisVersions restore` で戻せる)。

「段落」= 空行で区切った塊。比べるときは全角半角(NFKC)・大文字小文字・空白の違いを無視する。次は対象外にする:
front matter、``` で囲んだコード、関係ブロック(Related: など)、見出しだけの塊、リンクだけの塊、短い塊(既定 30 文字未満)。

CLI(JSON。--md なら Markdown):
  dedupe.py ROOT scan [--min N] | inner NOTE [--apply] [--min N]
"""
from __future__ import annotations

import json
import os
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tasks as tk  # noqa: E402
import versions as vs  # noqa: E402

REL = {"ParentBranch:", "ChildBranch:", "BranchGroup:", "Group:", "Context:", "Related:", "BackLink:"}
LINKONLY = re.compile(r"^\s*(?:[-*+]\s+)?!?\[[^\]]*\]\([^)]*\)\s*$")


def _norm(s: str) -> str:
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", s).lower())


def _paragraphs(text: str, min_chars: int) -> list[dict]:
    """[{start, end(含む), text, key}]。行番号は 1 始まり。"""
    lines = text.split("\n")
    i = 0
    if lines and lines[0].strip() == "---":
        i = 1
        while i < len(lines) and lines[i].strip() != "---":
            i += 1
        i += 1
    out, cur, fence, rel = [], [], False, False

    def flush(end):
        nonlocal cur
        if cur:
            blk = [x for _, x in cur]
            body = "\n".join(blk)
            if not blk[0].lstrip().startswith("#") and not all(LINKONLY.match(x) for x in blk) and len(_norm(body)) >= min_chars:
                out.append({"start": cur[0][0], "end": cur[-1][0], "text": body, "key": _norm(body)})
        cur = []
    for n in range(i, len(lines)):
        ln = lines[n]
        if ln.lstrip().startswith(("```", "~~~")):
            flush(n)
            fence = not fence
            continue
        if fence:
            continue
        if ln.strip() in REL and ln == ln.lstrip():
            flush(n)
            rel = True
            continue
        if not ln.strip():
            flush(n)
            rel = False
            continue
        if rel:
            continue
        cur.append((n + 1, ln))
    flush(len(lines))
    return out


def scan(root: str | Path, min_chars: int = 30) -> dict:
    root = Path(root).resolve()
    bodies: dict[str, list[str]] = {}
    paras: dict[str, list[dict]] = {}
    for p in tk.iter_notes(root):
        rel = p.relative_to(root).as_posix()
        ps = _paragraphs(p.read_text(encoding="utf-8"), min_chars)
        if not ps:
            continue
        bodies.setdefault("".join(x["key"] for x in ps), []).append(rel)
        seen = set()
        for x in ps:
            if x["key"] in seen:
                continue
            seen.add(x["key"])
            paras.setdefault(x["key"], []).append({"path": rel, "line": x["start"], "text": x["text"]})
    identical = sorted(sorted(v) for v in bodies.values() if len(v) > 1)
    ident_paths = {x for g in identical for x in g}
    shared = []
    for k, v in paras.items():
        if len(v) > 1 and not all(e["path"] in ident_paths for e in v):          # 本文が同じ組の段落は、組として報告済み
            shared.append({"text": v[0]["text"][:200], "chars": len(k), "notes": [{"path": e["path"], "line": e["line"]} for e in v]})
    shared.sort(key=lambda x: (-len(x["notes"]), -x["chars"], x["notes"][0]["path"]))
    return {"identical": identical, "shared": shared[:100], "shared_total": len(shared)}


def inner(root: str | Path, note: str, apply: bool = False, min_chars: int = 30) -> dict:
    root = Path(root).resolve()
    p = (root / note).resolve()
    try:
        rel = p.relative_to(root).as_posix()
    except ValueError:
        raise ValueError("vault の外は扱いません") from None
    if any(x.startswith(".") for x in rel.split("/")) or p.suffix != ".md" or not p.is_file():
        raise ValueError("vault の中のノートを指定してください: " + note)
    text = p.read_text(encoding="utf-8")
    ps = _paragraphs(text, min_chars)
    seen: dict[str, int] = {}
    dup = []
    for x in ps:
        if x["key"] in seen:
            dup.append({"line": x["start"], "end": x["end"], "first_line": seen[x["key"]], "text": x["text"][:120]})
        else:
            seen[x["key"]] = x["start"]
    res = {"note": rel, "duplicates": dup, "applied": False}
    if apply and dup:
        vs.save(root, rel)                                              # 戻せるように、除く前の内容を版として残す
        lines = text.split("\n")
        drop = set()
        for d in dup:
            drop.update(range(d["line"], d["end"] + 1))
            nxt = d["end"] + 1                                          # 段落と一緒に、続く空行 1 つも除いて空行が溜まらないようにする
            if nxt <= len(lines) and not lines[nxt - 1].strip():
                drop.add(nxt)
        new = "\n".join(x for i, x in enumerate(lines, 1) if i not in drop)
        tmp = p.with_name(p.name + ".tmp")
        tmp.write_text(new, encoding="utf-8")
        os.replace(tmp, p)
        res["applied"] = True
        res["removed_lines"] = len(drop)
    return res


def to_md(kind: str, r: dict) -> str:
    l = lambda p: f"[{p}]({p.replace(' ', '%20')})"
    if kind == "scan":
        L = ["# 本文の重複", "", "報告だけです(何も変えていません)。統合は `:GnosisMerge` 系で行います。", "", f"## 本文が同じノート（{len(r['identical'])} 組）", ""]
        L += [f"- {' ・ '.join(l(x) for x in g)}" for g in r["identical"]] or ["なし"]
        L += ["", f"## 複数のノートにある同じ段落（{r['shared_total']} 件" + ("・上位 100 件" if r["shared_total"] > 100 else "") + "）", ""]
        for s in r["shared"]:
            L.append(f"- 「{s['text'].splitlines()[0][:60]}」: " + "・".join(f"{l(e['path'])}:{e['line']}" for e in s["notes"]))
        if not r["shared"]:
            L.append("なし")
        return "\n".join(L) + "\n"
    head = f"# ノート内の重複: {l(r['note'])}"
    L = [head, ""]
    if r["applied"]:
        L += [f"2 回目以降の段落を除きました（{len(r['duplicates'])} 件・{r['removed_lines']} 行）。元に戻すなら `:GnosisVersions restore 1`。", ""]
    elif r["duplicates"]:
        L += ["見つけただけです(まだ除いていません)。除くなら `:GnosisDedupe!`。", ""]
    L += [f"- {d['line']} 行目（{d['first_line']} 行目と同じ）: {d['text'].splitlines()[0][:60]}" for d in r["duplicates"]] or ["繰り返しはありません。"]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        apply = "--apply" in argv
        a = [x for x in argv if x not in ("--md", "--apply")]
        mn = 30
        if "--min" in a:
            i = a.index("--min"); mn = int(a[i + 1]); del a[i:i + 2]
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "scan":
            r = scan(root, mn)
        elif cmd == "inner":
            r = inner(root, rest[0], apply, mn)
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
