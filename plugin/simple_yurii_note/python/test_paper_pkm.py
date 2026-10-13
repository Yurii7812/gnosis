#!/usr/bin/env python3
"""paper_pkm の自己完結テスト（pytest 非依存）。

    python3 test_paper_pkm.py
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import japanese_yomi as jy  # noqa: E402
import paper_pkm as pp  # noqa: E402

_FAILED: list[str] = []

_YOMI = {"知識管理": "ちしきかんり", "日記": "にっき"}


def fake_reader(text: str) -> str:
    return _YOMI.get(text, text)


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        _FAILED.append(msg)


def _make_vault(root: Path) -> Path:
    (root / "index.md").write_text(
        "---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n",
        encoding="utf-8",
    )
    return root


def _add_images(root: Path, ids: list[str]) -> list[tuple[Path, str]]:
    out = []
    for fid in ids:
        src = root / f"scan_{fid}.jpg"
        src.write_bytes(b"x")
        out.append((src, fid))
    return out


def test_parse_keyword_line() -> None:
    print("parse_keyword_line: キーワード行の解析")
    e = pp.parse_keyword_line("バナナ: 1,1a10b,3")
    check(e == {"key": "バナナ", "display": "バナナ",
                "ids": ["1", "1a10b", "3"]}, "カンマ区切り")
    e = pp.parse_keyword_line("キーワード: 1 2a")
    check(e is not None and e["ids"] == ["1", "2a"], "空白区切り")
    check(pp.parse_keyword_line("オザーク(ドラマ): 2") is None,
          "括弧付きの行は廃止（紛らわしいため扱わない）")
    check(pp.parse_keyword_line("キーワード: フォルゲゼッテル") is None,
          "ID でない値は行として扱わない")
    check(pp.parse_keyword_line("ただの文章") is None, "普通の文は None")
    check(pp.parse_keyword_line("time: 2026-01-01 00:00:00") is None,
          "front matter の time 行は None（誤マッチ回帰）")
    check(pp.parse_keyword_line("title: Index-write") is None, "title 行は None")
    check(pp.parse_keyword_line("バナナ: 1A10B") is not None, "大文字は正規化して受ける")


def test_keyword_reading() -> None:
    print("keyword_reading: キーワード行のよみ")
    check(pp.keyword_reading("バナナ: 1,2") == "ばなな", "カタカナはひらがな化")
    check(pp.keyword_reading("知識管理: 3") == "ちしきかんり", "漢字のよみ")
    check(pp.keyword_reading("ただの文") is None, "キーワード行でなければ None")


def test_keyword_sort() -> None:
    print("keyword_sort_key: キーワード行のよみ順")
    entries = [
        pp.parse_keyword_line("バナナ: 1,2"),
        pp.parse_keyword_line("知識管理: 3"),
        pp.parse_keyword_line("オザーク: 4"),
    ]
    order = [e["key"] for e in sorted(entries, key=pp.keyword_sort_key)]
    check(order == ["オザーク", "知識管理", "バナナ"], "おざーく < ちしき < ばなな")


def test_id_helpers() -> None:
    print("ID ヘルパー")
    check(pp.parent_id("1a10b") == "1a10", "parent_id")
    check(pp.parent_id("3") is None, "数字だけは親なし")
    check(pp.next_sibling_id("1a") == "1b", "next_sibling_id 英字")
    check(pp.next_sibling_id("9") == "10", "next_sibling_id 数字")
    check(pp.child_id("1a") == "1a1", "child_id 英字")
    check(pp.child_id("1") == "1a", "child_id 数字")
    check(pp.normalize_id("１Ａ") == "1a", "全角の正規化")


def test_create_and_regen() -> None:
    print("create/regen: Index・グループ・Folgezettel-Index・スキャンノート")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        index_path = pp.create_paper_index(root)
        check(index_path.is_file(), "Paper-Zettelkasten-Index ができる")
        check((root / "Index-write.md").is_file(), "Index-write.md ができる")
        check((root / "Folgezettel-Index.md").is_file(), "Folgezettel-Index.md ができる")
        check(pp.find_paper_index(root) == index_path, "paper_index マーカーで見つかる")
        check(pp.create_paper_index(root) == index_path, "2回目は同じ Index を再利用")

        moved, errors = pp.move_images(
            root, root, _add_images(root, ["1", "1a", "2"])
        )
        check(len(moved) == 3 and not errors, "3枚を移動してノート作成")
        notes = {fid: p for fid, p in moved}
        check(notes["1"].name != notes["1a"].name, "ノートはタイムスタンプ名")

        (root / "Index-write.md").write_text(
            "---\ntime: 2026-01-01 00:00:00\ntitle: Index-write\n---\n\n"
            "# Index-write\n\n"
            "バナナ: 1,1a,2\n"
            "オザーク: 2\n",
            encoding="utf-8",
        )
        pp.regen(root)

        index_text = index_path.read_text(encoding="utf-8")
        check("[オザーク]" in index_text and "[バナナ]" in index_text,
              "Index にキーワードリンクが並ぶ")
        check(index_text.index("[オザーク]") < index_text.index("[バナナ]"),
              "Index もよみ順（オザーク < バナナ）")

        group = pp.find_group(root, "バナナ")
        check(group is not None, "複数IDはグループノートができる")
        if group:
            group_text = group.read_text(encoding="utf-8")
            check("attribute: group" in group_text, "グループ属性")
            check(group_text.count(f"]({notes['1'].name})") == 1
                  and f"[1a]({notes['1a'].name})" in group_text
                  and f"[2]({notes['2'].name})" in group_text,
                  "グループに各IDノートへのリンク")
        check(pp.find_group(root, "オザーク") is None,
              "単一IDはグループを作らない")
        check(f"[オザーク]({notes['2'].name})" in index_text,
              "単一IDは Index から直接リンク")

        folge_text = (root / "Folgezettel-Index.md").read_text(encoding="utf-8")
        check(folge_text.index("[1](folgezettel-Index-1.md#1)")
              < folge_text.index("[2](folgezettel-Index-2.md#2)"), "Folgezettel-Index は自然順")
        check("[1a](" not in folge_text, "Folgezettel-Index は最上位IDだけ（1a 等は出ない）")
        check("### Context" in folge_text and "[Paper-Zettelkasten-Index]" in folge_text,
              "Folgezettel-Index の Group は Paper-Zettelkasten-Index")
        dedicated = pp.folge_index_path(root, "1")
        check(dedicated.is_file(), "専用ノート folgezettel-Index-1 ができる")
        if dedicated.is_file():
            d_text = dedicated.read_text(encoding="utf-8")
            check("## [1](" in d_text and "## [1a](" in d_text, "専用ノートに ID 見出し（リンク）")
            check("folgezettel_index: 1" in d_text, "専用ノートの fm マーカー")
            check(d_text.index("## [1](") < d_text.index("## [1a]("), "専用ノートは folge 順")
            check("![](" in d_text, "専用ノートに画像")
            check("[Paper-Zettelkasten-Index]" in d_text
                  or "[Folgezettel-Index]" in d_text, "専用ノートの Parent")
        iw_text = (root / "Index-write.md").read_text(encoding="utf-8")
        check("### Context" in iw_text and "[Paper-Zettelkasten-Index]" in iw_text,
              "Index-write の Group は Paper-Zettelkasten-Index")
        check("PAPER:START" not in index_text and "PAPER:END" not in folge_text,
              "管理コメントは書かない")
        parent_index = (root / "index.md").read_text(encoding="utf-8")
        check("[Paper-Zettelkasten-Index]" in parent_index,
              "vault の index.md にリンクが足される")

        note1 = notes["1"].read_text(encoding="utf-8")
        check(f"[1a]({notes['1a'].name})" in note1, "親ノートの本文に子リンク")
        check("[folgezettel-Index-1](folgezettel-Index-1.md#1)" in note1,
              "根のノートの Parent は folgezettel-Index-1#1")
        note1a = notes["1a"].read_text(encoding="utf-8")
        check(f"[1]({notes['1'].name})" in note1a, "子ノートの Parent は親ID")

        # キーワードから外した ID のグループ Parent 行は掃除される
        (root / "Index-write.md").write_text(
            "---\ntime: 2026-01-01 00:00:00\ntitle: Index-write\n---\n\n"
            "# Index-write\n\nバナナ: 1,1a\nオザーク: 2\n",
            encoding="utf-8",
        )
        pp.regen(root)
        note2 = notes["2"].read_text(encoding="utf-8")
        check("バナナ" not in note2, "外した ID のグループ Parent 行が消える")


def test_topic_index() -> None:
    print("トピック別Index: 1-仏教 + 1-Index グループ")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        index_path = pp.create_paper_index(root)
        src_topic = root / "scan_1b.jpg"
        src_topic.write_bytes(b"x")
        moved, errors = pp.move_images(
            root, root, _add_images(root, ["1"]) + [(src_topic, "1", "仏教")]
        )
        check(len(moved) == 2 and not errors, "ID と トピック を移動してノート作成")
        notes = {fid: p for fid, p in moved}
        check(notes.get("1") is not None and notes.get("1-仏教") is not None,
              "通常IDとトピック表示名のノート")
        topic_text = notes["1-仏教"].read_text(encoding="utf-8")
        check("paper_topic: 1" in topic_text and "title: 1-仏教" in topic_text,
              "トピックノートの fm")
        pp.regen(root)
        gid = pp.find_id_index(root, "1")
        check(gid is not None, "1-Index グループができる")
        if gid:
            gid_text = gid.read_text(encoding="utf-8")
            check("title: 1-Index" in gid_text, "トピックIndex は 1-Index に改名")
            check(f"[1]({notes['1'].name})" in gid_text and "[1-仏教]" in gid_text,
                  "グループに ID ノートと トピック のリンク")
            check("attribute: group" in gid_text, "グループ属性")
            check("[Paper-Zettelkasten-Index]" in gid_text, "グループの Parent は Paper index")
        n1 = notes["1"].read_text(encoding="utf-8")
        check("[folgezettel-Index-1](folgezettel-Index-1.md#1)" in n1,
              "ID ノートの Parent は folgezettel-Index-1#1")
        d_text = pp.folge_index_path(root, "1").read_text(encoding="utf-8")
        check("[1-Index]" in d_text, "専用ノートにトピックIndexへのリンク")
        topic_text = notes["1-仏教"].read_text(encoding="utf-8")
        i_folge = topic_text.find("[folgezettel-Index-1]")
        i_gindex = topic_text.find("[1-Index]")
        # 並び: Context（普通のノート folgezettel-Index-1）の次に Group（グループ 1-Index）
        check(i_folge != -1 and i_gindex != -1 and i_folge < i_gindex and "### Group" in topic_text,
              "トピックノートは Context に folgezettel-Index-1、Group に 1-Index")
        folge_text = (root / "Folgezettel-Index.md").read_text(encoding="utf-8")
        check("[1-仏教]" not in folge_text, "Folgezettel-Index にトピック名は出ない")

        # 階層トピック: 仏教/四念処 → 1-四念処（tm: 1-仏教）
        src_n = root / "scan_1c.jpg"
        src_n.write_bytes(b"x")
        moved2, errors2 = pp.move_images(root, root, [(src_n, "1", "四念処", "1-仏教")])
        check(len(moved2) == 1 and not errors2, "階層トピックの作成")

        topic_child = next(p for p in pp.iter_md(root)
                           if "title: 1-四念処" in p.read_text(encoding="utf-8"))
        pp.regen(root)
        gid = pp.find_id_index(root, "1")
        check(gid is not None, "階層後も 1-Index あり")
        gid_text = gid.read_text(encoding="utf-8")
        i_buk = gid_text.find("[1-仏教]")
        i_sinen = gid_text.find("  [1-四念処]")
        check(i_buk != -1 and i_sinen > i_buk,
              "四念処は仏教の下にインデント")



    print("move_images: ID 重複の検出")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        pp.create_paper_index(root)
        moved, errors = pp.move_images(root, root, _add_images(root, ["1"]))
        check(len(moved) == 1 and not errors, "1枚目は成功")
        old_note = moved[0][1]
        moved, errors = pp.move_images(root, root, _add_images(root, ["1"]))
        check(len(moved) == 1 and not errors, "同じ ID は上書き（エラーなし）")
        trashed = list((root / ".trash").glob("*"))
        check(any(p.name.endswith(old_note.name) for p in trashed), "旧ノートは .trash 退避")
        moved, errors = pp.move_images(root, root, _add_images(root, ["1a"]) + _add_images(root, ["1a"]))
        check(len(moved) == 1 and len(errors) == 1, "同じバッチ内の重複もエラー")


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def test_index_has_fixed_file_name() -> None:
    print("index: 新規作成は常に Paper-Zettelkasten-Index.md（タイムスタンプ名を作らない）")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        path = pp.create_paper_index(root)
        check(path.name == "Paper-Zettelkasten-Index.md" and path.is_file(), f"固定名で作られる: {path.name}")
        check(pp.find_paper_index(root) == path, "find_paper_index は固定名を返す")
        text = path.read_text(encoding="utf-8")
        check("paper_index: true" in text and "title: Paper-Zettelkasten-Index" in text, "paper_index マーカーと題")
        before = sorted(p.name for p in root.glob("*.md"))
        pp.regen(root)
        pp.create_paper_index(root)
        check(sorted(p.name for p in root.glob("*.md")) == before, "regen / create を繰り返しても新しい Index は増えない")
        check(sum(1 for p in root.glob("*.md") if "paper_index: true" in p.read_text(encoding="utf-8")) == 1,
              "Index は 1 つだけ")
        parent = (root / "index.md").read_text(encoding="utf-8")
        check("(Paper-Zettelkasten-Index.md)" in parent, "index.md から固定名でリンクされる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n"
                                       "[ガイド](simple-yurii-note-guide.md)\n[問題](261012130347.md)\n", encoding="utf-8")
        for name in ("simple-yurii-note-guide.md", "261012130347.md"):  # 消えたファイルへのリンクは sync が掃除するので実在させる
            (root / name).write_text("---\ntitle: " + name + "\n---\n\n# x\n", encoding="utf-8")
        pp.create_paper_index(root)
        lines = (root / "index.md").read_text(encoding="utf-8").split("\n")
        at = lines.index("[Paper-Zettelkasten-Index](Paper-Zettelkasten-Index.md)")
        check(lines[at - 1] == "[問題](261012130347.md)", f"index.md には空行を挟まず、最後のリンクの直後に足す: {lines[at-2:at+1]}")
        before = (root / "index.md").read_text(encoding="utf-8")
        pp.create_paper_index(root)
        check((root / "index.md").read_text(encoding="utf-8") == before, "2 回目はリンクを足さない（冪等）")


def test_index_migrates_from_timestamp_name() -> None:
    print("index: 旧タイムスタンプ名の Index を固定名へ移行（内容・メタデータ保持、リンク更新）")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        old = root / "261001120000.md"
        _write(old, "---\ntime: 2026-10-01 12:00:00\ntitle: Paper-Zettelkasten-Index\npaper_index: true\nextra: 残す\n---\n"
                    "# Paper-Zettelkasten-Index\n\n[Index-write](Index-write.md)\n[Folgezettel-Index](Folgezettel-Index.md)\n\n"
                    "[バナナ](261001120001.md)\n")
        _write(root / "index.md", "---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n"
                                  "[Paper-Zettelkasten-Index](261001120000.md)\n")
        _write(root / "Index-write.md", "---\ntime: 2026-01-01 00:00:00\ntitle: Index-write\n---\n\n# Index-write\n\n"
                                         "### Parent\n[Paper-Zettelkasten-Index](261001120000.md)\n")
        _write(root / "sub" / "n.md", "---\ntitle: sub\n---\n\n# sub\n\n[戻る](../261001120000.md#見出し)と[外部](https://example.com/261001120000.md)\n")
        _write(root / "other.md", "---\ntitle: other\n---\n\n# other\n\n[別](261001120009.md)\n")
        old_text = old.read_text(encoding="utf-8")
        result = pp.migrate_paper_index(root)
        new = root / "Paper-Zettelkasten-Index.md"
        check(result == new and new.is_file() and not old.exists(), "改名された")
        check(new.read_text(encoding="utf-8") == old_text, "中身（キーワード・リンク・メタデータ）は 1 バイトも変わらない")
        check("(Paper-Zettelkasten-Index.md)" in (root / "index.md").read_text(encoding="utf-8")
              and "261001120000" not in (root / "index.md").read_text(encoding="utf-8"), "index.md のリンクが更新される")
        check("(Paper-Zettelkasten-Index.md)" in (root / "Index-write.md").read_text(encoding="utf-8"), "他のノートのリンクも更新される")
        sub = (root / "sub" / "n.md").read_text(encoding="utf-8")
        check("(../Paper-Zettelkasten-Index.md#見出し)" in sub, "サブフォルダの相対リンクと #見出し を保つ")
        check("https://example.com/261001120000.md" in sub, "外部 URL は書き換えない")
        check("261001120009.md" in (root / "other.md").read_text(encoding="utf-8"), "別のノートへのリンクは触らない")
        check(pp.find_paper_index(root) == new, "find_paper_index は固定名")
        check(pp.migrate_paper_index(root) == new, "移行済みなら何もしない（冪等）")
        pp.regen(root)
        check(not list(root.glob("2610*.md")) or all(p.name != "261001120000.md" for p in root.glob("*.md")),
              "regen で旧名が復活しない")


def test_index_migration_never_overwrites() -> None:
    print("index: 固定名のファイルが既にあるとき、上書き・データ消失をしない")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        old = root / "261001120000.md"
        _write(old, "---\ntime: 2026-10-01 12:00:00\ntitle: Paper-Zettelkasten-Index\npaper_index: true\n---\n# Paper-Zettelkasten-Index\n")
        other = root / "Paper-Zettelkasten-Index.md"
        _write(other, "---\ntitle: 別のノート\n---\n# 別のノート\n\n大事な内容\n")
        before_old = old.read_text(encoding="utf-8")
        before_other = other.read_text(encoding="utf-8")
        result = pp.migrate_paper_index(root)
        check(result == old, "固定名が別のノートなら移行せず旧 Index を使い続ける")
        check(other.read_text(encoding="utf-8") == before_other and old.read_text(encoding="utf-8") == before_old,
              "どちらのファイルも変わらない")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        _write(root / "Paper-Zettelkasten-Index.md", "---\ntitle: 別のノート\n---\n# 別のノート\n\n大事な内容\n")
        try:
            pp.create_paper_index(root)
            check(False, "別のノートが固定名を使っていたら create は止まる")
        except RuntimeError:
            check(True, "別のノートが固定名を使っていたら create は止まる（上書きしない）")
        check("大事な内容" in (root / "Paper-Zettelkasten-Index.md").read_text(encoding="utf-8"), "中身は残る")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        _write(root / "Paper-Zettelkasten-Index.md", "---\ntitle: Paper-Zettelkasten-Index\n---\n# Paper-Zettelkasten-Index\n\n手書き\n")
        idx = pp.create_paper_index(root)
        text = idx.read_text(encoding="utf-8")
        check(idx.name == "Paper-Zettelkasten-Index.md" and "paper_index: true" in text and "手書き" in text,
              "題が Index の固定名ファイルはマーカーだけ足して使う（中身は残る）")


def _diary_vault(root: Path) -> tuple[Path, Path]:
    root = _make_vault(root)
    idx = pp.create_paper_index(root)
    return root, idx


def test_diary_register_and_keyword() -> None:
    print("diary: 紙の日記を登録 → Index にキーワード「日記」→ 日付順の一覧")
    with tempfile.TemporaryDirectory() as d:
        root, idx = _diary_vault(Path(d))
        # デジタル日記のグループ（題「日記」）。紙の日記はこれと別のノートになる
        _write(root / "digital.md", "---\ntime: 2026-10-01 00:00:00\ntitle: 日記\nattribute: group\n---\n\n# 日記\n")
        digital_before = (root / "digital.md").read_bytes()

        def img(name: str) -> Path:
            p = root / name
            p.write_bytes(b"x")
            return p

        moved, errors = pp.register_diary_pages(
            root, root, [(img("a1.jpg"), "2026-10-07"), (img("a2.jpg"), "2026-10-07"), (img("b1.png"), "2026-09-30")])
        check(not errors and len(moved) == 2, f"2 日分（3 ページ）が登録される: {moved}")
        notes = pp.scan_diary_notes(root)
        check(set(notes) == {"2026-10-07", "2026-09-30"}, "日記が書かれた日付ごとに 1 ノート")
        n7 = notes["2026-10-07"].read_text(encoding="utf-8")
        check("paper_diary: 2026-10-07" in n7 and "title: 2026-10-07-WE" in n7, "日記の日付と題")
        check("![](paper-diary-20261007-1.jpg)" in n7 and "![](paper-diary-20261007-2.jpg)" in n7, "複数ページの画像が並ぶ")
        check((root / "paper-diary-20261007-1.jpg").is_file() and (root / "paper-diary-20260930-1.png").is_file(), "画像が dest へ移る")
        import re as _re
        t7 = _re.search(r"^time: (.+)$", n7, _re.M).group(1)
        from datetime import datetime as _dt
        check(t7.startswith(_dt.now().strftime("%Y-%m-%d")) and "paper_diary: 2026-10-07" in n7,
              f"time はスキャンした日時（今）で、日記の日付（paper_diary: 2026-10-07）とは別: {t7}")

        pp.regen(root)
        index_text = idx.read_text(encoding="utf-8")
        check(index_text.count("[日記](") == 1, f"Index にキーワード「日記」が 1 つだけある: {index_text}")
        group = pp.find_group(root, "日記")
        check(group is not None and group.name != "digital.md", "日記グループはデジタル日記のグループとは別のノート")
        gtext = group.read_text(encoding="utf-8")
        check("title: 紙の日記" in gtext and "attribute: group" in gtext, "題は「紙の日記」（デジタル日記の「日記」と区別）")
        check("[2026-09](" in gtext and "[2026-10](" in gtext and gtext.index("[2026-09](") < gtext.index("[2026-10](")
              and "2026-10-07-WE" not in gtext, "「日記」の直下には月グループが古い順に並ぶ（年が変わるまで年グループは作らない）")
        check(pp._find_note_by_fm(root, "paper_diary_year", "2026") is None, "同じ年だけなら年グループは作られない")
        fi = (root / "Folgezettel-Index.md").read_text(encoding="utf-8")
        check(fi.count(f"[diary]({group.name})") == 1, f"Folgezettel-Index に diary（日記一覧）が 1 つ並ぶ: {fi}")
        body_lines = gtext.split("---\n", 2)[2].rstrip("\n").split("\n")
        check(body_lines[0] == "# 紙の日記" and "" not in body_lines
              and body_lines[body_lines.index("### Context") - 1].startswith("[2026-"),
              f"自動で作る日記グループには空行を入れない（リンクの次に ### Context がそのまま続く）: {body_lines}")
        idx_lines = idx.read_text(encoding="utf-8").split("\n")
        at = idx_lines.index("[日記](" + group.name + ")")
        check(idx_lines[at + 1].startswith("### "), f"Index の「日記」と ### の間にも空行がない: {idx_lines[at:at+2]}")
        m10 = pp._find_note_by_fm(root, "paper_diary_month", "2026-10")
        mtext = m10.read_text(encoding="utf-8")
        check("title: 2026-10\n" in mtext and "attribute: group" in mtext and "[2026-10-07-WE](" in mtext, "月グループ（題 YYYY-MM）に日が並ぶ")
        check((root / "digital.md").read_bytes() == digital_before, "デジタル日記のグループ（題「日記」）は変わらない")
        link = f"({group.name})"
        check(link in index_text, "Index の「日記」は紙の日記グループを指す")

        # 再生成しても消えず、重複しない
        pp.regen(root)
        pp.regen(root)
        index_text2 = idx.read_text(encoding="utf-8")
        check(index_text2.count("[日記](") == 1 and link in index_text2, "regen を繰り返しても「日記」は 1 つのまま消えない")
        # 後から追加（別の日付、同じ日付の続きのページ）
        moved, errors = pp.register_diary_pages(root, root, [(img("c1.jpg"), "2026-10-01"), (img("a3.jpg"), "2026-10-07")])
        check(not errors, "追加登録")
        n7b = pp.scan_diary_notes(root)["2026-10-07"].read_text(encoding="utf-8")
        check("paper-diary-20261007-3.jpg" in n7b and n7b.count("![](") == 3, "同じ日付の続きのページは同じノートに足される（上書きしない）")
        pp.regen(root)
        gtext = group.read_text(encoding="utf-8")
        mtext = pp._find_note_by_fm(root, "paper_diary_month", "2026-10").read_text(encoding="utf-8")
        order = [mtext.index(x) for x in ("2026-10-01-TH", "2026-10-07-WE")]
        check(order == sorted(order) and mtext.count("2026-10-07-WE](") == 1, "追加後も月の中で日付順、重複しない")
        check(pp._find_note_by_fm(root, "paper_diary_year", "2026") is None, "追加しても同じ年なら年グループは作らない")
        # 年が変わったら: すべての年に年グループを作り、「日記」の直下は年グループになる
        moved, errors = pp.register_diary_pages(root, root, [(img("d1.jpg"), "2025-12-31")])
        pp.regen(root)
        y25 = pp._find_note_by_fm(root, "paper_diary_year", "2025")
        y26 = pp._find_note_by_fm(root, "paper_diary_year", "2026")
        check(y25 is not None and y26 is not None, "年をまたいだら、すべての年に年グループができる")
        t25 = y25.read_text(encoding="utf-8")
        t26 = y26.read_text(encoding="utf-8")
        check("title: 2025\n" in t25 and "[2025-12](" in t25 and "[2026-09](" in t26 and "[2026-10](" in t26, "年グループに月グループが並ぶ")
        gtext = group.read_text(encoding="utf-8")
        check("[2025](" in gtext and "[2026](" in gtext and "[2026-09](" not in gtext and gtext.index("[2025](") < gtext.index("[2026](")
              and gtext.count("[2025](") == 1, f"「日記」の直下は年グループ（古い順・重複なし）に替わる: {gtext}")
        check("[日記](" in idx.read_text(encoding="utf-8") and idx.read_text(encoding="utf-8").count("[日記](") == 1, "Index の「日記」は 1 つのまま")
        fi = (root / "Folgezettel-Index.md").read_text(encoding="utf-8")
        check(fi.count(f"[diary]({group.name})") == 1, "年をまたいだあとも Folgezettel-Index の diary は 1 つ（年グループへ辿れる）")


def test_diary_keyword_merges_with_index_write_entry() -> None:
    print("diary: Index-write に「日記」のキーワード行があれば重複させず、日記も同じグループに入る")
    with tempfile.TemporaryDirectory() as d:
        root, idx = _diary_vault(Path(d))
        moved, errors = pp.move_images(root, root, _add_images(root, ["1", "2"]))
        _write(root / "Index-write.md", "---\ntime: 2026-01-01 00:00:00\ntitle: Index-write\n---\n\n# Index-write\n\n日記: 1,2\nバナナ: 1\n")
        p = root / "p.jpg"
        p.write_bytes(b"x")
        pp.register_diary_pages(root, root, [(p, "2026-10-07")])
        pp.regen(root)
        pp.regen(root)
        text = idx.read_text(encoding="utf-8")
        check(text.count("[日記](") == 1, f"「日記」は 1 つだけ: {text}")
        group = pp.find_group(root, "日記")
        gtext = group.read_text(encoding="utf-8")
        check("[2026-10](" in gtext and gtext.count("(") >= 3, "Index-write の ID と紙の日記（月グループ）が同じグループに並ぶ")


def test_diary_errors_and_scan_unchanged() -> None:
    print("diary: 不正な日付はエラー。日記が無ければ「日記」キーワードは出ない。通常のスキャンはそのまま")
    with tempfile.TemporaryDirectory() as d:
        root, idx = _diary_vault(Path(d))
        p = root / "z.jpg"
        p.write_bytes(b"x")
        moved, errors = pp.register_diary_pages(root, root, [(p, "2026-13-40"), (p, "あした")])
        check(not moved and len(errors) == 2 and p.exists(), "不正な日付は登録されず、画像も動かさない")
        check(pp.normalize_diary_date("2026/9/3") == "2026-09-03" and pp.normalize_diary_date("２０２６-１０-０７") == "2026-10-07"
              and pp.normalize_diary_date("20261007") == "2026-10-07", "日付の入力ゆれを受ける")
        moved, errors = pp.move_images(root, root, _add_images(root, ["1", "2"]))
        pp.regen(root)
        check("[日記](" not in idx.read_text(encoding="utf-8"), "日記を登録していなければ「日記」は出ない")
        check("[diary](" not in (root / "Folgezettel-Index.md").read_text(encoding="utf-8"), "日記を登録していなければ Folgezettel-Index に diary は出ない")
        check(len(moved) == 2 and not errors and pp.scan_folgezettel_notes(root).keys() == {"1", "2"}, "通常の ID 登録は今までどおり")


def test_diary_weekday_is_computed() -> None:
    print("diary: 題は デジタル日記と同じ YYYY-MM-DD-曜日2文字（曜日は日付から自動計算）。旧い題は regen で直る")
    check(pp.weekday_en("2026-10-07") == "WE" and pp.weekday_en("2026-10-11") == "SU" and pp.weekday_en("2024-02-29") == "TH"
          and pp.weekday_en("2026-10-13") == "TU" and pp.weekday_en("2026-10-12") == "MO", "曜日の計算（MO..SU。うるう日も）")
    check(pp.diary_title("2026-10-13") == "2026-10-13-TU" and pp.diary_label("2026-10-05") == "2026-10-05-MO",
          "題は 2026-10-13-TU の形")
    with tempfile.TemporaryDirectory() as d:
        root, idx = _diary_vault(Path(d))
        old = root / "261001000000.md"
        _write(old, "---\ntime: 2026-10-01 00:00:00\ntitle: 2026-10-01(木) 紙の日記\npaper_diary: 2026-10-01\n---\n# 2026-10-01(木) 紙の日記\n\n![](paper-diary-20261001-1.jpg)\n")
        (root / "paper-diary-20261001-1.jpg").write_bytes(b"x")
        pp.regen(root)
        text = old.read_text(encoding="utf-8")
        check("title: 2026-10-01-TH\n" in text and "# 2026-10-01-TH\n" in text and "paper-diary-20261001-1.jpg" in text and "paper_diary: 2026-10-01" in text,
              "旧い題（曜日つきの紙の日記など）は YYYY-MM-DD-TH に直り、画像と日付はそのまま")
        month = pp._find_note_by_fm(root, "paper_diary_month", "2026-10").read_text(encoding="utf-8")
        check("[2026-10-01-TH](261001000000.md)" in month and "(木) 紙の日記](" not in month, "月グループの一覧のリンクも同じ題（曜日つきの旧題は残らない）")


def test_index_has_no_blank_lines_between_links() -> None:
    print("index: Paper-Zettelkasten-Index のリンクの並びに自動で空行を入れない（利用者の空行は消さない）")
    with tempfile.TemporaryDirectory() as d:
        root, idx = _diary_vault(Path(d))
        p = root / "p.jpg"
        p.write_bytes(b"x")
        pp.register_diary_pages(root, root, [(p, "2026-10-07")])
        pp.regen(root)
        lines = idx.read_text(encoding="utf-8").split("\n")
        at = lines.index("[Folgezettel-Index](Folgezettel-Index.md)")
        check(lines[at + 1].startswith("[日記]("), f"Folgezettel-Index の直後に「日記」が続く（空行なし）: {lines[at:at+3]}")
        check(not any(lines[i] == "" and lines[i - 1].startswith("[") and lines[i + 1].startswith("[")
                      for i in range(1, len(lines) - 1)), "リンクとリンクのあいだに空行がない")
        # 利用者が入れた空行は消さない（ノートの空行は自由。自動で作る部分が空行を足さないだけ）
        text = idx.read_text(encoding="utf-8").replace("[Folgezettel-Index](Folgezettel-Index.md)\n[日記](", "[Folgezettel-Index](Folgezettel-Index.md)\n\n\n[日記](")
        idx.write_text(text, encoding="utf-8")
        pp.regen(root)
        pp.regen(root)
        lines = idx.read_text(encoding="utf-8").split("\n")
        at = lines.index("[Folgezettel-Index](Folgezettel-Index.md)")
        check(lines[at + 1:at + 4] == ["", "", lines[at + 3]] and lines[at + 3].startswith("[日記]("),
              f"自分で入れた空行（2 つ）は regen しても消えない・増えない: {lines[at:at+5]}")


def test_user_blank_lines_survive_regen() -> None:
    print("regen: 利用者が入れた空行は、グループなどの生成ノートでも消えない・増えない")
    with tempfile.TemporaryDirectory() as d:
        root, idx = _diary_vault(Path(d))
        p = root / "p.jpg"
        p.write_bytes(b"x")
        pp.register_diary_pages(root, root, [(p, "2026-10-07"), (root / "q.jpg", "2026-10-08")] if False else [(p, "2026-10-07")])
        pp.regen(root)
        group = pp.find_group(root, "日記")
        month = pp._find_note_by_fm(root, "paper_diary_month", "2026-10")
        for note in (group, month):
            t = note.read_text(encoding="utf-8")
            t = t.replace("### Context", "\n\n### Context", 1)  # リンクと ### Context の間に自分で空行
            t = t.replace("\n[2026", "\n\n[2026", 1)            # 最初のリンクの前にも空行
            note.write_text(t, encoding="utf-8")
        before = {n: n.read_text(encoding="utf-8") for n in (group, month)}
        pp.regen(root)
        pp.regen(root)
        for note in (group, month):
            check(note.read_text(encoding="utf-8").split("---\n", 2)[2] == before[note].split("---\n", 2)[2],
                  f"{note.name}: 自分で入れた空行がそのまま残る")
        # 新しく自動で作る部分は空行を足さない
        p2 = root / "p2.jpg"
        p2.write_bytes(b"x")
        pp.register_diary_pages(root, root, [(p2, "2026-10-09")])
        pp.regen(root)
        m = pp._find_note_by_fm(root, "paper_diary_month", "2026-10").read_text(encoding="utf-8")
        check("[2026-10-09-FR](" in m, "後から足した日が一覧に入る")


def test_regen_without_index() -> None:
    print("regen: Paper-Zettelkasten-Index が無ければ False")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        check(pp.regen(root, do_sync=False) is False, "Index 無しで False")


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        jy.set_reader(fake_reader)
        try:
            t()
        finally:
            jy.reset_reader()
    print()
    if _FAILED:
        print(f"{len(_FAILED)} FAILED")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
