#!/usr/bin/env python3
"""Activate the terminal containing a Gnosis Vim, including KDE Wayland."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def run(args: list[str]) -> str:
    try:
        return subprocess.check_output(args, stderr=subprocess.DEVNULL, text=True, timeout=4).strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def ancestors(pid: int) -> list[int]:
    result = []
    while pid > 1 and pid not in result:
        result.append(pid)
        try:
            # comm may contain spaces and parentheses.
            stat = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
            pid = int(stat[1])
        except (OSError, ValueError, IndexError):
            parent = run(["ps", "-o", "ppid=", "-p", str(pid)])
            if not parent.isdigit():
                break
            pid = int(parent)
    return result


def activate(pid: int, window: str = "") -> None:
    if sys.platform == "win32":
        # Include the console host when Vim is hosted by Windows Terminal.
        run(["powershell", "-NoProfile", "-Command",
             f"$p={pid}; $w=New-Object -ComObject WScript.Shell; "
             "while ($p -gt 0) { if ($w.AppActivate($p)) { break }; "
             "$p=(Get-CimInstance Win32_Process -Filter \"ProcessId=$p\").ParentProcessId }"])
        return
    pids = ancestors(pid)
    if sys.platform == "darwin":
        run(["osascript", "-e", "tell application \"System Events\"",
             "-e", "repeat with p in " + str(pids).replace("[", "{").replace("]", "}"),
             "-e", "set matches to application processes whose unix id is p",
             "-e", "if (count of matches) > 0 then",
             "-e", "set frontmost of item 1 of matches to true", "-e", "exit repeat",
             "-e", "end if", "-e", "end repeat", "-e", "end tell"])
        return
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        return
    # On X11 WINDOWID identifies the exact terminal window, even in a shared process.
    if window and window.isdigit() and shutil.which("wmctrl"):
        run(["wmctrl", "-ia", window])
        return
    qdbus = shutil.which("qdbus6") or shutil.which("qdbus")
    if qdbus and os.environ.get("WAYLAND_DISPLAY"):
        # KWin can activate native Wayland windows. Match the closest ancestor first.
        script = """(function () {
            var ids = %s, windows = workspace.windowList();
            for (var i = 0; i < ids.length; i++) {
                for (var j = 0; j < windows.length; j++) {
                    var w = windows[j];
                    if (w.normalWindow && w.pid === ids[i]) {
                        w.minimized = false;
                        workspace.activeWindow = w;
                        return;
                    }
                }
            }
        })();""" % json.dumps(pids)
        name = f"gnosis-focus-{os.getpid()}"
        with tempfile.TemporaryDirectory(prefix="gnosis-focus-") as folder:
            source = Path(folder) / "focus.js"
            source.write_text(script)
            service = [qdbus, "org.kde.KWin", "/Scripting"]
            loaded = run(service + ["org.kde.kwin.Scripting.loadScript", str(source), name])
            if loaded.isdigit():
                run(service + ["org.kde.kwin.Scripting.start"])
                run(service + ["org.kde.kwin.Scripting.unloadScript", name])
                return
    if shutil.which("wmctrl"):
        windows = run(["wmctrl", "-lp"]).splitlines()
        for parent in pids:
            for line in windows:
                fields = line.split(None, 4)
                if len(fields) >= 3 and fields[2] == str(parent):
                    run(["wmctrl", "-ia", fields[0]])
                    return


if __name__ == "__main__":
    activate(int(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else "")
