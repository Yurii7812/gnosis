#!/usr/bin/env python3
"""紙のPKM（フォルゲゼッテル）連携（Gnosis 用）。

紙に書いたノート（フォルゲゼッテル）をスキャンして vault へ取り込む。

- スキャン画像にフォルゲゼッテルIDを付けて vault 直下へ移す（GUI: folgezettel_scan.py）
- 各スキャンは**タイムスタンプ名ノート**（title=正式なフォルゲゼッテルID、本文に画像 `![](ID.ext)`）。
  画像は `<ID>.<拡張子>` として同じフォルダに置き、ノートが埋め込む。
- `Index-write.md`（手書き）::

      キーワード: フォルゲゼッテル
      バナナ(ばなな): 1,1a10b,3
      オザーク(ドラマ): 2

  の各行から、Paper-Zettelkasten-Index（`Paper-Zettelkasten-Index.md` 固定）の
  キーワードリンクを生成する。旧タイムスタンプ名の Index は regen / create が
  `Paper-Zettelkasten-Index.md` へ改名して移行する（他ノートからのリンクも書き換える）。**複数IDのキーワードはグループノート**
  （`attribute: group`、中に各IDノートへのリンク）、単一IDは直接リンク。
- `Folgezettel-Index.md`: 存在する全IDを自然順で並べた一覧。紙の日記があれば末尾に `diary`（日記一覧）が並ぶ。
- **紙の日記**: `\\F` の GUI で「日記として登録」した画像は、日記が書かれた日付ごとに 1 ノート
  （タイムスタンプ名・題 `YYYY-MM-DD-曜日2文字`（例 2026-10-13-TU。曜日は日付から自動計算。デジタル日記と同じ形）にまとめる。
  複数ページは同じノートに画像を並べる。ノートの `time:` はスキャンした日時で、日記の日付とは別。
  日記があると Paper-Zettelkasten-Index のキーワードに「日記」が 1 つ自動で入り、
  開くと日記の一覧（グループ `紙の日記`）になり、**年・月別**に辿れる: 「日記」→ 月グループ（題 `YYYY-MM`）→ 日（日付順）。
  **年グループ（題 `YYYY`）は、日記が 2 つ以上の年にまたがってから**作る（それまでは「日記」の直下に月グループが並ぶ）。デジタル日記（`\\d`）とは題の形が違い、
  `\\d` の日記グループ（題 `日記`）とも別のノート。
- **トピック**（`1-仏教` のようにトピック名を付けて取り込んだ画像）: `1-Index` のグループは作らず、番号のスキャンノート
  （ID `1`）の `BranchGroup:` にトピックのノートを入れる。親トピックは子より先に並べるだけで、段（インデント）は付けない。
  並びは手で直せて、regen は直した並びを変えない。旧形式の `1-Index` グループがあれば、
  その並びを `BranchGroup:` に引き継いでから、ごみ箱へ送る（グループを指していたリンクは ID ノートへ向け直す）。
- 生成物（Index・グループ・Folgezettel-Index・スキャンノート）の本文は regen が
  毎回まるごと作り直す（管理コメントは書かない）。`Index-write.md` だけは
  手書きの本文＝キーワード行をサイ博（並び順のみ整える）。
- `Index-write.md` と `Folgezettel-Index.md` の `### Context` は
  Paper-Zettelkasten-Index へのリンク（regen が無ければ足す）。
- `create` 時に vault 親Index（`index.md`）へ Paper-Zettelkasten-Index へのリンクを足す
  （空行は入れない。最後のリンク行の直後に 1 行）。
- 実行後は `note_format_v2.simple_sync()` で SYN 同期まで行う。

CLI::

    paper_pkm.py create ROOT          # 紙PKM Index一式を作成（既存なら再利用）し Index のパスを表示
    paper_pkm.py migrate ROOT         # 旧タイムスタンプ名の Index を Paper-Zettelkasten-Index.md へ移行
    paper_pkm.py diary ROOT DEST YYYY-MM-DD FILE...   # 画像を紙の日記として登録（複数ページ可）
    paper_pkm.py regen ROOT [--no-sync]   # Index・グループ・Folgezettel-Index を再生成
    paper_pkm.py ids ROOT             # ID → ノートの対応を表示（確認用）

キーワード行の並びは `(…)` の中身が本体のよみと一致すればそれをよみとして使い、
一致しなければ修飾語とみなして本体のよみで並べる（`バナナ(ばなな)` → ばなな、
`オザーク(ドラマ)` → おざーく）。`\\S`（sort_yomi.py --keyword-lines）と同じ規則。
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gnosis_i18n import tr  # noqa: E402
import japanese_yomi as jy  # noqa: E402

INDEX_WRITE = "Index-write.md"
OLD_INDEX_WRITE = "Index_write.md"
FOLGE_INDEX = "Folgezettel-Index.md"
DEFAULT_INDEX_TITLE = "Paper-Zettelkasten-Index"
# 紙の PKM の生成物（Index・Index-write・Folgezettel-Index・folgezettel-Index-N・頂点のノート）は、ふつうのノート
# （ファイル名はタイムスタンプ）。ファイル名ではなく題で探す（2026-10-27）。頂点のノートの題は Index と同じ Paper-Zettelkasten-Index（グループではない）

ID_PATTERN = re.compile(r"^\d+(?:[a-z]+\d+)*[a-z]*$")
FULL_ID_PATTERN = re.compile(r"^(?:[A-Z]{1,4}-)?\d+(?:[a-z]+\d+)*[a-z]*$")  # 印つきの番号も受ける
# キーと ID 部に `:` を許さない（`time: 2026-01-01 00:00:00` のような front matter を
# 後方一致でキーワード行と誤認しないため。`[^:]+?` の後退を防ぐ）。
KEYWORD_LINE_RE = re.compile(
    r"^(?P<key>[^:()]+?)\s*:\s*(?P<ids>[^:]+)$"
)

# 旧い front matter のキー（廃止）。新規には書かない。読むのは移行（migrate_legacy_metadata）だけ。
# ノートの種類は title・画像の参照・リンク階層で判定する（下の「ノートの種類の判定」）。
LEGACY_FM_KEYS = (
    "folgezettel", "paper_index", "paper_diary", "paper_diary_month", "paper_diary_year",
    "paper_keyword", "paper_topic", "paper_topic_index", "folgezettel_index",
)
DIARY_KEYWORD = "日記"                   # Paper-Zettelkasten-Index のキーワード表示名
DIARY_GROUP_TITLE = "紙の日記"           # 紙の日記の木の一番上のノートの題（グループではない普通のノート。timeline: true）
OLD_DIARY_GROUP_TITLE = "日記"           # 旧い題（グループだった頃。regen が「紙の日記」の普通のノートに直す）
PAPER_YEAR_RE = re.compile(r"^(\d{4})-紙$")        # 木の年のノートの題（デジタル日記の 2026 や夢の 2026-夢 と同じ付け方）
PAPER_MONTH_RE = re.compile(r"^(\d{4}-\d{2})-紙$")  # 木の月のノートの題
DIARY_IMAGE_PREFIX = "paper-diary-"
# スキャン由来のノート（紙の日記・スキャンノート・トピックノート）の印。デジタル日記の「今日のノート」に載せない
SCAN_SOURCE_LINE = "source: scan"
# トピックノートの、表示順のための親トピック（表示名。例: 1-仏教）。階層やインデントは作らない
TOPIC_PARENT_KEY = "topic_parent"

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp", ".webp"}


# ---------------------------------------------------------------------------
# ID
# ---------------------------------------------------------------------------


def natural_key(text: str):
    return [
        int(part) if part.isdigit() else part.casefold()
        for part in re.split(r"(\d+)", text)
    ]


# 紙のノートの番号の印（PA・PB…）。`PA-1a2` の形（印は大文字 1〜4 字）。印の無い番号（`1a2`）は旧い形（regen が印つきに直す）
PREFIX_PAT = r"[A-Z]{1,4}"
ID_BODY_PAT = r"\d+(?:[a-z]+\d+)*[a-z]*"
PREFIXED_ID_RE = re.compile(rf"^({PREFIX_PAT})-({ID_BODY_PAT})$")


def normalize_id(raw: str) -> str:
    """番号をそろえる。印つき（`pa-1A2` → `PA-1a2`）は印を大文字・番号を小文字に、印なしは小文字に。"""
    t = unicodedata.normalize("NFKC", raw).strip()
    m = re.match(r"^([A-Za-z]{1,4})-(.+)$", t)
    if m and re.fullmatch(ID_BODY_PAT, m.group(2).lower()):
        return m.group(1).upper() + "-" + m.group(2).lower()
    return t.lower()


def split_paper_title(title: str) -> tuple[str, str]:
    """`PA-1a2` → ('PA', '1a2')。印の無い題は ('', 題)。"""
    m = PREFIXED_ID_RE.match(title or "")
    return (m.group(1), m.group(2)) if m else ("", title or "")


def with_prefix(prefix: str, fid: str) -> str:
    """印の無い番号に印を付ける（もう付いていればそのまま）。"""
    return fid if PREFIXED_ID_RE.match(fid) or not prefix else f"{prefix}-{fid}"


def split_id_tokens(fid: str) -> list[str]:
    return re.findall(r"\d+|[a-z]+", fid)


def parent_id(fid: str) -> Optional[str]:
    tokens = split_id_tokens(fid)
    if len(tokens) <= 1:
        return None
    return "".join(tokens[:-1])


def increment_letters(letters: str) -> str:
    chars = list(letters)
    index = len(chars) - 1
    while index >= 0:
        if chars[index] != "z":
            chars[index] = chr(ord(chars[index]) + 1)
            return "".join(chars)
        chars[index] = "a"
        index -= 1
    return "a" + "".join(chars)


def next_sibling_id(fid: str) -> str:
    m = re.search(r"([a-z]+|\d+)$", fid)
    if not m:
        raise ValueError("IDの末尾を判定できません")
    tail = m.group(1)
    replacement = str(int(tail) + 1) if tail.isdigit() else increment_letters(tail)
    return fid[: m.start(1)] + replacement


def child_id(fid: str) -> str:
    if not fid:
        raise ValueError("基準IDがありません")
    return fid + ("a" if fid[-1].isdigit() else "1")


# ---------------------------------------------------------------------------
# Index_write のキーワード行
# ---------------------------------------------------------------------------


def reading_for_display(key: str) -> str:
    """キーワード行のよみ（pykakasi 自動推定・ひらがな）。"""
    return jy.kata2hira(jy.reading_for(key))


def parse_keyword_line(line: str) -> Optional[dict]:
    """`キーワード(よみ): 1,1a10b,3` を解析する。無効な行は None。"""
    m = KEYWORD_LINE_RE.match(line.strip())
    if not m:
        return None
    key = m.group("key").strip()
    raw_ids = m.group("ids").strip()
    if not key:
        return None
    ids = [normalize_id(x) for x in re.split(r"[,\s]+", raw_ids) if x.strip()]
    if not ids or not all(ID_PATTERN.fullmatch(i) for i in ids):
        return None
    return {
        "key": key,
        "display": key,
        "ids": ids,
    }


def keyword_reading(line: str) -> Optional[str]:
    """キーワード行のよみ。キーワード行でなければ None（sort_yomi 連携用）。"""
    entry = parse_keyword_line(line)
    if entry is None:
        return None
    return reading_for_display(entry["key"])


def keyword_sort_key(entry: dict):
    return jy.reading_key(reading_for_display(entry["key"]))


# ---------------------------------------------------------------------------
# ノート読み書き
# ---------------------------------------------------------------------------


# 上側の見出し。現行は `### Context`（旧 `### Parent`）。旧表記も読む。
CONTEXT_HEAD = "### Context"
CONTEXT_HEADS = ("### Context", "### Parent")


def _is_context_head(ln: str) -> bool:
    return ln.strip() in CONTEXT_HEADS


# 関係の節の見出し（本文はこれより前）。中身が空の節は見出しごと無いので、どれが最初に来るかは決まっていない。
SECTION_HEADS = ("### ParentBranch", "### Context", "### Parent", "### Group", "### ChildBranch", "### Related", "### BackLink",
                 "ChildBranch:", "Related:", "BackLink:")  # ParentBranch: は本文の上の先頭のブロック


def _is_section_head(ln: str) -> bool:
    return ln.strip() in SECTION_HEADS


def _first_section(lines: list[str]) -> int | None:
    return next((k for k, ln in enumerate(lines) if _is_section_head(ln)), None)


def parse_note(text: str) -> tuple[list[str], list[str]]:
    """front matter（`---` の内側）と本文に分ける。"""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return lines[1:i], lines[i + 1 :]
    return [], lines


def title_of(fm: list[str], body: list[str], default: str = "") -> str:
    """題。先頭の # 見出し（H1）が正。H1 が無い古いノートだけ front matter の title:。"""
    for ln in body:
        m = re.match(r"^#\s+(\S.*?)\s*#*\s*$", ln)
        if m:
            return m.group(1).strip()
    return fm_value(fm, "title") or default


def read_note(path: Path) -> tuple[list[str], list[str]]:
    return parse_note(path.read_text(encoding="utf-8"))


def merge_note_body(existing: list[str], generated: list[str]) -> list[str]:
    """紙PKMの自動生成ノートの本文を、手で書いた内容を消さずに作る。

    規則（作り方）は守る。手書きは消さない:
    - 見出し・画像などの規則の行は、無いものだけを `### Context` の前に足す（既にあれば足さない）。
    - `### Context` の中の規則のリンクは、無いものだけを足す（既存の行は残す）。
    - `# 見出し` は既存に `# ` 見出しがあれば足さない（タイトルを二重にしない）。
    - 行を消すことは、しない（削除は手でする）。
    - 空行は自動では足さない。既にある空行も消さない。例外は、本文がまだ見出しだけ（新しく作るノート）のとき
      だけ、生成した `# 見出し` の次の空行（通常のノートと同じ「見出し・空行・本文」）を保つ。
    """
    gen_head: list[str] = []
    gen_parent: list[str] = []
    for ln in generated:
        if _is_context_head(ln) or gen_parent:
            gen_parent.append(ln)
        else:
            gen_head.append(ln)

    out = list(existing)
    present = {ln.strip() for ln in out if ln.strip()}
    h1_exists = any(re.match(r"^# ", ln) for ln in out)
    # 本文がまだ見出しだけか（新しく作るノート）。そのとき、見出しの次の空行を整える
    only_heading = all((not ln.strip()) or ln.startswith("# ") for ln in out)

    def _is_heading(ln: str) -> bool:
        return ln.lstrip().startswith("### ")

    # 1) 見出し・画像など: `### Context` の前に足す（無ければ末尾）
    head_add: list[str] = []
    for ln in gen_head:
        t = ln.strip()
        if not t or t in present:
            continue
        if t.startswith("# ") and h1_exists:
            continue
        head_add.append(ln)
        present.add(t)
    if head_add:
        p = next((k for k, ln in enumerate(out) if _is_section_head(ln)), len(out))
        # 自動で空行は足さない（ノートの空行は利用者が自由に入れる。既にある空行も消さない）。
        out[p:p] = list(head_add)
    if only_heading:
        h = next((k for k, ln in enumerate(out) if ln.strip()), None)
        if h is not None and out[h].startswith("# ") and h + 1 < len(out) and out[h + 1].strip():
            out.insert(h + 1, "")  # 新しいノート: 見出しの次に空行 1 つ

    # 2) Parent のリンク: 無いものだけを、Parent の節の最後へ足す（節が無ければ作る）
    parent_links = [ln for ln in gen_parent[1:] if ln.strip() and ln.strip() not in present]
    if parent_links:
        p = next((k for k, ln in enumerate(out) if _is_context_head(ln)), None)
        if p is None:
            fs = _first_section(out)
            if fs is not None:
                # Context が無く Group 等だけある → その手前に Context を作る
                out[fs:fs] = [CONTEXT_HEAD, *parent_links]
            else:
                out += [CONTEXT_HEAD, *parent_links]
        else:
            e = next((k for k in range(p + 1, len(out)) if _is_heading(out[k])), len(out))
            last = e
            while last > p + 1 and not out[last - 1].strip():
                last -= 1
            out[last:last] = parent_links
    return out


def write_note(path: Path, fm: list[str], body: list[str], keep_trailing_blank: bool = False) -> None:
    """ノートを書く。通常のノートと同じ書式にする: front matter の終わりの `---` と最初の `# 見出し` の間に
    空行を 1 つ置く（本文が空行で始まっていればそれを使う）。
    keep_trailing_blank: 本文の末尾の空行を残す（紙の日記ノートの、画像のあとの空行など）。"""
    text = "\n".join(body) if keep_trailing_blank else "\n".join(body).rstrip("\n")
    if text.strip() and body and body[0].strip():
        text = "\n" + text  # `---` と最初の行の間の空行
    path.write_text("---\n" + "\n".join(fm) + "\n---\n" + text + "\n", encoding="utf-8")


def fm_value(fm: list[str], key: str) -> Optional[str]:
    for ln in fm:
        m = re.match(rf"^{re.escape(key)}\s*:\s*(.+?)\s*$", ln)
        if m:
            value = m.group(1).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            return value
    return None


def _rel(base_dir: Path, target: Path) -> str:
    try:
        return Path(os.path.relpath(target, base_dir)).as_posix()
    except ValueError:
        return target.as_posix()


def markdown_link(display: str, target: Path, base_dir: Path,
                  frag: Optional[str] = None) -> str:
    link = f"[{display}]({_rel(base_dir, target)})"
    if frag:
        link = link[:-1] + f"#{frag})"
    return link


# 名前空間（紙の番号の印ごとの組）。印が 1 つだけなら今までの名前（Index-write など）、複数あるときは末尾に印を付ける
# （Paper-Zettelkasten-Index-PA・Index-write-PA・Folgezettel-Index-PA・folgezettel-Index-PA-1）。regen が名前空間ごとに切り替える
_NS = {"prefix": "", "multi": False}


def ns_set(prefix: str, multi: bool) -> None:
    _NS["prefix"] = prefix
    _NS["multi"] = bool(multi and prefix)


def ns_title(kind: str, prefix: Optional[str] = None, multi: Optional[bool] = None) -> str:
    """今の名前空間の生成物の題。kind: index（グループ）・iw（Index-write）・fi（Folgezettel-Index）。"""
    base = {"index": DEFAULT_INDEX_TITLE, "iw": INDEX_WRITE[:-3], "fi": FOLGE_INDEX[:-3]}[kind]
    p = _NS["prefix"] if prefix is None else prefix
    m = _NS["multi"] if multi is None else multi
    return f"{base}-{p}" if (m and p) else base


def folge_index_display(fid: str, prefix: Optional[str] = None, multi: Optional[bool] = None) -> str:
    """番号専用ノート folgezettel-Index-N の表示名（印が複数のときは folgezettel-Index-PA-N）。"""
    p = _NS["prefix"] if prefix is None else prefix
    m = _NS["multi"] if multi is None else multi
    return f"folgezettel-Index-{p + '-' if (m and p) else ''}{fid}"


def folge_index_path(root: Path, fid: str) -> Path:
    return named_path(root, folge_index_display(fid))


def top_level_ids(folge: dict[str, Path]) -> list[str]:
    return sorted((f for f in folge if parent_id(f) is None), key=natural_key)


_RESERVED: set[Path] = set()           # これから作るノートに割り当てたパス（まだファイルが無いもの）
_NAMED: dict[tuple[str, str, object], Path] = {}


def unique_note_path(root: Path, when: Optional[datetime] = None) -> Path:
    base = when or datetime.now()
    for i in range(3660):
        candidate = Path(root) / (
            (base + timedelta(seconds=i)).strftime("%y%m%d%H%M%S") + ".md"
        )
        if not candidate.exists() and candidate not in _RESERVED:
            return candidate
    raise RuntimeError("空きタイムスタンプが見つかりません")


def reset_name_cache() -> None:
    _RESERVED.clear()
    _NAMED.clear()


def find_titled(root: Path, title: str, group: Optional[bool] = None) -> Optional[Path]:
    """題が title のノート（group を指定すれば、グループかどうかも合わせる）。複数あれば名前の順で先のもの。"""
    root = Path(root).resolve()
    key = (str(root), title, group)
    hit = _NAMED.get(key)
    if hit is not None and (hit.is_file() or hit in _RESERVED):
        return hit if hit.is_file() else None
    for n in load_notes(root):
        if n.title == title and (group is None or n.group == group):
            _NAMED[key] = n.path
            return n.path
    return None


def named_path(root: Path, title: str, group: Optional[bool] = None) -> Path:
    """題が title のノートのパス。まだ無ければ、これから作るノートの（タイムスタンプ名の）パス。"""
    root = Path(root).resolve()
    found = find_titled(root, title, group)
    if found is not None:
        return found
    key = (str(root), title, group)
    hit = _NAMED.get(key)
    if hit is not None and hit in _RESERVED:
        return hit
    path = unique_note_path(root)
    _RESERVED.add(path)
    _NAMED[key] = path
    return path


# ---------------------------------------------------------------------------
# 探索
# ---------------------------------------------------------------------------


def iter_md(root: Path):
    root = Path(root)
    for p in sorted(root.rglob("*.md")):
        parts = p.relative_to(root).parts
        if any(part.startswith(".") for part in parts):
            continue
        yield p


# ---------------------------------------------------------------------------
# ノートの種類の判定（front matter の目印は使わない）
# ---------------------------------------------------------------------------
#
#   スキャンノート   … title が正式なフォルゲゼッテルID（例 1a2）で、本文がその画像 `![](1a2.jpg)` を参照している
#   トピックノート   … title が `ID-トピック名`（例 1-仏教）で、本文が `![](1-仏教.jpg)` を参照している。
#                      親トピックは、本文の関係の節（Context など）にある、同じ ID の別のトピックノートへのリンク
#   番号別Index      … title が `ID-Index` の `attribute: group`
#   番号専用ノート   … ファイル名と title が `folgezettel-Index-ID`
#   紙の日記ノート   … title が `YYYY-MM-DD-曜日2文字` で、本文が `![](paper-diary-YYYYMMDD-N.jpg)` を参照している
#   日記の月・年     … title が `YYYY-MM` / `YYYY` の `attribute: group` で、リンク先が紙の日記（月は日記、年は月グループ）
#   キーワードのグループ … `attribute: group` で title がキーワード。Paper-Zettelkasten-Index からリンクされている
#   日記の一番上      … Paper-Zettelkasten-Index の `[日記](…)` のリンク先（デジタル日記の「日記」と題が同じなので、
#                      題ではなくこのリンク階層で見分ける）
#   Paper-Zettelkasten-Index … ファイル名 `Paper-Zettelkasten-Index.md`（旧タイムスタンプ名は題で見つけて移行する）
#
# IDらしい題を持つ普通のノートは、画像の参照が無ければ（title と同じ名前の画像を参照していなければ）
# スキャンノートとは見なさない。判定できないときは推測で分類しない（None を返す）。

_IS_LINK_LINE = re.compile(r"^\s*\[(?:\\.|[^\]\\])*\]\([^)]*\)\s*$")
_IMAGE_ONLY_RE = re.compile(r"^!\[(?:\\.|[^\]\\])*\]\(([^)\s]+)\)\s*$")
_MD_LINK_RE = re.compile(r"(?<!!)\[(?:\\.|[^\]\\])*\]\(([^)\s]+)\)")
TOPIC_TITLE_RE = re.compile(r"^(?:([A-Z]{1,4})-)?(\d+(?:[a-z]+\d+)*[a-z]*)-(.+)$")
DIARY_TITLE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-(MO|TU|WE|TH|FR|SA|SU)$")


@dataclass
class NoteInfo:
    path: Path
    fm: list
    body: list
    title: str
    group: bool
    images: list  # 画像だけの行 `![](…)` が指すファイル名（フォルダ部分を除く）
    links: list   # 本文のどこかにある .md リンクの宛先（正規化した絶対パスの文字列。画像は含めない）


def _norm_link(base: Path, target: str) -> Optional[str]:
    t = target.split("#", 1)[0].strip()
    if not t or "://" in t or not t.lower().endswith(".md"):
        return None
    return os.path.normpath(os.path.join(str(base), t))


def make_note_info(path: Path) -> Optional[NoteInfo]:
    try:
        fm, body = read_note(path)
    except OSError:
        return None
    images: list[str] = []
    links: list[str] = []
    for ln in body:
        m = _IMAGE_ONLY_RE.match(ln.strip())
        if m:
            images.append(Path(m.group(1)).name)
            continue
        for lm in _MD_LINK_RE.finditer(ln):
            norm = _norm_link(path.parent, lm.group(1))
            if norm:
                links.append(norm)
    return NoteInfo(path, fm, body, title_of(fm, body, path.stem).strip(),
                    (fm_value(fm, "attribute") or "").strip() == "group", images, links)


def load_notes(root: Path) -> list[NoteInfo]:
    out = []
    for p in iter_md(root):
        n = make_note_info(p)
        if n is not None:
            out.append(n)
    return out


def _has_image_named(n: NoteInfo, stem: str) -> bool:
    return any(Path(i).stem == stem and Path(i).suffix.lower() in IMAGE_EXTENSIONS for i in n.images)


def scan_key_of(n: NoteInfo) -> Optional[tuple[str, str]]:
    """スキャンノートなら (印, 番号)。題は `PA-1a2`（印つき。画像は同じ名前か、印を除いた番号）か `1a2`（旧い形。印は ''）。
    普通のノートや判定できないものは None。"""
    m = PREFIXED_ID_RE.match(n.title)
    if m:
        return (m.group(1), m.group(2)) if (_has_image_named(n, n.title) or _has_image_named(n, m.group(2))) else None
    fid = normalize_id(n.title)
    if n.title != fid or not ID_PATTERN.fullmatch(fid):
        return None
    return ("", fid) if _has_image_named(n, n.title) else None


def scan_id_of(n: NoteInfo) -> Optional[str]:
    """スキャンノートなら番号（印を除く）。普通のノートや判定できないものは None。"""
    k = scan_key_of(n)
    return k[1] if k else None


def topic_ref_of(n: NoteInfo) -> Optional[tuple[str, str, str]]:
    """トピックノートなら (印, 起点ID, 表示名=title)。題は `PA-1-仏教` か旧い `1-仏教`（印は ''）。"""
    m = TOPIC_TITLE_RE.match(n.title)
    if not m or not ID_PATTERN.fullmatch(m.group(2)):
        return None
    ok = _has_image_named(n, n.title) or (m.group(1) is not None and _has_image_named(n, n.title[len(m.group(1)) + 1:]))
    return (m.group(1) or "", m.group(2), n.title) if ok else None


def topic_of(n: NoteInfo) -> Optional[tuple[str, str]]:
    """トピックノートなら (起点ID, 表示名=title)。"""
    r = topic_ref_of(n)
    return (r[1], r[2]) if r else None


def diary_date_of(n: NoteInfo) -> Optional[str]:
    """紙の日記ノートなら日記が書かれた日付（title の YYYY-MM-DD）。曜日が実際の曜日と合わなければ None。"""
    m = DIARY_TITLE_RE.match(n.title)
    if not m:
        return None
    date = m.group(1)
    try:
        if weekday_en(date) != m.group(2):
            return None
    except ValueError:
        return None
    prefix = f"{DIARY_IMAGE_PREFIX}{date.replace('-', '')}-"
    return date if any(i.startswith(prefix) and Path(i).suffix.lower() in IMAGE_EXTENSIONS for i in n.images) else None


def scan_folgezettel_notes(root: Path, notes: Optional[list] = None, prefix: Optional[str] = None) -> dict[str, Path]:
    """スキャンノート（title が正式なID・本文がその画像を参照）→ {ID: ノート}。
    prefix を渡すと、その印（'PA' など。旧い形は ''）のノートだけを、印を除いた番号 {1a2: ノート} で返す。
    渡さないときは全部を、題そのまま {PA-1a2: ノート} で返す（旧い形は {1a2: ノート}）。
    IDが重複したときは先に見つかった（パス順の）ほうを使う。重複は find_scan_conflicts で検出する。"""
    found: dict[str, Path] = {}
    for n in (notes if notes is not None else load_notes(root)):
        k = scan_key_of(n)
        if not k:
            continue
        if prefix is None:
            found.setdefault(n.title, n.path)
        elif k[0] == prefix:
            found.setdefault(k[1], n.path)
    return found


def find_scan_conflicts(root: Path, notes: Optional[list] = None) -> dict[str, list[Path]]:
    """同じ番号（印つき）を持つスキャンノートが複数あるもの → {PA-1a2: [ノート…]}。
    印の無い旧い題は、今の印（既定 PA）のものとして数える。"""
    default = default_prefix(root)
    seen: dict[str, list[Path]] = {}
    for n in (notes if notes is not None else load_notes(root)):
        if scan_key_of(n):
            seen.setdefault(with_prefix(default, n.title), []).append(n.path)
    return {k: v for k, v in seen.items() if len(v) > 1}


def scan_namespaces(root: Path, notes: Optional[list] = None) -> list[str]:
    """紙のノートにある印（スキャンノート・トピックノートの題の印）の一覧。印なし（旧い形）は含めない。"""
    found: set[str] = set()
    for n in (notes if notes is not None else load_notes(root)):
        k = scan_key_of(n)
        if k and k[0]:
            found.add(k[0])
        t = topic_ref_of(n)
        if t and t[0]:
            found.add(t[0])
    return sorted(found)


def adopt_legacy_prefix(root: Path, default: str, notes: Optional[list] = None) -> int:
    """印の無い題の紙のノート（旧い形 `1a2` / `1-仏教`）を、印つき（`PA-1a2` / `PA-1-仏教`）に直す。
    画像のファイル名は変えない（ノートは同じ名前の画像、または印を除いた番号の画像を参照していれば紙のノートと分かる）。直した数を返す。"""
    n_done = 0
    for n in (notes if notes is not None else load_notes(root)):
        k = scan_key_of(n)
        if k and not k[0]:
            _retitle(n.path, f"{default}-{n.title}")
            n_done += 1
            continue
        t = topic_ref_of(n)
        if t and not t[0]:
            _retitle(n.path, f"{default}-{n.title}")
            n_done += 1
    if n_done:
        reset_name_cache()
    return n_done


def _legacy_paper_indexes(root: Path) -> list[Path]:
    """Paper-Zettelkasten-Index（グループ。題が Paper-Zettelkasten-Index、または旧マーカー `paper_index:` つき）。名前順。"""
    found: list[Path] = []
    for n in load_notes(root):
        if fm_value(n.fm, "paper_index") or (n.group and n.title == ns_title('index')):
            found.append(n.path)
    return sorted(found, key=lambda p: p.name)


def find_paper_index(root: Path) -> Optional[Path]:
    """Paper-Zettelkasten-Index（グループ）。題で探す。複数あれば名前の新しい方。"""
    found = _legacy_paper_indexes(Path(root))
    return found[-1] if found else None


def _rewrite_links_to(root: Path, old_path: Path, new_path: Path) -> int:
    """vault の全ノートで、old_path を指す Markdown リンクの宛先を new_path へ書き換える
    （表示名・`#見出し` はそのまま）。書き換えたノート数を返す。"""
    old_norm = os.path.normpath(str(old_path))
    link_re = re.compile(r"(\[(?:\\.|[^\]\\])*\]\()([^)\s]*)(\))")
    changed = 0
    for note in iter_md(root):
        try:
            text = note.read_text(encoding="utf-8")
        except OSError:
            continue
        if old_path.name not in text:
            continue

        def repl(m: re.Match) -> str:
            target = m.group(2)
            if "://" in target:
                return m.group(0)
            base, sep, frag = target.partition("#")
            if not base.endswith(old_path.name):
                return m.group(0)
            if os.path.normpath(os.path.join(str(note.parent), base)) != old_norm:
                return m.group(0)
            return m.group(1) + _rel(note.parent, new_path) + sep + frag + m.group(3)

        new_text = link_re.sub(repl, text)
        if new_text != text:
            note.write_text(new_text, encoding="utf-8")
            changed += 1
    return changed


def _fm_title_attr(fm: list[str], title: str, group: bool = True) -> list[str]:
    """front matter を 時刻・title・attribute・（yomi など）の順にそろえる。title / attribute 以外は触らない。"""
    rest = [ln for ln in fm if not re.match(r"^\s*(title|attribute)\s*:", ln)]
    at = next((i for i, ln in enumerate(rest) if ln.startswith("time:")), -1)
    add = [f"title: {title}"] + (["attribute: group"] if group else [])
    rest[at + 1:at + 1] = add
    return rest


def _fm_key_re(key: str):
    return re.compile(r"^\s*" + re.escape(key) + r"\s*:")


def _drop_fm_keys(path: Path, keys: set[str]) -> bool:
    """ノートの front matter から keys の行だけを取り除く（本文・ほかの行・空行は 1 バイトも変えない）。"""
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return False
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return False
    res = [ln for i, ln in enumerate(lines) if not (0 < i < end and any(_fm_key_re(k).match(ln) for k in keys))]
    if len(res) == len(lines):
        return False
    path.write_text("\n".join(res), encoding="utf-8")
    return True


def _retitle(path: Path, new_title: str) -> None:
    """title と、同じ文字の最初の `# 見出し` を新しい題に直す（それ以外は変えない）。"""
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), 0)
    old = None
    for i in range(1, end):
        m = re.match(r"^\s*title\s*:\s*(.*)$", lines[i])
        if m:
            old = m.group(1).strip()
            lines[i] = f"title: {new_title}"
            break
    if old is not None:
        for i in range(end + 1, len(lines)):
            if lines[i].strip() == f"# {old}":
                lines[i] = f"# {new_title}"
                break
    path.write_text("\n".join(lines), encoding="utf-8")


LAST_REPORT: list[str] = []  # 直近の regen / migrate が出した警告（重複ID・旧メタデータの矛盾 など）


def _legacy_keys_of(n: NoteInfo) -> set[str]:
    keys = {k for k in LEGACY_FM_KEYS if any(_fm_key_re(k).match(ln) for ln in n.fm)}
    # Digital IDs share this key; paper migration must never remove it.
    keys.discard("folgezettel")
    # 値の無い `topic_parent:`（旧い形の空欄）は何も表さないので、旧い目印と同じく外す
    if any(_fm_key_re(TOPIC_PARENT_KEY).match(ln) for ln in n.fm) and not any(_legacy_values(n, TOPIC_PARENT_KEY)):
        keys.add(TOPIC_PARENT_KEY)
    return keys


def _legacy_values(n: NoteInfo, key: str) -> list[str]:
    out = []
    for ln in n.fm:
        m = re.match(r"^\s*" + re.escape(key) + r"\s*:\s*(.*)$", ln)
        if m:
            out.append(m.group(1).strip())
    return out


def migrate_legacy_metadata(root: Path) -> list[str]:
    """旧い front matter の目印（`folgezettel:` など）を、新しい判定（title・画像の参照・リンク階層）で
    同じノートだと確かめられたものから取り除く。確かめられない・値が矛盾するものは**消さずに**警告を返す。

    - 取り除くのは目印の行だけ。本文・画像・リンク・ほかの front matter は変えない。
    - `folgezettel:` はデジタルノートの現役IDなので、title との一致に関わらず保持する。
    - `paper_diary:` は日記の日付で、紙の日記の画像（paper-diary-…）を参照しているものだけ外す
      （題が旧い形のときは YYYY-MM-DD-曜日2文字 に直してから）。
    - 月・年・キーワードのグループは、リンク階層で今と同じノートが見つかるものだけ外す。
    戻り値: 警告のリスト。"""
    root = Path(root).resolve()
    msgs: list[str] = []

    # ---- 1) ノート（グループ以外）----
    notes = load_notes(root)
    for n in notes:
        keys = _legacy_keys_of(n)
        if not keys:
            continue
        drop: set[str] = set()
        fm_title = n.title
        for key in sorted(keys):
            vals = _legacy_values(n, key)
            v = vals[0] if vals else ""
            if key == "folgezettel":
                if re.fullmatch(r"[A-Z]{1,4}-" + re.escape(fm_title), v or ""):
                    continue  # 紙のノートの番号（PA- + 題）。同期が付けるもの。外さない
                if normalize_id(v) != fm_title:
                    msgs.append(f"{n.path.name}: folgezettel: {v!r} と title: {fm_title!r} が一致しません（消していません）")
                elif scan_id_of(n) is None:
                    msgs.append(f"{n.path.name}: title: {fm_title} と同じ名前の画像を参照していないため、スキャンノートと確認できません"
                                "（folgezettel: は消していません）")
                else:
                    drop.add(key)
            elif key == "paper_diary":
                try:
                    date = normalize_diary_date(v)
                except ValueError:
                    msgs.append(f"{n.path.name}: paper_diary: {v!r} は日付として読めません（消していません）")
                    continue
                prefix = f"{DIARY_IMAGE_PREFIX}{date.replace('-', '')}-"
                if not any(i.startswith(prefix) for i in n.images):
                    msgs.append(f"{n.path.name}: paper_diary: {date} だが paper-diary- の画像を参照していません（消していません）")
                    continue
                if n.title != diary_title(date):
                    _retitle(n.path, diary_title(date))
                drop.add(key)
            elif key == "paper_topic":
                t = topic_of(n)
                if t is not None and t[0] == v:
                    drop.add(key)
                else:
                    msgs.append(f"{n.path.name}: paper_topic: {v!r} を title: {fm_title!r} と画像から確認できません（消していません）")
            elif key == TOPIC_PARENT_KEY:
                drop.add(key)  # 空欄のものだけがここに来る（_legacy_keys_of）
            elif key == "folgezettel_index":
                if n.title == f"folgezettel-Index-{v}":
                    drop.add(key)
                else:
                    msgs.append(f"{n.path.name}: folgezettel_index: {v!r} を title から確認できません（消していません）")
            elif key == "paper_topic_index":
                if n.group and n.title in (f"{v}-Index", f"{v}_Index"):
                    drop.add(key)
                else:
                    msgs.append(f"{n.path.name}: paper_topic_index: {v!r} を title と attribute から確認できません（消していません）")
            elif key == "paper_index":
                if n.group and (n.title == DEFAULT_INDEX_TITLE or n.title.startswith(DEFAULT_INDEX_TITLE + "-")):
                    drop.add(key)
        if drop:
            _drop_fm_keys(n.path, drop)

    # ---- 2) グループ（日記の月・年、キーワード）。1) で日記ノートの題が直ったあとに確かめる ----
    notes = load_notes(root)
    index_path = find_paper_index(root)
    groups = paper_diary_groups(notes)
    month_norms = {os.path.normpath(str(p)) for p in groups["months"].values()}
    for n in notes:
        keys = _legacy_keys_of(n) & {"paper_diary_month", "paper_diary_year", "paper_keyword"}
        if not keys:
            continue
        drop = set()
        me = os.path.normpath(str(n.path))
        for key in sorted(keys):
            vals = _legacy_values(n, key)
            v = vals[0] if vals else ""
            if key == "paper_diary_month":
                if groups["months"].get(v) == n.path:
                    drop.add(key)
                else:
                    msgs.append(f"{n.path.name}: paper_diary_month: {v!r} を title とリンク先（紙の日記）から確認できません（消していません）")
            elif key == "paper_diary_year":
                if groups["years"].get(v) == n.path:
                    drop.add(key)
                else:
                    msgs.append(f"{n.path.name}: paper_diary_year: {v!r} を title とリンク先（紙の日記の月グループ）から確認できません（消していません）")
            elif key == "paper_keyword":
                found = find_group(root, v, index_path, notes) if index_path else None
                is_old_diary_top = (v == DIARY_KEYWORD and (
                    n.path in groups["tops"]
                    or (index_path is not None and find_diary_group(root, index_path, notes) == n.path)))
                if (found == n.path) or is_old_diary_top:
                    if is_old_diary_top and n.title != DIARY_GROUP_TITLE:
                        _retitle(n.path, DIARY_GROUP_TITLE)
                    drop.add(key)
                else:
                    msgs.append(f"{n.path.name}: paper_keyword: {v!r} を Paper-Zettelkasten-Index からのリンクで確認できません（消していません）")
        if drop:
            _drop_fm_keys(n.path, drop)
    LAST_REPORT[:] = msgs
    return msgs


def _add_context_link(path: Path, link: str) -> None:
    """ノートの `### Context` の末尾にリンクを足す（節が無ければ最初の節の手前か末尾に作る）。"""
    fm, body = read_note(path)
    if any(link == ln for ln in body):
        return
    ci = next((k for k, ln in enumerate(body) if _is_context_head(ln)), None)
    if ci is None:
        fs = _first_section(body)
        at = fs if fs is not None else len(body)
        while at > 0 and not body[at - 1].strip() and fs is None:
            at -= 1
        body[at:at] = [CONTEXT_HEAD, link]
    else:
        e = next((k for k in range(ci + 1, len(body)) if body[k].lstrip().startswith("### ")), len(body))
        while e > ci + 1 and not body[e - 1].strip():
            e -= 1
        body.insert(e, link)
    write_note(path, fm, body, keep_trailing_blank=True)


def migrate_paper_index(root: Path) -> Optional[Path]:
    """使う Paper-Zettelkasten-Index（グループ）を返す。ファイル名は変えない（ふつうのノートとして題で探す。2026-10-27）。
    Index が無ければ None。"""
    root = Path(root).resolve()
    return find_paper_index(root)


def scan_diary_notes(root: Path, notes: Optional[list] = None) -> dict[str, Path]:
    """紙の日記ノート（title が YYYY-MM-DD-曜日2文字・本文が paper-diary-… の画像を参照）→ {日付: ノート}。
    デジタル日記（同じ形の題だが紙の日記の画像を持たない）は含めない。"""
    found: dict[str, Path] = {}
    for n in (notes if notes is not None else load_notes(root)):
        date = diary_date_of(n)
        if date:
            found.setdefault(date, n.path)
    return found


DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")


def normalize_diary_date(raw: str) -> str:
    """日記の日付を YYYY-MM-DD にそろえる（全角・`/`・`.`・`YYYYMMDD` も受ける）。不正なら ValueError。"""
    t = unicodedata.normalize("NFKC", raw).strip()
    m = re.fullmatch(r"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})", t) or re.fullmatch(r"(\d{4})(\d{2})(\d{2})", t)
    if not m:
        raise ValueError(f"日付は YYYY-MM-DD の形で入力してください: {raw!r}")
    try:
        d = datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError as exc:
        raise ValueError(f"存在しない日付です: {raw!r}") from exc
    return d.strftime("%Y-%m-%d")


_WEEKDAYS_EN = ("MO", "TU", "WE", "TH", "FR", "SA", "SU")  # デジタル日記（\\d）と同じ表記


def weekday_en(date: str) -> str:
    """YYYY-MM-DD の曜日（MO〜SU。デジタル日記の題と同じ 2 文字）。日付から自動で計算する。"""
    return _WEEKDAYS_EN[datetime.strptime(date, "%Y-%m-%d").weekday()]


def diary_label(date: str) -> str:
    """曜日つきの日付（例: 2026-10-13-TU）。"""
    return f"{date}-{weekday_en(date)}"


def diary_title(date: str) -> str:
    """紙の日記ノートの題。デジタル日記（\\d）と同じ YYYY-MM-DD-曜日2文字。
    Vim 側のデジタル日記の機能は 先頭の画像 `paper-diary-…` で紙の日記を見分けて無視する。"""
    return diary_label(date)


def _diary_image_name(date: str, page: int, suffix: str) -> str:
    return f"{DIARY_IMAGE_PREFIX}{date.replace('-', '')}-{page}{suffix.lower()}"


_IMAGE_LINE_RE = re.compile(r"^!\[(?:\\.|[^\]\\])*\]\((.+)\)$")


def _blank_after_last_image(body: list[str]) -> list[str]:
    """紙の日記ノートの本文で、最後の画像の次に空行が無ければ 1 つ足す（画像と `### Group` などの節、
    またはファイルの末尾とのあいだに空行を置く）。既に空行があれば何もしない。"""
    last = max((i for i, ln in enumerate(body) if _IMAGE_LINE_RE.match(ln.strip())), default=None)
    if last is None:
        return body
    if last + 1 >= len(body) or body[last + 1].strip():
        return body[:last + 1] + [""] + body[last + 1:]
    return body


def register_diary_pages(
    root: Path,
    dest: Path,
    pages: list[tuple[Path, str]],
) -> tuple[list[tuple[str, Path]], list[tuple[Path, str, str]]]:
    """スキャン画像を「紙の日記」として登録する。

    pages: [(画像パス, 日記が書かれた日付)]（指定順がページ順）。同じ日付の画像は 1 つの
    ノート（題 `日付-曜日2文字`）に画像を並べる。同じ日付の日記が既にあれば
    そのノートの末尾にページを足す（ページ番号は続き番号。既存の画像は上書きしない）。
    ノートの `time:` はスキャンした日時（画像の撮影日時、無ければ今）で、日記の日付とは別。
    戻り値は (moved, errors): moved = [(日付, ノートパス)]（日付ごとに 1 件）/ errors = [(元パス, 日付, 理由)]。
    """
    root = Path(root).resolve()
    dest = Path(dest).resolve()
    existing = scan_diary_notes(root)
    moved: dict[str, Path] = {}
    errors: list[tuple[Path, str, str]] = []

    # 日付ごとにまとめる（出現順を保つ）
    by_date: dict[str, list[Path]] = {}
    for src, raw_date in pages:
        src = Path(src)
        try:
            date = normalize_diary_date(raw_date)
        except ValueError as exc:
            errors.append((src, str(raw_date), str(exc)))
            continue
        by_date.setdefault(date, []).append(src)

    for date, srcs in by_date.items():
        note_path = existing.get(date)
        if note_path is not None:
            fm, body = read_note(note_path)
            image_dir = note_path.parent
            page = sum(1 for ln in body if _IMAGE_LINE_RE.match(ln.strip())) + 1
            when = None
        else:
            fm, body, image_dir, page = None, None, dest, 1
            when = image_datetime(srcs[0]) or datetime.now()
        added: list[str] = []
        for src in srcs:
            # 既にある画像名は使わない（上書きしない）
            while (image_dir / _diary_image_name(date, page, src.suffix)).exists():
                page += 1
            target = image_dir / _diary_image_name(date, page, src.suffix)
            try:
                shutil.move(str(src), str(target))
            except OSError as exc:
                errors.append((src, date, str(exc)))
                continue
            added.append(target.name)
            page += 1
        if not added:
            continue
        if note_path is None:
            note_path = unique_note_path(dest, when)
            fm = [_time_line(when), f"title: {diary_title(date)}", SCAN_SOURCE_LINE]
            body = [f"# {diary_title(date)}"]
        # 画像行を、最初の関係の節の手前（無ければ末尾）に、空行を挟んで足す
        fs = _first_section(body)
        end = fs if fs is not None else len(body)
        while end > 0 and not body[end - 1].strip():
            end -= 1
        new_lines: list[str] = []
        for name in added:
            new_lines += ["", f"![]({name})"]
        body = body[:end] + new_lines + body[end:]  # 元の空行はそのまま（無ければ下で 1 つ足す）
        write_note(note_path, fm, _blank_after_last_image(body), keep_trailing_blank=True)
        moved[date] = note_path
    return list(moved.items()), errors


def find_group(root: Path, keyword: str, index_path: Optional[Path] = None,
               notes: Optional[list] = None) -> Optional[Path]:
    """キーワードのグループノート: `attribute: group` で title が keyword のうち、
    Paper-Zettelkasten-Index からリンクされているもの → 無ければ Paper-Zettelkasten-Index へ（Context / Group で）
    リンクしているもの。見つからなければ None（目印の front matter は使わない）。"""
    notes = notes if notes is not None else load_notes(root)
    cands = [n for n in notes if n.group and n.title == keyword]
    if not cands:
        return None
    index_path = index_path or find_paper_index(root)
    if index_path is None:
        return None
    idx = next((n for n in notes if n.path == index_path), None) or make_note_info(index_path)
    linked = set(idx.links) if idx is not None else set()
    for n in cands:
        if os.path.normpath(str(n.path)) in linked:
            return n.path
    ip = os.path.normpath(str(index_path))
    for n in cands:
        if ip in n.links:
            return n.path
    return None


# ---------------------------------------------------------------------------
# 生成
# ---------------------------------------------------------------------------


def index_title(index_path: Path) -> str:
    fm, body = read_note(index_path)
    return title_of(fm, body, DEFAULT_INDEX_TITLE)


def _time_line(when: Optional[datetime] = None) -> str:
    return f"time: {(when or datetime.now()).strftime('%Y-%m-%d %H:%M:%S')}"


def image_datetime(path: Path) -> Optional[datetime]:
    """画像のEXIF日時（撮影日時）。無ければ None。"""
    try:
        from PIL import Image  # 遅延 import（未導入環境でもコアは動く）
    except Exception:
        return None
    try:
        with Image.open(path) as image:
            exif = image.getexif()
            for tag in (36867, 36868, 306):
                value = exif.get(tag)
                if not value:
                    continue
                if isinstance(value, bytes):
                    value = value.decode("utf-8", errors="ignore")
                text = str(value).strip().strip("\x00")
                for fmt in ("%Y:%m:%d %H:%M:%S", "%Y-%m-%d %H:%M:%S"):
                    try:
                        return datetime.strptime(text[:19], fmt)
                    except ValueError:
                        continue
    except Exception:
        return None
    return None


def create_scan_note(
    folder: Path,
    fid: str,
    image_name: str,
    when: Optional[datetime] = None,
) -> Path:
    """スキャン1枚をタイムスタンプ名ノートにする（title = 正式なフォルゲゼッテルID。本文は regen が作り直す）。"""
    path = unique_note_path(folder)
    fm = [_time_line(when), f"title: {fid}", SCAN_SOURCE_LINE]
    body = [f"# {fid}", "", f"![]({image_name})"]
    write_note(path, fm, body)
    return path


BRANCH_GROUP_HEAD = "BranchGroup:"


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _link_norm(base: Path, line: str) -> Optional[str]:
    m = re.search(r"\]\(([^)#\s]+)", line)
    return os.path.normpath(str(base / m.group(1))) if m else None


def _find_branch_group(body: list[str]) -> Optional[tuple[int, int]]:
    """BranchGroup:（旧 ThisNoteGroup:）の見出しの行と、続くリンク行（インデントつきも）の終わりの次。"""
    flags = _fence_flags(body)
    for i, ln in enumerate(body):
        if not flags[i] and ln.strip() in (BRANCH_GROUP_HEAD, "ThisNoteGroup:"):
            j = i + 1
            while j < len(body) and _IS_LINK_LINE.match(body[j]):
                j += 1
            return i, j
    return None


def _fence_flags(lines: list[str]) -> list[bool]:
    out: list[bool] = []
    inside = False
    for ln in lines:
        if re.match(r"^\s*(```|~~~)", ln):
            inside = not inside
            out.append(True)
        else:
            out.append(inside)
    return out


def _existing_branch_group(note_path: Path) -> list[str]:
    _fm, body = read_note(note_path)
    span = _find_branch_group(body)
    return body[span[0] + 1:span[1]] if span else []


def _legacy_topic_lines(legacy: Path, topic_norm: dict, base: Path) -> list[str]:
    """旧 `1-Index` グループの本文から、トピックノートへのリンク行を並びのまま取り出す（インデントは外す）。
    リンクの宛先は ID ノート（base）から見た相対パスに直す。"""
    _fm, body = read_note(legacy)
    out: list[str] = []
    for ln in body:
        if not _IS_LINK_LINE.match(ln):
            continue
        key = _link_norm(legacy.parent, ln)
        if key in topic_norm:
            disp = topic_norm[key][0]
            out.append(markdown_link(disp, Path(key), base))
    return out


def _branch_add_line(lines: list[str], new_line: str, base: Path, after: Optional[set] = None) -> list[str]:
    """new_line を BranchGroup の行の並びに足す（同じ宛先が既にあれば足さない。インデントは付けない）。
    after（宛先の正規化パスの集合: 親トピックとその子孫）のどれかが並びにあれば、その最後の行の次へ。無ければ最後へ。"""
    key = _link_norm(base, new_line)
    if key is not None and any(_link_norm(base, ln) == key for ln in lines):
        return lines
    out = list(lines)
    if after:
        pos = [p for p, ln in enumerate(out) if _link_norm(base, ln) in after]
        if pos:
            out.insert(pos[-1] + 1, new_line.lstrip(" "))
            return out
    out.append(new_line.lstrip(" "))
    return out


def _branch_add_topics(lines: list[str], base: Path, tlist: list, disp_path: dict) -> list[str]:
    """まだ BranchGroup に無いトピックを、親が子より先になるように足す（親トピックがあれば、その親と子孫の後ろへ。
    無ければ最後へ）。インデントは付けない。足したあとの並びは利用者が自由に直してよい（既にある行は動かさない）。"""
    out = list(lines)
    parent_of = {d: tp for d, _p, tp in tlist}

    def family(root_disp: str) -> set:
        fam = {root_disp}
        changed = True
        while changed:
            changed = False
            for d, tp in parent_of.items():
                if tp in fam and d not in fam:
                    fam.add(d)
                    changed = True
        return {os.path.normpath(str(disp_path[d])) for d in fam if d in disp_path}

    for d, pth, tp in topic_order(tlist):
        after = family(tp) if tp and tp in disp_path else None
        out = _branch_add_line(out, markdown_link(d, pth, base), base, after)
    return out


def _write_branch_group(note_path: Path, lines: list[str]) -> None:
    """ID ノートの BranchGroup: ブロックを、lines にする（無ければ H1 の直後に作る）。ほかの本文は変えない。"""
    fm, body = read_note(note_path)
    span = _find_branch_group(body)
    block = [BRANCH_GROUP_HEAD] + lines
    if span is not None:
        if body[span[0]:span[1]] == block:
            return
        body[span[0]:span[1]] = block
    else:
        if not lines:
            return
        h1 = next((i for i, ln in enumerate(body) if re.match(r"^#\s", ln)), None)
        at = h1 + 1 if h1 is not None else 0
        if at < len(body) and not body[at].strip():
            at += 1          # H1 の直後の空行を、ブロックの前の空行に使う
            pre: list[str] = []
        else:
            pre = [""] if at else []
        body[at:at] = pre + block + [""]
    write_note(note_path, fm, body)


def topic_display(fid: str, topic: str) -> str:
    """トピック別Indexの表示名（例: 1-仏教）。"""
    return f"{fid}-{topic}"


def create_topic_note(
    folder: Path,
    fid: str,
    topic: str,
    image_name: str,
    when: Optional[datetime] = None,
    parent_topic: Optional[str] = None,
    root: Optional[Path] = None,
) -> Path:
    """トピック別Indexノート（例: title: 1-仏教・画像添付。Context と Branch は regen が足す）。

    parent_topic は親トピックノートの表示名（例: 1-仏教）。表示順のためだけに front matter の
    `topic_parent:` に残す（folgezettel-Index-N と ID ノートの BranchGroup: で、親を子より先に並べる）。
    階層・インデントは作らない。同じ起点IDに、その表示名のトピックが無ければ書かない（推測しない）。
    """
    path = unique_note_path(folder)
    display = topic_display(fid, topic)
    fm = [_time_line(when), f"title: {display}", SCAN_SOURCE_LINE]
    if parent_topic and parent_topic != display and any(
            disp == parent_topic for disp, _p, _tp in scan_topic_notes(root or folder).get(fid, [])):
        fm.append(f"{TOPIC_PARENT_KEY}: {parent_topic}")
    body = [f"# {display}", "", f"![]({image_name})"]
    write_note(path, fm, body)
    return path


def scan_topic_notes(root: Path, notes: Optional[list] = None, prefix: Optional[str] = None) -> dict[str, list[tuple[str, Path, Optional[str]]]]:
    """トピックノート（title が `ID-トピック名`・本文がその画像を参照）→ {起点ID: [(表示名, ノート, 親トピック名), …]}。

    親トピック名（例: 1-仏教）は front matter の `topic_parent:`（同じ起点IDのトピックがあるときだけ）。
    無ければ旧い形（作成時に Context の節へ書いた、同じ起点IDの別のトピックへのリンク）から読む。
    どちらも無ければ None（親は推測しない）。
    prefix（'PA' など。旧い形は ''）を渡すと、その印のトピックだけを、印を除いた起点ID {1: …} で返す。
    渡さないときは全部を、印つきの起点ID {PA-1: …}（旧い形は {1: …}）で返す。"""
    notes = notes if notes is not None else load_notes(root)
    topics: dict[str, tuple[str, str]] = {}  # 正規化パス → (起点ID, 表示名)
    refs: dict[str, tuple[str, str, str]] = {}
    for n in notes:
        r = topic_ref_of(n)
        if r and (prefix is None or r[0] == prefix):
            key = r[1] if prefix is not None else with_prefix(r[0], r[1])
            topics[os.path.normpath(str(n.path))] = (key, r[2])
            refs[os.path.normpath(str(n.path))] = r
    found: dict[str, list[tuple[str, Path, Optional[str]]]] = {}
    for n in notes:
        t = topics.get(os.path.normpath(str(n.path)))
        if not t:
            continue
        fid, title = t
        parent = None
        yp = (fm_value(n.fm, TOPIC_PARENT_KEY) or "").strip()
        if yp and yp != title and any(v == (fid, yp) for v in topics.values()):
            parent = yp
        elif not yp:
            for target in _context_link_targets(n):
                other = topics.get(target)
                if other and other[0] == fid and other[1] != title:
                    parent = other[1]
                    break
        found.setdefault(fid, []).append((title, n.path, parent))
    for lst in found.values():
        lst.sort(key=lambda t: natural_key(t[0]))
    return found


def _context_link_targets(n: NoteInfo) -> list[str]:
    """ノートの Context（`### Context` の節・本文の上の `Context:` のブロック）にあるリンクの宛先（正規化パス）。"""
    out: list[str] = []
    inside = False
    for ln in n.body:
        t = ln.strip()
        if t in CONTEXT_HEADS or t == "Context:":
            inside = True
            continue
        if inside:
            if not t or t.startswith("#") or _is_section_head(ln) or re.match(r"^\w+:$", t):
                inside = False
                continue
            for lm in _MD_LINK_RE.finditer(ln):
                norm = _norm_link(n.path.parent, lm.group(1))
                if norm:
                    out.append(norm)
    return out


def topic_order(tlist: list) -> list:
    """トピック [(表示名, ノート, 親), …] を、親が子より先になる順に並べる（兄弟は自然順。インデントはしない）。
    親が見つからない・親子が循環しているものは、最上位として扱う。"""
    by_disp = {d: (d, pth, tp) for d, pth, tp in tlist}
    kids: dict[Optional[str], list] = {}
    for d, pth, tp in tlist:
        kids.setdefault(tp if tp in by_disp and tp != d else None, []).append(by_disp[d])
    out: list = []
    seen: set[str] = set()

    def walk(item) -> None:
        if item[0] in seen:
            return
        seen.add(item[0])
        out.append(item)
        for c in sorted(kids.get(item[0], []), key=lambda t: natural_key(t[0])):
            walk(c)

    for item in sorted(kids.get(None, []), key=lambda t: natural_key(t[0])):
        walk(item)
    for item in sorted(tlist, key=lambda t: natural_key(t[0])):  # 循環しているもの
        walk(item)
    return out


def find_id_index(root: Path, fid: str, notes: Optional[list] = None) -> Optional[Path]:
    """起点IDの番号別Index（グループ）ノート: title が `<ID>-Index`（旧表記 `<ID>_Index` も）の `attribute: group`。"""
    for n in (notes if notes is not None else load_notes(root)):
        if n.group and n.title in (f"{fid}-Index", f"{fid}_Index"):
            return n.path
    return None


def _is_timeline_note(n) -> bool:
    return any(re.match(r"^\s*timeline\s*:\s*true\s*$", ln, re.I) for ln in n.fm)


def paper_diary_groups(notes: list) -> dict:
    """紙の日記の月・年・一番上のノートを見つける。戻り値: {"months": {YYYY-MM: path}, "years": {YYYY: path}, "tops": [path…]}。
    新しい形（2026-10-26 から）: グループではない普通のノート（timeline: true）で、題が
      月 `YYYY-MM-紙`、年 `YYYY-紙`、一番上 `紙の日記`。デジタル日記の月（題 `YYYY-MM`）とは題が違うので取り違えない。
    旧い形（グループ）も見つける（regen が新しい形に直す）:
    - 月 … title が YYYY-MM の attribute: group で、リンク先に紙の日記ノートがある
    - 年 … title が YYYY の attribute: group で、リンク先に紙の日記の月グループがある
    - 一番上 … title が「日記」「紙の日記」の attribute: group で、リンク先に紙の日記の月/年グループがある
    デジタル日記の同名のグループは、リンク先が紙の日記ではないので含まれない。"""
    diaries = {os.path.normpath(str(n.path)) for n in notes if diary_date_of(n)}
    months: dict[str, Path] = {}
    years: dict[str, Path] = {}
    tops: list[Path] = []
    for n in notes:
        m = PAPER_MONTH_RE.match(n.title)
        if m and _is_timeline_note(n) and not n.group:
            months.setdefault(m.group(1), n.path)
            continue
        m = PAPER_YEAR_RE.match(n.title)
        if m and _is_timeline_note(n) and not n.group:
            years.setdefault(m.group(1), n.path)
            continue
        if n.title == DIARY_GROUP_TITLE and _is_timeline_note(n) and not n.group:
            tops.append(n.path)
    for n in notes:
        if n.group and re.fullmatch(r"\d{4}-\d{2}", n.title) and any(l in diaries for l in n.links):
            months.setdefault(n.title, n.path)
    month_norms = {os.path.normpath(str(p)) for p in months.values()}
    for n in notes:
        if n.group and re.fullmatch(r"\d{4}", n.title) and any(l in month_norms for l in n.links):
            years.setdefault(n.title, n.path)
    child_norms = month_norms | {os.path.normpath(str(p)) for p in years.values()}
    tops += [n.path for n in notes
             if n.group and n.title in (DIARY_GROUP_TITLE, OLD_DIARY_GROUP_TITLE) and any(l in child_norms for l in n.links)
             and n.path not in tops]
    return {"months": months, "years": years, "tops": tops}


def find_diary_group(root: Path, index_path: Optional[Path], notes: Optional[list] = None) -> Optional[Path]:
    """紙の日記の一番上のグループ（題「日記」）。デジタル日記のグループも題が「日記」なので、題ではなく
    リンク階層で見つける: Paper-Zettelkasten-Index の `[日記](…)` のリンク先 → Folgezettel-Index の
    `[日記](…)` のリンク先 → 紙の日記の月/年グループを子に持つ「日記」。"""
    notes = notes if notes is not None else load_notes(root)
    by_path = {os.path.normpath(str(n.path)): n for n in notes}

    def _target(note_path: Optional[Path]) -> Optional[Path]:
        n = by_path.get(os.path.normpath(str(note_path))) if note_path else None
        if n is None:
            return None
        for ln in n.body:
            m = re.match(r"^\s*\[(?:" + re.escape(DIARY_KEYWORD) + r"|diary)\]\(([^)#\s]+)\)\s*$", ln)
            if m:
                cand = (n.path.parent / m.group(1)).resolve()
                if cand.is_file():
                    return cand
        return None

    found = _target(index_path) or _target(find_titled(root, ns_title('fi'), True) or Path(root) / FOLGE_INDEX)
    if found is not None:
        return found
    tops = paper_diary_groups(notes)["tops"]
    return tops[0] if tops else None


def _new_group_note(root: Path, display: str, reading: str, title: Optional[str] = None) -> Path:
    path = unique_note_path(root)
    title = title or display
    fm = [
        _time_line(),
        f"title: {title}",
        "attribute: group",
    ]
    if reading and reading != display:
        fm = jy.set_yomi_map(fm, {display: reading})
    body = [f"# {title}", ""]
    write_note(path, fm, body, keep_trailing_blank=True)
    return path


def _entry_readings(entries: list[dict]) -> dict[str, str]:
    return {
        e["display"]: reading_for_display(e["key"]) for e in entries
    }


def _update_yomi(fm: list[str], mapping: dict[str, str]) -> list[str]:
    if not mapping:
        return fm
    merged = dict(jy.parse_yomi_map(fm))
    merged.update({k: v for k, v in mapping.items() if v and v != k})
    return jy.set_yomi_map(fm, merged)


def write_folge_index_notes(root: Path, folge: dict[str, Path],
                            id_index_paths: dict[str, Path], topics: Optional[dict] = None) -> None:
    """各最上位IDの専用ノート folgezettel-Index-N を作る/作り直す。

    中身: 配下IDの `## <ID>` 見出し + 画像をフォルゲゼッテル自然順で並べ、
    トピックIndex（1-Index）があればそのリンクも入れる。Parent は Folgezettel-Index。
    トピック（例: 1-仏教）は、その起点IDの `## <ID>` の節の最後に、親が子より先になる順で並べる（インデントなし）。
    """
    topics = topics if topics is not None else scan_topic_notes(root)
    for fid in top_level_ids(folge):
        path = folge_index_path(root, fid)
        display = folge_index_display(fid)
        if not path.is_file():
            write_note(path, [_time_line(), f"title: {display}"], [])
        fm_fi, old_fi_body = read_note(path)
        inner = [f"# {display}", ""]
        members = sorted((f for f in folge if _root_id(f) == fid), key=natural_key)
        for member in members:
            inner.append("## " + markdown_link(member, folge[member], path.parent))
            inner.append("")
            _fm_n, body_n = read_note(folge[member])
            base_dir = folge[member].parent
            for ln in body_n:
                m = re.match(r"^!\[\]\((.+)\)$", ln.strip())
                if m:
                    img = (base_dir / m.group(1)).resolve()
                    inner.append(f"![]({_rel(path.parent, img)})")
            inner.append("")
        id_index = id_index_paths.get(fid) or find_id_index(root, fid)
        inner += [CONTEXT_HEAD,
                  markdown_link(ns_title('fi'), named_path(root, ns_title('fi'), True), path.parent)]
        body = merge_note_body(old_fi_body, inner)
        body = _place_topic_lines(body, path.parent, members, folge, topics, id_index)
        if body != old_fi_body:
            write_note(path, fm_fi, body)


def _place_topic_lines(body: list[str], base: Path, members: list[str], folge: dict[str, Path],
                       topics: dict, id_index: Optional[Path] = None) -> list[str]:
    """folgezettel-Index-N の本文で、トピックの Index（その番号のグループと、トピックのノート）へのリンク行を、
    ノート（`## <ID>` の節）より先に、見出しの直後へ並べ直す（2026-10-24。トピックの Index を先、その後にノート）。
    トピックのノートは、起点の ID の順に、親が子より先になる順で並べる。トピック以外の行は変えない。
    消えたトピックの行は消す（自動で作る行なので）。"""
    all_topics = {os.path.normpath(str(pth)) for lst in topics.values() for _d, pth, _tp in lst}
    idx_norm = os.path.normpath(str(id_index)) if id_index is not None else None
    mine = set(all_topics) | ({idx_norm} if idx_norm else set())
    if not mine:
        return body
    first = next((k for k, ln in enumerate(body) if _IS_LINK_LINE.match(ln) and _link_norm(base, ln) in mine), None)
    out = [ln for ln in body if not (_IS_LINK_LINE.match(ln) and _link_norm(base, ln) in mine)]
    lines: list[str] = []
    if id_index is not None and id_index.is_file():
        fm_g, body_g = read_note(id_index)
        lines.append(markdown_link(title_of(fm_g, body_g, id_index.stem), id_index, base))
    for member in members:
        for d, pth, _tp in topic_order(topics.get(member) or []):
            lines.append(markdown_link(d, pth, base))
    if not lines:
        return out
    if first is not None:
        # すでにある場所（同期が上のブロックを動かしたあとの位置）に、同じ並びで置き直す。空行は増えない
        out[first:first] = lines
        return out
    h1 = next((k for k, ln in enumerate(out) if ln.startswith("# ")), None)
    at = (h1 + 1) if h1 is not None else 0
    if at < len(out) and not out[at].strip():
        at += 1  # 見出しの次の空行は 1 つだけ飛ばす（何度やっても同じ結果にするため）
    out[at:at] = lines + ([""] if at >= len(out) or out[at].strip() else [])
    return out


def _ensure_fm_line(path: Path, key: str, line: str) -> bool:
    """front matter に key が無ければ line を足す（title の次）。既にあれば変えない。本文は変えない。"""
    fm, body = read_note(path)
    if any(_fm_key_re(key).match(ln) for ln in fm):
        return False
    at = next((i + 1 for i, ln in enumerate(fm) if _fm_key_re("title").match(ln)), len(fm))
    fm = fm[:at] + [line] + fm[at:]
    write_note(path, fm, body, keep_trailing_blank=True)
    return True


def _ensure_branch(root: Path, parent: Path, child: Path) -> Optional[str]:
    """parent → child の Branch（child の ParentBranch: に parent、parent の ChildBranch: に child）が無ければ足す。
    child に別の親が既にある・編集中などで足せないときは何も変えず、お知らせを返す。"""
    import branch_ops  # 同ディレクトリの Branch 操作（\b と同じ規則・同じ排他）
    r = branch_ops.add_branch(root, parent, child)
    if r.get("ok"):
        return None
    code = r.get("code")
    if code == "has_parent":
        return f"{child.name}: 既に別の親（{r.get('parent_title')}）があるので、{parent.name} との Branch は足していません"
    if code == "dirty":
        return f"{Path(r.get('path', '')).name}: 編集中なので、Branch は次の再生成で足します"
    return f"{child.name}: {parent.name} との Branch を足せませんでした（{code}）"


_TOP_BLOCK_HEADS = ("ParentBranch:", "BranchGroup:", "ThisNoteGroup:", "Group:", "Context:")
PAPER_DIARY_LINK_TEXT = "紙の日記"


def _digital_diary_for(root: Path, date: str, notes: list) -> Optional[Path]:
    """日付 date のデジタル日記（\\d の日記。紙の日記・グループではない）。デジタル日記の記録
    （.state/diary_days.json）を優先し、無ければ題（YYYY-MM-DD-曜日2文字）で探す。無ければ None（作らない）。"""
    import json
    by_name = {n.path.name: n for n in notes}
    try:
        days = json.loads((root / ".state" / "diary_days.json").read_text(encoding="utf-8")).get("days", {})
    except (OSError, ValueError, AttributeError):
        days = {}
    f = days.get(date) if isinstance(days, dict) else None
    if isinstance(f, str) and f in by_name and diary_date_of(by_name[f]) is None and not by_name[f].group:
        return by_name[f].path
    for n in notes:
        m = DIARY_TITLE_RE.match(n.title)
        if m and m.group(1) == date and diary_date_of(n) is None and not n.group \
                and not any(_fm_key_re("source").match(ln) for ln in n.fm):
            return n.path
    return None


def link_paper_diaries(root: Path, diaries: dict) -> list[str]:
    """紙の日記を、書かれた日付のデジタル日記の、タイトルの下（本文の上の関係のブロックの下・本文より上）に、
    空行 1 行を挟んでリンクする。既に同じ紙の日記へのリンクがあれば足さない（再生成しても重複しない）。
    その日のデジタル日記が無ければ何もしない（作らない）。編集中のデジタル日記には書かない。戻り値: お知らせ。"""
    import note_format_v2 as nf
    notes = load_notes(root)
    msgs: list[str] = []
    for date, ppath in sorted(diaries.items()):
        dpath = _digital_diary_for(root, date, notes)
        if dpath is None:
            continue  # その日のデジタル日記が無い（作らない。日記ができたあとの再生成でリンクする）
        fm, body = read_note(dpath)
        pn = os.path.normpath(str(ppath))
        if any(_norm_link(dpath.parent, m.group(1)) == pn for ln in body for m in _MD_LINK_RE.finditer(ln)):
            continue
        if nf._editor_has_unsaved_changes(dpath):
            msgs.append(f"紙の日記 {date}: デジタル日記 {dpath.name} が編集中なので、次の再生成でリンクします")
            continue
        h1 = next((i for i, ln in enumerate(body) if re.match(r"^#\s", ln)), None)
        at = h1 + 1 if h1 is not None else 0
        i = at
        while True:  # タイトルの直後の関係のブロック（Group: など）は飛ばす
            j = i
            while j < len(body) and not body[j].strip():
                j += 1
            if j < len(body) and body[j].strip() in _TOP_BLOCK_HEADS:
                j += 1
                while j < len(body) and _IS_LINK_LINE.match(body[j]):
                    j += 1
                i = at = j
                continue
            break
        new = [markdown_link(PAPER_DIARY_LINK_TEXT, ppath, dpath.parent)]
        if not (at > 0 and not body[at - 1].strip()):
            new.insert(0, "")
        if at < len(body) and body[at].strip():
            new.append("")
        body[at:at] = new
        write_note(dpath, fm, body, keep_trailing_blank=True)
    return msgs


def _root_id(fid: str) -> str:
    while parent_id(fid) is not None:
        fid = parent_id(fid)
    return fid


def _sync_link_block(body: list[str], base: Path, strip_targets: set[str],
                     desired: list[tuple[Path, str]]) -> list[str]:
    """自動で作るリンク（紙の日記の構造: 日・月・年へのリンク）を、本文の中でその場で直す。

    - 今ある構造リンクの行は、必要なものならその位置のまま（表示名だけ新しく）残す。
      不要になったもの（消えた日記など）の行だけ消す。
    - 足りないものは、並びの順で前後のリンクの隣に入れる（どれも無ければ、最初の節の手前か末尾）。
    - 空行など、それ以外の行は一切変えない（ノートの空行は利用者が自由に入れる。自動では足さない）。
    """
    want = {os.path.normpath(str(t)): line for t, line in desired}
    order = [os.path.normpath(str(t)) for t, _ in desired]
    out: list[str] = []
    emitted: dict[str, int] = {}
    for ln in body:
        m = re.search(r"\]\(([^)#]+)", ln)
        key = os.path.normpath(str(base / m.group(1))) if m else None
        if key is not None and key in strip_targets:
            if key in want and key not in emitted:
                emitted[key] = len(out)
                out.append(want[key])
            continue  # 不要になった構造リンク / 重複は消す
        out.append(ln)
    for i, key in enumerate(order):
        if key in emitted:
            continue
        prev = next((emitted[k] for k in reversed(order[:i]) if k in emitted), None)
        if prev is not None:
            at = prev + 1
        else:
            nxt = next((emitted[k] for k in order[i + 1:] if k in emitted), None)
            if nxt is not None:
                at = nxt
            else:
                at = next((j for j, ln in enumerate(out) if _is_section_head(ln)), len(out))
        out.insert(at, want[key])
        # 以降の位置を 1 つずつずらす
        for k2 in emitted:
            if emitted[k2] >= at:
                emitted[k2] += 1
        emitted[key] = at
    return out


def _timeline_fm(fm: list[str], title: str) -> list[str]:
    """木のノートの front matter: 時刻・title・timeline: true（グループの印 attribute は付けない）。"""
    rest = [ln for ln in fm if not re.match(r"^\s*(title|attribute|timeline)\s*:", ln)]
    at = next((i for i, ln in enumerate(rest) if ln.startswith("time:")), -1)
    rest[at + 1:at + 1] = [f"title: {title}", "timeline: true"]
    return rest


def _write_tree_node(root: Path, existing: Optional[Path], title: str, strip: set[str]) -> Path:
    """紙の日記の木のノート（一番上・年・月）を作る／作り直す。グループだった旧い形は、その場で普通のノートに直す。
    子は本文ではなく ChildBranch:（同期が書く）に出るので、本文の古い構造リンクは外す。手書きは残す。"""
    path = existing
    if path is None:
        path = unique_note_path(root)
        write_note(path, [_time_line(), f"title: {title}", "timeline: true"], [f"# {title}", ""],
                   keep_trailing_blank=True)
    fm, body = read_note(path)
    old_title = title_of(fm, body, "")
    body = _sync_link_block(body, path.parent, strip, [])
    if old_title and old_title != title:
        body = [f"# {title}" if ln.strip() == f"# {old_title}" else ln for ln in body]
    write_note(path, _timeline_fm(fm, title), body, keep_trailing_blank=True)
    return path


def _set_tree_parent(child: Path, parent: Path, parent_title: str, tree_names: set[str]) -> None:
    """child の ParentBranch: を parent の 1 本にする。旧い形（グループ）の所属 Group: は外す。"""
    import branch_ops as bo
    import diary_tree as dt
    import note_format_v2 as nf
    text = child.read_text(encoding="utf-8")
    new = dt.remove_block_links(text, nf.GROUP_MARK, tree_names)
    new = dt.set_parent(new, bo._link(child.parent, parent, parent_title))
    if new != text:
        child.write_text(new, encoding="utf-8")


def build_diary_tree(root: Path, diaries: dict[str, Path], notes: Optional[list] = None,
                     top_existing: Optional[Path] = None) -> tuple[Path, set[str]]:
    """紙の日記を、グループではない普通のノートの木にする。戻り値: (一番上のノート「紙の日記」, 構造ノートの正規化パス)。

        紙の日記 > （年 `YYYY-紙` >）月 `YYYY-MM-紙` > その日のノート（`YYYY-MM-DD-曜日2文字`）

    - どれも timeline: true の普通のノート。子の ParentBranch: に親が入り、親の ChildBranch: は同期が書く。Folgezettel の番号も付く。
    - **年のノートは、日記が 2 つ以上の年にまたがってから**作る（年が変わるまでは月が「紙の日記」の直下）。
    - 旧い形（グループの月・年・日記）は、同じファイルのまま普通のノートに直す（regen のたびに同じ結果になる）。
    """
    notes = notes if notes is not None else load_notes(root)
    groups = paper_diary_groups(notes)
    by_month: dict[str, list[tuple[str, Path]]] = {}
    for date, path in sorted(diaries.items()):
        by_month.setdefault(date[:7], []).append((date, path))
    years = sorted({m[:4] for m in by_month})
    use_years = len(years) >= 2
    month_paths: dict[str, Path] = dict(groups["months"])
    year_paths: dict[str, Path] = dict(groups["years"])
    top_path = top_existing or (groups["tops"][0] if groups["tops"] else None)

    strip = {os.path.normpath(str(p)) for p in diaries.values()}
    strip |= {os.path.normpath(str(p)) for p in month_paths.values()}
    strip |= {os.path.normpath(str(p)) for p in year_paths.values()}

    top = _write_tree_node(root, top_path, DIARY_GROUP_TITLE, strip)
    strip.add(os.path.normpath(str(top)))
    for month in sorted(by_month):
        month_paths[month] = _write_tree_node(root, month_paths.get(month), f"{month}-紙", strip)
        strip.add(os.path.normpath(str(month_paths[month])))
    if use_years:
        for y in years:
            year_paths[y] = _write_tree_node(root, year_paths.get(y), f"{y}-紙", strip)
            strip.add(os.path.normpath(str(year_paths[y])))
    tree_names = {Path(p).name for p in strip} | {top.name}
    for month, days in sorted(by_month.items()):
        parent = year_paths[month[:4]] if use_years else top
        parent_title = f"{month[:4]}-紙" if use_years else DIARY_GROUP_TITLE
        _set_tree_parent(month_paths[month], parent, parent_title, tree_names)
        for _d, p in days:
            _set_tree_parent(p, month_paths[month], f"{month}-紙", tree_names)
    if use_years:
        for y in years:
            _set_tree_parent(year_paths[y], top, DIARY_GROUP_TITLE, tree_names)
    return top, strip


def _regen_ns(root: Path, prefix: str, index_path: Path, notes: list, diaries: dict, added_report: list[str]) -> None:
    """1 つの名前空間（紙の番号の印 prefix）の Index-write・グループ・Folgezettel-Index・番号専用ノート・スキャンノートを作り直す。
    ns_set が済んでいること。紙の日記は diaries を渡した名前空間（最初の 1 つ）だけが扱う。"""
    index_display = index_title(index_path)

    entries: list[dict] = []
    index_write = named_path(root, ns_title('iw'))
    keyword_line_order: list[tuple[int, dict]] = []
    if index_write.is_file():
        iw_fm, body = read_note(index_write)
        # Index-write も、索引（キーワード行）を書くグループ（attribute: group）。同名のノートを別に持たない
        iw_fm_new = _fm_title_attr(iw_fm, title_of(iw_fm, body, ns_title('iw')))
        iw_fm_changed = iw_fm_new != iw_fm
        iw_fm = iw_fm_new
        for i, line in enumerate(body):
            entry = parse_keyword_line(line)
            if entry is not None:
                keyword_line_order.append((i, entry))
                entries.append(entry)
        entries.sort(key=keyword_sort_key)
        if keyword_line_order:
            slots = [i for i, _ in keyword_line_order]
            for slot, entry in zip(slots, entries, strict=False):
                body[slot] = entry["key"] + ": " + ", ".join(entry["ids"])
        if not any(_is_section_head(ln) for ln in body):
            body += [CONTEXT_HEAD,
                     markdown_link(index_display, index_path, root)]
            write_note(index_write, iw_fm, body)
        elif keyword_line_order or iw_fm_changed:
            write_note(index_write, iw_fm, body)
    entries.sort(key=keyword_sort_key)

    # 紙の日記があれば、キーワード「日記」を 1 つだけ入れる（Index-write に同名のキーワードが
    # あればそれに日記を足す。無ければ自動で追加する）。regen のたびに作り直すので消えない。
    for date, dpath in diaries.items():
        fm_d, body_d = read_note(dpath)
        # 画像の次に空行が無ければ 1 つ足す（画像と ### Group などの節をくっつけない。あれば触らない）
        new_body = _blank_after_last_image(body_d)
        if new_body != body_d:
            write_note(dpath, fm_d, new_body, keep_trailing_blank=True)
    if diaries:
        dup = [e for e in entries if e["display"] == DIARY_KEYWORD]
        if dup:
            for e in dup:
                e["diary"] = True
            del dup[1:]  # 同名が複数あっても、グループは 1 つ
        else:
            entries.append({"key": DIARY_KEYWORD, "display": DIARY_KEYWORD, "ids": [],
                            "diary": True, "title": DIARY_GROUP_TITLE})
        entries.sort(key=keyword_sort_key)
    readings = _entry_readings(entries)

    folge = scan_folgezettel_notes(root, notes, prefix=prefix)

    # --- グループ（複数IDのキーワード）と、紙の日記の「日記」 ----------------------
    group_paths: dict[str, Path] = {}
    seen_groups: set[str] = set()
    for entry in entries:
        if len(entry["ids"]) < 2 and not entry.get("diary"):
            continue
        display = entry["display"]
        if display in seen_groups:
            continue  # 同名キーワードは 1 つのグループにまとめる
        seen_groups.add(display)
        group_title = entry.get("title", display)
        if entry.get("diary"):
            # 紙の日記はグループではなく、普通のノートの木（紙の日記 > 年 > 月 > 日）。キーワード「日記」は一番上のノートへのリンク
            group_paths[display], _structure = build_diary_tree(
                root, diaries, load_notes(root), find_diary_group(root, index_path, notes))
            continue
        group_path = find_group(root, display, index_path, notes)
        if group_path is None:
            group_path = _new_group_note(root, display, readings[display])
        group_paths[display] = group_path

        inner = [
            markdown_link(fid, folge[fid], group_path.parent)
            for fid in sorted(
                (f for f in entry["ids"] if f in folge), key=natural_key
            )
        ]
        inner.append(CONTEXT_HEAD)
        inner.append(markdown_link(index_display, index_path, group_path.parent))

        fm, old_group_body = read_note(group_path)
        # キーワードから外した ID のリンクは、グループの本文からも外す（残りのリンクはその場のまま）
        id_ids = sorted((f for f in entry["ids"] if f in folge), key=natural_key)
        old_group_body = _sync_link_block(
            old_group_body, group_path.parent, {os.path.normpath(str(p)) for p in folge.values()},
            [(folge[f], markdown_link(f, folge[f], group_path.parent)) for f in id_ids])
        fm = _fm_title_attr(fm, display)
        fm = _update_yomi(fm, {display: readings[display]})
        write_note(group_path, fm, merge_note_body(old_group_body, inner))

    # --- Paper-Zettelkasten-Index のキーワードリンク ------------------------
    inner: list[str] = []
    for entry in entries:
        display = entry["display"]
        if len(entry["ids"]) >= 2 or entry.get("diary"):
            target = group_paths.get(display)
            link = markdown_link(display, target, index_path.parent) if target is not None else None
            if link is not None and link not in inner:  # 同名キーワードは 1 回だけ
                inner.append(link)
        elif entry["ids"][0] in folge:
            target = folge[entry["ids"][0]]
            inner.append(markdown_link(display, target, index_path.parent))

    fm, old_index_body = read_note(index_path)
    fm = _fm_title_attr(fm, title_of(fm, old_index_body, DEFAULT_INDEX_TITLE))
    fixed_links = [markdown_link(ns_title('iw'), named_path(root, ns_title('iw')), index_path.parent),
                   markdown_link(ns_title('fi'), named_path(root, ns_title('fi'), True), index_path.parent)]
    body = [f"# {index_display}", "", *fixed_links, *inner]
    merged = merge_note_body(old_index_body, body)
    # Index-write・Folgezettel-Index の固定リンクは連続させ、その次のキーワード一覧との間に空行を 1 行置く
    fi_at = next((k for k, ln in enumerate(merged) if ln.strip() == fixed_links[1]), None)
    if fi_at is not None and fi_at + 1 < len(merged) and _IS_LINK_LINE.match(merged[fi_at + 1]):
        merged.insert(fi_at + 1, "")
    write_note(index_path, fm, merged)

    # --- Folgezettel-Index（日記 → 最上位IDを自然順。各リンクは専用ノート folgezettel-Index-N#N） ---
    folge_index = named_path(root, ns_title('fi'), True)
    id_links = [
        (folge_index_path(root, fid), markdown_link(fid, folge_index_path(root, fid), folge_index.parent, frag=fid))
        for fid in top_level_ids(folge)
    ]
    desired = list(id_links)
    # 紙の日記があれば、一番上に「日記」を並べる（Paper-Zettelkasten-Index と同じ日記グループ）:
    #   Folgezettel-Index → 日記 → 月 → その月のノート（年をまたいだら 日記 → 年 → 月グループ → その月のノート）
    diary_top = group_paths.get(DIARY_KEYWORD) if diaries else None
    if diary_top is not None:
        desired.insert(0, (diary_top, markdown_link(DIARY_KEYWORD, diary_top, folge_index.parent)))
    if not folge_index.is_file():
        write_note(folge_index, [_time_line(), f"title: {ns_title('fi')}", "attribute: group"],
                   [f"# {ns_title('fi')}", ""], keep_trailing_blank=True)
    fm, old_folge_body = read_note(folge_index)
    # 旧い `[diary](…)` の行（英語表記）は、日記グループへの `[日記](…)` に置き換える（位置も一番上へ）
    old_folge_body = [ln for ln in old_folge_body if ln.strip() != f"[diary]({_rel(folge_index.parent, diary_top)})"] \
        if diary_top is not None else old_folge_body
    structure = {os.path.normpath(str(t)) for t, _ in desired}
    if diary_top is not None:
        structure.add(os.path.normpath(str(diary_top)))
    old_folge_body = _sync_link_block(old_folge_body, folge_index.parent, structure, desired)
    fm = _fm_title_attr(fm, ns_title('fi'))
    write_note(folge_index, fm, merge_note_body(old_folge_body, [
        f"# {ns_title('fi')}", "", *[ln for _, ln in desired],
        CONTEXT_HEAD,
        markdown_link(index_display, index_path, folge_index.parent)]))

    # --- トピック別Index（`1-Index` グループは作らない。ID ノート `1` の BranchGroup: に `1-仏教` を入れる） ---
    # トピックの親子（front matter の topic_parent）は表示順のためだけ: 親を子より先に並べる。インデントは付けない。
    # 紙ノート 1 がトピックの ParentBranch（1 の ChildBranch にトピック）。Context では代用しない。
    added_report: list[str] = []
    notes = load_notes(root)
    topics = scan_topic_notes(root, notes, prefix)
    id_index_paths: dict[str, Path] = {}
    branch_lines: dict[str, list[str]] = {}

    for fid in sorted(topics, key=natural_key):
        tlist = topics[fid]
        disp_path = {disp: path for disp, path, _tp in tlist}
        for _disp, tpath, tp in tlist:
            _ensure_fm_line(tpath, "source", SCAN_SOURCE_LINE)
            if tp:  # 旧い形（Context のリンク）で分かった親も、front matter に残す
                _ensure_fm_line(tpath, TOPIC_PARENT_KEY, f"{TOPIC_PARENT_KEY}: {tp}")
        owner = folge.get(fid)
        if owner is None:
            continue  # ID ノートが無いときは BranchGroup の置き場が無い（スキャンしたら入る）
        topic_norm = {os.path.normpath(str(path)): (disp, tp) for disp, path, tp in tlist}
        lines = _existing_branch_group(owner)
        # 旧形式の `1-Index` グループ（グループ本文のインデントが階層）があれば、その並びを引き継ぐ（インデントは外す）
        legacy = find_id_index(root, fid, notes)
        if legacy is not None:
            for ln in _legacy_topic_lines(legacy, topic_norm, owner.parent):
                lines = _branch_add_line(lines, ln, owner.parent)
        lines = _branch_add_topics(lines, owner.parent, tlist, disp_path)
        branch_lines[fid] = lines
        if legacy is not None:
            # 旧 `1-Index` を指していたリンクは ID ノートへ向け直し、旧グループはごみ箱へ（内容は BranchGroup に移した）
            _rewrite_links_to(root, legacy, owner)
            _trash_note(root, legacy)
        for disp, tpath, tp in tlist:
            # トピックノートの Context に folgezettel-Index-N を足す（無いときだけ。本文・ほかの関係は消さない）
            fm_t, body_t = read_note(tpath)
            folge_link = markdown_link(folge_index_display(fid),
                                       folge_index_path(root, fid), tpath.parent)
            new_body = merge_note_body(body_t, [CONTEXT_HEAD, folge_link])
            if new_body != body_t:
                write_note(tpath, fm_t, new_body)

    # --- 番号専用ノート folgezettel-Index-N ----------------------------------
    write_folge_index_notes(root, folge, id_index_paths, topics)

    # --- スキャンノートの本文と Context -------------------------------------
    for fid, note_path in folge.items():
        _ensure_fm_line(note_path, "source", SCAN_SOURCE_LINE)
        fm, old_body = read_note(note_path)
        images = [ln for ln in old_body if re.match(r"^!\[\]\(", ln.strip())]
        inner = [f"# {with_prefix(prefix, fid)}", "", *images, CONTEXT_HEAD]
        # 専用ノート folgezettel-Index-N の自ID節（#ID）を Context に入れる（親子は Branch で表す）
        root_fid = _root_id(fid)
        inner.append(markdown_link(folge_index_display(root_fid), folge_index_path(root, root_fid),
                                   note_path.parent, frag=fid))
        mapping = {
            e["display"]: readings[e["display"]]
            for e in entries
            if len(e["ids"]) == 1 and e["ids"][0] == fid
        }
        fm = _update_yomi(fm, mapping)
        write_note(note_path, fm, merge_note_body(old_body, inner))
        if fid in branch_lines:
            _write_branch_group(note_path, branch_lines[fid])

    # --- Branch: 紙ID 1a の ParentBranch に 1（1 の ChildBranch に 1a）、トピックの ParentBranch に紙ノート 1 ---
    for fid in sorted(folge, key=natural_key):
        pid = parent_id(fid)
        if pid is not None and pid in folge:
            msg = _ensure_branch(root, folge[pid], folge[fid])
            if msg:
                added_report.append(msg)
    for fid in sorted(topics, key=natural_key):
        if fid not in folge:
            continue
        for _disp, tpath, _tp in topic_order(topics[fid]):
            msg = _ensure_branch(root, folge[fid], tpath)
            if msg:
                added_report.append(msg)


def has_paper_pkm(root: Path) -> bool:
    """紙の PKM（Paper-Zettelkasten-Index のグループ。印が複数なら Paper-Zettelkasten-Index-PA など）があるか。"""
    for n in load_notes(Path(root)):
        if fm_value(n.fm, "paper_index") or (n.group and (n.title == DEFAULT_INDEX_TITLE or n.title.startswith(DEFAULT_INDEX_TITLE + "-"))):
            return True
    return False


def default_prefix(root: Path) -> str:
    """これから取り込む紙のノートの印（設定 paperIdPrefix。既定 PA）。"""
    import folgezettel as fz  # 遅延 import（note_format_v2 を読み込む）
    return fz.paper_prefix(root)[:-1]


def reconcile_names(root: Path, namespaces: list[str], notes: list) -> int:
    """印が 1 つ ⇔ 複数 で変わる生成物の題を直す。印が 2 つ以上になったら、今までの名前（Index-write など）を
    いちばん古いスキャンノートの印のものとして `Index-write-PA` のように改名する。1 つに戻ったら元の名前に戻す。直した数を返す。"""
    multi = len(namespaces) > 1
    done = 0
    scans = []
    for n in notes:
        k = scan_key_of(n)
        if k and k[0]:
            scans.append((creation_stamp(n), k[0]))
    if multi:
        owner = min(scans)[1] if scans else namespaces[0]
        mapping = [(DEFAULT_INDEX_TITLE, True), (INDEX_WRITE[:-3], None), (FOLGE_INDEX[:-3], True)]
        for base, grp in mapping:
            for n in notes:
                if n.title == base and (grp is None or n.group == grp):
                    if base == INDEX_WRITE[:-3] and not any(DEFAULT_INDEX_TITLE in ln for ln in n.body):
                        continue   # 紙の Index-write だけ（デジタルの同名ノートは触らない）
                    _retitle(n.path, f"{base}-{owner}")
                    done += 1
        for n in notes:
            m = re.match(r"^folgezettel-Index-(\d.*)$", n.title)
            if m:
                _retitle(n.path, f"folgezettel-Index-{owner}-{m.group(1)}")
                done += 1
    elif namespaces:
        p = namespaces[0]
        for base in (DEFAULT_INDEX_TITLE, INDEX_WRITE[:-3], FOLGE_INDEX[:-3]):
            for n in notes:
                if n.title == f"{base}-{p}":
                    _retitle(n.path, base)
                    done += 1
        for n in notes:
            m = re.match(rf"^folgezettel-Index-{re.escape(p)}-(\d.*)$", n.title)
            if m:
                _retitle(n.path, f"folgezettel-Index-{m.group(1)}")
                done += 1
    if done:
        reset_name_cache()
    return done


def creation_stamp(n: NoteInfo) -> str:
    """ノートの作成の目安（front matter の time:。無ければ空）。古い順に並べるため。"""
    return (fm_value(n.fm, "time") or "").strip()


def ensure_ns_structure(root: Path) -> Path:
    """今の名前空間（ns_set 済み）のグループ・Index-write・Folgezettel-Index が無ければ作る。グループのパスを返す。"""
    index_write = named_path(root, ns_title('iw'))
    if not index_write.is_file():
        write_note(index_write, [_time_line(), f"title: {ns_title('iw')}", "attribute: group"], [f"# {ns_title('iw')}", ""])
    index_path = find_paper_index(root)
    if index_path is None:
        index_path = named_path(root, ns_title('index'), True)
        _write_new_paper_index(index_path, index_write, named_path(root, ns_title('fi'), True))
    return index_path


def regen(root: Path, do_sync: bool = True) -> bool:
    """Index・グループ・Folgezettel-Index・スキャンノートの本文を再生成する。
    紙のノートの印（PA・PB…）ごとに、グループ Paper-Zettelkasten-Index（印が複数なら -PA など）・Index-write・Folgezettel-Index を作る。
    頂点のノート Paper-Zettelkasten-Index の BranchGroup: に、そのグループが並ぶ。"""
    root = Path(root).resolve()
    reset_name_cache()
    ns_set("", False)
    if not has_paper_pkm(root):
        return False
    # 旧い front matter の目印（folgezettel: など）を、新しい判定で確かめられたものから外す。
    # 確かめられないものは消さず、警告として残す。
    report = migrate_legacy_metadata(root)
    default = default_prefix(root)
    # 印の無い題（旧い形）の紙のノートは、今の印（既定 PA）のものにする。以後は、ノートごとに自分の印を題に持つ
    adopt_legacy_prefix(root, default)
    notes = load_notes(root)
    namespaces = scan_namespaces(root, notes) or [default]
    reconcile_names(root, namespaces, notes)
    reset_name_cache()
    notes = load_notes(root)
    for title, paths in sorted(find_scan_conflicts(root, notes).items(), key=lambda kv: natural_key(kv[0])):
        report.append(f"ID {title} が重複しています（title: {title} のスキャンノートが複数）: "
                      + ", ".join(p.name for p in paths))
    LAST_REPORT[:] = report
    for msg in report:
        print(f"paper_pkm: {msg}", file=sys.stderr)
    multi = len(namespaces) > 1
    diaries = scan_diary_notes(root, notes)
    added_report: list[str] = []
    groups: list[Path] = []
    for k, prefix in enumerate(namespaces):
        ns_set(prefix, multi)
        index_path = ensure_ns_structure(root)
        reset_name_cache()
        _regen_ns(root, prefix, index_path, load_notes(root), diaries if k == 0 else {}, added_report)
        groups.append(index_path)
        reset_name_cache()
    ns_set(namespaces[0], multi)
    # --- 頂点の普通のノート（題 Paper-Zettelkasten-Index）。BranchGroup: にグループ（印ごとに 1 つ）------------
    ensure_paper_top(root, groups)

    # --- 紙の日記: スキャン由来の印と、その日のデジタル日記からのリンク ------------
    for _date, dpath in diaries.items():
        _ensure_fm_line(dpath, "source", SCAN_SOURCE_LINE)
    added_report += link_paper_diaries(root, diaries)
    for msg in added_report:
        print(f"paper_pkm: {msg}", file=sys.stderr)
    LAST_REPORT[:] = report + added_report

    if do_sync:
        jy.clear_memos()
        import note_format_v2  # 同ディレクトリの SYN 同期エンジン

        note_format_v2.simple_sync(root)
    return True


def find_paper_top(root: Path) -> Optional[Path]:
    """頂点の普通のノート（題 Paper-Zettelkasten-Index・グループではない）。題で探す。"""
    return find_titled(root, DEFAULT_INDEX_TITLE, False)


def ensure_paper_top(root: Path, groups: list[Path]) -> Path:
    """頂点の普通のノートを作る／直す。

        Paper-Zettelkasten-Index（普通のノート。ChildBranch: は空）
          BranchGroup: 紙の番号の印ごとのグループ（印が 1 つなら Paper-Zettelkasten-Index、複数なら Paper-Zettelkasten-Index-PA など）
            └ グループの中に Index-write（グループ。索引を書く）・Folgezettel-Index（グループ）・キーワード

    vault の index.md からは、グループではなくこの頂点のノートへリンクする（グループへのリンクは頂点へ張り替える）。"""
    top = find_paper_top(root)
    if top is None:
        top = named_path(root, DEFAULT_INDEX_TITLE, False)
        write_note(top, [_time_line(), f"title: {DEFAULT_INDEX_TITLE}"], [f"# {DEFAULT_INDEX_TITLE}", ""],
                   keep_trailing_blank=True)
    # 頂点のノートの BranchGroup: はグループだけ（印ごとに 1 つ）。Index-write と Folgezettel-Index は、そのグループの中のグループ
    lines = [markdown_link(index_title(g), g, top.parent) for g in groups]
    _write_branch_group(top, lines)
    parent_index = Path(root) / "index.md"
    if parent_index.is_file():
        fm, body = read_note(parent_index)
        new_link = markdown_link(DEFAULT_INDEX_TITLE, top, parent_index.parent)
        changed = False
        for g in groups:
            old_target = f"({_rel(parent_index.parent, g)})"
            for i, ln in enumerate(body):
                if ln.strip().startswith("[") and ln.strip().endswith(old_target):
                    body[i] = new_link
                    changed = True
        if changed:
            # 同じ頂点へのリンクが重なったら 1 つにする
            seen = False
            out = []
            for ln in body:
                if ln == new_link:
                    if seen:
                        continue
                    seen = True
                out.append(ln)
            write_note(parent_index, fm, out)
    return top


def _write_new_paper_index(index_path: Path, index_write: Path, folge_index: Path) -> None:
    fm = [
        _time_line(),
        f"title: {ns_title('index')}",
        "attribute: group",
    ]
    body = [
        f"# {ns_title('index')}",
        "",
        markdown_link(ns_title('iw'), index_write, index_path.parent),
        markdown_link(ns_title('fi'), folge_index, index_path.parent),
    ]
    write_note(index_path, fm, body)


def create_paper_index(root: Path) -> Path:
    """紙PKM Index一式（Index-write・Paper-Zettelkasten-Index・Folgezettel-Index）を作る。

    どれもふつうのノート（ファイル名はタイムスタンプ。題で探す）。既に Index があればそれを再利用する。
    作成/更新後に regen（同期込み）を実行。印が複数あるときは、最初の印のグループのパスを返す。
    """
    root = Path(root).resolve()
    reset_name_cache()
    ns_set("", False)
    index_path = None
    if not has_paper_pkm(root):
        index_write = named_path(root, ns_title('iw'))
        if not index_write.is_file():
            old_index_write = find_titled(root, OLD_INDEX_WRITE[:-3])
            if old_index_write is not None:
                fm, body = read_note(old_index_write)
                fm = [f"title: {ns_title('iw')}" if ln.startswith("title:") else ln for ln in fm]
                body = [ns_title('iw') if ln.strip() == OLD_INDEX_WRITE[:-3] else ln for ln in body]
                write_note(old_index_write, fm, body)
                index_write = old_index_write
                reset_name_cache()
            else:
                write_note(
                    index_write,
                    [_time_line(), f"title: {ns_title('iw')}", "attribute: group"],
                    [f"# {ns_title('iw')}", ""],
                )
        index_path = named_path(root, ns_title('index'), True)
        _write_new_paper_index(index_path, index_write, named_path(root, ns_title('fi'), True))
        # vault 親Index（index.md）に Paper-Zettelkasten-Index へのリンクを足す
        parent_index = root / "index.md"
        if parent_index.is_file():
            fm, body = read_note(parent_index)
            top_now = find_paper_top(root)
            if all(index_path.name not in ln and not (top_now is not None and top_now.name in ln) for ln in body):
                # 空行は入れない: 最後のリンク行（内容のある最後の行）の直後に 1 行足す
                link = f"[{DEFAULT_INDEX_TITLE}]({_rel(parent_index.parent, index_path)})"
                last = max((i for i, ln in enumerate(body) if ln.strip()), default=-1)
                body.insert(last + 1, link)
                write_note(parent_index, fm, body)
    else:
        # 旧い題（paper_index: マーカーや旧い名前）のグループは、regen が今の題に直す
        found = find_paper_index(root)
        if found is not None:
            index_path = found
            fm, body = read_note(index_path)
            old_title = title_of(fm, body, "")
            if old_title != ns_title('index'):
                fm = [f"title: {ns_title('index')}" if ln.startswith("title:") else ln for ln in fm]
                body = [f"# {ns_title('index')}" if ln.strip() == f"# {old_title}" else ln for ln in body]
                write_note(index_path, fm, body)

    regen(root)
    return find_paper_index(root) or index_path


def _trash_note(root: Path, note_path: Path) -> Optional[Path]:
    """上書き前の旧ノートを `<vault>/.trash/<時刻>_<名前>` へ退避する。"""
    trash = root / ".trash"
    try:
        trash.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        dest = trash / f"{stamp}_{note_path.name}"
        i = 0
        while dest.exists():
            i += 1
            dest = trash / f"{stamp}-{i}_{note_path.name}"
        note_path.rename(dest)
        return dest
    except OSError:
        return None


def move_images(
    root: Path,
    dest: Path,
    assignments: list[tuple[Path, str]],
) -> tuple[list[tuple[str, Path]], list[tuple[Path, str, str]]]:
    """スキャン画像を ID 名（または `ID-トピック` 名）で dest へ移し、ノートを作る。

    assignments: [(元画像パス, ID)] または [(元画像パス, ID, トピック名, [親トピック])].
    トピック名があるときはトピック別Indexノート（例: title: 1-仏教）を作る。
    同じ表示名が vault に既にあってもエラーにしない: 旧ノートは .trash 退避、
    同名画像は上書き（2026-10-09 指示）。
    戻り値は (moved, errors)。
    moved: [(ID, ノートパス)]（トピックは ID-トピック表示名）/ errors: [(元パス, ID, 理由)]。
    """
    root = Path(root).resolve()
    dest = Path(dest).resolve()
    default = default_prefix(root)
    # 既にあるスキャンノート（印の無い旧い題は、今の印のものとして数える）
    existing = {with_prefix(default, title): path for title, path in scan_folgezettel_notes(root).items()}
    topics = {with_prefix(default, disp): _p for _ids in scan_topic_notes(root).values()
              for disp, _p, _t in _ids}
    seen: set[str] = set()
    moved: list[tuple[str, Path]] = []
    errors: list[tuple[Path, str, str]] = []

    for src, raw_id, *rest in assignments:
        src = Path(src)
        topic = rest[0].strip() if rest else None
        topic = topic or None
        parent_topic = (rest[1].strip() if len(rest) > 1 and rest[1] else None)
        fid = normalize_id(raw_id)
        if not FULL_ID_PATTERN.fullmatch(fid):
            errors.append((src, fid, "IDの形式が不正です"))
            continue
        fid = with_prefix(default, fid)      # 印の無い番号には、今の印（既定 PA）を付ける。画像もノートの題も `PA-1a2`
        display = topic_display(fid, topic) if topic else fid
        if display in seen:
            # 同じバッチ内の重複はフォルダ内で同名 rename になるためそのまま禁止
            errors.append((src, display, "同じ表示名がこのバッチ内にあります"))
            continue
        target = dest / (display + src.suffix.lower())
        when = image_datetime(src) or datetime.now()
        try:
            shutil.move(str(src), str(target))
        except OSError as exc:
            errors.append((src, display, str(exc)))
            continue
        seen.add(display)
        # 上書き: 旧ノートを .trash へ退避する（同名画像は上書き済み）
        old = (existing.get(display) if not topic else None) or topics.get(display)
        if old is not None:
            _trash_note(root, old)
        if topic:
            note_path = create_topic_note(dest, fid, topic, target.name, when,
                                          parent_topic=parent_topic)
        else:
            note_path = create_scan_note(dest, fid, target.name, when)
        moved.append((display, note_path))
    return moved, errors


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="paper_pkm.py")
    sub = ap.add_subparsers(dest="mode", required=True)

    p_create = sub.add_parser("create", help="紙PKM Index一式を作成/再利用")
    p_create.add_argument("root")

    p_regen = sub.add_parser("regen", help="Index・グループ・Folgezettel-Index を再生成")
    p_regen.add_argument("root")
    p_regen.add_argument("--no-sync", action="store_true", help="SYN同期をしない")

    p_ids = sub.add_parser("ids", help="ID → ノートの対応を表示")
    p_ids.add_argument("root")

    p_migrate = sub.add_parser("migrate", help="旧タイムスタンプ名の Index を Paper-Zettelkasten-Index.md へ移行")
    p_migrate.add_argument("root")

    p_diary = sub.add_parser("diary", help="画像を紙の日記として登録（複数ページ可）")
    p_diary.add_argument("root")
    p_diary.add_argument("dest")
    p_diary.add_argument("date", help="日記が書かれた日付 YYYY-MM-DD")
    p_diary.add_argument("files", nargs="+")

    args = ap.parse_args(argv)

    if args.mode == "create":
        path = create_paper_index(Path(args.root))
        print(path)
        return 0

    if args.mode == "regen":
        ok = regen(Path(args.root), do_sync=not args.no_sync)
        if not ok:
            print(tr("paper_pkm: 紙PKM Index（Paper-Zettelkasten-Index）がありません", "paper_pkm: no paper PKM Index (Paper-Zettelkasten-Index)"), file=sys.stderr)
            return 1
        return 0

    if args.mode == "migrate":
        path = migrate_paper_index(Path(args.root))
        if path is None:
            print(tr("paper_pkm: 紙PKM Index（Paper-Zettelkasten-Index）がありません", "paper_pkm: no paper PKM Index (Paper-Zettelkasten-Index)"), file=sys.stderr)
            return 1
        print(path)
        return 0

    if args.mode == "diary":
        moved, errors = register_diary_pages(
            Path(args.root), Path(args.dest), [(Path(f), args.date) for f in args.files])
        for date, note in moved:
            print(f"{date}\t{note}")
        for src, date, reason in errors:
            print(f"error: {src}（{date}）: {reason}", file=sys.stderr)
        regen(Path(args.root))
        return 1 if errors else 0

    if args.mode == "ids":
        for fid, path in sorted(
            scan_folgezettel_notes(Path(args.root)).items(), key=lambda kv: natural_key(kv[0])
        ):
            print(f"{fid}\t{path}")
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
