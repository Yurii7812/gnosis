#!/bin/sh
# 変えたファイルに関係する試験だけを同時に流す（全部は test/run_parallel.sh）。
# 使い方: test/related.sh [比較する元（既定 main）]   小さな直しはこれで足りる。大きな直し・共通部分の変更は run_parallel.sh
BASE=${1:-main}
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO" || exit 1
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}; mkdir -p "$TMPDIR"; export TMPDIR
export GNOSIS_LANG=${GNOSIS_LANG:-ja}
CH=$( (git diff --name-only "$BASE"; git diff --name-only; git ls-files -o --exclude-standard) 2>/dev/null | sort -u)
[ -n "$CH" ] || { echo "変更なし"; exit 0; }
PAT=""
add() { PAT="$PAT|$1"; }
echo "$CH" | grep -q '^autoload/gnosis/mview.vim\|^python/mandala_view.py\|^test/mview' && add 'mview'
echo "$CH" | grep -q '^plugin/gnosis_search.vim\|^autoload/gnosis_search.vim\|^python/note_search.py\|^python/test_note_search.py\|^test/search_modes_pty.py' && add 'link_pick|search_query|note_search|search_modes'
echo "$CH" | grep -q '^autoload/gnosis/listnav.vim\|^autoload/gnosis/panel.vim\|^autoload/gnosis/outline.vim\|^autoload/gnosis/hint.vim\|^test/listnav\|^test/side_panel' && add 'listnav|side_panel|mview_panel'
echo "$CH" | grep -q '^autoload/gnosis/start.vim' && add 'start_screen|start_size'
echo "$CH" | grep -q '^autoload/gnosis/i18n.vim\|^i18n/\|^autoload/gnosis/settings' && add 'i18n|vault_settings|start_screen|settings'
echo "$CH" | grep -q '^autoload/gnosis/theme\|^colors/\|^assets/themes' && add 'theme|light_contrast'
echo "$CH" | grep -q '^web/' && add 'WEB'
echo "$CH" | grep -q '^guide/\|^docs/' && add 'check_guide'
echo "$CH" | grep -q '^autoload/gnosis.vim\|^plugin/gnosis.vim\|^python/note_format' && add 'ALL'
PAT=${PAT#|}
if [ -z "$PAT" ] || echo "$PAT" | grep -q 'ALL'; then
  echo "共通部分が変わっている（または対応が不明）ので全部流す"; exec bash "$REPO/test/run_parallel.sh" "$@"
fi
echo "変更に関係する試験: $PAT"
LIST=$(grep -E '^(python3|sh) "\$REPO/' "$REPO/test/run.sh" | grep -E "$(echo "$PAT" | sed 's/|WEB//; s/WEB|//; s/^WEB$/ZZZNONE/')" | grep -v xvfb)
FAIL=0
echo "$LIST" | xargs -P 8 -I{} bash -c 'H=$(mktemp -d "$TMPDIR/home.XXXXXX"); export GNOSIS_HOME=$H REPO='"$REPO"'; . "$REPO/test/noclip.sh"; if eval "{}" >/dev/null 2>&1; then echo "OK   {}"; else echo "NG   {}"; fi; rm -rf "$H"' | sort | tee "$TMPDIR/related-last.txt"
echo "$PAT" | grep -q WEB && (cd web && node test/mandala_scroll_e2e.mjs >/dev/null 2>&1 && echo "OK   web/mandala_scroll_e2e" || echo "NG   web/mandala_scroll_e2e")
grep -q '^NG' "$TMPDIR/related-last.txt" && exit 1 || exit 0
