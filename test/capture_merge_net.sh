#!/bin/sh
# \M の差分更新（仕様 §7.3）: 再実行で増えない・スマホの変更だけ同じノートへ・PC の追記は残る・同じ行の変更は競合として残す。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/capture-merge.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh" "$D/pack/images"
D="$D" python3 - <<'PY'
import os, json
from pathlib import Path
pack = Path(os.environ['D']) / 'pack/capture.json'
entry = dict(id='261019100000', created=1792371600000, topic='', images=[], parent=None, contexts=[],
             text='一行目\n二行目\n三行目')
pack.write_text(json.dumps(dict(format='gnosis-capture', entries=[entry]), ensure_ascii=False))
PY
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/capture_merge_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
printf '%s\n' 'capture_merge OK'
