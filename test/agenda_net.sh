#!/bin/sh
# :GnosisAgenda（統合 Agenda）: 集める・期限で分ける・Enter で移動・x で完了（繰り返しは次の回）。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/agenda.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntitle: A\n---\n\n# A\n\n- [ ] 過去の提出 📅 2026-10-10\n- [ ] 毎週の掃除 📅 2026-10-20 🔁 weekly\n\n```\n- [ ] コード内\n```\n' > "$D/v/a.md"
printf -- '---\ntitle: B\n---\n\n# B\n\n- [ ] 期限なし\n' > "$D/v/b.md"
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/agenda_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
printf '%s\n' 'agenda OK'
