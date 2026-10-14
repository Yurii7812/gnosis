#!/bin/sh
# 複数ウィンドウで vault を同時に使う（暗号化 vault のロック管理・異常終了した登録の掃除・同時編集の上書き防止）の回帰網。
# gocryptfs の代わりに偽の mountpoint / fusermount3 を PATH の先頭に置く。一時フォルダ（既定 ~/Desktop/test）だけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
OTHER_PID=
cleanup() {
  [ -n "$OTHER_PID" ] && kill "$OTHER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/home" "$WORK/stub-bin" "$WORK/stub" "$WORK/gh"
cat > "$WORK/stub-bin/mountpoint" <<'SH'
#!/bin/sh
[ "$1" = "-q" ] && shift
grep -qxF -- "$1" "$STUB_DIR/mounted" 2>/dev/null
SH
cat > "$WORK/stub-bin/fusermount3" <<'SH'
#!/bin/sh
for a; do last=$a; done
echo "$@" >> "$STUB_DIR/fusermount.log"
grep -vxF -- "$last" "$STUB_DIR/mounted" > "$STUB_DIR/mounted.new" 2>/dev/null
mv "$STUB_DIR/mounted.new" "$STUB_DIR/mounted"
exit 0
SH
chmod +x "$WORK/stub-bin/mountpoint" "$WORK/stub-bin/fusermount3"
# 「別のウィンドウ」の代わりに、生きているだけのプロセス（この試験が起動した PID だけを後で止める）
sleep 300 &
OTHER_PID=$!
SESSION_WORK="$WORK" STUB_DIR="$WORK/stub" OTHER_PID="$OTHER_PID" PATH="$WORK/stub-bin:$PATH" \
  HOME="$WORK/home" GNOSIS_HOME="$WORK/gh" WAYLAND_DISPLAY= DISPLAY= \
  timeout 120 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/session_check.vim" </dev/null >"$WORK/out.txt" 2>&1 || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: session の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" >&2; exit 1
fi
if grep -q '^NG' "$WORK/result.txt"; then
  grep -v '^OK' "$WORK/result.txt" >&2; echo "NG: session" >&2; exit 1
fi
[ -n "$SESSION_VERBOSE" ] && cat "$WORK/result.txt"
echo "session OK ($(grep -c '^OK' "$WORK/result.txt") 項目)"
