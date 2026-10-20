#!/bin/sh
# 編集の補助(計算・ブロックID・取り込み・テンプレート・プレビュー・複数編集・折りたたみ・集中・コピー履歴・補完)を実 Vim から。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/ed.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v/テンプレート" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 資料\n---\n\n# 資料\n\n導入の文。\n\n## 栽培\n\n水やりは控えめに。\n\n要点の段落。 ^key\n' > "$D/v/src.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 本体\n---\n\n# 本体\n\n計算 {{= 2 * 3 }} と\n12 / 4 =\n1 / 0 =\n\n{{include: src.md#栽培}}\n\nハーブ ハーブ ハーブ と [資料](src.md) の話\n\n水やりの段落\n' > "$D/v/main.md"
printf -- '# {{title}} {{date}}\n\n- 参加者: {{cursor}}\n' > "$D/v/テンプレート/会議.md"
( cd "$D/v" && find . -name '*.md' ! -name main.md | sort | xargs md5sum > "$D/before.md5" )
cp "$D/v/main.md" "$D/main.orig"
cp "$D/v/src.md" "$D/src.orig"
run() { REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/$1" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }; }
run edit_check1.vim
run edit_check2.vim
# 元からあったノートのうち、変わってよいのは main.md(計算・複数編集)と src.md(ID を付けた)だけ。他は 1 バイトも変わらない
grep -v 'src.md' "$D/before.md5" > "$D/before_other.md5"
( cd "$D/v" && md5sum -c --quiet "$D/before_other.md5" ) || { echo "NG: 想定外のノートが変わった" >&2; exit 1; }
# src.md は ID を付けた 1 行以外は同じ
grep -c '\^[0-9a-f]\{6\}$' "$D/v/src.md" | grep -q '^1$' || { echo "NG: src.md に付いた ID が 1 つではない" >&2; exit 1; }
sed 's/ \^[0-9a-f]\{6\}$//' "$D/v/src.md" | diff - "$D/src.orig" > /dev/null || { echo "NG: src.md が ID の追記以外で変わった" >&2; exit 1; }
# main.md は計算の結果だけが変わる(複数編集は u で戻してある)
diff "$D/main.orig" "$D/v/main.md" | grep '^[<>]' | sed 's/^[<>] //' | grep -vq '=>\|^12 / 4 =\|^計算 {{= 2 \* 3' && { echo "NG: main.md が計算以外で変わった" >&2; exit 1; }
printf '%s\n' 'edit OK'
