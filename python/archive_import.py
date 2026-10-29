#!/usr/bin/env python3
"""zip / 7z を vault に取り込む（:GnosisImportArchive の本体）。

  archive_import.py plan ROOT ARCHIVE [--pw-stdin]   書庫を一時フォルダへ展開し、何が増える・変わるかを JSON で出す
  archive_import.py apply ROOT STAGE [--merge] [--force]
        plan で展開したものを vault に反映する（STAGE は反映後に消す）。既定は「置き換え」: 書庫の内容が vault の正。
        --merge は足す・更新するだけ（消さない）。--force は、守って残していたもの（held）も上書きする
  archive_import.py discard STAGE                     反映せずに一時フォルダを消す

- 展開は 7z（7z / 7zz / 7za）。パスワードは標準入力の 1 行目（--pw-stdin）から受け取り、擬似端末で 7z に渡す
  （コマンドラインに出さない）。パスワードが要るのに無い・違うときは {"need_password": true}。
- 書庫の中が 1 つのフォルダだけなら、その 1 つ下を vault の直下とみなす。
- ドット始まりの場所（.state・.trash・.git・.crypt など）・シンボリックリンクは取り込まない。
- 置き換え（既定）: vault に無いファイルは足す。同じ中身は何もしない。違う中身は上書きする。
  **書庫に無い vault のファイルは消す**（vault を書庫の内容に合わせる。消したファイルが復活しない）。ただし書庫の最新より
  新しい vault のファイル（書庫が撮られたあとの作業）は消さない（protected）。
- 守って今回は触らないもの（held）: 今の vault の方が更新時刻が新しい／書庫側の中身が壊れていそう（UTF-8 として読めない・
  置換文字・文字化け・空・途中切れ・先頭の --- が無い）なファイル。plan が理由つきで返す。--force でだけ上書きする。
- strong: 別の vault の書庫かもしれない・古い記録、のとき plan が理由を返す（取り込む側は強い確認を出す）。
  上書き・消したファイルの元は、先に ROOT/.trash/archive-import-<時刻>/ へ同じ相対パスで退避する（戻せる）。
  退避できなければ何も変えない。--merge のときは消さない。
"""
from __future__ import annotations

import filecmp
import json
import os
import pty
import select
import shutil
import sys
import tempfile
import time
from pathlib import Path

MAX_FILES = 50000
MAX_BYTES = 4 * 1024 ** 3
TRASH_DIR = ".trash"
STAGE_PREFIX = "gnosis-archive-"


def find_7z() -> str | None:
    for n in ("7z", "7zz", "7za"):
        p = shutil.which(n)
        if p:
            return p
    return None


def _run_7z(exe: str, args: list[str], password: str | None) -> tuple[int, str]:
    """7z を実行して (終了コード, 出力)。パスワードがあれば擬似端末でプロンプトに答える。"""
    if password is None:
        import subprocess
        r = subprocess.run([exe] + args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
        return r.returncode, r.stdout
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(exe, [exe] + args)  # -p は付けない（空のパスワード扱いになり、聞かれなくなる）
        finally:
            os._exit(127)
    out = b""
    sent = False
    while True:
        r, _, _ = select.select([fd], [], [], 60)
        if not r:
            break
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        out += data
        if not sent and b"nter password" in out:
            time.sleep(0.3)  # 7z が端末の設定（エコー無し）を変えるのを待つ。早く書くと捨てられる
            os.write(fd, (password + "\n").encode())
            sent = True
    try:
        os.close(fd)
    except OSError:
        pass
    _, status = os.waitpid(pid, 0)
    rc = os.waitstatus_to_exitcode(status)
    return rc, out.decode("utf-8", "replace")


def _need_password(rc: int, out: str) -> bool:
    low = out.lower()
    return rc != 0 and ("enter password" in low or "wrong password" in low or "cannot open encrypted" in low)


def _hidden(parts) -> bool:
    return any(p.startswith(".") or p == "_expand_tmp" for p in parts)


def _content_root(stage: Path) -> Path:
    kids = [p for p in stage.iterdir()]
    if len(kids) == 1 and kids[0].is_dir() and not kids[0].is_symlink() and not kids[0].name.startswith("."):
        return kids[0]
    return stage


def _files(base: Path):
    for dirpath, dirnames, filenames in os.walk(base):
        rel_dir = Path(dirpath).relative_to(base)
        dirnames[:] = sorted(d for d in dirnames if not _hidden((d,)) and not (Path(dirpath) / d).is_symlink())
        for n in sorted(filenames):
            if _hidden((n,)):
                continue
            p = Path(dirpath) / n
            if p.is_symlink() or not p.is_file():
                continue
            yield p, (rel_dir / n).as_posix()


TEXT_EXT = {".md", ".txt", ".csv", ".json", ".yml", ".yaml", ".html", ".htm", ".tsv"}
# 文字化けでよく出る字（UTF-8 の日本語を別の文字コードとして読んだときに多い）
MOJIBAKE = "縺繧繝窶譁蜷荳螟蟄"
SLACK = 2.0  # 更新時刻の比べ方の余裕（秒）
STRONG_REMOVED_RATIO = 0.5   # 今の vault のファイルの半分以上が書庫に無い → 別の vault の疑い
MIN_FILES_FOR_RATIO = 10     # これより少ない vault では割合の判定をしない
STALE_SECONDS = 60           # 書庫の最新が vault の最新より、これ以上古ければ「古い書庫」


def _text_stats(path: Path):
    """(読めない or NUL あり, 置換文字の数, 文字化けの字の割合, 'ã' の数, 先頭が --- か, 大きさ)。読めなければ None。"""
    try:
        raw = path.read_bytes()
    except OSError:
        return None
    bad = b"\x00" in raw
    try:
        s = raw.decode("utf-8")
    except UnicodeDecodeError:
        bad = True
        s = raw.decode("utf-8", "replace")
    cjk = sum(1 for ch in s if "\u3040" <= ch <= "\u9fff")
    moji = sum(1 for ch in s if ch in MOJIBAKE)
    return {"bad": bad, "fffd": s.count("\ufffd"), "moji": (moji / cjk) if cjk >= 10 else 0.0,
            "tilde_a": s.count("\u00e3") + s.count("\u00e2\u20ac"), "front": s.startswith("---"), "size": len(raw)}


def suspicious(new: Path, old: Path | None) -> list[str]:
    """書庫側の新しい中身が壊れていそうな理由（なければ空）。テキストのファイルだけ見る。old は今の vault 側（無ければ None）。"""
    if new.suffix.lower() not in TEXT_EXT:
        return []
    n = _text_stats(new)
    if n is None:
        return ["読めない"]
    o = _text_stats(old) if old is not None and old.is_file() else None
    why = []
    if n["bad"]:
        why.append("UTF-8 として読めない／NUL を含む")
    if n["fffd"] and (o is None or n["fffd"] > o["fffd"]):
        why.append("置換文字（�）を含む")
    if n["moji"] >= 0.15 and (o is None or n["moji"] > o["moji"] + 0.1):
        why.append("文字化けの疑い")
    if n["tilde_a"] >= 5 and (o is None or n["tilde_a"] > o["tilde_a"] + 5):
        why.append("文字化けの疑い（ã など）")
    if o is not None:
        if n["size"] == 0 and o["size"] > 0:
            why.append("空になっている")
        elif o["size"] >= 200 and n["size"] < o["size"] * 0.2:
            why.append("元より大きく小さい（途中で切れた疑い）")
        if o["front"] and not n["front"] and n["size"] > 0:
            why.append("先頭の --- （front matter）が無い")
    return why


def classify(root: Path, base: Path) -> dict:
    """書庫（base）と今の vault（root）の違い。
    new 足す / changed 上書きする / same 同じ / removed 消す（書庫に無く、書庫より古い）。
    held は、守るために今回は触らないもの: [{rel, kind: changed|new, why: [...]}]（vault の方が新しい・書庫側の中身が壊れていそう）。
    protected は、書庫に無いが書庫の最新より新しい vault のファイル（作業の続き）で、消さない。"""
    new, changed, same, held = [], [], [], []
    have = {}
    for p, rel in _files(base):
        have[rel] = p
    snap = max((p.stat().st_mtime for p in have.values()), default=0.0)   # 書庫が撮られた時刻（最新のファイルの更新時刻）
    shared = 0
    for rel, p in have.items():
        dst = root / rel
        if not dst.exists():
            why = suspicious(p, None)
            if why:
                held.append({"rel": rel, "kind": "new", "why": why})
            else:
                new.append(rel)
            continue
        shared += 1
        if dst.is_file() and filecmp.cmp(p, dst, shallow=False):
            same.append(rel)
            continue
        why = suspicious(p, dst)
        if dst.is_file() and dst.stat().st_mtime > p.stat().st_mtime + SLACK:
            why.append("vault の方が新しい（古い記録で上書きしない）")
        if why:
            held.append({"rel": rel, "kind": "changed", "why": why})
        else:
            changed.append(rel)
    removed, protected = [], []
    mine = list(_files(root))
    vault_newest = 0.0
    for p, rel in mine:
        m = p.stat().st_mtime
        vault_newest = max(vault_newest, m)
        if rel in have:
            continue
        (protected if m > snap + SLACK else removed).append(rel)
    total = len(mine)
    removed_ratio = (len(removed) + len(protected)) / total if total else 0.0
    strong = []
    if total >= MIN_FILES_FOR_RATIO:
        if removed_ratio >= STRONG_REMOVED_RATIO:
            strong.append("今の vault のファイルの %d%% が書庫に無い（別の vault の書庫かもしれません）" % round(removed_ratio * 100))
        if shared == 0:
            strong.append("今の vault と同じパスのファイルが 1 つもありません（別の vault の書庫かもしれません）")
    if have and vault_newest > snap + STALE_SECONDS and (changed or removed or held):
        strong.append("この書庫は今の vault より古い記録です（書庫の最新 %s ／ vault の最新 %s）"
                      % (time.strftime("%Y-%m-%d %H:%M", time.localtime(snap)), time.strftime("%Y-%m-%d %H:%M", time.localtime(vault_newest))))
    return {"new": new, "changed": changed, "same": same, "removed": removed, "held": held, "protected": protected,
            "vault_total": total, "strong": strong}


def plan(root: str, archive: str, password: str | None) -> dict:
    exe = find_7z()
    if not exe:
        return {"error": "7z が見つかりません"}
    arc = Path(archive).expanduser()
    if not arc.is_file():
        return {"error": "書庫が見つかりません: %s" % archive}
    base = os.environ.get("TMPDIR") or tempfile.gettempdir()
    stage = Path(tempfile.mkdtemp(prefix=STAGE_PREFIX, dir=base))
    rc, out = _run_7z(exe, ["x", "-y", "-snl-", "-o" + str(stage), str(arc)], password)
    if _need_password(rc, out):
        shutil.rmtree(stage, ignore_errors=True)
        return {"need_password": True, "wrong": password is not None}
    if rc >= 2 or not any(stage.iterdir()):
        shutil.rmtree(stage, ignore_errors=True)
        return {"error": "展開できません: " + " ".join(out.split())[-200:]}
    base_dir = _content_root(stage)
    n = total = 0
    for p, _ in _files(base_dir):
        n += 1
        total += p.stat().st_size
        if n > MAX_FILES or total > MAX_BYTES:
            shutil.rmtree(stage, ignore_errors=True)
            return {"error": "大きすぎます（%d 件・%d MB を超えました）" % (MAX_FILES, MAX_BYTES // 1024 ** 2)}
    c = classify(Path(root), base_dir)
    c["stage"] = str(stage)
    c["warning"] = rc == 1
    return c


def _stage_ok(stage: Path) -> bool:
    return stage.is_dir() and stage.name.startswith(STAGE_PREFIX)


def _prune_empty(root: Path, rel: str) -> None:
    """消したファイルの空になったフォルダを、vault の直下を残して片づける（ドット始まりは触らない）。"""
    d = (root / rel).parent
    while d != root and root in d.parents:
        try:
            if any(d.iterdir()):
                break
            d.rmdir()
        except OSError:
            break
        d = d.parent


def apply(root: str, stage: str, merge: bool = False, force: bool = False) -> dict:
    """反映する。merge は足す・更新するだけ（消さない）。force は、守って残していたもの（held）も上書きする。"""
    r = Path(root).resolve()
    st = Path(stage)
    if not _stage_ok(st):
        return {"error": "展開したフォルダが見つかりません"}
    base = _content_root(st)
    c = classify(r, base)
    removed = [] if merge else c["removed"]
    over = c["changed"] + ([h["rel"] for h in c["held"] if h["kind"] == "changed"] if force else [])
    add = c["new"] + ([h["rel"] for h in c["held"] if h["kind"] == "new"] if force else [])
    backup = r / TRASH_DIR / ("archive-import-" + time.strftime("%Y%m%d%H%M%S"))
    # 先に退避する。ひとつでも失敗したら、vault は何も変えない
    try:
        for rel in over + removed:
            old = r / rel
            if old.is_file():
                b = backup / rel
                b.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(old, b)
    except OSError as e:
        return {"error": "元のファイルを .trash に退避できませんでした（vault は変えていません）: %s" % e}
    for rel in removed:
        try:
            (r / rel).unlink()
        except OSError:
            continue
        _prune_empty(r, rel)
    for rel in add + over:
        dst = r / rel
        if dst.exists() and not dst.is_file():
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base / rel, dst)
    shutil.rmtree(st, ignore_errors=True)
    kept = [] if force else c["held"]
    return {"added": len(add), "updated": len(over), "removed": len(removed), "same": len(c["same"]),
            "held": len(kept), "protected": len(c["protected"]),
            "backup": str(backup) if (over or removed) else "", "files": add + over + removed}


def discard(stage: str) -> dict:
    st = Path(stage)
    if _stage_ok(st):
        shutil.rmtree(st, ignore_errors=True)
    return {"ok": True}


def main(argv: list[str]) -> int:
    if len(argv) >= 4 and argv[1] == "plan":
        pw = None
        if "--pw-stdin" in argv[4:]:
            pw = sys.stdin.readline().rstrip("\r\n")
        out = plan(argv[2], argv[3], pw)
    elif len(argv) >= 4 and argv[1] == "apply":
        out = apply(argv[2], argv[3], merge="--merge" in argv[4:], force="--force" in argv[4:])
    elif len(argv) >= 3 and argv[1] == "discard":
        out = discard(argv[2])
    else:
        print(__doc__)
        return 2
    json.dump(out, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
