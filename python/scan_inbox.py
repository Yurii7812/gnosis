#!/usr/bin/env python3
"""紙のツェッテルカステンのスキャンの受け皿（`\\F` のアプリ内画面と、`\\M` の取り込みが使う）。

番号のないスキャンは `<vault>/.gnosis/scans/` に `paper-scan-<日時>-<連番>.<拡張子>` で置く。
番号を付けたら `<ID>.<拡張子>` として vault へ移し、番号ノートを作る（paper_pkm.move_images）。
同じ番号を付けたら前の画像を上書きする（前の画像は念のため `.trash/` に 1 つ残す）。

    scan_inbox.py list ROOT
    scan_inbox.py import ROOT SRC...           # フォルダまたは画像ファイルを受け皿へ（名前を paper-scan-… に揃える）
    scan_inbox.py importmove ROOT DIR          # vault の外のフォルダの写真を、受け皿へ移す（元のフォルダからは無くなる）
    scan_inbox.py assign ROOT NAME ID [TOPIC]  # 番号（トピック名つきならトピックのノート）
    scan_inbox.py diary ROOT NAME DATE         # 紙の日記として登録
    scan_inbox.py finish ROOT                  # Index・Folgezettel-Index などを作り直す
    scan_inbox.py prefix ROOT [印]             # 紙の番号の印（既定 PA → PA-1a2）を見る / 変える（変えたら番号を付け直す）

どれも標準出力に JSON を 1 つ出す（失敗は {"ok": false, "error": …}）。
"""
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import paper_pkm as pp  # noqa: E402
import folgezettel as fz  # noqa: E402

EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff"}
PREFIX = "paper-scan-"


def inbox(root: Path) -> Path:
    d = Path(root) / ".gnosis" / "scans"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _state_path(root: Path) -> Path:
    return Path(root) / ".gnosis" / "scans_state.json"


def load_state(root: Path) -> dict:
    try:
        return json.loads(_state_path(root).read_text("utf-8"))
    except (OSError, ValueError):
        return {}


def save_state(root: Path, state: dict) -> None:
    p = _state_path(root)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(state, ensure_ascii=False, indent=1), "utf-8")


def list_scans(root: Path) -> dict:
    d = inbox(root)
    files = sorted((p for p in d.iterdir() if p.is_file() and p.suffix.lower() in EXTS), key=lambda p: p.name)
    names = [p.name for p in files]
    # 並べ替え（画面の s）に使う、更新日時（秒）と大きさ
    info = {p.name: {"mtime": int(p.stat().st_mtime), "size": p.stat().st_size} for p in files}
    return {"ok": True, "scans": names, "info": info, "last": load_state(root).get("last", ""),
            "prefix": fz.paper_prefix(root)[:-1]}


def _next_name(d: Path, when: datetime, suffix: str) -> str:
    stamp = when.strftime("%Y%m%d-%H%M%S")
    n = 1
    while True:
        name = f"{PREFIX}{stamp}-{n:02d}{suffix}"
        if not (d / name).exists():
            return name
        n += 1


def import_files(root: Path, sources: list[str], move: bool = False) -> dict:
    """フォルダ（直下の画像）または画像ファイルを受け皿へ。すでに paper-scan- の名前ならそのまま、違えば付け替える。"""
    d = inbox(root)
    files: list[Path] = []
    for s in sources:
        p = Path(s)
        if p.is_dir():
            files += sorted(q for q in p.iterdir() if q.is_file() and q.suffix.lower() in EXTS)
        elif p.is_file() and p.suffix.lower() in EXTS:
            files.append(p)
    added: list[str] = []
    st = load_state(root)
    imported = set(st.get("imported", []))
    for f in files:
        suffix = f.suffix.lower()
        if f.name.startswith(PREFIX):
            # スマホで撮った名前。番号を付けて inbox から消えたあとでも、二度と取り込まない
            name = f.name
            if name in imported or (d / name).exists():
                continue
            imported.add(name)
        else:
            name = _next_name(d, pp.image_datetime(f) or datetime.fromtimestamp(f.stat().st_mtime), suffix)
        (shutil.move if move else shutil.copy2)(str(f), str(d / name))
        added.append(name)
    if added:
        st["imported"] = sorted(imported)
        save_state(root, st)
    # スマホで番号を付けたもの（scans.json の名前 → 番号）は、そのまま番号ノートにする（同じ番号は上書き）
    numbered: list[str] = []
    errors: list[str] = []
    for src in sources:
        idx = Path(src) / "scans.json"
        if not idx.is_file():
            continue
        try:
            mapping = {o["name"]: str(o.get("id", "")).strip() for o in json.loads(idx.read_text("utf-8"))}
        except (OSError, ValueError, KeyError, TypeError):
            continue
        for name in added:
            fid = mapping.get(name, "")
            if not fid:
                continue
            r = assign(root, name, fid)
            (numbered if r.get("ok") else errors).append(name if r.get("ok") else f"{name}: {r.get('error')}")
    return {"ok": True, "added": added, "numbered": numbered, "errors": errors}


def _keep_old(root: Path, dest: Path, display: str) -> None:
    """同じ名前の画像（拡張子が違うものも）を、上書きの前に .trash/ へ 1 つ残して取り除く。"""
    for old in dest.glob(display + ".*"):
        if old.suffix.lower() not in EXTS or old.stem != display:
            continue
        trash = Path(root) / ".trash"
        trash.mkdir(parents=True, exist_ok=True)
        shutil.copy2(old, trash / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}_{old.name}")
        old.unlink()


def _src(root: Path, name: str) -> Path:
    if "/" in name or name.startswith("."):
        raise ValueError("名前が不正です")
    p = inbox(root) / name
    if not p.is_file():
        raise ValueError("スキャンが見つかりません: " + name)
    return p


def assign(root: Path, name: str, raw_id: str, topic: str = "") -> dict:
    root = Path(root).resolve()
    src = _src(root, name)
    fid = pp.normalize_id(raw_id)
    if not pp.ID_PATTERN.fullmatch(fid):
        return {"ok": False, "error": "番号の形が違います: " + raw_id}
    display = pp.topic_display(fid, topic) if topic else fid
    _keep_old(root, root, display)
    item = (src, fid, topic) if topic else (src, fid)
    moved, errors = pp.move_images(root, root, [item])
    if errors:
        return {"ok": False, "error": errors[0][2]}
    if not topic:
        st = load_state(root)
        st["last"] = fid
        save_state(root, st)
    return {"ok": True, "display": display, "note": moved[0][1].name}


def diary(root: Path, name: str, date: str) -> dict:
    root = Path(root).resolve()
    src = _src(root, name)
    norm = pp.normalize_diary_date(date)  # 不正なら ValueError（main が {"ok": false, "error": …} にする）
    moved, errors = pp.register_diary_pages(root, root, [(src, norm)])
    if errors:
        return {"ok": False, "error": errors[0][2]}
    return {"ok": True, "date": norm}


def set_prefix(root: Path, value: str = "") -> dict:
    """紙の番号の印（PA → `PA-1a2`）。設定は vault の .gnosis/settings.json の paperIdPrefix。
    value が空なら今の印を返すだけ。変えたら regen（同期込み）で、紙のノートの番号を新しい印に付け直す。"""
    root = Path(root).resolve()
    value = value.strip().upper()
    if not value:
        return {"ok": True, "prefix": fz.paper_prefix(root)[:-1]}
    if not fz.PREFIX_RE.fullmatch(value):
        return {"ok": False, "error": "印は英大文字 1〜4 字です（例: PA）"}
    base = next((b for b in (root, root.parent) if (b / ".gnosis" / "settings.json").is_file()), None)
    if base is None:
        base = root.parent if root.name == "note" and (root.parent / ".gnosis").is_dir() else root
    f = base / ".gnosis" / "settings.json"
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            data = {}
    except (OSError, ValueError):
        data = {}
    data["paperIdPrefix"] = value
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    pp.regen(root)
    return {"ok": True, "prefix": value}


def finish(root: Path) -> dict:
    return {"ok": bool(pp.regen(Path(root).resolve()))}


def main(argv: list[str]) -> int:
    try:
        cmd, *a = argv
        if cmd == "list":
            out = list_scans(Path(a[0]))
        elif cmd == "import":
            out = import_files(Path(a[0]), a[1:])
        elif cmd == "importmove":
            out = import_files(Path(a[0]), a[1:], move=True)
        elif cmd == "assign":
            out = assign(Path(a[0]), a[1], a[2], a[3] if len(a) > 3 else "")
        elif cmd == "diary":
            out = diary(Path(a[0]), a[1], a[2])
        elif cmd == "finish":
            out = finish(Path(a[0]))
        elif cmd == "prefix":
            out = set_prefix(Path(a[0]), a[1] if len(a) > 1 else "")
        else:
            out = {"ok": False, "error": "使い方: " + __doc__.splitlines()[0]}
    except Exception as exc:  # noqa: BLE001
        out = {"ok": False, "error": str(exc)}
    print(json.dumps(out, ensure_ascii=False))
    return 0 if out.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
