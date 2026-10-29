# データ形式（原本・派生）

原本は可搬な Markdown。DB・キャッシュ・書き出し物は**派生物**で、vault から作り直せる。ノート本体の書式（関係ブロック・Folgezettel の書き方）は `NOTE_FORMAT.md` と `docs/02-ノート形式.md`・`docs/03-同期の規則.md`（古い記述が混じる。正はコードと試験）。ここでは、このロードマップで加えた・確認した形式をまとめる。

## 1. front matter のキー（ノート）
| キー | 意味 | 備考 |
|---|---|---|
| `time` `title` | 作成日時・題 | 既存 |
| `folgezettel: "1a1"` | デジタルの Folgezettel ID | 数字と英字が交互（`folgezettel.py` の `ID_RE`）。グループは持たない（ブランチで作ったグループは親ノートと同じ ID） |
| `attribute: group` | グループ（容器）ノート | 既存 |
| `topic` `capture` | スマホのメモのトピック／旧名 | 既存 |
| ~~`capture_id: <id>`~~ | **廃止（2026-10-29）**。`\M` は書かない | 出自は `.state/capture_imported.json` と、ノートの `time:`（スマホのメモを書いた時刻）で追う。既存ノートの印は `:GnosisCaptureStripMeta apply` で消す |
| `mandala: true` | 曼荼羅ノート | §3 |
| `private: true` / `export: false` | 書き出しサイトから除く | `docs/HTML_EXPORT.md` |
| `record` | 時系列記録のノート | 既存（`capture_topic` は廃止。まとめるトピックのノートは題と `.state/capture_topic_notes.json` で分かる） |

## 2. 関係（本文のブロック）
`ParentBranch:` / `BranchGroup:` / `Group:` / `Context:` / `Related:` / `BackLink:`（と旧 `### …` 節）。向き・同期の規則は `docs/03-同期の規則.md`。`gnosis_graph.py` はこれを読んで型付きの辺にする（`group` `parent_branch` `branch_group` `child_branch` `context` `related` `backlink` `link` `folgezettel`）。読み取り専用で、ノートは書き換えない。

## 3. 曼荼羅ノート（9×9）
`mandala: true` のふつうの Markdown ノート。本文に**列名行つきの 9 行 9 列の表**（`| 1 | … | 9 |`、区切り行、9 行）。マスは `[文字](ノート.md)`（実ノートや別の曼荼羅）。主題は(行5・列5)、副題 8 つは中心ブロックの周囲と、周囲 8 ブロックの中心の 2 か所に同じ内容で置く（`:GnosisMandalaSync` が揃える。食い違いは変えず報告）。位置は 0 から数えて主題(4,4)、副題 (3,3)(3,4)(3,5)(4,5)(5,5)(5,4)(5,3)(4,3) ↔ 周囲の中心 (1,1)(1,4)(1,7)(4,7)(7,7)(7,4)(7,1)(4,1)。

## 4. タスク
本文の `- [ ]` / `- [x]` の行（コードブロックの中を除く）。印（Obsidian Tasks 互換）: `📅`/`due:` 期限（`YYYY-MM-DD` と任意の `HH:MM`）、`⏳`/`scheduled:`、`🛫`/`start:`、`✅`/`done:`、`🔁`/`repeat:`（daily・weekly・monthly・yearly・weekday・every N days|weeks|months|years）、`⏫🔼🔽`、`id:` と `after:`。別 DB は持たない。DECISIONS D004。

## 5. スマホ取り込み（`\M`）の記録（vault の `.state/`）
- `capture_imported.json`: `{"ids": {メモ id: 行き先}, "entries": {メモ id: 取り込んだ時点のスマホ側の全項目}}`。行き先はノートのファイル名、日記 `(diary:YYYY-MM-DD)`、まとめるトピック `(topic:名)` または `ノート.md#見出し`、時系列記録 `(record:名:YYYY-MM-DD)`。`entries` の本文が 3-way merge の **base**。旧版の記録（`entries` に本文が無い）は merge の対象外で、従来どおり重複防止だけ。
- `capture_conflicts/<メモ id>.json`: 競合の記録 `{id, file, base, remote, conflicts:[{base, remote, context}], entry}`。ノートは変えていない。`:GnosisCaptureResolve` で解決すると消える。
- `capture_topic_notes.json`（まとめるトピック→ノート）、`diary_days.json`（日付→日記ノート）。
- `capture_strip.log`: `:GnosisCaptureStripMeta apply` が消した `capture:` `capture_id:` `capture_topic:` `topic:` の記録（1 行 1 JSON。戻すときの手がかり）。
- 画像は vault の `capture-images/`。詳細は `docs/ANDROID_SYNC.md`。

## 6. 書き出し（`:GnosisExportSite`）
出力先に `.gnosis-export`（印）・各ノートの `.html`・`index.html`・`folgezettel.html`・`FOLGEZETTEL.md`（Markdown の番号表）・`cards/table/timeline/graph/fznav/search` の `.html`・データ（`notes-data.js` `graph-data.js` `fz-data.js` `search-index.js` は `window.GNOSIS_*` を代入する JS。`file://` で動くよう fetch を使わない）・`*.js`・`style.css`・参照された添付。全部派生物。

## 7. 派生データの保証
- vault のノートを書き換えない: グラフ・検査・Agenda（読む側）・書き出し・診断（`duplicates`、`backfill` の既定）。
- 書く操作は一時ファイル＋`os.replace`（`\M` の merge・競合解決・`mandala.py`・`tasks.py complete`・`backfill --apply`）。

## 8. キャンバス（`\A`。2026-10-21・DECISIONS D007）
```markdown
---
time: 2026-10-21 13:00:00
title: ハーブの図
canvas: true
---

# ハーブの図

（自由な本文。画面は触らない）

[ハーブ](h.md)
[ローズマリーを育ててみた](r.md)
```gnosis-canvas
{"nodes":[{"id":"n1","type":"note","file":"h.md","x":0,"y":0,"w":220,"h":110},{"id":"t1","type":"text","text":"考え","x":300,"y":0,"w":180,"h":70,"color":"#57ab5a"}],"edges":[{"id":"e1","from":"n1","to":"t1","label":"栽培"}]}
```
```
- `file` は vault からの相対パス。リンクの行はキャンバスのノートからの相対パスで、`\A` が保存のたびに書き直す（コードブロックの直前に続くリンクだけの行）。
- 壊れた JSON は空のキャンバスとして開き、保存で書き直す（開いたときに知らせる）。
