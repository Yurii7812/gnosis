#!/usr/bin/env python3
"""複数のウィンドウ（本物の Vim を 2 つ以上）で、本物の gocryptfs の暗号化 vault を同時に使う試験。

  - 1 つ目のウィンドウがパスワードでマウントした vault を、2 つ目のウィンドウは（パスワード無しで）そのまま使える
  - 2 つ目のウィンドウが終わっても、1 つ目が使っているのでロックされない
  - 最後のウィンドウが終わると、ロックされる
  - 別のウィンドウが使っている vault から別の vault へ切り替えても、元の vault はロックされない
  - 異常終了（SIGKILL）したウィンドウの登録は、最後の 1 人の判定を妨げない
一時フォルダ（~/gnosis-work/test）の中だけで動く。gocryptfs / fusermount3 / /dev/fuse / pyte が無ければ省略する。
試験で作ったマウントだけを、試験の最後に外す（ほかの gocryptfs には触らない）。
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import pyte  # noqa: F401
except ImportError:
    print("skip: pyte が無いため実 gocryptfs の複数ウィンドウ試験を省略")
    sys.exit(0)
if not (shutil.which("gocryptfs") and shutil.which("fusermount3") and os.access("/dev/fuse", os.W_OK)):
    print("skip: gocryptfs / fusermount3 / /dev/fuse が使えないため実 gocryptfs の複数ウィンドウ試験を省略")
    sys.exit(0)
from keys_pty import Session  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
VIMRC = str(REPO / "vimrc_gnosis")
TMP_BASE = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
PASSWORD = "test-password-1"


def mounted(path: Path) -> bool:
    return subprocess.run(["mountpoint", "-q", str(path)], capture_output=True).returncode == 0


def wait_until(cond, sec: float = 10.0) -> bool:
    end = time.time() + sec
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.2)
    return cond()


class TestRealEncryptedVault(unittest.TestCase):
    def setUp(self) -> None:
        os.makedirs(TMP_BASE, exist_ok=True)
        self.work = Path(tempfile.mkdtemp(dir=TMP_BASE, prefix="session-real-"))
        self.mounts: list[Path] = []
        self.sessions: list[Session] = []
        self.addCleanup(self.cleanup)
        self.home = self.work / "home"
        self.gh = self.work / "gh"
        self.home.mkdir()
        self.gh.mkdir()
        self.A = self.make_encrypted("A")
        self.B = self.work / "B" / "note"
        self.B.mkdir(parents=True)
        (self.B / "index.md").write_text("---\ntitle: Index\nattribute: group\n---\n\n# Index\n", encoding="utf-8")

    def cleanup(self) -> None:
        for s in self.sessions:
            s.close()
        for m in self.mounts:  # この試験で作ったマウントだけを外す
            for _ in range(5):
                if not mounted(m):
                    break
                subprocess.run(["fusermount3", "-u", str(m)], capture_output=True)
                time.sleep(0.4)
            if mounted(m):
                subprocess.run(["fusermount3", "-u", "-z", str(m)], capture_output=True)
        shutil.rmtree(self.work, ignore_errors=True)

    def make_encrypted(self, name: str) -> Path:
        proj = self.work / name
        cipher = proj / ".crypt"
        mnt = proj / "note"
        cipher.mkdir(parents=True)
        mnt.mkdir()
        pf = self.work / "pf"
        pf.write_text(PASSWORD, encoding="utf-8")
        os.chmod(pf, 0o600)
        subprocess.run(["gocryptfs", "-init", "-q", "-passfile", str(pf), str(cipher)], check=True, capture_output=True)
        subprocess.run(["gocryptfs", "-q", "-passfile", str(pf), str(cipher), str(mnt)], check=True, capture_output=True)
        self.mounts.append(mnt)
        (mnt / "index.md").write_text("---\ntitle: Index\nattribute: group\n---\n\n# Index\n", encoding="utf-8")
        (mnt / "n.md").write_text("---\ntitle: N\n---\n\n# N\n\nbody\n", encoding="utf-8")
        for _ in range(10):  # ロックして「前の使用者がいない」状態から始める
            if subprocess.run(["fusermount3", "-u", str(mnt)], capture_output=True).returncode == 0:
                break
            time.sleep(0.3)
        self.assertFalse(mounted(mnt))
        return mnt

    def rc(self, root: Path) -> str:
        p = self.work / f"vimrc-{abs(hash(str(root)))}"
        p.write_text(f"source {VIMRC}\nlet g:gnosis_root = '{root}/'\nlet g:gnosis_start_screen = 0\nlet g:gnosis_autosync = 0\nlet g:gnosis_diary_auto = 0\n", encoding="utf-8")
        return str(p)

    def window(self, root: Path, password: bool = False) -> Session:
        s = Session(self.rc(root), str(self.home), str(self.gh), rows=30, cols=100)
        self.sessions.append(s)
        if password:
            self.assertIn("password", s.text(), s.text())
            s.send(PASSWORD + "\r", 3.0)
        else:
            s.wait(1.5)
        return s

    def quit(self, s: Session) -> None:
        s.send(":qa!\r", 1.0)
        # Vim が終了するまで待つ（終了時のロック判定が済む）
        end = time.time() + 15
        while time.time() < end:
            try:
                pid, _ = os.waitpid(s.pid, os.WNOHANG)
            except ChildProcessError:
                break
            if pid:
                break
            s.wait(0.2)
        self.sessions.remove(s)

    def test_second_window_shares_and_last_window_locks(self) -> None:
        w1 = self.window(self.A, password=True)
        self.assertTrue(wait_until(lambda: mounted(self.A)), "1 つ目のウィンドウでマウントできない\n" + w1.text())
        w2 = self.window(self.A)  # パスワードは聞かれない（マウント済み）
        self.assertNotIn("password", w2.text())
        self.assertTrue(mounted(self.A))
        self.quit(w2)
        time.sleep(1.0)
        self.assertTrue(mounted(self.A), "2 つ目のウィンドウが終わっただけで、1 つ目が使っている vault がロックされた")
        # 1 つ目はまだ普通に使える
        w1.send(":echo filereadable('" + str(self.A / "n.md") + "')\r", 0.6)
        self.assertIn("1", w1.last_line())
        self.quit(w1)
        self.assertTrue(wait_until(lambda: not mounted(self.A), 15), "最後のウィンドウが終わってもロックされない")

    def test_switching_to_another_vault_does_not_lock_the_vault_used_elsewhere(self) -> None:
        w1 = self.window(self.A, password=True)
        self.assertTrue(wait_until(lambda: mounted(self.A)))
        w2 = self.window(self.A)
        w2.send(f":call gnosis#switch_vault('{self.B}')\r", 2.0)
        self.assertTrue(mounted(self.A), "別の vault へ切り替えたら、別のウィンドウが使っている A までロックされた")
        self.assertIn("B", w2.text() + w2.last_line())
        self.quit(w2)
        self.assertTrue(mounted(self.A))
        self.quit(w1)
        self.assertTrue(wait_until(lambda: not mounted(self.A), 15))

    def test_crashed_window_does_not_block_the_last_one(self) -> None:
        w1 = self.window(self.A, password=True)
        self.assertTrue(wait_until(lambda: mounted(self.A)))
        w2 = self.window(self.A)
        w2.close()  # 異常終了（SIGKILL）。VimLeave は走らない
        self.sessions.remove(w2)
        time.sleep(0.5)
        self.assertTrue(mounted(self.A))
        self.quit(w1)
        self.assertTrue(wait_until(lambda: not mounted(self.A), 15), "異常終了したウィンドウの登録が残って、ロックされない")

    def test_window_that_never_opened_the_vault_does_not_lock_it(self) -> None:
        w1 = self.window(self.A, password=True)
        self.assertTrue(wait_until(lambda: mounted(self.A)))
        # 起動画面を出したまま（vault を選ぶ前）に終了する 2 つ目のウィンドウ
        (self.gh / "vaults.json").write_text('{"version":1,"last":"%s","vaults":[{"path":"%s","name":"A"}]}' % (self.A.parent, self.A.parent), encoding="utf-8")
        p = self.work / "vimrc-start"
        p.write_text(f"source {VIMRC}\n", encoding="utf-8")
        w2 = Session(str(p), str(self.home), str(self.gh), rows=30, cols=100)
        self.sessions.append(w2)
        w2.send("q", 1.5)
        self.sessions.remove(w2)
        time.sleep(1.0)
        self.assertTrue(mounted(self.A), "vault を選ぶ前の起動画面を閉じただけで、別のウィンドウの vault がロックされた")
        self.quit(w1)
        self.assertTrue(wait_until(lambda: not mounted(self.A), 15))


if __name__ == "__main__":
    unittest.main(verbosity=1)
