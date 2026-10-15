#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
if ! RELATED_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= timeout 90 vim -u NONE -i NONE --cmd "set runtimepath^=$REPO" -N -es -S "$REPO/test/related_check.vim" >"$WORK/out" 2>&1; then
  cat "$WORK/out" "$WORK/errors" 2>/dev/null
  exit 1
fi
[ -f "$WORK/errors" ] || { echo "Vim did not finish"; exit 1; }
python3 "$REPO/python/note_format_v2.py" update "$WORK/vault" >/dev/null
cp -R "$WORK/vault" "$WORK/before"
python3 "$REPO/python/note_format_v2.py" update "$WORK/vault" >/dev/null
python3 - "$WORK" <<'PY'
import sys
from pathlib import Path
w = Path(sys.argv[1])
for p in (w / 'vault').glob('*.md'):
    assert p.read_bytes() == (w / 'before' / p.name).read_bytes(), p
for a, b in [('a', 'b'), ('a', 'c'), ('e', 'f'), ('f', 'g')]:
    for src, dst in [(a,b), (b,a)]:
        lines = (w / 'vault' / f'{src}.md').read_text().splitlines()
        rel = lines[lines.index('Related:')+1:]
        rel = rel[:next((i for i,l in enumerate(rel) if l.endswith(':')), len(rel))]
        assert sum(f']({dst}.md)' in l for l in rel) == 1, (src,dst,rel)
print('related OK (Vim assertions; sync twice, mutual links and no duplicates)')
PY
