<p align="center"><img src="assets/logo/gnosis-logo.png" alt="Gnosis" width="420"></p>

# Gnosis

**Gnosis** は、Markdown のノートを本物の Vim で書き、リンクでつないで育てる PKM（Personal Knowledge Management）です。
旧名は **simple-yurii-note**（2026-10 に改名）。ノートの形式と操作は、そのまま引き継いでいます。

*Gnosis is a PKM for Markdown notes written in real Vim. Notes are linked into Context / Group / BackLink automatically.
The UI and the generated guide are available in Japanese and English (see [English summary](#english-summary)).*

- 1 ファイル = 1 ノート（Markdown）。関係はリンクで表し、`### Context` / `### Group` / `### Related` / `### BackLink` を保存時に自動で同期
- 中身は本物の Vim。Vim を知らなくても、インストーラーが Gnosis 専用の Vim 環境を作り、アイコンから起動できる
- デスクトップアプリ（Electron）は、Vim の画面をマークダウンの見た目で描く（画像・表・リンクの番号つき）
- 起動画面で vault（ノートのフォルダ）を選び・作り・登録できる。設定は vault ごと（言語・見た目・文字サイズ・起動サイズ・テーマ）
- 日本語 / 英語。操作ガイドも選んだ言語で作られる

リポジトリ: https://github.com/Yurii7812/gnosis

---

## インストール

ふだんの Vim の設定（`~/.vimrc`・`~/.vim`・`_vimrc`・`vimfiles`）は**読み込まず、変更もしません**。
インストーラーは Gnosis 専用の vimrc とプラグイン領域を **Gnosis ホーム**に作り、その vimrc を指定して起動するランチャーとアイコンを作ります。
Vim が無ければ入れ、Gnosis に使える Vim（8.2 以上、`+job +channel +timers +textprop +popupwin`）が既にあればそれを使います。
ふつうに `vim` を起動すれば、今までどおりの Vim です。

### Linux

```sh
git clone https://github.com/Yurii7812/gnosis.git
cd gnosis
./install/install.sh
```

- 足りないもの（Vim・git・Python 3・fzf・ripgrep・Node.js）は、確認してから apt / dnf / pacman / zypper で入れます（`--no-system` で入れない）
- アプリメニューに **Gnosis**（アイコン付き）ができます。端末からは `gnosis`（`~/.local/bin/gnosis`）
- デスクトップにもアイコンを置くなら `--desktop-icon`。アプリ（Electron）が不要なら `--no-app`

### macOS

```sh
git clone https://github.com/Yurii7812/gnosis.git
cd gnosis
./install/install.sh
```

Homebrew で足りないものを入れ、`~/Applications/Gnosis.app` を作ります（Finder・Launchpad から起動）。

### Windows 10 / 11

```bat
git clone https://github.com/Yurii7812/gnosis.git
cd gnosis
powershell -ExecutionPolicy Bypass -File install\install.ps1
```

winget で足りないもの（Vim・Git・Python・fzf・ripgrep・Node.js）を入れ、デスクトップとスタートメニューに **Gnosis** のショートカットを作ります。
Bash は要りません（起動画面のシンボルは静的なアセットから表示します）。

### アンインストール

`install/uninstall.sh`（Linux / macOS）はランチャー・アプリメニュー・アイコンを取り除きます。vault（ノート）は消しません。
`--purge` を付けると Gnosis ホーム（vault の一覧・テーマ・プラグイン）も消します。

---

## 起動

| 方法 | 動き |
| --- | --- |
| アイコン（アプリメニュー / Gnosis.app / ショートカット） | アプリ（Electron）で起動 |
| `gnosis` | アプリがあればアプリ、無ければ端末なら端末の Vim、GUI 版 Vim（gvim / MacVim） |
| `gnosis --app` / `--gui` / `--tui` | アプリ / GUI 版 Vim / 今の端末の Vim |
| `gnosis --new-terminal` | 新しい端末ウィンドウの Vim（対応端末には文字サイズと最大化を渡す） |
| `gnosis ノート.md` | そのノートを開く（起動画面は出さない） |
| `gnosis --where` | Gnosis のフォルダ・Gnosis ホーム・使う vimrc を表示 |

### 起動画面

ノートを開く前に、**白背景・黒文字**の起動画面が出ます: Chnoubis のシンボル・「Gnosis」・選択中の vault の名前とパス・「Enter で開始」。

| キー | 動き |
| --- | --- |
| `Enter` | 選択中の vault を開く（前回の vault が選ばれている） |
| `v` | vault の選択・管理 |
| `s` | 設定 |
| `q` | 終了 |

vault の一覧: `j` / `k` で選ぶ・`Enter` で開く・`a` 既存のフォルダを登録・`n` 新しい vault を作る・`d` 一覧から外す（**ノートとフォルダは消しません**）・`Esc` 戻る。
初めての起動（vault が無い）では、作るか登録するかを尋ねます。前回の vault が見つからないときは、元の場所に勝手に作らず、選び直し・場所の指定し直しを案内します。
使用中に vault を切り替えるときは `:GnosisVaults`（保存先・検索・同期・設定がその vault に切り替わります）。

### 設定（`:GnosisSettings` / 起動画面の `s` / アプリの「設定」）

vimrc を書き換えずに、vault ごとに設定します（`<vault>/.gnosis/settings.json`）。

- 言語（日本語 / English）… メッセージ・メニュー・入力案内・操作ガイド
- 起動時に最大化（既定: する。全画面表示ではありません）・通常のウィンドウサイズ
- 文字サイズ … 次に開くときから使われます
- ライト / ダーク
- テーマ … 標準・カスタム配色（背景・本文・リンク・見出し・選択範囲・カーソル行）・追加テーマ
- テーマの追加 … `Plug 'cocopon/iceberg.vim'` のように入力。Vim script としては実行せず、`作者/リポジトリ` だけを取り出して Gnosis ホームの `themes/` に取得します。読み込めないテーマは標準に戻ります

文字サイズと拡大縮小:

| 環境 | 文字サイズの設定 | Ctrl + / − / 0 |
| --- | --- | --- |
| アプリ | 本文と端末部分の文字の大きさ | 画面全体の拡大・縮小・元に戻す（その場だけ。設定は変わらない） |
| GUI 版 Vim | `guifont` の大きさ・起動サイズ | 文字の大きさをその場だけ変える（`Ctrl 0` で設定の大きさ） |
| 端末版 Vim | 端末の文字は Vim から変えられない。`gnosis --new-terminal` が kitty / alacritty / wezterm / xterm にだけ大きさと最大化を渡す | 端末の機能のまま |

ふだんの端末の設定は変更しません。gnome-terminal / konsole / Terminal.app などは、その端末の設定の文字サイズのままです。

---

## 主な操作

詳しくは vault の中の操作ガイド（`gnosis-guide.md`。旧 vault では `simple-yurii-note-guide.md`）と [docs/04-キー操作.md](docs/04-キー操作.md)。

| キー | 動作 |
| --- | --- |
| `zn` | ノート作成（`h` カーソル直下 / `Enter` 本文の最後 / `t` 見出しの下 / `c` Context 末尾 / `o` 孤立） |
| `zk` | グループ作成（位置キーは `zn` と同じ。**`g` = カーソル下のリンク 1 本を新しいグループへ**） |
| `zk`（ビジュアル） | 選択範囲を中身にしたグループ |
| `za` / `zA` / `zp` | クリップボード・ヤンクのリンクを追加（`zA` は表示名つき） |
| `\l` | 全文検索 → リンクを追加（**`n` = 表示名を入力して本文の最後へ**） |
| `\L` | ファイル名のリンク化 / 選択範囲から新ノート |
| `\S` | リンク行をよみ順に並べる（**グループでは本文の最後のブロックだけ**） |
| `\d` | 今日の日記 |

**`c` のあと（`zn` / `zk` / `za` / `\l`）**: 今のノート A の Context にリンク先 B を入れたあと、B に A へのリンクをどう入れるかを選びます。

| キー | B 側 |
| --- | --- |
| `Enter` | B の本文の最後（関係の節の手前） |
| `t` | B の見出しを選び、その節の最後（次の同じか上の階層の見出しの手前） |
| `o` | 入れない（A 側の追加はそのまま。操作の取り消しではありません） |
| `Esc` | 取り消し（A にも B にも何も書きません） |

B がグループなら、表示名を入力します。入力欄は空から始まり、空のまま `Enter` で A のタイトル、文字を入れて `Enter` でその文字、`Esc` で取り消し。
表示名はノートのタイトルやファイル名を変えず、保存・同期しても残ります（自動生成の BackLink とは別もの）。

アプリでは、リンクを `Alt` + クリックすると、開かずにカーソルだけがリンクに移ります（`zk` → `g` などに使います）。

---

## 置き場所

| もの | 場所 |
| --- | --- |
| Gnosis 本体 | `git clone` したフォルダ（更新は `git pull` してもう一度インストーラー） |
| Gnosis ホーム（Gnosis 側の状態） | Linux `~/.local/share/gnosis`（`$XDG_DATA_HOME/gnosis`）・macOS `~/Library/Application Support/Gnosis`・Windows `%APPDATA%\Gnosis`。`$GNOSIS_HOME` で変更可 |
| ├ `vaults.json` | 登録済みの vault と最後に選んだ vault |
| ├ `vimrc` / `vimrc.local` | 専用の vimrc（インストーラーが作る）/ Gnosis だけの追加設定（任意） |
| ├ `plugins/` / `themes/` | 専用のプラグイン（fzf・fzf.vim・vim-surround）/ 追加したテーマ |
| └ `logs/` / `state/` | アプリのログ / vault を選ぶ前の一時的な状態 |
| vault ごとの設定 | `<vault>/.gnosis/settings.json` |
| ノート | vault の中（`.md`）。履歴など vault の状態は `<vault>/.state/` |

設定の優先順位: 設定画面の項目は vault の `settings.json` → 既定値。設定画面に無い細かな動作は vimrc の `g:gnosis_*`（無ければ旧名 `g:simple_yurii_note_*`）→ 既定値。

---

## 旧 simple-yurii-note からの移行

1. Gnosis をインストールする（上の手順。今の `~/.vim-simple-yurii-note` はそのまま残ります）
2. 初めて Gnosis を起動すると、旧環境の vault（`~/.vim/simple_yurii_note/root.txt`）が自動で vault の一覧に入り、選択済みになります（root.txt は消しません）
3. 旧 vault の操作ガイド `simple-yurii-note-guide.md` は同じファイル名のまま最新の内容に更新されます（Index のリンクは壊れません）
4. 旧 vimrc の `g:simple_yurii_note_*` は `g:gnosis_*` にそのまま引き継がれます。旧コマンド `:Yurii*` は `:Gnosis*` の別名として使えます（`let g:gnosis_legacy_commands = 0` で定義しない）
5. 旧テーマ（kalisi）を使い続けるなら、設定画面のテーマの追加に `Plug 'freeo/vim-kalisi'`
6. 旧 vimrc（`~/.vimrc-simple-yurii-note`）で起動しても動きます（その場合だけ、従来どおり root.txt も更新します）

キーの変更点: 短いキー（`zn`・`zk`・`\l` など）は変わりません。追加は `zk` → `g`・`\l` → `n`・`c` のあとの `Enter` / `t` / `o`。`\S` はグループでは最後のブロックだけを並べます。

---

## 対応 OS と確認の範囲

| | Linux | macOS | Windows |
| --- | --- | --- | --- |
| Vim プラグイン（同期・リンク操作・起動画面・設定） | 実機で確認（Debian・Vim 9.1） | 実装済み・実機未確認 | 実装済み・実機未確認 |
| アプリ（Electron） | 実機で確認（xvfb 上の自動試験を含む） | 実装済み・実機未確認 | 実装済み・実機未確認（node-pty の作り直しが要る） |
| インストーラー | 一時 HOME で確認（パッケージの導入以外） | 実装済み・実機未確認 | 構文の確認のみ |
| GUI 版 Vim | gvim で確認 | MacVim 用に実装・未確認 | gvim 用に実装・未確認 |

---

## 開発

```sh
test/run.sh            # Vim・Python・インストーラーの回帰網（一時フォルダ ~/Desktop/test を使う）
cd web && npm test     # アプリの E2E（xvfb・本物の Vim）
python3 tools/build_icons.py       # アイコン・ロゴの生成（assets/*/source/ に正式な画像を置くと差し替え）
python3 tools/extract_chnoubis.py  # assets/chnoubis/chnoubis.sh から起動画面のアートを取り出す
```

構成: `plugin/` `autoload/`（Vim プラグイン）・`python/`（同期・検索）・`web/`（アプリ）・`i18n/`（日英の文言）・`guide/`（操作ガイドの元）・
`assets/`（シンボル・アイコン・ロゴ・テーマの色）・`install/`・`bin/`（ランチャー）。資料は [docs/](docs/README.md)。

---

## English summary

Gnosis (formerly simple-yurii-note) is a Markdown note system (PKM) built on real Vim.

- **Install**: `git clone https://github.com/Yurii7812/gnosis.git && cd gnosis && ./install/install.sh` (Linux / macOS) or
  `powershell -ExecutionPolicy Bypass -File install\install.ps1` (Windows). The installer creates a Gnosis-only vimrc and plugin area in the
  Gnosis home (`~/.local/share/gnosis`, `~/Library/Application Support/Gnosis`, `%APPDATA%\Gnosis`), a launcher (`gnosis`) and an icon.
  Your own `~/.vimrc` / `~/.vim` are never read or changed.
- **Start screen**: the Chnoubis symbol, "Gnosis", the selected vault, `Enter` to start, `v` to choose / register / create / remove vaults
  (removing never deletes notes), `s` for settings.
- **Settings per vault** (`.gnosis/settings.json`): language (Japanese / English), maximize on start, window size, font size, light / dark,
  themes (standard, custom colors, or `Plug 'author/repo'` themes from GitHub, safely parsed).
- **New keys**: `zk` → `g` groups the link under the cursor; `\l` → `n` adds a link with a typed display name;
  after `c` in `zn` / `zk` / `za` / `\l`, choose how the target links back: `Enter` end of body, `t` end of a chosen section, `o` none.
  `\S` in a group sorts only the last blank-line-separated block.
- **Migration**: the old vault is imported automatically on first start; old `g:simple_yurii_note_*` settings and `:Yurii*` commands keep working.
