# Gnosis — エージェント共通の作業規則（Codex・Claude Code など）

Claude Code 向けの入口は `CLAUDE.md`。ここは Codex など `AGENTS.md` を読むエージェントにも同じ規則を守らせるためのもの。
仕様・現在地は `CLAUDE.md` に挙げた文書（`docs/PROGRESS.md` など）を先に読む。

## 進め方
- 返答・コミット・文書は日本語。コミットは小さく。
- 調査・修正・試験は、まずローカルでまとめて終える。GitHub への書き込み（コミット・ブランチ・PR・push）を途中で細かく繰り返さない。
- **複数の AI が同時に動くことがある。** 作業の始め方・反映の仕方は `docs/AGENT_PROTOCOL.md` と `tools/agents`（`start` で専用の worktree とブランチを作り、担当を宣言する → 作業 → `ship` で順番待ち・rebase・ff-only で `main` へ）。始める前に `tools/agents list` で他の作業を見る。
- 作業は worktree（`~/src/gnosis-*`）で行う。`~/gnosis` の作業ツリーに他のエージェントの書きかけ（未コミット）があれば、消さずに、内容を自分のブランチへ取り込んでから進める。
- マージは最後。**試験が通ってから** `main` へ ff-only でマージして push する。先にマージしない。依頼にマージまで含まれていれば、再確認せず進める。
- **時間をかけない流れ（Codex もこれに従う）**: ① 作業中は関係する試験だけ（`test/related.sh`）を流す。② 区切りまで、直す・調べるをまとめて進める（そのたびに全試験・マージをしない）。③ 最後に `test/run_parallel.sh` を **1 回だけ**回す（直列の `sh test/run.sh` を何度も回さない。API 一覧など `run.sh` でしか見ない所を直したときだけ最後に 1 回）。④ 通ったら、まとめて `main` へ ff-only でマージして push。途中でマージしない・細かく push しない。
- GitHub の CI（`.github/workflows/gnosis-regression.yml`）は **pull request のときだけ**動く。マージを依頼されたら、ブランチを push して PR を作り、CI が通ってから ff-only でマージする。
- 破壊的操作（実 vault の書換・削除・force push・外部通信・課金）は止まって確認。それ以外は確認なしで進める。

## 試験
- 場所は必ず `~/gnosis-work/test`（`TMPDIR`）と一時の `GNOSIS_HOME`。**本物の vault・Gnosis ホームに触らない。プロセスは名前で kill しない。**
- 試験は `test/noclip.sh` で入力・デスクトップも隔離する。単独の Vim/GUI 試験でも本物の IME（`fcitx*-remote` など）・クリップボード・ウィンドウのフォーカスを操作しない。表示接続を外すだけでは D-Bus 経由の IME 操作は防げない。
- 小さな直し: `test/related.sh`（変えたファイルに関係する試験だけを同時に流す。共通部分が変わっていれば自動で全部）。
- 大きな直し・マージ前: `test/run_parallel.sh`（約 3〜6 分。同時に 12 本。落ちたものは 1 本ずつ流し直し、それでも落ちるものだけ失敗にする。`test/known_ng.txt` の既知の失敗は数えない）。API 一覧などを含む全体は `sh test/run.sh`（直列で遅い）。
- 言語の既定は英語。日本語の画面を確かめる試験は `GNOSIS_LANG=ja` で流す（`run.sh` は自動で ja）。
- 時々落ちる試験がある（`record_net` は深夜（0〜5 時台）に落ちやすい時刻依存。変更前の main でも落ちる。`requests_1020b` は変更前の main でも半々で落ちる。`theme_pty_check`・`mview_panel_pty_check` は重いと落ちる）。流し直しで通れば問題なし。調べ直さない。
- 未実施の試験は未実施と書く。スタブを「実装済み」と書かない。

## 見た目の言葉
- 画面の文言は日本語と英語の両方に対応する（`i18n/en.json`、Vim は `gnosis#i18n#tr`）。ノートの解析に使う見出し・キー名（`Group:` など）は翻訳しない。
