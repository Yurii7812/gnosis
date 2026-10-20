#!/usr/bin/env python3
"""他のノートアプリ（Obsidian など）の Markdown フォルダを、vault の新しいサブフォルダへ取り込む（UT14）。試走・再開・検証・取り消しつき。

変換（ノートの本文だけ。元のフォルダは読むだけで、何も変えない）:
  [[ノート]] [[ノート|表示]] [[ノート#見出し]]   → [ノート](相対パス.md) ［`#見出し` は保つ］。名前は、同じフォルダ → 最短のパス → 題の順で探す。大文字小文字は区別しない
  ![[画像.png]] ![[画像.png|300]]                → ![画像](相対パス)   ［画像などの添付は、取り込み先へ同じ相対位置でコピー］
  ![[ノート]]（ノートの埋め込み）                → {{include: 相対パス.md}}（この製品の取り込み表示。`blocks`/`transclude` を参照）
  見つからない [[…]]                              → 文字だけ（`ノート`）にして、検査の報告に載せる（壊れたリンクを作らない）
  front matter が無い／time:・title: が無い        → 足す（time は元ファイルの更新日時、title はファイル名）。あるものは変えない
  コードブロックの中は変換しない。

安全:
  - 取り込み先は、vault の中の**まだ無い**サブフォルダだけ（既存のファイルは上書きしない・混ぜない）。ドット始まり・vault の外は不可。
  - 既定は試走（`--apply` を付けたときだけ書く）。シンボリックリンク・ドット始まりのファイルは取り込まない。
  - 1 ファイルずつ「一時ファイル → 置き換え」で書き、そのたびにジャーナル `<vault>/.state/import/<ID>.json` に記録する。
    途中で止まっても、`resume` で残りだけ続けられる（書き終えたものは数え直さない）。
  - `verify` は、書いたファイルの内容（SHA-256）の照合と、取り込んだノートの壊れたリンクの数を調べる。
  - `undo` は、取り込みで作ったファイルのうち、あとから変更されていないものだけを消す（変更されたものは残して報告）。

CLI（JSON）:
  import_notes.py plan   ROOT SRC DEST            何がどうなるか（件数・変換・未解決リンク・名前の重複）。何も書かない
  import_notes.py run    ROOT SRC DEST            書く（ジャーナルを作る。ID を返す）
  import_notes.py resume ROOT ID                  止まった取り込みの続き
  import_notes.py verify ROOT ID                  照合と検査
  import_notes.py undo   ROOT ID                  取り込みで作ったファイルを消す（変更されていないものだけ）
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import posixpath
import re
import sys
import uuid
from pathlib import Path

JOURNAL_DIR = ".state/import"
WIKI = re.compile(r"(!?)\[\[([^\]\n]+?)\]\]")
MAX_FILE = 50 * 1024 * 1024


class Stop(Exception):
    """試験用: 指定件数で止める（中断のまねごと）。"""


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _scan(src: Path) -> tuple[list[str], list[str]]:
    notes, files = [], []
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith(".") and not (Path(dirpath) / d).is_symlink())
        for n in sorted(filenames):
            p = Path(dirpath) / n
            if n.startswith(".") or p.is_symlink():
                continue
            rel = p.relative_to(src).as_posix()
            (notes if n.lower().endswith(".md") else files).append(rel)
    return notes, files


class Resolver:
    def __init__(self, notes: list[str], files: list[str]):
        self.by_name: dict[str, list[str]] = {}
        for rel in notes:
            self.by_name.setdefault(Path(rel).stem.lower(), []).append(rel)
            self.by_name.setdefault(rel[:-3].lower(), []).append(rel)
        self.files: dict[str, list[str]] = {}
        for rel in files:
            self.files.setdefault(Path(rel).name.lower(), []).append(rel)
            self.files.setdefault(rel.lower(), []).append(rel)
        self.ambiguous: list[dict] = []

    def _pick(self, cands: list[str], here: str, name: str) -> str | None:
        cands = sorted(set(cands), key=lambda c: (posixpath.dirname(c) != posixpath.dirname(here), len(c), c))
        if not cands:
            return None
        same_folder = posixpath.dirname(cands[0]) == posixpath.dirname(here)
        if len(cands) > 1 and not same_folder:                       # 同じフォルダに無く、複数の候補から最短のものを選んだときだけ「曖昧」と報告する
            self.ambiguous.append({"from": here, "name": name, "chosen": cands[0], "others": cands[1:]})
        return cands[0]

    def note(self, name: str, here: str) -> str | None:
        key = name.strip().lower()
        key = key[:-3] if key.endswith(".md") else key
        return self._pick(self.by_name.get(key, []), here, name)

    def file(self, name: str, here: str) -> str | None:
        return self._pick(self.files.get(name.strip().lower(), []), here, name)


def convert(text: str, rel: str, res: Resolver, mtime: float, unresolved: list[dict]) -> str:
    lines = text.replace("\r\n", "\n").split("\n")
    fence = False
    out = []
    here_dir = posixpath.dirname(rel)

    def rel_to(target: str) -> str:
        return posixpath.relpath(target, here_dir or ".").replace(" ", "%20")

    def sub(m):
        bang, inner = m.group(1), m.group(2)
        target, _, alias = inner.partition("|")
        name, _, frag = target.partition("#")
        label = alias.strip() or (target.strip())
        if bang:
            f = res.file(name, rel)
            if f:                                                       # 画像などの添付（`|300` のような大きさ指定は表示名にしない）
                return f"![{(alias if alias and not alias.strip().isdigit() else Path(name).stem)}]({rel_to(f)})"
            n = res.note(name, rel)
            if n:                                                       # ノートの埋め込み → この製品の取り込み表示
                return "{{include: " + rel_to(n) + (("#" + frag.strip()) if frag.strip() else "") + "}}"
            unresolved.append({"file": rel, "link": m.group(0)})
            return name.strip()
        t = res.note(name, rel) if name.strip() else rel
        if t is None:
            unresolved.append({"file": rel, "link": m.group(0)})
            return alias.strip() or name.strip()
        return f"[{alias.strip() or (name.strip() or Path(rel).stem)}]({rel_to(t) if name.strip() else Path(rel).name}{('#' + frag.strip()) if frag.strip() else ''})"

    for ln in lines:
        if ln.strip().startswith(("```", "~~~")):
            fence = not fence
            out.append(ln)
        elif fence:
            out.append(ln)
        else:
            out.append(WIKI.sub(sub, ln))
    body = "\n".join(out)
    # front matter: 無ければ作る。あるときは、無い time: / title: だけ足す
    ts = dt.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
    title = Path(rel).stem
    if body.startswith("---\n"):
        end = body.find("\n---", 4)
        if end > 0:
            fm = body[4:end].split("\n")
            add = []
            if not any(x.startswith("time:") for x in fm):
                add.append(f"time: {ts}")
            if not any(x.startswith("title:") for x in fm):
                add.append(f"title: {title}")
            if add:
                body = "---\n" + "\n".join(add + fm) + body[end:]
            return body
    return f"---\ntime: {ts}\ntitle: {title}\n---\n\n{body}"


def _check_dest(root: Path, dest: str) -> tuple[Path, str]:
    d = (root / dest).resolve()
    try:
        rel = d.relative_to(root)
    except ValueError:
        raise ValueError("取り込み先が vault の外です") from None
    if not rel.parts or any(p.startswith(".") for p in rel.parts):
        raise ValueError("取り込み先は、vault の中の（ドット始まりでない）サブフォルダにしてください")
    return d, rel.as_posix()


def _build(root: Path, src: Path, dest: str) -> tuple[list[dict], dict]:
    notes, files = _scan(src)
    res = Resolver(notes, files)
    unresolved: list[dict] = []
    items = []
    for rel in notes:
        data = (src / rel).read_bytes()
        if len(data) > MAX_FILE:
            items.append({"src": rel, "dest": posixpath.join(dest, rel), "kind": "skipped", "status": "skipped", "reason": "大きすぎます"})
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            items.append({"src": rel, "dest": posixpath.join(dest, rel), "kind": "skipped", "status": "skipped", "reason": "UTF-8 として読めません"})
            continue
        new = convert(text, rel, res, (src / rel).stat().st_mtime, unresolved)
        items.append({"src": rel, "dest": posixpath.join(dest, rel), "kind": "note", "status": "pending", "sha": _sha(new.encode("utf-8")), "content": new})
    for rel in files:
        if (src / rel).stat().st_size > MAX_FILE:
            items.append({"src": rel, "dest": posixpath.join(dest, rel), "kind": "skipped", "status": "skipped", "reason": "大きすぎます"})
            continue
        items.append({"src": rel, "dest": posixpath.join(dest, rel), "kind": "file", "status": "pending", "sha": _sha((src / rel).read_bytes())})
    return items, {"unresolved": unresolved, "ambiguous": res.ambiguous}


def plan(root: str | Path, src: str | Path, dest: str) -> dict:
    root, src = Path(root).resolve(), Path(src).resolve()
    if not src.is_dir():
        raise ValueError("取り込み元のフォルダがありません: " + str(src))
    if src == root or root in src.parents or src in root.parents:
        raise ValueError("取り込み元と vault が重なっています")
    d, rel = _check_dest(root, dest)
    if d.exists():
        raise ValueError("取り込み先がすでにあります（混ぜません。新しい名前にしてください）: " + rel)
    items, rep = _build(root, src, rel)
    return {"dest": rel, "notes": sum(1 for i in items if i["kind"] == "note"), "files": sum(1 for i in items if i["kind"] == "file"),
            "skipped": [{"src": i["src"], "reason": i["reason"]} for i in items if i["kind"] == "skipped"], **rep, "dry_run": True}


def _jpath(root: Path, jid: str) -> Path:
    if not re.fullmatch(r"[0-9a-f]{12}", jid):
        raise ValueError("ID が正しくありません")
    return root / JOURNAL_DIR / f"{jid}.json"


def _save(root: Path, j: dict) -> None:
    p = _jpath(root, j["id"])
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(json.dumps(j, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, p)


def _write_items(root: Path, src: Path, j: dict, stop_after: int | None) -> None:
    done = 0
    for it in j["items"]:
        if it["status"] != "pending":
            continue
        target = root / it["dest"]
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            it["status"] = "failed"; it["reason"] = "すでにあります（上書きしません）"
            _save(root, j)
            continue
        data = it["content"].encode("utf-8") if it["kind"] == "note" else (src / it["src"]).read_bytes()
        if _sha(data) != it["sha"]:
            it["status"] = "failed"; it["reason"] = "取り込み元が途中で変わりました"
            _save(root, j)
            continue
        tmp = target.with_name(target.name + ".importing")
        tmp.write_bytes(data)
        os.replace(tmp, target)
        it["status"] = "done"
        it.pop("content", None)
        _save(root, j)
        done += 1
        if stop_after is not None and done >= stop_after:
            raise Stop()


def run(root: str | Path, src: str | Path, dest: str, stop_after: int | None = None) -> dict:
    root, src = Path(root).resolve(), Path(src).resolve()
    p = plan(root, src, dest)                                       # 試走と同じ検査(取り込み先・重なり)
    items, rep = _build(root, src, p["dest"])
    j = {"id": uuid.uuid4().hex[:12], "src": str(src), "dest": p["dest"], "started": dt.datetime.now().isoformat(timespec="seconds"), "items": items, **rep}
    (root / p["dest"]).mkdir(parents=True, exist_ok=False)
    _save(root, j)
    try:
        _write_items(root, src, j, stop_after)
    except Stop:
        return {"id": j["id"], "finished": False, "done": sum(1 for i in j["items"] if i["status"] == "done"), "pending": sum(1 for i in j["items"] if i["status"] == "pending")}
    return _summary(j)


def _load(root: Path, jid: str) -> dict:
    try:
        return json.loads(_jpath(root, jid).read_text(encoding="utf-8"))
    except OSError:
        raise ValueError("その取り込みの記録がありません: " + jid) from None


def _summary(j: dict) -> dict:
    c = {s: sum(1 for i in j["items"] if i["status"] == s) for s in ("done", "pending", "failed", "skipped")}
    return {"id": j["id"], "finished": c["pending"] == 0, "dest": j["dest"], **c, "unresolved": len(j["unresolved"]), "ambiguous": len(j["ambiguous"])}


def resume(root: str | Path, jid: str, stop_after: int | None = None) -> dict:
    root = Path(root).resolve()
    j = _load(root, jid)
    src = Path(j["src"])
    if not src.is_dir():
        raise ValueError("取り込み元のフォルダが見つかりません: " + j["src"])
    # 保存したジャーナルには変換後の本文を持たない(done 済み)。pending は、元から作り直して同じ照合値になるものだけ続ける
    items, _ = _build(root, src, j["dest"])
    fresh = {i["dest"]: i for i in items}
    for it in j["items"]:
        if it["status"] == "pending":
            f = fresh.get(it["dest"])
            if f is None or f["sha"] != it["sha"]:
                it["status"] = "failed"; it["reason"] = "取り込み元が変わったので続けられません"
            elif it["kind"] == "note":
                it["content"] = f["content"]
    _save(root, j)
    try:
        _write_items(root, src, j, stop_after)
    except Stop:
        return {"id": jid, "finished": False, **{k: v for k, v in _summary(j).items() if k in ("done", "pending", "failed")}}
    return _summary(j)


LINK = re.compile(r"(?<!!)\[(?:\\.|[^\]\\])*\]\(([^)\s]+)")


def verify(root: str | Path, jid: str) -> dict:
    root = Path(root).resolve()
    j = _load(root, jid)
    missing, changed, broken = [], [], []
    for it in j["items"]:
        if it["status"] != "done":
            continue
        p = root / it["dest"]
        if not p.is_file():
            missing.append(it["dest"])
            continue
        if _sha(p.read_bytes()) != it["sha"]:
            changed.append(it["dest"])
        if it["kind"] == "note":
            fence = False
            for no, ln in enumerate(p.read_text(encoding="utf-8").split("\n"), 1):
                if ln.strip().startswith(("```", "~~~")):
                    fence = not fence
                    continue
                if fence:
                    continue
                for m in LINK.finditer(ln):
                    u = m.group(1)
                    if "://" in u or u.startswith(("#", "mailto:")):
                        continue
                    t = posixpath.normpath(posixpath.join(posixpath.dirname(it["dest"]), u.split("#")[0].replace("%20", " ")))
                    if u.split("#")[0] and not (root / t).exists():
                        broken.append({"file": it["dest"], "line": no, "target": u})
    s = _summary(j)
    return {**s, "missing": missing, "changed": changed, "broken_links": broken,
            "ok": s["finished"] and not missing and not changed and not s["failed"]}


def undo(root: str | Path, jid: str) -> dict:
    root = Path(root).resolve()
    j = _load(root, jid)
    removed, kept = [], []
    for it in j["items"]:
        if it["status"] != "done":
            continue
        p = root / it["dest"]
        if not p.is_file():
            continue
        if _sha(p.read_bytes()) == it["sha"]:
            p.unlink()
            removed.append(it["dest"])
        else:
            kept.append(it["dest"])                                  # あとから変更されたものは残す
    d = root / j["dest"]
    for dirpath, dirnames, filenames in os.walk(d, topdown=False):   # 空になったフォルダだけ片づける
        try:
            Path(dirpath).rmdir()
        except OSError:
            pass
    if not kept:                                                     # すべて消せたら、記録に「取り消し済み」の印（再度の取り消し・検証を防ぐ）
        jp = _jpath(root, jid)
        jp.rename(jp.with_name(jp.name + ".undone"))
    return {"removed": len(removed), "kept_modified": kept}


def main(argv: list[str]) -> int:
    try:
        if len(argv) == 4 and argv[0] in ("plan", "run"):
            r = (plan if argv[0] == "plan" else run)(argv[1], argv[2], argv[3])
        elif len(argv) == 3 and argv[0] in ("resume", "verify", "undo"):
            r = {"resume": resume, "verify": verify, "undo": undo}[argv[0]](argv[1], argv[2])
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
