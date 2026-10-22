#!/usr/bin/env python3
"""古い形（Index に索引＝グループを直接張る）を、Index → 最初のノート → BranchGroup の索引 に直す。

ダブルインデックスは「Global Index → 最初のノート → BranchGroup（トピック索引）→ ノート」。
昔の vault には Index の本文にグループが直接載っているものがある。それぞれのグループについて:
  1. 最初のノートを決める: そのグループを BranchGroup: に持つノートが既にあればそれ。
     無ければ、グループの項目のうち**いちばん古い**ノート（front matter の time:。同じなら名前順）。
  2. Index の本文のリンクの行先を、グループから最初のノートへ付け替える（索引語＝リンクの文字はそのまま）。
  3. 最初のノートの BranchGroup: にそのグループを足す（グループは親と同じ Folgezettel になる。同期が振る）。
  4. グループの項目のうち、親（Branch）がまだ無いノートを、最初のノートの子（ParentBranch / ChildBranch）にする。
     （Folgezettel は Branch の形で振り直される。すでに別の親がある項目・索引は触らない）
  5. 同期（note_format_v2 update）で、Group: / BackLink / Folgezettel をそろえる。

CLI（結果は JSON）:
    index_migrate.py plan  ROOT                          何も書かない。グループごとの計画
    index_migrate.py apply ROOT BACKUP_DIR               バックアップ（tar.gz）を取ってから実行
実行前に、vault を開いている Vim・アプリが無いこと（未保存の編集の衝突を避ける）を確かめる。
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tarfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import branch_ops as bo  # noqa: E402
import folgezettel as fz  # noqa: E402
import gnosis_graph as gg  # noqa: E402
import note_format_v2 as nf  # noqa: E402

_LINK = re.compile(r"(\[(?:\\.|[^\]\\])*\]\()([^)]+)(\))")


def _members(g, gid: str) -> list[str]:
    seen: list[str] = []
    for e in g.edges:
        if e.src == gid and e.kind == "link" and e.dst not in seen and not g.nodes[e.dst].is_group:
            seen.append(e.dst)
    return seen


def plan(root) -> list[dict]:
    """Index に直接載っているグループごとの計画 [{group, title, entry, why, children, skipped}]。"""
    root = Path(root).resolve()
    g = gg.build(root)
    idx = "index.md"
    if idx not in g.nodes:
        return []
    direct: list[str] = []
    for e in g.edges:
        if e.src == idx and e.kind == "link" and e.dst != idx and g.nodes[e.dst].is_group and e.dst not in direct:
            direct.append(e.dst)
    v = bo.Vault(root)
    out = []
    for gid in direct:
        mem = _members(g, gid)
        owners = [e.src for e in g.edges if e.dst == gid and e.kind == "branch_group" and not g.nodes[e.src].is_group]
        if owners:
            entry, why = owners[0], "このグループを BranchGroup に持つノートが既にある"
        elif mem:
            entry, why = min(mem, key=lambda m: (g.nodes[m].time or "9999", m)), "グループの項目でいちばん古いノート"
        else:
            out.append({"group": gid, "title": g.nodes[gid].title, "entry": None, "why": "項目が無いので変えない",
                        "children": [], "skipped": []})
            continue
        children, skipped = [], []
        for m in mem:
            if m == entry:
                continue
            bad = bo._check_pair(v, root / entry, root / m)
            if bad is None:
                children.append(m)
            else:
                skipped.append({"note": m, "title": g.nodes[m].title, "code": bad.get("code", "")})
        out.append({"group": gid, "title": g.nodes[gid].title, "entry": entry, "entry_title": g.nodes[entry].title,
                    "why": why, "children": children, "skipped": skipped})
    return out


def _edit_index(root: Path, items: list[dict]) -> list[str]:
    """Index の本文で、グループへのリンクの行先を最初のノートへ付け替える。付け替えた行の一覧を返す。"""
    ip = root / "index.md"
    text = ip.read_text(encoding="utf-8")
    by_name = nf._index(root)
    want = {root / it["group"]: root / it["entry"] for it in items if it["entry"]}
    changed: list[str] = []
    out_lines = []
    flags = nf._fenced(text.split("\n"))
    for ln, fenced in zip(text.split("\n"), flags):
        if not fenced:
            def sub(m):
                t = m.group(2).split(" ", 1)[0].strip("<>")
                if "://" in t or t.startswith(("mailto:", "#", "memo:")):
                    return m.group(0)
                hit = nf._resolve(t, ip.parent, root, by_name)
                if hit is not None and hit.resolve() in {k.resolve() for k in want}:
                    new = next(v for k, v in want.items() if k.resolve() == hit.resolve())
                    changed.append(ln.strip())
                    return m.group(1) + nf._rel(ip.parent, new) + m.group(3)
                return m.group(0)
            ln = _LINK.sub(sub, ln)
        out_lines.append(ln)
    new_text = "\n".join(out_lines)
    if new_text != text:
        ip.write_text(new_text, encoding="utf-8")
    return changed


def _add_branch_group(root: Path, entry: str, group: str, title: str) -> bool:
    """最初のノートの BranchGroup: にグループのリンクを足す（既にあれば何もしない）。"""
    ep = root / entry
    text = ep.read_text(encoding="utf-8")
    link = bo._link(ep.parent, root / group, title)
    d = nf._simple_parse_text(ep, text)
    gp = (root / group).resolve()
    by_name = nf._index(root)
    for ln in d["body"] + [x for x in text.split("\n")]:
        m = _LINK.search(ln)
        if m and ln.strip().startswith("["):
            t = m.group(2).split(" ", 1)[0].strip("<>")
            hit = nf._resolve(t, ep.parent, root, by_name)
            if hit is not None and hit.resolve() == gp and _in_branch_group(text, ln):
                return False
    lines = text.split("\n")
    had_nl = text.endswith("\n")
    if had_nl:
        lines.pop()
    new = bo._insert_top_block_link(lines, nf.BRANCH_GROUP_HEAD, link) + ("\n" if had_nl else "")
    ep.write_text(new, encoding="utf-8")
    return True


def _in_branch_group(text: str, line: str) -> bool:
    lines = text.split("\n")
    for i, ln in enumerate(lines):
        if ln.strip() == nf.BRANCH_GROUP_HEAD:
            j = i + 1
            while j < len(lines) and nf._SIMPLE_LINK_LINE_RE.match(lines[j]):
                if lines[j] == line:
                    return True
                j += 1
    return False


def _backup(root: Path, backup_dir: Path) -> Path:
    backup_dir.mkdir(parents=True, exist_ok=True)
    dest = backup_dir / ("vault-backup-%s.tar.gz" % time.strftime("%Y%m%d-%H%M%S"))
    with tarfile.open(dest, "w:gz") as tf:
        tf.add(str(root), arcname=root.name)
    return dest


def _vault_is_open(root: Path) -> list[str]:
    """この vault のファイルを開いている Vim などがあれば、そのコマンド行の一覧（/proc を見る）。"""
    found = []
    me = os.getpid()
    for p in Path("/proc").glob("[0-9]*"):
        try:
            if int(p.name) == me:
                continue
            cmd = (p / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
        except (OSError, ValueError):
            continue
        if str(root) in cmd and re.search(r"\b(vim|nvim|gvim|electron)\b", cmd.split(" ", 1)[0] + " " + cmd[:200]):
            found.append(cmd[:160])
    return found


def _sync(root: Path) -> None:
    subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "note_format_v2.py"), "update", str(root)],
                   check=True, capture_output=True)


def apply(root, backup_dir, allow_open: bool = False) -> dict:
    root = Path(root).resolve()
    items = plan(root)
    todo = [it for it in items if it["entry"]]
    if not todo:
        return {"ok": True, "message": "直すものはありません", "plan": items}
    if not allow_open:
        opened = _vault_is_open(root)
        if opened:
            return {"ok": False, "message": "vault を開いている Vim かアプリがあります。閉じてからやり直してください", "open": opened}
    before = gg.check(gg.build(root))
    backup = _backup(root, Path(backup_dir))
    # 計画のあとで他が書いていないことの確認は branch_ops と同じ vault ロックで
    with nf.vault_lock(root, 20.0) as got:
        if not got:
            return {"ok": False, "message": "同期が動いています。少し待ってやり直してください", "backup": str(backup)}
        index_lines = _edit_index(root, todo)
        added = [_add_branch_group(root, it["entry"], it["group"], it["title"]) for it in todo]
    branch_results = []
    for it in todo:
        if it["children"]:
            branch_results.append(bo.add_branches(root, root / it["entry"], [root / c for c in it["children"]]))
    _sync(root)
    # BranchGroup のグループは親と同じ Folgezettel になる（同期が振る）。なっていなければここでそろえる
    fixed = []
    for it in todo:
        ep, gp = root / it["entry"], root / it["group"]
        eid = fz.value(ep.read_text(encoding="utf-8"))
        if eid and fz.value(gp.read_text(encoding="utf-8")) != eid:
            gp.write_text(fz.set_value(gp.read_text(encoding="utf-8"), eid), encoding="utf-8")
            fixed.append(it["group"])
    if fixed:
        _sync(root)
    after = gg.check(gg.build(root))
    result = {
        "ok": True, "backup": str(backup), "index_lines": index_lines, "branch_group_added": added,
        "branch": [r.get("code") for r in branch_results], "fz_fixed": fixed,
        "check_before": {k: len(v) for k, v in before.items() if isinstance(v, list)},
        "check_after": {k: len(v) for k, v in after.items() if isinstance(v, list)},
        "report": [],
    }
    g = gg.build(root)
    for it in todo:
        e, grp = g.nodes[it["entry"]], g.nodes[it["group"]]
        result["report"].append({"索引語のノート": e.title, "folgezettel": e.fz, "グループ": grp.title,
                                 "グループの folgezettel": grp.fz, "子にした数": len(it["children"])})
    return result


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "plan":
        json.dump(plan(argv[2]), sys.stdout, ensure_ascii=False, indent=1)
        return 0
    if len(argv) >= 4 and argv[1] == "apply":
        r = apply(argv[2], argv[3], allow_open="--allow-open" in argv)
        json.dump(r, sys.stdout, ensure_ascii=False, indent=1)
        return 0 if r.get("ok") else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
