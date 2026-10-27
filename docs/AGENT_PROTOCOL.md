# 複数の AI で並行して作業するときの取り決め

Codex・Claude Code など、複数の AI が**同じ PC の同じリポジトリ**で同時に作業しても、お互いの作業を壊さず、
`main` を壊さず、実 vault に触らないための取り決め。補助スクリプトは `tools/agents`、回帰網は `test/agents_net.sh`。

## 1. 基本の考え方
- **1 つの作業 = 1 つの worktree + 1 つのブランチ + 1 つの担当宣言。** AI どうしは、別々の作業ツリーで動く。
- **`~/gnosis`（本体の checkout）では作業しない。** 利用者が使っている場所で、書きかけがあるかもしれない。AI は触らず、`main` に追いつかせるのは `ship` だけが行う（クリーンなときだけ）。
- **`main` を進めてよいのは `tools/agents ship` だけ。** 順番待ち（ロック）→ `origin/main` へ rebase → ff-only で push。merge コミットは作らない（履歴は直線）。
- **仲介はリモート（`origin/main`）。** 手元の `main` ではなく `origin/main` を基準にする。
- 時間をかけない流れ（`AGENTS.md`）はそのまま守る: 作業中は関係する試験だけ → 区切りまでまとめて → 最後に並列で 1 回 → まとめてマージ。

## 2. 作業の流れ

```
tools/agents start fz-view --agent codex --desc "Folgezettel ビューの [ ]" --area autoload/gnosis/fznav.vim
eval "$(tools/agents env fz-view)"      # TMPDIR・GNOSIS_HOME を隔離して worktree へ移る
… 直す・関係する試験（sh test/related.sh）…
git commit …                            # 小さく。末尾に Co-Authored-By
tools/agents ship fz-view --test        # 並列で全体を 1 回 → 順番待ち → rebase → main へ ff-only
```

- `start 名前`: `~/src/gnosis-名前` に worktree と、ブランチ `agent/名前` を作る。名前は小文字の英数字とハイフン。**同じ名前は使えない**（先に始めた AI のもの）。
- `--area`: 触る予定のファイル・ディレクトリ。他の作業と重なれば警告が出る。**警告が出たら、直す前に相談するか範囲を分ける**（利用者に確認するか、後から始めた方が別の作業に回る）。後から足すのは `tools/agents area 名前 パス…`。
- `list`: 誰が・どこで・何をしているか、未コミットの数、`main` より進んだ数・遅れた数。始める前に必ず見る。
- `sync 名前`: `origin/main` を取り込む（rebase）。長く続く作業は、時々行って遅れを小さくする。
- `ship 名前 [--test] [--ci]`:
  - `--test` … 反映の前に `test/run_parallel.sh` を流す。**通らなければ反映しない。**
  - `--ci` … ブランチを push して PR を作り、CI（`.github/workflows/gnosis-regression.yml`。PR のときだけ動く）が通ってから反映する。
  - 順番待ちの間に他の作業が `main` を進めていたら、取り込んだあと `test/related.sh` を流し直す。通らなければ反映しない。
  - **衝突したら終了コード 2 で止まる。** `main` は変わらず、rebase も途中のまま残さない。案内に従って手で解決し、もう一度 `ship`。
  - 反映できたら、worktree・ブランチ（手元と `origin`）・担当宣言を片づける。
- `done 名前 [--force]`: やめる／片づける。`main` に反映されていないコミットがあれば `--force` が要る（破棄）。

## 3. 隔離（お互いの試験を邪魔しない）
- 試験は**必ず** `eval "$(tools/agents env 名前)"` のあとに流す。`TMPDIR=~/gnosis-work/test/名前`・`GNOSIS_HOME` はその下の一時ディレクトリ。別の AI の試験の一時ファイルと混ざらない。
- GUI の試験は `GNOSIS_GUI_PORT_BASE`（名前から決まる 20000〜39999）を使う。同じポートを取り合わない。
- **プロセスは名前で kill しない**（他の AI の Vim・アプリを落とす）。自分が起動したものは PID で止める。
- **実 vault・Gnosis ホームに触らない**（読み書きとも）。暗号化 vault のロックを開ける・閉じるのも、利用者が言ったときだけ。
- 本物のクリップボード・IME・ウィンドウのフォーカスを操作しない（`test/noclip.sh`）。

## 4. 衝突しやすいファイルの扱い
複数の AI が同時に直しやすい所。**先に取った方が書き、後の方が合わせる。**

| ファイル | やり方 |
| --- | --- |
| `guide/ja.md` と `guide/en.md` | **必ず対で直す**（行が対応する。`python3 test/check_guide.py`）。衝突したら両方を並べて、行の対応を保つ |
| `i18n/en.json` | キーを足すだけ。衝突したら両方の追加を残す（重複キーを作らない。`python3 test/i18n_check.py`） |
| `test/api_public.txt` | merge しない。衝突したら捨てて、`sh test/run.sh` の出力（`vim_api_check.vim`）で作り直す |
| `docs/PROGRESS.md` | 自分の項目を足すだけ。衝突したら両方残す |
| `test/known_ng.txt` | 増やすのは利用者の許可を取ってから |
| `autoload/gnosis.vim` | 巨大。関数単位で直し、広い整形・並べ替えをしない（衝突が広がる） |

- 他の AI が触っている範囲のファイル（`tools/agents list` の範囲）は、整形・名前変更・移動をしない。
- 公開関数を足したら `test/api_public.txt` を作り直す。ガイドに載っていないキー・コマンドを足したら、ガイドも直す（`check_guide.py` が落ちる）。

## 5. 困ったとき
- **「担当が重なる」と出た** … `tools/agents list` で相手の説明と範囲を見る。同じファイルを同時に直すと、`ship` のどちらかが衝突で止まる。範囲を分けるか、相手が `ship` してから `sync` して始める。
- **`ship` が順番待ちで止まる** … 他の AI が反映中。最大 20 分待つ。待っても来なければ `~/gnosis-work/agents/merge.lock` を見る（反映中のプロセスがあるか）。
- **`ship` が衝突で止まった** … `git -C ~/src/gnosis-名前 rebase origin/main` を手で進め、衝突を直して `git rebase --continue`。もう一度 `tools/agents ship 名前`。解決できなければ、利用者に聞く。
- **worktree が消えた・担当だけ残った** … `tools/agents list` に「消えている」と出る。`tools/agents done 名前 --force`。
- **`~/gnosis` に他の AI の書きかけ（未コミット）がある** … 消さない。内容を自分のブランチへ取り込んでから進めるか、利用者に聞く。
- 反映が済んでいない作業を**途中で投げ出さない**。続けられないときは、ブランチを push し、`docs/PROGRESS.md` に状況を書く。

## 6. 登録簿の形
`~/gnosis-work/agents/<名前>.claim`（`key=value` の行）。リポジトリの外なので、コミットされず、すべての AI が同じものを見る。

```
agent=codex
branch=agent/fz-view
worktree=/home/yurii/src/gnosis-fz-view
started=1793080410
desc=Folgezettel ビューの [ ]
areas=autoload/gnosis/fznav.vim autoload/gnosis/mview.vim
base=<開始時のコミット>
```
`merge.lock` は `ship` の順番待ちに使う（`flock`）。
