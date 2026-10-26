#!/bin/sh
# run.sh の python3 / sh の試験を、同時に何本も流す（各試験に専用の Gnosis ホームを渡す）。
# 使い方: test/run_parallel.sh [同時の本数（既定 8）]   run.sh の前半（API 一覧など）は run.sh のほうで確かめる
JOBS=${1:-8}
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
export GNOSIS_LANG=${GNOSIS_LANG:-ja}
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export REPO
LOG=$(mktemp -d "$TMPDIR/par.XXXXXX")
export LOG
grep -E '^(python3|sh) "\$REPO/' "$REPO/test/run.sh" | grep -v 'link_pick_pty\|xvfb' > "$LOG/list"
one() {
  cmd=$1
  name=$(echo "$cmd" | sed 's#.*/##; s#".*##' | tr -c 'A-Za-z0-9_.\n' '_')
  H=$(mktemp -d "$TMPDIR/home.XXXXXX")
  start=$(date +%s)
  if (GNOSIS_HOME=$H; export GNOSIS_HOME; . "$REPO/test/noclip.sh"; eval "$cmd") >"$LOG/$name.out" 2>&1; then r=OK; else r=NG; fi
  echo "$r $(( $(date +%s) - start ))s $name" >> "$LOG/result"
  rm -rf "$H"
}
export -f one 2>/dev/null || true
while IFS= read -r line; do
  printf '%s\n' "$line"
done < "$LOG/list" | xargs -P "$JOBS" -I{} bash -c '
  one() {
    cmd=$1
    name=$(echo "$cmd" | sed "s#.*/##; s#\".*##" | tr -c "A-Za-z0-9_.\n" "_")
    H=$(mktemp -d "$TMPDIR/home.XXXXXX")
    start=$(date +%s)
    if (GNOSIS_HOME=$H; export GNOSIS_HOME; . "$REPO/test/noclip.sh"; eval "$cmd") >"$LOG/$name.out" 2>&1; then r=OK; else r=NG; fi
    echo "$r $(( $(date +%s) - start ))s $name" >> "$LOG/result"
    rm -rf "$H"
  }
  one "$1"' _ {}
echo "合計 $(wc -l < "$LOG/result") 本 / NG $(grep -c '^NG' "$LOG/result") 本（結果: $LOG/result）"
grep '^NG' "$LOG/result" || true
echo "--- 遅い順"; sort -t' ' -k2 -n -r "$LOG/result" | sort -k2 -rn | head -5
[ "$(grep -c '^NG' "$LOG/result")" = 0 ]
