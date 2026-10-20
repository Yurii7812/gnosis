#!/usr/bin/env python3
"""知識の探索（XP01 ランダムウォーク・XP02 セレンディピティ・XP03 知識考古学・XP08 ルーレット・XP09 中間概念）。読み取り専用。

ノートは書き換えない。乱数を使うものは `--seed` で再現できる。意味の近さは local_ai（文字 n-gram の TF-IDF）のローカルの近似。

CLI（JSON。--md なら Markdown）:
  explore.py ROOT walk [NOTE] [--steps N] [--seed S]      リンクだけを辿る散歩（行き止まりで止まる）
  explore.py ROOT roulette [any|old|orphan] [--seed S]    ノートを 1 つ引く（古いもの・孤立したものに絞れる）
  explore.py ROOT serendipity NOTE [--k N]                近い内容なのに、リンクでは遠い（3 歩以上／つながりなし）ノート
  explore.py ROOT archaeology [日数]                       長く触っていないが、今も参照されている／最近のノートと近いノート
  explore.py ROOT between NOTE NOTE [--k N]               2 つのノートの間をつなぐ中間概念（経路上のノート・両方に近いノート・共通語）
"""
from __future__ import annotations

import datetime as dt
import json
import random
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gnosis_graph as gg  # noqa: E402
import local_ai as ai  # noqa: E402

REAL = ("link", "context", "related", "parent_branch", "group", "branch_group", "child_branch", "folgezettel")


def _adj(g: gg.Graph) -> dict[str, list[tuple[str, str]]]:
    adj: dict[str, set[tuple[str, str]]] = {n: set() for n in g.nodes}
    for e in g.edges:
        if e.src != e.dst and e.kind in REAL and e.dst in g.nodes and e.src in g.nodes:
            adj[e.src].add((e.dst, e.kind)); adj[e.dst].add((e.src, e.kind))
    return {n: sorted(v) for n, v in adj.items()}


def _find(g: gg.Graph, name: str) -> str:
    if name in g.nodes:
        return name
    for r, n in sorted(g.nodes.items()):
        if r.endswith("/" + name) or n.title == name or Path(r).stem == name:
            return r
    raise ValueError("ノートが見つかりません: " + name)


def _dist(adj, a: str) -> dict[str, int]:
    d = {a: 0}
    q = [a]
    for v in q:
        for w, _ in adj[v]:
            if w not in d:
                d[w] = d[v] + 1; q.append(w)
    return d


def random_walk(root: str | Path, start: str | None = None, steps: int = 8, seed: int | None = None) -> dict:
    g = gg.build(root)
    if not g.nodes:
        raise ValueError("ノートがありません")
    rng = random.Random(seed)
    adj = _adj(g)
    cur = _find(g, start) if start else rng.choice(sorted(n for n in g.nodes if adj[n]) or sorted(g.nodes))
    path = [{"path": cur, "title": g.nodes[cur].title, "via": ""}]
    visited = {cur}
    stopped = ""
    for _ in range(max(0, steps)):
        opts = adj[cur]
        if not opts:
            stopped = "行き止まり（リンクがありません）"
            break
        fresh = [o for o in opts if o[0] not in visited]
        nxt, kind = rng.choice(fresh or opts)                 # まだ行っていないノートを優先。無ければ戻ってもよい
        path.append({"path": nxt, "title": g.nodes[nxt].title, "via": kind})
        visited.add(nxt)
        cur = nxt
    return {"seed": seed, "steps": len(path) - 1, "path": path, "stopped": stopped, "distinct": len(visited)}


def roulette(root: str | Path, mode: str = "any", seed: int | None = None) -> dict:
    root = Path(root).resolve()
    g = gg.build(root)
    adj = _adj(g)
    pool = sorted(g.nodes)
    if mode == "orphan":
        pool = [n for n in pool if not adj[n]]
    elif mode == "old":
        mt = {n: (root / n).stat().st_mtime for n in pool if (root / n).exists()}
        ordered = sorted(mt, key=lambda n: (mt[n], n))
        pool = ordered[:max(1, len(ordered) // 4)]            # 古いほうの 4 分の 1
    elif mode != "any":
        raise ValueError("種類は any / old / orphan のどれかです")
    if not pool:
        return {"mode": mode, "note": None, "message": "条件に合うノートがありません"}
    pick = random.Random(seed).choice(pool)
    return {"mode": mode, "seed": seed, "note": {"path": pick, "title": g.nodes[pick].title}, "candidates": len(pool)}


def serendipity(root: str | Path, note: str, k: int = 5, far: int = 3) -> dict:
    """内容は近いのに、リンクでは遠い（far 歩以上、またはつながっていない）ノート。意外な近さの候補。"""
    g = gg.build(root)
    rel = _find(g, note)
    adj = _adj(g)
    dist = _dist(adj, rel)
    c = ai.Corpus.build(root)
    out = []
    for r, s in c.score(c.docs[rel]["vec"], {rel})[:60]:
        d = dist.get(r)
        if d is not None and d < far:
            continue
        out.append({"path": r, "title": c.docs[r]["title"], "score": round(s, 3), "distance": d, "shared": c.shared_terms(rel, r, 4),
                    "why": "リンクではつながっていないが内容が近い" if d is None else f"リンクでは {d} 歩離れているが内容が近い"})
        if len(out) >= k:
            break
    return {"note": rel, "far": far, "candidates": out, "note_text": "文字の近さによる候補です。偶然の一致もあります。"}


def archaeology(root: str | Path, days: int = 365, today: dt.date | None = None, k: int = 10) -> dict:
    """長く触っていないノートのうち、(1) 最近更新されたノートから今もリンクされている、(2) 最近のノートと内容が近い、ものを再発見の候補に。"""
    root = Path(root).resolve()
    today = today or dt.date.today()
    g = gg.build(root)
    age = {n: (today - dt.date.fromtimestamp((root / n).stat().st_mtime)).days for n in g.nodes if (root / n).exists()}
    old = {n for n, a in age.items() if a >= days}
    recent = {n for n, a in age.items() if a < 90}
    reasons: dict[str, list[str]] = {}
    for e in g.edges:
        if e.kind == "link" and e.dst in old and e.src in recent:
            reasons.setdefault(e.dst, []).append(f"最近更新した「{g.nodes[e.src].title}」から今もリンクされている")
    if recent and old:
        c = ai.Corpus.build(root)
        for n in sorted(recent)[:50]:
            for r, s in c.score(c.docs[n]["vec"], {n})[:5]:
                if r in old and s >= 0.15:
                    reasons.setdefault(r, []).append(f"最近のノート「{g.nodes[n].title}」と内容が近い（{round(s, 2)}）")
    out = [{"path": n, "title": g.nodes[n].title, "age_days": age[n], "reasons": sorted(set(rs))[:3]} for n, rs in reasons.items()]
    out.sort(key=lambda x: (-len(x["reasons"]), -x["age_days"], x["path"]))
    return {"days": days, "old_notes": len(old), "rediscover": out[:k]}


def between(root: str | Path, a: str, b: str, k: int = 5) -> dict:
    g = gg.build(root)
    A, B = _find(g, a), _find(g, b)
    sp = g.shortest_path(A, B, kinds=REAL)
    via = [{"path": n, "title": g.nodes[n].title, "edge": kind} for n, kind in (sp or [])[1:-1]]
    c = ai.Corpus.build(root)
    both = []
    for r, d in c.docs.items():
        if r in (A, B):
            continue
        sa = sum(c.docs[A]["vec"].get(t, 0.0) * v for t, v in d["vec"].items())
        sb = sum(c.docs[B]["vec"].get(t, 0.0) * v for t, v in d["vec"].items())
        m = min(sa, sb)
        if m > 0.05:
            both.append({"path": r, "title": d["title"], "score": round(m, 3), "to_a": round(sa, 3), "to_b": round(sb, 3)})
    both.sort(key=lambda x: (-x["score"], x["path"]))
    return {"a": A, "b": B, "link_path": [g.nodes[n].title for n, _ in sp] if sp else None, "via_links": via,
            "close_to_both": both[:k], "shared_terms": c.shared_terms(A, B, 8),
            "note_text": "経路はリンクの事実、「両方に近いノート」は文字の近さによる候補です。"}


def _l(path, title):
    return f"[{title}]({path.replace(' ', '%20')})"


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    if kind == "walk":
        L = ["# 散歩" + (f"（seed {r['seed']}）" if r["seed"] is not None else ""), ""]
        for i, p in enumerate(r["path"]):
            L.append(f"{i}. " + (f"〔{p['via']}〕→ " if p["via"] else "") + _l(p["path"], p["title"]))
        L += ["", f"{r['steps']} 歩・{r['distinct']} ノート" + (f"・{r['stopped']}" if r["stopped"] else "")]
    elif kind == "roulette":
        L = ["# ルーレット", ""] + ([f"- {_l(r['note']['path'], r['note']['title'])}（候補 {r['candidates']} 件から）"] if r["note"] else [r["message"]])
    elif kind == "serendipity":
        L = [f"# 意外な近さ: {r['note']}", ""] + [f"- {_l(x['path'], x['title'])} — {x['why']}（{x['score']}・共通: {'・'.join(x['shared'])}）" for x in r["candidates"]] + (["- なし"] if not r["candidates"] else []) + ["", r["note_text"]]
    elif kind == "archaeology":
        L = [f"# 知識考古学（{r['days']} 日以上触っていないノート {r['old_notes']} 件から）", ""] + [f"- {_l(x['path'], x['title'])} — {x['age_days']} 日: " + " / ".join(x["reasons"]) for x in r["rediscover"]] + (["- 候補なし"] if not r["rediscover"] else [])
    elif kind == "between":
        L = [f"# 中間概念: {r['a']} 〜 {r['b']}", "", "## リンクの経路", ""]
        L.append(" → ".join(r["link_path"]) if r["link_path"] else "つながっていません")
        L += ["", "## 両方に近いノート", ""] + [f"- {_l(x['path'], x['title'])} — {x['score']}（A {x['to_a']} / B {x['to_b']}）" for x in r["close_to_both"]] + (["- なし"] if not r["close_to_both"] else [])
        L += ["", "## 共通の語", "", "・".join(r["shared_terms"]) or "なし", "", r["note_text"]]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        opts = {}
        rest = []
        it = iter(argv)
        for x in it:
            if x == "--md":
                continue
            if x in ("--steps", "--seed", "--k"):
                opts[x[2:]] = int(next(it))
            else:
                rest.append(x)
        root, cmd, a = rest[0], rest[1], rest[2:]
        seed = opts.get("seed")
        if cmd == "walk":
            r = random_walk(root, a[0] if a else None, opts.get("steps", 8), seed)
        elif cmd == "roulette":
            r = roulette(root, a[0] if a else "any", seed)
        elif cmd == "serendipity":
            r = serendipity(root, a[0], opts.get("k", 5))
        elif cmd == "archaeology":
            r = archaeology(root, int(a[0]) if a else 365)
        elif cmd == "between":
            r = between(root, a[0], a[1], opts.get("k", 5))
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
