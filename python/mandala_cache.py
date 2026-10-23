#!/usr/bin/env python3
"""曼荼羅ビューの速さのための、vault の関係のキャッシュ（SQLite）。派生データで、いつでも作り直せる。

`mandala_view.py dump` は vault 全体を毎回読むので、ノートが増えると遅い（実測: 1 万件で 4 秒・10 万件で 38 秒・件数にほぼ比例）。
こちらは解析結果を `<vault>/.gnosis/cache/mandala.sqlite` に持ち、変わったファイルだけ読み直す。
Vim は全体を持たず、中心ごとに必要な分だけ受け取る（node / ring）。

  mandala_cache.py refresh ROOT [--full] [--only REL…]   更新。--only は指定のノートだけ（保存時）。--full は作り直し
  mandala_cache.py node ROOT ID        {"t","g","o","r","en","i"}（mandala_view.dump の 1 ノート分と同じ形。i は向かってくる親子・文脈・関連）
  mandala_cache.py ring ROOT ID        {"nodes": {ID: 上と同じ, 周りのノート: {"t","g"}}}
  mandala_cache.py nodes ROOT ID…      {"nodes": {ID: 上と同じ, …周りのノート: {"t","g"}}}（Vim が一度に取る）
  mandala_cache.py find ROOT 語…       題に語を全部含む索引（グループ）の相対パス
  mandala_cache.py status ROOT         {"notes", "edges", "stamp"}
  mandala_cache.py near|related ROOT ID / search ROOT 語…   大きな vault 用の近い索引・関連・検索（BIG_VAULT 件を超えたら mandala_view.py が使う）

辺の解決は保存時に行う。あとから足されたノートへ向く壊れたリンクは、そのノートを保存し直すか `--full` で直る。
"""
from __future__ import annotations

import json
import os
import posixpath
import re
import sqlite3
import sys
import time
from pathlib import Path

KINDS = ("group", "branch_group", "parent_branch", "child_branch", "context", "related", "backlink", "link")
_KID = {k: i for i, k in enumerate(KINDS)}
INCOMING = ("parent_branch", "child_branch", "context", "related")   # node の "i"（向かってくる辺）に入れる種類
SCHEMA = 3
_LINK_TEXT = re.compile(r"\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)")
FULL_FLOOR = 0     # 秒。直近の全体の走査から、走査にかかった時間の 20 倍（最低この秒数）が経つまでは、開くときの全体の走査を省く


def _db_path(root: Path) -> Path:
    return root / ".gnosis" / "cache" / "mandala.sqlite"


def connect(root: str | Path, create: bool = False) -> sqlite3.Connection | None:
    root = Path(root)
    p = _db_path(root)
    if not p.exists():
        if not create:
            return None
        p.parent.mkdir(parents=True, exist_ok=True)
        (p.parent / ".gitignore").write_text("*\n", encoding="utf-8")   # 同期（git）に入れない
    db = sqlite3.connect(str(p), timeout=60)
    db.execute("PRAGMA synchronous=OFF")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
        CREATE TABLE IF NOT EXISTS files(id INTEGER PRIMARY KEY, path TEXT UNIQUE, name TEXT, stem TEXT,
            mtime INTEGER, size INTEGER, title TEXT, g INTEGER);
        CREATE INDEX IF NOT EXISTS files_name ON files(name);
        CREATE INDEX IF NOT EXISTS files_stem ON files(stem);
        CREATE TABLE IF NOT EXISTS edges(src INTEGER, kind INTEGER, dst INTEGER);
        CREATE INDEX IF NOT EXISTS edges_src ON edges(src);
        CREATE INDEX IF NOT EXISTS edges_dst ON edges(dst);
        CREATE TABLE IF NOT EXISTS ents(grp INTEGER, dst INTEGER, name TEXT);
        CREATE INDEX IF NOT EXISTS ents_grp ON ents(grp);
    """)
    v = db.execute("SELECT v FROM meta WHERE k='schema'").fetchone()
    if v is None:
        db.execute("INSERT INTO meta VALUES('schema', ?)", (str(SCHEMA),))
        db.commit()
    elif int(v[0]) != SCHEMA:
        db.close()
        if not create:
            return None
        p.unlink()
        return connect(root, True)
    return db


# ---- 解析（作る側。重い取り込みは必要なときだけ） ------------------------------------------------

_G: dict = {}


def _resolver(known: set[str] | None, byname: dict[str, list[str]] | None, db: sqlite3.Connection | None):
    def has(rel: str) -> bool:
        if known is not None:
            return rel in known
        return db.execute("SELECT 1 FROM files WHERE path=?", (rel,)).fetchone() is not None

    def by(key: str) -> list[str]:
        if byname is not None:
            return byname.get(key, [])
        return [r[0] for r in db.execute("SELECT path FROM files WHERE name=? OR stem=?", (key, key))]

    def resolve(src_rel: str, raw: str) -> str | None:
        t = raw.split(" ", 1)[0].strip("<>")
        if "://" in t or t.startswith(("mailto:", "#", "memo:")):
            return None
        tp = t.split("#", 1)[0].strip()
        if not tp:
            return None
        if tp.lower().endswith(".md") and not tp.startswith("/"):
            fast = posixpath.normpath(posixpath.join(posixpath.dirname(src_rel), tp))
            if has(fast):
                return fast
        key = posixpath.basename(tp)
        lst = by(key) or by(key[:-3] if key.endswith(".md") else key)
        uniq = set(lst)
        return next(iter(uniq)) if len(uniq) == 1 else None
    return resolve


def _parse_one(rel: str):
    """1 ノートを読む: (rel, 題, 索引か, [(種類, 行き先)…], [(行き先, 名前)…])。mandala_view.dump と同じ規則。"""
    import note_format_v2 as nf
    import gnosis_graph as gg
    root: Path = _G["root"]
    resolve = _G["resolve"]
    p = root / rel
    try:
        text = p.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    d = nf._simple_parse_text(p, text)
    fm = "\n".join(d["fm"])
    is_group = bool(nf._GROUP_ATTR_RE.search(fm)) or rel == "index.md"
    body_lines, bg_lines, in_bg = [], [], False
    for ln in d["body"]:
        if ln.strip() in (nf.BRANCH_GROUP_HEAD, nf.LEGACY_THIS_NOTE_GROUP_HEAD):
            in_bg = True
            continue
        (bg_lines if in_bg else body_lines).append(ln)
    sets = [("branch_group", bg_lines), ("link", body_lines)] + [(k, d[s]) for s, k in gg._SECTIONS]
    edges: list[tuple[str, str]] = []
    for kind, lines in sets:
        if kind not in _KID:
            continue
        for raw in gg._links(lines):
            dst = resolve(rel, gg._target(raw))
            if dst is not None and dst != rel and (kind, dst) not in edges:
                edges.append((kind, dst))
    ents: list[tuple[str, str]] = []
    if is_group:
        for ln in d["body"]:
            for m in _LINK_TEXT.finditer(ln):
                name = re.sub(r"\\(.)", r"\1", m.group(1)).strip()
                t = m.group(2).split(" ", 1)[0].strip("<>")
                if not name or "://" in t or t.startswith(("mailto:", "#", "memo:")):
                    continue
                dst = resolve(rel, t)
                if dst is not None and dst != rel and (dst, name) not in ents:
                    ents.append((dst, name))
    return rel, d["title"], int(is_group), edges, ents


def _walk(root: Path) -> dict[str, tuple[int, int]]:
    """{相対パス: (更新時刻, 大きさ)}。ドット始まりの中は降りない（nf._iter_md と同じ）。"""
    out: dict[str, tuple[int, int]] = {}
    stack = [("", root)]
    while stack:
        prefix, d = stack.pop()
        try:
            it = os.scandir(d)
        except OSError:
            continue
        with it:
            for e in it:
                n = e.name
                if e.is_dir(follow_symlinks=False):
                    if not n.startswith(".") and n != "_expand_tmp":
                        stack.append((prefix + n + "/", Path(e.path)))
                elif n.endswith(".md") and not n.startswith("."):
                    try:
                        st = e.stat()
                    except OSError:
                        continue
                    out[prefix + n] = (st.st_mtime_ns, st.st_size)
    return out


def _ids(db: sqlite3.Connection, paths) -> dict[str, int]:
    paths = list(set(paths))
    out: dict[str, int] = {}
    for i in range(0, len(paths), 500):
        chunk = paths[i:i + 500]
        out.update(db.execute(f"SELECT path,id FROM files WHERE path IN ({','.join('?' * len(chunk))})", chunk))
    return out


def _write(db: sqlite3.Connection, root: Path, rels: list[str], stats: dict, resolve) -> None:
    """rels を読み直して書く。まず files に入れて id を決め、そのあと辺を入れる。"""
    import multiprocessing
    _G["root"], _G["resolve"] = root, resolve
    if len(rels) > 400 and (os.cpu_count() or 1) > 1:
        ctx = multiprocessing.get_context("fork")
        with ctx.Pool(min(os.cpu_count() or 2, 8)) as pool:
            rows = list(pool.imap(_parse_one, rels, chunksize=200))
    else:
        rows = [_parse_one(r) for r in rels]
    for rel, row in zip(rels, rows):
        if row is None:
            continue
        _rel, title, g, _e, _n = row
        st = stats[rel]
        db.execute("INSERT INTO files(path,name,stem,mtime,size,title,g) VALUES(?,?,?,?,?,?,?) "
                   "ON CONFLICT(path) DO UPDATE SET mtime=excluded.mtime,size=excluded.size,title=excluded.title,g=excluded.g",
                   (rel, posixpath.basename(rel), posixpath.splitext(posixpath.basename(rel))[0], st[0], st[1], title, g))
    need = {r[0] for r in rows if r is not None}
    for r in rows:
        if r is not None:
            need.update(d for _k, d in r[3])
            need.update(d for d, _n in r[4])
    ids = dict(db.execute("SELECT path, id FROM files")) if len(need) > 5000 else _ids(db, need)
    e_rows, n_rows = [], []
    for row in rows:
        if row is None:
            continue
        rel, _t, _g, edges, ents = row
        src = ids[rel]
        for kind, dst in edges:
            if dst in ids:
                e_rows.append((src, _KID[kind], ids[dst]))
        for dst, name in ents:
            if dst in ids:
                n_rows.append((src, ids[dst], name))
    db.executemany("INSERT INTO edges VALUES(?,?,?)", e_rows)
    db.executemany("INSERT INTO ents VALUES(?,?,?)", n_rows)


def _forget(db: sqlite3.Connection, ids: list[int], drop_in: bool) -> None:
    for chunk in (ids[i:i + 500] for i in range(0, len(ids), 500)):
        q = ",".join("?" * len(chunk))
        db.execute(f"DELETE FROM edges WHERE src IN ({q})", chunk)
        db.execute(f"DELETE FROM ents WHERE grp IN ({q})", chunk)
        if drop_in:   # ファイルが消えた: 向かってくる辺・索引の項目も消す
            db.execute(f"DELETE FROM edges WHERE dst IN ({q})", chunk)
            db.execute(f"DELETE FROM ents WHERE dst IN ({q})", chunk)
            db.execute(f"DELETE FROM files WHERE id IN ({q})", chunk)


def _take_dirty(root: Path) -> list[str]:
    """Vim が保存のたびに足していく `dirty`（保存したノートの相対パス）を受け取って空にする。"""
    p = root / ".gnosis" / "cache" / "dirty"
    try:
        text = p.read_text(encoding="utf-8")
        p.unlink()
    except OSError:
        return []
    out: list[str] = []
    for ln in text.split("\n"):
        ln = ln.strip()
        if ln and ln not in out:
            out.append(ln)
    return out


def refresh(root: str | Path, full: bool = False, only: list[str] | None = None, force: bool = False) -> dict:
    """キャッシュを更新する。only があればそのノートだけ。full は作り直し。force でなければ、直近に全体を走査していたら省く。"""
    root = Path(root).resolve()
    t0 = time.time()
    if full:
        p = _db_path(root)
        if p.exists():
            p.unlink()
    db = connect(root, create=True)
    try:
        if only is not None:
            ids = _ids(db, only)
            gone, todo, stats = [], [], {}
            for rel in only:
                f = root / rel
                if f.is_file():
                    st = f.stat()
                    stats[rel] = (st.st_mtime_ns, st.st_size)
                    todo.append(rel)
                elif rel in ids:
                    gone.append(ids[rel])
            _forget(db, gone, True)
            _forget(db, [ids[r] for r in todo if r in ids], False)
            _write(db, root, todo, stats, _resolver(None, None, db))
            db.commit()
            return {"changed": len(todo), "removed": len(gone), "sec": round(time.time() - t0, 2)}
        pend = _take_dirty(root)
        if pend:
            db.close()
            r = refresh(root, only=pend)
            db = connect(root, create=True)
            r["pending"] = len(pend)
        last = db.execute("SELECT v FROM meta WHERE k='stamp'").fetchone()
        took = db.execute("SELECT v FROM meta WHERE k='scan_sec'").fetchone()
        wait = max(FULL_FLOOR, 20 * float(took[0])) if took else FULL_FLOOR
        if last and not force and not full and time.time() - float(last[0]) < wait:
            return {"changed": len(pend), "removed": 0, "skipped": True, "sec": 0.0}
        t1 = time.time()
        found = _walk(root)
        walk_sec = time.time() - t1
        have = {p: (i, m, s) for i, p, m, s in db.execute("SELECT id, path, mtime, size FROM files")}
        todo = [r for r, ms in found.items() if r not in have or have[r][1:] != ms]
        gone = [have[r][0] for r in have if r not in found]
        _forget(db, gone, True)
        _forget(db, [have[r][0] for r in todo if r in have], False)
        byname: dict[str, list[str]] = {}
        for r in found:
            b = posixpath.basename(r)
            byname.setdefault(b, []).append(r)
            byname.setdefault(b[:-3], []).append(r)
        _write(db, root, todo, found, _resolver(set(found), byname, None))
        db.execute("INSERT OR REPLACE INTO meta VALUES('stamp', ?)", (str(time.time()),))
        db.execute("INSERT OR REPLACE INTO meta VALUES('scan_sec', ?)", (str(walk_sec),))
        db.commit()
        return {"changed": len(todo), "removed": len(gone), "notes": len(found), "sec": round(time.time() - t0, 2)}
    finally:
        db.close()


# ---- 読む側（Vim から呼ばれる。速さのため重い import はしない） -------------------------------------

def _paths(db: sqlite3.Connection, ids) -> dict[int, tuple[str, str, int]]:
    out = {}
    ids = list(ids)
    for i in range(0, len(ids), 500):
        chunk = ids[i:i + 500]
        for fid, path, title, g in db.execute(f"SELECT id,path,title,g FROM files WHERE id IN ({','.join('?' * len(chunk))})", chunk):
            out[fid] = (path, title, g)
    return out


def _node(db: sqlite3.Connection, rel: str) -> tuple[dict | None, set[int]]:
    """1 ノートの full（mandala_view.dump の形）と、それが指す id の集まり。"""
    row = db.execute("SELECT id,title,g FROM files WHERE path=?", (rel,)).fetchone()
    if row is None:
        return None, set()
    fid, title, g = row
    refs: set[int] = set()
    o: dict[str, list[int]] = {}
    for kind, dst in db.execute("SELECT kind,dst FROM edges WHERE src=? ORDER BY rowid", (fid,)):
        lst = o.setdefault(KINDS[kind], [])
        if dst not in lst:
            lst.append(dst)
        refs.add(dst)
    back = [s for (s,) in db.execute("SELECT DISTINCT src FROM edges WHERE dst=? AND kind=?", (fid, _KID["branch_group"]))]
    refs.update(back)
    # 向かってくる辺（相手のファイルにだけ書かれていて、こちらには書かれていない親子・文脈・関連も見えるように）
    inc: dict[str, list[int]] = {}
    for kind in INCOMING:
        ids = [s for (s,) in db.execute("SELECT DISTINCT src FROM edges WHERE dst=? AND kind=? LIMIT 300", (fid, _KID[kind]))]
        if ids:
            inc[kind] = ids
            refs.update(ids)
    ents = list(db.execute("SELECT dst,name FROM ents WHERE grp=? ORDER BY rowid", (fid,))) if g else []
    refs.update(d for d, _n in ents)
    pm = _paths(db, refs)
    nd: dict = {"t": title, "g": int(g), "o": {k: [pm[i][0] for i in v if i in pm] for k, v in o.items()}}
    if back:
        nd["r"] = {"branch_group": sorted(pm[i][0] for i in back if i in pm)}
    if inc:
        nd["i"] = {k: [pm[i][0] for i in v if i in pm] for k, v in inc.items()}
    if ents:
        nd["en"] = [[pm[d][0], "" if n == pm[d][1] else n] for d, n in ents if d in pm]
    return nd, refs


def node(root: str | Path, rel: str) -> dict | None:
    db = connect(root)
    if db is None:
        return None
    try:
        return _node(db, rel)[0]
    finally:
        db.close()


def ring(root: str | Path, rel: str) -> dict:
    db = connect(root)
    if db is None:
        return {"nodes": {}}
    try:
        nd, refs = _node(db, rel)
        if nd is None:
            return {"nodes": {}}
        nodes = {rel: nd}
        for _fid, (path, title, g) in _paths(db, refs).items():
            nodes.setdefault(path, {"t": title, "g": int(g)})
        return {"nodes": nodes}
    finally:
        db.close()


def nodes(root: str | Path, rels: list[str]) -> dict:
    """rels の full と、それらが指すノートの light（Vim が一度に取る）。"""
    db = connect(root)
    if db is None:
        return {"nodes": {}}
    try:
        out: dict[str, dict] = {}
        refs: set[int] = set()
        for rel in rels:
            nd, rf = _node(db, rel)
            if nd is not None:
                out[rel] = nd
                refs |= rf
        for _fid, (path, title, g) in _paths(db, refs).items():
            out.setdefault(path, {"t": title, "g": int(g)})
        return {"nodes": out}
    finally:
        db.close()


def find(root: str | Path, words: list[str], limit: int = 500) -> list[str]:
    """題に words を全部含む索引（グループ）。"""
    db = connect(root)
    if db is None:
        return []
    try:
        ws = [w.lower() for w in words if w]
        out = []
        for path, title in db.execute("SELECT path,title FROM files WHERE g=1 ORDER BY path"):
            t = title.lower()
            if all(w in t for w in ws):
                out.append(path)
                if len(out) >= limit:
                    break
        return out
    finally:
        db.close()


# ---- 大きな vault 用の近い索引・関連・検索（全体を読まず、キャッシュと狭い候補だけで求める） ----------------------------
# ノートが BIG_VAULT を超えたら mandala_view.py の near / related / search はこちらを使う（小さな vault は従来の全体計算のまま）。
# 従来の計算との違い: Folgezettel の枝・本文の内容（TF-IDF）・歩いた近さは使わない。つながりと題の言葉だけ。
BIG_VAULT = 20000
_CJK = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uff66-\uff9f]+")
_WORDS = re.compile(r"[a-z0-9]{2,}")


def is_big(root: str | Path) -> bool:
    db = connect(root)
    if db is None:
        return False
    try:
        return db.execute("SELECT COUNT(*) FROM files").fetchone()[0] > BIG_VAULT
    finally:
        db.close()


def _tokens(title: str) -> set[str]:
    t = title.lower()
    out = set(_WORDS.findall(t))
    for run in _CJK.findall(t):
        if len(run) == 1:
            out.add(run)
        else:
            out.update(run[i:i + 2] for i in range(len(run) - 1))
    return out


def _neighbors(db: sqlite3.Connection, fid: int) -> dict[int, set[str]]:
    """fid と辺でつながるノート {id: {種類…}}（向きは問わない）。"""
    out: dict[int, set[str]] = {}
    for dst, k in db.execute("SELECT dst,kind FROM edges WHERE src=?", (fid,)):
        out.setdefault(dst, set()).add(KINDS[k])
    for src, k in db.execute("SELECT src,kind FROM edges WHERE dst=? LIMIT 5000", (fid,)):
        out.setdefault(src, set()).add("in:" + KINDS[k])
    out.pop(fid, None)
    return out


def near(root: str | Path, rel: str, limit: int = 60) -> list[dict]:
    db = connect(root)
    if db is None:
        return []
    try:
        row = db.execute("SELECT id,title FROM files WHERE path=?", (rel,)).fetchone()
        if row is None:
            return []
        fid, title = row
        nb = _neighbors(db, fid)
        mine = {d for d, ks in nb.items() if "group" in ks or "branch_group" in ks}   # すでに所属している索引
        mine |= {s for s, in db.execute("SELECT src FROM edges WHERE dst=? AND kind=? AND src IN (SELECT id FROM files WHERE g=1)", (fid, _KID["link"]))}
        score: dict[int, float] = {}
        why: dict[int, dict[str, float]] = {}
        nbl = list(nb)
        for i in range(0, len(nbl), 500):
            chunk = nbl[i:i + 500]
            q = ",".join("?" * len(chunk))
            # 近所のノートが載っている索引（索引 → ノート の link、ノート → 索引 の group / branch_group）
            for g, c in db.execute(f"SELECT src, COUNT(*) FROM edges WHERE kind=? AND dst IN ({q}) AND src IN (SELECT id FROM files WHERE g=1) GROUP BY src", [_KID["link"], *chunk]):
                score[g] = score.get(g, 0.0) + 2.0 * min(c, 5)
                why.setdefault(g, {})[f"つながり {c}"] = 2.0 * min(c, 5)
            for g, c in db.execute(f"SELECT dst, COUNT(*) FROM edges WHERE kind IN (?,?) AND src IN ({q}) GROUP BY dst", [_KID["group"], _KID["branch_group"], *chunk]):
                score[g] = score.get(g, 0.0) + 2.0 * min(c, 5)
                why.setdefault(g, {})[f"つながり {c}"] = 2.0 * min(c, 5)
        mt = _tokens(title)
        if mt:
            for g, gt in db.execute("SELECT id,title FROM files WHERE g=1"):
                common = _tokens(gt) & mt
                if common:
                    pts = 2.0 * min(len(common), 2)
                    score[g] = score.get(g, 0.0) + pts
                    why.setdefault(g, {})["題が近い"] = pts
        for g in list(score):
            if g == fid or g in mine:
                del score[g]
        top = sorted(score.items(), key=lambda kv: -kv[1])[:limit]
        pm = _paths(db, [g for g, _v in top])
        return [{"id": pm[g][0], "score": round(v, 2),
                 "why": [k for k, _x in sorted(why[g].items(), key=lambda kv: -kv[1])]} for g, v in top if g in pm]
    finally:
        db.close()


_REL_OUT = {"parent_branch": ("親", 5.0), "child_branch": ("子", 5.0), "context": ("Context", 4.0), "related": ("関連", 4.0),
            "link": ("リンク", 3.0), "backlink": ("BackLink", 3.0), "group": ("所属の索引", 3.0), "branch_group": ("所属の索引", 3.0)}


def related(root: str | Path, rel: str, limit: int = 80) -> list[dict]:
    db = connect(root)
    if db is None:
        return []
    try:
        row = db.execute("SELECT id,title FROM files WHERE path=?", (rel,)).fetchone()
        if row is None:
            return []
        fid, title = row
        nb = _neighbors(db, fid)
        score: dict[int, dict[str, float]] = {}

        def add(x: int, why: str, pts: float) -> None:
            if x != fid:
                d = score.setdefault(x, {})
                d[why] = max(d.get(why, 0.0), pts)
        groups = set()
        for d, ks in nb.items():
            for k in ks:
                kk = k[3:] if k.startswith("in:") else k
                if kk in _REL_OUT:
                    add(d, *_REL_OUT[kk])
            if "group" in ks or "branch_group" in ks:
                groups.add(d)
            if "in:link" in ks:
                row = db.execute("SELECT g FROM files WHERE id=?", (d,)).fetchone()
                if row and row[0]:
                    groups.add(d)
        # 同じ索引に載っているノート
        for g in list(groups)[:20]:
            gname = db.execute("SELECT title FROM files WHERE id=?", (g,)).fetchone()
            for m, in db.execute("SELECT dst FROM edges WHERE src=? AND kind=? LIMIT 300", (g, _KID["link"])):
                add(m, "同じ索引: " + (gname[0] if gname else ""), 2.0)
            for m, in db.execute("SELECT src FROM edges WHERE dst=? AND kind IN (?,?) LIMIT 300", (g, _KID["group"], _KID["branch_group"])):
                add(m, "同じ索引: " + (gname[0] if gname else ""), 2.0)
        # 近所の近所（2 歩先）
        for d in list(nb)[:50]:
            for x, in db.execute("SELECT dst FROM edges WHERE src=? LIMIT 50", (d,)):
                add(x, "つながりが近い", 1.5)
        # 題の言葉（候補の中だけ）
        mt = _tokens(title)
        if mt and score:
            pm = _paths(db, list(score))
            for x, (_p, t, _g) in pm.items():
                common = _tokens(t) & mt
                if common:
                    add(x, "題が近い", min(1.5 * len(common), 4.0))
        top = sorted(((x, sum(w.values()), w) for x, w in score.items()), key=lambda r: -r[1])[:limit]
        pm = _paths(db, [x for x, _s, _w in top])
        return [{"id": pm[x][0], "score": round(sc, 2), "why": [k for k, _v in sorted(w.items(), key=lambda kv: -kv[1])]}
                for x, sc, w in top if x in pm]
    finally:
        db.close()


def search(root: str | Path, words: list[str], limit: int = 200) -> list[str]:
    """題か本文に words を全部含むノート。題に合うものが先。本文は ripgrep があればそれで探す。"""
    db = connect(root)
    if db is None:
        return []
    ws = [w.lower() for w in words if w]
    if not ws:
        return []
    try:
        title_hits = [p for p, t in db.execute("SELECT path,title FROM files ORDER BY path") if all(w in t.lower() for w in ws)][:limit]
    finally:
        db.close()
    out = list(title_hits)
    seen = set(out)
    import shutil
    import subprocess
    root_p = Path(root)
    if shutil.which("rg") and len(out) < limit:
        try:
            r = subprocess.run(["rg", "-l", "-i", "-F", "--glob", "*.md", "-e", ws[0], str(root_p)], capture_output=True, text=True, timeout=60)
            for ln in r.stdout.split("\n"):
                if not ln.strip() or len(out) >= limit:
                    continue
                try:
                    rel = Path(ln).relative_to(root_p).as_posix()
                except ValueError:
                    continue
                if rel in seen or rel.startswith("."):
                    continue
                try:
                    body = (root_p / rel).read_text(encoding="utf-8").lower()
                except (OSError, UnicodeDecodeError):
                    continue
                if all(w in body for w in ws):
                    out.append(rel)
                    seen.add(rel)
        except (OSError, subprocess.TimeoutExpired):
            pass
    return out


def status(root: str | Path) -> dict:
    db = connect(root)
    if db is None:
        return {"notes": 0, "edges": 0, "stamp": 0, "scan_sec": 0.0}
    try:
        st = db.execute("SELECT v FROM meta WHERE k='stamp'").fetchone()
        took = db.execute("SELECT v FROM meta WHERE k='scan_sec'").fetchone()
        return {"notes": db.execute("SELECT COUNT(*) FROM files").fetchone()[0],
                "edges": db.execute("SELECT COUNT(*) FROM edges").fetchone()[0],
                "stamp": float(st[0]) if st else 0, "scan_sec": float(took[0]) if took else 0.0}
    finally:
        db.close()


def main(argv: list[str]) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    if len(argv) >= 3 and argv[1] == "refresh":
        rest = argv[3:]
        only = rest[rest.index("--only") + 1:] if "--only" in rest else None
        out = refresh(argv[2], full="--full" in rest, only=only, force="--force" in rest)
    elif len(argv) >= 4 and argv[1] == "node":
        out = node(argv[2], argv[3])
    elif len(argv) >= 4 and argv[1] == "ring":
        out = ring(argv[2], argv[3])
    elif len(argv) >= 4 and argv[1] == "nodes":
        out = nodes(argv[2], argv[3:])
    elif len(argv) >= 4 and argv[1] == "near":
        out = near(argv[2], argv[3])
    elif len(argv) >= 4 and argv[1] == "related":
        out = related(argv[2], argv[3])
    elif len(argv) >= 4 and argv[1] == "search":
        out = search(argv[2], argv[3:])
    elif len(argv) >= 3 and argv[1] == "isbig":
        out = is_big(argv[2])
    elif len(argv) >= 4 and argv[1] == "find":
        out = find(argv[2], argv[3:])
    elif len(argv) >= 3 and argv[1] == "status":
        out = status(argv[2])
    else:
        print(__doc__, file=sys.stderr)
        return 2
    json.dump(out, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
