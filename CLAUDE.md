# Gnosis — Claude Code 入口（毎回最初に読む）

- 原本の要求仕様: `Gnosis_Claude_Implementation_Master_Prompt.md`（全機能が対象。縮小・格下げ禁止）
- 現在地と次の作業: `docs/PROGRESS.md`（**作業の前に読み、終わったら必ず更新**）
- 機能台帳: `docs/FEATURES.md` ／ 順序: `docs/ROADMAP.md` ／ 判断の記録: `docs/DECISIONS.md`
- 不変条件: `docs/PHILOSOPHY.md`（ダブルインデックス・実 Vim・`\c` 拡張のみ・`\M` 重複禁止）

## 作業規則
- 返答・コミット・文書は日本語。コミットは小さく、末尾に Co-Authored-By を付ける。
- 試験は必ず `~/gnosis-work/test`（TMPDIR）と一時 GNOSIS_HOME で。**本物の vault・Gnosis ホームに触らない。プロセスは名前で kill しない。**
- 作業は worktree（`~/src/gnosis-*`）で。main への反映は区切りでまとめて ff-only → push。GitHub への書き込みを細かく繰り返さない。
- 破壊的操作（実 vault の書換・削除・force push・外部通信・課金）は止まって確認。それ以外は確認なしで次へ進む。
- 回帰: `sh test/run.sh`（`set -e` で最初の失敗で止まる）。基準線は PROGRESS.md の「テスト基準線」。
- スタブ・ダミーを「実装済み」と書かない。未実施の試験は未実施と書く。
