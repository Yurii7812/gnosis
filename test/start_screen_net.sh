#!/bin/sh
# Vim の起動画面の回帰網（pty が要るので script + fifo で起動する）。一時フォルダだけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if ! command -v script >/dev/null 2>&1 || ! command -v mkfifo >/dev/null 2>&1; then
  echo "skip: script / mkfifo が無いため起動画面の確認を省略"; exit 0
fi
WORK=$(mktemp -d)
HOLDER=
trap '[ -n "$HOLDER" ] && kill "$HOLDER" 2>/dev/null; rm -rf "$WORK"' EXIT
V="$WORK/ノート 保管庫"
mkdir -p "$V/.gnosis" "$WORK/home" "$WORK/gh"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n' > "$V/index.md"
printf '{"version":1,"language":"en","appearance":"dark","fontSize":16,"window":{"maximized":true,"width":1200,"height":860},"theme":{"kind":"builtin"},"customThemes":{}}\n' > "$V/.gnosis/settings.json"
printf '{"version":1,"last":"%s","vaults":[{"path":"%s","name":"保管庫"}]}\n' "$V" "$V" > "$WORK/gh/vaults.json"
FIFO="$WORK/fifo"
mkfifo "$FIFO"
(sleep 16 > "$FIFO" 2>/dev/null) &
HOLDER=$!
START_WORK="$WORK" START_VAULT="$V" HOME="$WORK/home" GNOSIS_HOME="$WORK/gh" COLORTERM=truecolor WAYLAND_DISPLAY= DISPLAY= \
  timeout 25 script -qec "stty rows 60 cols 120; vim -u '$REPO/vimrc_gnosis' -N -S '$REPO/test/start_screen_check.vim'" /dev/null < "$FIFO" >/dev/null 2>&1 || true
if [ ! -s "$WORK/result.txt" ]; then echo "NG: 起動画面の結果が無い" >&2; exit 1; fi
if grep -aq "^NG" "$WORK/result.txt"; then grep -av "^OK" "$WORK/result.txt" >&2; echo "NG: start_screen" >&2; exit 1; fi
[ -n "$START_VERBOSE" ] && cat "$WORK/result.txt"
echo "start_screen OK ($(grep -c '^OK' "$WORK/result.txt") 項目)"
