#!/bin/sh
# スマホのメモの取り込み（USB の代わりに capture.json と images/ を渡す）: 日記は日記の本文へ時刻つき・
# ほかは 1 件 = 1 ノート・Branch / Context・画像・二度目は取り込まない
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-$HOME/gnosis-work/test}/cap.XXXXXX")
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
 {"id": "261018150000", "created": ms("2026-10-18 15:00"), "topic": "仕事", "text": "見積もりを出す\n来週まで", "images": [], "parent": None, "contexts": []},
 {"id": "261018151000", "created": ms("2026-10-18 15:10"), "topic": "仕事", "text": "電話した\n折り返し待ち", "images": [], "parent": None, "contexts": []},
 {"id": "261019090000", "created": ms("2026-10-19 09:00"), "topic": "仕事", "text": "翌日の作業", "images": [], "parent": None, "contexts": []},
 {"id": "261019091000", "created": ms("2026-10-19 09:10"), "topic": "仕事", "text": "会議の話", "images": [], "parent": None, "contexts": ["261018150000"]},
 {"id": "261018160000", "created": ms("2026-10-18 16:00"), "topic": "読書", "text": "一冊目", "images": [], "parent": None, "contexts": []},
 {"id": "261018161000", "created": ms("2026-10-18 16:10"), "topic": "読書", "text": "二冊目", "images": [], "parent": None, "contexts": []},
 {"id": "261018070000", "created": ms("2026-10-18 07:00"), "topic": "夢", "text": "空を飛んだ\n高かった", "images": [], "parent": None, "contexts": []},
 {"id": "261018071000", "created": ms("2026-10-18 07:10"), "topic": "夢", "text": "海の夢", "images": [], "parent": None, "contexts": []},
 {"id": "261018170000", "created": ms("2026-10-18 17:00"), "topic": "メモ", "text": "見積もりの続き\n前の[電話](memo:261018151000)を参照\n[本](memo:261018160000)", "images": [], "parent": "261018151000", "contexts": []},
]
M = {"仕事": {"single": True, "stamp": True}, "読書": {"single": True, "stamp": False}, "日記": {"single": True}, "夢": {"record": True, "single": True}}
json.dump({"format": "gnosis-capture", "version": 1, "entries": E, "topicModes": M}, open(D + "/pack/capture.json", "w"), ensure_ascii=False)
open(D + "/pack/images/a.jpg", "wb").write(b"\xff\xd8fake")
# 2 回目: 夢の続き（PC で書いた 07:30 の分と時刻の順にまざる）
E2 = E + [
 {"id": "261018072000", "created": ms("2026-10-18 07:20"), "topic": "夢", "text": "三つ目の夢", "images": [], "parent": None, "contexts": []},
 {"id": "261018074000", "created": ms("2026-10-18 07:40"), "topic": "夢", "text": "四つ目の夢", "images": [], "parent": None, "contexts": []},
]
os.makedirs(D + "/pack2/images")
open(D + "/pack2/images/a.jpg", "wb").write(b"\xff\xd8fake")
json.dump({"format": "gnosis-capture", "version": 1, "entries": E2, "topicModes": M}, open(D + "/pack2/capture.json", "w"), ensure_ascii=False)
EOF
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -S "$REPO/test/capture_import_check.vim" </dev/null 2>"$D/err" || true
V="$D/v"
diary=$(grep -l "^# 2026-10-18-[A-Z][A-Z]$" "$V"/*.md | head -1)
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
chk "番号（Folgezettel ID）の無いメモは未所属（\\N）に出る（スマホでつないだだけでは番号は付かない）" 'PYTHONDONTWRITEBYTECODE=1 python3 "$REPO/python/orphans.py" "$V" | grep -q "261018101000"'
work=$(grep -l '^capture_topic: "仕事"$' "$V"/*.md | head -1)
book=$(grep -l '^capture_topic: "読書"$' "$V"/*.md | head -1)
chk "まとめるトピックは 1 つのノート（トピック名の題）" '[ -n "$work" ] && grep -q "^# 仕事$" "$work" && [ ! -f "$V/261018151000.md" ] && [ ! -f "$V/261019090000.md" ]'
chk "日時あり: 日付の見出しの下に時刻つき（同じ日は見出し 1 つ）" '[ "$(grep -c "^## 2026-10-18（日）$" "$work")" = 1 ] && grep -q "^15:10 電話した$" "$work" && grep -q "^## 2026-10-19（月）$" "$work" && grep -q "^09:00 翌日の作業$" "$work"'
chk "日時あり: 複数行の本文もそのまま" 'grep -A1 "^15:10 電話した$" "$work" | grep -q "^折り返し待ち$"'
W=$(basename "$work")
chk "まとめる: 使われたメモは見出しの節（見出しも本文に残る。すぐ下が見出しなら閉じない）" '[ ! -f "$V/261018150000.md" ] && grep -A4 "^## 見積もりを出す$" "$work" | tr "\n" "|" | grep -q "^## 見積もりを出す|15:00 見積もりを出す|来週まで||## 電話した|"'
chk "まとめる: 下に見出しが無い節は ## だけの行で閉じる" 'grep -A4 "^## 一冊目$" "$book" | tr "\n" "|" | grep -q "^## 一冊目|一冊目|##||二冊目"'
chk "まとめる: 使ったメモは同じノートの中で、その見出しへのリンクの行" '[ ! -f "$V/261019091000.md" ] && grep -q "^09:10 会議の話$" "$work" && grep -q "^文脈: \[仕事#見積もりを出す\]($W#見積もりを出す)$" "$work"'
chk "ほかのノートから: 親が節なら見出しへのリンクの行と、トピックのノートを文脈に" 'grep -q "^↳ \[仕事#電話した\]($W#電話した) の続き$" "$V/261018170000.md" && grep -q "^前の\[仕事#電話した\]($W#電話した)を参照$" "$V/261018170000.md" && grep -A1 "^Context:" "$V/261018170000.md" | grep -q "$W"'
chk "日時なし: 本文だけを足す" '[ -n "$book" ] && grep -q "^一冊目$" "$book" && grep -q "^二冊目$" "$book" && ! grep -q "^## 2026" "$book"'
chk "日記はまとめる設定にしない（日記のまま）" '! grep -l "^capture_topic: \"日記\"" "$V"/*.md >/dev/null 2>&1'
dream=$(grep -l '^# 2026-10-18-SU-夢$' "$V"/*.md | head -1)
recg=$(grep -l '^# 時系列記録$' "$V"/*.md | head -1)
chk "時系列記録: その日の記録のノート（日付-曜日-夢）に時刻つき" '[ -n "$dream" ] && grep -q "^record: \"夢\"$" "$dream" && grep -q "^07:00 空を飛んだ$" "$dream" && grep -A1 "^07:00 空を飛んだ$" "$dream" | grep -q "^高かった$" && grep -q "^07:10 海の夢$" "$dream"'
chk "時系列記録: 2 回目はその日のノートへ、PC で書いた分と時刻の順にまぜる" '[ "$(grep -o "^07:[0-9]* [^ ]*" "$dream" | cut -c1-5 | tr "\n" " ")" = "07:00 07:10 07:20 07:30 07:40 " ]'
chk "時系列記録: その日の日記の上に DailyNotes: でリンク（表示名は系列名）・時系列記録の中に夢" 'grep -q "^DailyNotes:$" "$diary" && grep -q "^\[夢\]($(basename "$dream"))$" "$diary" && grep -q "^\[夢\](" "$recg"'
chk "二度目は取り込まない" '[ "$(grep -c "スコーン" "$diary")" = 1 ] && [ "$(grep -c "^15:10 電話した" "$work")" = 1 ] && [ "$(grep -c "^二冊目" "$book")" = 1 ] && [ "$(grep -c "海の夢" "$dream")" = 1 ]'
if [ $ng = 0 ]; then echo "capture_import OK"; else cat "$D/err" >&2; [ -n "${KEEP:-}" ] && cp -r "$D" "$KEEP"; exit 1; fi
