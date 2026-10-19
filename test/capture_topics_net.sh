#!/bin/sh
# タイトル/本文・vault ごとの取り込み・欠損からの復旧・トピック移動・PC の編集の保全。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/capture-topics.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/other" "$D/home" "$D/gh" "$D/pack/images"
D="$D" python3 - <<'PY'
import os, json
from pathlib import Path
pack = Path(os.environ['D']) / 'pack/capture.json'
entry = dict(id='261019100000', created=1792371600000, topic='', images=[], parent=None, contexts=[],
             text='こんにちは今日はいい天気だと思ったけどそうでもないかもしれない\nところで最近はいい感じ。')
pack.write_text(json.dumps(dict(format='gnosis-capture', entries=[entry]), ensure_ascii=False))
PY
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/capture_topics_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
printf '%s\n' 'capture_topics OK'
