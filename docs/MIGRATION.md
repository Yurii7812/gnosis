# 移行ガイド（既存の vault から、このブランチの機能へ）

このブランチ（`feat/master-roadmap`）は、**既存の vault の形式を変えません**。ノート・Folgezettel・関係ブロック（`ParentBranch:` など）・`\M` の取り込み記録はそのまま読めます。

## 増えるもの（すべて任意・派生または追記）
| 場所 | 中身 | 消したら |
|---|---|---|
| `<vault>/.state/` | 履歴 `history.json`・リマインダー `reminders.json`・タイマー `timer.json`・インクリメンタル `incremental.json`・取り消し用の控え（`merge-undo`・`split-undo`・`rename-undo`）・取り込み記録 | 履歴・通知の「扱い済み」・取り消しの控えが失われる。ノートは無傷 |
| `<vault>/.gnosis/` | 保存した検索・SRS の進み・ブックマーク・トレイル・全文索引（派生） | 索引は作り直される。ブックマーク等は失われる |
| `記録.md`（任意の名前） | `⏱`（時間）・`🌱`（習慣）・`📋`（ライフログ）・`📖`（読書進捗）の行 | ふつうのノート。消せば記録が消える |
| front matter の任意キー | `maturity:` `requires:` `source:` `para:` `slides:` `location:` `moc:` | 付けたものだけ。付けなくても何も困らない |

## 変わる挙動（注意）
- `:GnosisRename` は、**他のノートのリンクと取り込み記録も更新**する安全版に置き換わった（`:Rename` は従来どおり）。取り消しは `:GnosisRenameUndo`。
- `:GnosisBackup` は従来どおり（暗号化 vault の 7z）。新しい tar.gz のスナップショットは `:GnosisSnapshot`。
- Vim でノートを開くと、`.state/history.json` が（終了時に）書かれる。

## 手順
1. **まずバックアップ**: `:GnosisSnapshot`（vault の外に tar.gz と SHA-256 の manifest。作った直後に検証される）。復元の練習は `:GnosisSnapshotRestore アーカイブ 新しい空のフォルダ`。
2. `:GnosisCheck` で壊れたリンクを確認、`:GnosisCompat` で他アプリで崩れそうな書き方を確認（どちらも読み取り専用）。
3. 必要な機能だけ使う。`docs/USER_GUIDE.md` と `:GnosisGuide` に一覧がある。
4. 元に戻したいとき: 取り消し系（分割・統合・名前変更）は控えから、全体はスナップショットから復元。

## 互換性
- 書き出したサイト・EPUB は派生物で、いつでも作り直せる。`private: true` のノートは含まれない。
- スマホのメモ（Android）側は変えていない。`\M` の取り込みは従来の記録 `.state/capture_imported.json` を使い続ける。
