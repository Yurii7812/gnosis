#!/usr/bin/env python3
"""DailyNotes: … 時系列記録（Record）の包含関係と、同じ日付のノートへの自動リンク（2026-10-27）。

各日のRecordのノート（front matter に `record: "せどり"`、題は `YYYY-MM-DD-曜日2文字-せどり`）は、
上位概念を `parent_record: ビジネス`（時系列記録の名前）で持てる。日付ごとに持つので、上位が途中で変わっても過去は変わらない。

その日の日記と、その日の各Recordのノートの上（Group: などの上部ブロックのあと、本文の前）に、
同じ日付の「いちばん近い下位Record」へのリンクを `DailyNotes:` の見出しつきで実ファイルに書く。

  - 日記には、その日のRecordのうち、上位がその日に無い（最上位の）ものだけを出す。
  - Recordには、その日にある、直接の（その日に記録のある、いちばん近い）下位Recordだけを出す。
    その日に記録の無い中間のRecordは飛ばす（空のノートは作らない）。
  - リンクが一つも無ければ、`DailyNotes:` の見出しも書かない（あれば消す）。
  - 手で書いたリンク・本文は変えない。自動の行（その日のRecord・日記へのリンク）だけを管理する。

継承: 新しい日のRecordは、同じ系列の、その日より前の直近のノートから `parent_record` を引き継ぐ（解除も引き継ぐ）。
未来の日の設定を過去に使わない。循環する包含関係は作らない。

使い方::

    daily_notes.py sync ROOT DATE            # その日の DailyNotes: を整える
    daily_notes.py plan ROOT DATE [系列,系列…]  # 同じ内容を書かずに JSON で返す（Vim 用）。create = その日に作るべき上位の系列
    daily_notes.py sync-all ROOT             # 全部の日を整える（移行）
    daily_notes.py plan-parent ROOT KIND DATE NAME [系列,…]   # 上位を NAME にした内容を書かずに返す（Vim 用。循環・存在しない系列は ok=false）
    daily_notes.py inherit ROOT KIND DATE    # 継承する値: 「unset」「none」または上位の名前
    daily_notes.py set-parent ROOT KIND DATE NAME   # その日のKINDのノートの上位を決める（NAME が空/none なら解除）
"""
from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_format_v2 as nf  # noqa: E402

DAILY_HEAD = "DailyNotes:"
TOP_HEADS = ("ParentBranch:", "BranchGroup:", "ThisNoteGroup:", "Group:", "Context:")
LINK_LINE = re.compile(r"^\s*\[(?:\\.|[^\]\\])*\]\(([^)\s]+)\)\s*$")
TITLE_DAY = re.compile(r"^(\d{4}-\d{2}-\d{2})-([A-Z]{2})(?:-(.+))?$")
LEGACY_AUTO = re.compile(r"^\s*\[(\d{4}-\d{2}-\d{2}-[A-Z]{2}-[^\]]+)\]\(([^)\s]+)\)\s*$")
KEY = "parent_record"
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


@dataclass(eq=False)
class Rec:
    path: Path
    rel: str
    title: str
    date: str
    kind: str          # "" = 日記
    lines: list = field(default_factory=list)
    parent: object = None   # None = 未設定（キーが無い）／ "" = 明示的に解除 ／ 名前


def _unq(v: str) -> str:
    v = v.strip()
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        try:
            return json.loads(v)
        except ValueError:
            return v[1:-1]
    return v


def _fm_get(fm: list[str], key: str):
    pat = re.compile(r"^" + re.escape(key) + r"\s*:(.*)$")
    for ln in fm[1:-1] if len(fm) >= 2 else []:
        m = pat.match(ln)
        if m:
            return _unq(m.group(1))
    return None


def _quote(v: str) -> str:
    return json.dumps(v, ensure_ascii=False) if re.search(r'[:#\[\]{}",&*!|>\'%@`]|^\s|\s$', v) else v


def load(root) -> list[Rec]:
    root = Path(root).resolve()
    out: list[Rec] = []
    for p in nf._iter_md(root):
        try:
            text = Path(p).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        lines = text.split("\n")
        fm, rest = nf._split_front_matter(lines)
        title = nf._title_of(fm, rest, Path(p).stem)
        m = TITLE_DAY.match(title)
        if not m:
            continue
        kind_fm = _fm_get(fm, "record")
        if kind_fm:
            # Recordのその日のノート: 題が 日付-曜日-系列名
            if m.group(3) is None or not (m.group(3) == kind_fm or m.group(3).startswith(kind_fm + "-")):
                continue
            kind = kind_fm
        elif m.group(3) is None and not _fm_get(fm, "source"):
            kind = ""        # 日記（デジタル）。スキャン由来（source: scan）の紙の日記は含めない
        else:
            continue
        pv = _fm_get(fm, KEY)
        out.append(Rec(Path(p), str(Path(p).resolve().relative_to(root)).replace(os.sep, "/"), title, m.group(1), kind, lines, pv))
    return out


class Day:
    """ある日の状態。"""

    def __init__(self, recs: list[Rec], date: str):
        self.date = date
        self.all = recs
        self.by_kind: dict[str, list[Rec]] = {}
        for r in recs:
            if r.kind:
                self.by_kind.setdefault(r.kind, []).append(r)
        for v in self.by_kind.values():
            v.sort(key=lambda r: r.date)
        self.today = {k: next((r for r in v if r.date == date), None) for k, v in self.by_kind.items()}
        self.today = {k: r for k, r in self.today.items() if r is not None}
        self.diary = next((r for r in recs if not r.kind and r.date == date), None)

    def effective_parent(self, kind: str, date: str | None = None) -> str:
        """その日（date）の kind の上位。その日にノートがあって `parent_record` があればそれ。
        無ければ、その日より前の直近のノート（`parent_record` があるもの）から引き継ぐ。無ければ ""。"""
        date = date or self.date
        notes = self.by_kind.get(kind, [])
        cur = next((r for r in notes if r.date == date), None)
        if cur is not None and cur.parent is not None:
            return cur.parent
        prev = [r for r in notes if r.date < date and r.parent is not None]
        return prev[-1].parent if prev else ""

    def inherited(self, kind: str, date: str):
        """新しく作るときの継承値: None（未設定）／ ""（解除）／ 名前"""
        prev = [r for r in self.by_kind.get(kind, []) if r.date < date and r.parent is not None]
        return prev[-1].parent if prev else None

    def needed_ancestors(self, kinds: set[str] | None = None) -> list[str]:
        """その日に記録の無い上位の系列のうち、下位へのリンクが 2 つ以上つく見込みのものは、その日のノートを作る。
        （1 つだけなら作らずに飛ばす。途中の系列も同じ規則で、固定点まで繰り返す。）
        kinds = 作ってよい系列名（時系列記録として存在するもの）。None なら、記録が 1 つでもある系列。"""
        valid = set(kinds) if kinds is not None else set(self.by_kind)
        present = set(self.today)
        chain: dict[str, list[str]] = {}

        def ancestors(k: str) -> list[str]:
            out, seen, p = [], {k}, self.effective_parent(k)
            while p and p not in seen:
                out.append(p)
                seen.add(p)
                p = self.effective_parent(p)
            return out

        cand: set[str] = set()
        for k in present:
            chain[k] = ancestors(k)
            cand.update(a for a in chain[k] if a not in present and a in valid)
        made: list[str] = []
        members = set(present)
        changed = True
        while changed:
            changed = False
            for a in sorted(cand - members):
                count = 0
                for x in list(members):
                    c = chain.get(x) or ancestors(x)
                    chain[x] = c
                    first = next((y for y in c if y in members or y == a), None)
                    if first == a:
                        count += 1
                if count >= 2:
                    members.add(a)
                    made.append(a)
                    chain.setdefault(a, ancestors(a))
                    changed = True
        return made

    def attach_point(self, kind: str) -> str:
        """kind の記録をぶら下げる先の系列名（"" = 日記）。その日に記録の無い中間の系列は飛ばす。"""
        seen = {kind}
        p = self.effective_parent(kind)
        while p:
            if p in self.today and p not in seen:
                return p
            if p in seen:
                return ""      # 循環は最上位として扱う
            seen.add(p)
            p = self.effective_parent(p)
        return ""

    def children(self) -> dict[str, list[str]]:
        """{ぶら下げ先の系列名（"" = 日記）: [下位の系列名…]}"""
        out: dict[str, list[str]] = {}
        for k in sorted(self.today):
            out.setdefault(self.attach_point(k), []).append(k)
        return out

    def would_cycle(self, kind: str, parent: str, date: str) -> bool:
        """kind の上位を parent にすると、循環するか。"""
        if not parent:
            return False
        seen = set()
        p = parent
        while p:
            if p == kind:
                return True
            if p in seen:
                return True
            seen.add(p)
            p = self.effective_parent(p, date)
        return False


# ---- ノートの本文を整える ---------------------------------------------------------------------

def _h1(lines: list[str]) -> int:
    fm, _ = nf._split_front_matter(lines)
    flags = nf._fenced(lines)
    for i in range(len(fm), len(lines)):
        if not flags[i] and re.match(r"^#\s", lines[i]):
            return i
    return -1


def _top_end(lines: list[str], h1: int) -> int:
    """上部ブロック（ParentBranch: / Group: / Context: など）の終わりの次の行。無ければ h1 + 1。"""
    i = h1 + 1
    end = h1 + 1
    while True:
        j = i
        while j < len(lines) and not lines[j].strip():
            j += 1
        if j >= len(lines) or lines[j].strip() not in TOP_HEADS:
            break
        j += 1
        while j < len(lines) and LINK_LINE.match(lines[j]):
            j += 1
        end = j
        i = j
    return end


def _rel_link(a: Rec, b: Rec, text: str) -> str:
    rel = os.path.relpath(b.path, a.path.parent).replace(os.sep, "/")
    return f"[{text}]({rel})"


def _target_name(line: str, base: Path) -> str:
    m = LINK_LINE.match(line)
    if not m:
        return ""
    t = m.group(1).split("#", 1)[0]
    return os.path.normpath(str((base / t))) if t else ""


def rewrite(note: Rec, links: list[str], managed: set[str]) -> list[str] | None:
    """note の DailyNotes: ブロックを links（自動の行）にする。managed = 自動で管理する宛先（その日のRecord・日記の絶対パス）。
    手で書いた（managed でない宛先の）行は残す。変わらなければ None。"""
    lines = list(note.lines)
    h1 = _h1(lines)
    if h1 < 0:
        return None
    e = _top_end(lines, h1)
    base = note.path.parent
    # 上部ブロックのあとの空行をまたいで、今ある DailyNotes: ブロックと、昔の自動の行（見出し無しの日記へのリンク）を探す
    i = e
    while i < len(lines) and not lines[i].strip():
        i += 1
    kept: list[str] = []
    start = e
    stop = e
    if i < len(lines) and lines[i].strip() == DAILY_HEAD:
        j = i + 1
        while j < len(lines) and LINK_LINE.match(lines[j]):
            if _target_name(lines[j], base) not in managed:
                kept.append(lines[j])
            j += 1
        start, stop = e, j
    else:
        # 昔の形: 見出し無しで並んでいた自動のリンク行（題が 日付-曜日-系列名 で、宛先がその日のRecord）
        j = i
        while j < len(lines) and LEGACY_AUTO.match(lines[j]) and _target_name(lines[j], base) in managed:
            j += 1
        if j > i:
            start, stop = e, j
    had_block = stop > start
    if not had_block and not links:
        return None           # 何も無く、足すものも無い: ノートを触らない（手書きの空行などを変えない）
    new_block = [DAILY_HEAD] + links + kept if (links or kept) else []
    # 区切り: ブロックの前は空行 1 つ、後ろは本文との間に空行 1 つ
    before = lines[:start]
    after = lines[stop:]
    while after and not after[0].strip():
        after = after[1:]
    out = list(before)
    while out and not out[-1].strip() and len(out) > h1 + 1:
        out.pop()
    if new_block:
        out += [""] + new_block
        if after:
            out += [""]
    else:
        if after:
            out += [""]
    out += after
    # 元の末尾（最後の改行）を保つ
    return out if out != lines else None


def needed(root, date: str, kinds=None) -> list[str]:
    """date に、記録が無くても作るべき系列（下位へのリンクが 2 つ以上つく上位）。"""
    return Day(load(root), date).needed_ancestors(set(kinds) if kinds is not None else None)


def plan_date(root, date: str, recs: list[Rec] | None = None) -> dict:
    """date の DailyNotes: を整えたあとの内容（変わるノートだけ）: {Rec: 新しい行}。ファイルは書かない。"""
    root = Path(root).resolve()
    recs = recs if recs is not None else load(root)
    day = Day(recs, date)
    managed = {os.path.normpath(str(r.path)) for r in recs if r.date == date}
    children = day.children()
    plan: dict = {}
    owners: list[tuple[Rec, str]] = [(r, k) for k, r in day.today.items()]
    if day.diary is not None:
        owners.append((day.diary, ""))
    for rec, k in owners:
        links = [_rel_link(rec, day.today[c], c) for c in children.get(k, [])]
        new = rewrite(rec, links, managed)
        if new is not None:
            plan[rec] = new
    return plan


def sync_date(root, date: str, recs: list[Rec] | None = None) -> list[str]:
    """date の DailyNotes: を整える。変えたファイルの相対パスを返す。"""
    changed: list[str] = []
    for rec, new in plan_date(root, date, recs).items():
        Path(rec.path).write_text("\n".join(new), encoding="utf-8")
        changed.append(rec.rel)
    return changed


def sync_all(root) -> list[str]:
    root = Path(root).resolve()
    recs = load(root)
    dates = sorted({r.date for r in recs})
    out: list[str] = []
    for d in dates:
        out += sync_date(root, d, load(root))
    return out


# ---- 上位の設定・継承 -------------------------------------------------------------------------

def inherit(root, kind: str, date: str) -> str:
    day = Day(load(root), date)
    v = day.inherited(kind, date)
    return "unset" if v is None else ("none" if v == "" else v)


def _set_fm_key(lines: list[str], key: str, value: str | None) -> list[str]:
    fm, rest = nf._split_front_matter(lines)
    if not fm:
        return lines
    pat = re.compile(r"^" + re.escape(key) + r"\s*:")
    body = [ln for ln in fm[1:-1] if not pat.match(ln)]
    if value is not None:
        at = next((i for i, ln in enumerate(body) if ln.startswith("record:")), len(body) - 1) + 1
        body.insert(at, f"{key}: {_quote(value)}" if value else f"{key}:")
    return [fm[0]] + body + [fm[-1]] + rest


def plan_parent(root, kind: str, date: str, parent: str, kinds=None) -> dict:
    """その日の kind のノートの上位を parent にした内容（書かない）。{"ok", "file": 相対パス, "lines": [行…]} か {"ok": False, "error"}"""
    root = Path(root).resolve()
    recs = load(root)
    day = Day(recs, date)
    rec = day.today.get(kind)
    if rec is None:
        return {"ok": False, "error": f"{date} の {kind} のノートがありません"}
    parent = "" if parent in ("none", "-") else parent.strip()
    if parent == kind:
        return {"ok": False, "error": "自分自身を上位にはできません"}
    known = set(day.by_kind) | set(kinds or ())
    if parent and parent not in known:
        return {"ok": False, "error": f"時系列記録「{parent}」がありません"}
    if day.would_cycle(kind, parent, date):
        return {"ok": False, "error": "包含関係が循環します"}
    return {"ok": True, "file": rec.rel, "lines": _set_fm_key(rec.lines, KEY, parent)}


def set_parent(root, kind: str, date: str, parent: str) -> dict:
    """plan_parent の内容を書き、その日の DailyNotes: を整える（Vim を通さない使い方。試験・コマンドライン用）。"""
    r = plan_parent(root, kind, date, parent)
    if not r["ok"]:
        return r
    path = Path(root).resolve() / r["file"]
    old = path.read_text(encoding="utf-8").split("\n")
    if r["lines"] != old:
        path.write_text("\n".join(r["lines"]), encoding="utf-8")
    changed = sync_date(root, date)
    return {"ok": True, "changed": [r["file"]] + changed}


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "sync-all":
        print(json.dumps({"ok": True, "changed": sync_all(argv[2])}, ensure_ascii=False))
        return 0
    if len(argv) >= 4 and argv[1] == "sync":
        if not DATE_RE.match(argv[3]):
            print(json.dumps({"ok": False, "error": "日付は YYYY-MM-DD"}, ensure_ascii=False))
            return 1
        print(json.dumps({"ok": True, "changed": sync_date(argv[2], argv[3])}, ensure_ascii=False))
        return 0
    if len(argv) >= 4 and argv[1] == "plan":
        # Vim が開いているノートも安全に書き換えられるように、書かずに新しい内容だけ返す: {"files": {相対パス: [行…]}}
        kinds = argv[4].split(",") if len(argv) > 4 and argv[4] else None
        plan = plan_date(argv[2], argv[3])
        print(json.dumps({"ok": True, "create": needed(argv[2], argv[3], kinds),
                          "files": {r.rel: new for r, new in plan.items()}}, ensure_ascii=False))
        return 0
    if len(argv) >= 6 and argv[1] == "plan-parent":
        kinds = argv[6].split(",") if len(argv) > 6 and argv[6] else None
        print(json.dumps(plan_parent(argv[2], argv[3], argv[4], argv[5], kinds), ensure_ascii=False))
        return 0
    if len(argv) >= 5 and argv[1] == "inherit":
        print(inherit(argv[2], argv[3], argv[4]))
        return 0
    if len(argv) >= 5 and argv[1] == "set-parent":
        r = set_parent(argv[2], argv[3], argv[4], argv[5] if len(argv) > 5 else "")
        print(json.dumps(r, ensure_ascii=False))
        return 0 if r["ok"] else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
