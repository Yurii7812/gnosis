#!/usr/bin/env python3
"""capture_merge: スマホ側の変更だけを PC のノートへ 3-way で反映する（仕様 §7.3 の本文まわり）。"""
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capture_merge as cm

FAILED = 0


def check(ok: bool, msg: str) -> None:
    global FAILED
    print(("  ok   " if ok else "  FAIL ") + msg)
    if not ok:
        FAILED += 1


HEAD = ["---", "time: 2026-10-01 00:00:00", "title: A", "---", "", "# A", ""]


def note(body, tail=("",)):
    return HEAD + list(body) + list(tail)


def test_basic() -> None:
    print("merge: 基本")
    base = ["一行目", "二行目", "三行目"]
    # スマホが 1 行だけ変えた → その行だけ更新
    m, c = cm.merge(base, ["一行目", "二行目(改)", "三行目"], note(base))
    check(c == [] and m == note(["一行目", "二行目(改)", "三行目"]), f"スマホの 1 行変更が反映される: {m}")
    # PC が末尾へ追記 + スマホが別の行を変更 → 両方残る
    local = note(base + ["PC の追記"])
    m, c = cm.merge(base, ["一行目(改)", "二行目", "三行目"], local)
    check(c == [] and m == note(["一行目(改)", "二行目", "三行目", "PC の追記"]), f"PC の追記とスマホの別行編集が両方残る: {m}")
    # PC が別の行を変更 + スマホが別の行を変更
    m, c = cm.merge(base, ["一行目", "二行目", "三行目(スマホ)"], note(["一行目(PC)", "二行目", "三行目"]))
    check(c == [] and m == note(["一行目(PC)", "二行目", "三行目(スマホ)"]), "PC とスマホが別々の行を変えたら両方残る")
    # スマホが行を足す
    m, c = cm.merge(base, base + ["四行目"], note(base))
    check(c == [] and m == note(base + ["四行目"]), "スマホの追記が反映される")
    m, c = cm.merge(base, ["零行目"] + base, note(base))
    check(c == [] and m == note(["零行目"] + base), "先頭への挿入")
    # 前後の PC 側のブロック（関係など）は動かない
    local = ["---", "title: A", "---", "", "# A", "", "ParentBranch:", "[P](p.md)", ""] + base + ["", "### Context", "[X](x.md)", ""]
    m, c = cm.merge(base, ["一行目", "二行目(改)", "三行目"], local)
    check(c == [] and m[:9] == local[:9] and m[-4:] == local[-4:] and "二行目(改)" in m, "関係のブロックは触らない")


def test_conflict_and_idempotent() -> None:
    print("merge: 競合と冪等")
    base = ["一行目", "二行目", "三行目"]
    local = note(["一行目", "二行目(PC)", "三行目"])
    m, c = cm.merge(base, ["一行目", "二行目(スマホ)", "三行目"], local)
    check(m is None and len(c) == 1, "同じ行を別々に変えたら競合（何も返さない）")
    # すでに同じ変更がある（二度目の実行）
    done = note(["一行目", "二行目(改)", "三行目"])
    m, c = cm.merge(base, ["一行目", "二行目(改)", "三行目"], done)
    check(c == [] and m == done, "同じ変更が既にあれば当て済み（そのまま）")
    # 一度反映した結果にもう一度 base→remote を当てても変わらない（前回のスナップショットが更新されない障害）
    once, _ = cm.merge(base, ["一行目", "二行目(改)", "三行目", "四行目"], note(base))
    twice, c2 = cm.merge(base, ["一行目", "二行目(改)", "三行目", "四行目"], once)
    check(c2 == [] and twice == once, "反映済みに再度当てても二重にならない")
    m, c = cm.merge(base, base, local)
    check(c == [] and m == local, "スマホが変えていなければ何もしない")
    # PC が行を消した所へスマホが編集 → 競合
    m, c = cm.merge(base, ["一行目", "二行目(スマホ)", "三行目"], note(["一行目", "三行目"]))
    check(m is None, "PC が消した行をスマホが編集したら競合")


def test_images() -> None:
    print("merge: 画像")
    b = cm.body_lines("本文", ["a.jpg"])
    r = cm.body_lines("本文", ["a.jpg", "b.jpg"])
    m, c = cm.merge(b, r, note(b))
    check(c == [] and "![](capture-images/b.jpg)" in m and m.count("![](capture-images/a.jpg)") == 1, f"画像の追加: {m}")
    r2 = cm.body_lines("本文", [])
    m, c = cm.merge(b, r2, note(b))
    check(c == [] and "![](capture-images/a.jpg)" not in m, "画像を外す（ファイルは消さない・本文の行だけ）")


def test_apply_note() -> None:
    print("apply_note: ファイルへの適用（原子的・競合の記録）")
    with tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test")) as d:
        root = Path(d)
        p = root / "a.md"
        base = ["一行目", "二行目"]
        p.write_text("\n".join(note(base)) + "\n", encoding="utf-8")
        r = cm.apply_note(root, "id1", "a.md", base, ["一行目", "二行目(改)"])
        check(r["status"] == "merged" and "二行目(改)" in p.read_text(encoding="utf-8"), "merged")
        mt = p.stat().st_mtime_ns
        r = cm.apply_note(root, "id1", "a.md", base, ["一行目", "二行目(改)"])
        check(r["status"] == "unchanged" and p.stat().st_mtime_ns == mt, "二度目は unchanged でファイルを書き換えない")
        p.write_text(p.read_text(encoding="utf-8").replace("二行目(改)", "二行目(PC)"), encoding="utf-8")
        before = p.read_text(encoding="utf-8")
        r = cm.apply_note(root, "id1", "a.md", base, ["一行目", "二行目(スマホ)"])
        cp = cm.conflict_path(root, "id1")
        check(r["status"] == "conflict" and p.read_text(encoding="utf-8") == before and cp.is_file(), "競合はノートを変えず記録だけ残す")
        check(not list(root.glob("*.md")) == [] and len(list(root.glob("*.md"))) == 1 and not list(root.glob("*.gnosis-tmp")), "ノートは増えない・一時ファイルは残らない")
        cm.apply_note(root, "id1", "a.md", base, ["一行目", "二行目(PC)"])
        check(not cp.exists(), "競合が解消すれば記録は消える")


def main() -> int:
    for t in (test_basic, test_conflict_and_idempotent, test_images, test_apply_note):
        t()
    print(f"{FAILED} FAILED" if FAILED else "capture_merge OK")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
