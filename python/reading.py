#!/usr/bin/env python3
"""読書・学習（LR01 インクリメンタルリーディング・LR07 ハイライト・LR09 進捗・LR10 成熟度・LR11 学習経路・LR12 自己説明・LR13 出典・LR14 ハイライトからノート）。

原本はノートの記述（別の DB は持たない）:
  ==強調した文== (p.12)            … ハイライト。`(p.12)` / `(12ページ)` は任意の位置
  - 📖 書名 120/300 2026-10-21      … 読書の進捗（現在のページ/全ページ・日付）。最新の日付が現在地
  front matter:  source: book|paper|web  author: …  year: …  url: …   … 出典のノート
                 maturity: seed|growing|evergreen                       … 成熟度（**利用者が付ける任意の属性**。自動では付けない・分類は置き換えない）
                 requires: a.md, b.md                                    … 先に読むノート（学習経路）
書くのは、利用者が明示したとき（`progress-set` の追記・`maturity-set` の front matter 1 行・`digest --write` の新規ノート）だけ。
インクリメンタルリーディングの進み具合（次に見る日）だけ `.state/incremental.json` に持つ。

CLI（JSON。--md なら Markdown）:
  reading.py ROOT highlights [NOTE]              ハイライトの一覧（出典ノートとページつき）
  reading.py ROOT digest NOTE [--write NEWFILE]  ハイライトから読書ノートの草稿（--write で新規ノートとして保存）
  reading.py ROOT progress                       読書の進捗（書名ごとの現在地・割合・再開ページ）
  reading.py ROOT progress-set 書名 ページ [全ページ] [YYYY-MM-DD]
  reading.py ROOT maturity [seed|growing|evergreen]   成熟度の一覧と、引き上げの提案（提案だけ）
  reading.py ROOT maturity-set NOTE LEVEL        成熟度を front matter に書く
  reading.py ROOT path NOTE                      そのノートの前に読むべきノートの順序（循環は報告）
  reading.py ROOT sources                        出典ノートと、それを引用しているノート（戻りリンクつき）
  reading.py ROOT explain NOTE ['自分の説明'] [--record]   説明を促す問い。説明を渡すと、要点語(そのまま/一部合う)と触れていない文を調べる。--record で記録して前回と比べる
  reading.py ROOT ir-next [YYYY-MM-DD]           インクリメンタルリーディング: 次に見るハイライト
  reading.py ROOT ir-rate ID again|good|easy [YYYY-MM-DD]
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import local_ai as ai  # noqa: E402
import note_format_v2 as nf  # noqa: E402
import tasks as tk  # noqa: E402

HL = re.compile(r"==(?!=)(.+?)==(?:\s*[（(](?:p\.?\s*(\d+)|(\d+)\s*ページ)[）)])?")
PROG = re.compile(r"📖\s*(.+?)\s+(\d+)\s*/\s*(\d+)\s+(\d{4}-\d{2}-\d{2})\s*$")
PROG_NOTOTAL = re.compile(r"📖\s*(.+?)\s+(\d+)\s+(\d{4}-\d{2}-\d{2})\s*$")
LEVELS = ("seed", "growing", "evergreen")
LEVEL_JA = {"seed": "種（書き始め）", "growing": "育成中", "evergreen": "常緑（完成に近い）"}


def _notes(root: Path):
    for p in tk.iter_notes(root):
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        d = nf._simple_parse_text(p, text)
        fm = {}
        for ln in d["fm"]:
            if ":" in ln and not ln.startswith(" "):
                k, v = ln.split(":", 1)
                fm[k.strip()] = v.strip().strip("'\"")
        yield p, p.relative_to(root).as_posix(), text, d, fm


def _fence_free(text: str):
    fence = False
    for i, raw in enumerate(text.split("\n"), 1):
        if raw.strip().startswith(("```", "~~~")):
            fence = not fence
        elif not fence:
            yield i, raw


def _resolve(root: Path, name: str) -> str:
    for p, rel, _t, d, _fm in _notes(root):
        if rel == name or p.name == name or p.stem == name or d["title"] == name:
            return rel
    raise ValueError("ノートが見つかりません: " + name)


def highlights(root: str | Path, note: str | None = None) -> dict:
    root = Path(root).resolve()
    only = _resolve(root, note) if note else None
    out = []
    for p, rel, text, d, fm in _notes(root):
        if only and rel != only:
            continue
        for i, raw in _fence_free(text):
            for m in HL.finditer(raw):
                page = m.group(2) or m.group(3)
                hid = hashlib.sha1(f"{rel}\0{m.group(1)}".encode("utf-8")).hexdigest()[:10]
                out.append({"id": hid, "file": rel, "line": i, "title": d["title"], "text": m.group(1).strip(), "page": int(page) if page else None, "source": fm.get("source", "")})
    return {"count": len(out), "highlights": out}


def digest(root: str | Path, note: str, write: str | None = None, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    rel = _resolve(root, note)
    h = highlights(root, rel)["highlights"]
    if not h:
        raise ValueError("ハイライト（==…==）がありません")
    title = h[0]["title"]
    link = rel.replace(" ", "%20")
    L = [f"# {title}の読書メモ（ハイライトから）", "", "元のノートのハイライトを集めた草稿です。自分の言葉での要約は、この下に書き足してください。", ""]
    for x in sorted(h, key=lambda x: (x["page"] is None, x["page"] or 0, x["line"])):
        pg = f"（p.{x['page']}）" if x["page"] else ""
        L.append(f"> {x['text']}\n> — [{title}]({link}){pg}\n")
    body = "\n".join(L) + f"\n## 自分の言葉で\n\n\nRelated:\n[{title}]({link})\n"
    res = {"source": rel, "count": len(h), "draft": body}
    if write:
        t = (root / write).resolve()
        try:
            r2 = t.relative_to(root)
        except ValueError:
            raise ValueError("vault の外には書きません") from None
        if any(x.startswith(".") for x in r2.parts) or t.suffix != ".md":
            raise ValueError("書き先は vault の中の .md（ドット始まりのフォルダ以外）にしてください")
        if t.exists():
            raise ValueError("すでにあります（上書きしません）: " + str(r2))
        now = now or dt.datetime.now()
        head = f"---\ntime: {now:%Y-%m-%d %H:%M:%S}\ntitle: {title}の読書メモ\n---\n\n"
        t.parent.mkdir(parents=True, exist_ok=True)
        tmp = t.with_name(t.name + ".tmp")
        tmp.write_text(head + body, encoding="utf-8")
        os.replace(tmp, t)
        res["written"] = r2.as_posix()
    return res


# ---- 進捗 ----
def progress(root: str | Path) -> dict:
    root = Path(root).resolve()
    latest: dict[str, dict] = {}
    for p, rel, text, d, fm in _notes(root):
        for i, raw in _fence_free(text):
            m = PROG.search(raw)
            if m:
                name, cur, tot, day = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
            else:
                m = PROG_NOTOTAL.search(raw)
                if not m:
                    continue
                name, cur, tot, day = m.group(1), int(m.group(2)), 0, m.group(3)
            old = latest.get(name)
            if old is None or (day, i) >= (old["date"], old["line"]):        # 日付が最新のものが現在地（同じ日なら後の行）
                tot = tot or (old["total"] if old else 0)
                latest[name] = {"name": name, "page": cur, "total": tot, "date": day, "file": rel, "line": i}
    rows = []
    for v in latest.values():
        v["percent"] = round(100 * min(v["page"], v["total"]) / v["total"]) if v["total"] else None
        v["finished"] = bool(v["total"] and v["page"] >= v["total"])
        v["resume_page"] = v["page"] if not v["finished"] else None
        rows.append(v)
    return {"books": sorted(rows, key=lambda r: (r["finished"], r["date"]), reverse=False)}


def progress_set(root: str | Path, name: str, page: int, total: int | None = None, day: str | None = None, file: str = "記録.md") -> dict:
    import tracker as tr
    root = Path(root).resolve()
    name = name.strip()
    if not name or "\n" in name or page < 0 or (total is not None and (total <= 0 or page > total)):
        raise ValueError("書名とページ（0 以上、全ページ以下）を指定してください")
    day = day or dt.date.today().isoformat()
    dt.date.fromisoformat(day)
    line = f"- 📖 {name} {page}" + (f"/{total}" if total else "") + f" {day}"
    rel = tr._append(root, file, line, dt.datetime.now())
    return {"added": True, "file": rel, "line": line}


# ---- 成熟度 ----
def _inbound(root: Path) -> dict[str, int]:
    import gnosis_graph as gg
    g = gg.build(root)
    c: dict[str, int] = defaultdict(int)
    for e in g.edges:
        if e.kind == "link" and e.src != e.dst:
            c[e.dst] += 1
    return c


def maturity(root: str | Path, level: str | None = None) -> dict:
    root = Path(root).resolve()
    if level and level not in LEVELS:
        raise ValueError("成熟度は seed / growing / evergreen のどれかです")
    inbound = _inbound(root)
    rows, suggest = [], []
    for p, rel, text, d, fm in _notes(root):
        lv = fm.get("maturity", "")
        if lv not in LEVELS:
            continue
        chars = len(re.sub(r"\s", "", "\n".join(d["body"])))
        rows.append({"path": rel, "title": d["title"], "level": lv, "chars": chars, "inbound": inbound.get(rel, 0)})
        nxt = {"seed": "growing", "growing": "evergreen"}.get(lv)
        if lv == "seed" and chars >= 400 and inbound.get(rel, 0) >= 2:
            suggest.append({"path": rel, "title": d["title"], "from": lv, "to": nxt, "why": f"{chars} 文字・{inbound.get(rel, 0)} 件から参照されている"})
        elif lv == "growing" and chars >= 1500 and inbound.get(rel, 0) >= 4:
            suggest.append({"path": rel, "title": d["title"], "from": lv, "to": nxt, "why": f"{chars} 文字・{inbound.get(rel, 0)} 件から参照されている"})
    counts = {k: sum(1 for r in rows if r["level"] == k) for k in LEVELS}
    return {"counts": counts, "notes": [r for r in rows if not level or r["level"] == level], "suggestions": suggest,
            "note_text": "成熟度は自分で付ける任意の属性です。提案は目安で、自動では書き換えません。"}


def maturity_set(root: str | Path, note: str, level: str) -> dict:
    root = Path(root).resolve()
    if level not in LEVELS:
        raise ValueError("成熟度は seed / growing / evergreen のどれかです")
    rel = _resolve(root, note)
    p = root / rel
    text = p.read_text(encoding="utf-8")
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
        if end is None:
            raise ValueError("front matter が閉じていません")
        for i in range(1, end):
            if re.match(r"^maturity:\s*", lines[i]):
                lines[i] = f"maturity: {level}"
                break
        else:
            lines.insert(end, f"maturity: {level}")
    else:
        lines = ["---", f"maturity: {level}", "---", ""] + lines
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text("\n".join(lines), encoding="utf-8")
    os.replace(tmp, p)
    return {"path": rel, "level": level}


# ---- 学習経路 ----
def learning_path(root: str | Path, note: str) -> dict:
    root = Path(root).resolve()
    goal = _resolve(root, note)
    names: dict[str, str] = {}
    req: dict[str, list[str]] = {}
    for p, rel, text, d, fm in _notes(root):
        names[rel] = d["title"]
        req[rel] = [x.strip() for x in fm.get("requires", "").split(",") if x.strip()]
    def find(n: str) -> str | None:
        for rel in names:
            if rel == n or Path(rel).name == n or Path(rel).stem == n or names[rel] == n:
                return rel
        return None
    order, state, missing, cycle = [], {}, [], None
    stack: list[str] = []
    def visit(n: str):
        nonlocal cycle
        if cycle:
            return
        if state.get(n) == 2:
            return
        if state.get(n) == 1:
            cycle = stack[stack.index(n):] + [n]
            return
        state[n] = 1
        stack.append(n)
        for r in req.get(n, []):
            t = find(r)
            if t is None:
                missing.append({"in": n, "requires": r})
            else:
                visit(t)
        stack.pop()
        state[n] = 2
        order.append(n)
    visit(goal)
    return {"goal": goal, "cycle": [names[x] for x in cycle] if cycle else None, "missing": missing,
            "order": [] if cycle else [{"path": n, "title": names[n]} for n in order]}


# ---- 出典 ----
def sources(root: str | Path) -> dict:
    root = Path(root).resolve()
    srcs: dict[str, dict] = {}
    texts = {}
    for p, rel, text, d, fm in _notes(root):
        texts[rel] = text
        if fm.get("source"):
            srcs[rel] = {"path": rel, "title": d["title"], "kind": fm["source"], "author": fm.get("author", ""), "year": fm.get("year", ""), "url": fm.get("url", ""), "cited_by": []}
    for rel, text in texts.items():
        for i, raw in _fence_free(text):
            for m in re.finditer(r"\]\(([^)#\s]+\.md)(?:#([^)\s]*))?\)", raw):
                tgt = (Path(rel).parent / m.group(1)).as_posix()
                tgt = os.path.normpath(tgt)
                if tgt in srcs and rel != tgt:
                    srcs[tgt]["cited_by"].append({"path": rel, "line": i, "anchor": m.group(2) or "", "text": raw.strip()[:140]})
    return {"sources": sorted(srcs.values(), key=lambda s: s["path"])}


# ---- 自己説明 ----
def _bigrams(t: str) -> set[str]:
    t = re.sub(r"\s+", "", unicodedata.normalize("NFKC", t).lower())
    return {t[i:i + 2] for i in range(len(t) - 1)} if len(t) > 1 else set()


def _contain(part: str, whole: set[str]) -> float:
    """part の 2 文字の連なりのうち、whole に入っている割合。言い換えや活用の違いで一部だけ合うものを拾う目安。"""
    g = _bigrams(part)
    return len(g & whole) / len(g) if g else 0.0


def _ex_path(root: Path) -> Path:
    return root / ".state" / "explain.json"


def explain(root: str | Path, note: str, answer: str | None = None, record: bool = False, today: str | None = None) -> dict:
    """自己説明の見直しの手がかり。**採点でも理解の判定でもない**(文字の連なりの重なりを見るだけ)。

    covered: 要点語がそのまま入っている／partial: 一部の文字の連なりが合う(言い換え・活用の可能性)／missing: 合わない。
    unaddressed: ノートの文のうち、答えに触れていないように見えるもの(最大 5)。record=True で `.state/explain.json` に残し、前回と比べる。"""
    root = Path(root).resolve()
    rel = _resolve(root, note)
    c = ai.Corpus.build(root)
    key = ai.phrases(c, rel, 12)
    title = c.docs[rel]["title"]
    out = {"note": rel, "title": title, "prompts": [f"「{title}」を、初めて聞く人に説明するつもりで書いてください。", "なぜそうなるのか（理由）を 1 つ、具体例を 1 つ入れてください。"]}
    if answer is None:
        out["key_terms_hidden"] = len(key)
        return out
    low = answer.lower()
    ag = _bigrams(answer)
    hit = [k for k in key if k.lower() in low]
    rest = [k for k in key if k.lower() not in low]
    partial = [k for k in rest if len(k) >= 3 and _contain(k, ag) >= 0.6]
    miss = [k for k in rest if k not in partial]
    text = _notes_text(root, rel)
    sents = [x.strip() for x in re.split(r"[。！？!?\n]+", text) if len(re.sub(r"\s", "", x)) >= 12]
    un = [x[:100] for x in sents if _contain(x, ag) < 0.25][:5]
    out.update({"answer_chars": len(re.sub(r"\s", "", answer)), "covered": hit, "partial": partial, "missing": miss, "coverage": round(len(hit) / len(key), 2) if key else None,
                "coverage_loose": round((len(hit) + len(partial)) / len(key), 2) if key else None, "unaddressed": un,
                "note_text": "ノートの要点語と文を、文字の連なりの重なりで見た目安です。言い換えを完全には拾えず、理解の採点でもありません。見直しの手がかりです。"})
    if record:
        day = today or dt.date.today().isoformat()
        st = _json_load(_ex_path(root))
        hist = st.get(rel, [])
        out["previous"] = hist[-1] if hist else None
        out["delta"] = round(out["coverage"] - hist[-1]["coverage"], 2) if hist and hist[-1].get("coverage") is not None and out["coverage"] is not None else None
        hist.append({"date": day, "coverage": out["coverage"], "loose": out["coverage_loose"], "chars": out["answer_chars"]})
        st[rel] = hist[-30:]
        p = _ex_path(root)
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_name(p.name + ".tmp")
        tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
        os.replace(tmp, p)
        out["recorded"] = True
    return out


def _json_load(p: Path) -> dict:
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _notes_text(root: Path, rel: str) -> str:
    d = nf._simple_parse_text(root / rel, (root / rel).read_text(encoding="utf-8"))
    return "\n".join(x for x in d["body"] if not x.lstrip().startswith("#") and x.strip() not in ("ParentBranch:", "ChildBranch:", "Related:", "BackLink:", "Context:") and not re.match(r"^\s*[-*+]?\s*\[[^\]]*\]\([^)]*\)\s*$", x))


# ---- インクリメンタルリーディング ----
def _ir_path(root: Path) -> Path:
    return root / ".state" / "incremental.json"


def _ir_load(root: Path) -> dict:
    try:
        return json.loads(_ir_path(root).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def ir_next(root: str | Path, today: str | None = None) -> dict:
    """期日が来たハイライトを先に、無ければまだ一度も見ていないものを 1 つ。"""
    root = Path(root).resolve()
    day = today or dt.date.today().isoformat()
    st = _ir_load(root)
    hs = highlights(root)["highlights"]
    byid = {h["id"]: h for h in hs}
    due = sorted(((st[i]["due"], i) for i in st if i in byid and st[i]["due"] <= day))
    if due:
        h = byid[due[0][1]]
        return {"item": {**h, "state": "復習", "interval_days": st[h["id"]]["interval"]}, "remaining_due": len(due) - 1,
                "unseen": sum(1 for x in byid if x not in st)}
    unseen = [h for h in hs if h["id"] not in st]
    if unseen:
        return {"item": {**unseen[0], "state": "初回", "interval_days": 0}, "remaining_due": 0, "unseen": len(unseen) - 1}
    return {"item": None, "remaining_due": 0, "unseen": 0, "next_due": min((v["due"] for v in st.values()), default=None)}


def ir_rate(root: str | Path, hid: str, grade: str, today: str | None = None) -> dict:
    root = Path(root).resolve()
    if grade not in ("again", "good", "easy"):
        raise ValueError("評価は again / good / easy のどれかです")
    ids = {h["id"] for h in highlights(root)["highlights"]}
    if hid not in ids:
        raise ValueError("そのハイライトはありません: " + hid)
    day = dt.date.fromisoformat(today) if today else dt.date.today()
    st = _ir_load(root)
    cur = st.get(hid, {"interval": 0, "n": 0})
    if grade == "again":
        interval = 1
    elif grade == "good":
        interval = 3 if cur["interval"] < 1 else max(cur["interval"] + 1, round(cur["interval"] * 2))
    else:
        interval = 7 if cur["interval"] < 1 else round(cur["interval"] * 3.5)
    st[hid] = {"interval": interval, "due": (day + dt.timedelta(days=interval)).isoformat(), "n": cur["n"] + 1, "last": day.isoformat()}
    p = _ir_path(root)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, p)
    return {"id": hid, "interval_days": interval, "due": st[hid]["due"]}


def _l(p, t=None):
    return f"[{t or p}]({p.replace(' ', '%20')})"


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    if kind == "highlights":
        L = [f"# ハイライト {r['count']} 件", ""] + [f"- {x['text']}" + (f"（p.{x['page']}）" if x["page"] else "") + f" — {_l(x['file'], x['title'])}:{x['line']}・ID `{x['id']}`" for x in r["highlights"]]
    elif kind == "digest":
        return r["draft"]
    elif kind == "progress":
        L = ["# 読書の進捗", ""]
        for b in r["books"]:
            bar = f"{b['page']}/{b['total']}（{b['percent']}%）" if b["total"] else f"{b['page']} ページ"
            L.append(f"- {b['name']} — {bar}・{b['date']}" + ("・読了" if b["finished"] else f"・再開は {b['resume_page']} ページから"))
        if not r["books"]:
            L.append("記録がありません（`:GnosisReadProgress 書名 ページ 全ページ`）")
    elif kind == "maturity":
        L = ["# 成熟度", "", "・".join(f"{LEVEL_JA[k]} {v}" for k, v in r["counts"].items()), ""] + [f"- {_l(x['path'], x['title'])} — {x['level']}（{x['chars']} 文字・参照 {x['inbound']}）" for x in r["notes"]]
        L += ["", "## 引き上げの提案", ""] + ([f"- {_l(x['path'], x['title'])}: {x['from']} → {x['to']}（{x['why']}）" for x in r["suggestions"]] or ["なし"]) + ["", r["note_text"]]
    elif kind == "path":
        L = [f"# 学習経路: {r['goal']}", ""]
        if r["cycle"]:
            L.append("前提が循環しています: " + " → ".join(r["cycle"]))
        L += [f"{i}. {_l(x['path'], x['title'])}" for i, x in enumerate(r["order"], 1)]
        L += [f"- 前提「{m['requires']}」が見つかりません（{m['in']}）" for m in r["missing"]]
    elif kind == "sources":
        L = ["# 出典", ""]
        for s in r["sources"]:
            L += [f"## {_l(s['path'], s['title'])}", "", f"- {s['kind']}・{s['author']}・{s['year']}" + (f"・{s['url']}" if s["url"] else ""), f"- 引用しているノート {len(s['cited_by'])} 件"]
            L += [f"  - {_l(c['path'])}:{c['line']} {c['text']}" for c in s["cited_by"]] + [""]
        if not r["sources"]:
            L.append("出典のノート（front matter に `source:`）がありません。")
    elif kind == "explain":
        L = [f"# 自己説明: {r['title']}", ""] + [f"- {p}" for p in r["prompts"]]
        if "coverage" in r:
            L += ["", f"## 見直しの手がかり（要点語がそのまま入っていた割合 {int((r['coverage'] or 0) * 100)}%・一部合うものを含めて {int((r['coverage_loose'] or 0) * 100)}%）", "", "入っていた: " + ("・".join(r["covered"]) or "なし"),
                  "", "一部合う（言い換えかもしれません）: " + ("・".join(r["partial"]) or "なし"), "", "入っていなかった: " + ("・".join(r["missing"]) or "なし")]
            if r["unaddressed"]:
                L += ["", "答えに触れていないように見えるノートの文:"] + [f"- {x}" for x in r["unaddressed"]]
            if r.get("recorded"):
                pv = r.get("previous")
                L += ["", "記録しました。" + (f"前回（{pv['date']}）は {int((pv['coverage'] or 0) * 100)}%" + (f"、{'+' if r['delta'] >= 0 else ''}{int(r['delta'] * 100)} ポイント。" if r.get("delta") is not None else "。") if pv else "初めての記録です。")]
            L += ["", r["note_text"]]
    elif kind == "ir-next":
        it = r["item"]
        L = ["# インクリメンタルリーディング", ""]
        if it:
            L += [f"{it['text']}", "", f"— {_l(it['file'], it['title'])}:{it['line']}" + (f"（p.{it['page']}）" if it["page"] else ""), f"- {it['state']}・ID `{it['id']}`・期日待ち {r['remaining_due']} 件・未見 {r['unseen']} 件"]
        else:
            L.append("今日見るものはありません。" + (f"次の期日は {r['next_due']} です。" if r.get("next_due") else ""))
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        write = None
        a = []
        it = iter([x for x in argv if x not in ("--md", "--record")])
        for x in it:
            if x == "--write":
                write = next(it)
            else:
                a.append(x)
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "highlights":
            r = highlights(root, rest[0] if rest else None)
        elif cmd == "digest":
            r = digest(root, rest[0], write)
        elif cmd == "progress":
            r = progress(root)
        elif cmd == "progress-set":
            r = progress_set(root, rest[0], int(rest[1]), int(rest[2]) if len(rest) > 2 and rest[2].isdigit() else None, rest[-1] if re.fullmatch(r"\d{4}-\d{2}-\d{2}", rest[-1]) else None)
        elif cmd == "maturity":
            r = maturity(root, rest[0] if rest else None)
        elif cmd == "maturity-set":
            r = maturity_set(root, rest[0], rest[1])
        elif cmd == "path":
            r = learning_path(root, rest[0])
        elif cmd == "sources":
            r = sources(root)
        elif cmd == "explain":
            r = explain(root, rest[0], rest[1] if len(rest) > 1 else None, record="--record" in argv)
        elif cmd == "ir-next":
            r = ir_next(root, rest[0] if rest else None)
        elif cmd == "ir-rate":
            r = ir_rate(root, rest[0], rest[1], rest[2] if len(rest) > 2 else None)
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md and cmd in ("highlights", "digest", "progress", "maturity", "path", "sources", "explain", "ir-next") else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
