r"""通常の \L が、チェック項目の文章をビジュアル版と同じ経路でリンクにする。"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parent.parent


class CheckboxLinkify(unittest.TestCase):
    def run_linkify(self, text, choice="\r", visual=False):
        with tempfile.TemporaryDirectory(prefix="gnosis-checkbox-link-") as d:
            root = Path(d)
            vault = root / "v"
            vault.mkdir()
            home = root / "home"
            home.mkdir()
            note = vault / "a.md"
            note.write_text("---\ntime: 2026-01-01 00:00:00\n---\n\n# A\n\n" + text + "\n")
            (vault / "existing.md").write_text("# Existing\n")
            out = root / "out.json"
            script = root / "run.vim"
            script.write_text(
                "set nocompatible\n"
                f"let g:gnosis_root = '{vault}/'\n"
                "let g:gnosis_skip_interactive_mount=1\nlet g:gnosis_start_screen=0\n"
                "let g:gnosis_autosync=0\nlet g:gnosis_diary_auto=0\n"
                f"set runtimepath^={REPO}\nruntime plugin/gnosis.vim\n"
                f"edit {note}\n"
                "call cursor(line('$'), 1)\n"
                # A stale linewise selection must not become the checkbox range.
                "execute \"normal! V\\<Esc>\"\n"
                f"let g:gnosis_test_keys = [{json.dumps(choice)}]\n"
                + ("call gnosis#linkify_selection_new_note()\n" if visual else
                   "execute \"normal \\\\L\"\n")
                + f"call writefile([json_encode({{'file':expand('%:t'), 'lines':getline(1,'$')}})], '{out}')\n"
                "qa!\n")
            result = subprocess.run(["vim", "-u", "NONE", "-N", "-n", "-i", "NONE", "-es", "-S", str(script)],
                                    capture_output=True, text=True, timeout=30)
            self.assertTrue(out.exists(), result.stdout + result.stderr)
            state = json.loads(out.read_text())
            # The filename-link path changes only the buffer; the new-note path also saves.
            state["saved"] = note.read_text()
            state["created"] = sorted(p.name for p in vault.glob("*.md") if p.name not in ("a.md", "existing.md"))
            return state

    def test_checkbox_text_and_prefix(self):
        for prefix in ("- [ ] ", "  * [x] ", "+ [X] ", "12. [ ] ", "3) [ ] "):
            with self.subTest(prefix=prefix):
                state = self.run_linkify(prefix + "調べたいこと  ")
                self.assertNotEqual(state["file"], "a.md")
                self.assertIn(prefix + f"[調べたいこと]({state['file']})  ", state["saved"])
                self.assertEqual(state["created"], [state["file"]])

    def test_branch_and_context_are_shared(self):
        for choice, section in (("b", "ParentBranch:"), ("c", "Context:")):
            with self.subTest(choice=choice):
                state = self.run_linkify("- [ ] 日本語の文章", choice)
                self.assertIn(section, state["lines"])
                self.assertIn("[A](a.md)", state["lines"])

    def test_cancel_and_empty_item(self):
        for text in ("- [ ] 文章", "- [ ] ", "  * [X]   "):
            with self.subTest(text=text):
                state = self.run_linkify(text, "\x1b")
                self.assertEqual(state["file"], "a.md")
                self.assertEqual(state["lines"][-1], text)
                self.assertEqual(state["created"], [])
                self.assertTrue(state["saved"].endswith(text + "\n"))

    def test_normal_filename_and_visual_selection(self):
        state = self.run_linkify("existing.md")
        self.assertEqual(state["lines"][-1], "[Existing](existing.md)")
        state = self.run_linkify("選択した文章", visual=True)
        self.assertNotEqual(state["file"], "a.md")
        self.assertIn(f"[選択した文章]({state['file']})", state["saved"])


if __name__ == "__main__":
    unittest.main()
