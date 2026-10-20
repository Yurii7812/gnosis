#!/usr/bin/env python3
import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gitops as go


def git(root, *a):
    return subprocess.run(["git", "-C", str(root), "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", *a], capture_output=True, text=True, check=True).stdout


class GitOpsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "vault"
        self.root.mkdir()
        r = self.root
        git(r, "init", "-q", "-b", "main")
        (r / "a.md").write_text("# A\n\n一行目\n", encoding="utf-8")
        (r / "日本語 名.md").write_text("# 日本語\n", encoding="utf-8")
        (r / "gone.md").write_text("# gone\n", encoding="utf-8")
        git(r, "add", "-A"); git(r, "commit", "-q", "-m", "初回")
        (r / "a.md").write_text("# A\n\n一行目\n二行目\n", encoding="utf-8")
        git(r, "add", "a.md"); git(r, "commit", "-q", "-m", "二行目を足す")

    def test_not_a_repo_is_refused_and_nothing_is_created(self):
        plain = Path(self.tmp.name) / "plain"
        plain.mkdir()
        for fn in (go.status, go.log):
            with self.assertRaises(ValueError) as cm:
                fn(plain)
            self.assertIn("Git リポジトリではありません", str(cm.exception))
        self.assertFalse((plain / ".git").exists())                                   # git init はしない

    def test_status_kinds_and_hidden_folders_excluded(self):
        r = self.root
        self.assertTrue(go.status(r)["clean"])
        (r / "a.md").write_text("# A\n\n変えた\n", encoding="utf-8")                      # 変更
        (r / "new.md").write_text("# new\n", encoding="utf-8")                          # 未追跡
        (r / "gone.md").unlink()                                                        # 削除
        git(r, "mv", "日本語 名.md", "改名後.md")                                         # 名前変更(ステージ済み)
        (r / ".state").mkdir(); (r / ".state" / "h.json").write_text("{}", encoding="utf-8")
        (r / ".gnosis").mkdir(); (r / ".gnosis" / "c.json").write_text("{}", encoding="utf-8")
        st = go.status(r)
        by = {c["path"]: c for c in st["changes"]}
        self.assertEqual(st["branch"], "main")
        self.assertEqual(by["a.md"]["kind"], "変更")
        self.assertEqual(by["new.md"]["kind"], "未追跡")
        self.assertEqual(by["gone.md"]["kind"], "削除")
        self.assertEqual((by["改名後.md"]["kind"], by["改名後.md"]["old"], by["改名後.md"]["staged"]), ("名前変更", "日本語 名.md", True))
        self.assertFalse(any(p.startswith(".") for p in by), by)                          # ドット始まりは出さない
        self.assertFalse(st["clean"])

    def test_diff_whole_and_per_note_and_staged(self):
        r = self.root
        (r / "a.md").write_text("# A\n\n一行目\n二行目\n三行目\n", encoding="utf-8")
        (r / ".state").mkdir(); (r / ".state" / "x.json").write_text("1", encoding="utf-8")
        git(r, "add", "-f", ".state/x.json"); git(r, "commit", "-q", "-m", "state")
        (r / ".state" / "x.json").write_text("2", encoding="utf-8")
        d = go.diff(r)
        self.assertIn("+三行目", d["diff"])
        self.assertEqual((d["added"], d["removed"]), (1, 0))
        self.assertNotIn(".state", d["diff"])                                            # ドット始まりの差分は出さない
        self.assertEqual(go.diff(r, "a.md")["added"], 1)
        self.assertTrue(go.diff(r, "日本語 名.md")["empty"])
        self.assertTrue(go.diff(r, staged=True)["empty"])
        git(r, "add", "a.md")
        self.assertTrue(go.diff(r, "a.md")["empty"])
        self.assertEqual(go.diff(r, "a.md", staged=True)["added"], 1)

    def test_log_and_show_old_revision(self):
        lg = go.log(self.root, "a.md")
        self.assertEqual([c["subject"] for c in lg["commits"]], ["二行目を足す", "初回"])
        self.assertEqual(len(go.log(self.root)["commits"]), 2)
        self.assertEqual(len(go.log(self.root, n=1)["commits"]), 1)
        old = go.show(self.root, "a.md", lg["commits"][1]["rev"])
        self.assertEqual(old["content"], "# A\n\n一行目\n")                                # 初回の版
        self.assertNotIn("二行目", old["content"])
        self.assertEqual((self.root / "a.md").read_text(encoding="utf-8").count("二行目"), 1)   # 表示するだけで、ファイルは戻さない
        with self.assertRaises(ValueError):
            go.show(self.root, "gone-never.md", "HEAD")
        fresh = Path(self.tmp.name) / "fresh"; fresh.mkdir(); git(fresh, "init", "-q", "-b", "main")
        self.assertEqual(go.log(fresh)["commits"], [])                                    # コミットが無くても落ちない

    def test_dangerous_arguments_are_refused(self):
        for bad in ("../outside.md", "/etc/passwd", ".git/config", ".state/x", "--output=/tmp/x", "-p", "a\x00b"):
            with self.assertRaises(ValueError, msg=repr(bad)):
                go.diff(self.root, bad)
            with self.assertRaises(ValueError, msg=repr(bad)):
                go.log(self.root, bad)
        with self.assertRaises(ValueError):
            go.show(self.root, "", "HEAD")                                                # show は空のノート名を拒否(diff/log の空は「全体」)
        self.assertTrue(go.diff(self.root, "")["empty"])
        for rev in ("--help", "-1", "HEAD;rm", "a b", "$(x)", "HEAD:../../x", "x" * 100):
            with self.assertRaises(ValueError, msg=rev):
                go.show(self.root, "a.md", rev)

    def test_commit_only_visible_changes_and_needs_message(self):
        r = self.root
        (r / "a.md").write_text("# A\n\n改訂\n", encoding="utf-8")
        (r / "new.md").write_text("# new\n", encoding="utf-8")
        (r / "gone.md").unlink()
        (r / ".state").mkdir(); (r / ".state" / "h.json").write_text("{}", encoding="utf-8")
        (r / ".gnosis").mkdir(); (r / ".gnosis" / "c.json").write_text("{}", encoding="utf-8")
        for bad in ("", "   "):
            with self.assertRaises(ValueError):
                go.commit(r, bad)
        self.assertEqual(len(go.log(r)["commits"]), 2)                                    # メッセージ無しでは何も起きない
        res = go.commit(r, "改訂と整理")
        self.assertEqual(res["files"], 3)
        files = git(r, "show", "--name-status", "--pretty=format:", "HEAD").split("\n")
        files = sorted(x.split("\t", 1)[1] for x in files if x.strip())
        self.assertEqual(files, ["a.md", "gone.md", "new.md"])                            # ノートだけ。.state/.gnosis は入らない
        self.assertEqual(go.log(r)["commits"][0]["subject"], "改訂と整理")
        self.assertIn(".state/h.json", git(r, "status", "--porcelain", "--untracked-files=all"))   # 派生データは未追跡のまま
        with self.assertRaises(ValueError) as cm:
            go.commit(r, "もう一度")
        self.assertIn("変更がありません", str(cm.exception))

    def test_commit_does_not_push_or_touch_remotes(self):
        r = self.root
        (r / "a.md").write_text("# A\n\n変更\n", encoding="utf-8")
        self.assertEqual(git(r, "remote").strip(), "")
        go.commit(r, "ローカルだけ")
        self.assertEqual(git(r, "remote").strip(), "")                                    # リモートは作らない・触らない

    def test_markdown_and_cli(self):
        r = self.root
        (r / "a.md").write_text("# A\n\n変更\n", encoding="utf-8")
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = go.main([str(r), *a])
            return rc, buf.getvalue()
        self.assertIn("変更: [a.md](a.md)", run("status", "--md")[1])
        self.assertIn("```diff", run("diff", "a.md", "--md")[1])
        self.assertIn("二行目を足す", run("log", "--md")[1])
        self.assertIn("# a.md @ HEAD", run("show", "a.md", "HEAD", "--md")[1])
        self.assertEqual(run("commit", "CLI")[0], 0)
        self.assertEqual(run("commit", "CLI2")[0], 1)
        self.assertEqual(run("diff", "../x")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
