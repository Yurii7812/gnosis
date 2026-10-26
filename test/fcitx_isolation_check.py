#!/usr/bin/env python3
"""試験用 Vim が利用者の IME を切り替えないことを、偽の fcitx だけで検証する。"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parent.parent
TMP = Path(os.environ.get("TMPDIR") or Path.home() / "gnosis-work/test")


class FcitxIsolationTest(unittest.TestCase):
    def run_vim(self, graphical=False, isolated=False):
        TMP.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="fcitx-isolation.", dir=TMP) as folder:
            work = Path(folder)
            fake = work / "fcitx5-remote"
            fake.write_text('#!/bin/sh\nprintf "%s\\n" "${1:-state}" >> "$IME_TEST_LOG"\nprintf "2\\n"\n')
            fake.chmod(0o755)
            script = work / "check.vim"
            script.write_text(
                "execute 'doautocmd ' . (exists('##InsertLeavePre') ? 'InsertLeavePre' : 'InsertLeave')\n"
                "doautocmd InsertEnter\nGnosisFcitxOff\nGnosisFcitxOn\nGnosisFcitxStatus\n"
                "sleep 300m\ncall writefile([v:errmsg], $IME_TEST_ERRORS)\nqa!\n"
            )
            log = work / "calls"
            errors = work / "errors"
            env = dict(os.environ, HOME=str(work), GNOSIS_HOME=str(work / "gnosis"),
                       TMPDIR=str(TMP), DISPLAY=":fake" if graphical else "", WAYLAND_DISPLAY="",
                       GNOSIS_TEST_NO_DESKTOP="1" if isolated else "0",
                       IME_TEST_LOG=str(log), IME_TEST_ERRORS=str(errors),
                       PATH=str(work) + os.pathsep + os.environ.get("PATH", ""))
            result = subprocess.run(
                ["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "-i", "NONE", "-n", "-es",
                 "--cmd", "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1",
                 "-S", str(script)], env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            self.assertEqual(errors.read_text().strip(), "")
            return log.read_text().splitlines() if log.exists() else []

    def test_headless_vim_does_not_call_session_ime(self):
        self.assertEqual(self.run_vim(), [])

    def test_isolated_test_does_not_call_ime_even_with_display(self):
        self.assertEqual(self.run_vim(graphical=True, isolated=True), [])

    def test_normal_desktop_keeps_ime_switching(self):
        self.assertCountEqual(self.run_vim(graphical=True), ["-c", "-c", "-o", "state"])


if __name__ == "__main__":
    unittest.main()
