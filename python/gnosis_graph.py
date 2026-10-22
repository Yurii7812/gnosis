#!/usr/bin/env python3
"""vault の関係を「型付き・向き付き・多重」のグラフとして読む共通層（読み取り専用）。

`\\A` のグラフ・Folgezettel ナビ、整合性検査、到達可能性・最短経路などの分析が同じものを使う。
ノートも索引も書き換えない。派生データなので、いつでも vault から作り直せる。

辺（src → dst）は src のファイルに書かれている向きのまま持つ。種類 kind:
  group         … Group:（src が属するグループ）
  parent_branch … ParentBranch:（src の親）
  branch_group  … BranchGroup:（src の子として並べたもの）
  child_branch  … ChildBranch:（旧形式。src の子）
  context       … Context:（src の文脈）
  related       … Related:
  backlink      … BackLink:（派生。他ノートの記述から同期が作る）
  link          … 本文中のリンク
  folgezettel   … 番号の親子（子 → 親。派生。同じ ID のグループ以外のノートへ）
種類を無条件に 1 本へ潰さない。何で結ばれているかが分かるように kind を残す（原本 §5 GR）。

CLI（JSON を標準出力へ）:
  gnosis_graph.py check ROOT            壊れたリンク・重複／抜けた Folgezettel・孤立ノート
  gnosis_graph.py graph ROOT            ノードと辺（`\\A` のグラフ表示用）
  gnosis_graph.py path ROOT A B         A から B への最短経路（辺の向きは無視、種類つき）
  gnosis_graph.py fz ROOT [ID|FILE]     Folgezettel の木、または 1 つの番号の親・兄弟・子・前後
"""
from __future__ import annotations

import json
import posixpath
import re
import sys
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import folgezettel as fz  # noqa: E402
import note_format_v2 as nf  # noqa: E402

KINDS = ("group", "parent_branch", "branch_group", "child_branch", "context", "related", "backlink", "link", "folgezettel")
_SECTIONS = (("group", "group"), ("pbranch", "parent_branch"), ("cbranch", "child_branch"),
             ("ctx", "context"), ("related", "related"), ("back", "backlink"))


@dataclass
class Node:
    id: str          # vault からの相対パス（/ 区切り）
    title: str
    fz: str = ""     # Folgezettel ID（無ければ ""）
    is_group: bool = False
    attribute: str = ""
    time: str = ""   # front matter の time:（作成日時。成長の分析に使う）


@dataclass
class Edge:
    src: str
    dst: str
    kind: str
    derived: bool = False


@dataclass
class Graph:
    root: Path
    nodes: dict[str, Node] = field(default_factory=dict)
    edges: list[Edge] = field(default_factory=list)
    broken: list[dict] = field(default_factory=list)  # {src, target, kind}

    # --- 近傍 ---
    def adjacency(self, kinds=None, undirected: bool = True) -> dict[str, list[tuple[str, str]]]:
        adj: dict[str, list[tuple[str, str]]] = {n: [] for n in self.nodes}
        for e in self.edges:
            if kinds and e.kind not in kinds:
                continue
            adj[e.src].append((e.dst, e.kind))
            if undirected:
                adj[e.dst].append((e.src, e.kind))
        return adj

    def shortest_path(self, a: str, b: str, kinds=None, undirected: bool = True) -> list[tuple[str, str]] | None:
        """a→b の最短経路 [(ノード, そこへ来た辺の種類), …]（先頭は (a, "")）。無ければ None。"""
        if a not in self.nodes or b not in self.nodes:
            return None
        adj = self.adjacency(kinds, undirected)
        prev: dict[str, tuple[str, str]] = {}
        seen = {a}
        q = deque([a])
        while q:
            cur = q.popleft()
            if cur == b:
                break
            for nxt, kind in adj[cur]:
                if nxt not in seen:
                    seen.add(nxt)
                    prev[nxt] = (cur, kind)
                    q.append(nxt)
        if b not in seen:
            return None
        path = [(b, prev[b][1] if b in prev else "")]
        cur = b
        while cur != a:
            cur = prev[cur][0]
            path.append((cur, prev[cur][1] if cur in prev else ""))
        return list(reversed(path))

    def reachable(self, start: str, kinds=None, undirected: bool = False) -> set[str]:
        adj = self.adjacency(kinds, undirected)
        seen = {start}
        q = deque([start])
        while q:
            for nxt, _ in adj.get(q.popleft(), []):
                if nxt not in seen:
                    seen.add(nxt)
                    q.append(nxt)
        return seen

    def orphans(self) -> list[str]:
        """辺（派生の backlink／folgezettel を除く）が 1 本も無いノート。"""
        linked: set[str] = set()
        for e in self.edges:
            if not e.derived and e.kind != "backlink":
                linked.add(e.src)
                linked.add(e.dst)
        return sorted(n for n in self.nodes if n not in linked)

    def components(self, kinds=None) -> list[list[str]]:
        adj = self.adjacency(kinds, True)
        seen: set[str] = set()
        out = []
        for n in sorted(self.nodes):
            if n in seen:
                continue
            comp = [n]
            seen.add(n)
            q = deque([n])
            while q:
                for nxt, _ in adj[q.popleft()]:
                    if nxt not in seen:
                        seen.add(nxt)
                        comp.append(nxt)
                        q.append(nxt)
            out.append(sorted(comp))
        return out

    # --- Folgezettel ---
    def fz_index(self) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
        """(ID → ノート（グループ以外）, ID → グループ)。ブランチで作ったグループは親ノートと同じ ID を持つ。"""
        notes: dict[str, list[str]] = {}
        groups: dict[str, list[str]] = {}
        for n in self.nodes.values():
            if n.fz:
                (groups if n.is_group else notes).setdefault(n.fz, []).append(n.id)
        return notes, groups

    def fz_problems(self) -> dict:
        notes, groups = self.fz_index()
        every = set(notes) | set(groups)
        dup = {i: ps for i, ps in notes.items() if len(ps) > 1}
        # 親の ID が無い（抜け）。最上位（親が ""）は対象外
        gaps_set = set()
        for i in every:
            cur = fz.parent_id(i)
            while cur and cur not in every:  # 欠けている祖先は全部（3a1 だけがあれば 3a と 3）
                gaps_set.add(cur)
                cur = fz.parent_id(cur)
        gaps = sorted(gaps_set, key=fz.natural_key)
        bad = sorted(n.id for n in self.nodes.values() if n.fz and not fz.ID_RE.fullmatch(n.fz))
        return {"duplicate_ids": dup, "missing_parents": gaps, "invalid_ids": bad}

    def fz_info(self, ident: str) -> dict:
        """1 つの番号の見取り図。兄弟移動(1a→1b)と親子(1→1a→1a1)を混同しない。存在しない番号は exists=False。"""
        notes, groups = self.fz_index()
        every = set(notes) | set(groups)
        pid = fz.parent_id(ident)
        nat = fz.natural_key
        kids = sorted((i for i in every if fz.parent_id(i) == ident), key=nat)
        sibs = sorted((i for i in every if fz.parent_id(i) == pid), key=nat)
        pos = sibs.index(ident) if ident in sibs else -1
        ordered = sorted(every, key=nat)
        at = ordered.index(ident) if ident in ordered else -1

        def one(i):
            ps = notes.get(i) or groups.get(i) or []
            return {"id": i, "files": ps, "title": self.nodes[ps[0]].title if ps else ""}
        crumbs = []
        cur = pid
        while cur:
            crumbs.append(cur)
            cur = fz.parent_id(cur)
        return {
            "id": ident, "exists": ident in every,
            "files": notes.get(ident, []) + groups.get(ident, []),
            "parent": one(pid) | {"exists": pid in every} if pid else None,
            "siblings": [one(i) for i in sibs],
            "prev_sibling": one(sibs[pos - 1]) if pos > 0 else None,
            "next_sibling": one(sibs[pos + 1]) if 0 <= pos < len(sibs) - 1 else None,
            "children": [one(i) for i in kids],
            "first_child": one(kids[0]) if kids else None,
            "breadcrumbs": [one(i) | {"exists": i in every} for i in reversed(crumbs)],
            "prev_in_order": one(ordered[at - 1]) if at > 0 else None,   # 自然順（1, 1a, 1a1, 1a2, 1b, 2）の前後
            "next_in_order": one(ordered[at + 1]) if 0 <= at < len(ordered) - 1 else None,
        }

    def fz_tree(self) -> list[dict]:
        notes, groups = self.fz_index()
        every = sorted(set(notes) | set(groups), key=fz.natural_key)
        tops = [i for i in every if not fz.parent_id(i) or fz.parent_id(i) not in every]

        def build(i):
            ps = notes.get(i) or groups.get(i) or []
            return {"id": i, "files": ps, "title": self.nodes[ps[0]].title if ps else "",
                    "children": [build(c) for c in every if fz.parent_id(c) == i]}
        return [build(i) for i in tops]


def _links(lines: list[str]) -> list[str]:
    out = []
    flags = nf._fenced(lines)
    for ln, fenced in zip(lines, flags):
        if fenced:
            continue
        for m in nf.ANY_LINK_RE.finditer(ln):
            out.append(m.group(1).strip())
    return out


def _target(raw: str) -> str:
    raw = raw.split(" ", 1)[0].strip("<>")  # [t](x.md "title") の title を除く
    return raw


def build(root: str | Path) -> Graph:
    root = Path(root).resolve()
    g = Graph(root=root)
    by_name = nf._index(root)
    parsed: dict[str, dict] = {}
    for p in nf._iter_md(root):
        rel = p.resolve().relative_to(root).as_posix()
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        d = nf._simple_parse_text(p, text)
        fm = "\n".join(d["fm"])
        attr = ""
        m = re.search(r"^attribute:\s*(\S+)", fm, re.M)
        if m:
            attr = m.group(1)
        tm = next((ln.split(":", 1)[1].strip() for ln in d["fm"] if ln.startswith("time:")), "")
        g.nodes[rel] = Node(id=rel, title=d["title"], fz=fz.value(text), is_group=bool(nf._GROUP_ATTR_RE.search(fm)), attribute=attr, time=tm)
        parsed[rel] = d

    def resolve(src_rel: str, raw: str):
        t = _target(raw)
        if "://" in t or t.startswith(("mailto:", "#", "memo:")):
            return None, False  # 外部リンク・同じノート内は辺にしない
        # 速い道: 相対パスを文字列だけで正規化し、ノートとして知っている id に当たればそれ（realpath を呼ばない）
        tp = t.split("#", 1)[0].strip()
        if tp.lower().endswith(".md") and not tp.startswith("/"):
            fast = posixpath.normpath(posixpath.join(posixpath.dirname(src_rel), tp))
            if fast in g.nodes:
                return fast, False
        hit = nf._resolve(t, (root / src_rel).parent, root, by_name)
        if hit is None:
            return None, bool(t.split("#", 1)[0].strip())
        try:
            return hit.relative_to(root).as_posix(), False
        except ValueError:
            return None, False

    for rel, d in parsed.items():
        # 本文（BranchGroup: のリンクは本文の末尾に付いて来る）
        body = list(d["body"])
        in_bg = False
        body_lines = []
        bg_lines = []
        for ln in body:
            if ln.strip() in (nf.BRANCH_GROUP_HEAD, nf.LEGACY_THIS_NOTE_GROUP_HEAD):
                in_bg = True
                continue
            (bg_lines if in_bg else body_lines).append(ln)
        groups = [("branch_group", bg_lines), ("link", body_lines)] + [(k, d[s]) for s, k in _SECTIONS]
        for kind, lines in groups:
            for raw in _links(lines):
                dst, broken = resolve(rel, raw)
                if dst is not None:
                    if dst != rel:
                        g.edges.append(Edge(rel, dst, kind, derived=(kind == "backlink")))
                elif broken:
                    g.broken.append({"src": rel, "target": _target(raw), "kind": kind})
    # Folgezettel の親子（子 → 親。派生）
    notes, groups_by_id = g.fz_index()
    for i, ps in notes.items():
        pid = fz.parent_id(i)
        for parent in (notes.get(pid) or groups_by_id.get(pid) or []):
            for c in ps:
                g.edges.append(Edge(c, parent, "folgezettel", derived=True))
    return g


def to_json(g: Graph) -> dict:
    return {"nodes": [vars(n) for n in g.nodes.values()],
            "edges": [vars(e) for e in g.edges], "broken": g.broken}


def check(g: Graph) -> dict:
    return {"broken_links": g.broken, "folgezettel": g.fz_problems(), "orphans": g.orphans(),
            "counts": {"notes": len(g.nodes), "edges": len(g.edges), "broken": len(g.broken)}}


def main(argv: list[str]) -> int:
    try:
        if len(argv) == 2 and argv[0] == "check":
            out = check(build(argv[1]))
        elif len(argv) == 2 and argv[0] == "graph":
            out = to_json(build(argv[1]))
        elif len(argv) == 4 and argv[0] == "path":
            g = build(argv[1])
            out = {"path": g.shortest_path(argv[2], argv[3])}
        elif len(argv) in (2, 3) and argv[0] == "fz":
            g = build(argv[1])
            if len(argv) == 2:
                out = {"tree": g.fz_tree(), "problems": g.fz_problems()}
            else:
                ident = argv[2]
                if ident in g.nodes:
                    ident = g.nodes[ident].fz
                out = g.fz_info(ident)
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
