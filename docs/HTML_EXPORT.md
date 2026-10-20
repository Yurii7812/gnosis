# Markdown と HTML の相互運用・書き出し

原本: `Gnosis_Claude_Implementation_Master_Prompt.md` §8。

## いまできること（`:GnosisExportSite[!] [出力先]` / `python/export_site.py ROOT OUTDIR`）
- **オフラインで読める静的サイト**: ノートごとの HTML、`index.html`（題の一覧）、`folgezettel.html`、`search.html`（自前の全文検索。`search.js` と `search-index.json`）。外部 CDN は使わない。
- **通常の Markdown ビューアで読める番号表** `FOLGEZETTEL.md`（`| 番号 | 題 |`、字下げは全角空白、リンクは `.md`）。JavaScript が要るものは HTML 側だけ。
- ノート HTML には、本文のほか Folgezettel のパンくず（親へ戻れる）、ParentBranch・Group・Context・Related・BackLink、「このノートへのリンク」を付ける（`gnosis_graph.py` から。元の索引は書き換えない）。
- 変換は `python/md_html.py`（依存なし）。見出し・段落・箇条書き（入れ子・チェックボックス）・番号つき・引用・コードブロック・表・水平線・画像・リンク・強調・取り消し線。`.md` へのリンクは `.html` に書き換える。

## 安全（試験済み: `python/test_md_html.py` `python/test_export_site.py` `test/export_site_net.sh`）
- 本文は全部エスケープ。生の HTML・`<script>` は通さない。リンク・画像の URL は http / https / mailto / 相対だけ。`javascript:` `data:` `file:` `//` は無効。タグに任意の属性は付かない。
- 各 HTML に CSP（`default-src 'none'; img-src 'self'; style-src 'self'; script-src 'self'`）。表示専用で、編集・ローカルファイル読み出しの仕組みは無い。
- **非公開**: `private: true` / `export: false` のノートは既定で書き出さず、検索索引にも入れない。そのノートへのリンクは文字だけにする（存在しないページへのリンクを残さない）。`!` で含める。
- 添付（画像・PDF 等）は、本文が参照する vault 内のファイルだけコピー。`..`・シンボリックリンクで vault の外へ出るもの、ドット始まりのフォルダのものは持ち出さない。
- 出力先は、無い／空／前回の書き出し（`.gnosis-export`）のときだけ。それ以外は何も書かずに止まる。vault 内なら `.`始まりのフォルダだけ（書き出しをノートとして読み直さないため）。vault のノートは 1 バイトも変えない。

## 未実装・未検証（台帳で未完了のまま）
- 画像の EXIF・位置情報の除去オプション（コピーはそのまま。公開時は利用者が確認する）。
- 暗号化 vault の扱いの専用確認、大規模 vault の分割出力、PDF・EPUB 出力（UT07）、スライド（VW19）。
- Markdown の「表示索引（views 目次）」: いまは Folgezettel の番号表だけ。タスク一覧・検索結果・トレイルなどは対応する機能と一緒に作る。
- Markdown の網羅性: ネストした引用内のコードや HTML ブロック、脚注、定義リストは未対応（そのままテキストとして出る）。
- ブラウザでの実表示確認（レイアウト・ダークモード）は未実施。生成した HTML の構造は試験済み。
