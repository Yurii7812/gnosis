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
    related … 周辺のノートが所属するグループを、関連度の高い順に（chain に出したものは除く）。
              周辺 = 番号の直前・直後・親・子・きょうだい（同じ親から分かれたもの）と、直接のリンク（親子・Context・Related・リンク・BackLink）。
              関連度 = 周辺ノートの重みの合計 ÷ log2(2 + グループの大きさ)（大きな一般的なグループほど割り引く）。
              番号が近いだけで、周辺のノートが 1 つも載っていないグループは出さない。"""
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
        # 周辺のノート {ファイル id: 重み}
        nb: dict[int, float] = {}

        def add(fid: int, w: float) -> None:
            if fid != cid and fid in files and not files[fid][2]:
                nb[fid] = nb.get(fid, 0.0) + w
        by_path = {v[0]: k for k, v in files.items()}
        if cur_row >= 0 and cfz:
            notes = [k for k, r in enumerate(base) if r[3] == "n"]
            pos = next((p for p, k in enumerate(notes) if base[k][1] == cpath), -1)
            if pos < 0:                               # 現在がグループのとき: 同じ番号のノートの位置
                pos = next((p for p, k in enumerate(notes) if base[notes[p]][0] == cfz), -1)
            if pos >= 0:
                for d, w in ((-1, W_NEAR[0]), (1, W_NEAR[0]), (-2, W_NEAR[1]), (2, W_NEAR[1])):
                    if 0 <= pos + d < len(notes):
                        add(by_path[base[notes[pos + d]][1]], w)
            r0 = idx[cur_row]
            blk0 = cur_row                            # 自分のブロックの先頭の行
            while blk0 > 0 and base[blk0 - 1][0] == r0[0]:
                blk0 -= 1
            up = r0[5]
            if up >= 0:
                for k in range(up, idx[up][6] + 1):   # 親（実在する直近の祖先）のノート
                    if base[k][3] == "n":
                        add(by_path[base[k][1]], W_PARENT)
                sibs = []                             # 同じ親から分かれたノート
                k = idx[up][6] + 1
                while k < idx[up][7]:
                    if idx[k][5] == up and idx[k][0] != r0[0]:
                        sibs.extend(j for j in range(k, idx[k][6] + 1) if base[j][3] == "n")
                    k = idx[k][6] + 1
                sibs.sort(key=lambda j: abs(j - cur_row))
                for j in sibs[:SIB_MAX]:
                    add(by_path[base[j][1]], W_SIB)
            kids = []                                 # 子（自分の直下の番号）のノート
            k = r0[6] + 1
            while k < r0[7]:
                if idx[k][5] == blk0:
                    kids.extend(j for j in range(k, idx[k][6] + 1) if base[j][3] == "n")
                k = idx[k][6] + 1
            for j in kids[:SIB_MAX]:
                add(by_path[base[j][1]], W_CHILD)
        # 直接のリンク
        for dst, k in db.execute("SELECT dst,kind FROM edges WHERE src=?", (cid,)):
            kind = mc.KINDS[k]
            if kind in W_LINK:
                add(dst, W_LINK[kind])
        for src, k in db.execute("SELECT src,kind FROM edges WHERE dst=? LIMIT 3000", (cid,)):
            kind = mc.KINDS[k]
            if kind in W_LINK:
                add(src, W_LINK[kind])
        # 自分自身の所属グループ
        mine = mc._groups_of(db, [cid]).get(cid, set())
        gm = mc._groups_of(db, list(nb)) if nb else {}
        score: dict[int, float] = {}
        count: dict[int, int] = {}
        for fid, w in nb.items():
            for g in gm.get(fid, ()):
                score[g] = score.get(g, 0.0) + w
                count[g] = count.get(g, 0) + 1
        for g in mine:
            score[g] = score.get(g, 0.0) + W_SELF
            count[g] = count.get(g, 0) + 1
        cand = []
        for g, s in score.items():
            gp = files.get(g)
            if not gp or gp[0] in shown or g == cid:
                continue
            size = _members(db, g)
            cand.append((-(s / math.log2(2 + size)), natural_key(gp[3]) if valid(gp[3]) else (), gp[1], gp[0], g, s, size, count[g]))
        cand.sort()
        out["total"] = len(cand)
        for neg, _k, title, path, g, s, size, c in cand[:limit]:
            fz = files[g][3]
            out["related"].append({"id": fz if valid(fz) else "", "num": abbreviate(fz, numw) if valid(fz) else "",
                                   "path": path, "title": title, "score": round(-neg, 3), "near": c, "size": size,
                                   "own": 1 if g in mine else 0})
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
