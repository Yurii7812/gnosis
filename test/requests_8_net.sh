#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"   # 本物のクリップボードを読まない・書かない
D=$(mktemp -d "${TMPDIR:-/tmp}/gnosis8.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v/sub" "$D/v/other" "$D/home" "$D/gh"
note() { printf -- '---\ntitle: %s\n%b---\n\n# %s\n\n%b\n' "$2" "$3" "$2" "$4" > "$D/v/$1.md"; }
note a A '' '本文A'
note orphan 未所属 '' '本文'
note parent 元の親 '' 'ChildBranch:\n[既存](existing.md)'
note existing 既存 '' 'ParentBranch:\n[元の親](parent.md)\n\n本文'
note modeoff 自動オフ '' '本文'
note joiner 外から追加 '' '本文'
note index Index 'attribute: group\n' '[A](a.md)'
note plain 通常グループ 'attribute: group\n' ''
note other/a 別A '' 'BranchGroup:\n[別B](../sub/b.md)\n\nChildBranch:\n[別B](../sub/b.md)'
note sub/b 別B 'attribute: group\n' 'ParentBranch:\n[別A](../other/a.md)\n\n'
if ! REPO="$REPO" D="$D" HOME="$D/home" GNOSIS_HOME="$D/gh" WAYLAND_DISPLAY= DISPLAY= timeout 90 vim -u NONE -i NONE -N -es -V1"$D/log" -S "$REPO/test/requests_8_check.vim" >"$D/out" 2>&1; then
  cat "$D/errors" "$D/out" "$D/log" 2>/dev/null
  exit 1
fi
python3 "$REPO/python/note_format_v2.py" update "$D/v" >/dev/null
cp -R "$D/v" "$D/before"
python3 "$REPO/python/note_format_v2.py" update "$D/v" >/dev/null
python3 - "$D" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
paths = [Path(p) for p in (root / 'created').read_text().splitlines()]
for p in (root/'v').rglob('*.md'):
    assert p.read_bytes() == (root/'before'/p.relative_to(root/'v')).read_bytes(), p
assert 'ParentBranch:\n[A](a.md)' in paths[0].read_text()
assert 'ParentBranch:\n[別A](../other/a.md)' in paths[-1].read_text()
for p in paths[1:-1]:
    assert 'ParentBranch:' not in p.read_text(), p
print('requests_8 OK (BranchGroup Enter / g / o / plain group / Index / relative paths / za parentless+existing / mode off / dirty origin / sync twice)')
PY
python3 "$REPO/python/branch_ops.py" check "$D/v" >/dev/null
