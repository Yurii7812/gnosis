# アーキテクチャ（2026-10-20 時点の監査結果）

## 層（現状）
| 層 | 場所 | 規模 |
|---|---|---|
| Vim プラグイン（操作層の大半） | `autoload/gnosis.vim`（約 1.8 万行）、`autoload/gnosis/*.vim`、`plugin/` | 巨大な単一ファイルが中心 |
| Python ヘルパー（データ処理） | `python/`（ノート形式 `note_format_v2.py`、紙 PKM `paper_pkm.py`、Folgezettel、`capture_import.py` ほか） | 単体試験あり（`python/test_*.py`） |
| `\A` / `gnosis --app` | `web/`（Electron＋xterm.js＋CodeMirror 6 の**読み取り専用**描画。`vim/gui.vim` が TCP/JSON で状態を送る。`bridge/ptybridge.py` が Vim を pty で動かす） | `web/test/*.mjs` の E2E |
| Android | `android/`（Kotlin。`Store.kt` `Alarm.kt` `MainActivity.kt`）。PC へは adb `run-as` で `entries.json` を読む | Gradle |
| 試験 | `test/run.sh`（`set -e`）＋ `test/*_net.sh`（実 Vim）＋ CI `.github/workflows/gnosis-regression.yml`（一部のみ） | |

## 計画上の方針（案。DECISIONS に確定を書く）
- 新機能のデータ処理は Python 層（純関数＋単体試験）に置き、Vim コマンドと `\A` ボタンは同じ CLI／API を呼ぶ。
- `\A` は現在「Vim が唯一の書き込み主体、画面は読み取り専用」。GUI 編集モードは、Vim を介して（Vim バッファへ編集を送る）か、保存権を明示的に移す方式で、同時 2 書き込み主体を避ける設計が要る（Phase 2 の最初に設計）。
- `\M` の新 state は既存 `.state/capture_imported.json` を**読める**まま、追加フィールド（source ID・base 内容・ハッシュ）を持つ版 2 にする。
- SQLite FTS 等は派生キャッシュ（再構築可能）。

## 既知の資料矛盾（原本 §2 の指摘の確認）
- `docs/04-キー操作.md` 自身が古い操作を含むと注記。`NOTE_FORMAT.md` は過去形式を含む。正はコードとテスト。
- `docs/11-スマホのメモ.md` の「本文を書き直したら別版として取り込む」は原本 §7.3 により**廃止予定**（移行は Phase 1）。
