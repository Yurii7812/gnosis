#!/usr/bin/env python3
"""スマホのメモ（Gnosis メモ APK の書き出し）を取り込む下ごしらえ。

USB でつないだスマホ（adb）から、アプリの中のデータ（entries.json と images/）を直接読む
（共有フォルダにファイルを置かないので、パスワードは要らない）。取り込んだ id はアプリへ書き戻し、
スマホ側に「取り込み済み」と出す。ここでは読み出しと、取り込む内容の整理だけをする。ノートを作る・日記へ入れる・Branch / Context を
つなぐのは Vim 側（gnosis#capture_import）が、普段の zn と同じ処理で行う。

CLI:
    capture_import.py adbpull OUTDIR                 # スマホのアプリから OUTDIR/capture.json と images/ を作る
    capture_import.py adbmark ROOT                   # 取り込み済みの id をスマホのアプリへ書き戻す
    capture_import.py adbinstall APK                 # つながっているスマホへ APK を入れる（adb install -r）
    capture_import.py plan OUTDIR ROOT               # 取り込む内容を JSON で出す（取り込み済みの id は除く）
    capture_import.py whatsapp TXT OUTDIR [TOPIC]    # WhatsApp の「チャットのエクスポート」を capture.json にする
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
    if not p.exists():
        return {"ids": {}, "entries": {}}
    state = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(state, dict) or not isinstance(state.get("ids"), dict):
        raise ValueError("取り込み記録が壊れています: " + str(p))
    return state


PACKAGE = "net.gnosis.capture"


def _adb() -> str | None:
    return shutil.which("adb")


def adb_ready() -> str:
    """つながっているスマホにアプリが入っていれば ''、だめなら理由。"""
    exe = _adb()
    if not exe:
        return "adb が見つかりません"
    r = subprocess.run([exe, "devices"], stdout=subprocess.PIPE, text=True)
    devs = [ln for ln in r.stdout.splitlines()[1:] if ln.strip().endswith("\tdevice")]
    if not devs:
        un = [ln for ln in r.stdout.splitlines()[1:] if "unauthorized" in ln]
        return ("スマホで「USB デバッグを許可」を押してください" if un
                else "スマホが見つかりません（USB でつなぎ、USB デバッグをオンに）")
    if len(devs) > 1:
        return "スマホが 2 台以上つながっています"
    r = subprocess.run([exe, "shell", "pm", "path", PACKAGE], stdout=subprocess.PIPE, text=True)
    if "package:" not in r.stdout:
        return "スマホに Gnosis メモが入っていません"
    return ""


def adb_pull(outdir: str) -> int:
    why = adb_ready()
    if why:
        print(why, file=sys.stderr)
        return 3
    exe = _adb()
    out = Path(outdir)
    if out.exists():
        shutil.rmtree(out)
    (out / "images").mkdir(parents=True)
    r = subprocess.run([exe, "exec-out", "run-as", PACKAGE, "cat", "files/entries.json"],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    raw = r.stdout.decode("utf-8", "replace").strip()
    if r.returncode != 0 or not raw.startswith("["):
        if "No such file" in raw or not raw:
            raw = "[]"
        else:
            print("スマホのメモを読めませんでした: " + raw[:200], file=sys.stderr)
            return 2
    entries = json.loads(raw)
    names = sorted({n for e in entries for n in (e.get("images") or [])})
    for n in names:
        if "/" in n or n.startswith("."):
            continue
        r = subprocess.run([exe, "exec-out", "run-as", PACKAGE, "cat", "files/images/" + n],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if r.returncode != 0 or not r.stdout:
            print("画像を読めませんでした（取り込み済みにはしません）: " + n, file=sys.stderr)
            return 2
        (out / "images" / n).write_bytes(r.stdout)
    # トピックの取り込み方（1 つのノートにまとめる・日時）。アプリの設定ファイルにある
    r = subprocess.run([exe, "exec-out", "run-as", PACKAGE, "cat", "files/settings.json"],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        modes = json.loads(r.stdout.decode("utf-8")).get("topicModes") or {} if r.returncode == 0 else {}
    except ValueError:
        modes = {}
    data = {"format": "gnosis-capture", "version": 1, "entries": entries, "topicModes": modes}
    (out / "capture.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    print(len(entries))
    return 0


TOPIC_NOTES = ".state/capture_topic_notes.json"


def topic_note(root: Path, name: str) -> str:
    """1 つのノートにまとめるトピックのノート（vault の中のパス）。無ければ ''。"""
    try:
        rel = json.loads((root / TOPIC_NOTES).read_text(encoding="utf-8")).get(name, "")
    except (OSError, ValueError):
        return ""
    return rel if rel and (root / rel).is_file() else ""


def _destination_exists(root: Path, target: str) -> bool:
    if target.startswith("(topic:"):
        return bool(topic_note(root, target[len("(topic:"):-1]))
    if target.startswith("(diary:"):
        # 旧版の記録。日記は日時のファイル名を使うので日付とファイルの対応も読む。
        date = target[len("(diary:"):-1]
        try:
            days = json.loads((root / ".state/diary_days.json").read_text(encoding="utf-8"))["days"]
            return (root / days[date]).is_file()
        except (OSError, ValueError, KeyError):
            return False
    return bool(target) and (root / target).is_file()


def _snapshot(e: dict) -> dict:
    return {"text": e.get("text") or "", "topic": normalize_topic(e.get("topic") or ""),
            "images": e.get("images") or [], "parent": e.get("parent") or None,
            "contexts": e.get("contexts") or []}


def normalize_topic(topic: str) -> str:
    return "" if topic == "メモ" else topic


def adb_mark(root: str) -> int:
    """この vault に実在する取り込み先のスナップショットだけを返す。スマホの原本は消さない。"""
    if adb_ready():
        return 0
    rp = Path(root).resolve()
    state = load_state(rp)
    entries = [e for key, e in state.get("entries", {}).items()
               if _destination_exists(rp, state["ids"].get(key, ""))]
    data = {"version": 2, "vault": str(rp), "entries": entries}
    r = subprocess.run([_adb(), "exec-in", "run-as", PACKAGE, "tee", "files/imported.json.tmp"],
                       input=json.dumps(data, ensure_ascii=False).encode("utf-8"),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode:
        return r.returncode
    # リダイレクトを adb の外側のシェルに解釈させず、アプリの権限で原子的に置き換える。
    return subprocess.run([_adb(), "exec-out", "run-as", PACKAGE, "mv",
                           "files/imported.json.tmp", "files/imported.json"],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode


# スマホのメモの本文の中の、ほかのメモへのリンク（[表示名](memo:ID)）。取り込むと Gnosis のリンクになる。
MEMO_LINK = re.compile(r"\[([^\]\n]*)\]\(memo:([^)\s]+)\)")


def _first_line_title(text: str, limit: int = 20) -> str:
    for ln in text.splitlines():
        ln = ln.strip().lstrip("#").strip()
        if ln:
            return ln if len(ln) <= limit else ln[:limit] + "..."
    return ""


def plan(outdir: str, root: str) -> dict:
    data = json.loads((Path(outdir) / "capture.json").read_text(encoding="utf-8"))
    if data.get("format") != "gnosis-capture":
        raise ValueError("Gnosis メモの書き出しではありません")
    st = load_state(Path(root))
    entries = data.get("entries", [])
    by_id = {e["id"]: e for e in entries}
    # 日記以外で「1 つのノートにまとめる」トピック（取り込むとそのトピックのノートに追記する）
    modes = {k: v for k, v in (data.get("topicModes") or {}).items()
             if k and k != "日記" and isinstance(v, dict) and v.get("single")}
    # 関係のある日記は 1 件のノートにもする（Branch / Context / 本文のリンクの相手になれるように）
    related = set()
    for e in entries:
        if e.get("parent"):
            related.add(e["id"]); related.add(e["parent"])
        for c in e.get("contexts") or []:
            related.add(e["id"]); related.add(c)
        for m in MEMO_LINK.finditer(e.get("text") or ""):
            related.add(e["id"]); related.add(m.group(2))
    items = []
    for e in sorted(entries, key=lambda x: x.get("created", 0)):
        t = dt.datetime.fromtimestamp(e.get("created", 0) / 1000)
        previous = st.get("entries", {}).get(e["id"])
        target = st.get("ids", {}).get(e["id"], "")
        exists = _destination_exists(Path(root), target)
        same = previous is not None and _snapshot(previous) == _snapshot(e)
        topic = normalize_topic(e.get("topic") or "")
        single = topic in modes
        # 日記と、まとめるトピックは、関係のあるものだけ 1 件のノートにする
        needs_note = (topic != "日記" and not single) or e["id"] in related
        # 旧版の記録は本文が残っていない。ノートのファイルが実在するなら取り込み済みとして扱い、
        # 同じメモを別ファイルで重ねて作らない。日記に書いただけの旧記録は、ノートが要るなら取り込み直す。
        legacy = previous is None and not target.startswith("(diary:")
        appended = target.startswith("(diary:") or target.startswith("(topic:")
        done = exists and (same or legacy) and not (needs_note and appended)
        metadata_only = exists and previous is not None and all(
            _snapshot(previous)[k] == _snapshot(e)[k] for k in ("text", "images")) and not appended
        missing = [name for name in e.get("images") or [] if not (Path(outdir) / "images" / name).is_file()]
        if not done and missing:
            raise ValueError("画像がありません（取り込み済みにはしません）: " + ", ".join(missing))
        items.append({
            "id": e["id"],
            "time": t.strftime("%Y-%m-%d %H:%M:%S"),
            "date": t.strftime("%Y-%m-%d"),
            "hm": t.strftime("%H:%M"),
            "topic": normalize_topic(e.get("topic") or ""),
            "text": e.get("text") or "",
            "title": _first_line_title(MEMO_LINK.sub(r"\1", e.get("text") or "")) or t.strftime("%H:%M のメモ"),
            "images": [i for i in e.get("images") or [] if (Path(outdir) / "images" / i).is_file()],
            # 親が無く文脈があるときは、最初の文脈を親（Branch）にする（PC の c と同じ）
            "parent": e.get("parent") or next((c for c in e.get("contexts") or [] if c and c != e["id"]), ""),
            "contexts": [c for c in e.get("contexts") or [] if c],
            "note": needs_note,
            "single": single,
            "stamp": bool(single and modes[topic].get("stamp", True)),
            "done": done,
            "file": target if exists else "",
            "update": metadata_only and not done,
            "known": {k: st["ids"][k] for k in ([e.get("parent")] + list(e.get("contexts") or [])
                                                + [m.group(2) for m in MEMO_LINK.finditer(e.get("text") or "")])
                      if k and k in st.get("ids", {}) and k not in by_id
                      and not st["ids"][k].startswith("(diary:") and not st["ids"][k].startswith("(topic:")
                      and _destination_exists(Path(root), st["ids"][k])},
        })
    return {"items": items, "count": len(items), "new": sum(1 for i in items if not i["done"])}


def record(root: str, pairs: list[tuple[str, str]], outdir: str = "") -> None:
    rp = Path(root)
    st = load_state(rp)
    for key, target in pairs:
        if not _destination_exists(rp, target):
            raise ValueError("取り込み先がありません（記録を更新しません）: " + target)
    st.setdefault("ids", {}).update(dict(pairs))
    if outdir:
        entries = json.loads((Path(outdir) / "capture.json").read_text(encoding="utf-8"))["entries"]
        made = {key for key, _ in pairs}
        st.setdefault("entries", {}).update({e["id"]: e for e in entries if e["id"] in made})
    p = _state_path(rp)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(p)


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


def adb_install(apk: str) -> int:
    """つながっているスマホへ APK を入れる（adb install -r）。結果は標準出力へ。"""
    exe = _adb()
    if not exe:
        print("adb が見つかりません")
        return 1
    r = subprocess.run([exe, "devices"], stdout=subprocess.PIPE, text=True)
    devs = [ln for ln in r.stdout.splitlines()[1:] if ln.strip().endswith("\tdevice")]
    if not devs:
        un = [ln for ln in r.stdout.splitlines()[1:] if "unauthorized" in ln]
        print("スマホで「USB デバッグを許可」を押してください" if un
              else "スマホが見つかりません（USB でつなぎ、USB デバッグをオンに）")
        return 1
    if len(devs) > 1:
        print("スマホが 2 台以上つながっています")
        return 1
    r = subprocess.run([exe, "install", "-r", apk], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(r.stdout, end="")
    return r.returncode


def main(argv: list[str]) -> int:
    try:
        return _main(argv)
    except (OSError, ValueError, KeyError) as e:
        print(str(e), file=sys.stderr)
        return 2


def _main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "adbpull":
        return adb_pull(argv[1])
    if len(argv) == 2 and argv[0] == "adbmark":
        return adb_mark(argv[1])
    if len(argv) == 2 and argv[0] == "adbinstall":
        return adb_install(argv[1])
    if len(argv) == 3 and argv[0] == "plan":
        try:
            print(json.dumps(plan(argv[1], argv[2]), ensure_ascii=False))
        except (OSError, ValueError, KeyError) as e:
            print(str(e), file=sys.stderr)
            return 2
        return 0
    if len(argv) >= 3 and argv[0] == "record":
        pairs = [tuple(x.split("\t", 1)) for x in sys.stdin.read().splitlines() if "\t" in x]
        record(argv[1], pairs, argv[2])  # type: ignore[arg-type]
        return 0
    if len(argv) >= 3 and argv[0] == "whatsapp":
        return whatsapp(argv[1], argv[2], argv[3] if len(argv) > 3 else "日記")
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
