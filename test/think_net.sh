#!/bin/sh
# :GnosisThink / :GnosisThinkCheck: 雛形を作って開く・構造検査・ふつうのノートには出さない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/think.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntitle: ふつう\n---\n\n# ふつう\n' > "$D/v/plain.md"
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/think_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
printf '%s\n' 'think OK'
