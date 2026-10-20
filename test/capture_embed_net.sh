#!/bin/sh
# \M と「まとめるトピック」「時系列記録」: 再取り込みで増えない・書き直しは同じ行へ・PC の文章は残る・同じ行は競合。
set -eu
export TZ=Asia/Tokyo  # 取り込む時刻（HH:MM）がタイムゾーンで変わるため固定
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/capture-embed.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh" "$D/pack/images"
D="$D" python3 - <<'PY'
import os, json
from pathlib import Path
pack = Path(os.environ['D']) / 'pack/capture.json'
mk = lambda i, ts, topic, text: dict(id=i, created=ts, topic=topic, images=[], parent=None, contexts=[], text=text)
entries = [mk('261019100000', 1792371600000, 'アイデア', 'ひとつめのアイデア'),
           mk('261019110000', 1792375200000, 'アイデア', 'ふたつめ\n詳しく'),
           mk('261019120000', 1792378800000, '夢', '空を飛ぶ夢')]
modes = {'アイデア': {'single': True, 'stamp': True}, '夢': {'record': True}}
pack.write_text(json.dumps(dict(format='gnosis-capture', entries=entries, topicModes=modes), ensure_ascii=False))
PY
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/capture_embed_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
printf '%s\n' 'capture_embed OK'
