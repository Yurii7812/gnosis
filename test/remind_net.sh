#!/bin/sh
# :GnosisReminders 系を実 Vim から。ノートは書き換えない。状態は .state/reminders.json だけ。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/rm.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-10-01 09:00:00\ntitle: A\n---\n\n# A\n\n- [ ] 薬を飲む ⏰ 2020-01-01 09:30\n- [ ] 先の予定 ⏰ 2999-01-01 09:00\n' > "$D/v/a.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/remind_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -path './.state/*' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: ノートが変わった" >&2; exit 1; }
[ -f "$D/v/.state/reminders.json" ] || { echo "NG: 状態ファイルが無い" >&2; exit 1; }
printf '%s\n' 'remind OK'
