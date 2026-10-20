#!/usr/bin/env python3
"""expand_v2 の自己完結テスト（pytest 非依存）。

現行のノート形式（`### Parent` / `Related:` / `### BackLink`。子 = 本文リンク）と
現役エンジン `simple_sync` で動かす。

    python3 test_expand_v2.py
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import expand_v2 as ex
import note_format_v2 as v2

_FAILED: list[str] = []


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        _FAILED.append(msg)


UP_MARK = v2.UP_MARK
RELATED_MARK = v2.RELATED_MARK
DOWN_MARK = v2.DOWN_MARK


def note(path: Path, title: str, body: str = "", parent: str = "",
         related: str = "", back: str = "", attr: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    txt = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n"
    if attr:
        txt += f"attribute: {attr}\n"
    txt += "---\n\n# " + title + "\n\n"
    if body:
        txt += body.strip("\n") + "\n\n"
    txt += f"{UP_MARK}\n"
    if parent:
        txt += parent.strip("\n") + "\n"
    if related:
        txt += f"{RELATED_MARK}\n" + related.strip("\n") + "\n"
    txt += f"{DOWN_MARK}\n"
    if back:
        txt += back.strip("\n") + "\n"
    path.write_text(txt, encoding="utf-8")


def _fixture(root: Path) -> None:
    """G(グループ) の子が A。A の本文は B。D が本文で A に言及。A と R は Related。"""
    note(root / "G.md", "G", body="[A](A.md)", attr="group")
    note(root / "A.md", "A", body="Aの本文。参照: [B](B.md)", related="[R](R.md)")
    note(root / "B.md", "B")
    note(root / "D.md", "D", body="Dの本文。言及: [A](A.md)")
    note(root / "R.md", "R", related="[A](A.md)")
    v2.simple_sync(root)


def _dir_of(root: Path, by_name, notes, ids, id_to_path):
    def dir_of(nid: str):
        p = id_to_path[nid]
        return ex._directions(p, notes[p], root, by_name, ids)
    return dir_of


def test_directions_parent_child_backlink_related() -> None:
    print("directions: 現行形式の 親(Parent)/子(本文)/文中(BackLink+Related)")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        a_p = (root / "A.md").resolve()
        d_a = ex._directions(a_p, notes[a_p], root, by_name, ids)
        check(d_a["parent"] == {ids[(root / "G.md").resolve()]}, "A の親は ### Parent の G")
        check(d_a["child"] == {ids[(root / "B.md").resolve()]}, "A の子は本文リンクの B")
        check(d_a["backlink"] == {ids[(root / "D.md").resolve()]},
              "A の文中（### BackLink）は D だけ（Related を混ぜない）")
        check(d_a["related"] == {ids[(root / "R.md").resolve()]},
              "A の関連（Related:）は R（独立した方向）")


def test_simple_mode_depth1() -> None:
    print("simple: 深さ1で親・子・文中すべてを平等に1階層集める")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]
        order, _po = ex.collect_simple(start_id, _dir_of(root, by_name, notes, ids, id_to_path), 1)
        titles = {notes[id_to_path[i]]["title"] for i in order}
        check(titles == {"A", "G", "B", "D", "R"}, "深さ1で親G・子B・文中D・関連Rが全部入る")


def test_simple_mode_depth0_only_start() -> None:
    print("simple: 深さ0なら起点だけ")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]
        order, _po = ex.collect_simple(
            start_id, _dir_of(root, by_name, notes, ids, id_to_path), 0)
        check(order == [start_id], "深さ0は起点ノートのみ")


def _ctx(root: Path):
    """(dir_of, ids, notes, id_to_path) を作る。"""
    by_name, notes, ids, id_to_path = ex._build_index(root)
    return _dir_of(root, by_name, notes, ids, id_to_path), ids, notes, id_to_path


def _titles(order, notes, id_to_path) -> set[str]:
    return {notes[id_to_path[i]]["title"] for i in order}


def _detailed(root: Path, start: str, body=0, context=0, group=0, br=0, diary=True) -> set[str]:
    dir_of, ids, notes, id_to_path = _ctx(root)
    holder = {"is_diary": lambda nid: ex.is_diary_title(notes[id_to_path[nid]]["title"])}
    order, _po = ex.collect_detailed(
        ids[(root / start).resolve()], dir_of, body, context, group, br,
        skip_backlink=None if diary else holder["is_diary"])
    assert len(order) == len(set(order)), "重複なし"
    return _titles(order, notes, id_to_path)


def test_detailed_body_depth_follows_only_body_links() -> None:
    print("detailed: 文中リンクの深さ 3 → 文中リンクだけを 3 段階辿る（Context / BackLink は数えない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "A.md", "A", body="[B1](B1.md)")
        note(root / "B1.md", "B1", body="[B2](B2.md)", parent="[P](P.md)")
        note(root / "B2.md", "B2", body="[B3](B3.md)")
        note(root / "B3.md", "B3", body="[B4](B4.md)")
        note(root / "B4.md", "B4")
        note(root / "P.md", "P")
        note(root / "X.md", "X", body="言及: [B1](B1.md)")
        v2.simple_sync(root)
        check(_detailed(root, "A.md", body=3) == {"A", "B1", "B2", "B3"},
              "深さ 3 は A→B1→B2→B3（B4 は 4 段階目、Context の P・BackLink の X は辿らない）")
        check(_detailed(root, "A.md", body=1) == {"A", "B1"}, "深さ 1 は B1 まで")
        check(_detailed(root, "A.md", body=0) == {"A"}, "深さ 0 は文中リンクを辿らない（起点だけ）")


def test_detailed_context_first_step_then_all_kinds() -> None:
    print("detailed: Context の深さ 2 → Context に進み、その先で全種類を 1 段階（Context だけ 2 回ではない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "A.md", "A", parent="[C](C.md)")
        # C: 子 CB（本文）・Context CC・Related R
        note(root / "C.md", "C", body="[CB](CB.md)", parent="[CC](CC.md)", related="[R](R.md)")
        note(root / "CB.md", "CB", body="[CBB](CBB.md)")
        note(root / "CBB.md", "CBB")
        note(root / "CC.md", "CC", parent="[CCC](CCC.md)")
        note(root / "CCC.md", "CCC")
        note(root / "R.md", "R", related="[C](C.md)")
        v2.simple_sync(root)
        check(_detailed(root, "A.md", context=1) == {"A", "C"}, "深さ 1 は Context の辺だけ（C）")
        check(_detailed(root, "A.md", context=2) == {"A", "C", "CB", "CC", "R"},
              "深さ 2 は C の先で全種類（子 CB・Context CC・関連 R）を 1 段階")
        check(_detailed(root, "A.md", context=3) == {"A", "C", "CB", "CC", "R", "CBB", "CCC"},
              "深さ 3 は全種類の探索をさらに 1 段階（CBB・CCC）")
        check(_detailed(root, "A.md", context=0) == {"A"}, "深さ 0 は Context を辿らない")


def test_detailed_group_first_step_then_all_kinds() -> None:
    print("detailed: Group の深さも同じ考え方（最初は Group の辺、その先は全種類）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "G.md", "G", body="[A](A.md)\n[A2](A2.md)", attr="group")
        note(root / "A.md", "A", body="[X](X.md)")
        note(root / "A2.md", "A2")
        note(root / "X.md", "X")
        v2.simple_sync(root)
        check(_detailed(root, "A.md", group=1) == {"A", "G"}, "深さ 1 は Group の G だけ")
        check(_detailed(root, "A.md", group=2) == {"A", "G", "A2"},
              "深さ 2 は G の先で全種類（G の子 A2）。A 自身の子 X は Group の先ではないので入らない")
        check(_detailed(root, "A.md", group=0) == {"A"}, "深さ 0 は Group を辿らない")


def test_detailed_backlink_related_shared_depth() -> None:
    print("detailed: BackLink / Related は共通の深さ（最初は両方、その先は全種類）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "A.md", "A", related="[R](R.md)")
        note(root / "R.md", "R", related="[A](A.md)", body="[RB](RB.md)")
        note(root / "RB.md", "RB")
        note(root / "D.md", "D", body="言及: [A](A.md)", parent="[DP](DP.md)")
        note(root / "DP.md", "DP")
        v2.simple_sync(root)
        check(_detailed(root, "A.md", br=1) == {"A", "R", "D"}, "深さ 1 は BackLink の D と Related の R の両方")
        check(_detailed(root, "A.md", br=2) == {"A", "R", "D", "RB", "DP"},
              "深さ 2 は D・R の先で全種類（R の子 RB・D の Context DP）")
        check(_detailed(root, "A.md", br=0) == {"A"}, "深さ 0 は BackLink / Related を辿らない")


def test_detailed_anchors_include_body_reached_notes() -> None:
    print("detailed: Context 等の探索の起点は、現在のノートと文中リンクで届いたノート")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "A.md", "A", body="[B1](B1.md)", parent="[PA](PA.md)")
        note(root / "B1.md", "B1", body="[B2](B2.md)", parent="[PB1](PB1.md)")
        note(root / "B2.md", "B2", parent="[PB2](PB2.md)")
        for n in ("PA", "PB1", "PB2"):
            note(root / f"{n}.md", n)
        v2.simple_sync(root)
        check(_detailed(root, "A.md", body=1, context=1) == {"A", "B1", "PA", "PB1"},
              "文中 1・Context 1: 起点 A と B1 のそれぞれの Context（PA・PB1）。B2 の PB2 は入らない")
        check(_detailed(root, "A.md", body=2, context=1) == {"A", "B1", "B2", "PA", "PB1", "PB2"},
              "文中 2・Context 1: B2 の Context も入る")
        check(_detailed(root, "A.md", body=0, context=1) == {"A", "PA"}, "文中 0 なら起点 A の Context だけ")


def test_detailed_dedup_and_cycles() -> None:
    print("detailed: 複数経路・循環でも重複せず、止まる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # 循環 A <-> B。ひし形 A→M1→T、A→M2→T。T は Context に A を持つ。
        note(root / "A.md", "A", body="[B](B.md)\n[M1](M1.md)\n[M2](M2.md)")
        note(root / "B.md", "B", body="[A](A.md)")
        note(root / "M1.md", "M1", body="[T](T.md)")
        note(root / "M2.md", "M2", body="[T](T.md)")
        note(root / "T.md", "T", parent="[A](A.md)", body="[A](A.md)")
        v2.simple_sync(root)
        got = _detailed(root, "A.md", body=10, context=10, group=10, br=10)
        check(got == {"A", "B", "M1", "M2", "T"}, f"循環があっても有限で、全部 1 回ずつ: {got}")
        dir_of, ids, notes, id_to_path = _ctx(root)
        order, _po = ex.collect_detailed(ids[(root / "A.md").resolve()], dir_of, 10, 10, 10, 10)
        check(len(order) == len(set(order)) == 5, "T は複数経路から届いても 1 回だけ")
        # 経路の順で深さの数え方が変わらない: M1 側の T は深さ 2、BackLink 側の T は深さ 1
        check(_detailed(root, "A.md", br=1) >= {"A", "T"}, "最短の深さで見つける（BackLink 1 段階で T が入る）")


def test_detailed_diary_flag_only_affects_backlink_edges() -> None:
    print("detailed: Diary の t/f は BackLink の辺だけに効く（他の辺で届く日記は除外しない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "A.md", "A", body="[Y](Y.md)", related="[Z](Z.md)")
        note(root / "D.md", "D", body="言及: [A](A.md)")
        note(root / "X.md", "2026-10-12-MO-日記", body="言及: [A](A.md)")
        note(root / "Y.md", "2026-10-11-SU-別の日記")
        note(root / "Z.md", "2026-10-10-SA-関連の日記", related="[A](A.md)")
        v2.simple_sync(root)
        t = _detailed(root, "A.md", br=1, diary=True)
        check({"D", "2026-10-12-MO-日記", "2026-10-10-SA-関連の日記"} <= t, f"t: BackLink の日記も入る: {t}")
        f = _detailed(root, "A.md", br=1, diary=False)
        check("D" in f and "2026-10-12-MO-日記" not in f, f"f: BackLink の日記 X だけ除外、D は入る: {f}")
        check("2026-10-10-SA-関連の日記" in f, "f でも Related で届く日記は除外しない")
        fb = _detailed(root, "A.md", body=1, diary=False)
        check("2026-10-11-SU-別の日記" in fb, "f でも文中リンクで届く日記は除外しない")


def test_relation_links_shown_even_for_terminal_nodes() -> None:
    print("render: 展開されなかったノート（終端）でも、そのノートの関係リンクは表示する")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # Index は子（本文リンク）に 日記・Gnosis を持つが、この展開では
        # 深さの都合で Index 自体は含まれても、その子は展開されない。
        note(root / "index.md", "Index",
             body="[日記](diary.md)\n[Gnosis](pkm.md)\n[A](A.md)")
        note(root / "diary.md", "日記", parent="[Index](index.md)")
        note(root / "pkm.md", "Gnosis", parent="[Index](index.md)")
        note(root / "A.md", "A", parent="[Index](index.md)")
        v2.simple_sync(root)

        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_detailed(sid, dir_of, 0, 0, 1, 0))
        text = out_path.read_text(encoding="utf-8")
        check("## Index" in text, "Index 自体は展開結果に含まれる（終端として）")
        check("## 日記" not in text and "## Gnosis" not in text,
              "Index の子（日記・Gnosis）はこの深さでは展開されない")
        check("[日記](" in text and "[Gnosis](" in text,
              "それでも Index の関係リンクとして 日記・Gnosis へのリンクは表示される")
        check("- 子（本文）: [日記](" in text, "関係リンクは現行セクション名（子（本文））で出る")


def test_relation_links_show_all_sections() -> None:
    print("render: 関係リンクは 親/関連/子（本文）/バックリンク を区別して表示する")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        text = out_path.read_text(encoding="utf-8")
        check("- 親: [G:A](" in text, "親セクションが出る")
        check("- 関連: [R](" in text, "関連セクションが出る（ノートに混ざらない）")
        check("- 子（本文）: [B](" in text, "子（本文）セクションが出る")
        check("- バックリンク: [D](" in text, "バックリンクセクションが出る")


def test_toc_is_nested_by_discovery_path() -> None:
    print("目次: 発見経路に沿ってインデントされる（フラットな一覧ではない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        text = out_path.read_text(encoding="utf-8")
        toc = text.split("## 目次")[1].split("---")[0]
        toc_lines = [ln for ln in toc.split("\n") if ln.strip().startswith("-")]
        check(toc_lines[0].startswith("- ["), "起点はインデント0")
        check(all(ln.startswith("  - [") for ln in toc_lines[1:]),
              "起点から直接発見されたものは1段インデントされる")


def test_render_strips_own_h1_and_frontmatter() -> None:
    print("render: front matter・見張りコメントは出さず、自分の H1 も二重にしない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        text = out_path.read_text(encoding="utf-8")
        check("attribute:" not in text, "front matter は含まれない")
        check(UP_MARK not in text and DOWN_MARK not in text and RELATED_MARK not in text,
              "見張り（### Parent / Related: / ### BackLink）は含まれない")
        lines = text.split("\n")
        check("# A" not in lines, "本文側の重複 H1 (# A) は除去される（## A だけが残る）")
        check("## A" in text and "## G" in text and "## B" in text and "## D" in text,
              "各ノートが見出しとして出る")
        check("Aの本文。参照:" in text, "本文の中身は保持される")


def test_run_creates_file_under_trash_dir() -> None:
    print("run: 出力先は ROOT/.trash/T_<timestamp>.md")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 0))
        check(out_path.parent == root / ex.TRASH_DIR, ".trash ディレクトリの下に作られる")
        check(out_path.name.startswith("T_") and out_path.suffix == ".md",
              "ファイル名は T_ + タイムスタンプ")


def test_trash_output_excluded_from_sync_scan() -> None:
    print("sync: .trash の展開出力と旧 _tmp 配下は vault スキャンから除外される")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        check(out_path.exists(), "展開ファイル自体は作られている")
        # 2026-10-06 以前の出力（_tmp）が残っていても sync に見えないこと。
        (root / v2.EXPAND_TMP_DIR).mkdir(exist_ok=True)
        (root / v2.EXPAND_TMP_DIR / "old.md").write_text("# old\n", encoding="utf-8")
        found = [p for p in v2._iter_md(root)
                 if ex.TRASH_DIR in p.relative_to(root).parts
                 or v2.EXPAND_TMP_DIR in p.relative_to(root).parts]
        check(found == [], "_iter_md は .trash / _tmp 配下を無視する")


def _snapshot(root: Path) -> dict:
    return {p.name: p.read_bytes() for p in root.glob("*.md")}


def test_presets_save_list_overwrite_delete_persist() -> None:
    print("presets: 保存・一覧・上書き確認・削除。保存済みは再読み込み（再起動）後も残る")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        before = _snapshot(root)
        a = ex.normalize_settings(3, 2, 1, 4, "t")
        b = ex.normalize_settings(0, 1, 0, 2, "f")
        check(ex.load_presets(root) == {}, "最初は空")
        check(ex.save_preset(root, "広く 日本語", a) == "saved", "新しい名前は保存される")
        check(ex.save_preset(root, "狭い", b) == "saved", "もう一つ保存")
        check(ex.save_preset(root, "広く 日本語", b) == "exists", "同じ名前は確認なしに上書きしない")
        check(ex.load_presets(root)["広く 日本語"] == a, "上書きしなかったので元の設定のまま")
        check(ex.save_preset(root, "広く 日本語", b, overwrite=True) == "overwritten", "確認したら上書きできる")
        check(ex.load_presets(root)["広く 日本語"] == b, "上書き後は新しい設定")
        ex.save_preset(root, "広く 日本語", a, overwrite=True)
        # 「再起動」= ファイルから読み直す（プロセス内の状態を持たない）
        again = ex.load_presets(root)
        check(set(again) == {"広く 日本語", "狭い"} and again["広く 日本語"] == a and again["狭い"] == b,
              "5 項目すべてが復元される（body/context/group/br/diary）")
        check(again["広く 日本語"] == {"body": 3, "context": 2, "group": 1, "br": 4, "diary": True}, "保存形式の中身")
        check(ex.delete_preset(root, "狭い") is True and "狭い" not in ex.load_presets(root), "削除すると一覧から消える")
        check(ex.delete_preset(root, "狭い") is False, "無い名前の削除は何もしない")
        check(set(ex.load_presets(root)) == {"広く 日本語"}, "再読み込み後も削除したものは復活しない")
        check(_snapshot(root) == before, "プリセットの操作でノートの中身は 1 バイトも変わらない")
        for bad in ("", "  ", "a\tb", "a\nb"):
            try:
                ex.save_preset(root, bad, a)
                check(False, f"不正な名前 {bad!r} は拒否される")
            except ValueError:
                check(True, f"不正な名前 {bad!r} は拒否される")


def test_settings_validation() -> None:
    print("settings: 深さは 0 以上の整数、diary は t/f")
    check(ex.normalize_settings("2", "0", "1", "3", "f")["diary"] is False, "f は False")
    check(ex.normalize_settings(1, 1, 1, 1, "T")["diary"] is True, "T は True")
    for args in ((-1, 0, 0, 0, "t"), (0, 0, 0, 0, "x"), ("a", 0, 0, 0, "t")):
        try:
            ex.normalize_settings(*args)
            check(False, f"不正な設定 {args} は拒否される")
        except ValueError:
            check(True, f"不正な設定 {args} は拒否される")


def test_cli_detailed_updates_prefs_but_not_presets() -> None:
    print("CLI: detailed は前回の設定だけ更新し、保存済みプリセットは自動では書き換えない")
    import contextlib
    import io
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        check(ex._load_prefs(root) is None, "初回は前回の設定なし")
        ex.save_preset(root, "固定", ex.normalize_settings(1, 1, 1, 1, "t"))
        preset_bytes = (root / ex._PRESETS_FILE).read_bytes()
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = ex.main(["expand_v2.py", "detailed", str(root), str(root / "A.md"), "2", "1", "0", "1", "f"])
        check(rc == 0 and Path(buf.getvalue().strip()).is_file(), "展開ファイルができる")
        check(ex._load_prefs(root) == {"body": 2, "context": 1, "group": 0, "br": 1, "diary": False},
              "前回の設定が新しい 5 項目で保存される")
        check((root / ex._PRESETS_FILE).read_bytes() == preset_bytes, "プリセットのファイルは変わらない")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            ex.main(["expand_v2.py", "presets_list", str(root)])
        check(buf.getvalue().strip() == "固定\t1 1 1 1 t", f"一覧は 名前<TAB>設定: {buf.getvalue()!r}")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            ex.main(["expand_v2.py", "preset_save", str(root), "固定", "0", "0", "0", "0", "f"])
        check(buf.getvalue().strip() == "exists" and ex.load_presets(root)["固定"]["body"] == 1,
              "CLI の保存も同じ名前は上書きしない（exists）")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            ex.main(["expand_v2.py", "preset_delete", str(root), "固定"])
        check(buf.getvalue().strip() == "deleted" and ex.load_presets(root) == {}, "CLI の削除")
        (root / ex._PREFS_FILE).write_text('{"child":1,"parent":1,"backlink":1,"related":0}', encoding="utf-8")
        check(ex._load_prefs(root) is None, "旧形式の前回設定は読まない（探索の意味が違うため）")


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
    print()
    if _FAILED:
        print(f"{len(_FAILED)} FAILED")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
