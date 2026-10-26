#!/bin/sh
# run.sh の python3 / sh の試験を、同時に何本も流す（各試験に専用の Gnosis ホームを渡す）。
# 使い方: test/run_parallel.sh [同時の本数（既定 12）]。遅い試験を先に始める（全体の時間は一番遅い 1 本で決まるため）   run.sh の前半（API 一覧など）は run.sh のほうで確かめる
JOBS=${1:-12}
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
export GNOSIS_LANG=${GNOSIS_LANG:-ja}
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export REPO
LOG=$(mktemp -d "$TMPDIR/par.XXXXXX")
export LOG
grep -E '^(python3|sh) "\$REPO/' "$REPO/test/run.sh" | grep -v 'xvfb' > "$LOG/list.raw"
# 遅い試験を先頭に（keys_pty は 4 分近くかかる。mview_net は 1.5 分）
# 4 分近くかかる unittest の試験は、テスト 1 つずつに分けて同時に流す（全体の時間は一番遅い 1 本で決まるため）
split() {
  f="$REPO/test/$1"
  awk -v f="$1" '/^class /{split($2,a,"[(:]"); cls=a[1]} /^    def test_/{split($2,b,"("); print "python3 \"$REPO/test/" f "\" " cls "." b[1]}' "$f"
}
grep -v 'keys_pty_check\|theme_pty_check' "$LOG/list.raw" > "$LOG/list.raw2"
{ split keys_pty_check.py; split theme_pty_check.py; } >> "$LOG/list.raw2"
mv "$LOG/list.raw2" "$LOG/list.raw"
grep -E 'keys_pty_check|mview_net|theme_pty_check|imgview_pty|session_real|link_ops_net|install_net|bootstrap_net|install_update_net' "$LOG/list.raw" > "$LOG/list"
grep -vE 'keys_pty_check|mview_net|theme_pty_check|imgview_pty|session_real|link_ops_net|install_net|bootstrap_net|install_update_net' "$LOG/list.raw" >> "$LOG/list"
one() {
  cmd=$1
  name=$(echo "$cmd" | sed 's#.*/test/##; s#"##g' | tr -c 'A-Za-z0-9_.\n' '_')
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
    name=$(echo "$cmd" | sed "s#.*/test/##; s#\"##g" | tr -c "A-Za-z0-9_.\n" "_")
    H=$(mktemp -d "$TMPDIR/home.XXXXXX")
    start=$(date +%s)
    if (GNOSIS_HOME=$H; export GNOSIS_HOME; . "$REPO/test/noclip.sh"; eval "$cmd") >"$LOG/$name.out" 2>&1; then r=OK; else r=NG; fi
    echo "$r $(( $(date +%s) - start ))s $name" >> "$LOG/result"
    [ "$r" = NG ] && printf "%s\t%s\n" "$name" "$cmd" >> "$LOG/ng.list"
    rm -rf "$H"
  }
  one "$1"' _ {}
# 重くて時々落ちる試験があるので、落ちたものは 1 本ずつ流し直して、それでも落ちるものだけを失敗にする
if [ -s "$LOG/ng.list" ]; then
  echo "落ちた $(wc -l < "$LOG/ng.list") 本を 1 本ずつ流し直す…"
  : > "$LOG/result.retry"
  while IFS="$(printf '\t')" read -r name cmd; do
    H=$(mktemp -d "$TMPDIR/home.XXXXXX")
    if (GNOSIS_HOME=$H; export GNOSIS_HOME; . "$REPO/test/noclip.sh"; eval "$cmd") >"$LOG/$name.retry.out" 2>&1; then echo "OK(流し直しで通った) 0s $name" >> "$LOG/result.retry"; else echo "NG 0s $name" >> "$LOG/result.retry"; fi
    rm -rf "$H"
  done < "$LOG/ng.list"
  grep -v '^NG' "$LOG/result" > "$LOG/result.new"; cat "$LOG/result.retry" >> "$LOG/result.new"; mv "$LOG/result.new" "$LOG/result"
fi
# 変更前の main でも落ちる既知の失敗（test/known_ng.txt。fzf の試験）は、失敗に数えず別に出す
grep '^NG' "$LOG/result" | grep -v -F -f "$REPO/test/known_ng.txt" > "$LOG/ng.real" || true
grep '^NG' "$LOG/result" | grep -F -f "$REPO/test/known_ng.txt" > "$LOG/ng.known" || true
echo "合計 $(wc -l < "$LOG/result") 本 / 失敗 $(wc -l < "$LOG/ng.real") 本 / 既知の失敗 $(wc -l < "$LOG/ng.known") 本（結果: $LOG/result）"
cat "$LOG/ng.real"; sed 's/^NG/既知/' "$LOG/ng.known"
echo "--- 遅い順"; sort -t' ' -k2 -n -r "$LOG/result" | sort -k2 -rn | head -5
[ ! -s "$LOG/ng.real" ]
