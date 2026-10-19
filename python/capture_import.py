#!/usr/bin/env python3
"""スマホのメモ（Gnosis メモ APK の書き出し）を取り込む下ごしらえ。

APK は capture.json と images/ を鍵付きの .7z（または AES-256 の zip）にして書き出す。
ここでは展開と、取り込む内容の整理だけをする。ノートを作る・日記へ入れる・Branch / Context を
つなぐのは Vim 側（gnosis#capture_import）が、普段の zn と同じ処理で行う。

CLI:
    capture_import.py unpack ARCHIVE OUTDIR          # パスワードは stdin の 1 行目。7z コマンドで展開
    capture_import.py plan OUTDIR ROOT               # 取り込む内容を JSON で出す（取り込み済みの id は除く）
    capture_import.py whatsapp TXT OUTDIR [TOPIC]    # WhatsApp の「チャットのエクスポート」を capture.json にする
    capture_import.py newest DIR...                  # いちばん新しい gnosis-capture-*.7z / .zip のパス
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

STATE_NAME = "capture_imported.json"


def _state_path(root: Path) -> Path:
    return root / ".state" / STATE_NAME


def load_state(root: Path) -> dict:
    p = _state_path(root)
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"ids": {}}


def unpack(archive: str, outdir: str, password: str) -> int:
    out = Path(outdir)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    exe = shutil.which("7z") or shutil.which("7za") or shutil.which("7zz")
    if not exe:
        print("7z が見つかりません（p7zip-full を入れてください）", file=sys.stderr)
        return 3
    r = subprocess.run([exe, "x", "-y", "-p" + password, "-o" + str(out), archive],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if r.returncode != 0 or not (out / "capture.json").is_file():
        msg = (r.stderr or r.stdout).strip().splitlines()
        wrong = any("Wrong password" in m or "password" in m.lower() for m in msg)
        print("パスワードが違います" if wrong else "展開できませんでした: " + " / ".join(msg[-3:]), file=sys.stderr)
        return 2
    return 0


def _first_line_title(text: str, limit: int = 30) -> str:
    for ln in text.splitlines():
        ln = ln.strip().lstrip("#").strip()
        if ln:
            return ln if len(ln) <= limit else ln[:limit] + "…"
    return ""


def plan(outdir: str, root: str) -> dict:
    data = json.loads((Path(outdir) / "capture.json").read_text(encoding="utf-8"))
    if data.get("format") != "gnosis-capture":
        raise ValueError("Gnosis メモの書き出しではありません")
    st = load_state(Path(root))
    entries = data.get("entries", [])
    by_id = {e["id"]: e for e in entries}
    # 関係のある日記は 1 件のノートにもする（Branch / Context の相手になれるように）
    related = set()
    for e in entries:
        if e.get("parent"):
            related.add(e["id"]); related.add(e["parent"])
        for c in e.get("contexts") or []:
            related.add(e["id"]); related.add(c)
    items = []
    for e in sorted(entries, key=lambda x: x.get("created", 0)):
        t = dt.datetime.fromtimestamp(e.get("created", 0) / 1000)
        done = e["id"] in st.get("ids", {})
        items.append({
            "id": e["id"],
            "time": t.strftime("%Y-%m-%d %H:%M:%S"),
            "date": t.strftime("%Y-%m-%d"),
            "hm": t.strftime("%H:%M"),
            "topic": e.get("topic") or "メモ",
            "text": e.get("text") or "",
            "title": _first_line_title(e.get("text") or "") or t.strftime("%H:%M のメモ"),
            "images": [i for i in e.get("images") or [] if (Path(outdir) / "images" / i).is_file()],
            "parent": e.get("parent") or "",
            "contexts": [c for c in e.get("contexts") or [] if c],
            "note": (e.get("topic") != "日記") or (e["id"] in related),
            "done": done,
            "file": st.get("ids", {}).get(e["id"], ""),
            "known": {k: st["ids"][k] for k in ([e.get("parent")] + list(e.get("contexts") or []))
                      if k and k in st.get("ids", {}) and k not in by_id},
        })
    return {"items": items, "count": len(items), "new": sum(1 for i in items if not i["done"])}


def record(root: str, pairs: list[tuple[str, str]]) -> None:
    rp = Path(root)
    st = load_state(rp)
    st.setdefault("ids", {}).update(dict(pairs))
    p = _state_path(rp)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding="utf-8")


_WA_RE = re.compile(r"^(\d{4})/(\d{1,2})/(\d{1,2}) (\d{1,2}):(\d{2}) - ([^:]+): (.*)$")


def whatsapp(txt: str, outdir: str, topic: str = "日記") -> int:
    """WhatsApp の自分宛てチャットの書き出し（txt）を、APK と同じ capture.json にする。"""
    out = Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    entries: list[dict] = []
    used: set[str] = set()
    for raw in Path(txt).read_text(encoding="utf-8").splitlines():
        m = _WA_RE.match(raw)
        if m:
            y, mo, d, h, mi, _who, body = m.groups()
            t = dt.datetime(int(y), int(mo), int(d), int(h), int(mi))
            body = body.replace(" <このメッセージは編集されました>", "")
            if body in ("<メディアなし>",) or "エンドツーエンド暗号化" in body:
                continue
            base = t.strftime("%y%m%d%H%M%S")
            nid, n = base, 2
            while nid in used:
                nid = f"{base}-{n}"; n += 1
            used.add(nid)
            entries.append({"id": nid, "created": int(t.timestamp() * 1000), "topic": topic, "text": body,
                            "images": [], "parent": None, "contexts": [], "exported": True, "edited": 0})
        elif entries and raw.strip():
            entries[-1]["text"] += "\n" + raw.replace(" <このメッセージは編集されました>", "")
    data = {"format": "gnosis-capture", "version": 1, "exported": 0, "entries": entries}
    (out / "capture.json").write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(len(entries))
    return 0


def newest(dirs: list[str]) -> str:
    best = None
    for d in dirs:
        p = Path(os.path.expanduser(d))
        if not p.is_dir():
            continue
        for f in list(p.glob("gnosis-capture-*.7z")) + list(p.glob("gnosis-capture-*.zip")):
            if best is None or f.stat().st_mtime > best.stat().st_mtime:
                best = f
    return str(best) if best else ""


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[0] == "unpack":
        return unpack(argv[1], argv[2], sys.stdin.readline().rstrip("\n"))
    if len(argv) == 3 and argv[0] == "plan":
        try:
            print(json.dumps(plan(argv[1], argv[2]), ensure_ascii=False))
        except (OSError, ValueError, KeyError) as e:
            print(str(e), file=sys.stderr)
            return 2
        return 0
    if len(argv) >= 3 and argv[0] == "record":
        pairs = [tuple(x.split("\t", 1)) for x in sys.stdin.read().splitlines() if "\t" in x]
        record(argv[1], pairs)  # type: ignore[arg-type]
        return 0
    if len(argv) >= 3 and argv[0] == "whatsapp":
        return whatsapp(argv[1], argv[2], argv[3] if len(argv) > 3 else "日記")
    if len(argv) >= 2 and argv[0] == "newest":
        print(newest(argv[1:]))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
