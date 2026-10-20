#!/usr/bin/env python3
"""vault の Git 連携（UT05）。状態・差分・履歴・過去の版の表示は読み取り専用。コミットは、メッセージを渡した明示の操作だけ。

- `git` は引数の配列で呼ぶ（シェルを通さない）。パスは vault の中のものだけ。`..`・絶対パス・ドット始まりのフォルダは拒否する。
- vault が Git リポジトリでなければ、そう伝えて何もしない（`git init` もしない）。
- 状態・コミットの対象は、ノートと添付だけ。`.state/` `.gnosis/` などドット始まりのフォルダは含めない（派生データ・個人の設定）。
- コミットは、変更のあるノート・添付だけを `git add` してから行う。push・pull・force などリモートへの操作はしない。
- 過去の版（`show`）は表示するだけ。ファイルへの書き戻し（復元）はしない（必要なら表示を見て自分で貼る）。

CLI（JSON。--md なら Markdown）:
  gitops.py ROOT status                    変更・追加・削除・未追跡のノート
  gitops.py ROOT diff [NOTE]               差分（NOTE を省くと全体）。--staged で git add 済みの分
  gitops.py ROOT log [NOTE] [--n N]        履歴（NOTE を省くと全体）
  gitops.py ROOT show NOTE REV             その版の内容
  gitops.py ROOT commit 'メッセージ'        変更のあるノート・添付をコミット
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

GIT_TIMEOUT = 60
STATUS_LABEL = {"M": "変更", "A": "追加", "D": "削除", "R": "名前変更", "C": "コピー", "?": "未追跡", "U": "競合", "T": "種類変更"}


def _git(root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    r = subprocess.run(["git", "-C", str(root), "-c", "core.quotepath=false", "-c", "color.ui=false", *args], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=GIT_TIMEOUT)
    if check and r.returncode != 0:
        raise ValueError("git: " + (r.stderr.strip() or r.stdout.strip() or f"終了コード {r.returncode}")[:300])
    return r


def _repo(root: str | Path) -> Path:
    root = Path(root).resolve()
    r = subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if r.returncode != 0:
        raise ValueError("この vault は Git リポジトリではありません（git init はしません）")
    top = Path(r.stdout.strip()).resolve()
    if top != root and top not in root.parents:
        raise ValueError("この vault は Git リポジトリではありません")
    return root


def _safe(root: Path, note: str) -> str:
    if not note or note.startswith("-") or "\x00" in note:
        raise ValueError("ノートの指定が正しくありません")
    p = (root / note).resolve()
    try:
        rel = p.relative_to(root)
    except ValueError:
        raise ValueError("vault の外は扱いません") from None
    if any(part.startswith(".") for part in rel.parts):
        raise ValueError("ドット始まりのフォルダは扱いません")
    return rel.as_posix()


def _visible(path: str) -> bool:
    return not any(part.startswith(".") for part in path.split("/"))


def status(root: str | Path) -> dict:
    root = _repo(root)
    out = _git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", ".").stdout
    items = []
    parts = out.split("\x00")
    i = 0
    while i < len(parts):
        e = parts[i]
        i += 1
        if len(e) < 4:
            continue
        xy, path = e[:2], e[3:]
        old = ""
        if "R" in xy or "C" in xy:                      # 名前変更は、次の要素が元の名前
            old = parts[i] if i < len(parts) else ""
            i += 1
        k = "?" if xy == "??" else (xy[1] if xy[1] != " " else xy[0])
        if not _visible(path):
            continue
        items.append({"path": path, "old": old, "code": xy, "kind": STATUS_LABEL.get(k, k), "staged": xy[0] not in " ?"})
    branch = _git(root, "rev-parse", "--abbrev-ref", "HEAD", check=False).stdout.strip()
    return {"branch": branch, "clean": not items, "changes": sorted(items, key=lambda x: x["path"])}


def diff(root: str | Path, note: str | None = None, staged: bool = False) -> dict:
    root = _repo(root)
    args = ["diff", "--no-ext-diff", "--no-color", "--unified=3"] + (["--staged"] if staged else [])
    args += ["--", _safe(root, note) if note else "."]
    text = _git(root, *args).stdout
    # ドット始まりのフォルダの差分は出さない(ファイル単位に分けて落とす)
    chunks = re.split(r"(?m)^(?=diff --git )", text)
    kept = [c for c in chunks if not c.strip() or _visible((re.match(r"diff --git a/(.*?) b/", c) or [None, "x"])[1])]
    text = "".join(kept)
    added = sum(1 for ln in text.split("\n") if ln.startswith("+") and not ln.startswith("+++"))
    removed = sum(1 for ln in text.split("\n") if ln.startswith("-") and not ln.startswith("---"))
    return {"note": note, "staged": staged, "diff": text, "added": added, "removed": removed, "empty": not text.strip()}


def log(root: str | Path, note: str | None = None, n: int = 20) -> dict:
    root = _repo(root)
    n = max(1, min(200, n))
    args = ["log", f"-{n}", "--date=short", "--pretty=format:%h%x1f%ad%x1f%an%x1f%s"]
    if note:
        args += ["--follow", "--", _safe(root, note)]
    r = _git(root, *args, check=False)
    if r.returncode != 0 and "does not have any commits" in r.stderr:
        return {"note": note, "commits": []}
    if r.returncode != 0:
        raise ValueError("git: " + r.stderr.strip()[:300])
    commits = []
    for ln in r.stdout.split("\n"):
        f = ln.split("\x1f")
        if len(f) == 4:
            commits.append({"rev": f[0], "date": f[1], "author": f[2], "subject": f[3]})
    return {"note": note, "commits": commits}


def show(root: str | Path, note: str, rev: str) -> dict:
    root = _repo(root)
    if not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z._/~^-]{0,80}", rev) or rev.startswith("-"):
        raise ValueError("版の指定が正しくありません")
    rel = _safe(root, note)
    r = _git(root, "show", f"{rev}:{rel}", check=False)
    if r.returncode != 0:
        raise ValueError("その版にこのノートはありません")
    return {"note": rel, "rev": rev, "content": r.stdout}


def commit(root: str | Path, message: str) -> dict:
    root = _repo(root)
    message = (message or "").strip()
    if not message or "\x00" in message:
        raise ValueError("コミットのメッセージを指定してください")
    st = status(root)
    paths = [c["path"] for c in st["changes"] if c["kind"] != "削除" and _visible(c["path"])]
    gone = [c["path"] for c in st["changes"] if c["kind"] == "削除"]
    if not st["changes"]:
        raise ValueError("コミットする変更がありません")
    if paths:
        _git(root, "add", "--", *paths)
    if gone:
        _git(root, "rm", "--cached", "--quiet", "--ignore-unmatch", "--", *gone)
    # 対象はノート・添付だけ。ドット始まりが誤ってステージされていたら外す
    staged = _git(root, "diff", "--cached", "--name-only", "-z").stdout.split("\x00")
    for f in [x for x in staged if x and not _visible(x)]:
        _git(root, "reset", "--quiet", "HEAD", "--", f, check=False)
    r = _git(root, "commit", "-m", message, check=False)
    if r.returncode != 0:
        raise ValueError("git: " + (r.stderr.strip() or r.stdout.strip())[:300])
    rev = _git(root, "rev-parse", "--short", "HEAD").stdout.strip()
    return {"rev": rev, "files": len(paths) + len(gone), "message": message}


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    if kind == "status":
        L = [f"# Git の状態（{r['branch']}）", ""] + ([f"- {c['kind']}: [{c['path']}]({c['path'].replace(' ', '%20')})" + ("（git add 済み）" if c["staged"] else "") for c in r["changes"]] or ["変更はありません。"])
    elif kind == "diff":
        L = [f"# 差分{(' — ' + r['note']) if r['note'] else ''}", "", f"+{r['added']} / -{r['removed']} 行", ""] + (["```diff", r["diff"].rstrip(), "```"] if not r["empty"] else ["差分はありません。"])
    elif kind == "log":
        L = [f"# 履歴{(' — ' + r['note']) if r['note'] else ''}", ""] + ([f"- `{c['rev']}` {c['date']} {c['subject']}（{c['author']}）" for c in r["commits"]] or ["まだコミットがありません。"])
    elif kind == "show":
        L = [f"# {r['note']} @ {r['rev']}", "", "```", r["content"].rstrip(), "```"]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        staged = "--staged" in argv
        a = [x for x in argv if x not in ("--md", "--staged")]
        n = 20
        if "--n" in a:
            i = a.index("--n"); n = int(a[i + 1]); del a[i:i + 2]
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "status":
            r = status(root)
        elif cmd == "diff":
            r = diff(root, rest[0] if rest else None, staged)
        elif cmd == "log":
            r = log(root, rest[0] if rest else None, n)
        elif cmd == "show":
            r = show(root, rest[0], rest[1])
        elif cmd == "commit":
            r = commit(root, rest[0])
            md = False
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
