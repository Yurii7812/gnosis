#!/usr/bin/env python3
"""vault の検索インデックス（SR01〜SR09・SR15 の核）。原本は Markdown のまま。インデックスは派生キャッシュで、消しても作り直せる。

保存先: <vault>/.gnosis/cache/index.sqlite（ドット始まり。バックアップ・書き出し・各走査の対象外）。
更新は差分（mtime と大きさ）。ノート・索引・リンクは書き換えない。

クエリ（空白区切りで AND。`OR` で区切ると OR）:
  語 / "フレーズ"        … 題か本文に含む（大文字小文字を区別しない。日本語の 1〜2 文字の語も引ける）
  -語                   … 含まない
  /正規表現/             … 本文に一致（Python の re）
  title:語  fz:1a*  date:2026-10  before:2026-10-15  after:2026-10-01
  type:group|note|diary   has:image|task|link   links>3  backlinks>=1
  in:索引.md             … そのノートから辿れる範囲（Index → 最初のノート → GroupBranch …。実際の到達可能性）
CLI（JSON）:
  vault_index.py ROOT update
  vault_index.py ROOT search 'クエリ' [--limit N]
  vault_index.py ROOT fuzzy '語'                 … 題・番号・ファイル名のあいまい検索
  vault_index.py ROOT saved list|add NAME 'クエリ'|run NAME|del NAME
  vault_index.py ROOT dynamic 'クエリ' [--promote FILE]   … 結果を読み取り専用の Markdown にする。--promote は明示のときだけ新規ノートに書く
"""
from __future__ import annotations

import json
import os
import re
import shlex
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import folgezettel as fz  # noqa: E402
import note_format_v2 as nf  # noqa: E402

SCHEMA = 2
LINK_RE = nf.ANY_LINK_RE
DIARY_TITLE = re.compile(r"^\d{4}-\d{2}-\d{2}(-[A-Z]{2})?$")


def db_path(root: Path) -> Path:
    return root / ".gnosis" / "cache" / "index.sqlite"


def _connect(root: Path) -> sqlite3.Connection:
    p = db_path(root)
    p.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(p)
    con.row_factory = sqlite3.Row
    ver = con.execute("pragma user_version").fetchone()[0]
    if ver != SCHEMA:                      # 形が違えば作り直す（派生物なので捨ててよい）
        con.close()
        p.unlink(missing_ok=True)
        con = sqlite3.connect(p)
        con.row_factory = sqlite3.Row
        con.executescript("""
            create table notes(id integer primary key, path text unique, name text, title text, fz text, is_group int,
                               created text, mtime_ns integer, size integer, body text, has_image int, has_task int,
                               n_links int, kind text, line0 int);
            create table links(src integer, target text);
            create index links_target on links(target);
            create virtual table fts using fts5(title, body, tokenize='trigram');
        """)
        con.execute(f"pragma user_version={SCHEMA}")
        con.commit()
    return con


def _walk(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".") and d != nf.EXPAND_TMP_DIR]
        for name in sorted(filenames):
            if name.endswith(".md") and not name.startswith("."):
                yield Path(dirpath) / name


def _target_name(raw: str) -> str:
    t = raw.split(" ", 1)[0].strip("<>").split("#", 1)[0]
    if not t or "://" in t or t.startswith(("mailto:", "memo:")):
        return ""
    return os.path.basename(t)[:-3] if t.lower().endswith(".md") else ""


def update(root: str | Path) -> dict:
    """差分更新。返り値: {added, changed, removed, total}。"""
    root = Path(root).resolve()
    con = _connect(root)
    have = {r["path"]: (r["id"], r["mtime_ns"], r["size"]) for r in con.execute("select id,path,mtime_ns,size from notes")}
    seen = set()
    added = changed = 0
    for p in _walk(root):
        rel = p.relative_to(root).as_posix()
        seen.add(rel)
        st = p.stat()
        old = have.get(rel)
        if old and old[1] == st.st_mtime_ns and old[2] == st.st_size:
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        d = nf._simple_parse_text(p, text)
        fm = "\n".join(d["fm"])
        body = text.split("\n---\n", 1)[1] if text.startswith("---\n") and "\n---\n" in text else text
        body = body.lstrip("\n")
        line0 = text.count("\n", 0, len(text) - len(body))      # 本文の前（front matter など）の行数。ヒット行をファイルの行番号に直すのに使う
        created = next((ln.split(":", 1)[1].strip()[:10] for ln in d["fm"] if ln.startswith("time:")), "")
        group = bool(nf._GROUP_ATTR_RE.search(fm))
        kind = "group" if group else "diary" if DIARY_TITLE.match(d["title"]) else "note"
        targets = [t for t in (_target_name(m.group(1)) for m in LINK_RE.finditer(body)) if t]
        row = (rel, p.stem, d["title"], fz.value(text), int(group), created, st.st_mtime_ns, st.st_size, body,
               int(bool(re.search(r"!\[[^\]]*\]\(", body))), int(bool(re.search(r"^\s*[-*+] \[[ xX]\]", body, re.M))), len(targets), kind, line0)
        if old:
            nid = old[0]
            con.execute("update notes set path=?,name=?,title=?,fz=?,is_group=?,created=?,mtime_ns=?,size=?,body=?,has_image=?,has_task=?,n_links=?,kind=?,line0=? where id=?", row + (nid,))
            con.execute("delete from links where src=?", (nid,))
            con.execute("delete from fts where rowid=?", (nid,))
            changed += 1
        else:
            nid = con.execute("insert into notes(path,name,title,fz,is_group,created,mtime_ns,size,body,has_image,has_task,n_links,kind,line0) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", row).lastrowid
            added += 1
        con.execute("insert into fts(rowid,title,body) values (?,?,?)", (nid, d["title"], body))
        con.executemany("insert into links(src,target) values (?,?)", [(nid, t) for t in targets])
    gone = [(i,) for rel, (i, _, _) in have.items() if rel not in seen]
    for (i,) in gone:
        con.execute("delete from notes where id=?", (i,))
        con.execute("delete from links where src=?", (i,))
        con.execute("delete from fts where rowid=?", (i,))
    con.commit()
    total = con.execute("select count(*) from notes").fetchone()[0]
    con.close()
    return {"added": added, "changed": changed, "removed": len(gone), "total": total}


# ---------------------------------------------------------------- クエリ

FIELD_RE = re.compile(r"^(title|fz|date|before|after|type|has|in):(.*)$", re.I)
CMP_RE = re.compile(r"^(links|backlinks)(>=|<=|>|<|=)(\d+)$", re.I)


def parse(query: str) -> list[list[dict]]:
    """OR で分けた AND 群のリスト。各条件は {op, ...}。"""
    try:
        toks = shlex.split(query.replace("“", '"').replace("”", '"'), posix=True)
    except ValueError:
        toks = query.split()
    groups: list[list[dict]] = [[]]
    for t in toks:
        if t == "OR":
            groups.append([])
            continue
        neg = t.startswith("-") and len(t) > 1
        body = t[1:] if neg else t
        c: dict
        if len(body) >= 2 and body.startswith("/") and body.endswith("/"):
            c = {"op": "regex", "v": body[1:-1]}
        elif (m := CMP_RE.match(body)):
            c = {"op": m.group(1).lower(), "cmp": m.group(2), "v": int(m.group(3))}
        elif (m := FIELD_RE.match(body)):
            c = {"op": m.group(1).lower(), "v": m.group(2)}
        else:
            c = {"op": "text", "v": body}
        c["neg"] = neg
        groups[-1].append(c)
    return [g for g in groups if g] or [[]]


def _fts_phrase(term: str) -> str:
    return '"' + term.replace('"', '""') + '"'


def _where(group: list[dict], params: list, scope_ids: set[int] | None) -> list[str]:
    sql = []
    for c in group:
        op, neg = c["op"], c["neg"]
        if op == "text":
            v = c["v"].lower()
            cond = "instr(lower(n.title || char(10) || n.body), ?) > 0"
            p = [v]
            if len(v) >= 3:                 # 3 文字以上は FTS（trigram）で先に絞る。1〜2 文字は部分一致で確かめる
                cond = f"(n.id in (select rowid from fts where fts match ?) and {cond})"
                p = [_fts_phrase(c["v"])] + p
            sql.append(("not " if neg else "") + cond)
            params.extend(p)
        elif op == "title":
            sql.append(("not " if neg else "") + "instr(lower(n.title), ?) > 0")
            params.append(c["v"].lower())
        elif op == "fz":
            v = c["v"]
            if v.endswith("*"):
                sql.append(("not " if neg else "") + "n.fz like ?")
                params.append(v[:-1].replace("%", "") + "%")
            else:
                sql.append(("not " if neg else "") + "n.fz = ?")
                params.append(v)
        elif op == "date":
            sql.append(("not " if neg else "") + "n.created like ?")
            params.append(c["v"] + "%")
        elif op == "before":
            sql.append(("not " if neg else "") + "(n.created != '' and n.created < ?)")
            params.append(c["v"])
        elif op == "after":
            sql.append(("not " if neg else "") + "(n.created != '' and n.created > ?)")
            params.append(c["v"])
        elif op == "type":
            sql.append(("not " if neg else "") + "n.kind = ?")
            params.append(c["v"].lower())
        elif op == "has":
            col = {"image": "n.has_image", "task": "n.has_task", "link": "(n.n_links > 0)"}.get(c["v"].lower())
            sql.append(("not " if neg else "") + (col + " = 1" if col and col != "(n.n_links > 0)" else (col or "0")))
        elif op in ("links", "backlinks"):
            expr = "n.n_links" if op == "links" else "(select count(*) from links l where l.target = n.name and l.src != n.id)"
            sql.append(("not " if neg else "") + f"{expr} {c['cmp']} ?")
            params.append(c["v"])
        elif op == "in":
            ids = scope_ids if scope_ids is not None else set()
            sql.append(("not " if neg else "") + "n.id in (" + ",".join(str(i) for i in sorted(ids) or [-1]) + ")")
        # regex は SQL の後で Python で確かめる
    return sql


def _scope_ids(con, root: Path, group: list[dict]) -> set[int] | None:
    ins = [c["v"] for g in group for c in [g] if c["op"] == "in"]
    if not ins:
        return None
    import gnosis_graph as gg
    g = gg.build(root)
    ok = {"link", "branch_group", "child_branch", "related", "context", "group"}
    ids: set[int] = set()
    for start in ins:
        rel = start if start in g.nodes else next((n for n in g.nodes if n.endswith("/" + start) or n == start), None)
        if rel is None:
            continue
        # 親→子（BranchGroup/ChildBranch/リンク）の向き。ParentBranch は子→親なので逆向きに辿る
        out_adj: dict[str, list[str]] = {n: [] for n in g.nodes}
        for e in g.edges:
            if e.kind in ok and not e.derived:
                out_adj[e.src].append(e.dst)
            elif e.kind == "parent_branch":
                out_adj[e.dst].append(e.src)
        seen = {rel}
        stack = [rel]
        while stack:
            for nxt in out_adj.get(stack.pop(), []):
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        for p in seen:
            r = con.execute("select id from notes where path=?", (p,)).fetchone()
            if r:
                ids.add(r[0])
    return ids


def _snippet(body: str, terms: list[str], regexes: list[re.Pattern], width: int = 80, line0: int = 0) -> dict:
    """最初に当たった行と、その中の一致位置（開いた本文には何も足さない。表示側が強調に使う）。"""
    low_terms = [t.lower() for t in terms]
    for i, ln in enumerate(body.split("\n"), 1):
        low = ln.lower()
        spans = []
        for t in low_terms:
            k = low.find(t)
            while k >= 0 and t:
                spans.append([k, k + len(t)])
                k = low.find(t, k + len(t))
        for rx in regexes:
            spans += [[m.start(), m.end()] for m in rx.finditer(ln) if m.end() > m.start()]
        if spans:
            start = max(0, min(s for s, _ in spans) - width // 3)
            text = ln[start:start + width]
            return {"line": line0 + i, "text": text, "ranges": [[s - start, e - start] for s, e in sorted(spans) if s - start < len(text)]}
    return {"line": 0, "text": "", "ranges": []}


def search(root: str | Path, query: str, limit: int = 50, refresh: bool = True) -> list[dict]:
    root = Path(root).resolve()
    if refresh:
        update(root)
    con = _connect(root)
    groups = parse(query)
    out: dict[int, dict] = {}
    for group in groups:
        scope = _scope_ids(con, root, group)
        params: list = []
        conds = _where(group, params, scope)
        sql = "select n.id, n.path, n.title, n.fz, n.body, n.mtime_ns, n.line0 from notes n" + (" where " + " and ".join(conds) if conds else "")
        terms = [c["v"] for c in group if c["op"] == "text" and not c["neg"]]
        regexes = []
        for c in group:
            if c["op"] == "regex":
                try:
                    regexes.append((re.compile(c["v"], re.I), c["neg"]))
                except re.error as e:
                    raise ValueError(f"正規表現が正しくありません: {e}")
        for r in con.execute(sql, params):
            if any(bool(rx.search(r["body"])) == neg for rx, neg in regexes):
                continue
            if r["id"] in out:
                continue
            tl = r["title"].lower()
            tscore = sum(1 for t in terms if t.lower() in tl)   # 題に当たった語が多いほど上（既存の \l と同じ考え方）
            out[r["id"]] = {"path": r["path"], "title": r["title"], "fz": r["fz"], "mtime_ns": r["mtime_ns"], "_t": tscore,
                            **{"snippet": _snippet(r["body"], terms, [rx for rx, neg in regexes if not neg], line0=r["line0"])}}
    rows = sorted(out.values(), key=lambda x: (-x["_t"], -x["mtime_ns"], x["title"]))[:limit]
    for r in rows:
        r.pop("_t"); r.pop("mtime_ns")
    con.close()
    return rows


# ---------------------------------------------------------------- あいまい検索

def _fuzzy_score(q: str, s: str) -> int | None:
    """q の文字が s に順に現れれば得点（連続・語頭・短いほど高い）。現れなければ None。"""
    q, s = q.lower(), s.lower()
    if not q:
        return 0
    pos, score, prev = 0, 0, -2
    for ch in q:
        k = s.find(ch, pos)
        if k < 0:
            return None
        score += 10 + (15 if k == prev + 1 else 0) + (10 if k == 0 or not s[k - 1].isalnum() else 0)
        prev, pos = k, k + 1
    return score - len(s) // 4


def fuzzy(root: str | Path, query: str, limit: int = 50, refresh: bool = True) -> list[dict]:
    root = Path(root).resolve()
    if refresh:
        update(root)
    con = _connect(root)
    rows = []
    for r in con.execute("select path,title,fz,name from notes"):
        best = None
        for field in (r["title"], r["fz"], r["name"]):
            s = _fuzzy_score(query, field or "")
            if s is not None and (best is None or s > best):
                best = s
        if best is not None:
            rows.append({"path": r["path"], "title": r["title"], "fz": r["fz"], "score": best})
    con.close()
    return sorted(rows, key=lambda x: (-x["score"], x["title"]))[:limit]


# ---------------------------------------------------------------- 保存検索・動的索引

def _saved_path(root: Path) -> Path:
    return root / ".gnosis" / "searches.json"


def saved(root: str | Path, action: str, name: str = "", query: str = "") -> object:
    root = Path(root).resolve()
    p = _saved_path(root)
    data = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {"version": 1, "searches": []}
    items = data["searches"]
    if action == "list":
        return items
    if action == "add":
        if not name or not query:
            raise ValueError("名前とクエリが要ります")
        parse(query)
        items[:] = [s for s in items if s["name"] != name] + [{"name": name, "query": query}]
    elif action == "del":
        items[:] = [s for s in items if s["name"] != name]
    elif action == "run":
        s = next((s for s in items if s["name"] == name), None)
        if s is None:
            raise ValueError("保存した検索がありません: " + name)
        return search(root, s["query"])
    else:
        raise ValueError("list / add / run / del")
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".gnosis-tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, p)
    return items


def dynamic_markdown(query: str, results: list[dict], title: str = "") -> str:
    """検索結果を読み取り専用の Markdown にする（動的索引）。どこにも書かない。"""
    lines = [f"# {title or '検索: ' + query}", "", f"クエリ: `{query}` ・ {len(results)} 件（この表は検索結果で、ノートではありません）", ""]
    for r in results:
        lab = (f"{r['fz']} " if r.get("fz") else "") + r["title"].replace("[", "(").replace("]", ")")
        snip = r.get("snippet", {}).get("text", "").strip()
        lines.append(f"- [{lab}]({r['path'].replace(' ', '%20')})" + (f" — {snip}" if snip else ""))
    return "\n".join(lines) + "\n"


def promote(root: str | Path, file: str, query: str, results: list[dict]) -> str:
    """利用者が明示したときだけ、結果を新しいノートとして書く（既存のファイルは上書きしない・索引は書き換えない）。"""
    root = Path(root).resolve()
    target = (root / file).resolve()
    try:
        target.relative_to(root)
    except ValueError:
        raise ValueError("vault の外には書きません")
    text = f"---\ntime: {__import__('datetime').datetime.now():%Y-%m-%d %H:%M:%S}\ntitle: 検索: {query}\n---\n\n" + dynamic_markdown(query, results)
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)   # 既存なら失敗する
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    return str(target.relative_to(root))


def main(argv: list[str]) -> int:
    try:
        if len(argv) >= 2 and argv[1] == "update":
            print(json.dumps(update(argv[0]), ensure_ascii=False))
        elif len(argv) >= 3 and argv[1] == "search":
            lim = int(argv[argv.index("--limit") + 1]) if "--limit" in argv else 50
            print(json.dumps(search(argv[0], argv[2], lim), ensure_ascii=False))
        elif len(argv) >= 3 and argv[1] == "fuzzy":
            print(json.dumps(fuzzy(argv[0], argv[2]), ensure_ascii=False))
        elif len(argv) >= 3 and argv[1] == "saved":
            print(json.dumps(saved(argv[0], argv[2], *(argv[3:5])), ensure_ascii=False))
        elif len(argv) >= 3 and argv[1] == "dynamic":
            res = search(argv[0], argv[2])
            if "--promote" in argv:
                print(json.dumps({"ok": True, "file": promote(argv[0], argv[argv.index("--promote") + 1], argv[2], res)}, ensure_ascii=False))
            else:
                print(dynamic_markdown(argv[2], res), end="")
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError, sqlite3.Error) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
