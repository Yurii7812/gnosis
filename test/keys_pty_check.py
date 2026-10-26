#!/usr/bin/env python3
"""矢印キーの回帰網。擬似端末で本物の Vim（Gnosis 専用 vimrc）を動かし、端末が送るキーコード
（アプリケーションカーソルモードの ESC O A と、通常の ESC [ A の両方）を送って、画面で確かめる。

確かめること:
  - `:` のコマンド履歴（↑ ↓ ← →）・Esc。`<F13>` のような文字が入らない
  - ノーマル / 挿入 / ビジュアルの矢印
  - 起動画面・vault 一覧・設定画面・作業タブ（\\q）で ↑ ↓ が使える
  - fzf の検索画面（gs / <Space> / \\l）で ↑ ↓ が使える

使い方: python3 test/keys_pty_check.py   （一時フォルダは ~/gnosis-work/test）
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import pyte  # noqa: F401
except ImportError:
    print("skip: pyte が無いため矢印キーの擬似端末試験を省略")
    sys.exit(0)
from keys_pty import ESC, Session  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
VIMRC = str(REPO / "vimrc_gnosis")
TMP_BASE = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
REAL_PLUGINS = Path(os.environ.get("GNOSIS_TEST_PLUGINS", str(Path.home() / ".local/share/gnosis/plugins")))
MODES = ("ss3", "csi")


def note(title: str, body: str = "") -> str:
    return f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n{body}\n"


class Env(unittest.TestCase):
    def setUp(self) -> None:
        os.makedirs(TMP_BASE, exist_ok=True)
        self.work = Path(tempfile.mkdtemp(dir=TMP_BASE, prefix="keys-"))
        self.addCleanup(shutil.rmtree, self.work, True)
        self.home = self.work / "home"
        self.gh = self.work / "gh"
        self.home.mkdir()
        self.gh.mkdir()
        self.out = self.work / "out.txt"

    def rc(self, extra: str = "", root: Path | bool | None = True) -> str:
        """root: 開く vault（True なら空の試験用 vault。None / False は起動画面から始める）"""
        p = self.work / "vimrc"
        head = ""
        if root:
            v = self.make_vault("v0") if root is True else root
            head = (f"let g:gnosis_root = '{v}/'\nlet g:gnosis_start_screen = 0\nlet g:gnosis_skip_interactive_mount = 1\n"
                    "let g:gnosis_autosync = 0\nlet g:gnosis_diary_auto = 0\n")
        p.write_text(f"source {VIMRC}\n{head}{extra}\n", encoding="utf-8")
        return str(p)

    def link_plugins(self) -> bool:
        if not (REAL_PLUGINS / "fzf").is_dir() or not (REAL_PLUGINS / "fzf.vim").is_dir():
            return False
        (self.gh / "plugins").mkdir(exist_ok=True)
        for n in ("fzf", "fzf.vim"):
            link = self.gh / "plugins" / n
            if not link.exists():
                link.symlink_to(REAL_PLUGINS / n)
        return True

    def make_vault(self, name: str, notes: dict[str, str] | None = None) -> Path:
        v = self.work / name
        v.mkdir(exist_ok=True)
        (v / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n", encoding="utf-8")
        for fn, text in (notes or {}).items():
            (v / fn).write_text(text, encoding="utf-8")
        return v

    def register(self, vaults: list[Path], last: int = 0) -> None:
        (self.gh / "vaults.json").write_text(json.dumps({
            "version": 1, "last": str(vaults[last]),
            "vaults": [{"path": str(v), "name": v.name} for v in vaults]}), encoding="utf-8")

    def dump_cmd(self, expr: str) -> str:
        return f":call writefile([string({expr})], '{self.out}')\r"

    def read_out(self) -> str:
        return self.out.read_text(encoding="utf-8").strip() if self.out.exists() else ""


class TestCommandLine(Env):
    def test_history_and_cursor_keys(self) -> None:
        for mode in MODES:
            with self.subTest(mode=mode):
                self.out.unlink(missing_ok=True)
                with Session(self.rc(), str(self.home), str(self.gh)) as s:
                    s.send(":let g:n = 0\r")
                    s.send(":let g:n += 1\r")
                    s.send(":echo 'second'\r")
                    s.send(":")
                    s.key(mode, "up")
                    self.assertTrue(s.last_line().startswith(":echo 'second'"), s.last_line())
                    s.key(mode, "up")
                    self.assertTrue(s.last_line().startswith(":let g:n += 1"), s.last_line())
                    s.key(mode, "down")
                    self.assertTrue(s.last_line().startswith(":echo 'second'"), s.last_line())
                    self.assertNotIn("<F1", s.text())
                    s.send("\x15")  # Ctrl-U で消す
                    s.send("abc")
                    s.key(mode, "left")
                    s.key(mode, "left")
                    s.send("X")
                    self.assertTrue(s.last_line().startswith(":aXbc"), s.last_line())
                    s.key(mode, "right")
                    s.send("Y")
                    self.assertTrue(s.last_line().startswith(":aXbYc"), s.last_line())
                    self.assertNotIn("<F1", s.text())
                    s.send(ESC, 0.9)  # Esc: コマンドラインを抜ける
                    self.assertFalse(s.last_line().startswith(":aXbYc"), s.last_line())
                    # 履歴から選んで Enter で実行できる
                    s.send(":let")  # 打った文字から始まる履歴だけをたどる
                    s.key(mode, "up")
                    self.assertTrue(s.last_line().startswith(":let g:n += 1"), s.last_line())
                    s.send("\r")
                    s.send(self.dump_cmd("g:n"))
                    self.assertEqual(self.read_out(), "2")

    def test_input_and_search_prompts(self) -> None:
        for mode in MODES:
            with self.subTest(mode=mode):
                with Session(self.rc(), str(self.home), str(self.gh)) as s:
                    s.send("/hello\r")
                    s.send("/")
                    s.key(mode, "up")
                    self.assertTrue(s.last_line().startswith("/hello"), s.last_line())
                    self.assertNotIn("<F1", s.text())
                    s.send(ESC, 0.9)


class TestTerminals(Env):
    """端末の種類（TERM）が違っても、矢印キーがコマンド履歴で効く（terminfo の矢印が ESC O A か ESC [ A かの違い）"""

    TERMS = ["xterm", "xterm-256color", "screen-256color", "tmux-256color", "linux", "rxvt-unicode-256color",
             "alacritty", "foot", "konsole", "wezterm", "vt100"]

    def test_history_with_various_terminals(self) -> None:
        import subprocess
        terms = [t for t in self.TERMS if subprocess.run(["infocmp", t], capture_output=True).returncode == 0]
        self.assertTrue(terms)
        for term in terms:
            for mode in MODES:
                with self.subTest(term=term, mode=mode):
                    with Session(self.rc(), str(self.home), str(self.gh), term=term) as s:
                        s.send(":echo 'first'\r")
                        s.send(":echo 'second'\r")
                        s.send(":")
                        s.key(mode, "up")
                        self.assertTrue(s.last_line().startswith(":echo 'second'"), (term, mode, s.last_line()))
                        s.key(mode, "up")
                        self.assertTrue(s.last_line().startswith(":echo 'first'"), (term, mode, s.last_line()))
                        s.key(mode, "down")
                        self.assertTrue(s.last_line().startswith(":echo 'second'"), (term, mode, s.last_line()))
                        self.assertNotIn("<F1", s.text())
                        s.send(ESC, 0.9)


class TestConcurrentEdit(Env):
    """別のプロセスが同じノートを書き換えたとき（FileChangedShell は本物の端末で動く）"""

    def test_unsaved_edit_survives_external_change(self) -> None:
        import time
        v = self.make_vault("vc", {"n.md": note("N", "最初の本文")})
        f = v / "n.md"
        with Session(self.rc("let g:gnosis_autosave = 0", root=v), str(self.home), str(self.gh), args=[str(f)]) as s:
            s.send("GA 未保存で打った文字", 0.5)
            s.send(ESC, 0.9)
            time.sleep(1.2)
            f.write_text(note("N", "別のプロセスが書いた本文"), encoding="utf-8")
            s.send(":checktime\r", 1.0)
            self.assertIn("未保存で打った文字", s.text(), "外で書き換えられても、未保存の変更を読み直しで失った\n" + s.text())
            self.assertNotIn("別のプロセスが書いた本文", s.text())
            self.assertIn("別のウィンドウ", s.text() + s.last_line())
            self.assertEqual(f.read_text(encoding="utf-8"), note("N", "別のプロセスが書いた本文"), "自動保存の前に、相手のファイルを上書きしていない")
            backups = list((v / ".state" / "conflicts").glob("*-n.md"))
            self.assertTrue(backups and "未保存で打った文字" in backups[0].read_text(encoding="utf-8"), "未保存の内容を退避していない")
            s.send(":qa!\r", 0.5)

    def test_unmodified_buffer_follows_external_change(self) -> None:
        import time
        v = self.make_vault("vd", {"n.md": note("N", "最初の本文")})
        f = v / "n.md"
        with Session(self.rc(root=v), str(self.home), str(self.gh), args=[str(f)]) as s:
            time.sleep(1.2)
            f.write_text(note("N", "別のプロセスが書いた本文"), encoding="utf-8")
            s.send(":checktime\r", 1.0)
            self.assertIn("別のプロセスが書いた本文", s.text(), "未保存の変更が無いときは、外の変更を読み込む\n" + s.text())
            s.send(":qa!\r", 0.5)


class TestEditorModes(Env):
    def test_normal_insert_visual_arrows_and_escape(self) -> None:
        for mode in MODES:
            with self.subTest(mode=mode):
                self.out.unlink(missing_ok=True)
                f = self.work / f"t-{mode}.txt"
                f.write_text("aaaa\nbbbb\ncccc\n", encoding="utf-8")
                with Session(self.rc(f"inoremap <F8> <Cmd>call writefile([string([mode(), line('.')])], '{self.out}')<CR>"), str(self.home), str(self.gh), args=[str(f)]) as s:
                    s.key(mode, "down")
                    s.key(mode, "right")
                    s.send(self.dump_cmd("[line('.'), col('.')]"))
                    self.assertEqual(self.read_out(), "[2, 2]")
                    s.send("i")
                    s.key(mode, "down")
                    s.key(mode, "left")
                    s.send("Z")
                    s.send(ESC, 0.9)  # 素の Esc（挿入 → ノーマル）
                    s.send(self.dump_cmd("[mode(), getline(3)]"))
                    self.assertEqual(self.read_out(), "['n', 'Zcccc']")
                    s.send("gg")
                    s.send("v")
                    s.key(mode, "right")
                    s.key(mode, "down")
                    s.send(self.dump_cmd("[visualmode(), getpos(\"'<\")[1:2], getpos(\"'>\")[1:2]]"))
                    self.assertEqual(self.read_out(), "['v', [1, 1], [2, 2]]")
                    s.send(ESC, 0.9)
                    # Esc のあと別のキー（O）を続けても矢印と取り違えない
                    s.send("i")
                    s.send(ESC, 0.9)
                    s.send("O", 0.9)
                    s.send(ESC + b"[19~", 0.4)  # F8: 挿入モードのまま状態を書く
                    self.assertEqual(self.read_out(), "['i', 2]")
                    s.send(ESC, 0.9)
                    s.send(":q!\r")


class TestScreens(Env):
    def test_start_screen_vault_list(self) -> None:
        vs = [self.make_vault(n) for n in ("va", "vb", "vc")]
        self.register(vs, last=0)
        for mode in MODES:
            with self.subTest(mode=mode):
                with Session(self.rc(root=None), str(self.home), str(self.gh)) as s:
                    s.send("v")
                    sel = lambda: [ln for ln in s.text().split("\n") if ln.startswith(" > ")]  # noqa: E731
                    self.assertIn("va", sel()[0], s.text())
                    s.key(mode, "down")
                    self.assertIn("vb", sel()[0], s.text())
                    s.key(mode, "down")
                    self.assertIn("vc", sel()[0], s.text())
                    s.key(mode, "up")
                    self.assertIn("vb", sel()[0], s.text())
                    s.send("j")
                    self.assertIn("vc", sel()[0], s.text())
                    s.send("k")
                    self.assertIn("vb", sel()[0], s.text())
                    self.assertNotIn("<F1", s.text())

    def test_settings_screen(self) -> None:
        vs = [self.make_vault("va")]
        self.register(vs)
        for mode in MODES:
            with self.subTest(mode=mode):
                with Session(self.rc(root=None), str(self.home), str(self.gh)) as s:
                    s.send("s")
                    sel = lambda: [ln for ln in s.text().split("\n") if ln.startswith(" > ")]  # noqa: E731
                    first = sel()[0]
                    s.key(mode, "down")
                    second = sel()[0]
                    self.assertNotEqual(first, second, s.text())
                    s.key(mode, "down")
                    third = sel()[0]
                    self.assertNotIn(third, (first, second), s.text())
                    s.key(mode, "up")
                    self.assertEqual(sel()[0], second, s.text())
                    s.key(mode, "up")
                    self.assertEqual(sel()[0], first, s.text())
                    self.assertNotIn("<F1", s.text())


class TestFzf(Env):
    def setUp(self) -> None:
        super().setUp()
        if shutil.which("fzf") is None or not self.link_plugins():
            self.skipTest("fzf / fzf.vim が無い")

    def _vault(self) -> Path:
        return self.make_vault("vf", {f"{n}.md": note(f"Title-{n}", f"body about herb {n}") for n in ("alpha", "beta", "gamma")})

    def _rc(self, v: Path) -> str:
        return self.rc(f"nnoremap <F9> <Cmd>call writefile([expand('%:t')], '{self.out}')<CR>\n", root=v)

    def test_gs_up_down(self) -> None:
        v = self._vault()
        for mode in MODES:
            with self.subTest(mode=mode):
                self.out.unlink(missing_ok=True)
                with Session(self._rc(v), str(self.home), str(self.gh), env={"PATH": os.environ["PATH"]}) as s:
                    s.send("gs", 1.5)
                    s.key(mode, "up", 0.5)  # 検索バーが下のレイアウト: ↑ で次の候補
                    s.send("\r", 0.8)
                    s.send(ESC + b"[20~", 0.3)  # F9
                    first = self.read_out()
                    self.assertTrue(first.endswith(".md"), first)
                self.out.unlink(missing_ok=True)
                with Session(self._rc(v), str(self.home), str(self.gh), env={"PATH": os.environ["PATH"]}) as s:
                    s.send("gs", 1.5)
                    s.key(mode, "up", 0.5)
                    s.key(mode, "up", 0.5)
                    s.key(mode, "down", 0.5)
                    s.send("\r", 0.8)
                    s.send(ESC + b"[20~", 0.3)
                    second = self.read_out()
                self.out.unlink(missing_ok=True)
                with Session(self._rc(v), str(self.home), str(self.gh), env={"PATH": os.environ["PATH"]}) as s:
                    s.send("gs", 1.5)
                    s.send("\r", 0.8)
                    s.send(ESC + b"[20~", 0.3)
                    top = self.read_out()
                self.assertTrue(top.endswith(".md"), top)
                self.assertNotEqual(first, top, "↑ で選択が動いていない")
                self.assertEqual(second, first, "↑ ↑ ↓ は ↑ 1 回と同じ位置のはず")

    def test_gs_escape_cancels(self) -> None:
        v = self._vault()
        with Session(self._rc(v), str(self.home), str(self.gh), env={"PATH": os.environ["PATH"]}) as s:
            s.send(f":edit {v}/gamma.md\r")
            s.send("gs", 1.5)
            s.send(ESC, 1.0)
            s.send(ESC + b"[20~", 0.3)
            self.assertEqual(self.read_out(), "gamma.md")

    def test_other_pickers(self) -> None:
        v = self._vault()
        # :GnosisLocalLinks（旧 <Space>。今のノートのリンク先を検索）と \l（リンク挿入）も同じ fzf。↑ で動く
        (v / "alpha.md").write_text(note("Title-alpha", "[b](beta.md)\n[g](gamma.md)"), encoding="utf-8")
        for mode in MODES:
            with self.subTest(mode=mode):
                self.out.unlink(missing_ok=True)
                with Session(self._rc(v), str(self.home), str(self.gh), env={"PATH": os.environ["PATH"]}) as s:
                    s.send(f":edit {v}/alpha.md\r")
                    s.send(":GnosisLocalLinks\r", 1.5)
                    s.key(mode, "up", 0.5)
                    s.send("\r", 0.8)
                    s.send(ESC + b"[20~", 0.3)
                    got = self.read_out()
                self.assertIn(got, ("beta.md", "gamma.md"))
                self.out.unlink(missing_ok=True)
                with Session(self._rc(v), str(self.home), str(self.gh), env={"PATH": os.environ["PATH"]}) as s:
                    s.send(f":edit {v}/alpha.md\r")
                    s.send(" ", 1.5)
                    s.send("\r", 0.8)
                    s.send(ESC + b"[20~", 0.3)
                    base = self.read_out()
                self.assertNotEqual(got, base, "<Space> の検索で ↑ が効いていない")

                with Session(self._rc(v), str(self.home), str(self.gh), env={"PATH": os.environ["PATH"]}) as s:
                    s.send(f":edit {v}/gamma.md\r")
                    s.send("\\l", 1.5)
                    s.key(mode, "up", 0.5)
                    self.assertIn("Title>", s.text())
                    s.send(ESC, 1.0)
                    s.send(self.dump_cmd("expand('%:t')"))
                    self.assertEqual(self.read_out(), "'gamma.md'")


if __name__ == "__main__":
    unittest.main(verbosity=1)
