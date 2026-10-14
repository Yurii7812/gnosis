"""擬似端末（pty）で本物の Vim を動かし、端末が送るキーコードをそのまま送って、画面を pyte で読む。

矢印キーは端末のモードで送るバイト列が違う（通常: ESC [ A、アプリケーションカーソル: ESC O A）。
Vim は起動時に t_ks（smkx）を出すので、実際の端末（xterm 系）は ESC O A を送ってくる。
Gnosis はその両方を矢印キーとして受け取らなければならない。
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import signal
import struct
import termios
import time

import pyte

ESC = b"\x1b"
KEYS = {
    "ss3": {"up": ESC + b"OA", "down": ESC + b"OB", "right": ESC + b"OC", "left": ESC + b"OD"},
    "csi": {"up": ESC + b"[A", "down": ESC + b"[B", "right": ESC + b"[C", "left": ESC + b"[D"},
}


class _Screen(pyte.Screen):
    """pyte が受けられない端末制御（CSI ? … m など Vim が出すもの）を無視する。"""

    def select_graphic_rendition(self, *attrs, private=False, **kw):
        if private:
            return
        return super().select_graphic_rendition(*attrs, **kw)

    def report_device_attributes(self, *a, **kw):
        return

    def report_device_status(self, *a, **kw):
        return


class Session:
    def __init__(self, vimrc: str, home: str, gnosis_home: str | None = None, args: list[str] | None = None,
                 env: dict | None = None, rows: int = 30, cols: int = 100, term: str = "xterm-256color") -> None:
        self.rows, self.cols = rows, cols
        self.screen = _Screen(cols, rows)
        self.stream = pyte.Stream(self.screen)
        e = dict(os.environ, TERM=term, HOME=home, GNOSIS_HOME=gnosis_home or home,
                 LANG="ja_JP.UTF-8", COLORTERM="truecolor", WAYLAND_DISPLAY="", DISPLAY="")
        e.update(env or {})
        e.pop("TMUX", None)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execvpe("vim", ["vim", "-u", vimrc, "-i", "NONE", "-n"] + (args or []), e)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        self.raw = b""
        self.wait(1.5)

    def wait(self, sec: float = 0.4) -> None:
        end = time.time() + sec
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if not r:
                continue
            try:
                d = os.read(self.fd, 65536)
            except OSError:
                return
            if not d:
                return
            self.raw += d
            self.stream.feed(d.decode("utf-8", "replace"))

    def send(self, data: bytes | str, wait: float = 0.4) -> None:
        os.write(self.fd, data if isinstance(data, bytes) else data.encode())
        self.wait(wait)

    def key(self, mode: str, name: str, wait: float = 0.4) -> None:
        self.send(KEYS[mode][name], wait)

    def text(self) -> str:
        return "\n".join(line.rstrip() for line in self.screen.display)

    def line(self, i: int) -> str:
        return self.screen.display[i].rstrip()

    def last_line(self) -> str:
        return self.line(self.rows - 1)

    def close(self) -> None:
        try:
            os.kill(self.pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except OSError:
            pass
        try:
            os.close(self.fd)
        except OSError:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *a) -> None:
        self.close()
