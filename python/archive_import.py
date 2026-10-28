#!/usr/bin/env python3
"""zip / 7z を vault に取り込む（:GnosisImportArchive の本体）。

  archive_import.py plan ROOT ARCHIVE [--pw-stdin]   書庫を一時フォルダへ展開し、何が増える・変わるかを JSON で出す
  archive_import.py apply ROOT STAGE                  plan で展開したものを vault に反映する（STAGE は反映後に消す）
  archive_import.py discard STAGE                     反映せずに一時フォルダを消す

- 展開は 7z（7z / 7zz / 7za）。パスワードは標準入力の 1 行目（--pw-stdin）から受け取り、擬似端末で 7z に渡す
  （コマンドラインに出さない）。パスワードが要るのに無い・違うときは {"need_password": true}。
- 書庫の中が 1 つのフォルダだけなら、その 1 つ下を vault の直下とみなす。
- ドット始まりの場所（.state・.trash・.git・.crypt など）・シンボリックリンクは取り込まない。
- vault に無いファイルは足す。同じ中身は何もしない。違う中身は上書きするが、元のファイルは
  ROOT/.trash/archive-import-<時刻>/ に同じ相対パスで残す（消えない）。
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


def classify(root: Path, base: Path) -> dict:
    new, changed, same = [], [], []
    for p, rel in _files(base):
        dst = root / rel
        if not dst.exists():
            new.append(rel)
        elif dst.is_file() and filecmp.cmp(p, dst, shallow=False):
            same.append(rel)
        else:
            changed.append(rel)
    return {"new": new, "changed": changed, "same": same}


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


def apply(root: str, stage: str) -> dict:
    r = Path(root).resolve()
    st = Path(stage)
    if not _stage_ok(st):
        return {"error": "展開したフォルダが見つかりません"}
    base = _content_root(st)
    c = classify(r, base)
    backup = r / TRASH_DIR / ("archive-import-" + time.strftime("%Y%m%d%H%M%S"))
    for rel in c["changed"]:
        old = r / rel
        if old.is_file():
            b = backup / rel
            b.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(old, b)
    for rel in c["new"] + c["changed"]:
        dst = r / rel
        if dst.exists() and not dst.is_file():
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base / rel, dst)
    shutil.rmtree(st, ignore_errors=True)
    return {"added": len(c["new"]), "updated": len(c["changed"]), "same": len(c["same"]),
            "backup": str(backup) if c["changed"] else "", "files": c["new"] + c["changed"]}


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
        out = apply(argv[2], argv[3])
    elif len(argv) >= 3 and argv[1] == "discard":
        out = discard(argv[2])
    else:
        print(__doc__)
        return 2
    json.dump(out, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
