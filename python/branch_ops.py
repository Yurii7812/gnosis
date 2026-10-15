#!/usr/bin/env python3
"""Branch（直接のブランチ）の追加と整合性の検査。

`b` で明示した「親 → 子」を、親の `### ChildBranch` と子の `### ParentBranch` の両方に書く。
識別子（タイトルやファイル名の `1a` など）から親子は推測しない。

守る規則:
  - 1 つのノートが持てる親は最大 1 つ（ChildBranch は複数可）。
  - 自分自身を親にも子にもできない。親子の循環（A → B → C → A）は作れない。
  - 子に別の親が既にあるときは拒否する（付け替えない・既存の親を消さない）。
  - 既に同じ親子関係があれば重複を作らない。片側だけ書かれていた場合は欠けた側だけ補う。
  - 変更前に両方のノートを検証し、問題がなければ 2 つのファイルを書く。片方の保存に失敗したら
    書いた側を元に戻す（片側だけ変わった状態を残さない）。拒否したときは何も書かない。
  - コードブロックの中の `### ChildBranch` は節として扱わない。本文は変更しない。
  - Vim で未保存の編集があるノート（sync-dirty マーカー）は触らない。

CLI（結果は 1 行の JSON）:
    branch_ops.py add   ROOT PARENT_FILE CHILD_FILE... [--dry-run]
    branch_ops.py check ROOT
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path
from urllib.parse import unquote

try:
    import note_format_v2 as nf
except ImportError:  # 実行ディレクトリ以外から import されたとき
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import note_format_v2 as nf

PB = nf.PARENT_BRANCH_MARK
CB = nf.CHILD_BRANCH_MARK
# 節の並び（小さいほど上）。旧 `### Parent` は Context と同じ位置。
_RANK = {PB: 0, nf.PARENT_BRANCH_MARK_LEGACY: 0, nf.CONTEXT_MARK: 1, nf.UP_MARK: 1, nf.GROUP_MARK: 2,
         nf.LEGACY_GROUP_MARK: 2, CB: 3, nf.CHILD_BRANCH_MARK_LEGACY: 3,
         nf.RELATED_MARK: 4, nf.RELATED_MARK_LEGACY: 4, nf.BACKLINK_MARK: 5, nf.DOWN_MARK: 5}


# ---------------------------------------------------------------------------
# 読み取り
# ---------------------------------------------------------------------------

def note_title(text: str, path: Path) -> str:
    """タイトル: front matter の title → 最初の H1（コードブロック外）→ ファイル名（拡張子なし）。"""
    lines = text.split("\n")
    fm, rest = nf._split_front_matter(lines)
    t = nf._fm_title(fm)
    if t:
        return t
    for ln, fz in zip(rest, nf._fenced(rest)):
        if fz:
            continue
        if ln.startswith("# "):
            h = ln[2:].strip()
            if h:
                return h
    return path.stem


def _resolve(target: str, base: Path, known: set[str]) -> Path | None:
    tg = target.split("#", 1)[0].strip()
    if not tg.lower().endswith(".md"):
        return None
    for cand in (tg, unquote(tg)):
        p = Path(os.path.normpath(cand if cand.startswith("/") else os.path.join(str(base), cand)))
        if str(p) in known:
            return p
    return None


class Vault:
    """vault 内の全ノートを読み、Branch の親子関係を求める。"""

    def __init__(self, root) -> None:
        self.root = Path(root).resolve()
        self.texts: dict[Path, str] = {}
        self.parsed: dict[Path, dict] = {}
        for p in nf._iter_md(self.root):
            rp = Path(os.path.normpath(str(p.resolve())))
            try:
                text = p.read_text(encoding="utf-8")
            except OSError:
                continue
            self.texts[rp] = text
            self.parsed[rp] = nf._simple_parse_text(rp, text)
        known = {str(p) for p in self.parsed}
        # 宣言: {ノート: [親…]}（自分の ParentBranch）と {ノート: [子…]}（自分の ChildBranch）
        self.declared_parents: dict[Path, list[Path]] = {}
        self.declared_children: dict[Path, list[Path]] = {}
        for p, n in self.parsed.items():
            for key, store in (("pbranch", self.declared_parents), ("cbranch", self.declared_children)):
                out: list[Path] = []
                for _d, tg in nf._links_from(n[key]):
                    rp = _resolve(tg, p.parent, known)
                    if rp is not None and rp not in out:
                        out.append(rp)
                store[p] = out

    def parents(self, p: Path) -> list[Path]:
        """p の親（自分の ParentBranch と、相手の ChildBranch に p があるものの和集合）。"""
        out = list(self.declared_parents.get(p, []))
        for q, kids in self.declared_children.items():
            if p in kids and q not in out:
                out.append(q)
        return out

    def ancestors(self, p: Path) -> set[Path]:
        seen: set[Path] = set()
        stack = [p]
        while stack:
            cur = stack.pop()
            for q in self.parents(cur):
                if q not in seen:
                    seen.add(q)
                    stack.append(q)
        return seen

    def title(self, p: Path) -> str:
        """利用者に見せるタイトル（front matter の title → 最初の H1 → ファイル名）。"""
        return note_title(self.texts.get(p, ""), p)

    def link_title(self, p: Path) -> str:
        """リンクの表示名。sync が表示名を合わせるタイトル（front matter の title → ファイル名）と同じにする。"""
        return self.parsed[p]["title"]


# ---------------------------------------------------------------------------
# 検査
# ---------------------------------------------------------------------------

def check(root) -> dict:
    """手編集などで壊れた状態を報告する（何も書き換えない・片方を消さない）。"""
    v = Vault(root)
    issues: dict[str, list] = {"multi_parent": [], "one_sided": [], "cycle": [], "self": []}
    rel = lambda p: str(p.relative_to(v.root))  # noqa: E731
    for p in v.parsed:
        ps = v.parents(p)
        if p in ps or p in v.declared_children.get(p, []):
            issues["self"].append(rel(p))
        if len(ps) > 1:
            issues["multi_parent"].append({"note": rel(p), "parents": [rel(q) for q in ps]})
        for q in v.declared_parents.get(p, []):
            if p not in v.declared_children.get(q, []):
                issues["one_sided"].append({"parent": rel(q), "child": rel(p), "missing": "ChildBranch"})
        for c in v.declared_children.get(p, []):
            if p not in v.declared_parents.get(c, []):
                issues["one_sided"].append({"parent": rel(p), "child": rel(c), "missing": "ParentBranch"})
        if p in v.ancestors(p):
            issues["cycle"].append(rel(p))
    issues["ok"] = not any(issues[k] for k in ("multi_parent", "one_sided", "cycle", "self"))
    return issues


# ---------------------------------------------------------------------------
# 書き込み（テキストの挿入。本文・他の節は 1 バイトも変えない）
# ---------------------------------------------------------------------------

def _section_starts(lines: list[str]) -> list[tuple[int, str]]:
    fm, _rest = nf._split_front_matter(lines)
    start = len(fm)
    out: list[tuple[int, str]] = []
    for i, (ln, fz) in enumerate(zip(lines, nf._fenced(lines))):
        if i < start or fz:
            continue
        s = ln.strip()
        if s in _RANK:
            out.append((i, s))
    return out


def insert_link(text: str, mark: str, link_line: str) -> str:
    """text の `mark` の節の最後にリンク行を足す。節が無ければ正しい位置に節ごと作る。"""
    lines = text.split("\n")
    had_nl = text.endswith("\n")
    if had_nl:
        lines.pop()
    secs = _section_starts(lines)
    # 旧形式の見出し（### ChildBranch など）の節があれば、それに足す（同じ節を新旧 2 つに分けない）
    mine = [i for i, m in secs if nf.LEGACY_TO_NEW_MARK.get(m, m) == mark]
    if mine:
        start = mine[0]
        nxt = [i for i, _m in secs if i > start]
        end = min(nxt) if nxt else len(lines)
        j = end
        while j > start + 1 and lines[j - 1].strip() == "":
            j -= 1
        lines.insert(j, link_line)
    else:
        later = [i for i, m in secs if _RANK[m] > _RANK[mark]]
        if later:
            pos = min(later)
        elif not secs:
            # 節がまだ無いノート: 本文の末尾の空行（新しいノートの書き出し用の余白）はそのまま残す
            pos = len(lines)
        else:
            pos = len(lines)
            while pos > 0 and lines[pos - 1].strip() == "":
                pos -= 1
            del lines[pos:]
        block = [mark, link_line]
        # 本文のすぐ後ろ（最初の節になるとき）は、本文との間に空行を 1 つ確保する
        first_section = not secs or pos <= min(i for i, _m in secs)
        if first_section and pos > 0 and lines[pos - 1].strip() != "":
            block = [""] + block
        lines[pos:pos] = block
    return "\n".join(lines) + "\n"


def _link(from_dir: Path, target: Path, title: str) -> str:
    # 表示名は sync（_preserve_parent）と同じ書き方（エスケープしない）にして、同期で揺らがないようにする
    return f"[{title}]({nf._rel(from_dir, target)})"


def _digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _atomic_pair_write(plan: list[tuple[Path, str, str]]) -> None:
    """plan = [(path, 元の内容, 新しい内容)]。全部を書けなければ元に戻して例外を投げる。"""
    tmps: list[tuple[Path, Path]] = []
    done: list[tuple[Path, str]] = []
    try:
        for p, _old, new in plan:
            tmp = p.with_name(f".{p.name}.branch-{os.getpid()}.tmp")
            tmp.write_text(new, encoding="utf-8")
            tmps.append((tmp, p))
        for p, old, _new in plan:  # 直前の再確認: 計画のあとで誰かが書き換えていたら何も置き換えない
            if _digest(p.read_text(encoding="utf-8")) != _digest(old):
                raise RuntimeError("conflict:" + p.name)
        for tmp, p in tmps:
            old = next(o for q, o, _n in plan if q == p)
            os.replace(tmp, p)
            done.append((p, old))
    except Exception:
        for p, old in reversed(done):
            try:
                p.write_text(old, encoding="utf-8")
            except OSError:
                pass
        raise
    finally:
        for tmp, _p in tmps:
            try:
                if tmp.exists():
                    tmp.unlink()
            except OSError:
                pass


def _result(ok: bool, code: str, **kw) -> dict:
    return {"ok": ok, "code": code, **kw}


def _norm(p) -> Path:
    return Path(os.path.normpath(str(Path(p).resolve())))


def _check_pair(v: Vault, parent: Path, child: Path) -> dict | None:
    """この組を足せないとき、その理由（拒否の結果）を返す。足せるなら None。"""
    if parent == child:
        return _result(False, "self", parent=str(parent), child=str(child))
    for p in (parent, child):
        if p not in v.parsed:
            return _result(False, "missing", path=str(p))
        if p.name == "index.md":
            return _result(False, "index", path=str(p))
    ps = v.parents(child)
    if len(ps) > 1:
        return _result(False, "multi_parent", child=str(child), title=v.title(child),
                       parents=[{"path": str(q), "title": v.title(q)} for q in ps])
    others = [q for q in ps if q != parent]
    if others:
        q = others[0]
        return _result(False, "has_parent", child=str(child), title=v.title(child),
                       parent=str(q), parent_title=v.title(q))
    if child in v.ancestors(parent):
        return _result(False, "cycle", parent=str(parent), child=str(child))
    return None


def add_branches(root, parent_file, child_files, dry_run: bool = False) -> dict:
    """parent_file の ChildBranch に child_files を、各 child の ParentBranch に parent_file を入れる。

    code: added / already / self / cycle / has_parent / multi_parent / index / missing / dirty / conflict / error
    1 つでも足せない子がいれば全体を拒否し、どのファイルも変更しない（部分的な追加をしない）。
    """
    try:
        # 同じ vault の同期と順番にする（別の vault とは何も共有しない）
        with nf.vault_lock(root, 20.0) as got:
            if not got:
                return _result(False, "conflict", path="(sync)")
            return _add_branches_locked(root, parent_file, child_files, dry_run)
    except RuntimeError as e:
        if str(e).startswith("conflict:"):
            return _result(False, "conflict", path=str(e)[9:])
        return _result(False, "error", message=str(e))
    except OSError as e:
        return _result(False, "error", message=str(e))


def _add_branches_locked(root, parent_file, child_files, dry_run: bool = False) -> dict:
    try:
        v = Vault(root)
        parent = _norm(parent_file)
        children: list[Path] = []
        for c in child_files:
            nc = _norm(c)
            if nc not in children:
                children.append(nc)
        if not children:
            return _result(False, "missing", path="")
        for child in children:
            bad = _check_pair(v, parent, child)
            if bad is not None:
                return bad
        todo_cb = [c for c in children if c not in v.declared_children.get(parent, [])]
        todo_pb = [c for c in children if parent not in v.declared_parents.get(c, [])]
        if not todo_cb and not todo_pb:
            return _result(True, "already", parent=str(parent), child=str(children[0]), changed=[])
        touched = ([parent] if todo_cb else []) + todo_pb
        for p in touched:
            if nf._editor_has_unsaved_changes(p):
                return _result(False, "dirty", path=str(p))
        plan: list[tuple[Path, str, str]] = []
        if todo_cb:
            old = v.texts[parent]
            new = old
            for c in todo_cb:
                new = insert_link(new, CB, _link(parent.parent, c, v.link_title(c)))
            plan.append((parent, old, new))
        for c in todo_pb:
            old = v.texts[c]
            plan.append((c, old, insert_link(old, PB, _link(c.parent, parent, v.link_title(parent)))))
        if dry_run:
            return _result(True, "added", parent=str(parent), child=str(children[0]), changed=[], dry_run=True)
        _atomic_pair_write(plan)
        return _result(True, "added", parent=str(parent), child=str(children[0]),
                       children=[str(c) for c in children], changed=[str(p) for p, _o, _n in plan])
    except RuntimeError as e:
        if str(e).startswith("conflict:"):
            return _result(False, "conflict", path=str(e)[9:])
        return _result(False, "error", message=str(e))
    except OSError as e:
        return _result(False, "error", message=str(e))


def add_branch(root, parent_file, child_file, dry_run: bool = False) -> dict:
    return add_branches(root, parent_file, [child_file], dry_run)


def main(argv: list[str]) -> int:
    if len(argv) >= 5 and argv[1] == "add":
        rest = [a for a in argv[4:] if a != "--dry-run"]
        r = add_branches(argv[2], argv[3], rest, dry_run="--dry-run" in argv[4:])
        print(json.dumps(r, ensure_ascii=False))
        return 0 if r["ok"] else 1
    if len(argv) >= 3 and argv[1] == "check":
        r = check(argv[2])
        print(json.dumps(r, ensure_ascii=False))
        return 0 if r["ok"] else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
