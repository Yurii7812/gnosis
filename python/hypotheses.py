#!/usr/bin/env python3
"""仮説実験室（XP10）と思考の対戦（XP11）。読み取り専用。

ノートの中に、次の形で書く（ふつうの Markdown。行頭の印で読む）:
  仮説: 睡眠は記憶の定着に効く
  状態: 検証中                       … 検証中 / 支持 / 棄却 / 保留（省略可。書かなければ「未設定」）
  + 証拠: 学習後の睡眠で成績が上がった [論文](paper.md)
  - 反証: 昼寝だけでは差が出なかった [実験](nap.md)
  結論: 当面は支持する                … 省略可
  履歴: 2026-10-21 検証中 / 2026-11-02 支持   … 状態の変遷（省略可。日付 状態 を「 / 」で区切る）
`仮説:` の行から、空行（または次の `仮説:`）までが 1 つの仮説。コードブロックの中は読まない。
集計は数えるだけ（証拠 n・反証 m・リンク先）。**「支持」「棄却」を自動では決めない**。状態の候補（提案）は出すが、ノートは書き換えない。

CLI（JSON。--md なら Markdown）:
  hypotheses.py ROOT list [--status S]         すべての仮説（ノート・行・状態・証拠/反証の数）
  hypotheses.py ROOT show NOTE [N]             そのノートの仮説の詳細（N 番目。省略で全部）
  hypotheses.py ROOT debate A B                2 つの仮説（題の一部・`ノート#N`）を並べて比べる
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tasks as tk  # noqa: E402

HEAD = re.compile(r"^\s*(?:[-*+]\s+)?(?:仮説|Hypothesis)\s*[:：]\s*(.+?)\s*$", re.I)
PRO = re.compile(r"^\s*[+＋]\s*(?:証拠|evidence)\s*[:：]\s*(.+?)\s*$", re.I)
CON = re.compile(r"^\s*[-−ー]\s*(?:反証|counter)\s*[:：]\s*(.+?)\s*$", re.I)
STATE = re.compile(r"^\s*状態\s*[:：]\s*(.+?)\s*$")
CONCL = re.compile(r"^\s*結論\s*[:：]\s*(.+?)\s*$")
HIST = re.compile(r"^\s*履歴\s*[:：]\s*(.+?)\s*$")
LINK = re.compile(r"(?<!!)\[((?:\\.|[^\]\\])*)\]\(([^)\s]+?)(?:#[^)\s]*)?\)")
STATES = ("検証中", "支持", "棄却", "保留")


def _links(text: str) -> list[dict]:
    return [{"text": m.group(1), "target": m.group(2)} for m in LINK.finditer(text) if "://" not in m.group(2)]


def parse_text(text: str, file: str = "") -> list[dict]:
    """1 つのノートから仮説を読む。"""
    out, cur, fence = [], None, False
    lines = text.split("\n")
    for i, raw in enumerate(lines, 1):
        if raw.strip().startswith(("```", "~~~")):
            fence = not fence
            continue
        if fence:
            continue
        m = HEAD.match(raw)
        if m:
            cur = {"file": file, "line": i, "claim": m.group(1), "status": "", "evidence": [], "counter": [], "conclusion": "", "history": []}
            out.append(cur)
            continue
        if cur is None:
            continue
        if not raw.strip():
            cur = None
            continue
        for rx, key in ((PRO, "evidence"), (CON, "counter")):
            mm = rx.match(raw)
            if mm:
                cur[key].append({"text": mm.group(1), "line": i, "links": _links(mm.group(1))})
                break
        else:
            mm = STATE.match(raw)
            if mm:
                cur["status"] = mm.group(1)
                continue
            mm = CONCL.match(raw)
            if mm:
                cur["conclusion"] = mm.group(1)
                continue
            mm = HIST.match(raw)
            if mm:
                for part in re.split(r"\s*/\s*", mm.group(1)):
                    h = re.match(r"^(\d{4}-\d{2}-\d{2})\s+(.+)$", part.strip())
                    if h:
                        cur["history"].append({"date": h.group(1), "status": h.group(2)})
    return out


def suggest(h: dict) -> dict:
    """状態の候補（提案）。決めるのは利用者。証拠と反証の数だけを見る。"""
    p, c = len(h["evidence"]), len(h["counter"])
    if p == 0 and c == 0:
        s, why = "検証中", "証拠も反証もまだありません"
    elif c == 0:
        s, why = "支持", f"反証がなく、証拠が {p} 件あります"
    elif p == 0:
        s, why = "棄却", f"証拠がなく、反証が {c} 件あります"
    elif p >= 2 * c:
        s, why = "支持", f"証拠 {p} 件が反証 {c} 件の 2 倍以上です"
    elif c >= 2 * p:
        s, why = "棄却", f"反証 {c} 件が証拠 {p} 件の 2 倍以上です"
    else:
        s, why = "保留", f"証拠 {p} 件と反証 {c} 件が拮抗しています"
    return {"status": s, "why": why, "note_text": "数を数えた目安です。判断は自分で（状態: を書き換えるのは利用者）。"}


def collect(root: str | Path) -> list[dict]:
    root = Path(root).resolve()
    out = []
    for p in tk.iter_notes(root):
        text = p.read_text(encoding="utf-8")
        if "仮説" not in text and "ypothesis" not in text:
            continue
        rel = p.relative_to(root).as_posix()
        title = next((ln.split(":", 1)[1].strip() for ln in text.split("\n")[:12] if ln.startswith("title:")), p.stem)
        for n, h in enumerate(parse_text(text, rel), 1):
            h.update({"note_title": title, "n": n, "suggest": suggest(h), "id": f"{rel}#{n}",
                      "pro": len(h["evidence"]), "con": len(h["counter"]), "state_known": h["status"] in STATES})
            out.append(h)
    return out


def list_hyp(root: str | Path, status: str | None = None) -> dict:
    hs = collect(root)
    if status:
        hs = [h for h in hs if (h["status"] or "未設定") == status]
    counts: dict[str, int] = {}
    for h in collect(root):
        k = h["status"] or "未設定"
        counts[k] = counts.get(k, 0) + 1
    return {"count": len(hs), "by_status": counts, "hypotheses": hs}


def show(root: str | Path, note: str, n: int | None = None) -> dict:
    hs = [h for h in collect(root) if h["file"] == note or Path(h["file"]).name == note or Path(h["file"]).stem == note or h["note_title"] == note]
    if not hs:
        raise ValueError("そのノートに仮説がありません: " + note)
    if n is not None:
        hs = [h for h in hs if h["n"] == n]
        if not hs:
            raise ValueError(f"{n} 番目の仮説がありません")
    return {"hypotheses": hs}


def _pick(hs: list[dict], key: str) -> dict:
    m = re.match(r"^(.+)#(\d+)$", key)
    if m:
        c = [h for h in hs if (h["file"] == m.group(1) or Path(h["file"]).name == m.group(1)) and h["n"] == int(m.group(2))]
    else:
        c = [h for h in hs if key in h["claim"]]
    if not c:
        raise ValueError("仮説が見つかりません: " + key)
    if len(c) > 1:
        raise ValueError(f"「{key}」に当てはまる仮説が {len(c)} 件あります。`ノート#番号` で指定してください")
    return c[0]


def debate(root: str | Path, a: str, b: str) -> dict:
    hs = collect(root)
    A, B = _pick(hs, a), _pick(hs, b)
    if A["id"] == B["id"]:
        raise ValueError("別々の仮説を選んでください")
    def targets(h):
        return {x["target"] for e in h["evidence"] + h["counter"] for x in e["links"]}
    ta, tb = targets(A), targets(B)
    shared = sorted(ta & tb)
    side = lambda h: {"id": h["id"], "claim": h["claim"], "status": h["status"] or "未設定", "pro": h["pro"], "con": h["con"], "evidence": h["evidence"], "counter": h["counter"], "suggest": h["suggest"]}
    sa, sb = side(A), side(B)
    # 食い違い: 同じ出典を、一方は証拠・他方は反証として使っている
    def role(h, t):
        return ("証拠" if any(t == x["target"] for e in h["evidence"] for x in e["links"]) else "") + ("反証" if any(t == x["target"] for e in h["counter"] for x in e["links"]) else "")
    clash = [{"target": t, "A": role(A, t), "B": role(B, t)} for t in shared if role(A, t) and role(B, t) and role(A, t) != role(B, t)]
    lead = "拮抗" if abs((A["pro"] - A["con"]) - (B["pro"] - B["con"])) == 0 else ("A" if (A["pro"] - A["con"]) > (B["pro"] - B["con"]) else "B")
    return {"A": sa, "B": sb, "shared_sources": shared, "clashes": clash, "lead": lead,
            "note_text": "証拠と反証の数の差を比べただけです（内容の正しさは判断していません）。"}


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    def lk(h):
        return f"[{h['note_title']}]({h['file'].replace(' ', '%20')}):{h['line']}"
    if kind == "list":
        L = [f"# 仮説 {r['count']} 件", "", "状態: " + "・".join(f"{k} {v}" for k, v in sorted(r["by_status"].items())), ""]
        for h in r["hypotheses"]:
            L.append(f"- **{h['claim']}**（{h['status'] or '未設定'}・証拠 {h['pro']}・反証 {h['con']}）— {lk(h)}")
            if h["suggest"]["status"] != (h["status"] or ""):
                L.append(f"  - 目安: {h['suggest']['status']}（{h['suggest']['why']}）")
    elif kind == "show":
        for h in r["hypotheses"]:
            L += [f"# 仮説: {h['claim']}", "", f"- 状態: {h['status'] or '未設定'}・{lk(h)}", f"- 目安: {h['suggest']['status']}（{h['suggest']['why']}）", ""]
            L += ["## 証拠", ""] + ([f"- {e['text']}" for e in h["evidence"]] or ["なし"]) + ["", "## 反証", ""] + ([f"- {e['text']}" for e in h["counter"]] or ["なし"]) + [""]
            if h["conclusion"]:
                L += ["## 結論", "", h["conclusion"], ""]
            if h["history"]:
                L += ["## 履歴", ""] + [f"- {x['date']} {x['status']}" for x in h["history"]] + [""]
    elif kind == "debate":
        A, B = r["A"], r["B"]
        L = ["# 思考の対戦", "", f"| | A | B |", "|---|---|---|", f"| 主張 | {A['claim']} | {B['claim']} |", f"| 状態 | {A['status']} | {B['status']} |",
             f"| 証拠 | {A['pro']} | {B['pro']} |", f"| 反証 | {A['con']} | {B['con']} |", f"| 目安 | {A['suggest']['status']} | {B['suggest']['status']} |", "",
             f"優勢: {r['lead']}（証拠−反証の差で比べた）", ""]
        if r["clashes"]:
            L += ["## 同じ出典を逆の立場で使っている", ""] + [f"- {c['target']}: A は{c['A']}・B は{c['B']}" for c in r["clashes"]] + [""]
        if r["shared_sources"]:
            L += ["## 共通の出典", ""] + [f"- {t}" for t in r["shared_sources"]] + [""]
        L.append(r["note_text"])
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        a = [x for x in argv if x != "--md"]
        status = None
        if "--status" in a:
            i = a.index("--status"); status = a[i + 1]; del a[i:i + 2]
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "list":
            r = list_hyp(root, status)
        elif cmd == "show":
            r = show(root, rest[0], int(rest[1]) if len(rest) > 1 else None)
        elif cmd == "debate":
            r = debate(root, rest[0], rest[1])
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
