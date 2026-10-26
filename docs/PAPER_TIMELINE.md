# 紙の日記の木と Paper-Zettelkasten-Index を、グループにしない設計へ（2026-10-26 実装済み）

2026-10-26 の相談で決まった方針: **紙の日記の木も、デジタルの日記の木（`python/diary_tree.py`）と同じく、グループではない普通のノートにする。
`Paper-Zettelkasten-Index` 自体も普通のノートにする。** `\F` の `t` で出るトピックは今までどおり BranchGroup のグループ。

## 今の形（`python/paper_pkm.py`）
- `Paper-Zettelkasten-Index.md`（`attribute: group`）… 本文にキーワード（グループ）へのリンク。
- 紙の日記: キーワード「日記」（グループ・題 `日記`/`紙の日記`）→ 月（題 `YYYY-MM`・グループ）→ 日（`paper_diary: YYYY-MM-DD` の普通のノート）。
  年（題 `YYYY`・グループ）は、日記が 2 つ以上の年にまたがってから。
- 月・年・日記はグループなので Folgezettel の番号が付かず、「groupでgroupを作れない」の制約にも当たる。
- デジタル日記の月（題 `YYYY-MM`）と同じ題になる。見分けはリンク先（`paper_diary_groups()`）で、壊れやすい。

## 新しい形
```
Paper-Zettelkasten-Index       … 普通のノート（timeline: true）。Index の本文に載る
  紙の日記                    … 普通のノート。ParentBranch: Paper-Zettelkasten-Index
    2026-紙                   … 年（日記が 2 つ以上の年にまたがってから）。ParentBranch: 紙の日記
      2026-10-紙              … 月。ParentBranch: 年（年が無ければ 紙の日記）
        2026-10-13-TU         … その日のノート（paper_diary: 2026-10-13）。ParentBranch: 月
  キーワード（BranchGroup）    … 今までどおりのグループ。Paper-Zettelkasten-Index の BranchGroup: に載る
```
- 題の付け方は夢の木（`2026-夢` / `2026-10-夢`）と同じ。デジタル日記の月と題がぶつからないので、リンク先で見分ける必要がなくなる。
- 木のノートは front matter に `timeline: true`、グループの印（`attribute: group`）は持たない。
  親の `ChildBranch:` と子の `ParentBranch:` は同期（`note_format_v2.py` の timeline の規則）がそろえる。Folgezettel の番号も付く。
- 本文の子の一覧は、デジタル日記と同じく `ChildBranch:` に書く（本文に重ねない）。
- 年の作り方は今の規則のまま（2 つ以上の年にまたがってから。月の親が年に替わったら同期が番号を振り直す）。

## 変えるところ
1. `paper_pkm.build_diary_hierarchy()` / `_write_diary_group()`: グループではなく木のノートを作る（題 `YYYY-紙` / `YYYY-MM-紙`、`timeline: true`、ParentBranch）。
2. `paper_pkm.find_diary_group()` / `paper_diary_groups()`: 題 `紙の日記` と `timeline: true` と `paper_diary` のリンクで見つける。
3. `Paper-Zettelkasten-Index.md` の作成・再生成: `attribute: group` を付けない。`timeline: true`。キーワードは BranchGroup: で結ぶ。
4. 移行 `paper_pkm.py migrate-tree ROOT [--dry-run]`（`diary_tree.py migrate` と同じ作り）: 今のグループの木を新しい形に直す。何度流しても同じ結果（冪等）。
   `\f` / `\F` が最初に開いたとき自動で走る。直す前に vault のバックアップ（tar.gz）を作る。
5. `\F` の `d`（日記として登録）: 新しい木に日を入れる。
6. 試験: `python/test_paper_pkm.py`・`test_paper_branchgroup.py` などの期待を新しい形に直し、移行の試験を足す。

## 確認したいこと
- 題の付け方: 年 `2026-紙`、月 `2026-10-紙`、一番上 `紙の日記` でよいか（夢と同じ付け方）。
- 移行は自動で走らせるか、手で `migrate-tree` を流すか（本物の vault は暗号化されていて、ロック中は触れない）。
- キーワードのグループ（BranchGroup）の置き場所は、Paper-Zettelkasten-Index の `BranchGroup:` でよいか。

## 決まった形（実装）
```
index.md ─ Paper-Zettelkasten-Index（普通のノート・Paper-Zettelkasten.md）
              BranchGroup: Paper-Zettelkasten-Index（グループ・キーワードは全部ここ）/ Index-write / Folgezettel-Index
              ChildBranch: （空）
Folgezettel-Index（グループ）の一番上: 日記 → 紙の日記（普通のノート）> 2026-紙 > 2026-10-紙 > 2026-10-13-TU
```
- 旧い形（グループの 日記 / 年 / 月）は regen のたびに同じファイルのまま新しい形に直る（`build_diary_tree`）。冪等。
- 頂点のノートは `ensure_paper_top`。`index.md` のグループへのリンクは頂点へ張り替える。`\f` は今までどおりグループを開く。
- 未確認: 本物の vault（暗号化・ロック中）。試験は一時 vault だけ。
