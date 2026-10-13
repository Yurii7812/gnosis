#!/usr/bin/env python3
"""擬似端末 (pty) の中でコマンドを動かし、標準入出力と中継する。

Electron (Node) は pty を直接扱えないので、このスクリプトが間に入る。
  使い方: ptybridge.py COLS ROWS -- コマンド [引数...]
  stdin  … 端末への入力（キー入力）をそのまま pty に書く
  stdout … pty の出力（端末の描画データ）をそのまま出す
  fd 3   … 制御用。1 行 1 つの JSON。{"cols": 120, "rows": 40} で端末の大きさを変える
終了コードは子プロセスのものを返す。
"""
import fcntl
import json
import os
import pty
import select
import signal
import struct
import sys
import termios


def set_size(fd, cols, rows):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def main():
    argv = sys.argv[1:]
    if "--" not in argv:
        sys.exit("usage: ptybridge.py COLS ROWS -- cmd [args...]")
    sep = argv.index("--")
    cols, rows = int(argv[0]), int(argv[1])
    cmd = argv[sep + 1:]
    if not cmd:
        sys.exit("no command")

    pid, fd = pty.fork()
    if pid == 0:
        env = dict(os.environ)
        env.setdefault("TERM", "xterm-256color")
        env["COLORTERM"] = "truecolor"
        try:
            os.execvpe(cmd[0], cmd, env)
        except OSError as e:
            sys.stderr.write(f"exec failed: {e}\n")
            os._exit(127)

    set_size(fd, cols, rows)
    ctl = None
    try:
        ctl = os.fdopen(3, "rb", buffering=0)
    except OSError:
        ctl = None
    ctl_buf = b""
    stdin_fd = sys.stdin.fileno()
    out_fd = sys.stdout.fileno()
    fds = [fd, stdin_fd] + ([ctl.fileno()] if ctl else [])
    status = 0
    while True:
        try:
            r, _, _ = select.select(fds, [], [], 0.5)
        except InterruptedError:
            continue
        done = False
        for f in r:
            if f == fd:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    data = b""
                if not data:
                    done = True
                    break
                os.write(out_fd, data)
            elif f == stdin_fd:
                data = os.read(stdin_fd, 65536)
                if not data:
                    fds.remove(stdin_fd)
                    continue
                os.write(fd, data)
            elif ctl and f == ctl.fileno():
                chunk = os.read(ctl.fileno(), 4096)
                if not chunk:
                    fds.remove(ctl.fileno())
                    continue
                ctl_buf += chunk
                while b"\n" in ctl_buf:
                    line, ctl_buf = ctl_buf.split(b"\n", 1)
                    try:
                        m = json.loads(line)
                        set_size(fd, int(m["cols"]), int(m["rows"]))
                        os.kill(pid, signal.SIGWINCH)
                    except Exception:
                        pass
        if done:
            break
    try:
        _, st = os.waitpid(pid, 0)
        status = os.waitstatus_to_exitcode(st)
    except ChildProcessError:
        pass
    sys.exit(status if status >= 0 else 1)


if __name__ == "__main__":
    main()
