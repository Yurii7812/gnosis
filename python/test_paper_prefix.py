#!/usr/bin/env python3
"""紙のノートの印（PA・PB…）の試験: 題と画像が PA- 付き・印ごとのグループ・印が増えたら改名・旧い題は PA- に直る。
一時フォルダだけを使う。"""
import json
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import paper_pkm as pp  # noqa: E402
import japanese_yomi as jy  # noqa: E402
import test_paper_pkm as base  # noqa: E402
from test_paper_pkm import check, T, N, _make_vault, _add_images  # noqa: E402


def titles(root):
    out = {}
    for n in pp.load_notes(root):
        out.setdefault(n.title, []).append(n)
    return out


def block_links(path: Path, head: str) -> list[str]:
    lines = path.read_text(encoding="utf-8").split("\n")
    out = []
    i = lines.index(head) + 1 if head in lines else len(lines)
    while i < len(lines) and re.match(r"^\[", lines[i]):
        out.append(lines[i])
        i += 1
    return out


def test_single_prefix_structure() -> None:
    print("印が 1 つ（PA）: 題と画像は PA- 付き。頂点の BranchGroup: はグループ 1 つ")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        pp.create_paper_index(root)
        moved, errors = pp.move_images(root, root, _add_images(root, ["1", "1a"]))
        check(not errors and [m[0] for m in moved] == ["PA-1", "PA-1a"], f"題は PA- 付き: {moved}")
        check((root / "PA-1.jpg").is_file() and (root / "PA-1a.jpg").is_file(), "画像のファイル名も PA- 付き")
        pp.regen(root, do_sync=False)
        t = titles(root)
        check("Paper-Zettelkasten-Index" in t and "Index-write" in t and "Folgezettel-Index" in t, "印が 1 つなら今までの名前")
        check(not any(k.startswith("Paper-Zettelkasten-Index-") for k in t), "印が 1 つなら -PA は付かない")
        top = pp.find_paper_top(root)
        links = block_links(top, "BranchGroup:")
        check(len(links) == 1 and links[0].startswith("[Paper-Zettelkasten-Index]"), f"頂点の BranchGroup: はグループ 1 つ: {links}")
        check(any("folgezettel-Index-1" in k for k in t), "番号専用ノートは folgezettel-Index-1")


def test_second_prefix_renames() -> None:
    print("印が増える（PB）: 既存の生成物に -PA を付けて改名し、PB の組を作る。1 つに戻れば元の名前")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        pp.create_paper_index(root)
        pp.move_images(root, root, _add_images(root, ["1", "1a"]))
        pp.regen(root, do_sync=False)
        a_ids = {n.title: n.path for n in pp.load_notes(root) if n.title in ("Paper-Zettelkasten-Index", "Index-write", "Folgezettel-Index")}
        # PB のノート（番号に印を付けて取り込む）
        src = root / "scan_b1.jpg"
        src.write_bytes(b"x")
        moved, errors = pp.move_images(root, root, [(src, "PB-1")])
        check(not errors and moved[0][0] == "PB-1" and (root / "PB-1.jpg").is_file(), f"PB の画像とノート: {moved}")
        pp.regen(root, do_sync=False)
        t = titles(root)
        for name in ("Paper-Zettelkasten-Index-PA", "Paper-Zettelkasten-Index-PB", "Index-write-PA", "Index-write-PB",
                     "Folgezettel-Index-PA", "Folgezettel-Index-PB", "folgezettel-Index-PA-1", "folgezettel-Index-PB-1"):
            check(name in t, f"{name} がある")
        check("Index-write" not in t and "Folgezettel-Index" not in t and "folgezettel-Index-1" not in t, "印なしの名前は残らない")
        # 改名は同じファイル（作り直さない）
        check(titles(root)["Index-write-PA"][0].path == a_ids["Index-write"], "PA の Index-write は同じノートの改名")
        tops = [n for n in t.get("Paper-Zettelkasten-Index", []) if not n.group]
        check(len(tops) == 1, "頂点のノートは 1 つ（題は印なしのまま）")
        links = block_links(tops[0].path, "BranchGroup:")
        check(len(links) == 2 and "Paper-Zettelkasten-Index-PA" in links[0] and "Paper-Zettelkasten-Index-PB" in links[1], f"頂点の BranchGroup: は PA・PB のグループ: {links}")
        pa_group = titles(root)["Paper-Zettelkasten-Index-PA"][0].path.read_text(encoding="utf-8")
        check("[Index-write-PA](" in pa_group and "[Folgezettel-Index-PA](" in pa_group, "PA のグループの中に Index-write-PA・Folgezettel-Index-PA")
        # PB のノートが無くなったら、1 つに戻る
        for n in titles(root)["PB-1"]:
            n.path.unlink()
        (root / "PB-1.jpg").unlink()
        for k in list(titles(root)):
            if k.endswith("-PB") or "-PB-" in k:
                for n in titles(root)[k]:
                    n.path.unlink()
        pp.regen(root, do_sync=False)
        t = titles(root)
        check("Index-write" in t and "Folgezettel-Index" in t and "Paper-Zettelkasten-Index" in t and "Index-write-PA" not in t, "1 つに戻ったら元の名前に戻る")


def test_keywords_per_prefix() -> None:
    print("印ごとの Index-write のキーワードは、その印のグループに出る")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        pp.create_paper_index(root)
        pp.move_images(root, root, _add_images(root, ["1", "2"]))
        src = root / "scan_b1.jpg"
        src.write_bytes(b"x")
        src2 = root / "scan_b2.jpg"
        src2.write_bytes(b"x")
        pp.move_images(root, root, [(src, "PB-1"), (src2, "PB-2")])
        pp.regen(root, do_sync=False)
        pa_iw = titles(root)["Index-write-PA"][0].path
        pb_iw = titles(root)["Index-write-PB"][0].path
        for path, line in ((pa_iw, "バナナ: 1,2\n"), (pb_iw, "リンゴ: 1,2\n")):
            txt = path.read_text(encoding="utf-8")
            path.write_text(txt.rstrip("\n") + "\n" + line, encoding="utf-8")
        pp.regen(root, do_sync=False)
        pa_g = titles(root)["Paper-Zettelkasten-Index-PA"][0].path.read_text(encoding="utf-8")
        pb_g = titles(root)["Paper-Zettelkasten-Index-PB"][0].path.read_text(encoding="utf-8")
        check("[バナナ](" in pa_g and "[リンゴ](" not in pa_g, "PA のグループにバナナ（リンゴは出ない）")
        check("[リンゴ](" in pb_g and "[バナナ](" not in pb_g, "PB のグループにリンゴ（バナナは出ない）")
        banana = pp.find_group(root, "バナナ", titles(root)["Paper-Zettelkasten-Index-PA"][0].path)
        btxt = banana.read_text(encoding="utf-8") if banana else ""
        check(banana is not None and titles(root)["PA-1"][0].path.name in btxt and titles(root)["PB-1"][0].path.name not in btxt, "バナナのグループは PA のノートだけ")


def test_legacy_titles_are_adopted() -> None:
    print("旧い題（印なし）は regen が PA- 付きに直す（画像のファイル名は変えない）")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        pp.create_paper_index(root)
        for fid in ("1", "1a"):
            (root / f"{fid}.jpg").write_bytes(b"x")
            (root / f"2610010000{'01' if fid == '1' else '02'}.md").write_text(
                f"---\ntime: 2026-10-01 00:00:00\ntitle: {fid}\nsource: scan\n---\n\n# {fid}\n\n![]({fid}.jpg)\n", encoding="utf-8")
        pp.regen(root, do_sync=False)
        t = titles(root)
        check("PA-1" in t and "PA-1a" in t and "1" not in t, f"題が PA- 付きに直る: {sorted(t)}")
        check((root / "1.jpg").is_file() and not (root / "PA-1.jpg").exists(), "画像のファイル名は変えない")
        check("![](1.jpg)" in t["PA-1"][0].path.read_text(encoding="utf-8"), "本文の画像参照も残る")
        check(pp.scan_folgezettel_notes(root).keys() == {"PA-1", "PA-1a"}, "旧い画像名でも紙のノートと分かる")
        before = {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}
        pp.regen(root, do_sync=False)
        check(before == {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}, "もう一度 regen しても変わらない")


def test_default_prefix_setting() -> None:
    print("設定 paperIdPrefix を PB にすると、これから取り込むものは PB- 付き（既存の PA は PA のまま）")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        pp.create_paper_index(root)
        pp.move_images(root, root, _add_images(root, ["1"]))
        (root / ".gnosis").mkdir(exist_ok=True)
        (root / ".gnosis" / "settings.json").write_text(json.dumps({"paperIdPrefix": "PB"}), encoding="utf-8")
        src = root / "scan_x.jpg"
        src.write_bytes(b"x")
        moved, errors = pp.move_images(root, root, [(src, "1")])
        check(not errors and moved[0][0] == "PB-1" and (root / "PB-1.jpg").is_file(), f"PB- 付きで取り込まれる: {moved}")
        check((root / "PA-1.jpg").is_file(), "既存の PA の画像はそのまま")
        pp.regen(root, do_sync=False)
        check({"Paper-Zettelkasten-Index-PA", "Paper-Zettelkasten-Index-PB"} <= set(titles(root)), "印が 2 つになったので改名・分割される")


def test_numbers_follow_each_notes_prefix() -> None:
    print("Folgezettel の番号は、ノートごとの印（PA-1 / PB-1）。自動の索引は PA-0 / PB-0")
    import note_format_v2 as nf
    import folgezettel as fz
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        pp.create_paper_index(root)
        pp.move_images(root, root, _add_images(root, ["1"]))
        src = root / "scan_b.jpg"
        src.write_bytes(b"x")
        pp.move_images(root, root, [(src, "PB-1")])
        pp.regen(root, do_sync=False)
        nf.simple_sync(root)
        vals = {n.title: fz.value(n.path.read_text(encoding="utf-8")) for n in pp.load_notes(root)}
        check(vals.get("PA-1") == "PA-1" and vals.get("PB-1") == "PB-1", f"番号は題と同じ印: {vals.get('PA-1')} {vals.get('PB-1')}")
        check(vals.get("Index-write-PA") == "PA-0" and vals.get("Index-write-PB") == "PB-0", f"自動の索引は印ごとの 0: {vals.get('Index-write-PA')} {vals.get('Index-write-PB')}")
        check(vals.get("folgezettel-Index-PB-1") == "PB-0", f"番号専用ノートも: {vals.get('folgezettel-Index-PB-1')}")


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        jy.set_reader(base.fake_reader)
        try:
            t()
        finally:
            jy.reset_reader()
    print()
    if base._FAILED:
        print(f"{len(base._FAILED)} FAILED")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
