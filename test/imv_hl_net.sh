#!/bin/sh
# 外部ビューア imv に渡す設定（gnosis#imgview#imv_config）: 利用者の設定を写して h / l を足す。一時 HOME だけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home/.config/imv" "$WORK/gn"
printf '[options]\noverlay = true\n[binds]\nc = exec echo hi\n' > "$WORK/home/.config/imv/config"
run() {
  HOME="$WORK/home" XDG_CONFIG_HOME= XDG_CACHE_HOME= GNOSIS_HOME="$WORK/gn" WAYLAND_DISPLAY= DISPLAY= \
    timeout 30 vim -u "$REPO/vimrc_gnosis" -N -es -c "$1" -c 'qa!' </dev/null >/dev/null 2>&1 || true
}
run "call writefile([gnosis#imgview#imv_config()], '$WORK/path1')"
C="$WORK/home/.cache/gnosis/imv.conf"
[ -f "$C" ] || { echo "NG: imv.conf が作られない" >&2; exit 1; }
grep -q '^overlay = true' "$C" || { echo "NG: 利用者の設定が写っていない" >&2; exit 1; }
[ "$(grep -c '^\[binds\]' "$C")" = 1 ] || { echo "NG: [binds] が 2 つできた" >&2; exit 1; }
grep -q '^h = prev' "$C" && grep -q '^l = next' "$C" || { echo "NG: h / l が足されていない" >&2; exit 1; }
grep -q 'exec echo hi' "$WORK/home/.config/imv/config" && ! grep -q 'h = prev' "$WORK/home/.config/imv/config" || { echo "NG: 利用者の設定ファイルが書き換わった" >&2; exit 1; }
rm -rf "$WORK/home/.cache"
run "let g:gnosis_image_viewer_hl = 0 | call writefile([gnosis#imgview#imv_config()], '$WORK/path2')"
[ ! -e "$WORK/home/.cache/gnosis/imv.conf" ] || { echo "NG: g:gnosis_image_viewer_hl=0 でも作られた" >&2; exit 1; }
rm -rf "$WORK/home/.config/imv"
run "call writefile([gnosis#imgview#imv_config()], '$WORK/path3')"
grep -q '^l = next' "$WORK/home/.cache/gnosis/imv.conf" || { echo "NG: 利用者の設定が無いときに作られない" >&2; exit 1; }
echo "imv_hl OK"
