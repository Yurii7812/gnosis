#!/bin/sh
# Folgezettel ビュー・アウトライン窓の回帰網（実 Vim・ヘッドレス）。一時フォルダ（既定 ~/gnosis-work/test）だけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
LINES=40 COLUMNS=140 CM_WORK="$WORK" GNOSIS_HOME="$WORK/home" GNOSIS_LANG=ja WAYLAND_DISPLAY= DISPLAY= \
  timeout 150 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/conflict_merge_check.vim" </dev/null >"$WORK/out.txt" 2>"$WORK/err.txt" || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: conflict merge の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" "$WORK/err.txt" >&2; exit 1
fi
if grep -aq '^NG' "$WORK/result.txt"; then
  grep -av '^OK' "$WORK/result.txt" >&2
  echo "NG: conflict_merge" >&2; exit 1
fi
echo "conflict_merge OK (同期の書き換えと未保存の編集が別々の場所なら、警告せずに両方を取り込む)"
