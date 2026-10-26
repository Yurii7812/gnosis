#!/usr/bin/env python3
"""daily_notes.py の試験（一時フォルダだけを使う）。"""
import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import daily_notes as dn  # noqa: E402

FAILED = []
WD = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def check(cond, name):
    print(("  ok   " if cond else "  FAIL ") + name)
    if not cond:
        FAILED.append(name)


def wd(date):
    import datetime
    y, m, d = map(int, date.split("-"))
    return WD[datetime.date(y, m, d).weekday()]


class V:
    def __init__(self, root):
        self.root = Path(root)
        self.n = 0

    def note(self, title, rec=None, parent=None, extra_fm=(), body=("本文",), top=()):
        self.n += 1
        name = f"{self.n:04d}.md"
        fm = ["---", "time: 2026-01-01 00:00:00"]
        if rec:
            fm.append(f'record: "{rec}"')
        if parent is not None:
            fm.append(f"parent_record: {parent}" if parent else "parent_record:")
        fm += list(extra_fm) + ["---", ""]
        lines = fm + [f"# {title}", ""] + list(top) + (list(top) and [""] or []) + list(body) + [""]
        (self.root / name).write_text("\n".join(lines), encoding="utf-8")
        return name

    def day(self, kind, date, parent=None, body=("本文",)):
        return self.note(f"{date}-{wd(date)}-{kind}", rec=kind, parent=parent, body=body)

    def diary(self, date, body=("日記本文",)):
        return self.note(f"{date}-{wd(date)}", body=body)

    def read(self, name):
        return (self.root / name).read_text(encoding="utf-8")


def block(text):
    """DailyNotes: の下のリンク先の表示名。"""
    lines = text.split("\n")
    if "DailyNotes:" not in lines:
        return None
    i = lines.index("DailyNotes:") + 1
    out = []
    while i < len(lines) and lines[i].startswith("["):
        out.append(lines[i].split("]")[0][1:])
        i += 1
    return out


def run():
    D = "2026-10-27"
    print("daily_notes: 親子 1 段（せどり → ビジネス）。同じ日付だけ・リンクがあるときだけ DailyNotes:")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        biz = v.day("ビジネス", D)
        sed = v.day("せどり", D, parent="ビジネス")
        biz_other = v.day("ビジネス", "2026-10-26")
        dia = v.diary(D)
        dn.sync_date(d, D)
        check(block(v.read(biz)) == ["せどり"], "ビジネスの当日に せどり へのリンクが DailyNotes: で出る")
        check(block(v.read(sed)) is None and "DailyNotes:" not in v.read(sed), "せどり（下位が無い）には DailyNotes: が出ない")
        check(block(v.read(biz_other)) is None, "別の日付のビジネスには出ない")
        check(block(v.read(dia)) == ["ビジネス"], "日記には最上位（ビジネス）だけ出て、せどりは出ない")
        check("-ビジネス\n\nDailyNotes:\n[せどり](0002.md)\n\n本文\n" in v.read(biz), "タイトルの下・本文の上に、空行をあけて並ぶ")
        first = {n: v.read(n) for n in (biz, sed, dia)}
        dn.sync_date(d, D)
        check({n: v.read(n) for n in (biz, sed, dia)} == first, "もう一度整えても同じ（冪等・重複しない）")
        check("本文" in v.read(biz) and "日記本文" in v.read(dia), "本文は残る")

    print("daily_notes: 多段・複数の下位")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        biz = v.day("ビジネス", D)
        sed = v.day("せどり", D, parent="ビジネス")
        furu = v.day("古本せどり", D, parent="せどり")
        dev = v.day("商品開発", D, parent="ビジネス")
        app = v.day("アプリ開発", D, parent="商品開発")
        dia = v.diary(D)
        dn.sync_date(d, D)
        check(block(v.read(biz)) == ["せどり", "商品開発"], "ビジネス: 直接の下位だけ（せどり・商品開発）。古本せどり・アプリ開発は出ない")
        check(block(v.read(sed)) == ["古本せどり"] and block(v.read(dev)) == ["アプリ開発"], "各階層で同じ規則")
        check(block(v.read(furu)) is None and block(v.read(app)) is None, "いちばん下には出ない")
        check(block(v.read(dia)) == ["ビジネス"], "日記: 最上位（ビジネス）だけ")

    print("daily_notes: 上位に記録が無い日 — 下位へのリンクが 2 つ以上つくなら作る・1 つなら飛ばす")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        v.day("ビジネス", "2026-10-01")                       # 系列は存在する（その日の記録は無い）
        v.day("勉強", "2026-10-01")
        sed = v.day("せどり", D, parent="ビジネス")
        dev = v.day("商品開発", D, parent="ビジネス")
        math = v.day("数学", D, parent="勉強")
        dia = v.diary(D)
        kinds = {"ビジネス", "勉強", "せどり", "商品開発", "数学"}
        check(dn.needed(d, D, kinds) == ["ビジネス"], "ビジネス（下位 2 つ）は作る。勉強（下位 1 つ）は作らない")
        # ビジネスのノートを作った状態
        biz = v.day("ビジネス", D)
        dn.sync_date(d, D)
        check(block(v.read(dia)) == ["ビジネス", "数学"], "日記: ビジネス（作った）と、勉強を飛ばした 数学")
        check(block(v.read(biz)) == ["せどり", "商品開発"], "作ったビジネスに せどり・商品開発")
        check(dn.needed(d, D, kinds) == [], "もう作るものは無い（固定点）")

    print("daily_notes: 中間が 2 段とも記録が無い — 古本せどり 1 つだけなら飛ばして、2 つなら中間も作る")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        for k, p in (("ビジネス", None), ("せどり", "ビジネス"), ("古本せどり", "せどり"), ("家電せどり", "せどり")):
            v.day(k, "2026-10-01", parent=p)
        v.day("古本せどり", D, parent="せどり")
        kinds = {"ビジネス", "せどり", "古本せどり", "家電せどり"}
        check(dn.needed(d, D, kinds) == [], "古本せどり 1 つだけなら、せどり・ビジネスは作らない（飛ばす）")
        v.day("家電せどり", D, parent="せどり")
        check(dn.needed(d, D, kinds) == ["せどり"], "古本せどりと家電せどりの 2 つなら せどり を作る（ビジネスには せどり 1 つだけなので作らない）")
        v.day("商品開発", "2026-10-01", parent="ビジネス")
        v.day("商品開発", D, parent="ビジネス")
        kinds.add("商品開発")
        check(dn.needed(d, D, kinds) == ["せどり", "ビジネス"] or sorted(dn.needed(d, D, kinds)) == ["せどり", "ビジネス"], "商品開発も加わると、せどり（2 つ）とビジネス（せどり・商品開発の 2 つ）を作る")

    print("daily_notes: 中間（せどり）に記録が無い日は、1 つだけなら ビジネスにぶら下げる")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        biz = v.day("ビジネス", D)
        v.day("せどり", "2026-10-20", parent="ビジネス")      # 過去のせどり（上位 ビジネス）
        furu = v.day("古本せどり", D, parent="せどり")
        dn.sync_date(d, D)
        check(block(v.read(biz)) == ["古本せどり"], "せどりの記録が無い日は、せどりの過去の上位（ビジネス）を使って飛ばす")

    print("daily_notes: 上位が日ごとに変わる（10/20 はビジネス、10/27 は副業）")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        biz20 = v.day("ビジネス", "2026-10-20")
        sub20 = v.day("副業", "2026-10-20")
        sed20 = v.day("せどり", "2026-10-20", parent="ビジネス")
        biz27 = v.day("ビジネス", D)
        sub27 = v.day("副業", D)
        sed27 = v.day("せどり", D, parent="副業")
        dn.sync_all(d)
        check(block(v.read(biz20)) == ["せどり"] and block(v.read(sub20)) is None, "10/20: ビジネスにだけ せどり")
        check(block(v.read(sub27)) == ["せどり"] and block(v.read(biz27)) is None, "10/27: 副業にだけ せどり（ビジネスには出ない）")

    print("daily_notes: 古い自動リンクが残らない・手書きは残る・DailyNotes: が消える")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        biz = v.day("ビジネス", D)
        sed = v.day("せどり", D, parent="ビジネス")
        other = v.note("手書きで繋ぐノート")
        dn.sync_date(d, D)
        # 手書きのリンクを DailyNotes: の下に足す
        t = v.read(biz).replace("DailyNotes:\n", f"DailyNotes:\n[手書き]({other})\n", 1)
        (Path(d) / biz).write_text(t, encoding="utf-8")
        dn.sync_date(d, D)
        check("[手書き](" + other + ")" in v.read(biz) and block(v.read(biz))[0] == "せどり", "手書きのリンクは残り、自動の行は先に並ぶ")
        # せどりの上位を解除すると、ビジネスから せどり のリンクが消えるが、手書きは残る
        r = dn.set_parent(d, "せどり", D, "none")
        check(r["ok"], "上位を解除できる")
        check(block(v.read(biz)) == ["手書き"], "自動の行は消え、手書きは残る（DailyNotes: は手書きのために残る）")
        t = v.read(biz).replace(f"[手書き]({other})\n", "", 1)
        (Path(d) / biz).write_text(t, encoding="utf-8")
        dn.sync_date(d, D)
        check("DailyNotes:" not in v.read(biz), "リンクが一つも無くなれば DailyNotes: も消える")

    print("daily_notes: 継承（指定日より前の直近・解除も引き継ぐ・未来は使わない）")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        v.day("せどり", "2026-10-20", parent="ビジネス")
        v.day("せどり", "2026-10-25", parent="副業")
        v.day("ビジネス", "2026-10-01")
        v.day("副業", "2026-10-01")
        check(dn.inherit(d, "せどり", "2026-10-21") == "ビジネス", "10/21 は 10/20 の ビジネス を引き継ぐ")
        check(dn.inherit(d, "せどり", "2026-10-22") == "ビジネス", "後から作る 10/22 も、10/20 の設定（未来の 10/25 は使わない）")
        check(dn.inherit(d, "せどり", "2026-10-26") == "副業", "10/26 は 10/25 の 副業")
        check(dn.inherit(d, "せどり", "2026-10-10") == "unset", "過去の記録が無ければ未設定")
        v.day("数学", "2026-10-02", parent="")
        check(dn.inherit(d, "数学", "2026-10-03") == "none", "明示的な解除も引き継ぐ")

    print("daily_notes: 循環と存在しない系列の拒否")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        v.day("A", D, parent="B")
        v.day("B", D)
        check(not dn.set_parent(d, "B", D, "A")["ok"], "A の上位が B のとき、B の上位を A にはできない（循環）")
        check(not dn.set_parent(d, "A", D, "A")["ok"], "自分自身は上位にできない")
        check(not dn.set_parent(d, "A", D, "存在しない")["ok"], "存在しない系列は上位にできない")
        check(dn.set_parent(d, "A", D, "none")["ok"], "解除はできる")
        check("parent_record:" in v.read("0001.md") and "parent_record: B" not in v.read("0001.md"), "解除は parent_record:（空）で明示される")

    print("daily_notes: 日記の昔の自動リンク（見出し無し）は DailyNotes: に置き換わる")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        dream = v.day("夢", D)
        dia = v.note(f"{D}-{wd(D)}", top=(f"[{D}-{wd(D)}-夢]({dream})",), body=("日記本文",))
        dn.sync_date(d, D)
        t = v.read(dia)
        check(block(t) == ["夢"] and t.count(f"({dream})") == 1, "昔の見出し無しのリンクは、DailyNotes: の 1 つに置き換わる")
        check("日記本文" in t, "日記の本文は残る")
        check(v.read(dream).count("DailyNotes:") == 0, "夢（下位が無い）には出ない")

    print("daily_notes: 紙の日記（source: scan）やふつうのノートは触らない")
    with tempfile.TemporaryDirectory() as d:
        v = V(d)
        v.day("夢", D)
        paper = v.note(f"{D}-{wd(D)}", extra_fm=("source: scan",))
        plain = v.note("ふつうのノート")
        before = {n: v.read(n) for n in (paper, plain)}
        dn.sync_date(d, D)
        check({n: v.read(n) for n in (paper, plain)} == before, "紙の日記・ふつうのノートは変わらない")


if __name__ == "__main__":
    run()
    print()
    print("all passed" if not FAILED else f"{len(FAILED)} FAILED")
    sys.exit(1 if FAILED else 0)
