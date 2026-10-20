#!/bin/sh
# 前回セッションの復元(:GnosisRestore・自動復元)と、とりあえず書く(:GnosisQuick)を実 Vim から。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/rs.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
for n in a b c d; do printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: %s\n---\n\n# %s\n\n1\n2\n3\n4\n5\n6\n7\n8\n' $n $n > "$D/v/$n.md"; done
run() { REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" "$@" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }; }
run -S "$REPO/test/restore_check1.vim"
[ -f "$D/v/.state/session.json" ] || { echo "NG: セッションが保存されていない" >&2; exit 1; }
rm "$D/v/a.md"                                  # 復元までの間に消えたノートは飛ばす
run -S "$REPO/test/restore_check2.vim"
run -S "$REPO/test/restore_check3.vim"           # 自動復元(引数なし)
run "$D/v/d.md" -S "$REPO/test/restore_check4.vim"   # ファイルを指定して起動したら自動復元しない
run -S "$REPO/test/quick_check.vim"
printf '%s\n' 'restore OK'
