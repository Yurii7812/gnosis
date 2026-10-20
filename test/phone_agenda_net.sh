#!/bin/sh
# :GnosisPushAgenda / :GnosisPullDone を実 Vim から(偽の adb でスマホのアプリの files/ を模す)。
# 送った予定がスマホ側に届き、スマホで「完了」を押した記録が、ノートの [x] に反映される。反映後はスマホ側の記録が消える。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/ph.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/phone" "$D/bin" "$D/home" "$D/gh"
cat > "$D/bin/adb" <<SH
#!/bin/sh
# adb exec-in|exec-out run-as PKG CMD files/NAME [files/NAME2]
shift 3
cmd=\$1; shift
rel() { echo "$D/phone/\$(basename "\$1")"; }
case "\$cmd" in
  tee) cat > "\$(rel "\$1")" ;;
  mv) [ -f "\$(rel "\$1")" ] && mv "\$(rel "\$1")" "\$(rel "\$2")" || exit 1 ;;
  cat) [ -f "\$(rel "\$1")" ] && cat "\$(rel "\$1")" || exit 1 ;;
  rm) shift; rm -f "\$(rel "\$1")" ;;
esac
SH
chmod +x "$D/bin/adb"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 家\n---\n\n# 家\n\n- [ ] ゴミ出し 📅 2026-10-21\n- [ ] 電球 📅 2026-10-19\n- [ ] 来月 📅 2099-01-01\n' > "$D/v/a.md"
KEY=$(printf 'a.md\0ゴミ出し' | sha1sum | cut -c1-10)
REPO="$REPO" D="$D" KEY="$KEY" PATH="$D/bin:$PATH" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/phone_agenda_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
grep -q '^- \[x\] ゴミ出し 📅 2026-10-21 ✅ ' "$D/v/a.md" || { echo "NG: スマホの完了がノートに反映されていない" >&2; exit 1; }
grep -q '^- \[ \] 電球 ' "$D/v/a.md" || { echo "NG: ほかのタスクが変わった" >&2; exit 1; }
[ ! -e "$D/phone/agenda-done.tsv" ] && [ ! -e "$D/phone/agenda-done.processing" ] || { echo "NG: スマホ側の完了の記録が残っている" >&2; exit 1; }
head -1 "$D/phone/agenda.tsv" | grep -q '^# gnosis-agenda v1$' || { echo "NG: 送った予定の形が違う" >&2; exit 1; }
printf '%s\n' 'phone OK'
