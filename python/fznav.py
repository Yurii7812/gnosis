#!/usr/bin/env python3
"""Folgezettel ビュー（CUI・アプリ共通の計算）。ノートは書き換えない（読み取り専用）。

番号（front matter の folgezettel:）の並び・Group と Note の行・上位の番号・折りたたみの範囲・上位表示（祖先の Group と関連 Group）を、
曼荼羅のキャッシュ（<vault>/.gnosis/cache/mandala.sqlite。mandala_cache.py が作る派生データ）から求める。
Vim（autoload/gnosis/fznav.vim）はこの JSON を受け取って描くだけで、番号の規則を二重に持たない。

  fznav.py rows ROOT [--numw N]                 全行（自然順・同じ番号は Group → Note）と、親子の位置
  fznav.py upper ROOT REL [--numw N] [--max N]  REL の上位表示: 祖先の番号にある Group と、関連 Group（順位つき）
  fznav.py outline FILE                          Markdown の見出し（# ## ###）の一覧

行は [番号, パス, 題, 種類("g"=Group / "n"=Note), 番号欄の表示, 上(ブロックの先頭の行), ブロックの終わり, 部分木の終わり, 下(最初の子孫の行)]。
「ブロック」は同じ番号の行（Group の行 → Note の行）。部分木の終わりは、その番号の子孫の次の行（折りたたみで隠す範囲は ブロックの終わり+1 〜 部分木の終わり-1）。
"""
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mandala_cache as mc  # noqa: E402

ID_RE = re.compile(r"^(?:[A-Z]{1,4}-)?[1-9]\d*(?:[a-z]+[1-9]\d*)*[a-z]*$")
NUMW = 8          # 番号欄の幅（文字数）。これを超える番号は先頭を「~」で省く


# ---- 番号 ---------------------------------------------------------------------------------------

def parts(ident: str) -> list[str]:
    return re.findall(r"[A-Z]+-|\d+|[a-z]+", ident)   # 紙の番号の印（PA-）も 1 つの部品


def natural_key(ident: str) -> tuple:
    """1 < 1a < 1a1 < 1a1a < 1a2 < 1b < 1z < 1aa < 2 < 10。数字は数として、文字は（長さ, 文字）で比べる。"""
    return tuple((0, int(p), "") if p.isdigit() else (1, len(p), p) for p in parts(ident))


def abbreviate(ident: str, width: int = NUMW) -> str:
    """番号欄に収まらない番号は、先頭を省いて「~」を付ける（例 ~a1）。実際の番号は変えない。
    省くのは番号の区切り（数字と文字の境目）で。1 つの区切りも入らないときだけ、末尾の文字を取る。"""
    if len(ident) <= width:
        return ident
    room = width - 1
    out = ""
    for p in reversed(parts(ident)):
        if len(out) + len(p) > room:
            break
        out = p + out
    if not out:
        out = ident[-room:] if room > 0 else ""
    return "~" + out


def valid(ident: str) -> bool:
    return bool(ident) and bool(ID_RE.fullmatch(ident))


# ---- 全行 ---------------------------------------------------------------------------------------

def _collect(db):
    """files と BranchGroup の辺を読む。{id: (path, title, g, fz)} と {ノート id: [グループ id…]}（辺の書かれた順）。"""
    files = {i: (p, t, g, fz) for i, p, t, g, fz in db.execute("SELECT id,path,title,g,fz FROM files")}
    bg: dict[int, list[int]] = {}
    for src, dst in db.execute("SELECT src,dst FROM edges WHERE kind=? ORDER BY rowid", (mc._KID["branch_group"],)):
        lst = bg.setdefault(src, [])
        if dst not in lst:
            lst.append(dst)
    return files, bg


def build_rows(db) -> list[tuple]:
    """(番号, パス, 題, 種類, ファイル id) を自然順に。同じ番号は Group の行が先、Note の行が後。
    Group の行は、実際に BranchGroup: に書かれ、かつそのノートと同じ番号を持つグループだけ（番号を共有する仕組み）。
    番号の一致しない BranchGroup は行にしない（共有の BranchGroup が全ノートの下に並ぶのを避ける）。
    番号を持つグループが、同じ番号のノートの BranchGroup: に無いときも、実在するグループなので 1 行出す。"""
    files, bg = _collect(db)
    claimed: set[int] = set()
    rows: list[tuple] = []     # (キー, 種類順, 順, …)
    for fid, (path, title, g, fz) in files.items():
        if not valid(fz) or g:
            continue
        key = natural_key(fz)
        rows.append((key, 1, 0, path, fz, title, "n", fid))
        for n, gid in enumerate(bg.get(fid, [])):
            gp = files.get(gid)
            if gp and gp[2] and gp[3] == fz and gid not in claimed:
                claimed.add(gid)
                rows.append((key, 0, n, gp[0], fz, gp[1], "g", gid))
    for fid, (path, title, g, fz) in files.items():
        if g and valid(fz) and fid not in claimed:
            rows.append((natural_key(fz), 0, 99, path, fz, title, "g", fid))
    rows.sort(key=lambda r: (r[0], r[1], r[2], r[3]))
    return [(r[4], r[3], r[5], r[6], r[7]) for r in rows]


def index_rows(rows: list[tuple], numw: int = NUMW) -> list[list]:
    """行に、番号の表示・上(ブロックの先頭)・ブロックの終わり・部分木の終わり・下(最初の子孫)を付ける。"""
    n = len(rows)
    out: list[list] = []
    keys = [parts(r[0]) for r in rows]
    be = [0] * n
    i = 0
    while i < n:                               # ブロック（同じ番号の行）の範囲
        j = i
        while j + 1 < n and rows[j + 1][0] == rows[i][0]:
            j += 1
        for k in range(i, j + 1):
            be[k] = j
        i = j + 1
    up = [-1] * n
    sub = [n] * n
    stack: list[int] = []                      # 祖先のブロックの先頭の行
    i = 0
    while i < n:
        last = be[i]
        while stack and keys[stack[-1]] != keys[i][:len(keys[stack[-1]])]:
            top = stack.pop()
            for k in range(top, be[top] + 1):
                sub[k] = i
        up_i = stack[-1] if stack else -1
        for k in range(i, last + 1):
            up[k] = up_i
        stack.append(i)
        i = last + 1
    for top in stack:
        for k in range(top, be[top] + 1):
            sub[k] = n
    for k, r in enumerate(rows):
        down = be[k] + 1 if sub[k] > be[k] + 1 else -1
        out.append([r[0], r[1], r[2], r[3], abbreviate(r[0], numw), up[k], be[k], sub[k], down])
    return out


def rows(root: str | Path, numw: int = NUMW) -> dict:
    db = mc.connect(root)
    if db is None:
        return {"ok": False, "rows": []}
    try:
        return {"ok": True, "numw": numw, "rows": index_rows(build_rows(db), numw)}
    finally:
        db.close()


# ---- 上位表示 -----------------------------------------------------------------------------------

# 現在のノートとの関係の強さ（周辺ノートに付ける重み）
W_PARENT, W_CHILD, W_SIB, W_NEAR = 4.0, 3.0, 2.0, (3.0, 2.0)
W_LINK = {"parent_branch": 5.0, "child_branch": 5.0, "context": 5.0, "related": 4.0, "link": 4.0, "backlink": 3.0}
W_SELF = 6.0       # 現在のノート自身が所属しているグループ
SIB_MAX = 12       # きょうだい・子は番号順に近いほうから、これだけ


def _members(db, gid: int) -> int:
    n1 = db.execute("SELECT COUNT(DISTINCT dst) FROM edges WHERE src=? AND kind=?", (gid, mc._KID["link"])).fetchone()[0]
    n2 = db.execute("SELECT COUNT(DISTINCT src) FROM edges WHERE dst=? AND kind IN (?,?)",
                    (gid, mc._KID["group"], mc._KID["branch_group"])).fetchone()[0]
    return n1 + n2


def upper(root: str | Path, rel: str, numw: int = NUMW, limit: int = 30) -> dict:
    """rel の上位表示。
    chain   … 番号の祖先（自分を含む）それぞれにある Group（実在するものだけ。無い番号は飛ばす。rel 自身は含めない）
    related … 本文の内容が似ているノートが入っているグループを、類似度順に（chain に出したものは除く）。
              番号は加点せず、直接の Group 所属は弱い補助証拠として使う。
              Index・日記など機械的な管理グループは候補から外す。"""
    db = mc.connect(root)
    if db is None:
        return {"ok": False}
    try:
        row = db.execute("SELECT id,path,title,g,fz FROM files WHERE path=?", (rel,)).fetchone()
        if row is None:
            return {"ok": False}
        cid, cpath, ctitle, cg, cfz = row
        cfz = cfz if valid(cfz) else ""
        base = build_rows(db)
        idx = index_rows(base, numw)
        files, _bg = _collect(db)
        # 現在の行
        cur_row = next((k for k, r in enumerate(base) if r[1] == cpath), -1)
        out: dict = {"ok": True, "cur": {"id": cfz, "num": abbreviate(cfz, numw), "path": cpath, "title": ctitle, "kind": "g" if cg else "n"},
                     "chain": [], "related": [], "total": 0}
        # 祖先（自分を含む）の番号にある Group
        if cfz:
            ps = parts(cfz)
            want = {"".join(ps[:k]) for k in range(1, len(ps) + 1)}
            for r in idx:
                if r[0] in want and r[3] == "g" and r[1] != cpath:
                    out["chain"].append({"id": r[0], "num": r[4], "path": r[1], "title": r[2]})
        shown = {c["path"] for c in out["chain"]} | {cpath}
        # 関連グループ: 番号の近さやリンク・所属の加点は使わない。
        # 本文が近いノートを先に選び、それらが実際に含まれるグループを集計する。
        import content_rank as cr
        hits = mc.related(root, rel, limit=250)
        by_path = {v[0]: k for k, v in files.items()}
        similarities = {by_path[h["id"]]: h["score"] / 100.0
                        for h in hits if h["id"] in by_path}
        membership = mc._groups_of(db, list(similarities)) if similarities else {}
        evidence: dict[int, list[float]] = {}
        for fid, groups in membership.items():
            for gid in groups:
                evidence.setdefault(gid, []).append(similarities[fid])
        # The center's explicitly assigned topical Group is a meaningful
        # relationship even when its note is just a short heading. Do not
        # infer groups from Folgezettel numbers or directory proximity.
        mine = mc._groups_of(db, [cid]).get(cid, set())
        for gid in mine:
            evidence.setdefault(gid, []).append(0.22)
        cand = []
        for gid, weights in evidence.items():
            gp = files.get(gid)
            if not gp or gid == cid or gp[0] in shown:
                continue
            # Indexや日記の階層は管理上の入れ物であって関連する話題ではない。
            if cr.organizational(gp[0], gp[1]):
                continue
            size = _members(db, gid)
            pts = sum(sorted(weights, reverse=True)[:8]) / math.log2(2 + size)
            if pts <= 0:
                continue
            cand.append((-pts, natural_key(gp[3]) if valid(gp[3]) else (),
                         gp[1], gp[0], gid, size, len(weights)))
        cand.sort()
        out["total"] = len(cand)
        for neg, _key, title, path, gid, size, count in cand[:limit]:
            fzid = files[gid][3]
            out["related"].append({
                "id": fzid if valid(fzid) else "",
                "num": abbreviate(fzid, numw) if valid(fzid) else "",
                "path": path, "title": title, "score": round(-neg, 3),
                "near": count, "size": size, "own": 1 if gid in mine else 0})
        return out
    finally:
        db.close()


# ---- 見出し -------------------------------------------------------------------------------------

_FENCE = re.compile(r"^\s*(```|~~~)")
_HEAD = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")


def outline_items(lines: list[str]) -> list[dict]:
    """Markdown の見出し（# ~ ######）。コードブロックの中は除く。front matter は読み飛ばす。
    [{level, text, lnum}]（lnum は 1 始まり）。"""
    items = []
    i = 0
    if lines and lines[0].strip() == "---":
        for j in range(1, len(lines)):
            if lines[j].strip() == "---":
                i = j + 1
                break
    fence = False
    for n in range(i, len(lines)):
        ln = lines[n]
        if _FENCE.match(ln):
            fence = not fence
            continue
        if fence:
            continue
        m = _HEAD.match(ln)
        if m and m.group(2):
            items.append({"level": len(m.group(1)), "text": m.group(2), "lnum": n + 1})
    return items


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    opts = {a: argv[i + 1] for i, a in enumerate(argv) if a in ("--numw", "--max") and i + 1 < len(argv)}
    numw = int(opts.get("--numw", NUMW))
    if cmd == "rows" and len(argv) >= 3:
        out = rows(argv[2], numw)
    elif cmd == "upper" and len(argv) >= 4:
        out = upper(argv[2], argv[3], numw, int(opts.get("--max", 30)))
    elif cmd == "outline" and len(argv) >= 3:
        try:
            out = outline_items(Path(argv[2]).read_text(encoding="utf-8").splitlines())
        except OSError:
            out = []
    else:
        print(__doc__)
        return 2
    sys.stdout.write(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
