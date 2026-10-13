#!/usr/bin/env python3
"""ノート形式 v2 用の「展開」機能。

現在のノートを起点に、親（`### Parent`）/ 子（本文リンク）/ 文中
（`### BackLink`）/ 関連（`### Related`）方向へノートを辿り、集めた
ノートの本文を 1 つの使い捨て md ファイルへ集約する。front matter や
見張りコメントは含めない。

方向は現行形式（`note_format_v2._simple_parse`）の意味に合わせる:

    - 親   … `### Parent` のリンク（Index・グループなど、自分を子に持つ側）
    - 子   … 本文のリンク（自分が親として持つ側）
    - 文中 … `### BackLink` のリンク（本文で自分に言及している側）
    - 関連 … `### Related` のリンク（対称。独立した方向）

出力先は ROOT/.trash/T_<タイムスタンプ>.md（expand_s.py の展開出力と同じ場所。
`.trash` はドット始まりなので sync・検索・一覧に出ない）。編集しても
元ノートへは反映されない一方向のスナップショット。

モード:
    simple   … 親/子/文中/関連を区別せず、全リンクを平等に扱って深さ N まで
                BFS で辿る（1 つの共有カウンタ）。
    detailed … 5 項目の設定で探索する（深さ 0 = その探索はしない）:
                文中リンクの深さ / Context の深さ / Group の深さ /
                BackLink・Related の深さ（共通）/ BackLink の探索に日記を含めるか（t/f）。
                文中リンクの探索は、本文のリンクだけを辿る。Context・Group・BackLink/Related の
                探索は、起点（現在のノートと、文中リンクで届いたノート）から独立に行い、
                1 段階目はその種類の辺だけ、2 段階目以降は全種類の辺を 1 段階ずつ辿る。

detailed の設定は ROOT/.pkm_expand_prefs.json に「前回の設定」として自動で記録する。
名前を付けて保存したプリセットは ROOT/.pkm_expand_presets.json（明示的に保存したものだけ）。

CLI:
    expand_v2.py simple    ROOT START_FILE DEPTH
    expand_v2.py detailed  ROOT START_FILE BODY CONTEXT GROUP BR DIARY(t|f)
    expand_v2.py presets_list  ROOT                       名前<TAB>設定 の一覧
    expand_v2.py preset_save   ROOT NAME BODY CONTEXT GROUP BR DIARY [overwrite]
    expand_v2.py preset_delete ROOT NAME
    expand_v2.py get_prefs ROOT
"""
from __future__ import annotations

import datetime as _dt
import json
import re
import sys
from pathlib import Path

import note_format_v2 as v2

_PREFS_FILE = ".pkm_expand_prefs.json"
# \e / \se の使い捨て展開出力先（vault のゴミ箱と同じ場所。ドット始まりなので
# sync・検索・一覧・アプリの対象外）。
TRASH_DIR = ".trash"


# ---------------------------------------------------------------------------
# vault 読み込み・方向づけ
# ---------------------------------------------------------------------------

def _build_index(root: Path):
    by_name = v2._index(root)
    notes: dict[Path, dict] = {}
    for p in v2._iter_md(root):
        try:
            notes[p.resolve()] = v2._simple_parse(p)
        except Exception:  # noqa: BLE001
            continue
    ids: dict[Path, str] = {}
    id_to_path: dict[str, Path] = {}
    for k in notes:
        i = v2._nid(k, root)
        if i is not None:
            ids[k] = i
            id_to_path[i] = k
    return by_name, notes, ids, id_to_path


def _directions(note_path: Path, n: dict, root: Path, by_name,
                ids: dict[Path, str]) -> dict[str, set[str]]:
    """このノートから見た (親, 子, 文中, 関連) の id 集合。

    現行形式（`simple_sync` / `_simple_parse`）の意味に合わせる:

    - 親   = `### Parent` のリンク先（自分を子として持つ側）。
    - 子   = 本文のリンク先（自分が親として持つ側）。
    - 文中 = `### BackLink` のリンク先（本文で自分に言及している相手）。
    - 関連 = `### Related` のリンク先（対称。独立した方向として扱う）。
    """
    self_id = ids.get(note_path)

    def targets(lines: list[str]) -> set[str]:
        out: set[str] = set()
        for _disp, tg in v2._links_from(lines):
            tp = v2._resolve(tg, note_path.parent, root, by_name)
            if tp is None:
                continue
            i = ids.get(tp.resolve())
            if i and i != self_id:
                out.add(i)
        return out

    ctx = targets(n["parent"])
    grp = targets(n["group"])
    return {
        # 親 = Context ∪ Group（simple モードと関係リンク欄の表示用）
        "parent": ctx | grp,
        "context": ctx,
        "group": grp,
        "child": targets(n["body"]),
        "backlink": targets(n["back"]),
        "related": targets(n["related"]),
    }


# ---------------------------------------------------------------------------
# 収集（BFS）
# ---------------------------------------------------------------------------

Collected = tuple[list[str], dict]
"""(発見順の id リスト, {id: 発見元の id（起点は None）})。

`parent_of` は展開結果の木構造（目次のネストに使う）であって、ノート形式の
`### Parent` とは無関係 ── ここでの「親」は単に「どのノートを辿って
この id にたどり着いたか」を指す。
"""


def collect_simple(start_id: str, dir_of, depth: int) -> Collected:
    """親/子/文中/関連を区別せず、共有の深さ N まで辿る。順番は発見順。"""
    visited = {start_id}
    order = [start_id]
    parent_of: dict = {start_id: None}
    frontier = [start_id]
    for _ in range(max(depth, 0)):
        nxt: list[str] = []
        for nid in frontier:
            d = dir_of(nid)
            for neighbor in d["parent"] | d["child"] | d["backlink"] | d["related"]:
                if neighbor not in visited:
                    visited.add(neighbor)
                    order.append(neighbor)
                    parent_of[neighbor] = nid
                    nxt.append(neighbor)
        frontier = nxt
        if not frontier:
            break
    return order, parent_of


# 日記ノート: 題が `YYYY-MM-DD-曜日2文字`（例: 2026-10-13-TU-…）で始まるもの
DIARY_TITLE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-[A-Z]{2}(?:-|$)")


def is_diary_title(title: str) -> bool:
    return bool(DIARY_TITLE_RE.match(title or ""))


# 全種類の辺（文中 = child、Context、Group、BackLink、Related）。2 段階目以降はこれを辿る。
ALL_KINDS = ("child", "context", "group", "backlink", "related")


def _search(anchor: str, dir_of, depth: int, first_kinds, skip_backlink=None) -> Collected:
    """起点から深さ N の幅優先で集める（1 回の探索）。

    - 1 段階目は first_kinds の辺だけを辿る。
    - 2 段階目以降は ALL_KINDS（全種類）の辺を 1 段階ずつ辿る。
    - skip_backlink(id) が真なら、BackLink の辺をたどった先のそのノートは集めない
      （他の種類の辺で届いたときは除外しない）。
    探索ごとに自分の訪問済み集合を持つ（最短の深さで見つけるので、深さの数え方が
    経路の順に左右されない）。循環があっても訪問済みは再訪しないので止まる。
    """
    visited = {anchor}
    order = [anchor]
    parent_of: dict = {anchor: None}
    frontier = [anchor]
    for step in range(max(depth, 0)):
        kinds = first_kinds if step == 0 else ALL_KINDS
        nxt: list[str] = []
        for nid in frontier:
            d = dir_of(nid)
            for kind in kinds:
                for neighbor in sorted(d[kind]):  # 出力が実行ごとに変わらないよう並べる
                    if kind == "backlink" and skip_backlink is not None and skip_backlink(neighbor):
                        continue
                    if neighbor not in visited:
                        visited.add(neighbor)
                        order.append(neighbor)
                        parent_of[neighbor] = nid
                        nxt.append(neighbor)
        frontier = nxt
        if not frontier:
            break
    return order, parent_of


def collect_detailed(start_id: str, dir_of, body_depth: int, context_depth: int,
                      group_depth: int, br_depth: int, skip_backlink=None) -> Collected:
    """詳細モード: 次の 4 つの深さを独立に適用して、結果を統合する。

    1. 文中（本文のリンク）: 起点から本文リンクだけを body_depth 段階辿る
       （Context や BackLink などは数えない）。
    2. 1 で届いたノートと起点を「起点」とし、各起点から次の探索をそれぞれ行う
       （深さ 0 の探索はしない）:
       - Context: 1 段階目は Context の辺だけ、2 段階目以降は全種類。
       - Group:   1 段階目は Group の辺だけ、2 段階目以降は全種類。
       - BackLink / Related: 共通の深さ。1 段階目は BackLink と Related の両方、2 段階目以降は全種類。
    3. 全体を通して同じノートは 1 回だけ（発見順に最初のものを残す）。
    skip_backlink(id) が真のノートは、BackLink の辺をたどった先として集めない。
    """
    order = [start_id]
    seen = {start_id}
    parent_of: dict = {start_id: None}

    def _merge(chain: list[str], pof: dict) -> None:
        for nid in chain[1:]:
            if nid not in seen:
                seen.add(nid)
                order.append(nid)
                parent_of[nid] = pof[nid]

    # 文中リンクの探索は、その先を全種類に広げず、文中だけを辿る
    body_only = _search_body_only(start_id, dir_of, body_depth)
    _merge(*body_only)
    anchors = body_only[0]

    for anchor in anchors:
        for depth, first in ((context_depth, ("context",)), (group_depth, ("group",)),
                             (br_depth, ("backlink", "related"))):
            if depth <= 0:
                continue
            _merge(*_search(anchor, dir_of, depth, first, skip_backlink))

    return order, parent_of


def _search_body_only(start_id: str, dir_of, depth: int) -> Collected:
    """文中リンクだけを辿って深さ N まで集める（毎段階、文中リンクのみ）。"""
    visited = {start_id}
    order = [start_id]
    parent_of: dict = {start_id: None}
    frontier = [start_id]
    for _ in range(max(depth, 0)):
        nxt: list[str] = []
        for nid in frontier:
            for neighbor in sorted(dir_of(nid)["child"]):
                if neighbor not in visited:
                    visited.add(neighbor)
                    order.append(neighbor)
                    parent_of[neighbor] = nid
                    nxt.append(neighbor)
        frontier = nxt
        if not frontier:
            break
    return order, parent_of


# ---------------------------------------------------------------------------
# 出力レンダリング
# ---------------------------------------------------------------------------

def _anchor(index: int) -> str:
    return f"note-{index}"


_H1_RE = re.compile(r"^#\s+(.+?)\s*$")


def _body_without_own_h1(n: dict) -> list[str]:
    """本文の先頭が自分のタイトルと同じ H1 なら、見出しの二重表示を避けて
    その行（と直後の空行）を取り除く（展開側で `## タイトル` を別途出すため）。"""
    body = list(n["body"])
    idx = 0
    while idx < len(body) and body[idx].strip() == "":
        idx += 1
    if idx < len(body):
        m = _H1_RE.match(body[idx].strip())
        if m and m.group(1) == n["title"]:
            idx += 1
            while idx < len(body) and body[idx].strip() == "":
                idx += 1
            return body[idx:]
    return body


_REL_SECTIONS = (
    ("parent", "親"),
    ("related", "関連"),
    ("body", "子（本文）"),
    ("back", "バックリンク"),
)


def _relation_lines(note_path: Path, n: dict, root: Path, by_name, tmp_dir: Path) -> list[str]:
    """このノートの関係リンクを現行形式のセクション単位（親 / 関連 / 子（本文）/
    バックリンク）で書き出す。展開先に含まれていないものも含めてそのまま
    リンクとして書き出す（そこから先は展開しない ── あくまで「このノートは
    他に何にリンクしているか」を見せるだけ）。リンク先は展開ファイル（.trash
    配下）から見た相対パスに直す。"""
    lines: list[str] = []
    for key, label in _REL_SECTIONS:
        links: list[str] = []
        src = n[key] + n.get("group", []) if key == "parent" else n[key]
        for disp, tg in v2._links_from(src):
            tp = v2._resolve(tg, note_path.parent, root, by_name)
            rel = v2._rel(tmp_dir, tp) if tp is not None else tg
            links.append(f"[{disp}]({rel})")
        if links:
            lines.append(f"- {label}: " + "、".join(links))
    return lines


def _toc_lines(start_id: str, order: list[str], parent_of: dict, notes_by_id: dict[str, dict],
               anchors: dict[str, str]) -> list[str]:
    """`parent_of`（＝どのノートを辿ってこの id に着いたか）に沿って、
    段落（インデント）で経路が分かる目次を作る。"""
    children: dict[str, list[str]] = {}
    for nid in order:
        p = parent_of.get(nid)
        if p is not None:
            children.setdefault(p, []).append(nid)

    lines: list[str] = []

    def walk(nid: str, depth: int) -> None:
        indent = "  " * depth
        lines.append(f"{indent}- [{notes_by_id[nid]['title']}](#{anchors[nid]})")
        for c in children.get(nid, []):
            walk(c, depth + 1)

    walk(start_id, 0)
    return lines


def _render(order: list[str], parent_of: dict, notes_by_id: dict[str, dict],
            root: Path, by_name, id_to_path: dict[str, Path], tmp_dir: Path) -> str:
    anchors = {i: _anchor(idx) for idx, i in enumerate(order)}
    start_id = order[0]
    start_title = notes_by_id[start_id]["title"]

    out = [f"# 展開: {start_title}", "", "## 目次", ""]
    out.extend(_toc_lines(start_id, order, parent_of, notes_by_id, anchors))
    out.append("")
    out.append("---")

    for i in order:
        n = notes_by_id[i]
        out.append("")
        out.append(f'<a id="{anchors[i]}"></a>')
        out.append(f"## {n['title']}")
        out.append("")
        out.extend(_body_without_own_h1(n))
        rel_lines = _relation_lines(id_to_path[i], n, root, by_name, tmp_dir)
        if rel_lines:
            out.append("")
            out.append("**関係リンク:**")
            out.extend(rel_lines)
        out.append("")
        out.append("---")

    text = "\n".join(out)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.rstrip() + "\n"


def _make_filename() -> str:
    ts = _dt.datetime.now().strftime("%y%m%d%H%M%S")
    return f"T_{ts}.md"


# ---------------------------------------------------------------------------
# 詳細モードの設定（前回の設定とプリセット）
# ---------------------------------------------------------------------------
#
# 探索設定は 5 項目: body（文中リンクの深さ）/ context / group / br（BackLink と Related の
# 共通の深さ）/ diary（BackLink の探索に日記を含めるか。True/False）。
#
#   前回の設定 … ROOT/.pkm_expand_prefs.json   （展開するたびに自動で更新される）
#   プリセット … ROOT/.pkm_expand_presets.json  （名前を付けて明示的に保存したものだけ）
#
# 両者は別のファイル。展開や設定変更で、保存済みのプリセットが書き換わることはない。
# どちらも vault（ノートの置き場）の中なので、Vim を再起動してもプラグインを更新しても残る。

_PRESETS_FILE = ".pkm_expand_presets.json"
SETTING_KEYS = ("body", "context", "group", "br")


def normalize_settings(body, context, group, br, diary) -> dict:
    """5 項目を検証して dict にする。深さは 0 以上の整数、diary は t/f（True/False/1/0 も可）。"""
    out: dict = {}
    for k, v in zip(SETTING_KEYS, (body, context, group, br)):
        n = int(v)
        if n < 0:
            raise ValueError(f"{k} の深さは 0 以上: {v}")
        out[k] = n
    if isinstance(diary, str):
        d = diary.strip().lower()
        if d in ("t", "true", "1"):
            diary = True
        elif d in ("f", "false", "0"):
            diary = False
        else:
            raise ValueError(f"diary は t か f: {diary}")
    out["diary"] = bool(diary)
    return out


def format_settings(st: dict) -> str:
    """Vim が読む 1 行（空白区切り）: body context group br t|f"""
    return f"{st['body']} {st['context']} {st['group']} {st['br']} {'t' if st['diary'] else 'f'}"


def _write_json(fp: Path, data) -> None:
    """途中で壊れないよう、一時ファイルに書いてから置き換える。"""
    tmp = fp.with_name(fp.name + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(fp)


def _load_prefs(root: Path) -> dict | None:
    fp = root / _PREFS_FILE
    if not fp.exists():
        return None
    try:
        d = json.loads(fp.read_text(encoding="utf-8"))
        # 旧形式（child / parent / backlink / related = 探索の意味が違う）は読まない
        return normalize_settings(d["body"], d["context"], d["group"], d["br"], d.get("diary", True))
    except Exception:  # noqa: BLE001
        return None


def _save_prefs(root: Path, st: dict) -> None:
    _write_json(root / _PREFS_FILE, st)


def load_presets(root: Path) -> dict[str, dict]:
    """名前 → 設定。ファイルが無い・壊れているときは空。壊れた項目は飛ばす。"""
    fp = root / _PRESETS_FILE
    if not fp.exists():
        return {}
    try:
        raw = json.loads(fp.read_text(encoding="utf-8")).get("presets", {})
    except Exception:  # noqa: BLE001
        return {}
    out: dict[str, dict] = {}
    for name, d in raw.items():
        try:
            out[name] = normalize_settings(d["body"], d["context"], d["group"], d["br"], d["diary"])
        except Exception:  # noqa: BLE001
            continue
    return out


def _check_preset_name(name: str) -> str:
    name = (name or "").strip()
    if not name or any(c in name for c in "\t\n\r"):
        raise ValueError("プリセット名が空、またはタブ・改行を含んでいる")
    return name


def save_preset(root: Path, name: str, st: dict, overwrite: bool = False) -> str:
    """プリセットを保存する。同じ名前があって overwrite=False なら何もせず "exists" を返す
    （確認なしに上書きしない）。保存したら "saved"、上書きしたら "overwritten"。"""
    name = _check_preset_name(name)
    presets = load_presets(root)
    existed = name in presets
    if existed and not overwrite:
        return "exists"
    presets[name] = st
    _write_json(root / _PRESETS_FILE, {"version": 1, "presets": presets})
    return "overwritten" if existed else "saved"


def delete_preset(root: Path, name: str) -> bool:
    """プリセットを削除する（ノートには一切触れない）。無ければ False。"""
    presets = load_presets(root)
    if name not in presets:
        return False
    del presets[name]
    _write_json(root / _PRESETS_FILE, {"version": 1, "presets": presets})
    return True


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _run(root: Path, start_file: Path, order_fn, holder: dict | None = None) -> Path:
    by_name, notes, ids, id_to_path = _build_index(root)
    start_id = ids.get(start_file.resolve())
    if start_id is None:
        raise SystemExit("expand_v2: 起点ノートが vault 内で見つからない（sync 済みか確認して）")

    dir_cache: dict[str, dict[str, set[str]]] = {}

    def dir_of(nid: str) -> dict[str, set[str]]:
        if nid not in dir_cache:
            p = id_to_path[nid]
            dir_cache[nid] = _directions(p, notes[p], root, by_name, ids)
        return dir_cache[nid]

    if holder is not None:
        # order_fn が日記かどうかを引けるように渡す
        holder["is_diary"] = lambda nid: is_diary_title(notes[id_to_path[nid]]["title"])
    order, parent_of = order_fn(start_id, dir_of)
    notes_by_id = {i: notes[id_to_path[i]] for i in order}

    tmp_dir = root / TRASH_DIR
    tmp_dir.mkdir(parents=True, exist_ok=True)
    text = _render(order, parent_of, notes_by_id, root, by_name, id_to_path, tmp_dir)
    out_path = tmp_dir / _make_filename()
    out_path.write_text(text, encoding="utf-8")
    return out_path


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    mode = argv[1]
    root = Path(argv[2]).resolve()

    if mode == "get_prefs":
        prefs = _load_prefs(root)
        if prefs:
            print(format_settings(prefs))
        return 0

    # ---- プリセット（ノートには触れない） ----
    if mode == "presets_list":
        for name, st in sorted(load_presets(root).items()):
            print(f"{name}\t{format_settings(st)}")
        return 0
    if mode == "preset_save":
        # preset_save ROOT NAME BODY CONTEXT GROUP BR DIARY [overwrite]
        if len(argv) < 9:
            print("usage: expand_v2.py preset_save ROOT NAME BODY CONTEXT GROUP BR DIARY [overwrite]", file=sys.stderr)
            return 2
        try:
            st = normalize_settings(argv[4], argv[5], argv[6], argv[7], argv[8])
            res = save_preset(root, argv[3], st, overwrite=len(argv) > 9 and argv[9] == "overwrite")
        except ValueError as e:
            print(f"error: {e}", file=sys.stderr)
            return 2
        print(res)
        return 0
    if mode == "preset_delete":
        print("deleted" if delete_preset(root, argv[3] if len(argv) > 3 else "") else "notfound")
        return 0

    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    start_file = Path(argv[3])

    if mode == "simple":
        if len(argv) < 5:
            print("usage: expand_v2.py simple ROOT START_FILE DEPTH", file=sys.stderr)
            return 2
        depth = int(argv[4])
        out_path = _run(root, start_file, lambda sid, dir_of: collect_simple(sid, dir_of, depth))
    elif mode == "detailed":
        if len(argv) < 9:
            print("usage: expand_v2.py detailed ROOT START_FILE BODY CONTEXT GROUP BR DIARY(t|f)",
                  file=sys.stderr)
            return 2
        try:
            st = normalize_settings(argv[4], argv[5], argv[6], argv[7], argv[8])
        except ValueError as e:
            print(f"error: {e}", file=sys.stderr)
            return 2
        holder: dict = {}
        out_path = _run(
            root, start_file,
            lambda sid, dir_of: collect_detailed(
                sid, dir_of, st["body"], st["context"], st["group"], st["br"],
                skip_backlink=None if st["diary"] else holder["is_diary"]),
            holder)
        _save_prefs(root, st)  # 前回の設定だけ更新する（プリセットには触れない）
    else:
        print(f"unknown mode: {mode}", file=sys.stderr)
        return 2

    print(str(out_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
