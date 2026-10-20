#!/usr/bin/env python3
"""ローカル完結の知識支援（AI01〜AI10・AI13〜AI15・SR04/SR05 の核）。クラウドも外部通信も使わない。依存も増やさない（純 Python）。

方針（原本 §5 F-AI）:
  - **ノートも索引も書き換えない**。出すのは「提案」と「根拠つきの候補」だけ。書くのは、利用者が明示した新規ノートへの出力だけ。
  - **断定しない**。矛盾は「疑い」と根拠の行・確信度（低/中）で示す。根拠が見つからないときは「見つからない」と言う（作り話をしない）。
  - 意味の近さは、**文字 n-gram の TF-IDF（と擬似適合フィードバック）**というローカルの近似。ニューラルの埋め込みではない。
    それでも同じ語を使わない言い換えまでは拾えない。精度は目安。

CLI（JSON。--md を付けると読みやすい Markdown）:  duplicates もある（ほぼ同じ内容の組）
  local_ai.py ROOT similar NOTE [K]          AI01 似たノート・重複の疑い
  local_ai.py ROOT links NOTE [K]            AI02 つなぎ候補（まだリンクしていない近いノート・文中に名前が出ているが未リンク）
  local_ai.py ROOT index NOTE [K]            AI03 そのノートを入れると良さそうな索引（グループ）の候補。索引は書き換えない
  local_ai.py ROOT summary NOTE [N]          AI04 要約（抜き出し）
  local_ai.py ROOT common NOTE NOTE …        AI05 複数ノートの共通点
  local_ai.py ROOT conflicts [NOTE]          AI06 記述の食い違いの疑い（根拠の行・確信度つき）
  local_ai.py ROOT stale [日数]               AI07 古くなっていそうな記述の再確認候補
  local_ai.py ROOT keywords NOTE [N]         AI08 キーワード・索引語の候補
  local_ai.py ROOT questions NOTE [N]        AI09 問題の候補（Q:/A: と {{穴埋め}}。SRS にそのまま使える）
  local_ai.py ROOT ask '質問' [K]             AI10 自分のノートを根拠にした答え（抜き出し・出典つき）
  local_ai.py ROOT semantic '語' [K]          SR04 意味検索（ローカル近似）
  local_ai.py ROOT hybrid '語' [K]            SR05 全文＋意味のハイブリッド
  local_ai.py ROOT nl '自然な文'              AI13 自然な文から検索条件を作る
  local_ai.py ROOT report [週|月] [日付]       AI14 活動と知識の変化のレポート
  local_ai.py ROOT patrol                     AI15 保存した検索を巡回し、前回からの新しい一致を出す
"""
from __future__ import annotations

import datetime as dt
import json
import math
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_format_v2 as nf  # noqa: E402

CJK = re.compile(r"[ぁ-んァ-ヶ一-龠ー]+")
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9_\-\.]*")
LINK_MD = re.compile(r"!?\[((?:\\.|[^\]\\])*)\]\([^)]*\)")
SENT = re.compile(r"(?<=[。！？!?])|\n+|(?<=[a-z0-9]\.)\s+")
DUP = 0.7   # ほぼ同じ内容とみなす類似度（2 文字 n-gram の TF-IDF は短い文だと低めに出るので 0.7）
STOP_JA = set("これそれあれこのそのあのためこと(もの)ようからまでよりなどです")  # 記号の寄せ集め。実質は IDF で落とす


def _strip(body: str) -> str:
    """リンクの書き方・見出し記号などを外した、読む文章。"""
    out = []
    fence = False
    for ln in body.split("\n"):
        t = ln.strip()
        if t.startswith(("```", "~~~")):
            fence = not fence
            continue
        if fence or t in ("ParentBranch:", "BranchGroup:", "Group:", "Context:", "Related:", "BackLink:", "ChildBranch:"):
            continue
        t = LINK_MD.sub(r"\1", t)
        t = re.sub(r"^#{1,6}\s+", "", t)
        t = re.sub(r"^[-*+]\s+(\[[ xX]\]\s*)?", "", t)
        t = re.sub(r"[*_`~>|]+", " ", t)
        out.append(t)
    return "\n".join(out)


def tokens(text: str) -> list[str]:
    """日本語は文字 2-gram（と 1 文字の漢字語）、英数字は語。小文字化。"""
    text = text.lower()
    out: list[str] = []
    for m in CJK.finditer(text):
        run = m.group(0)
        if len(run) == 1:
            if "一" <= run <= "龠":
                out.append(run)
            continue
        out += [run[i:i + 2] for i in range(len(run) - 1)]
    out += [w for w in WORD.findall(text) if len(w) > 1]
    return out


class Corpus:
    def __init__(self) -> None:
        self.docs: dict[str, dict] = {}          # path -> {title, text, tf, norm, links, mtime, time, lines}
        self.df: Counter = Counter()
        self.inv: dict[str, list[tuple[str, float]]] = {}
        self.n = 0
        self.titles: dict[str, str] = {}

    @staticmethod
    def build(root: str | Path) -> "Corpus":
        root = Path(root).resolve()
        c = Corpus()
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            for name in sorted(filenames):
                if not name.endswith(".md") or name.startswith("."):
                    continue
                p = Path(dirpath) / name
                try:
                    text = p.read_text(encoding="utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
                d = nf._simple_parse_text(p, text)
                rel = p.relative_to(root).as_posix()
                body = "\n".join(d["body"])
                links = {os.path.basename(m.group(1).split("#")[0]) for m in nf.ANY_LINK_RE.finditer(text) if m.group(1).lower().split("#")[0].endswith(".md")}
                tm = next((ln.split(":", 1)[1].strip() for ln in d["fm"] if ln.startswith("time:")), "")
                kind = "group" if nf._GROUP_ATTR_RE.search("\n".join(d["fm"])) else "note"
                c.docs[rel] = {"raw": text.split("\n"), "title": d["title"], "body": body, "clean": _strip(body), "links": links, "mtime": p.stat().st_mtime, "time": tm, "kind": kind,
                               "head_lines": len(text.split("\n")) - len(body.split("\n"))}
        c._index()
        return c

    def _index(self) -> None:
        self.n = len(self.docs)
        for rel, d in self.docs.items():
            toks = tokens(d["title"] + " " + d["title"] + " " + d["clean"])        # 題は 2 回数える（題の語を重く）
            d["tf"] = Counter(toks)
            self.df.update(d["tf"].keys())
            self.titles[rel] = d["title"]
        for rel, d in self.docs.items():
            vec = {t: (1 + math.log(f)) * self.idf(t) for t, f in d["tf"].items()}
            norm = math.sqrt(sum(v * v for v in vec.values())) or 1.0
            d["vec"] = {t: v / norm for t, v in vec.items()}
            for t, v in d["vec"].items():
                self.inv.setdefault(t, []).append((rel, v))

    def idf(self, t: str) -> float:
        return math.log((1 + self.n) / (1 + self.df.get(t, 0))) + 1.0

    def vec(self, text: str) -> dict[str, float]:
        tf = Counter(tokens(text))
        v = {t: (1 + math.log(f)) * self.idf(t) for t, f in tf.items() if t in self.df}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1.0
        return {t: x / norm for t, x in v.items()}

    def score(self, qv: dict[str, float], exclude: set[str] | None = None) -> list[tuple[str, float]]:
        acc: dict[str, float] = defaultdict(float)
        for t, w in qv.items():
            for rel, dv in self.inv.get(t, ()):
                acc[rel] += w * dv
        return sorted(((r, s) for r, s in acc.items() if not exclude or r not in exclude), key=lambda x: (-x[1], x[0]))

    def find(self, name: str) -> str:
        if name in self.docs:
            return name
        for rel, d in self.docs.items():
            if rel.endswith("/" + name) or d["title"] == name or Path(rel).stem == name:
                return rel
        raise ValueError("ノートが見つかりません: " + name)

    def shared_terms(self, a: str, b: str, n: int = 6) -> list[str]:
        va, vb = self.docs[a]["vec"], self.docs[b]["vec"]
        common = sorted(((va[t] * vb[t], t) for t in va.keys() & vb.keys()), reverse=True)
        return [t for _, t in common[:n]]

    def file_line(self, rel: str, snippet: str) -> int:
        """snippet（リンクの書き方を外した文の頭）が最初に現れる、元ファイルの行（1 から）。見つからなければ 0。
        関係のブロックを除いた本文の行番号は、元のファイルの行とずれるので、根拠の行は元のファイルから探す。"""
        key = LINK_MD.sub(r"\1", snippet).strip()[:12]
        if not key:
            return 0
        for i, ln in enumerate(self.docs[rel]["raw"], 1):
            if key in LINK_MD.sub(r"\1", ln):
                return i
        return 0

    def linked(self, a: str, b: str) -> bool:
        return Path(b).name in self.docs[a]["links"] or Path(a).name in self.docs[b]["links"]


# ---- AI01 似たノート・重複 ----
def similar(c: Corpus, note: str, k: int = 5) -> dict:
    rel = c.find(note)
    ranked = c.score(c.docs[rel]["vec"], {rel})[:k]
    out = []
    for r, s in ranked:
        out.append({"path": r, "title": c.docs[r]["title"], "score": round(s, 3), "shared": c.shared_terms(rel, r), "linked": c.linked(rel, r),
                    "duplicate_suspect": s >= DUP})
    return {"note": rel, "similar": out}


def duplicates(c: Corpus, threshold: float = 0.7) -> list[dict]:
    """全体から、ほぼ同じ内容のノートの組（疑い）。"""
    seen: set[tuple[str, str]] = set()
    out = []
    for rel, d in c.docs.items():
        for r, s in c.score(d["vec"], {rel})[:3]:
            key = tuple(sorted((rel, r)))
            if s >= threshold and key not in seen:
                seen.add(key)
                out.append({"a": key[0], "b": key[1], "score": round(s, 3)})
    return sorted(out, key=lambda x: -x["score"])


# ---- AI02 つなぎ候補 ----
def link_suggestions(c: Corpus, note: str, k: int = 8) -> dict:
    rel = c.find(note)
    d = c.docs[rel]
    out: dict[str, dict] = {}
    for r, s in c.score(d["vec"], {rel})[:40]:
        if c.linked(rel, r):
            continue
        out[r] = {"path": r, "title": c.docs[r]["title"], "score": round(s, 3), "reason": "内容が近い", "shared": c.shared_terms(rel, r, 4)}
    # 文字列の言及: 他のノートの題が本文に文字として出ている（リンクはされていない）。意味の近さとは別に出す
    mentions = []
    plain = d["clean"]
    for r, o in c.docs.items():
        t = o["title"].strip()
        if r == rel or len(t) < 3 or c.linked(rel, r):
            continue
        at = plain.find(t)
        if at >= 0:
            line = plain[:at].count("\n") + 1
            mentions.append({"path": r, "title": t, "line_in_text": line, "reason": "本文にこの題が出ているが、リンクされていない（文字の一致）"})
    return {"note": rel, "similar_unlinked": sorted(out.values(), key=lambda x: -x["score"])[:k], "unlinked_mentions": mentions[:k]}


# ---- AI03 索引の候補 ----
def index_candidates(c: Corpus, note: str, k: int = 3) -> dict:
    """グループ（索引）ごとに、そこに載っているノートの重心との近さを見る。索引は書き換えない（提案だけ）。"""
    rel = c.find(note)
    me = c.docs[rel]["vec"]
    out = []
    for g, gd in c.docs.items():
        if gd["kind"] != "group" or g == rel:
            continue
        members = [m for m, md in c.docs.items() if md["title"] != "" and Path(m).name in gd["links"] and m != rel]
        if not members or Path(rel).name in gd["links"]:
            continue                                            # 空の索引・すでに載っているもの
        cen: dict[str, float] = defaultdict(float)
        for m in members:
            for t, v in c.docs[m]["vec"].items():
                cen[t] += v / len(members)
        norm = math.sqrt(sum(v * v for v in cen.values())) or 1.0
        sim = sum(me.get(t, 0.0) * v / norm for t, v in cen.items())
        out.append({"index": g, "title": gd["title"], "score": round(sim, 3), "members": len(members)})
    return {"note": rel, "candidates": sorted(out, key=lambda x: -x["score"])[:k], "note_text": "提案だけです。索引は書き換えていません。"}


# ---- AI08 キーワード ----
def phrases(c: Corpus, rel: str, n: int = 10) -> list[str]:
    """重みの高い 2 文字の連なり（bigram）を、本文の中でつながっている範囲まで伸ばして語句にする（例: ブラ・ラッ・ック・クホ… → ブラックホール）。"""
    d = c.docs[rel]
    ranked = sorted(d["vec"].items(), key=lambda kv: (-kv[1], kv[0]))
    top = {t for t, _ in ranked[:max(30, n * 4)]}
    weight = dict(ranked)
    found: dict[str, float] = {}
    for m in CJK.finditer((d["title"] + "\n" + d["clean"]).lower()):
        run = m.group(0)
        i = 0
        while i < len(run) - 1:
            if run[i:i + 2] in top:
                j = i + 1
                while j < len(run) - 1 and run[j:j + 2] in top:
                    j += 1
                ph = run[i:j + 1]
                if len(ph) >= 2:
                    found[ph] = found.get(ph, 0.0) + sum(weight.get(run[k:k + 2], 0.0) for k in range(i, j))
                i = j + 1
            else:
                i += 1
    for t, w in ranked[:max(30, n * 4)]:                      # 英数字の語はそのまま
        if WORD.fullmatch(t):
            found[t] = found.get(t, 0.0) + w
    out: list[str] = []
    for ph, _ in sorted(found.items(), key=lambda kv: (-kv[1], kv[0])):
        if any(ph in o or o in ph for o in out):
            continue
        out.append(ph)
        if len(out) >= n:
            break
    return out


def keywords(c: Corpus, note: str, n: int = 10) -> dict:
    rel = c.find(note)
    return {"note": rel, "keywords": phrases(c, rel, n), "note_text": "索引語の候補です。ノートにも索引にも書き込みません。"}


# ---- AI04 要約（抜き出し） ----
def sentences(text: str) -> list[str]:
    out = []
    for part in re.split(r"(?<=[。！？!?])|\n+", text):
        s = part.strip()
        if len(s) >= 6:
            out.append(s)
    return out


def summarize(c: Corpus, note: str, n: int = 3) -> dict:
    rel = c.find(note)
    d = c.docs[rel]
    sents = sentences(d["clean"])
    if not sents:
        return {"note": rel, "summary": [], "note_text": "要約できる文がありません"}
    scored = []
    for i, s in enumerate(sents):
        toks = tokens(s)
        if not toks:
            continue
        w = sum(d["vec"].get(t, 0.0) for t in toks) / math.sqrt(len(toks))
        scored.append((w * (1.15 if i == 0 else 1.0), i, s))
    top = sorted(scored, reverse=True)[:n]
    keep = sorted(top, key=lambda x: x[1])
    return {"note": rel, "summary": [s for _, _, s in keep], "method": "抜き出し（文の重要語の重みで選ぶ。言い換えはしない）", "sentences": len(sents)}


# ---- AI05 共通点 ----
def common(c: Corpus, notes: list[str]) -> dict:
    rels = [c.find(n) for n in notes]
    if len(rels) < 2:
        raise ValueError("2 つ以上のノートを指定してください")
    sets = [set(c.docs[r]["vec"]) for r in rels]
    shared = set.intersection(*sets)
    ranked = sorted(shared, key=lambda t: -sum(c.docs[r]["vec"][t] for r in rels))[:12]
    most = Counter(t for s in sets for t in s)
    majority = sorted((t for t, k in most.items() if k >= max(2, math.ceil(len(rels) * 0.6)) and t not in shared), key=lambda t: -most[t] * c.idf(t))[:8]
    return {"notes": rels, "shared_in_all": ranked, "shared_in_most": majority,
            "summaries": {r: summarize(c, r, 1)["summary"] for r in rels}}


# ---- AI06 食い違いの疑い ----
NEG = re.compile(r"(ない|ません|ではない|じゃない|不可|禁止|not|never|no longer|cannot|can't|isn't|aren't)", re.I)
NUM = re.compile(r"\d+(?:\.\d+)?")


def conflicts(c: Corpus, note: str | None = None, threshold: float = 0.35, limit: int = 20) -> list[dict]:
    """似た文どうしで、数字が違う・否定の有無が違うものを「疑い」として挙げる。断定はしない（確信度は 低／中）。"""
    rels = [c.find(note)] if note else list(c.docs)
    out = []
    sent_cache: dict[str, list[tuple[int, str, set]]] = {}
    def sents(rel):
        if rel not in sent_cache:
            lines = c.docs[rel]["clean"].split("\n")
            arr = []
            for i, ln in enumerate(lines, 1):
                for s in sentences(ln):
                    arr.append((i, s, set(tokens(s))))
            sent_cache[rel] = arr
        return sent_cache[rel]
    for rel in rels:
        for other, score in c.score(c.docs[rel]["vec"], {rel})[:8]:
            if score < threshold or (note is None and other < rel):
                continue
            for i, s, ts in sents(rel):
                for j, s2, ts2 in sents(other):
                    if len(ts) < 3 or len(ts2) < 3:
                        continue
                    ov = len(ts & ts2) / min(len(ts), len(ts2))
                    if ov < 0.55:
                        continue
                    n1, n2 = NUM.findall(s), NUM.findall(s2)
                    reason = ""
                    if n1 and n2 and set(n1) != set(n2):
                        reason = f"同じ話題の文で数字が違います（{'・'.join(n1[:3])} と {'・'.join(n2[:3])}）"
                    elif bool(NEG.search(s)) != bool(NEG.search(s2)):
                        reason = "同じ話題の文で、肯定と否定が食い違っているように見えます"
                    if reason:
                        out.append({"a": {"path": rel, "line": c.file_line(rel, s), "text": s[:120]}, "b": {"path": other, "line": c.file_line(other, s2), "text": s2[:120]},
                                    "reason": reason, "confidence": "中" if ov >= 0.75 else "低", "note_text": "疑いです。文脈で食い違いでないこともあります。"})
                        if len(out) >= limit:
                            return out
    return out


# ---- AI07 古い記述の再確認 ----
YEAR = re.compile(r"(?<!\d)(19\d\d|20\d\d)\s*年")
SOFT = re.compile(r"(現在|最新|今のところ|時点|バージョン\s*\d|v\d+\.\d+|as of|latest|currently)", re.I)


def stale(c: Corpus, days: int = 365, today: dt.date | None = None) -> list[dict]:
    today = today or dt.date.today()
    out = []
    for rel, d in c.docs.items():
        age = (today - dt.date.fromtimestamp(d["mtime"])).days
        reasons = []
        m = re.search(r"^reverify:\s*(\d{4}-\d{2}-\d{2})", d["body"] + "\n" + "", re.M)
        if m and m.group(1) <= today.isoformat():
            reasons.append(f"再確認の期限（reverify: {m.group(1)}）を過ぎています")
        if age >= days:
            hits = SOFT.findall(d["clean"])
            years = [int(y) for y in YEAR.findall(d["clean"]) if int(y) <= today.year - 2]
            if hits:
                reasons.append(f"{age} 日更新されていないノートに、時点によって変わる語（{hits[0]}）があります")
            if years:
                reasons.append(f"{max(years)} 年など、古い年への言及があります")
        if reasons:
            out.append({"path": rel, "title": d["title"], "age_days": age, "reasons": reasons})
    return sorted(out, key=lambda x: -x["age_days"])


# ---- AI09 問題の候補 ----
DEF = re.compile(r"^(.{2,20}?)(?:とは|は)(.{4,80}?)(?:です|である|だ|。)")


def questions(c: Corpus, note: str, n: int = 6) -> dict:
    rel = c.find(note)
    d = c.docs[rel]
    out = []
    for s in sentences(d["clean"]):
        m = re.match(r"^(.{2,20}?)とは(.{4,100}?)(?:です|である|だ|。|$)", s) or DEF.match(s)
        if m and len(out) < n and "{{" not in s:
            term = m.group(1).strip("、, ")
            out.append({"kind": "qa", "text": f"Q: {term}とは何ですか？\nA: {m.group(2).strip('、, ')}"})
    # 穴埋め: 重要語を含む文から、その語を伏せる
    ranked = sorted(d["vec"].items(), key=lambda kv: -kv[1])
    used = set()
    for t, _ in ranked:
        if len(out) >= n:
            break
        if len(t) < 2 or t in used:
            continue
        for s in sentences(d["clean"]):
            at = s.lower().find(t)
            if at >= 0 and 12 <= len(s) <= 90 and "{{" not in s:
                out.append({"kind": "cloze", "text": s[:at] + "{{" + s[at:at + len(t)] + "}}" + s[at + len(t):]})
                used.add(t)
                break
    heads = [ln.lstrip("# ").strip() for ln in d["body"].split("\n") if ln.startswith("## ")]
    for h in heads[:2]:
        if len(out) < n:
            out.append({"kind": "prompt", "text": f"Q: 「{h}」について、自分の言葉で説明してください。\nA: （答えを書く）"})
    return {"note": rel, "questions": out[:n], "note_text": "候補です。ノートには書き込みません。使うときは Q:/A:・{{穴埋め}} の形で本文に貼ってください（:GnosisSrs で復習できます）。"}


# ---- AI10 根拠つきの答え（RAG の取り出し側。生成はしない） ----
def passages(c: Corpus) -> list[tuple[str, int, str]]:
    """本文を空行で区切った段落（見出しだけの段落は除く）。行番号は元のファイルの行。"""
    out = []
    for rel, d in c.docs.items():
        buf: list[str] = []
        for ln in d["body"].split("\n") + [""]:
            if ln.strip():
                buf.append(ln.strip())
            elif buf:
                lines = [x for x in buf if not x.startswith("#")]
                text = " ".join(LINK_MD.sub(r"\1", x) for x in lines)
                if len(text) >= 12 and not lines[0].startswith(("ParentBranch:", "BranchGroup:", "Group:", "BackLink:", "Context:", "Related:", "ChildBranch:")):
                    out.append((rel, c.file_line(rel, lines[0]), text))
                buf = []
    return out


def ask(c: Corpus, question: str, k: int = 4, min_score: float = 0.12) -> dict:
    qv = c.vec(question)
    if not qv:
        return {"question": question, "answers": [], "note_text": "質問から手がかりになる語を取り出せませんでした。"}
    qterms = set(tokens(question))
    scored = []
    for rel, line, text in passages(c):
        pv = c.vec(text)
        s = sum(qv.get(t, 0.0) * w for t, w in pv.items())
        cover = len(qterms & set(tokens(text))) / len(qterms) if qterms else 0
        scored.append((s * (0.6 + 0.4 * cover), cover, rel, line, text))
    scored.sort(reverse=True)
    top = [x for x in scored if x[0] >= min_score][:k]
    if not top:
        return {"question": question, "answers": [], "note_text": "根拠になるノートが見つかりませんでした（作り話はしません）。"}
    return {"question": question, "answers": [{"path": rel, "line": line, "text": text[:240], "score": round(sc, 3), "term_coverage": round(cov, 2)}
                                              for sc, cov, rel, line, text in top],
            "note_text": "生成ではなく、ノートからの抜き出しです。出典のノートで確かめてください。"}


# ---- SR04 / SR05 意味検索 ----
def semantic(c: Corpus, query: str, k: int = 10, feedback: int = 3) -> list[dict]:
    """文字 n-gram の TF-IDF の近さ + 擬似適合フィードバック（上位の文書の特徴語を足して取り直す）。ローカルの近似。"""
    qv = c.vec(query)
    if not qv:
        return []
    first = c.score(qv)[:max(feedback, 1)]
    exp: dict[str, float] = defaultdict(float, qv)
    for rel, s in first:
        for t, v in sorted(c.docs[rel]["vec"].items(), key=lambda kv: -kv[1])[:12]:
            exp[t] += 0.3 * v * s
    norm = math.sqrt(sum(v * v for v in exp.values())) or 1.0
    ranked = c.score({t: v / norm for t, v in exp.items()})[:k]
    return [{"path": r, "title": c.docs[r]["title"], "score": round(s, 3)} for r, s in ranked]


def hybrid(root: str | Path, query: str, k: int = 10, c: Corpus | None = None) -> list[dict]:
    """全文検索（vault_index）と意味検索を、順位の逆数で混ぜる（RRF）。"""
    import vault_index as vi
    c = c or Corpus.build(root)
    fts = vi.search(root, query, limit=50)
    sem = semantic(c, query, 50)
    score: dict[str, float] = defaultdict(float)
    src: dict[str, set] = defaultdict(set)
    for i, r in enumerate(fts):
        score[r["path"]] += 1 / (60 + i); src[r["path"]].add("全文")
    for i, r in enumerate(sem):
        score[r["path"]] += 1 / (60 + i); src[r["path"]].add("意味")
    return [{"path": p, "title": c.docs[p]["title"] if p in c.docs else p, "score": round(s, 4), "from": sorted(src[p])}
            for p, s in sorted(score.items(), key=lambda x: (-x[1], x[0]))[:k]]


# ---- AI13 自然な文 → 検索条件 ----
def nl_to_query(text: str, today: dt.date | None = None) -> dict:
    """ルールで読む（機械学習ではない）。読めた条件だけを vault_index のクエリにして、どう読んだかも返す。"""
    today = today or dt.date.today()
    t = text.strip()
    parts, notes = [], []
    rest = t
    def month_range(y, m):
        a = dt.date(y, m, 1)
        b = (dt.date(y + (m == 12), m % 12 + 1, 1) - dt.timedelta(days=1))
        return a, b
    rules = [
        (r"今月", lambda: month_range(today.year, today.month)),
        (r"先月", lambda: month_range(today.year - (today.month == 1), 12 if today.month == 1 else today.month - 1)),
        (r"今年", lambda: (dt.date(today.year, 1, 1), dt.date(today.year, 12, 31))),
        (r"昨年|去年", lambda: (dt.date(today.year - 1, 1, 1), dt.date(today.year - 1, 12, 31))),
        (r"今週", lambda: (today - dt.timedelta(days=today.weekday()), today + dt.timedelta(days=6 - today.weekday()))),
        (r"昨日", lambda: (today - dt.timedelta(days=1), today - dt.timedelta(days=1))),
        (r"今日", lambda: (today, today)),
    ]
    for pat, fn in rules:
        if re.search(pat, rest):
            a, b = fn()
            parts += [f"after:{(a - dt.timedelta(days=1)).isoformat()}", f"before:{(b + dt.timedelta(days=1)).isoformat()}"]
            notes.append(f"「{re.search(pat, rest).group(0)}」→ {a.isoformat()}〜{b.isoformat()}")
            rest = re.sub(pat, " ", rest, count=1)
            break
    m = re.search(r"(\d{4})年(\d{1,2})月", rest)
    if m and not parts:
        a, b = month_range(int(m.group(1)), int(m.group(2)))
        parts += [f"after:{(a - dt.timedelta(days=1)).isoformat()}", f"before:{(b + dt.timedelta(days=1)).isoformat()}"]
        notes.append(f"「{m.group(0)}」→ {a.isoformat()}〜{b.isoformat()}"); rest = rest.replace(m.group(0), " ")
    flags = [(r"未完了|終わってない|やること|タスク|todo", "has:task", "タスクを含む"), (r"画像|写真|図", "has:image", "画像を含む"), (r"日記", "type:diary", "日記"),
             (r"グループ|索引", "type:group", "グループ（索引）"), (r"リンクの?ない|孤立", "links=0", "リンクを持たない")]
    for pat, q, why in flags:
        if re.search(pat, rest):
            parts.append(q); notes.append(f"「{re.search(pat, rest).group(0)}」→ {why}"); rest = re.sub(pat, " ", rest, count=1)
    fz = re.search(r"番号\s*([0-9]+[a-z0-9]*)|folgezettel\s*([0-9]+[a-z0-9]*)", rest, re.I)
    if fz:
        v = fz.group(1) or fz.group(2); parts.append(f"fz:{v}*"); notes.append(f"番号 {v} とその枝"); rest = rest.replace(fz.group(0), " ")
    for q in re.findall(r"[「『\"“]([^」』\"”]+)[」』\"”]", rest):
        parts.append(f'"{q}"' if " " in q else q); notes.append(f"語「{q}」を含む"); rest = rest.replace(q, " ")
    rest = re.sub(r"[「」『』\"“”を含む|について|の|に関する|ノート|メモ|探して|見せて|一覧|全部|で|が|は|も]+", " ", rest)
    words = [w for w in re.split(r"[\s、,。]+", rest) if len(w) >= 2]
    for w in words:
        parts.append(w); notes.append(f"語「{w}」を含む")
    return {"query": " ".join(parts), "read_as": notes, "note_text": "ルールで読んだだけです。意図と違うときは、条件を直接書いてください（:GnosisGuide の検索の書き方）。"}


# ---- AI14 活動レポート ----
def activity(c: Corpus, period: str = "週", on: dt.date | None = None) -> dict:
    on = on or dt.date.today()
    if period in ("月", "month"):
        a = dt.date(on.year, on.month, 1)
        b = dt.date(on.year + (on.month == 12), on.month % 12 + 1, 1) - dt.timedelta(days=1)
    else:
        a = on - dt.timedelta(days=on.weekday()); b = a + dt.timedelta(days=6)
    prev_len = (b - a).days + 1
    pa, pb = a - dt.timedelta(days=prev_len), a - dt.timedelta(days=1)
    def within(d, lo, hi):
        t = (d["time"] or "")[:10]
        return lo.isoformat() <= t <= hi.isoformat() if t else False
    new = [r for r, d in c.docs.items() if within(d, a, b)]
    prev = [r for r, d in c.docs.items() if within(d, pa, pb)]
    modified = [r for r, d in c.docs.items() if a <= dt.date.fromtimestamp(d["mtime"]) <= b and r not in new]
    words = Counter()
    for r in new:
        words.update(phrases(c, r, 3))
    return {"period": [a.isoformat(), b.isoformat()], "new_notes": len(new), "previous_period_new": len(prev), "modified_notes": len(modified),
            "new": [{"path": r, "title": c.docs[r]["title"]} for r in sorted(new)[:20]],
            "themes": [t for t, _ in words.most_common(8)], "total_notes": len(c.docs),
            "note_text": "ノートの作成日時（time:）と更新日時から数えた事実です。"}


def activity_md(rep: dict) -> str:
    L = [f"# 活動レポート {rep['period'][0]}〜{rep['period'][1]}", "",
         f"- 新しいノート: {rep['new_notes']} 件（前の期間は {rep['previous_period_new']} 件）", f"- 更新したノート: {rep['modified_notes']} 件", f"- 全体: {rep['total_notes']} 件", ""]
    if rep["themes"]:
        L += ["## 新しいノートに多かった語", "", "・".join(rep["themes"]), ""]
    if rep["new"]:
        L += ["## 新しいノート", ""] + [f"- [{x['title']}]({x['path'].replace(' ', '%20')})" for x in rep["new"]] + [""]
    L.append(rep["note_text"])
    return "\n".join(L) + "\n"


# ---- AI15 保存検索の巡回 ----
def patrol(root: str | Path) -> dict:
    """保存した検索（vault_index の saved）を順に実行し、前回の結果との差（新しい一致）を返す。ノートは動かさない。状態は .gnosis/patrol.json。"""
    import vault_index as vi
    root = Path(root).resolve()
    sp = root / ".gnosis" / "patrol.json"
    old = json.loads(sp.read_text(encoding="utf-8")) if sp.exists() else {}
    new_state, report = {}, []
    for s in vi.saved(root, "list"):
        res = vi.search(root, s["query"], limit=200)
        paths = sorted(r["path"] for r in res)
        prev = set(old.get(s["name"], []))
        report.append({"name": s["name"], "query": s["query"], "count": len(paths), "new": [p for p in paths if p not in prev] if s["name"] in old else paths, "first_run": s["name"] not in old})
        new_state[s["name"]] = paths
    sp.parent.mkdir(parents=True, exist_ok=True)
    tmp = sp.with_name(sp.name + ".tmp")
    tmp.write_text(json.dumps(new_state, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, sp)
    return {"searches": report}


def _lnk(path: str, title: str = "") -> str:
    return f"[{title or path}]({path.replace(' ', '%20')})"


def render_md(cmd: str, res) -> str:
    """結果を、読みやすい Markdown に（ノートへのリンクつき。Vim の結果画面で Enter で開ける）。"""
    L: list[str] = []
    if cmd == "similar":
        L = [f"# 似たノート: {res['note']}", ""] + [f"- {_lnk(x['path'], x['title'])} — 近さ {x['score']}" + ("・**重複の疑い**" if x["duplicate_suspect"] else "") + ("・リンク済み" if x["linked"] else "") + (f"（共通: {'・'.join(x['shared'][:4])}）" if x["shared"] else "") for x in res["similar"]]
    elif cmd == "duplicates":
        L = ["# ほぼ同じ内容のノート（疑い）", ""] + [f"- {_lnk(x['a'])} と {_lnk(x['b'])} — 近さ {x['score']}" for x in res] or ["- なし"]
    elif cmd == "links":
        L = [f"# つなぎ候補: {res['note']}", "", "## 内容が近い（まだリンクしていない）", ""] + ([f"- {_lnk(x['path'], x['title'])} — {x['score']}（共通: {'・'.join(x['shared'])}）" for x in res["similar_unlinked"]] or ["- なし"]) \
            + ["", "## 本文にこの題が出ているが、リンクされていない（文字の一致）", ""] + ([f"- {_lnk(x['path'], x['title'])} — 本文の {x['line_in_text']} 行目あたり" for x in res["unlinked_mentions"]] or ["- なし"])
    elif cmd == "index":
        L = [f"# 載せる索引の候補: {res['note']}", ""] + ([f"- {_lnk(x['index'], x['title'])} — 近さ {x['score']}（{x['members']} 件が載っている）" for x in res["candidates"]] or ["- 候補なし"]) + ["", res["note_text"]]
    elif cmd == "summary":
        L = [f"# 要約: {res['note']}", ""] + [f"- {x}" for x in res["summary"]] + ["", res.get("method", "")]
    elif cmd == "common":
        L = ["# 共通点", "", "## すべてに出る語", "", "・".join(res["shared_in_all"]) or "なし", "", "## 多くに出る語", "", "・".join(res["shared_in_most"]) or "なし", "", "## それぞれの要点", ""] + [f"- {_lnk(p)}: {' '.join(v)}" for p, v in res["summaries"].items()]
    elif cmd == "conflicts":
        L = ["# 記述の食い違いの疑い", "", "疑いです。文脈で食い違いでないこともあります。", ""]
        for x in res:
            L += [f"- {x['reason']}（確信度 {x['confidence']}）", f"  - {_lnk(x['a']['path'])}:{x['a']['line']} 「{x['a']['text']}」", f"  - {_lnk(x['b']['path'])}:{x['b']['line']} 「{x['b']['text']}」"]
        if not res:
            L.append("- 見つかりませんでした")
    elif cmd == "stale":
        L = ["# 再確認の候補（古くなっていそうな記述）", ""] + ([f"- {_lnk(x['path'], x['title'])} — {x['age_days']} 日更新なし: " + " / ".join(x["reasons"]) for x in res] or ["- なし"])
    elif cmd == "keywords":
        L = [f"# 索引語の候補: {res['note']}", "", "・".join(res["keywords"]) or "なし", "", res["note_text"]]
    elif cmd == "questions":
        L = [f"# 問題の候補: {res['note']}", "", res["note_text"], ""] + [x["text"] + "\n" for x in res["questions"]]
    elif cmd == "ask":
        L = [f"# 質問: {res['question']}", "", res["note_text"], ""] + [f"- {_lnk(x['path'])}:{x['line']} — {x['text']}（近さ {x['score']}）" for x in res["answers"]]
    elif cmd in ("semantic", "hybrid"):
        L = [f"# {'ハイブリッド' if cmd == 'hybrid' else '意味'}検索", ""] + [f"- {_lnk(x['path'], x['title'])} — {x['score']}" + (f"（{'・'.join(x['from'])}）" if "from" in x else "") for x in res]
    elif cmd == "nl":
        L = [f"# 検索条件: `{res['query']}`", ""] + [f"- {x}" for x in res["read_as"]] + ["", res["note_text"]]
    elif cmd == "report":
        return activity_md(res)
    elif cmd == "patrol":
        L = ["# 保存した検索の巡回", ""]
        for x in res["searches"]:
            L += [f"## {x['name']}（`{x['query']}`）— {x['count']} 件" + ("・初回" if x["first_run"] else f"・新しい一致 {len(x['new'])} 件"), ""] + [f"- {_lnk(p)}" for p in x["new"][:30]] + [""]
        if not res["searches"]:
            L.append("保存した検索がありません（:GnosisQuerySave）")
    else:
        L = [json.dumps(res, ensure_ascii=False, indent=1)]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        if len(argv) < 2:
            print(__doc__, file=sys.stderr)
            return 2
        md = "--md" in argv
        argv = [x for x in argv if x != "--md"]
        root, cmd, a = argv[0], argv[1], argv[2:]
        num = lambda i, d: int(a[i]) if len(a) > i and a[i].isdigit() else d
        if cmd == "nl":
            res = nl_to_query(" ".join(a))
        elif cmd == "patrol":
            res = patrol(root)
        else:
            c = Corpus.build(root)
            res = {"similar": lambda: similar(c, a[0], num(1, 5)), "links": lambda: link_suggestions(c, a[0], num(1, 8)), "index": lambda: index_candidates(c, a[0], num(1, 3)),
                   "summary": lambda: summarize(c, a[0], num(1, 3)), "common": lambda: common(c, a), "conflicts": lambda: conflicts(c, a[0] if a else None),
                   "stale": lambda: stale(c, num(0, 365)), "keywords": lambda: keywords(c, a[0], num(1, 10)), "questions": lambda: questions(c, a[0], num(1, 6)),
                   "ask": lambda: ask(c, a[0], num(1, 4)), "semantic": lambda: semantic(c, a[0], num(1, 10)), "hybrid": lambda: hybrid(root, a[0], num(1, 10), c),
                   "duplicates": lambda: duplicates(c),
                   "report": lambda: activity(c, a[0] if a else "週", dt.date.fromisoformat(a[1]) if len(a) > 1 else None)}.get(cmd)
            if res is None:
                print(__doc__, file=sys.stderr)
                return 2
            res = res()
        print(render_md(cmd, res), end="") if md else print(json.dumps(res, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
