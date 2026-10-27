#!/bin/sh
# zg（ノートが、グループの中でどう表示されているかを変える）の回帰網。一時フォルダだけを使う。
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"
D=$(mktemp -d "${TMPDIR:-$HOME/gnosis-work/test}/gnm.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- "---\ntime: 2026-01-01 00:00:00\n---\n\n# ノートA\n" > "$D/v/a.md"
printf -- "---\ntime: 2026-01-01 00:00:00\n---\n\n# 独り\n" > "$D/v/lone.md"
printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: Gグループ\nattribute: group\n---\n\n# Gグループ\n\n[ノートA](a.md)\n[別名](a.md)\n" > "$D/v/g.md"
printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: Hグループ\nattribute: group\n---\n\n# Hグループ\n\n[ノートA](a.md)\n" > "$D/v/h.md"
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" GNOSIS_LANG=ja \
  timeout 120 vim -u NONE -N -es -S "$REPO/test/group_name_check.vim" </dev/null 2>"$D/err" || true
if [ ! -s "$D/out.txt" ]; then echo "NG: group_name の結果が無い" >&2; cat "$D/err" >&2; exit 1; fi
fail() { echo "NG: $1" >&2; cat "$D/out.txt" >&2; exit 1; }
grep -q "^h \['\[ひとつ目\](a.md)'\]" "$D/out.txt" || fail "表示名が 1 つのグループで変わらない"
grep -q "^g .*\[ノートA\](a.md).*\[改名\](a.md)\|^g .*\[改名\](a.md).*\[ノートA\](a.md)" "$D/out.txt" || fail "表示名が複数のグループで 2 番目を変えられない"
grep -q "^pick \['\[選んだ\](a.md)'\]" "$D/out.txt" || fail "グループを選んで変えられない"
grep -q "^lone 2" "$D/out.txt" || fail "グループに入っていないノートで何かが変わった"
echo "group_name OK (zg: 表示名が 1 つ・複数・グループを選ぶ・入っていないノート)"
