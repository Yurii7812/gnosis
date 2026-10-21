#!/usr/bin/env python3
"""CUI の曼荼羅ビュー（Vim の `<Space>`）の元データ。読み取り専用。

vault の関係（gnosis_graph.py）を、Vim が一度だけ読み込んで持てる小さな JSON にする。
ノートも索引も書き換えない。派生データなので、いつでも vault から作り直せる。

  mandala_view.py near ROOT NOTE  NOTE に近い索引を近い順に [{"id","score","why"}]（\\g の候補・c モード）
  mandala_view.py search ROOT 語…  題か本文に語を全部含むノート（題に合うものが先）
  mandala_view.py dump ROOT      {"nodes": {相対パス: {"t": 題, "g": 1|0, "o": {種類: [相対パス, …]}}}}
                                  g は索引（index.md・attribute: group のノート）。o は向きのまま・ファイル順・重複なし・
                                  自分自身と壊れたリンクは含めない（Folgezettel の派生の辺も含めない）。

どの辺を周辺に出すかは `items()` が決める（Vim 側の autoload/gnosis/mview.vim も同じ規則を持つ。試験で食い違いを防ぐ）:
  中心が索引   … 所属する索引（Group: / BranchGroup:。Index を含む）のあとに、載っているノート（本文のリンク）。
                 groups=索引だけ / notes=載っているノートのうち索引でないもの / all=全部
  中心がノート … groups=Group: と BranchGroup:（所属の索引） / notes=ParentBranch・ChildBranch・Context・Related・BackLink・本文のリンク
                 / all=groups のあとに notes
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import folgezettel as fz  # noqa: E402
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
        # 索引の周りは、所属する索引（Group: / BranchGroup:。Index も）→ 載っているノート（本文のリンク）の順
        if mode == "groups":
            add(GROUP_KINDS)
            add(("link",), True)
        elif mode == "notes":
            add(("link",), False)
        else:
            add(GROUP_KINDS)
            add(("link",))
    else:
        if mode in ("groups", "all"):
            add(GROUP_KINDS)
        if mode in ("notes", "all"):
            add(NOTE_KINDS)
    return out


# ---- 近い索引（\g の候補・c モード） -------------------------------------------------

_CJK_RUN = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uff66-\uff9f]+")
_WORD = re.compile(r"[a-z0-9]{2,}")


def _tokens(title: str) -> set[str]:
    """題の言葉の目印: 英数字の語、かな・漢字は 2 文字ずつ（1 文字だけの塊はその 1 文字）。"""
    t = title.lower()
    out = set(_WORD.findall(t))
    for run in _CJK_RUN.findall(t):
        if len(run) == 1:
            out.add(run)
        else:
            out.update(run[i:i + 2] for i in range(len(run) - 1))
    return out


def _fz_chain(ident: str) -> list[str]:
    out = []
    while ident:
        out.append(ident)
        ident = fz.parent_id(ident)
    return out


_FZ_SCORE = {"同じ番号": 6.0, "枝の親": 5.0, "枝の子": 5.0, "枝の兄弟": 3.0, "同じ枝": 2.0}


def _fz_relation(a: str, b: str):
    """番号 a から見た番号 b の関係と近さ（点数）。関係なし・片方が空なら None。"""
    if not a or not b:
        return None
    if a == b:
        return "同じ番号", _FZ_SCORE["同じ番号"]
    if fz.parent_id(a) == b:
        return "枝の親", _FZ_SCORE["枝の親"]
    if fz.parent_id(b) == a:
        return "枝の子", _FZ_SCORE["枝の子"]
    if fz.parent_id(a) == fz.parent_id(b) and fz.parent_id(a):
        return "枝の兄弟", _FZ_SCORE["枝の兄弟"]
    ca, cb = _fz_chain(a), _fz_chain(b)
    if b in ca or a in cb:
        return "同じ枝", _FZ_SCORE["同じ枝"]
    return None


def near(root: str | Path, note: str, limit: int = 60) -> list[dict]:
    """note に近い索引を、近い順に返す: [{"id", "score", "why": [理由…]}]。note を載せている索引は含めない。

    手がかり（足し算）:
      番号   … 索引の中身のノートの Folgezettel 番号が、note の番号と同じ枝（同じ・親・子・兄弟・先祖/子孫）
      つながり … note の親・子・Context・Related・BackLink・本文のリンク・番号の親子が、その索引に載っている
      題     … note の題と索引の題・中身の題で、言葉（英数字の語・かなと漢字の 2 文字）が重なる
    """
    g = gg.build(root)
    return _near(g, note, limit)


def _members(g, gid: str) -> set[str]:
    return {e.dst for e in g.edges if e.src == gid and e.kind == "link"} | \
           {e.src for e in g.edges if e.dst == gid and e.kind in GROUP_KINDS}


def _near(g, note: str, limit: int = 60) -> list[dict]:
    if note not in g.nodes:
        return []
    me = g.nodes[note]
    groups = [n.id for n in g.nodes.values() if (n.is_group or n.id == "index.md") and n.id != note]
    members_of = {gid: _members(g, gid) for gid in groups}
    # note の近所（番号の親子を含む）。グループ関係の辺は除く（その索引に載っている手がかりにならない）
    nb_kinds = ("parent_branch", "child_branch", "context", "related", "backlink", "link", "folgezettel")
    adj = g.adjacency(kinds=nb_kinds, undirected=True)
    neighbors = {m for m, _k in adj.get(note, []) if m != note}
    my_tokens = _tokens(me.title)
    out = []
    for gid in groups:
        mem = members_of[gid]
        if note in mem:
            continue
        gn = g.nodes[gid]
        why: dict[str, float] = {}
        # 番号
        fz_total, fz_best = 0.0, ""
        for m in mem:
            mn = g.nodes.get(m)
            rel = _fz_relation(me.fz, mn.fz) if mn else None
            if rel:
                fz_total += rel[1]
                if not fz_best or rel[1] > _FZ_SCORE[fz_best]:
                    fz_best = rel[0]
        own = _fz_relation(me.fz, gn.fz)
        if own:
            fz_total += own[1] * 1.5
            fz_best = fz_best or own[0]
        if fz_total:
            why[fz_best or "同じ枝"] = min(fz_total, 10.0)
        # つながり
        shared = len(neighbors & mem)
        if shared:
            why[f"つながり {shared}"] = 2.0 * min(shared, 5)
        # 題
        gt = _tokens(gn.title) & my_tokens
        mt = set()
        for m in mem:
            mn = g.nodes.get(m)
            if mn:
                mt |= _tokens(mn.title) & my_tokens
        mt -= gt
        t = 2.0 * min(len(gt), 2) + 0.5 * min(len(mt), 6)
        if t:
            why["題が近い"] = t
        if why:
            out.append({"id": gid, "score": round(sum(why.values()), 2),
                        "why": [k for k, _v in sorted(why.items(), key=lambda kv: -kv[1])]})
    out.sort(key=lambda d: (-d["score"], g.nodes[d["id"]].title))
    return out[:limit]


def search(root: str | Path, words: list[str], limit: int = 200) -> list[str]:
    """題か本文に words を全部含むノート（相対パス）。題に合うものが先。"""
    g = gg.build(root)
    ws = [w.lower() for w in words if w]
    if not ws:
        return []
    title_hits, body_hits = [], []
    for nid, n in g.nodes.items():
        t = n.title.lower()
        if all(w in t for w in ws):
            title_hits.append((n.title, nid))
            continue
        try:
            body = (g.root / nid).read_text(encoding="utf-8").lower()
        except (OSError, UnicodeDecodeError):
            continue
        if all(w in t or w in body for w in ws):
            body_hits.append((n.title, nid))
    return [nid for _t, nid in sorted(title_hits)] + [nid for _t, nid in sorted(body_hits)][:max(0, limit - len(title_hits))]


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "dump":
        json.dump(dump(argv[2]), sys.stdout, ensure_ascii=False, separators=(",", ":"))
        return 0
    if len(argv) >= 4 and argv[1] == "near":
        json.dump(near(argv[2], argv[3]), sys.stdout, ensure_ascii=False, separators=(",", ":"))
        return 0
    if len(argv) >= 4 and argv[1] == "search":
        json.dump(search(argv[2], argv[3:]), sys.stdout, ensure_ascii=False, separators=(",", ":"))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
