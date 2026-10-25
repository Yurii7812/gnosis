#!/usr/bin/env python3
"""\\x（今の画面を閉じる）と \\X（CUI も GUI も全部閉じる）を、実 Vim を擬似端末で動かして確かめる（一時フォルダだけ）。
  - CUI の Vim を 2 つ起動 → 登録（run/cui-<pid>.json）される
  - 片方で \\x → その Vim だけ終了、もう片方は残る
  - 片方で \\X → どちらも終了（登録も消える）
  - GUI（Electron）の登録の代わりに、生きているダミーのプロセスの登録を置く → \\X が、そのダミーに閉じる依頼のファイルを置く"""
import fcntl, json, os, pty, select, shutil, struct, subprocess, sys, tempfile, termios, time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TMP = Path(os.environ.get("TMPDIR") or Path.home() / "Desktop/test")
TMP.mkdir(parents=True, exist_ok=True)
work = Path(tempfile.mkdtemp(dir=TMP))
res = []


def ok(name, cond):
    res.append(("OK " if cond else "NG ") + name)


procs = []


def start_vim():
    env = dict(os.environ, TERM="xterm-256color", GNOSIS_HOME=str(work / "home"), WAYLAND_DISPLAY="", DISPLAY="", TMPDIR=str(work))
    env.pop("GNOSIS_GUI_PORT", None)
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("vim", ["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "--cmd",
                           "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1|let g:gnosis_autosync=0|let g:gnosis_root='" + str(work / "vault") + "/'",
                           str(work / "vault" / "a.md")], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    procs.append((pid, fd))
    return pid, fd


def pump(fd, t):
    end = time.time() + t
    while time.time() < end:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                os.read(fd, 65536)
            except OSError:
                return


def alive(pid):
    try:
        r, status = os.waitpid(pid, os.WNOHANG)
        return r == 0
    except ChildProcessError:
        return False


try:
    (work / "home").mkdir()
    (work / "vault").mkdir()
    (work / "vault" / "a.md").write_text("# a\n", encoding="utf-8")
    (work / "vault" / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n", encoding="utf-8")
    run = work / "home" / "run"
    p1, f1 = start_vim()
    p2, f2 = start_vim()
    pump(f1, 2.5)
    pump(f2, 1.0)
    regs = sorted(x.name for x in run.glob("cui-*.json")) if run.exists() else []
    ok("CUI の Vim が起動時に自分を登録する（2 つ）: " + str(regs), len(regs) == 2)
    # \x: 片方（p1）だけ閉じる
    os.write(f1, b"\\x")
    pump(f1, 2.0)
    pump(f2, 0.5)
    ok("\\x で、その Vim だけ終了する（もう片方は残る）", (not alive(p1)) and alive(p2))
    regs = sorted(x.name for x in run.glob("cui-*.json"))
    ok("終了した Vim の登録は消える: " + str(regs), len(regs) == 1 and str(p2) in regs[0])
    # GUI の代わりのダミー（生きているプロセス）を登録 → \X が閉じる依頼を置く
    dummy = subprocess.Popen(["sleep", "30"])
    (run / f"gui-{dummy.pid}.json").write_text(json.dumps({"kind": "gui", "pid": dummy.pid}))
    p3, f3 = start_vim()
    pump(f3, 2.5)
    os.write(f3, b"\\X")
    pump(f3, 2.0)
    pump(f2, 2.0)
    ok("\\X で、押した Vim も、ほかの CUI の Vim も終了する", (not alive(p3)) and (not alive(p2)))
    ok("\\X は、登録されている GUI に閉じる依頼のファイルを置く", (run / f"close-gui-{dummy.pid}").exists())
    dummy.kill()
    print("\n".join(res))
    sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
finally:
    for pid, fd in procs:
        try:
            os.kill(pid, 9)
        except OSError:
            pass
    shutil.rmtree(work, ignore_errors=True)
