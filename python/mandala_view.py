#!/usr/bin/env python3
"""CUI の曼荼羅ビュー（Vim の `<Space>`）の元データ。読み取り専用。

vault の関係（gnosis_graph.py）を、Vim が一度だけ読み込んで持てる小さな JSON にする。
ノートも索引も書き換えない。派生データなので、いつでも vault から作り直せる。

  mandala_view.py near ROOT NOTE  NOTE に近い索引を近い順に [{"id","score","why"}]（\\g の候補・c モード）
  mandala_view.py related ROOT NOTE  NOTE に関連する索引・ノートを関連の強い順に（r モード）
  mandala_view.py search ROOT 語…  題か本文に語を全部含むノート（題に合うものが先）
  mandala_view.py dump ROOT      {"nodes": {相対パス: {"t": 題, "g": 1|0, "o": {種類: [相対パス, …]}}}}
                                  g は索引（index.md・attribute: group のノート）。o は向きのまま・ファイル順・重複なし・
                                  自分自身と壊れたリンクは含めない（Folgezettel の派生の辺も含めない）。

どの辺を周辺に出すかは `items()` が決める（Vim 側の autoload/gnosis/mview.vim も同じ規則を持つ。試験で食い違いを防ぐ）。
ダブルインデックスの道（Global Index → 最初のノート → BranchGroup のトピック索引 → ノート）に沿う:
  中心がノート … groups=進む先のトピック索引（BranchGroup:）→ 所属する索引（Group:） /
                 notes=ParentBranch・ChildBranch・Context・Related・BackLink・本文のリンク / all=groups のあとに notes
  中心が索引   … all=この索引を持つノート（BranchGroup: を逆にたどる）→ 所属する索引（Group:）→ 索引の項目すべて /
                 groups(i)=所属する索引と、索引の項目すべて / notes=この索引を持つノートと、項目のうち索引でない普通のノート
                 項目の名前は、その索引に書かれたリンクの文字（索引語）。dump の en（[[項目, 名前], …]。同じノートが別の名前で何回載っていても全部）
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import folgezettel as fz  # noqa: E402
import gnosis_graph as gg  # noqa: E402
import note_format_v2 as nf  # noqa: E402

GROUP_KINDS = ("group", "branch_group")
NOTE_KINDS = ("parent_branch", "child_branch", "context", "related", "backlink", "link")
KEPT = GROUP_KINDS + NOTE_KINDS
MODES = ("all", "groups", "notes")


_LINK_TEXT = re.compile(r"\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)")


def _entries(g, root: Path, gid: str) -> list[list[str]]:
    """索引（グループ）gid の本文に書かれた項目 [[項目の相対パス, 名前（リンクの文字＝索引語）], …]。
    ファイルの順。同じノートが別の名前で何回載っていても、載っている回数だけ入れる（同じ名前の重複は 1 つ）。"""
    try:
        text = (root / gid).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    d = nf._simple_parse_text(root / gid, text)
    by_name = _BY_NAME.get(str(root))
    if by_name is None:
        by_name = _BY_NAME[str(root)] = nf._index(root)
    out: list[list[str]] = []
    for ln in d["body"]:
        for m in _LINK_TEXT.finditer(ln):
            name = re.sub(r"\\(.)", r"\1", m.group(1)).strip()
            t = m.group(2).split(" ", 1)[0].strip("<>")
            if not name or "://" in t or t.startswith(("mailto:", "#", "memo:")):
                continue
            hit = nf._resolve(t, (root / gid).parent, root, by_name)
            if hit is None:
                continue
            try:
                rel = hit.relative_to(root).as_posix()
            except ValueError:
                continue
            if rel != gid and [rel, name] not in out:
                out.append([rel, name])
    return out


_BY_NAME: dict[str, dict] = {}


def dump(root: str | Path) -> dict:
    g = gg.build(root)
    root = Path(root).resolve()
    _BY_NAME.pop(str(root), None)
    nodes: dict[str, dict] = {}
    for nid, n in g.nodes.items():
        nodes[nid] = {"t": n.title, "g": 1 if (n.is_group or nid == "index.md") else 0, "o": {}}
    for e in g.edges:
        if e.kind not in KEPT or e.src == e.dst or e.dst not in nodes:
            continue
        lst = nodes[e.src]["o"].setdefault(e.kind, [])
        if e.dst not in lst:
            lst.append(e.dst)
        if e.kind == "branch_group":
            back = nodes[e.dst].setdefault("r", {}).setdefault("branch_group", [])
            if e.src not in back:
                back.append(e.src)
    # 索引の項目（en）: [[項目, 名前（索引語）], …]。同じノートが別の名前で何回載っていても全部。名前が題と同じなら ""
    for nid, nd in nodes.items():
        if nd["g"]:
            en = [[k, "" if v == nodes[k]["t"] else v] for k, v in _entries(g, root, nid) if k in nodes]
            if en:
                nd["en"] = en
    return {"nodes": nodes}


def items(data: dict, center: str, mode: str = "all") -> list[str]:
    """中心 center の周辺に出すノート（相対パス）を、出す順に返す。ダブルインデックスの道
    （Global Index → 最初のノート → そのノートの BranchGroup のトピック索引 → ノート）に沿う。

      中心がノート … 進む先のトピック索引（BranchGroup:）→ 所属する索引（Group:。戻る方向）→ ほかのつながり
      中心が索引   … その索引を持つノート（BranchGroup: を逆にたどる）→ 所属する索引（Group:）→ 索引の項目すべて
    """
    nodes = data["nodes"]
    c = nodes.get(center)
    if c is None:
        return []
    o = c["o"]
    origin = c.get("r", {}).get("branch_group", [])
    out: list[str] = []

    def add_ids(ids, want=None):
        for t in ids:
            if t == center or t in out or t not in nodes:
                continue
            if want is not None and bool(nodes[t]["g"]) != want:
                continue
            out.append(t)

    def add(kinds, want=None):
        for k in kinds:
            add_ids(o.get(k, []), want)

    if c["g"]:
        if mode in ("notes", "all"):
            add_ids(origin)                       # この索引を持つ最初のノート（戻る道）
        if mode != "notes":
            add(("group",))                      # 所属する索引（Index も）
        # 索引の項目: 同じノートが別の名前で何回載っていても、載っている回数だけ（n は索引でない普通のノートだけ）
        for dst, _name in c.get("en") or [[t, ""] for t in o.get("link", [])]:
            if dst in nodes and dst != center and not (mode == "notes" and nodes[dst]["g"]):
                out.append(dst)
    else:
        if mode in ("groups", "all"):
            add(("branch_group",))               # 進む先のトピック索引
            add(("group",))                      # 所属する索引（戻る方向）
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


# ---- 関連（r モード。索引でもノートでも、関連の強い順） --------------------------------------

# note から見て相手がどういう関係か（辺の向きで言い換える）と点数
_OUT = {"parent_branch": ("親", 5.0), "child_branch": ("子", 5.0), "context": ("Context", 4.0), "related": ("関連", 4.0),
        "link": ("リンク", 3.0), "backlink": ("BackLink", 3.0), "group": ("所属の索引", 3.0), "branch_group": ("所属の索引", 3.0)}
_IN = {"parent_branch": ("子", 5.0), "child_branch": ("親", 5.0), "context": ("Context にされている", 3.0), "related": ("関連", 4.0),
       "link": ("リンクされている", 3.0), "backlink": ("BackLink", 3.0), "group": ("索引の中身", 3.0), "branch_group": ("索引の中身", 3.0)}
# 歩いて近さを測るときの辺の重み（向きは無視）
_WALK = {"parent_branch": 3.0, "child_branch": 3.0, "context": 2.5, "related": 2.5, "link": 2.0, "backlink": 1.5,
         "group": 1.5, "branch_group": 1.5, "folgezettel": 2.5}


def _walk_scores(g, note: str, restart: float = 0.25, iters: int = 18) -> dict[str, float]:
    """note から出発して、辺を重みに比例して歩き、確率 restart で戻る。各ノートにいる確率（近さ）を返す。"""
    nbr: dict[str, list[tuple[str, float]]] = {n: [] for n in g.nodes}
    for e in g.edges:
        w = _WALK.get(e.kind)
        if w and e.src in nbr and e.dst in nbr and e.src != e.dst:
            nbr[e.src].append((e.dst, w))
            nbr[e.dst].append((e.src, w))
    tot = {n: sum(w for _d, w in v) for n, v in nbr.items()}
    p = {note: 1.0}
    for _ in range(iters):
        q: dict[str, float] = {note: restart}
        for n, pv in p.items():
            if not tot[n]:
                q[note] = q.get(note, 0.0) + (1 - restart) * pv
                continue
            share = (1 - restart) * pv / tot[n]
            for d, w in nbr[n]:
                q[d] = q.get(d, 0.0) + share * w
        p = q
    p.pop(note, None)
    return p


def _body_vectors(g) -> tuple[dict[str, dict[str, float]], dict[str, float]]:
    """ノートごとの TF-IDF（本文と題。語はかな・漢字の 2 文字ずつと英数字の語）。珍しい語ほど重い。"""
    import math
    docs: dict[str, dict[str, int]] = {}
    df: dict[str, int] = {}
    for nid, n in g.nodes.items():
        try:
            text = (g.root / nid).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            text = ""
        toks: dict[str, int] = {}
        for t in list(_tokens(n.title)) * 3 + list(_all_tokens(text)):
            toks[t] = toks.get(t, 0) + 1
        docs[nid] = toks
        for t in toks:
            df[t] = df.get(t, 0) + 1
    n_docs = max(1, len(docs))
    idf = {t: math.log(1 + n_docs / c) for t, c in df.items()}
    vec: dict[str, dict[str, float]] = {}
    for nid, toks in docs.items():
        v = {t: (1 + math.log(c)) * idf[t] for t, c in toks.items() if df[t] < max(3, n_docs * 0.5)}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1.0
        vec[nid] = {t: x / norm for t, x in v.items()}
    return vec, idf


def _all_tokens(text: str):
    t = text.lower()
    yield from _WORD.findall(t)
    for run in _CJK_RUN.findall(t):
        if len(run) == 1:
            continue
        for i in range(len(run) - 1):
            yield run[i:i + 2]


def related(root: str | Path, note: str, limit: int = 80) -> list[dict]:
    """note に関連するノート・索引を関連の強い順に返す: [{"id", "score", "why"}]（r モード）。

    足し算: 直接のつながり（親・子・Context・Related・リンク・BackLink・所属）、同じ索引に載っていること、
    Folgezettel の枝、題の言葉の重なり（珍しい語ほど重い）、本文の内容の近さ（TF-IDF のコサイン類似度）、
    つながりをたどった近さ（起点に戻りながら歩く）。理由は強い順。
    """
    g = gg.build(root)
    return _related(g, note, limit)


def _related(g, note: str, limit: int = 80) -> list[dict]:
    if note not in g.nodes:
        return []
    me = g.nodes[note]
    score: dict[str, dict[str, float]] = {}

    def add(x: str, why: str, pts: float):
        if x == note or x not in g.nodes:
            return
        d = score.setdefault(x, {})
        d[why] = max(d.get(why, 0.0), pts)

    my_groups = set()
    for e in g.edges:
        if e.src == note and e.dst in g.nodes and e.kind in _OUT:
            add(e.dst, *_OUT[e.kind])
            if e.kind in GROUP_KINDS:
                my_groups.add(e.dst)
        elif e.dst == note and e.src in g.nodes and e.kind in _IN:
            add(e.src, *_IN[e.kind])
            if e.kind == "link" and g.nodes[e.src].is_group:
                my_groups.add(e.src)
    # 同じ索引に載っているノート
    for gid in my_groups:
        for m in _members(g, gid):
            add(m, "同じ索引: " + g.nodes[gid].title, 2.0)
    # Folgezettel の枝
    for nid, n in g.nodes.items():
        rel = _fz_relation(me.fz, n.fz) if nid != note else None
        if rel:
            add(nid, rel[0], rel[1])
    # 題の言葉（珍しい語ほど重い）
    my_tok = _tokens(me.title)
    if my_tok:
        df: dict[str, int] = {}
        toks_of = {nid: _tokens(n.title) for nid, n in g.nodes.items()}
        for tk in toks_of.values():
            for t in tk:
                df[t] = df.get(t, 0) + 1
        import math
        for nid, tk in toks_of.items():
            common = my_tok & tk
            if nid != note and common:
                pts = sum(1.5 * math.log(1 + len(g.nodes) / df[t]) / 3 for t in common)
                add(nid, "題が近い", min(pts, 4.0))
    # 本文の内容
    vec, _idf = _body_vectors(g)
    mv = vec.get(note, {})
    if mv:
        for nid, v in vec.items():
            if nid == note:
                continue
            small, big = (mv, v) if len(mv) < len(v) else (v, mv)
            cos = sum(x * big.get(t, 0.0) for t, x in small.items())
            if cos >= 0.12:
                add(nid, "内容が近い", min(10.0 * cos, 6.0))
    # つながりをたどった近さ
    walk = _walk_scores(g, note)
    if walk:
        top = max(walk.values())
        for nid, w in walk.items():
            if w / top >= 0.05:
                add(nid, "つながりが近い", 5.0 * (w / top) ** 0.5)
    out = []
    for nid, why in score.items():
        total = sum(why.values())
        out.append({"id": nid, "score": round(total, 2), "why": [k for k, _v in sorted(why.items(), key=lambda kv: -kv[1])]})
    out.sort(key=lambda d: (-d["score"], g.nodes[d["id"]].title))
    return out[:limit]


def search(root: str | Path, words: list[str], limit: int = 200) -> list[str]:
    """題・ファイル名・本文に words を全部含むノート（相対パス）。題やファイル名に合うものが先（python/mandala_search.py）。"""
    import mandala_search as ms

    g = gg.build(root)

    def body_of(nid: str):
        return lambda: (g.root / nid).read_text(encoding="utf-8")

    return ms.rank(((nid, n.title, body_of(nid)) for nid, n in g.nodes.items()), words, limit)


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "dump":
        json.dump(dump(argv[2]), sys.stdout, ensure_ascii=False, separators=(",", ":"))
        return 0
    if len(argv) >= 4 and argv[1] in ("near", "related", "search"):
        # 大きな vault（キャッシュがあり、BIG_VAULT 件を超える）は、全体を読まないキャッシュ版で求める
        import mandala_cache as mc
        if mc.is_big(argv[2]):
            fn = {"near": mc.near, "related": mc.related}.get(argv[1])
            out = fn(argv[2], argv[3]) if fn else mc.search(argv[2], argv[3:])
        else:
            out = {"near": near, "related": related}[argv[1]](argv[2], argv[3]) if argv[1] != "search" else search(argv[2], argv[3:])
        json.dump(out, sys.stdout, ensure_ascii=False, separators=(",", ":"))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
