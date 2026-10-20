# 操作ガイド（Vim・`\A`・書き出し）

通常の操作は `docs/04-キー操作.md` と Vim 内の `:GnosisGuide`。ここでは、新しく加わった操作を、使う順にまとめる。**未実装・未確認のものは明記**する。

## 1. スマホのメモを取り込む（`\M`）
- `\M`（`:GnosisCaptureImport`）: USB でつないだスマホのメモを取り込む。**同じメモを何度取り込んでも増えない**。スマホで書き直したメモは、別のノートを作らず**同じノートの該当部分だけ**を更新する。PC で追記した部分は残る。日記・時系列記録・まとめるトピックに入れたメモも同じ（その行だけ更新）。
- PC とスマホが**同じ場所**を変えたときは、どちらも変えずに警告する（ノートは取り込み済みにしない）。`:GnosisCaptureConflicts` で内容を見て、`:GnosisCaptureResolve ID keep`（PC を残す）か `append`（スマホの行を引用で足す。手で統合）で解決する。
- 旧版でできた別版（`ID-2.md` など）は `:GnosisCaptureDuplicates` で一覧するだけ（何も消さない。統合は `\l` → m）。旧ノートにも追跡用の印を足すには `:GnosisCaptureBackfill`（確認だけ）→ `:GnosisCaptureBackfill apply`。
- 実機（本物のスマホ・adb）での確認は未実施。試験は取り込みデータ（`capture.json`）を使う。

## 2. 検査・Agenda
- `:GnosisCheck`: 壊れたリンク・Folgezettel の重複／抜け・孤立ノート。Enter でそのノートへ。読み取り専用。
- `:GnosisAgenda [YYYY-MM-DD]`: `- [ ]` を期限ごとに集める。Enter でその行へ、`x` で完了（繰り返しは次の回を作る）。書き方は `docs/DATA_FORMATS.md` §4。

## 3. 曼荼羅（9×9）
- `:GnosisMandalaNew 主題 [副題…8個まで]` → ふつうの Markdown の表のノートができる。
- 表のマスの上で `:GnosisMandalaCell`（新しいノート）／`:GnosisMandalaCell!`（別の曼荼羅）: そのマスの文字からノートを作ってリンクにする。`:GnosisMandalaSync`: 主題・副題の対応を揃える。
- 9×9 の格子表示は、書き出したサイト（§4）で見る。`\A` の中での表示は未実装。

## 4. 書き出し（HTML）
- `:GnosisExportSite[!] [出力先]`: 既定は `<vault>/.site`。`private: true` のノートは入らない（`!` で含める）。出力先が空でも前回の書き出しでもなければ何も書かない。
- 開くのは `index.html`。**カード・テーブル・タイムライン・番号ナビ（Folgezettel）・グラフ・検索**は、ブラウザでファイルとして直接開いて使える（ネット不要）。番号ナビのキー: ↑親 ↓最初の子 ←→兄弟 `[` `]` 番号順 Home/End、Alt+←→ 履歴。Markdown ビューア用には `FOLGEZETTEL.md`（番号表）。
- 公開前に確認: 画像の EXIF・位置情報は取り除かない（未実装）。

## 5. `\A`（Electron アプリ）
- 今ある機能: Vim の内容を Markdown 表示で映す・閲覧専用（Alt+V）・クリックでリンク移動。
- **未実装**: タブ・分割ペイン、Vim に依存しない GUI 編集モード、`\A` 内のグラフ／番号ナビ／カード、コマンドパレット。設計案は `docs/ARCHITECTURE.md`（GUI 編集モードは承認待ち。`docs/DECISIONS.md` D006）。
