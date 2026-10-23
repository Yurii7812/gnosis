#!/usr/bin/env python3
"""スマホのメモ（Gnosis メモ APK の書き出し）を取り込む下ごしらえ。

USB でつないだスマホ（adb）から、アプリの中のデータ（entries.json と images/）を直接読む
（共有フォルダにファイルを置かないので、パスワードは要らない）。取り込んだ id はアプリへ書き戻し、
スマホ側に「取り込み済み」と出す。ここでは読み出しと、取り込む内容の整理だけをする。ノートを作る・日記へ入れる・Branch / Context を
つなぐのは Vim 側（gnosis#capture_import）が、普段の zn と同じ処理で行う。

CLI:
    capture_import.py adbpull OUTDIR                 # スマホのアプリから OUTDIR/capture.json と images/ を作る
    capture_import.py adbmark ROOT                   # 取り込み済みの id をスマホのアプリへ書き戻す
    capture_import.py adbrecords < JSON              # PC の時系列記録の名前（["夢", …]）をスマホのアプリへ書く
    capture_import.py adbinstall APK                 # つながっているスマホへ APK を入れる（adb install -r）
    capture_import.py plan OUTDIR ROOT               # 取り込む内容を JSON で出す（取り込み済みの id は除く）
    capture_import.py merge OUTDIR ROOT              # スマホで書き直したメモを、取り込み済みの同じノートへ差分だけ反映（競合は記録だけ）
    capture_import.py conflicts ROOT                 # 競合しているメモの一覧（JSON）
    capture_import.py conflict-show ROOT ID          # 競合の中身（前回の行・スマホの行）
    capture_import.py resolve ROOT ID keep|append    # 競合を解決（keep: PC を残す / append: スマホの行を引用で足す）
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
from note_title import title_of_lines  # noqa: E402

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


def record_note(root: Path, kind: str, date: str) -> str:
    """時系列記録 kind のその日のノート（front matter の record: と、題が 日付- で始まる）。無ければ ''。"""
    want = 'record: ' + json.dumps(kind, ensure_ascii=False)
    for p in sorted(root.glob("*.md")):
        try:
            head = p.read_text(encoding="utf-8").split("\n", 15)[:15]
        except OSError:
            continue
        if want in head and title_of_lines(p.read_text(encoding="utf-8").split("\n")[:40], "").startswith(date + "-"):
            return p.name
    return ""


def source_index(root: Path) -> dict[str, str]:
    """vault のノートの front matter `capture_id:`（スマホのメモの不変 ID）→ vault 内の相対パス。
    ノートがリネーム・移動されても同じメモを見つけるため。ドット始まりのフォルダには降りない。"""
    found: dict[str, str] = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            if not name.endswith(".md"):
                continue
            p = Path(dirpath) / name
            try:
                with open(p, encoding="utf-8") as f:
                    head = [f.readline() for _ in range(30)]
            except (OSError, UnicodeDecodeError):
                continue
            if not head or head[0].strip() != "---":
                continue
            for ln in head[1:]:
                if ln.strip() == "---":
                    break
                if ln.startswith("capture_id:"):
                    cid = ln.split(":", 1)[1].strip().strip('"')
                    if cid:
                        found.setdefault(cid, str(p.relative_to(root)))
    return found


def _destination_exists(root: Path, target: str) -> bool:
    if "#" in target and not target.startswith("("):
        # まとめるトピックのノートの中の見出し（ノート.md#見出し）
        target = target.split("#", 1)[0]
    if target.startswith("(record:"):
        kind, _, date = target[len("(record:"):-1].rpartition(":")
        return bool(record_note(root, kind, date))
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


def adb_records(names: list[str]) -> int:
    """PC にある時系列記録の名前をアプリへ渡す（files/records.json）。スマホでは選ぶだけにして表記揺れを防ぐ。"""
    if adb_ready():
        return 0
    data = {"version": 1, "records": [n for n in names if isinstance(n, str) and n]}
    r = subprocess.run([_adb(), "exec-in", "run-as", PACKAGE, "tee", "files/records.json.tmp"],
                       input=json.dumps(data, ensure_ascii=False).encode("utf-8"),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode:
        return r.returncode
    return subprocess.run([_adb(), "exec-out", "run-as", PACKAGE, "mv",
                           "files/records.json.tmp", "files/records.json"],
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
    raw_modes = {k: v for k, v in (data.get("topicModes") or {}).items()
                 if k and k != "日記" and isinstance(v, dict)}
    # 時系列記録（日記のように日ごとのノート）。名前に使えない文字があるものは、ふつうのトピックとして扱う
    records = {k for k, v in raw_modes.items() if v.get("record") and not re.search(r"[\[\]()/\\]", k) and not k[:1].isdigit()}
    modes = {k: v for k, v in raw_modes.items() if v.get("single") and k not in records}
    # 関係のある日記は 1 件のノートにもする（Branch / Context / 本文のリンクの相手になれるように）
    related = set()
    # ほかのメモから親・文脈・リンクで使われたメモ（まとめるトピックでは見出しの節にして、そこを指す）
    referenced = set()
    for e in entries:
        if e.get("parent"):
            related.add(e["id"]); related.add(e["parent"]); referenced.add(e["parent"])
        for c in e.get("contexts") or []:
            related.add(e["id"]); related.add(c); referenced.add(c)
        for m in MEMO_LINK.finditer(e.get("text") or ""):
            related.add(e["id"]); related.add(m.group(2)); referenced.add(m.group(2).split("#", 1)[0])
    items = []
    sources: dict[str, str] | None = None  # 行き先が見つからないときだけ、vault を capture_id で探す（遅いので 1 回だけ）
    for e in sorted(entries, key=lambda x: x.get("created", 0)):
        t = dt.datetime.fromtimestamp(e.get("created", 0) / 1000)
        previous = st.get("entries", {}).get(e["id"])
        target = st.get("ids", {}).get(e["id"], "")
        exists = _destination_exists(Path(root), target)
        if not exists and not target.startswith("("):
            if sources is None:
                sources = source_index(Path(root))
            if e["id"] in sources:  # リネーム・移動された、または記録を失ったが、ノートは実在する
                target, exists = sources[e["id"]], True
        same = previous is not None and _snapshot(previous) == _snapshot(e)
        topic = normalize_topic(e.get("topic") or "")
        single = topic in modes
        record = topic in records
        # 日記・時系列記録は、関係のあるものだけ 1 件のノートにする。まとめるトピックはノートにせず、
        # 使われたものだけトピックのノートの中で見出しの節にする
        needs_note = not single and ((topic != "日記" and not record) or e["id"] in related)
        section = single and e["id"] in referenced
        # 旧版の記録は本文が残っていない。ノートのファイルが実在するなら取り込み済みとして扱い、
        # 同じメモを別ファイルで重ねて作らない。日記に書いただけの旧記録は、ノートが要るなら取り込み直す。
        legacy = previous is None and not target.startswith("(diary:")
        appended = target.startswith(("(diary:", "(topic:", "(record:")) or "#" in target
        done = exists and (same or legacy) and not (needs_note and appended)
        metadata_only = exists and previous is not None and all(
            _snapshot(previous)[k] == _snapshot(e)[k] for k in ("text", "images")) and not appended
        # 本文か画像をスマホで変えた取り込み済みメモ: 別版を作らず、同じノートへ差分だけ当てる（capture_merge）。
        # 前回の本文（base）が残っている記録と、ノートの実ファイルがあるものだけ。日記・トピック・記録への追記は対象外
        merge = (exists and previous is not None and "text" in previous and not appended and not same and not metadata_only
                 and bool(target) and target.endswith(".md"))
        # 日記・時系列記録・まとめるトピック（節も）に埋め込んだメモも同じ: 前回入れた行を base にして、そのノートの該当行だけ更新する。
        # トピックを変えた場合は対象外（既存の移動の扱いのまま）
        embedded = (exists and previous is not None and "text" in previous and appended and not same
                    and normalize_topic(previous.get("topic") or "") == topic
                    and (target.startswith(("(diary:", "(record:")) and (topic == "日記" or record)
                         or (target.startswith("(topic:") or "#" in target) and single)
                    and (previous.get("text"), previous.get("images")) != (e.get("text"), e.get("images")))
        merge = merge or embedded
        # 記録が無いのに行き先のノートに同じ行がもう入っているなら、取り込み済み（クラッシュ後の再実行で二重に追記しない）
        adopt = ""
        if not done and previous is None and not target and not needs_note and not section:
            kind = "diary" if topic == "日記" else "record" if record else "topic" if single else ""
            adopt = adoptable_target(Path(root), e, topic, kind, bool(single and modes[topic].get("stamp", True)))
            done = bool(adopt)
        missing = [name for name in e.get("images") or [] if not (Path(outdir) / "images" / name).is_file()]
        if not done and missing:
            raise ValueError("画像がありません（取り込み済みにはしません）: " + ", ".join(missing))
        items.append({
            "id": e["id"],
            "time": t.strftime("%Y-%m-%d %H:%M:%S"),
            "date": t.strftime("%Y-%m-%d"),
            # スマホで日付を指定し「時刻を入れない」で書いたメモ（notime）は、時刻を付けない
            "hm": "" if e.get("notime") else t.strftime("%H:%M"),
            "topic": normalize_topic(e.get("topic") or ""),
            "text": e.get("text") or "",
            "title": _first_line_title(MEMO_LINK.sub(r"\1", e.get("text") or "")) or t.strftime("%H:%M のメモ"),
            "images": [i for i in e.get("images") or [] if (Path(outdir) / "images" / i).is_file()],
            # 親が無く文脈があるときは、最初の文脈を親（Branch）にする（PC の c と同じ）
            "parent": e.get("parent") or next((c for c in e.get("contexts") or [] if c and c != e["id"]), ""),
            "contexts": [c for c in e.get("contexts") or [] if c],
            "note": needs_note,
            "single": single,
            "section": section,
            "record": record,
            "stamp": bool(single and modes[topic].get("stamp", True)),
            "done": done,
            "file": target if exists else "",
            "update": metadata_only and not done,
            "merge": merge,
            "adopt": adopt,
            "known": {k: st["ids"][k] for k in ([e.get("parent")] + list(e.get("contexts") or [])
                                                + [m.group(2).split("#", 1)[0] for m in MEMO_LINK.finditer(e.get("text") or "")])
                      if k and k in st.get("ids", {}) and k not in by_id
                      and not st["ids"][k].startswith(("(diary:", "(topic:", "(record:"))
                      and _destination_exists(Path(root), st["ids"][k])},
        })
    # 親・文脈の行に使う相手の題（取り込み済みの相手は、取り込んだときの本文から）
    titles = {}
    for k, e in list(st.get("entries", {}).items()) + [(e["id"], e) for e in entries]:
        titles[k] = _first_line_title(MEMO_LINK.sub(r"\1", e.get("text") or "")) or k
    return {"items": items, "count": len(items), "new": sum(1 for i in items if not i["done"]), "titles": titles}


def _hm(e: dict) -> str:
    return "" if e.get("notime") else dt.datetime.fromtimestamp(e.get("created", 0) / 1000).strftime("%H:%M")


def embedded_lines(e: dict, target: str, stamp: bool) -> list[str]:
    """取り込みが日記・時系列記録・まとめるトピックのノートへ入れる行を、gnosis#capture_import と同じ形に作り直す
    （先頭に HH:MM。トピックは stamp のときだけ。つながりの行と画像はトピックでは対象外）。"""
    lines = (e.get("text") or "").split("\n")
    imgs = [f"![](capture-images/{n})" for n in e.get("images") or []]
    hm = _hm(e)
    if target.startswith("(diary:"):
        return ([hm + " " + lines[0]] if hm else [lines[0]]) + lines[1:] + imgs
    if target.startswith("(record:"):
        return ([hm + " " + lines[0]] if hm else [lines[0]]) + lines[1:] + ([""] + imgs if imgs else [])
    if stamp and hm:
        lines = [hm + " " + lines[0]] + lines[1:]
    return lines


def embedded_file(root: Path, target: str, topic: str, date: str) -> str:
    """埋め込み先のノート（vault 内の相対パス）。見つからなければ ''。"""
    if target.startswith("(diary:"):
        days = json.loads((root / ".state/diary_days.json").read_text(encoding="utf-8"))["days"]
        return days.get(target[len("(diary:"):-1], "")
    if target.startswith("(record:"):
        return record_note(root, topic, date)
    return topic_note(root, topic)


def adoptable_target(root: Path, e: dict, topic: str, kind: str, stamp: bool) -> str:
    """取り込み記録が無い（書き込みの途中で落ちた等）メモの行が、日記・時系列記録・まとめるトピックのノートに
    すでに入っているなら、その行き先（記録に使う文字列）。無ければ ''。二重に追記しないため。"""
    date = dt.datetime.fromtimestamp(e.get("created", 0) / 1000).strftime("%Y-%m-%d")
    target = {"diary": f"(diary:{date})", "record": f"(record:{topic}:{date})", "topic": f"(topic:{topic})"}.get(kind, "")
    if not target:
        return ""
    try:
        rel = embedded_file(root, target, topic, date)
        lines = (root / rel).read_text(encoding="utf-8").split("\n") if rel else []
    except (OSError, ValueError, KeyError):
        return ""
    import capture_merge as cm
    want = embedded_lines(e, target, stamp)
    return target if cm._find(lines, want, 0) >= 0 else ""


def apply_merges(outdir: str, root: str) -> dict:
    """plan で merge になったメモを、PC のノートへ差分だけ当てる。{id: {status, file, target, embedded}}。競合はノートを変えない。"""
    import capture_merge as cm
    rp = Path(root)
    st = load_state(rp)
    out = {}
    entries = json.loads((Path(outdir) / "capture.json").read_text(encoding="utf-8"))["entries"]
    for it in plan(outdir, root)["items"]:
        if not it["merge"]:
            continue
        prev = st["entries"][it["id"]]
        remote = next(e for e in entries if e["id"] == it["id"])
        target = st["ids"].get(it["id"], "")
        if target.startswith("(") or "#" in target:
            date = dt.datetime.fromtimestamp(prev.get("created", 0) / 1000).strftime("%Y-%m-%d")
            rel = embedded_file(rp, target, it["topic"], date)
            if not rel:
                out[it["id"]] = {"id": it["id"], "status": "conflict", "file": "", "count": 0}
            else:
                res = cm.apply_note(rp, it["id"], rel, embedded_lines(prev, target, it["stamp"]),
                                    embedded_lines(remote, target, it["stamp"]), {"entry": remote})
                res["target"], res["embedded"] = target, True
                out[it["id"]] = res
            continue
        out[it["id"]] = cm.apply_note(
            rp, it["id"], it["file"],
            cm.body_lines(prev.get("text") or "", prev.get("images") or []),
            cm.body_lines(remote.get("text") or "", remote.get("images") or []), {"entry": remote})
    return out


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
    if len(argv) == 1 and argv[0] == "adbrecords":
        return adb_records(json.loads(sys.stdin.read() or "[]"))
    if len(argv) == 2 and argv[0] == "adbinstall":
        return adb_install(argv[1])
    if len(argv) == 3 and argv[0] == "plan":
        try:
            print(json.dumps(plan(argv[1], argv[2]), ensure_ascii=False))
        except (OSError, ValueError, KeyError) as e:
            print(str(e), file=sys.stderr)
            return 2
        return 0
    if len(argv) == 2 and argv[0] == "conflicts":
        import capture_merge as cm
        print(json.dumps(cm.list_conflicts(Path(argv[1])), ensure_ascii=False))
        return 0
    if len(argv) == 3 and argv[0] == "conflict-show":
        import capture_merge as cm
        print(cm.show(Path(argv[1]), argv[2]))
        return 0
    if len(argv) == 4 and argv[0] == "resolve":
        import capture_merge as cm
        print(json.dumps(cm.resolve(Path(argv[1]), argv[2], argv[3]), ensure_ascii=False))
        return 0
    if len(argv) == 3 and argv[0] == "merge":
        print(json.dumps(apply_merges(argv[1], argv[2]), ensure_ascii=False))
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
