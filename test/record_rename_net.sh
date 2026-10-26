#!/bin/sh
# 時系列記録の種類を zr/zR で改題する。実 vault・IME・クリップボードには触らない。
set -eu
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"
WORK=$(mktemp -d "$TMPDIR/record-rename.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home" "$WORK/gnosis"
python3 - "$REPO" "$WORK" <<'PY'
import fcntl, os, pty, select, struct, subprocess, sys, termios, time
from pathlib import Path
repo, work = map(Path, sys.argv[1:])
env = dict(os.environ, RECORD_RENAME_WORK=str(work), HOME=str(work / "home"),
           GNOSIS_HOME=str(work / "gnosis"), TERM="xterm-256color", WAYLAND_DISPLAY="", DISPLAY="")
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
proc = subprocess.Popen(["vim", "-u", str(repo / "vimrc_gnosis"), "-N", "-i", "NONE", "-n",
                         "-S", str(repo / "test/record_rename_check.vim")],
                        stdin=slave, stdout=slave, stderr=slave, env=env)
os.close(slave)
try:
    with (work / "vim.log").open("wb") as log:
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                log.write(data)
            elif proc.poll() is not None:
                break
finally:
    if proc.poll() is None:
        proc.kill()
    proc.wait()
    os.close(master)
PY
if [ ! -s "$WORK/result.txt" ] || ! grep -q '^DONE$' "$WORK/result.txt"; then
  tail -c 4000 "$WORK/vim.log" >&2
  echo 'NG record rename: 検証が完了しなかった' >&2
  exit 1
fi
if grep -q '^NG' "$WORK/result.txt"; then
  cat "$WORK/result.txt" >&2
  tail -c 2000 "$WORK/vim.log" >&2
  exit 1
fi
echo "record_rename OK ($(grep -c '^OK' "$WORK/result.txt") 項目)"
