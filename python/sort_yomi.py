#!/usr/bin/env python3
"""Index のリンクを表示名のよみ順に並べる CLI（Gnosis 用）。

使い方::

    sort_yomi.py sort --base DIR        # stdin の行をソートして stdout へ
    sort_yomi.py sort --base DIR --keyword-lines
                                        # 紙PKM の Index-write のキーワード行も並べる
    sort_yomi.py guess NAME             # NAME のよみを表示
    sort_yomi.py get  --note PATH --name NAME
    sort_yomi.py list --note PATH       # yomi の表示名を登録順に一覧
    sort_yomi.py set  --note PATH --name NAME [--reading READING]
                                        # READING 省略時は推測。空文字で削除
    sort_yomi.py readings --base DIR    # stdin のリンク行ごとに「登録済み(1/0)<TAB>よみ」
    sort_yomi.py setmany                # stdin の「ノート<TAB>表示名<TAB>よみ」を全部登録
    sort_yomi.py heads --base DIR       # stdin のノート全体に、頭文字の見出し（あ など）を付け直して stdout へ
                                        # （本文のリンクが 30 本未満なら見出しを外すだけ）

ソートはリンク行だけを対象にし、リンクでない行は位置ごと動かさない。
`sort` は未登録の表示名のよみを pykakasi で `yomi:` に書き込む（`--dry-run` で抑止）。
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gnosis_i18n import tr  # noqa: E402
import japanese_yomi as jy  # noqa: E402


def _warn_if_missing() -> None:
    if not jy.pykakasi_installed():
        print(
            tr("Gnosis: pykakasi 未導入のため Unicode 順で代用します（pip install --user pykakasi）",
               "Gnosis: pykakasi is not installed; using Unicode order (pip install --user pykakasi)"),
            file=sys.stderr,
        )


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="sort_yomi.py")
    sub = ap.add_subparsers(dest="mode", required=True)

    p_sort = sub.add_parser("sort", help="stdin の行をよみ順にソート")
    p_sort.add_argument("--base", default=".", help="リンク解決の基準ディレクトリ")
    p_sort.add_argument(
        "--dry-run", action="store_true", help="未登録のよみを yomi: に書き込まない"
    )
    p_sort.add_argument(
        "--keyword-lines",
        action="store_true",
        help="紙PKM の Index-write のキーワード行（バナナ(ばなな): 1,2）も並べる",
    )
    p_sort.add_argument(
        "--report-file", default=None, help="yomi: に追加した件数を書き出すファイル"
    )

    p_guess = sub.add_parser("guess", help="名前のよみを表示")
    p_guess.add_argument("name")

    p_get = sub.add_parser("get", help="ノートの yomi を表示")
    p_get.add_argument("--note", required=True)
    p_get.add_argument("--name", required=True)

    p_list = sub.add_parser("list", help="ノートの yomi の表示名を一覧")
    p_list.add_argument("--note", required=True)

    p_set = sub.add_parser("set", help="ノートに yomi を登録/削除")
    p_set.add_argument("--note", required=True)
    p_set.add_argument("--name", required=True)
    p_set.add_argument("--reading", default=None, help="省略時は推測。空文字で削除")

    p_readings = sub.add_parser("readings", help="リンク行ごとの登録済みのよみ（無ければ推測）")
    p_readings.add_argument("--base", default=".")
    sub.add_parser("setmany", help="ノート・表示名・よみ（TSV）を stdin から全部登録")
    p_heads = sub.add_parser("heads", help="頭文字の見出し（あ など）を付け直す")
    p_heads.add_argument("--base", default=".")
    p_heads.add_argument("--min", type=int, default=jy.KANA_HEAD_MIN)

    args = ap.parse_args(argv)

    if args.mode == "readings":
        for line in sys.stdin.read().split("\n"):
            if not line.strip():
                continue
            disp = jy.display_name(line)
            note = jy.resolve_note(args.base, jy.link_target(line))
            got = jy.get_yomi(note, disp) if note is not None and note.is_file() else ""
            print(f"1\t{got}" if got else f"0\t{jy.reading_for(disp)}")
        return 0

    if args.mode == "heads":
        lines = sys.stdin.read().split("\n")
        if lines and lines[-1] == "":
            lines.pop()
        out = jy.kana_heads(lines, args.base, args.min)
        if out:
            sys.stdout.write("\n".join(out) + "\n")
        return 0

    if args.mode == "setmany":
        n = 0
        for line in sys.stdin.read().split("\n"):
            f = line.split("\t")
            if len(f) != 3 or not f[0] or not f[1]:
                continue
            if jy.set_yomi(f[0], f[1], f[2].strip()):
                n += 1
        print(n)
        return 0

    if args.mode == "sort":
        data = sys.stdin.read()
        lines = data.split("\n")
        if lines and lines[-1] == "":
            lines.pop()
        _warn_if_missing()
        extra_key_fn = None
        if args.keyword_lines:
            import paper_pkm as pp  # 同ディレクトリ。キーワード行のよみ規則を共有

            def extra_key_fn(line: str):
                reading = pp.keyword_reading(line)
                return jy.reading_key(reading) if reading else None

        added = 0
        if not args.dry_run:
            added = jy.persist_readings(lines, args.base)
        if args.report_file:
            Path(args.report_file).write_text(f"{added}\n", encoding="utf-8")
        out = jy.sort_lines(lines, args.base, extra_key_fn=extra_key_fn)
        if out:
            sys.stdout.write("\n".join(out) + "\n")
        return 0

    if args.mode == "guess":
        _warn_if_missing()
        print(jy.reading_for(args.name))
        return 0

    if args.mode == "get":
        print(jy.get_yomi(args.note, args.name))
        return 0

    if args.mode == "list":
        for name in jy.list_yomi_names(args.note):
            print(name)
        return 0

    if args.mode == "set":
        reading = args.reading
        if reading is None:
            if not jy.has_pykakasi():
                _warn_if_missing()
                return 1
            reading = jy.reading_for(args.name)
        changed = jy.set_yomi(args.note, args.name, reading)
        if not changed:
            print(tr("Gnosis: 変更なし", "Gnosis: no change"))
        elif reading:
            print(tr(f"Gnosis: よみを登録 [{args.name}] → {reading}", f"Gnosis: reading set [{args.name}] → {reading}"))
        else:
            print(tr(f"Gnosis: よみを削除 [{args.name}]", f"Gnosis: reading removed [{args.name}]"))
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
