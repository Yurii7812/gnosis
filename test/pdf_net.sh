#!/bin/sh
# :GnosisPdf を実 Vim から。手書きの注釈つき PDF(python/test_pdf_notes.py と同じ作り)で、annotations / digest(新規ノート) / check を通す。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/pdfn.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
REPO="$REPO" D="$D" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["REPO"] + "/python")
import test_pdf_notes as t
pages = [["Alpha beta gamma delta"], ["Page two has memory palace technique"]]
ann = {1: ["/Subtype /Highlight " + t.quad(70, 697, 150, 712) + " /Contents (key)"]}
open(os.environ["D"] + "/v/b.pdf", "wb").write(t.build_pdf(pages, ann))
open(os.environ["D"] + "/v/n.md", "w", encoding="utf-8").write("---\ntime: 2026-01-01 00:00:00\ntitle: n\n---\n\n> Page two has memory palace technique [p.2](b.pdf#page=2)\n\n> Alpha beta gamma [p.2](b.pdf#page=2)\n")
PY
REPO="$REPO" D="$D" HOME="$D/home" GNOSIS_HOME="$D/gh" timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/pdf_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
grep -q 'b.pdf#page=1' "$D/v/読書.md" || { echo "NG: digest のノートが無い" >&2; exit 1; }
printf '%s\n' 'pdf OK'
