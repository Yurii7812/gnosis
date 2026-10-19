#!/bin/sh
# スマホのメモの取り込み（USB の代わりに capture.json と images/ を渡す）: 日記は日記の本文へ時刻つき・
# ほかは 1 件 = 1 ノート・Branch / Context・画像・二度目は取り込まない
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-$HOME/Desktop/test}/cap.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh" "$D/pack/images"
D="$D" python3 - <<'EOF'
import json, os, datetime as dt
D = os.environ["D"]
ms = lambda s: int(dt.datetime.strptime(s, "%Y-%m-%d %H:%M").timestamp() * 1000)
E = [
 {"id": "261018091500", "created": ms("2026-10-18 09:15"), "topic": "日記", "text": "吉原駅まで歩く", "images": ["a.jpg"], "parent": None, "contexts": []},
 {"id": "261018101000", "created": ms("2026-10-18 10:10"), "topic": "メモ", "text": "APKに画像添付\nこれ重要", "images": [], "parent": None, "contexts": []},
 {"id": "261018101500", "created": ms("2026-10-18 10:15"), "topic": "メモ", "text": "通知で書く機能", "images": [], "parent": "261018101000", "contexts": ["261018091500"]},
 {"id": "261018120000", "created": ms("2026-10-18 12:00"), "topic": "日記", "text": "お昼はスコーン\n二切れだけ", "images": [], "parent": None, "contexts": []},
 {"id": "261018130000", "created": ms("2026-10-18 13:00"), "topic": "メモ", "text": "前の [APKに画像添付](memo:261018101000) を見る\n[消えたメモ](memo:999999999999) は文字だけ", "images": [], "parent": None, "contexts": ["261018140000"]},
 {"id": "261018140000", "created": ms("2026-10-18 14:00"), "topic": "日記", "text": "散歩した", "images": [], "parent": None, "contexts": []},
]
json.dump({"format": "gnosis-capture", "version": 1, "entries": E}, open(D + "/pack/capture.json", "w"), ensure_ascii=False)
open(D + "/pack/images/a.jpg", "wb").write(b"\xff\xd8fake")
EOF
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -S "$REPO/test/capture_import_check.vim" </dev/null 2>"$D/err" || true
V="$D/v"
diary=$(grep -l "^title: 2026-10-18-" "$V"/*.md | head -1)
ng=0
chk() { if eval "$2"; then :; else echo "NG $1" >&2; ng=1; fi; }
chk "日記の本文に時刻つきで入る" 'grep -q "^12:00 お昼はスコーン$" "$diary" && grep -q "^二切れだけ$" "$diary"'
chk "関係のある日記はノートになり、日記には時刻つきのリンク" 'grep -q "^09:15 \[吉原駅まで歩く\](261018091500.md)$" "$diary" && [ -f "$V/261018091500.md" ]'
chk "メモは 1 件 = 1 ノートで今日のノートに載る" 'grep -q "^\[APKに画像添付\](261018101000.md)$" "$diary" && grep -q "^topic: \"\"$" "$V/261018101000.md"'
chk "題にした 1 行目も本文にそのまま残る" '[ "$(grep -c "^APKに画像添付$" "$V/261018101000.md")" = 1 ] && grep -q "^これ重要$" "$V/261018101000.md"'
chk "Branch（続けて書く）" 'grep -A1 "^ParentBranch:" "$V/261018101500.md" | grep -q "261018101000.md" && grep -A1 "^ChildBranch:" "$V/261018101000.md" | grep -q "261018101500.md"'
chk "Context（文脈）" 'grep -A1 "^Context:" "$V/261018101500.md" | grep -q "261018091500.md"'
chk "画像は capture-images/ に置く" '[ -f "$V/capture-images/a.jpg" ] && grep -q "capture-images/a.jpg" "$V/261018091500.md"'
chk "本文の中のメモへのリンクは、取り込んだノートへのリンクになる" 'grep -q "^前の \[APKに画像添付\](261018101000.md) を見る$" "$V/261018130000.md"'
chk "取り込んでいないメモへのリンクは表示名だけ" 'grep -q "^消えたメモ は文字だけ$" "$V/261018130000.md"'
chk "親が無いときは最初の文脈が親（Branch）になる" 'grep -A1 "^ParentBranch:" "$V/261018130000.md" | grep -q "261018140000.md" && grep -A1 "^Context:" "$V/261018130000.md" | grep -q "261018140000.md"'
chk "スマホでつないだノートは未整理（\\N）に出ない" '! PYTHONDONTWRITEBYTECODE=1 python3 "$REPO/python/orphans.py" "$V" | grep -q "26101813000\|261018101500\|261018101000"'
chk "二度目は取り込まない" '[ "$(grep -c "スコーン" "$diary")" = 1 ]'
if [ $ng = 0 ]; then echo "capture_import OK"; else cat "$D/err" >&2; exit 1; fi
