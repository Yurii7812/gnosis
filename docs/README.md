# Gnosis — PKM システムの資料

このフォルダは Gnosis（旧名 simple-yurii-note。2026-10 に改名）の資料置き場。
**他のAI・未来の自分が引き継げるように**、構成と規則をここに集める。

- 本体: GitHub `Yurii7812/gnosis`（旧 `Yurii7812/simple-yurii-note`。GitHub が旧 URL を新 URL へ転送する）
- 作者の環境: 本体 `~/.vim-simple-yurii-note/simple-yurii-note`、ノート `~/files/yurii-note`（`A/note` の暗号化 vault）
- 起動: `gnosis`（ランチャー `bin/gnosis`。専用の vimrc `<Gnosis ホーム>/vimrc` → `vimrc_gnosis`）。
  旧 `vim -u ~/.vimrc-simple-yurii-note` でも動く
- 導入・移行・置き場所は [09-導入と移行](09-導入と移行.md)

## まず読む順

1. [01-概要](01-概要.md) … 何のシステムか、環境、全体マップ
2. [02-ノート形式](02-ノート形式.md) … ノートの書き方（`### Context` / `BackLink:` / 本文リンク）
3. [03-同期の規則](03-同期の規則.md) … Context/BackLink がどう決まるか
4. [04-キー操作](04-キー操作.md) … よく使うキー / コマンド
5. [05-データとリポジトリ](05-データとリポジトリ.md) … 保存場所・Git・push ルール
6. [06-引き継ぎ](06-引き継ぎ.md) … 新しいAI向けチェックリスト・落とし穴・検証コマンド
7. [07-ドキュメントの書き方](07-ドキュメントの書き方.md) … **何をどこに残すか**（触ったら必ず読む）
8. [08-Web アプリ](08-web.md) … アプリ（Electron）。起動画面・vault 管理・設定画面
9. [09-導入と移行](09-導入と移行.md) … インストーラー・Gnosis ホーム・vault ごとの設定・言語・テーマ・旧環境からの移行
10. [10-旧README](10-旧README.md) … simple-yurii-note 時代の README（機能一覧の詳細。名前は Gnosis に読み替え済み）

> 作業して何か学到んだら、**その判断基準に従って必ずどこかに追記する**。
> このフォルダは GitHub `Yurii7812/gnosis` の `docs/` にも複製して公開している
> （同期手順は 07）。

## 30秒サマリ

- **1ファイル=1Markdown ノート**。関係は Markdown リンクで表す。
- ノート下部に `### Context` と `BackLink:` の2セクション。**`### Child` は無い**。
- **本文にリンクを書くと「子」**になる。
- **`### Context` は手書き管理**（書いたまま。勝手に増減しない）。ただし消えた
  ファイルへのリンク行は sync が掃除する。
- **`BackLink:` = 本文でこのノートを参照している相手（incoming）− Context**。
- 同期エンジンは `python/note_format_v2.py`。保存時に自動同期。
- Gnosis 専用の Vim 環境（ふだんの `~/.vimrc`・`~/.vim` は読まない）で運用。起動画面 → vault を選んで Enter。
