#!/usr/bin/env python3
"""スマホのメモの再取り込みで、取り込み済みの PC のノートへ「スマホで変えた部分だけ」を反映する（3-way merge）。

base   … 前回取り込んだときのスマホ側の本文（.state/capture_imported.json の entries[id]）
remote … 今回のスマホ側の本文
local  … 今の PC のノートのファイル全体（PC で追記・修正されていてもよい）

base → remote の差分を、行の塊（hunk）ごとに local へ当てる。塊の元の行（と直前の 1 行）が local に
そのまま見つかる塊だけ当て、見つからない塊（= PC 側で同じ場所を変えている）は**競合**にして何も書かない。
黙って上書きすることも、新しい別のノートを作ることもしない。同じ変更がすでに local にあれば当て済みとみなす
（何度実行しても同じ結果になる）。ノートの題・ファイル名・関係のブロックには触れない。
"""
from __future__ import annotations

import difflib
import json
import os
import sys
from pathlib import Path


def body_lines(text: str, images: list[str]) -> list[str]:
    """取り込みでノートの本文に並べる行（gnosis#capture_import の `body + ['']+ img` と同じ形）。"""
    lines = (text or "").split("\n")
    if images:
        lines = lines + [""] + [f"![](capture-images/{n})" for n in images]
    return lines


def _find(hay: list[str], needle: list[str], start: int) -> int:
    n = len(needle)
    if n == 0:
        return start
    for k in range(start, len(hay) - n + 1):
        if hay[k:k + n] == needle:
            return k
    return -1


def merge(base: list[str], remote: list[str], local: list[str]) -> tuple[list[str] | None, list[dict]]:
    """(merged, conflicts)。競合があるとき merged は None。変更が無ければ local のコピー。"""
    if base == remote:
        return list(local), []
    out = list(local)
    # 本文は題（# 見出し）より後ろにある。そこから探す
    pos = 0
    for k, ln in enumerate(out):
        if ln.startswith("# "):
            pos = k + 1
            if pos < len(out) and out[pos] == "":
                pos += 1  # 題の次の空行を飛ばして本文の先頭へ
            break
    conflicts: list[dict] = []
    sm = difflib.SequenceMatcher(None, base, remote, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        old, new = base[i1:i2], remote[j1:j2]
        ctx = remote[j1 - 1:j1] if j1 > 0 else []  # 直前の 1 行（当てた後の形で探す）
        if old:
            k = _find(out, ctx + old, pos)
            if k >= 0:
                k += len(ctx)
                out[k:k + len(old)] = new
                pos = k + len(new)
                continue
        else:
            # 追記は、同じ行がすでにそこにあれば当て済み（クラッシュ後の再実行で二重に入れない）。空行だけの追記は判定できないので当てる
            if any(ln.strip() for ln in new):
                done = _find(out, ctx + new, pos)
                if done >= 0:
                    pos = done + len(ctx) + len(new)
                    continue
            k = _find(out, ctx, pos) if ctx else pos
            if k >= 0 and (ctx or j1 == 0):
                at = k + len(ctx)
                out[at:at] = new
                pos = at + len(new)
                continue
        # 当たらない。同じ変更がすでに local にあるなら当て済み
        done = _find(out, ctx + new, pos) if new else -1
        if done >= 0:
            pos = done + len(ctx) + len(new)
            continue
        conflicts.append({"base": old, "remote": new, "context": ctx})
    if conflicts:
        return None, conflicts
    return out, []


def _atomic_write(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".gnosis-tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def conflict_path(root: Path, mid: str) -> Path:
    return root / ".state" / "capture_conflicts" / (mid.replace("/", "_") + ".json")


def apply_note(root: Path, mid: str, rel: str, base: list[str], remote: list[str], extra: dict | None = None) -> dict:
    """ノート rel（vault 内の相対パス）へ反映する。status: merged / unchanged / conflict。"""
    path = root / rel
    text = path.read_text(encoding="utf-8")
    trailing = text.endswith("\n")
    local = text.split("\n")
    if trailing:
        local = local[:-1]
    merged, conflicts = merge(base, remote, local)
    cp = conflict_path(root, mid)
    if merged is None:
        cp.parent.mkdir(parents=True, exist_ok=True)
        _atomic_write(cp, json.dumps({"id": mid, "file": rel, "base": base, "remote": remote,
                                      "conflicts": conflicts, **(extra or {})}, ensure_ascii=False, indent=1))
        return {"id": mid, "status": "conflict", "file": rel, "count": len(conflicts)}
    if cp.exists():
        cp.unlink()
    if merged == local:
        return {"id": mid, "status": "unchanged", "file": rel}
    _atomic_write(path, "\n".join(merged) + ("\n" if trailing else ""))
    return {"id": mid, "status": "merged", "file": rel}


def list_conflicts(root: Path) -> list[dict]:
    d = root / ".state" / "capture_conflicts"
    out = []
    for p in sorted(d.glob("*.json")) if d.is_dir() else []:
        try:
            c = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        out.append({"id": c.get("id", p.stem), "file": c.get("file", ""), "hunks": c.get("conflicts", [])})
    return out


def show(root: Path, mid: str) -> str:
    """競合の中身を、PC のノートの今の行とスマホの行を並べた文章にする（差分の確認用）。"""
    c = json.loads(conflict_path(root, mid).read_text(encoding="utf-8"))
    out = [f"{c['file']}  （メモ id {mid}）", ""]
    for n, h in enumerate(c["conflicts"], 1):
        out += [f"--- 競合 {n}: 前回取り込んだときの行 ---"] + (h["base"] or ["(なし)"])
        out += [f"--- 競合 {n}: スマホで書き直した行 ---"] + (h["remote"] or ["(なし)"]) + [""]
    out += ["PC のノートの今の行は " + c["file"] + " にあります（そのまま残してあります）。"]
    return "\n".join(out)


_REL_HEADS = ("ChildBranch:", "Related:", "BackLink:")


def resolve(root: Path, mid: str, how: str) -> dict:
    """keep   … PC のノートを残し、スマホの今の版を「了解済み」にする（次回から競合にならない）。
    append … スマホで変えた行を、引用してノートの本文の最後に足してから了解済みにする（手で統合する）。
    どちらもスマホの原本は消さない。state の更新は取り込み記録（entries）に今の版を入れること。"""
    cp = conflict_path(root, mid)
    c = json.loads(cp.read_text(encoding="utf-8"))
    entry = c.get("entry")
    if not entry:
        raise ValueError("この競合は古い形式で解決できません。スマホのメモを書き直して取り込み直してください")
    if how == "append":
        path = root / c["file"]
        lines = path.read_text(encoding="utf-8").split("\n")
        at = len(lines)
        for i, ln in enumerate(lines):
            if ln in _REL_HEADS:
                at = i
                break
        while at > 0 and lines[at - 1] == "":
            at -= 1
        quote = ["", "> スマホで書き直した内容（手で統合してください）"]
        for h in c["conflicts"]:
            quote += ["> " + ln for ln in (h["remote"] or ["(削除)"])]
        lines[at:at] = quote
        _atomic_write(path, "\n".join(lines))
    elif how != "keep":
        raise ValueError("keep か append を指定してください")
    st_path = root / ".state" / "capture_imported.json"
    st = json.loads(st_path.read_text(encoding="utf-8"))
    st.setdefault("entries", {})[mid] = entry
    _atomic_write(st_path, json.dumps(st, ensure_ascii=False, indent=1))
    cp.unlink()
    return {"id": mid, "file": c["file"], "how": how}


if __name__ == "__main__":
    print(__doc__)
    sys.exit(0)
