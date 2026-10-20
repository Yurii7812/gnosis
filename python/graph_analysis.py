#!/usr/bin/env python3
"""グラフの数学的分析（GR01〜GR14）。`gnosis_graph.py` の型付き・有向・多重のグラフを読み、何も書き換えない。

数学的な評価は意味的な価値と同じではない。ここで出すのは「構造の事実」（つながり方）で、重要・不要の判断ではない。
一般リンク・Index 参照・BranchGroup・Context・Related・バックリンク・Folgezettel の系譜は、潰さずに種類ごとに扱う。

  analysis.py ROOT hubs [N]              GR01 つながりの多いノート（種類別の次数つき）
  analysis.py ROOT central [N]           GR08 中心性（次数・媒介・近接）
  analysis.py ROOT bridges [N]           GR02 異なる領域をつなぐ橋渡しノート（コミュニティをまたぐ媒介）
  analysis.py ROOT communities           GR03 コミュニティ（ラベル伝播・決定的）と modularity
  analysis.py ROOT islands               GR04 孤立ノード・孤立した小さな群
  analysis.py ROOT reach INDEX           GR06 INDEX から辿れる範囲と、辿れないノート
  analysis.py ROOT cycles                GR07 階層（ParentBranch など）の不正な循環と、リンクの循環（ふつうは正常）
  analysis.py ROOT density               GR09 領域（コミュニティ）ごとの接続密度と、領域どうしの結びつき
  analysis.py ROOT compare A B           GR10 2 つの索引から辿れる範囲の構造比較
  analysis.py ROOT growth                GR11 Folgezettel の知識発展ツリー（部分木の大きさ・深さ・月ごとの増え方）
  analysis.py ROOT kinds                 GR12 関係の種類の内訳
  analysis.py ROOT query 'パターン'       GR13 パターン探索（例: ?a -[parent_branch]-> ?b -[group]-> ?c）
  analysis.py ROOT paths A B [K]         GR14 A から B への複数の（種類の異なる）経路
  analysis.py ROOT report                上をまとめた Markdown のレポート
"""
from __future__ import annotations

import json
import math
import re
import sys
from collections import Counter, defaultdict, deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import folgezettel as fz  # noqa: E402
import gnosis_graph as gg  # noqa: E402

# 階層・構造を表す辺（派生の backlink・folgezettel は構造の分析から外す。folgezettel は GR11 で別に使う）
REAL = ("group", "parent_branch", "branch_group", "child_branch", "context", "related", "link")
# 「親 → 子」の向きに揃える（INDEX から辿る・階層の循環を調べる）
def down_edges(g: gg.Graph) -> dict[str, set[str]]:
    d: dict[str, set[str]] = {n: set() for n in g.nodes}
    for e in g.edges:
        if e.derived:
            continue
        if e.kind in ("branch_group", "child_branch", "link", "related", "context"):
            d[e.src].add(e.dst)
        elif e.kind in ("parent_branch", "group"):   # 子が親を指す → 親から子へ
            d[e.dst].add(e.src)
    return d


def undirected(g: gg.Graph, kinds=REAL) -> dict[str, set[str]]:
    a: dict[str, set[str]] = {n: set() for n in g.nodes}
    for e in g.edges:
        if e.kind in kinds and not e.derived and e.src != e.dst:
            a[e.src].add(e.dst)
            a[e.dst].add(e.src)
    return a


def _title(g, n): return g.nodes[n].title


# ---- GR01 ハブ ----
def hubs(g: gg.Graph, n: int = 10) -> list[dict]:
    deg_out, deg_in = Counter(), Counter()
    kinds: dict[str, Counter] = defaultdict(Counter)
    for e in g.edges:
        if e.derived or e.src == e.dst:
            continue
        deg_out[e.src] += 1
        deg_in[e.dst] += 1
        kinds[e.src][e.kind] += 1
        kinds[e.dst][e.kind] += 1
    rows = [{"id": x, "title": _title(g, x), "degree": deg_out[x] + deg_in[x], "out": deg_out[x], "in": deg_in[x], "kinds": dict(kinds[x])} for x in g.nodes]
    return sorted((r for r in rows if r["degree"]), key=lambda r: (-r["degree"], r["id"]))[:n]


# ---- GR08 中心性 ----
def betweenness(adj: dict[str, set[str]], samples: int | None = None) -> dict[str, float]:
    """Brandes（重みなし・無向）。ノードが多いときは samples 個の始点だけで近似する（決定的）。"""
    nodes = sorted(adj)
    cb = dict.fromkeys(nodes, 0.0)
    srcs = nodes if not samples or samples >= len(nodes) else nodes[:: max(1, len(nodes) // samples)][:samples]
    for s in srcs:
        stack, pred = [], {v: [] for v in nodes}
        sigma = dict.fromkeys(nodes, 0); sigma[s] = 1
        dist = dict.fromkeys(nodes, -1); dist[s] = 0
        q = deque([s])
        while q:
            v = q.popleft(); stack.append(v)
            for w in sorted(adj[v]):
                if dist[w] < 0:
                    dist[w] = dist[v] + 1; q.append(w)
                if dist[w] == dist[v] + 1:
                    sigma[w] += sigma[v]; pred[w].append(v)
        delta = dict.fromkeys(nodes, 0.0)
        while stack:
            w = stack.pop()
            for v in pred[w]:
                delta[v] += sigma[v] / sigma[w] * (1 + delta[w])
            if w != s:
                cb[w] += delta[w]
    scale = (len(nodes) / len(srcs)) if srcs else 1
    return {v: c * scale / 2 for v, c in cb.items()}      # 無向なので 2 重に数えた分を割る


def closeness(adj: dict[str, set[str]]) -> dict[str, float]:
    out = {}
    for s in adj:
        dist = {s: 0}; q = deque([s])
        while q:
            v = q.popleft()
            for w in adj[v]:
                if w not in dist:
                    dist[w] = dist[v] + 1; q.append(w)
        tot = sum(dist.values())
        out[s] = (len(dist) - 1) / tot if tot and len(dist) > 1 else 0.0     # 同じ連結成分の中での近接
    return out


def central(g: gg.Graph, n: int = 10, samples: int | None = 300) -> list[dict]:
    adj = undirected(g)
    bt = betweenness(adj, samples if len(adj) > samples * 2 else None)
    cl = closeness(adj)
    rows = [{"id": x, "title": _title(g, x), "degree": len(adj[x]), "betweenness": round(bt[x], 3), "closeness": round(cl[x], 4)} for x in adj]
    return sorted((r for r in rows if r["degree"]), key=lambda r: (-r["betweenness"], -r["degree"], r["id"]))[:n]


# ---- GR03 コミュニティ ----
def communities(g: gg.Graph, iters: int = 30) -> dict:
    """ラベル伝播（決定的: 辞書順に更新・同数なら小さいラベル）。{groups:[[id…]], membership:{id: 番号}, modularity}"""
    adj = undirected(g)
    label = {n: n for n in adj}
    order = sorted(adj)
    for _ in range(iters):
        changed = False
        for n in order:
            if not adj[n]:
                continue
            cnt = Counter(label[m] for m in adj[n])
            best = min(cnt.items(), key=lambda kv: (-kv[1], kv[0]))[0]
            if cnt[label[n]] < cnt[best] or (cnt[label[n]] == cnt[best] and best < label[n]):
                if label[n] != best:
                    label[n] = best; changed = True
        if not changed:
            break
    groups: dict[str, list[str]] = defaultdict(list)
    for n in order:
        groups[label[n]].append(n)
    ordered = sorted(groups.values(), key=lambda m: (-len(m), m[0]))
    mem = {n: i for i, m in enumerate(ordered) for n in m}
    # modularity
    m2 = sum(len(a) for a in adj.values())
    q = 0.0
    if m2:
        for i, mbrs in enumerate(ordered):
            inner = sum(1 for a in mbrs for b in adj[a] if mem[b] == i)
            deg = sum(len(adj[a]) for a in mbrs)
            q += inner / m2 - (deg / m2) ** 2
    return {"groups": ordered, "membership": mem, "modularity": round(q, 4)}


# ---- GR02 橋渡し ----
def bridges(g: gg.Graph, n: int = 10) -> list[dict]:
    """異なるコミュニティの近傍を持つノート。媒介中心性が高く、自分のコミュニティの外へ複数の領域に辺があるものを上位に。"""
    adj = undirected(g)
    com = communities(g)["membership"]
    bt = betweenness(adj, 300 if len(adj) > 600 else None)
    rows = []
    for x in adj:
        other = Counter(com[m] for m in adj[x] if com[m] != com[x])
        if not other:
            continue
        rows.append({"id": x, "title": _title(g, x), "communities_touched": len(other) + 1, "outside_links": sum(other.values()),
                     "betweenness": round(bt[x], 3), "from": com[x], "to": sorted(other)})
    return sorted(rows, key=lambda r: (-r["communities_touched"], -r["betweenness"], r["id"]))[:n]


# ---- GR04 孤立 ----
def islands(g: gg.Graph, small: int = 3) -> dict:
    adj = undirected(g)
    comps = g.components(kinds=set(REAL))
    comps = [c for c in comps]
    sizes = sorted((len(c) for c in comps), reverse=True)
    iso = [c[0] for c in comps if len(c) == 1]
    groups = [c for c in comps if 1 < len(c) <= small]
    main = max(comps, key=len) if comps else []
    return {"isolated": sorted(iso), "small_groups": [sorted(c) for c in groups], "main_size": len(main), "components": len(comps), "sizes": sizes[:10]}


# ---- GR06 到達可能性 ----
def reach(g: gg.Graph, start: str) -> dict:
    rel = start if start in g.nodes else next((k for k in g.nodes if k.endswith("/" + start) or g.nodes[k].title == start), None)
    if rel is None:
        raise ValueError("ノートが見つかりません: " + start)
    d = down_edges(g)
    depth = {rel: 0}
    q = deque([rel])
    while q:
        v = q.popleft()
        for w in sorted(d[v]):
            if w not in depth:
                depth[w] = depth[v] + 1; q.append(w)
    unreached = sorted(n for n in g.nodes if n not in depth)
    layers = Counter(depth.values())
    return {"start": rel, "reached": len(depth), "total": len(g.nodes), "unreached": unreached, "max_depth": max(depth.values()),
            "layers": {str(k): layers[k] for k in sorted(layers)}, "depth": depth}


# ---- GR07 循環 ----
def _scc(nodes, succ) -> list[list[str]]:
    index, low, on, st, out, idx = {}, {}, set(), [], [], [0]
    def strong(v):
        index[v] = low[v] = idx[0]; idx[0] += 1; st.append(v); on.add(v)
        for w in sorted(succ.get(v, ())):
            if w not in index:
                strong(w); low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = st.pop(); on.discard(w); comp.append(w)
                if w == v:
                    break
            out.append(sorted(comp))
    sys.setrecursionlimit(max(10000, len(nodes) * 4))
    for v in sorted(nodes):
        if v not in index:
            strong(v)
    return out


def cycles(g: gg.Graph) -> dict:
    """階層（親子の関係: ParentBranch・BranchGroup・ChildBranch・Group）の循環は不正。一般リンクなどの循環は、ふつうは正常（相互参照）。"""
    hier: dict[str, set[str]] = {n: set() for n in g.nodes}
    for e in g.edges:
        if e.derived:
            continue
        if e.kind in ("branch_group", "child_branch"):
            hier[e.src].add(e.dst)
        elif e.kind in ("parent_branch",):
            hier[e.dst].add(e.src)
    bad = [c for c in _scc(g.nodes, hier) if len(c) > 1 or c[0] in hier.get(c[0], ())]
    allg: dict[str, set[str]] = {n: set() for n in g.nodes}
    for e in g.edges:
        if not e.derived and e.kind in ("link", "related", "context") and e.src != e.dst:
            allg[e.src].add(e.dst)
    benign = [c for c in _scc(g.nodes, allg) if len(c) > 1]
    return {"invalid_hierarchy_cycles": bad, "link_cycles": benign[:20], "link_cycle_groups": len(benign)}


# ---- GR09 密度 ----
def density(g: gg.Graph) -> dict:
    c = communities(g)
    adj = undirected(g)
    mem = c["membership"]
    rows = []
    for i, m in enumerate(c["groups"]):
        n = len(m)
        inner = sum(1 for a in m for b in adj[a] if mem[b] == i) // 2
        possible = n * (n - 1) // 2
        rows.append({"community": i, "size": n, "internal_edges": inner, "density": round(inner / possible, 4) if possible else 0.0,
                     "sample": [_title(g, x) for x in m[:3]]})
    between: Counter = Counter()
    for a in adj:
        for b in adj[a]:
            if a < b and mem[a] != mem[b]:
                between[(min(mem[a], mem[b]), max(mem[a], mem[b]))] += 1
    return {"communities": rows, "between": [{"a": a, "b": b, "edges": n} for (a, b), n in between.most_common(10)],
            "overall_density": round(sum(len(v) for v in adj.values()) / (len(adj) * (len(adj) - 1)), 5) if len(adj) > 1 else 0.0}


# ---- GR10 索引の比較 ----
def compare(g: gg.Graph, a: str, b: str) -> dict:
    ra, rb = reach(g, a), reach(g, b)
    sa, sb = set(ra["depth"]), set(rb["depth"])
    d = down_edges(g)
    def branching(depth):
        internal = [n for n in depth if any(w in depth for w in d[n])]
        return round(sum(len([w for w in d[n] if w in depth]) for n in internal) / len(internal), 3) if internal else 0.0
    inter = sa & sb
    return {"a": {"index": ra["start"], "size": len(sa), "max_depth": ra["max_depth"], "layers": ra["layers"], "avg_branching": branching(ra["depth"])},
            "b": {"index": rb["start"], "size": len(sb), "max_depth": rb["max_depth"], "layers": rb["layers"], "avg_branching": branching(rb["depth"])},
            "shared": sorted(inter), "only_a": len(sa - sb), "only_b": len(sb - sa),
            "jaccard": round(len(inter) / len(sa | sb), 4) if sa | sb else 0.0}


# ---- GR11 Folgezettel の知識発展 ----
def growth(g: gg.Graph) -> dict:
    notes, groups = g.fz_index()
    ids = sorted(set(notes) | set(groups), key=fz.natural_key)
    kids: dict[str, list[str]] = defaultdict(list)
    tops = []
    for i in ids:
        p = fz.parent_id(i)
        (kids[p].append(i) if p in ids else tops.append(i))
    size: dict[str, int] = {}
    def sub(i):
        size[i] = 1 + sum(sub(c) for c in kids[i])
        return size[i]
    for t in tops:
        sub(t)
    def depth(i): return 1 + max((depth(c) for c in kids[i]), default=0)
    def title(i):
        ps = notes.get(i) or groups.get(i) or []
        return g.nodes[ps[0]].title if ps else ""
    def month(i):
        ps = notes.get(i) or groups.get(i) or []
        return (g.nodes[ps[0]].time or "")[:7] if ps else ""
    branches = [{"id": t, "title": title(t), "size": size[t], "depth": depth(t), "children": len(kids[t])} for t in tops]
    timeline: dict[str, Counter] = defaultdict(Counter)
    for i in ids:
        top = i
        while fz.parent_id(top) in ids:
            top = fz.parent_id(top)
        if month(i):
            timeline[month(i)][top] += 1
    return {"branches": sorted(branches, key=lambda r: (-r["size"], fz.natural_key(r["id"]))), "total_ids": len(ids),
            "deepest": max((depth(t) for t in tops), default=0),
            "timeline": {m: dict(c) for m, c in sorted(timeline.items())}}


# ---- GR12 関係の種類 ----
def kinds(g: gg.Graph) -> dict:
    cnt = Counter(e.kind for e in g.edges)
    pair: dict[tuple[str, str], set[str]] = defaultdict(set)
    for e in g.edges:
        if not e.derived:
            pair[(min(e.src, e.dst), max(e.src, e.dst))].add(e.kind)
    multi = Counter(tuple(sorted(k)) for k in pair.values() if len(k) > 1)
    return {"by_kind": dict(cnt.most_common()), "derived": sum(1 for e in g.edges if e.derived),
            "notes_pairs_with_several_kinds": sum(multi.values()), "common_combinations": [{"kinds": list(k), "pairs": n} for k, n in multi.most_common(5)]}


# ---- GR13 パターン探索 ----
NODE_RE = re.compile(r"\?(\w+)(?:\{([^}]*)\})?|([^\s\[\]\-<>]+\.md)")
EDGE_RE = re.compile(r"(<)?-\[([\w|]+)\]-(>)?")


def _node_ok(g, n, cond: str) -> bool:
    for part in [p for p in (cond or "").split(",") if p.strip()]:
        k, _, v = part.partition("~")
        k = k.strip(); v = v.strip()
        val = {"title": g.nodes[n].title, "path": n, "fz": g.nodes[n].fz, "attr": g.nodes[n].attribute}.get(k, "")
        if k == "group":
            if str(g.nodes[n].is_group).lower() != v.lower():
                return False
        elif not re.search(v, val, re.I):
            return False
    return True


def query(g: gg.Graph, pattern: str, limit: int = 200) -> list[dict]:
    """`?a -[kind1|kind2]-> ?b <-[kind]- ?c{title~正規表現} ` のような連なりを探す。ノードは ?名{条件} か ノート.md。"""
    toks = []
    pos = 0
    pat = pattern.strip()
    while pos < len(pat):
        while pos < len(pat) and pat[pos].isspace():
            pos += 1
        if pos >= len(pat):
            break
        m = EDGE_RE.match(pat, pos)
        if m and (m.group(1) or m.group(3)):
            toks.append(("edge", m)); pos = m.end(); continue
        m = NODE_RE.match(pat, pos)
        if not m:
            raise ValueError("パターンが読めません（位置 %d）: %s" % (pos, pat[pos:pos + 20]))
        toks.append(("node", m)); pos = m.end()
    if not toks or toks[0][0] != "node" or len(toks) % 2 == 0:
        raise ValueError("パターンは ノード 辺 ノード … の形にしてください")
    adj_out: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for e in g.edges:
        if not e.derived or e.kind == "folgezettel":
            adj_out[e.src].append((e.dst, e.kind))
    adj_in: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for e in g.edges:
        if not e.derived or e.kind == "folgezettel":
            adj_in[e.dst].append((e.src, e.kind))
    results: list[dict] = []
    def cands(m):
        if m.group(3):
            f = m.group(3)
            return [n for n in g.nodes if n == f or n.endswith("/" + f)]
        return [n for n in sorted(g.nodes) if _node_ok(g, n, m.group(2))]
    def walk(i, binding, path):
        if len(results) >= limit:
            return
        if i >= len(toks):
            results.append({"vars": dict(binding), "path": list(path)}); return
        ekind, em = toks[i]
        nkind, nm = toks[i + 1]
        kinds_ = em.group(2).split("|")
        backward = bool(em.group(1)) and not em.group(3)
        cur = path[-1]
        for nxt, k in sorted((adj_in if backward else adj_out)[cur]):
            if k not in kinds_:
                continue
            if nm.group(3):
                if not (nxt == nm.group(3) or nxt.endswith("/" + nm.group(3))):
                    continue
            else:
                if not _node_ok(g, nxt, nm.group(2)):
                    continue
                v = nm.group(1)
                if v in binding and binding[v] != nxt:
                    continue
            b2 = dict(binding)
            if nm.group(1):
                b2[nm.group(1)] = nxt
            walk(i + 2, b2, path + [nxt])
    first = toks[0][1]
    for n in cands(first):
        walk(1, {first.group(1): n} if first.group(1) else {}, [n])
    return results


# ---- GR14 複数の経路 ----
def _bfs_path(adj, a, b, banned_nodes=frozenset(), banned_edges=frozenset()):
    prev = {a: None}; q = deque([a])
    while q:
        v = q.popleft()
        if v == b:
            break
        for w, k in adj[v]:
            if w in prev or w in banned_nodes or (v, w) in banned_edges or (w, v) in banned_edges:
                continue
            prev[w] = (v, k); q.append(w)
    if b not in prev:
        return None
    path = [(b, prev[b][1] if prev[b] else "")]
    while path[-1][0] != a:
        v = prev[path[-1][0]][0]
        path.append((v, prev[v][1] if prev[v] else ""))
    return list(reversed(path))


def paths(g: gg.Graph, a: str, b: str, k: int = 3) -> list[dict]:
    """A から B への、重ならない複数の経路（Yen 法・無向・種類つき）。経路ごとの辺の種類の並びを出す。"""
    adj: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for e in g.edges:
        if e.src != e.dst and (not e.derived or e.kind == "folgezettel"):
            adj[e.src].append((e.dst, e.kind)); adj[e.dst].append((e.src, e.kind))
    for n in g.nodes:
        adj.setdefault(n, [])
    for n in adj:
        adj[n] = sorted(set(adj[n]))
    A = a if a in g.nodes else next((n for n in g.nodes if g.nodes[n].title == a or n.endswith("/" + a)), None)
    B = b if b in g.nodes else next((n for n in g.nodes if g.nodes[n].title == b or n.endswith("/" + b)), None)
    if A is None or B is None:
        raise ValueError("ノートが見つかりません")
    first = _bfs_path(adj, A, B)
    if not first:
        return []
    found = [first]
    cand: list[list[tuple[str, str]]] = []
    while len(found) < k:
        last = found[-1]
        for i in range(len(last) - 1):
            spur = last[i][0]
            root = [x[0] for x in last[: i + 1]]
            banned_e = set()
            for p in found:
                if [x[0] for x in p[: i + 1]] == root and len(p) > i + 1:
                    banned_e.add((p[i][0], p[i + 1][0]))
            sp = _bfs_path(adj, spur, B, banned_nodes=frozenset(root[:-1]), banned_edges=frozenset(banned_e))
            if sp:
                total = last[: i + 1] + sp[1:]              # 共通の根（分岐点まで）に、分岐点から先の経路をつなぐ（辺の種類は元のまま）
                if total not in cand and total not in found:
                    cand.append(total)
        if not cand:
            break
        cand.sort(key=lambda p: (len(p), [x[0] for x in p]))
        found.append(cand.pop(0))
    out = []
    for p in found:
        out.append({"length": len(p) - 1, "nodes": [x[0] for x in p], "titles": [_title(g, x[0]) for x in p], "kinds": [x[1] for x in p[1:]],
                    "distinct_kinds": sorted({x[1] for x in p[1:]})})
    return out


def report(g: gg.Graph, top: int = 8) -> str:
    """分析のまとめを Markdown で。構造の事実を並べるだけで、重要・不要の判断はしない（原本 §5 GR の注意）。"""
    L = ["# グラフ分析", "", f"ノート {len(g.nodes)} 件・関係 {sum(1 for e in g.edges if not e.derived)} 本（派生を除く）。",
         "数学的な指標は、つながり方の事実です。ノートの価値の大小を表すものではありません。", ""]
    h = hubs(g, top)
    L += ["## つながりの多いノート（ハブ）", ""] + [f"- [{x['title']}]({x['id'].replace(' ', '%20')}) — 次数 {x['degree']}（出 {x['out']}・入 {x['in']}）" for x in h] + [""]
    b = bridges(g, top)
    L += ["## 異なる領域をつなぐノート", ""] + ([f"- [{x['title']}]({x['id'].replace(' ', '%20')}) — {x['communities_touched']} 領域に接する・媒介 {x['betweenness']}" for x in b] or ["- なし"]) + [""]
    c = communities(g)
    L += [f"## コミュニティ（{len(c['groups'])} 個・modularity {c['modularity']}）", ""]
    for i, m in enumerate(c["groups"][:top]):
        L.append(f"- 領域 {i + 1}: {len(m)} 件（例: " + "・".join(g.nodes[x].title for x in m[:3]) + "）")
    L.append("")
    isl = islands(g)
    L += ["## 孤立", "", f"- 孤立したノート: {len(isl['isolated'])} 件" + ("（" + "・".join(g.nodes[x].title for x in isl["isolated"][:5]) + "…）" if isl["isolated"] else ""),
          f"- 小さな孤立した群: {len(isl['small_groups'])} 個", ""]
    cy = cycles(g)
    L += ["## 循環", "", f"- 階層（親子）の不正な循環: {len(cy['invalid_hierarchy_cycles'])} 件" + ("（要確認: " + " / ".join(" ↔ ".join(g.nodes[x].title for x in grp) for grp in cy["invalid_hierarchy_cycles"][:3]) + "）" if cy["invalid_hierarchy_cycles"] else ""),
          f"- リンクの循環（相互参照。ふつうは正常）: {cy['link_cycle_groups']} 群", ""]
    k = kinds(g)
    L += ["## 関係の種類", ""] + [f"- {name}: {n}" for name, n in k["by_kind"].items()] + [""]
    gr = growth(g)
    if gr["branches"]:
        L += ["## Folgezettel の枝", ""] + [f"- {x['id']} {x['title']} — {x['size']} 件・深さ {x['depth']}" for x in gr["branches"][:top]] + [""]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        if len(argv) < 2:
            print(__doc__, file=sys.stderr); return 2
        g = gg.build(argv[0])
        c, a = argv[1], argv[2:]
        num = lambda i, d: int(a[i]) if len(a) > i and a[i].isdigit() else d
        if c == "report":
            print(report(g), end="")
            return 0
        res = {"hubs": lambda: hubs(g, num(0, 10)), "central": lambda: central(g, num(0, 10)), "bridges": lambda: bridges(g, num(0, 10)),
               "communities": lambda: {k: v for k, v in communities(g).items() if k != "membership"}, "islands": lambda: islands(g),
               "reach": lambda: {k: v for k, v in reach(g, a[0]).items() if k != "depth"}, "cycles": lambda: cycles(g), "density": lambda: density(g),
               "compare": lambda: compare(g, a[0], a[1]), "growth": lambda: growth(g), "kinds": lambda: kinds(g),
               "query": lambda: query(g, a[0]), "paths": lambda: paths(g, a[0], a[1], num(2, 3))}.get(c)
        if res is None:
            print(__doc__, file=sys.stderr); return 2
        print(json.dumps(res(), ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
