#!/usr/bin/env python3
"""操作ガイド（guide/ja.md・guide/en.md）の陳腐化チェック。

1. plugin の nnoremap/xnoremap/vnoremap を全部拾い、s:guide_template() に
   載っていなければ失敗（キーを足したらガイドも直せ）。日本語と英語は同じ行に同じキー。
2. plugin の command! を全部拾い、s:guide_template() に載っていなければ失敗
   （コマンドを足したらガイドも直せ）。
3. test/guide_keys.txt の必須トークンがガイドに無ければ失敗。
4. 旧名・旧用語が残っていたら失敗。
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
AUTOLOAD = REPO / "autoload/gnosis.vim"
MAPPING_FILES = [
    REPO / "plugin/gnosis.vim",
    REPO / "plugin/gnosis_search.vim",
    REPO / "plugin/SetImageSize.vim",
    REPO / "plugin/other.vim",
]

# ガイドに載せなくてよい（内部用・Vim 標準の再定義）
EXEMPT_KEYS = {"<C-O>", "."}
MODIFIERS = {"<nowait>", "<silent>", "<buffer>", "<expr>", "<script>", "<unique>"}
BANNED = ["yurii_pkm", "Child", "バックリンク", "タイトルだけ検索"]


GUIDE_JA = REPO / "guide/ja.md"
GUIDE_EN = REPO / "guide/en.md"


def guide_source() -> str:
    return GUIDE_JA.read_text(encoding="utf-8")


def code_spans(line: str) -> list:
    return re.findall(r"`[^`]*`", line)


def check_parallel() -> int:
    """日本語と英語のガイドが同じ行に同じキー（ASCII のコード表記）を載せているか。"""
    ja = GUIDE_JA.read_text(encoding="utf-8").split("\n")
    en = GUIDE_EN.read_text(encoding="utf-8").split("\n")
    ng = 0
    if len(ja) != len(en):
        print(f"NG: ガイドの行数が日本語 {len(ja)} / 英語 {len(en)} で違う", file=sys.stderr)
        return 1
    for i, (a, b) in enumerate(zip(ja, en), 1):
        if (a.startswith("#") != b.startswith("#")) or (a.strip() == "") != (b.strip() == ""):
            print(f"NG: guide {i} 行目の形（見出し・空行）が日本語と英語で違う", file=sys.stderr)
            ng += 1
        ca, cb = code_spans(a), code_spans(b)
        if len(ca) != len(cb):
            print(f"NG: guide {i} 行目のキーの数が違う: {ca} / {cb}", file=sys.stderr)
            ng += 1
            continue
        if sorted(x for x in ca if x.isascii()) != sorted(x for x in cb if x in ca and x.isascii()):
            print(f"NG: guide {i} 行目のキーが日本語と英語で違う: {ca} / {cb}", file=sys.stderr)
            ng += 1
    return ng


def command_files() -> list:
    files = [REPO / "vimrc_gnosis"]
    for path in (REPO / "plugin").glob("**/*.vim"):
        if "node_modules" in path.parts:
            continue
        files.append(path)
    return files


def all_commands() -> list:
    cmds = []
    pat = re.compile(r"^\s*command!\s*(?:-[A-Za-z=0-9?*+]+(?:\s+\d+)?\s+)*([A-Za-z_][A-Za-z0-9_]*)")
    for path in command_files():
        for line in path.read_text(encoding="utf-8").splitlines():
            m = pat.match(line)
            if not m:
                continue
            name = m.group(1)
            if name not in cmds:
                cmds.append(name)
    return cmds


def mapped_keys() -> list:
    keys = []
    pat = re.compile(r"^\s*(?:nnoremap|xnoremap|vnoremap)\s+(.*)$")
    for path in MAPPING_FILES:
        for line in path.read_text(encoding="utf-8").splitlines():
            if "<buffer" in line:
                continue
            m = pat.match(line)
            if not m:
                continue
            for tok in m.group(1).split():
                if tok in MODIFIERS:
                    continue
                key = tok.replace("<leader>", "\\")
                if key not in keys:
                    keys.append(key)
                break
    return keys


def main() -> int:
    guide = guide_source()
    ng = 0

    for key in mapped_keys():
        if key in EXEMPT_KEYS:
            continue
        if key not in guide:
            print(f"NG: マッピング {key} が操作ガイドに無い。guide_template と guide_keys.txt を更新すること", file=sys.stderr)
            ng += 1

    keys_file = REPO / "test/guide_keys.txt"
    for raw in keys_file.read_text(encoding="utf-8").splitlines():
        token = raw.strip()
        if not token or token.startswith("#"):
            continue
        if token not in guide:
            print(f"NG: guide_keys.txt の {token} が操作ガイドに無い", file=sys.stderr)
            ng += 1

    ng += check_parallel()

    for cmd in all_commands():
        # 旧名 :Yurii* は、同じ名前の :Gnosis* の別名としてまとめて説明している
        if cmd.startswith("Yurii") and re.search(r"(?<![\w:]):Gnosis" + re.escape(cmd[5:]) + r"(?![\w])", guide):
            continue
        if not re.search(r"(?<![\w:]):" + re.escape(cmd) + r"(?![\w])", guide):
            print(f"NG: コマンド :{cmd} が操作ガイドに無い。guide_template を更新すること", file=sys.stderr)
            ng += 1

    # コマンド名（`:RenameChildLinkTitles` 等）は BANNED 語を含みうるので、
    # インラインコードのコマンド表記を除いてから旧表記を探す。
    guide_no_cmds = re.sub(r"`:[^`]*`", "", guide)
    for bad in BANNED:
        if bad in guide_no_cmds:
            print(f"NG: 操作ガイドに旧表記 {bad!r} が残っている", file=sys.stderr)
            ng += 1

    if ng:
        return 1
    print(f"guide OK ({len(mapped_keys())} mappings, {len(all_commands())} commands)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
