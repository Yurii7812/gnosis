#!/bin/sh
# \M と日記: 同じメモを何度取り込んでも日記の行は 1 つ・編集は同じ行へ・PC で書いた他の文章は残る・同じ行の競合は記録。
set -eu
export TZ=Asia/Tokyo  # 取り込む時刻（HH:MM）がタイムゾーンで変わるため固定
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/capture-diary.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh" "$D/pack/images"
D="$D" python3 - <<'PY'
import os, json
from pathlib import Path
pack = Path(os.environ['D']) / 'pack/capture.json'
mk = lambda i, ts, text: dict(id=i, created=ts, topic='日記', images=[], parent=None, contexts=[], text=text)
entries = [mk('261019100000', 1792371600000, '朝の記録'), mk('261019120000', 1792378800000, '昼の記録\n二行目')]
pack.write_text(json.dumps(dict(format='gnosis-capture', entries=entries), ensure_ascii=False))
PY
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/capture_diary_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
printf '%s\n' 'capture_diary OK'
