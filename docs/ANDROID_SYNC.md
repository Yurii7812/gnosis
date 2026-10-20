# Android 同期（`\M`）の仕様と実装状況

原本: `Gnosis_Claude_Implementation_Master_Prompt.md` §7.3。**重複インポート禁止・差分更新が絶対条件。**

## 仕組み
- スマホ（`android/`）の `entries.json` を adb `run-as` で読み、`capture.json` にする（`capture_import.py adbpull`）。
- `capture_import.py plan` が各メモを分類する。state は vault ごとの `.state/capture_imported.json`（`ids`: メモ id → 行き先、`entries`: 取り込んだ時点のスナップショット＝**base**）。
- 行き先がノートのファイル（`xxx.md`）で、スナップショットに本文があるメモは、本文／画像が変わったら **merge** になる。`capture_import.py merge OUTDIR ROOT` が `capture_merge.py` で同じノートへ当てる。

## 3-way merge（`python/capture_merge.py`）
- base（前回のスマホ本文）→ remote（今回）の差分を行の塊ごとに local（PC のノート全体）へ当てる。塊の元の行と直前の 1 行がそのまま見つかれば当てる。見つからない塊は**競合**。
- 競合のとき: ノートは変えない・新しいノートも作らない・`.state/capture_conflicts/<id>.json`（base/remote/塊）を残す・取り込み済み（snapshot 更新・✓）にしない。次回の `\M` でも同じ競合として出る。
- すでに同じ変更が local にあれば当て済み（冪等）。題・ファイル名・関係のブロックには触れない。ノート書き込みは一時ファイル＋`os.replace`。
- 本文の画像は `![](capture-images/…)` の行として本文と一緒に扱う（追加・削除が反映される。ファイル自体は消さない）。

## 要件 14 項目の状況（2026-10-20）
| # | 要件 | 状況 |
|---|---|---|
| 1 | 安定した原本 ID と対応の永続化 | id→行き先は既存（state）。ノート側の不変 source ID は**未実装** |
| 2 | ノートの出自 ID・移動／リネーム検出 | **未実装**（リネームすると行き先が無くなり新規扱い＝重複の恐れ。次の作業） |
| 3 | 新規／完全スキップ／差分更新の 3 動作 | **実装・試験済み**（標準のノート。日記・まとめトピック・時系列記録への追記は未対応） |
| 4 | PC 未変更なら同一ノート更新 | 実装・試験済み |
| 5 | base/local/remote の 3 方向マージ・競合表示 | マージは実装・試験済み。競合の**差分画面・解決操作は未実装**（記録と警告のみ） |
| 6 | トピックだけの変更 | 既存どおり同一ノート（試験あり） |
| 7 | 日記の埋め込み境界 | **未実装**（日記は本文に追記。編集は反映されない） |
| 8 | 画像の hash 管理 | 一部（本文の画像行のみ。hash 重複排除は未実装） |
| 9 | Branch／Context の差分反映 | 未実装（初回のみ） |
| 10 | 冪等・クラッシュ復旧・ジャーナル | 一部（merge は冪等・原子的書込。取り込み全体のジャーナルは未実装） |
| 11 | ✓ は永続化後のみ | 既存（record 成功後に adbmark） |
| 12 | 既存の重複候補の診断・統合 | 未実装 |
| 13 | vault ごとに独立 | 既存（試験あり） |
| 14 | プレビュー／競合解決／履歴／取り消し | 未実装 |

## 試験
`python/test_capture_merge.py`（merge の単体）、`python/test_capture_import.py`（plan）、`test/capture_merge_net.sh`（実 Vim: 再実行で増えない／mtime 不変／PC 追記とスマホ別行編集／冪等／同一行競合）、`test/capture_topics_net.sh`。必須 E2E のうち未着手: 日記 10 回、クラッシュ後の再実行、リネーム、旧 state 移行、新旧 APK。
