#!/usr/bin/env python3
"""曼荼羅ノート（9×9 = 81 マスの思考展開）。

保存形式は、ふつうの Markdown ノート（front matter に `mandala: true`）の 9 行 9 列の表。通常の Markdown ビューアでも
そのまま読め、マスの `[文字](ノート.md)` で実際のノートへ、別の曼荼羅ノートへも辿れる。表示は HTML（9×9 の格子）が主。

複数枚（2026-10-21〜）: 副題が 8 つで足りないときは、同じノートに 9×9 の表をもう 1 枚（空行で区切って下へ）足す。
どの表も同じ主題（真ん中）を持つ「同じ主題の曼荼羅の続き」。1 枚目だけの古いノートはそのまま読める。

構造: 中心のブロック（行 4〜6・列 4〜6）の中心マス(5,5) が主題。その周り 8 マスが 8 つの副題。8 つの副題は、それぞれ
周りの 8 ブロックの中心マスにも同じ内容で置く（そこから 8 マスずつ展開する）。`sync` はこの対応を揃える:
片方だけが入っていれば他方へ写し、両方が違う内容なら**どちらも変えずに食い違いとして報告する**。

CLI（JSON）:
  mandala.py new FILE 主題 [副題1 … 副題8]    新しい曼荼羅ノートを作る（既存のファイルは上書きしない）
  mandala.py sync FILE                          主題・副題の対応を揃える（食い違いは変えず報告）
  mandala.py link FILE LINE COL [note|mandala]  カーソルのマスの文字から新しいノート／別の曼荼羅を作り、マスをリンクにする
  mandala.py link-cell FILE ROW COL [note|mandala] [PAGE]  同じことを、マスの位置（行・列とも 0 から。PAGE は何枚目か、0 から）で（`\\A` の曼荼羅）
  mandala.py show FILE                          81 マスを JSON で出す
"""
from __future__ import annotations

import html
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import md_html  # noqa: E402

N = 9
# 副題 i（0..7）の、中心ブロック内の位置と、それを中心に持つ周囲ブロックの中心マス（行, 列）。上から時計回り
RING = [(3, 3), (3, 4), (3, 5), (4, 5), (5, 5), (5, 4), (5, 3), (4, 3)]
BLOCK_CENTER = [(1, 1), (1, 4), (1, 7), (4, 7), (7, 7), (7, 4), (7, 1), (4, 1)]
THEME = (4, 4)
ROW_RE = re.compile(r"^\s*\|(.*)\|\s*$")


def is_mandala(text: str) -> bool:
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---" or "---" not in [x.strip() for x in lines[1:]]:
        return False
    end = [x.strip() for x in lines[1:]].index("---") + 1
    return any(re.match(r"^mandala:\s*true\s*$", ln) for ln in lines[1:end])


def _cells(line: str) -> list[str]:
    m = ROW_RE.match(line)
    inner = m.group(1) if m else line
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", inner)]


SEP_RE = re.compile(r"^\s*\|\s*:?-{2,}")


def table_blocks(lines: list[str]) -> list[tuple[int, int]]:
    """曼荼羅の表（列名の行・区切りの行・マスの行）の [始まり, 終わり) の一覧。9 行に満たない表も 1 枚と数える。"""
    out, i = [], 0
    while i < len(lines):
        if ROW_RE.match(lines[i]) and i + 1 < len(lines) and SEP_RE.match(lines[i + 1]):
            j = i + 2
            while j < len(lines) and ROW_RE.match(lines[j]) and j - (i + 2) < N:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def _grid_of(lines: list[str], blk: tuple[int, int]) -> list[list[str]]:
    grid = [["" for _ in range(N)] for _ in range(N)]
    for r, ln in enumerate(lines[blk[0] + 2:blk[1]][:N]):
        for c, v in enumerate(_cells(ln)[:N]):
            grid[r][c] = v
    return grid


def parse_all(text: str) -> list[list[list[str]]]:
    """本文の曼荼羅の表を全部（何枚目かの順）。表が無ければ空の 9×9 が 1 枚。"""
    lines = text.split("\n")
    blocks = table_blocks(lines)
    return [_grid_of(lines, b) for b in blocks] or [[["" for _ in range(N)] for _ in range(N)]]


def replace_tables(text: str, grids: list[list[list[str]]]) -> str:
    """表を grids に差し替える（枚数が増えたら最後の表の下に空行をはさんで足し、減ったら消す）。表の外の本文は触らない。"""
    lines = text.split("\n")
    blocks = table_blocks(lines)
    if not blocks:
        h1 = next((i for i, ln in enumerate(lines) if re.match(r"^#\s", ln)), len(lines) - 1)
        add: list[str] = []
        for k, g in enumerate(grids):
            add += [""] + render_table(g)
        lines[h1 + 1:h1 + 1] = add
        return "\n".join(lines)
    out = lines[:blocks[0][0]]
    for k, g in enumerate(grids):
        if k:
            out.append("")
        out += render_table(g)
    # 最後の表のあとの本文（2 枚目以降の表のあいだの空行は捨てる）
    tail = lines[blocks[-1][1]:]
    out += tail
    return "\n".join(out)


def parse(text: str) -> list[list[str]]:
    """本文の最初の表から 9×9 を読む。足りないマスは空文字、余りは無視。表が無ければ空の 9×9。"""
    grid = [["" for _ in range(N)] for _ in range(N)]
    lines = text.split("\n")
    rows: list[list[str]] = []
    started = False
    for i, ln in enumerate(lines):
        if ROW_RE.match(ln):
            if re.match(r"^\s*\|\s*:?-{2,}", ln):
                started = True
                continue
            if started or (i + 1 < len(lines) and re.match(r"^\s*\|\s*:?-{2,}", lines[i + 1])):
                if not started:  # 見出し行（列名）は読み飛ばす
                    continue
                rows.append(_cells(ln))
        elif started and rows:
            break
    for r, row in enumerate(rows[:N]):
        for c, v in enumerate(row[:N]):
            grid[r][c] = v
    return grid


def render_table(grid: list[list[str]]) -> list[str]:
    esc = lambda v: v.replace("|", "\\|")
    out = ["| " + " | ".join(f"{c + 1}" for c in range(N)) + " |", "|" + "---|" * N]
    for r in range(N):
        out.append("| " + " | ".join(esc(grid[r][c]) for c in range(N)) + " |")
    return out


def new_text(theme: str, subs: list[str], time: str = "2026-01-01 00:00:00") -> str:
    if len(subs) > 8:
        raise ValueError("副題は 8 個までです")
    grid = [["" for _ in range(N)] for _ in range(N)]
    grid[THEME[0]][THEME[1]] = theme
    for i, s in enumerate(subs):
        grid[RING[i][0]][RING[i][1]] = s
        grid[BLOCK_CENTER[i][0]][BLOCK_CENTER[i][1]] = s
    fm = f"---\ntime: {time}\ntitle: {theme}\nmandala: true\n---\n\n# {theme}\n\n"
    return fm + "\n".join(render_table(grid)) + "\n"


def sync(text: str) -> tuple[str, dict]:
    """主題・副題の対応を揃えた本文と、報告 {filled: [...], conflicts: [...]}。表の 9×9 の外は触らない。
    2 枚目以降の表も同じように揃え、主題が空なら 1 枚目の主題を入れる。報告の位置には page（0 から）が付く。"""
    lines = text.split("\n")
    blocks = table_blocks(lines)
    if len(blocks) <= 1:
        return _sync_one(text)
    grids = [_grid_of(lines, b) for b in blocks]
    filled, conflicts = [], []
    theme = grids[0][THEME[0]][THEME[1]]
    for p, g in enumerate(grids):
        if p and theme and not g[THEME[0]][THEME[1]]:
            g[THEME[0]][THEME[1]] = theme
            filled.append({"page": p, "from": [THEME[0], THEME[1]], "to": [THEME[0], THEME[1]]})
        f, c = _sync_grid(g)
        filled += [{"page": p, **x} for x in f]
        conflicts += [{"page": p, **x} for x in c]
    if not filled:
        return text, {"filled": [], "conflicts": conflicts}
    return replace_tables(text, grids), {"filled": filled, "conflicts": conflicts}


def _sync_grid(grid: list[list[str]]) -> tuple[list, list]:
    filled, conflicts = [], []
    for i in range(8):
        (ra, ca), (rb, cb) = RING[i], BLOCK_CENTER[i]
        a, b = grid[ra][ca], grid[rb][cb]
        if a and not b:
            grid[rb][cb] = a
            filled.append({"from": [ra, ca], "to": [rb, cb]})
        elif b and not a:
            grid[ra][ca] = b
            filled.append({"from": [rb, cb], "to": [ra, ca]})
        elif a and b and a != b:
            conflicts.append({"ring": [ra, ca], "block_center": [rb, cb], "ring_value": a, "block_center_value": b})
    return filled, conflicts


def _sync_one(text: str) -> tuple[str, dict]:
    grid = parse(text)
    filled, conflicts = [], []
    for i in range(8):
        (ra, ca), (rb, cb) = RING[i], BLOCK_CENTER[i]
        a, b = grid[ra][ca], grid[rb][cb]
        if a and not b:
            grid[rb][cb] = a
            filled.append({"from": [ra, ca], "to": [rb, cb]})
        elif b and not a:
            grid[ra][ca] = b
            filled.append({"from": [rb, cb], "to": [ra, ca]})
        elif a and b and a != b:
            conflicts.append({"ring": [ra, ca], "block_center": [rb, cb], "ring_value": a, "block_center_value": b})
    if not filled:
        return text, {"filled": [], "conflicts": conflicts}
    lines = text.split("\n")
    # 元の表の行を差し替える（表の前後の本文は触らない）
    idx = [i for i, ln in enumerate(lines) if ROW_RE.match(ln)]
    if len(idx) < N + 2:
        return text, {"filled": [], "conflicts": conflicts}
    first = idx[0]
    table = render_table(grid)
    lines[first:first + len(table)] = table
    return "\n".join(lines), {"filled": filled, "conflicts": conflicts}


def to_html(grid: list[list[str]], title: str = "曼荼羅") -> str:
    """9×9 の格子（3×3 のブロックごとに枠）。マスの中の [文字](x.md) は x.html へのリンクになる。"""
    rows = []
    for r in range(N):
        tds = []
        for c in range(N):
            cls = ["m"]
            if (r, c) == THEME:
                cls.append("theme")
            elif (r, c) in RING:
                cls.append("sub")
            elif (r, c) in BLOCK_CENTER:
                cls.append("sub2")
            if c % 3 == 0:
                cls.append("bl")
            if r % 3 == 0:
                cls.append("bt")
            body = md_html.inline(grid[r][c]) if grid[r][c] else ""
            tds.append(f'<td class="{" ".join(cls)}">{body}</td>')
        rows.append("<tr>" + "".join(tds) + "</tr>")
    return f'<table class="mandala" aria-label="{html.escape(title, quote=True)}">' + "".join(rows) + "</table>"


MANDALA_CSS = """table.mandala{border-collapse:collapse;table-layout:fixed;width:100%;max-width:60rem;font-size:.85rem}
table.mandala td{border:1px solid #8886;height:4.2rem;padding:.2rem;vertical-align:middle;text-align:center;word-break:break-word}
table.mandala td.bl{border-left:3px solid #888}table.mandala td.bt{border-top:3px solid #888}
table.mandala tr:last-child td{border-bottom:3px solid #888}table.mandala td:last-child{border-right:3px solid #888}
table.mandala+table.mandala{margin-top:1.5rem}
table.mandala td.theme{background:#e0a80033;font-weight:bold}table.mandala td.sub{background:#4a90d933}table.mandala td.sub2{background:#4a90d91a}"""


def locate(text: str, line: int, col: int) -> tuple[int, int] | None:
    """ファイルの行 line（1 から）・桁 col（バイト、1 から）にあるマスの (行, 列)（0 から）。表の外なら None。"""
    p = locate_page(text, line, col)
    return None if p is None else (p[1], p[2])


def locate_page(text: str, line: int, col: int) -> tuple[int, int, int] | None:
    """locate と同じで、何枚目の表か（0 から）も返す: (枚, 行, 列)。"""
    lines = text.split("\n")
    for k, (a, b) in enumerate(table_blocks(lines)):
        if a + 2 <= line - 1 < b:
            r = line - 1 - (a + 2)
            prefix = lines[line - 1].encode("utf-8")[:max(col - 1, 0)].decode("utf-8", errors="ignore")
            c = len(re.findall(r"(?<!\\)\|", prefix)) - 1
            return (k, r, min(max(c, 0), N - 1))
    return None


def link_cell(path: Path, r: int, c: int, kind: str = "note", page: int = 0) -> dict:
    """マス (r, c)（page 枚目の表）の文字から、新しいノート（kind=note）か別の曼荼羅（kind=mandala）を同じフォルダに作り、マスをそのリンクにする。
    すでにリンクのあるマス・空のマスには何もしない。"""
    import datetime as dt
    text = path.read_text(encoding="utf-8")
    grids = parse_all(text)
    if not 0 <= page < len(grids):
        return {"ok": False, "error": "その曼荼羅の表はありません"}
    grid = grids[page]
    cell = grid[r][c].strip()
    if not cell:
        return {"ok": False, "error": "マスが空です"}
    if md_html._LINK.search(cell):
        return {"ok": False, "error": "このマスにはもうリンクがあります"}
    stamp = dt.datetime.now().strftime("%y%m%d%H%M%S")
    name, n = stamp + ".md", 2
    while (path.parent / name).exists():
        name, n = f"{stamp}-{n}.md", n + 1
    now = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if kind == "mandala":
        body = new_text(cell, [], now)
    else:
        body = f"---\ntime: {now}\ntitle: {cell}\n---\n\n# {cell}\n\n"
    _atomic(path.parent / name, body)
    label = cell.replace("[", "(").replace("]", ")")
    link = f"[{label}]({name})"
    changed = {r}
    grid[r][c] = link
    # 副題は中心ブロックと周囲ブロックの 2 か所にある。同じ文字なら両方を同じリンクにする（sync が食い違いと見ないように）
    for a, b in zip(RING, BLOCK_CENTER):
        for src, dst in ((a, b), (b, a)):
            if (r, c) == src and grid[dst[0]][dst[1]].strip() == cell:
                grid[dst[0]][dst[1]] = link
                changed.add(dst[0])
    lines = text.split("\n")
    blocks = table_blocks(lines)
    if blocks:
        b0 = blocks[page][0]
        for rr in sorted(changed):
            if b0 + 2 + rr < blocks[page][1]:
                lines[b0 + 2 + rr] = "| " + " | ".join(v.replace("|", "\\|") for v in grid[rr]) + " |"
        _atomic(path, "\n".join(lines))
    else:
        _atomic(path, replace_tables(text, grids))
    return {"ok": True, "file": name, "cell": [r, c], "kind": kind, "page": page}


def _atomic(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".gnosis-tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def main(argv: list[str]) -> int:
    try:
        if len(argv) >= 3 and argv[0] == "new":
            p = Path(argv[1])
            if p.exists():
                raise ValueError("すでにあります（上書きしません）: " + str(p))
            import datetime as dt
            _atomic(p, new_text(argv[2], argv[3:], dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
            print(json.dumps({"ok": True, "file": str(p)}, ensure_ascii=False))
            return 0
        if len(argv) == 2 and argv[0] == "sync":
            p = Path(argv[1])
            text = p.read_text(encoding="utf-8")
            if not is_mandala(text):
                raise ValueError("曼荼羅ノート（mandala: true）ではありません")
            new, report = sync(text)
            if new != text:
                _atomic(p, new)
            print(json.dumps({"ok": True, **report}, ensure_ascii=False))
            return 0
        if len(argv) in (4, 5) and argv[0] == "link":
            p = Path(argv[1])
            pos = locate_page(p.read_text(encoding="utf-8"), int(argv[2]), int(argv[3]))
            if pos is None:
                raise ValueError("表のマスの上で実行してください")
            res = link_cell(p, pos[1], pos[2], argv[4] if len(argv) == 5 else "note", pos[0])
            print(json.dumps(res, ensure_ascii=False))
            return 0 if res["ok"] else 1
        if len(argv) in (4, 5, 6) and argv[0] == "link-cell":
            r, c = int(argv[2]), int(argv[3])
            if not (0 <= r < N and 0 <= c < N):
                raise ValueError("マスの位置が違います")
            res = link_cell(Path(argv[1]), r, c, argv[4] if len(argv) >= 5 else "note", int(argv[5]) if len(argv) == 6 else 0)
            print(json.dumps(res, ensure_ascii=False))
            return 0 if res["ok"] else 1
        if len(argv) == 2 and argv[0] == "show":
            print(json.dumps(parse(Path(argv[1]).read_text(encoding="utf-8")), ensure_ascii=False))
            return 0
    except (OSError, ValueError) as e:
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
