"""A でリンク行へ追記しても、明示モード以外ではリンク先を表示しない。"""
from pathlib import Path
import tempfile
try:
    from keys_pty import Session, ESC
except ModuleNotFoundError as exc:
    if exc.name != "pyte":
        raise
    print("link_source_pty skipped (pyte not installed)")
    raise SystemExit(0)

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='gnosis-source-') as tmp:
    root = Path(tmp)
    vault = root / 'v'
    vault.mkdir()
    home = root / 'home'
    home.mkdir()
    note = vault / '261019222455.md'
    note.write_text('---\ntitle: gnosisの修正一覧\n---\n\n# gnosisの修正一覧\n\n- [ ] [gnosisの修正6](261020131029.md)\n', encoding='utf-8')
    rc = root / 'vimrc'
    rc.write_text('set nocompatible\n'
                  'let g:gnosis_skip_interactive_mount=1\n'
                  'let g:gnosis_open_index_on_startup=0\n'
                  'let g:gnosis_autosync=0\n'
                  'let g:gnosis_autosave=0\n'
                  f'set runtimepath^={repo}\nset runtimepath+={repo}/after\n'
                  'filetype plugin on\nsyntax on\nruntime plugin/gnosis.vim\n', encoding='utf-8')
    with Session(str(rc), str(home), args=[str(note)]) as s:
        s.send(':call cursor(7, 1)\r')
        s.send('A')
        assert '261020131029.md' not in s.text(), s.text()
        s.send(' 追記')
        s.send(ESC)
        s.send(':GnosisLinkSource on\r')
        assert '261020131029.md' in s.text(), s.text()
        # 再適用しても明示的な表示モードは続く。
        s.send(':set filetype=markdown\r')
        assert '261020131029.md' in s.text(), s.text()
        s.send(':GnosisLinkSource off\r')
        assert '261020131029.md' not in s.text(), s.text()
        s.send('A')
        assert '261020131029.md' not in s.text(), s.text()
        s.send(ESC)
        s.send(':w\r')
    assert '- [ ] [gnosisの修正6](261020131029.md) 追記' in note.read_text(encoding='utf-8'), note.read_text(encoding='utf-8')
print('link_source_pty OK (A append / on / reapply / off; link preserved)')
