#!/usr/bin/env python3
"""CUI の曼荼羅ビュー（Vim の `<Space>`）の元データ。読み取り専用。

vault の関係（gnosis_graph.py）を、Vim が一度だけ読み込んで持てる小さな JSON にする。
ノートも索引も書き換えない。派生データなので、いつでも vault から作り直せる。

  mandala_view.py dump ROOT      {"nodes": {相対パス: {"t": 題, "g": 1|0, "o": {種類: [相対パス, …]}}}}
                                  g は索引（index.md・attribute: group のノート）。o は向きのまま・ファイル順・重複なし・
                                  自分自身と壊れたリンクは含めない（Folgezettel の派生の辺も含めない）。

どの辺を周辺に出すかは `items()` が決める（Vim 側の autoload/gnosis/mview.vim も同じ規則を持つ。試験で食い違いを防ぐ）:
  中心が索引   … 載っているノート（本文のリンク）。groups=索引だけ / notes=索引でないもの / all=全部
  中心がノート … groups=Group: と BranchGroup:（所属の索引） / notes=ParentBranch・ChildBranch・Context・Related・BackLink・本文のリンク
                 / all=groups のあとに notes
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gnosis_graph as gg  # noqa: E402

GROUP_KINDS = ("group", "branch_group")
NOTE_KINDS = ("parent_branch", "child_branch", "context", "related", "backlink", "link")
KEPT = GROUP_KINDS + NOTE_KINDS
MODES = ("all", "groups", "notes")


def dump(root: str | Path) -> dict:
    g = gg.build(root)
    nodes: dict[str, dict] = {}
    for nid, n in g.nodes.items():
        nodes[nid] = {"t": n.title, "g": 1 if (n.is_group or nid == "index.md") else 0, "o": {}}
    for e in g.edges:
        if e.kind not in KEPT or e.src == e.dst or e.dst not in nodes:
            continue
        lst = nodes[e.src]["o"].setdefault(e.kind, [])
        if e.dst not in lst:
            lst.append(e.dst)
    return {"nodes": nodes}


def items(data: dict, center: str, mode: str = "all") -> list[str]:
    """中心 center の周辺に出すノート（相対パス）を、出す順に返す。"""
    nodes = data["nodes"]
    c = nodes.get(center)
    if c is None:
        return []
    o = c["o"]
    out: list[str] = []

    def add(kinds, want=None):
        for k in kinds:
            for t in o.get(k, []):
                if t == center or t in out or t not in nodes:
                    continue
                if want is not None and bool(nodes[t]["g"]) != want:
                    continue
                out.append(t)

    if c["g"]:
        # 索引の中身は本文のリンク。親の索引（Group:）は周辺に出さない
        if mode == "groups":
            add(("link",), True)
        elif mode == "notes":
            add(("link",), False)
        else:
            add(("link",))
    else:
        if mode in ("groups", "all"):
            add(GROUP_KINDS)
        if mode in ("notes", "all"):
            add(NOTE_KINDS)
    return out


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "dump":
        json.dump(dump(argv[2]), sys.stdout, ensure_ascii=False, separators=(",", ":"))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
