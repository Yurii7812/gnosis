#!/bin/sh
# vault の登録簿・vault ごとの設定・旧環境からの移行・テーマ・ガイドの言語の回帰網。
# HOME と GNOSIS_HOME を一時フォルダ（既定 ~/Desktop/test の下。空白と日本語を含むパス）にして動かす。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
W="$WORK/作業 場所"
mkdir -p "$W/home"
VS_WORK="$W" HOME="$W/home" GNOSIS_HOME="$W/gnosis ホーム" WAYLAND_DISPLAY= DISPLAY= \
  timeout 60 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/vault_settings_check.vim" </dev/null >"$WORK/out.txt" 2>&1 || true
if [ ! -s "$W/result.txt" ]; then
  echo "NG: vault_settings の結果が無い" >&2; cat "$WORK/out.txt" >&2; exit 1
fi
if grep -q '^NG' "$W/result.txt"; then
  grep -v '^OK' "$W/result.txt" >&2; echo "NG: vault_settings" >&2; exit 1
fi
[ -n "$VS_VERBOSE" ] && cat "$W/result.txt"
echo "vault_settings OK ($(grep -c '^OK' "$W/result.txt") 項目)"
