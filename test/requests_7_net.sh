#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"   # 本物のクリップボードを読まない・書かない
D=$(mktemp -d "${TMPDIR:-/tmp}/gnosis7.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
note() { printf -- '---\ntitle: %s\n%b---\n\n# %s\n\n%b\n' "$2" "$3" "$2" "$4" > "$D/v/$1.md"; }
note a A '' '本文A'
note b B '' '本文B'
note g G 'attribute: group\n' '[aaa](a.md)'
note h H 'attribute: group\n' ''
note x X '' '[A](a.md)'
note z Z '' '[B](b.md)'
if ! REPO="$REPO" D="$D" HOME="$D/home" GNOSIS_HOME="$D/gh" WAYLAND_DISPLAY= DISPLAY= timeout 90 vim -u NONE -i NONE -N -es -V1"$D/log" -S "$REPO/test/requests_7_check.vim" >"$D/out" 2>&1; then
    cat "$D/errors" "$D/out" "$D/log" 2>/dev/null
    exit 1
fi
cat "$D/errors"
echo 'requests_7 OK'
