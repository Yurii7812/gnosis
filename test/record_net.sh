#!/bin/sh
# 時系列記録（:GnosisRecordNew・\R・:GnosisRecordMigrate）
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-$HOME/gnosis-work/test}/record.XXXXXX")
trap 'rm -rf "$W"' EXIT
V="$W/v"
mkdir -p "$V" "$W/home"
# 旧形式の vault: Index の直下に日記と夢日記。夢日記の月グループは日記と同じ題「2026-10」
cat > "$V/index.md" <<'EOF'
---
title: Index
attribute: group
---

# Index

[日記](old-diaryg.md)
[夢日記](old-dream.md)
EOF
cat > "$V/old-diaryg.md" <<'EOF'
---
title: 日記
attribute: group
---

# 日記

Group:
[Index](index.md)

[2026-10](old-dmonth.md)
EOF
cat > "$V/old-dmonth.md" <<'EOF'
---
title: 2026-10
attribute: group
---

# 2026-10

Group:
[日記](old-diaryg.md)

[2026-10-12-MO](old-diary.md)
EOF
cat > "$V/old-diary.md" <<'EOF'
---
time: 2026-10-12 08:00:00
title: 2026-10-12-MO
---

# 2026-10-12-MO

Group:
[2026-10](old-dmonth.md)

今日は[病院の夢](old-day.md)を見た。

## 今日のノート

[2026-10-12-MO-夢-病院](old-day.md)
EOF
cat > "$V/old-dream.md" <<'EOF'
---
title: 夢日記
attribute: group
---

# 夢日記

Group:
[Index](index.md)

[2026-10](old-month.md)
EOF
cat > "$V/old-month.md" <<'EOF'
---
title: 2026-10
attribute: group
---

# 2026-10

Group:
[夢日記](old-dream.md)

[2026-10-12-MO-夢-病院](old-day.md)
EOF
cat > "$V/old-day.md" <<'EOF'
---
time: 2026-10-12 09:00:00
title: 2026-10-12-MO-夢-病院
---

# 2026-10-12-MO-夢-病院

Group:
[2026-10](old-month.md)

病院の夢。
EOF
mkdir -p "$V/.state"
printf '{"days": {"2026-10-12": "old-diary.md"}, "notes": {"old-day.md": "old-diary.md"}, "no_list": {}}' > "$V/.state/diary_days.json"
HOME="$W/home" GNOSIS_HOME="$W/home/gh" RECORD_VAULT="$V" RECORD_RESULT="$W/result.txt" \
  timeout 60 vim -u "$REPO/vimrc_gnosis" -N -n -i NONE -es --cmd "let g:gnosis_root='$V/'" -S "$REPO/test/record_check.vim" </dev/null >/dev/null 2>&1 || true
cat "$W/result.txt" 2>/dev/null || echo "NG 結果がありません"
if [ -f "$W/result.txt" ] && ! grep -q "^NG" "$W/result.txt"; then echo "record OK"; else echo "NG: record"; [ -n "${KEEP:-}" ] && cp -r "$W" "$KEEP"; exit 1; fi
