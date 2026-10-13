#!/usr/bin/env python3
"""紙のPKM（フォルゲゼッテル）連携（simple_yurii_note 用）。

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
import japanese_yomi as jy  # noqa: E402

INDEX_WRITE = "Index-write.md"
OLD_INDEX_WRITE = "Index_write.md"
FOLGE_INDEX = "Folgezettel-Index.md"
DEFAULT_INDEX_TITLE = "Paper-Zettelkasten-Index"
PAPER_INDEX_NAME = "Paper-Zettelkasten-Index.md"  # Index のファイル名は常にこれ

ID_PATTERN = re.compile(r"^\d+(?:[a-z]+\d+)*[a-z]*$")
# キーと ID 部に `:` を許さない（`time: 2026-01-01 00:00:00` のような front matter を
# 後方一致でキーワード行と誤認しないため。`[^:]+?` の後退を防ぐ）。
KEYWORD_LINE_RE = re.compile(
    r"^(?P<key>[^:()]+?)\s*:\s*(?P<ids>[^:]+)$"
)

# 旧い front matter のキー（廃止）。新規には書かない。読むのは移行（migrate_legacy_metadata）だけ。
# ノートの種類は title・画像の参照・リンク階層で判定する（下の「ノートの種類の判定」）。
LEGACY_FM_KEYS = (
    "folgezettel", "paper_index", "paper_diary", "paper_diary_month", "paper_diary_year",
    "paper_keyword", "paper_topic", "paper_topic_index", "folgezettel_index", "topic_parent",
)
DIARY_KEYWORD = "日記"                   # Paper-Zettelkasten-Index のキーワード表示名
DIARY_GROUP_TITLE = "日記"               # 紙の日記の一番上のグループの題（デジタル日記のグループも「日記」。区別はリンク階層）
OLD_DIARY_GROUP_TITLE = "紙の日記"       # 旧い題（regen が「日記」に直す）
DIARY_IMAGE_PREFIX = "paper-diary-"

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp", ".webp"}


# ---------------------------------------------------------------------------
# ID
# ---------------------------------------------------------------------------


def natural_key(text: str):
    return [
        int(part) if part.isdigit() else part.casefold()
        for part in re.split(r"(\d+)", text)
    ]


def normalize_id(raw: str) -> str:
    return unicodedata.normalize("NFKC", raw).strip().lower()


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
SECTION_HEADS = ("### Context", "### Parent", "### Group", "### Related", "### BackLink")


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


def folge_index_display(fid: str) -> str:
    """番号専用ノート folgezettel-Index-N の表示名。"""
    return f"folgezettel-Index-{fid}"


def folge_index_path(root: Path, fid: str) -> Path:
    return Path(root) / f"folgezettel-Index-{fid}.md"


def top_level_ids(folge: dict[str, Path]) -> list[str]:
    return sorted((f for f in folge if parent_id(f) is None), key=natural_key)


def unique_note_path(root: Path, when: Optional[datetime] = None) -> Path:
    base = when or datetime.now()
    for i in range(3660):
        candidate = Path(root) / (
            (base + timedelta(seconds=i)).strftime("%y%m%d%H%M%S") + ".md"
        )
        if not candidate.exists():
            return candidate
    raise RuntimeError("空きタイムスタンプが見つかりません")


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

_IS_LINK_LINE = re.compile(r"^\s*\[[^\]]*\]\([^)]*\)\s*$")
_IMAGE_ONLY_RE = re.compile(r"^!\[[^\]]*\]\(([^)\s]+)\)\s*$")
_MD_LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)\)")
TOPIC_TITLE_RE = re.compile(r"^(\d+(?:[a-z]+\d+)*[a-z]*)-(.+)$")
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
    return NoteInfo(path, fm, body, (fm_value(fm, "title") or path.stem).strip(),
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


def scan_id_of(n: NoteInfo) -> Optional[str]:
    """スキャンノートなら正式なID（title）を返す。普通のノートや判定できないものは None。"""
    fid = normalize_id(n.title)
    if n.title != fid or not ID_PATTERN.fullmatch(fid):
        return None
    return fid if _has_image_named(n, n.title) else None


def topic_of(n: NoteInfo) -> Optional[tuple[str, str]]:
    """トピックノートなら (起点ID, 表示名=title)。"""
    m = TOPIC_TITLE_RE.match(n.title)
    if not m or not ID_PATTERN.fullmatch(m.group(1)):
        return None
    return (m.group(1), n.title) if _has_image_named(n, n.title) else None


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


def scan_folgezettel_notes(root: Path, notes: Optional[list] = None) -> dict[str, Path]:
    """スキャンノート（title が正式なID・本文がその画像を参照）→ {ID: ノート}。
    IDが重複したときは先に見つかった（パス順の）ほうを使う。重複は find_scan_conflicts で検出する。"""
    found: dict[str, Path] = {}
    for n in (notes if notes is not None else load_notes(root)):
        fid = scan_id_of(n)
        if fid:
            found.setdefault(fid, n.path)
    return found


def find_scan_conflicts(root: Path, notes: Optional[list] = None) -> dict[str, list[Path]]:
    """同じID（title）を持つスキャンノートが複数あるもの → {ID: [ノート…]}。"""
    seen: dict[str, list[Path]] = {}
    for n in (notes if notes is not None else load_notes(root)):
        fid = scan_id_of(n)
        if fid:
            seen.setdefault(fid, []).append(n.path)
    return {k: v for k, v in seen.items() if len(v) > 1}


def _legacy_paper_indexes(root: Path) -> list[Path]:
    """旧いタイムスタンプ名などの Paper-Zettelkasten-Index（題が Paper-Zettelkasten-Index、または旧マーカー
    `paper_index:` つき）。固定ファイル名のものは含めない。名前順。"""
    fixed = Path(root) / PAPER_INDEX_NAME
    found: list[Path] = []
    for n in load_notes(root):
        if n.path == fixed:
            continue
        if n.title == DEFAULT_INDEX_TITLE or fm_value(n.fm, "paper_index"):
            found.append(n.path)
    return sorted(found, key=lambda p: p.name)


def find_paper_index(root: Path) -> Optional[Path]:
    """Paper-Zettelkasten-Index。固定ファイル名 `Paper-Zettelkasten-Index.md`（題が Paper-Zettelkasten-Index、
    または旧マーカーつき）を優先し、無ければ旧タイムスタンプ名のもの（複数あれば名前の新しい方）を返す。"""
    fixed = Path(root) / PAPER_INDEX_NAME
    if fixed.is_file():
        n = make_note_info(fixed)
        if n is not None and (n.title == DEFAULT_INDEX_TITLE or fm_value(n.fm, "paper_index")):
            return fixed
    found = _legacy_paper_indexes(Path(root))
    return found[-1] if found else None


def _rewrite_links_to(root: Path, old_path: Path, new_path: Path) -> int:
    """vault の全ノートで、old_path を指す Markdown リンクの宛先を new_path へ書き換える
    （表示名・`#見出し` はそのまま）。書き換えたノート数を返す。"""
    old_norm = os.path.normpath(str(old_path))
    link_re = re.compile(r"(\[[^\]]*\]\()([^)\s]*)(\))")
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
    return {k for k in LEGACY_FM_KEYS if any(_fm_key_re(k).match(ln) for ln in n.fm)}


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
    - `folgezettel:` は title と一致し、かつ title と同じ名前の画像を参照しているスキャンノートだけ外す。
    - `paper_diary:` は日記の日付で、紙の日記の画像（paper-diary-…）を参照しているものだけ外す
      （題が旧い形のときは YYYY-MM-DD-曜日2文字 に直してから）。
    - `topic_parent:` は、親トピックへのリンクが本文の関係の節にあることを確かめてから外す
      （無ければリンクを書き足してから外す。親が見つからなければ残す）。
    - 月・年・キーワードのグループは、リンク階層で今と同じノートが見つかるものだけ外す。
    戻り値: 警告のリスト。"""
    root = Path(root).resolve()
    msgs: list[str] = []
    fixed_index = root / PAPER_INDEX_NAME

    # ---- 1) ノート（グループ以外）----
    notes = load_notes(root)
    topic_parent_of = {os.path.normpath(str(path)): (fid, tp)
                       for fid, lst in scan_topic_notes(root, notes).items() for _d, path, tp in lst}
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
            elif key == "topic_parent":
                if all(not x for x in vals):
                    drop.add(key)
                    continue
                parent = next((x for x in vals if x), "")
                fid_tp = topic_parent_of.get(os.path.normpath(str(n.path)))
                if fid_tp is not None and fid_tp[1] == parent:
                    drop.add(key)
                elif fid_tp is not None:
                    # リンクの親と旧い値が違う: 本文のリンクを正とせず、矛盾として残す
                    msgs.append(f"{n.path.name}: topic_parent: {parent!r} と、本文の Context にある親トピック {fid_tp[1]!r} が違います（消していません）")
                else:
                    cand = None
                    t = topic_of(n)
                    if t is not None:
                        for disp, ppath, _tp in scan_topic_notes(root, notes).get(t[0], []):
                            if disp == parent:
                                cand = ppath
                    if cand is None:
                        msgs.append(f"{n.path.name}: topic_parent: {parent!r} のトピックが見つかりません（消していません）")
                    else:
                        _add_context_link(n.path, markdown_link(parent, cand, n.path.parent))
                        drop.add(key)
            elif key == "folgezettel_index":
                if n.path.name == f"folgezettel-Index-{v}.md" and n.title == f"folgezettel-Index-{v}":
                    drop.add(key)
                else:
                    msgs.append(f"{n.path.name}: folgezettel_index: {v!r} をファイル名と title から確認できません（消していません）")
            elif key == "paper_topic_index":
                if n.group and n.title in (f"{v}-Index", f"{v}_Index"):
                    drop.add(key)
                else:
                    msgs.append(f"{n.path.name}: paper_topic_index: {v!r} を title と attribute から確認できません（消していません）")
            elif key == "paper_index":
                if n.path == fixed_index:
                    drop.add(key)
                # 旧いタイムスタンプ名のものは migrate_paper_index が改名してから外す
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
    """旧タイムスタンプ名の Paper-Zettelkasten-Index を `Paper-Zettelkasten-Index.md` へ移行する。

    - 内容・キーワード・リンク・メタデータはそのまま（ファイルの改名だけ）。
    - 他のノート（`index.md` を含む）からのリンクの宛先を新しい名前へ書き換える。
    - 固定名のファイルが既にある場合は、上書きもデータ消失もしない: 固定名がマーカー付きの
      Index ならそれを正とし、旧ファイルはそのまま残す。固定名が Index でない別のノートなら
      何もしない（旧ファイルをそのまま使い続ける）。
    戻り値: 使う Index のパス（Index が無ければ None）。
    """
    root = Path(root).resolve()
    fixed = root / PAPER_INDEX_NAME
    current = find_paper_index(root)
    if current is None or current == fixed:
        return current
    if fixed.exists():
        print(f"paper_pkm: {PAPER_INDEX_NAME} が既にあるため移行しません（{current.name} を使います）",
              file=sys.stderr)
        return current
    os.rename(current, fixed)
    _rewrite_links_to(root, current, fixed)
    return fixed


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


_IMAGE_LINE_RE = re.compile(r"^!\[[^\]]*\]\((.+)\)$")


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
            fm = [_time_line(when), f"title: {diary_title(date)}"]
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
    fm, _ = read_note(index_path)
    return fm_value(fm, "title") or DEFAULT_INDEX_TITLE


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
    fm = [_time_line(when), f"title: {fid}"]
    body = [f"# {fid}", "", f"![]({image_name})"]
    write_note(path, fm, body)
    return path


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
    """トピック別Indexノート（例: title: 1-仏教・画像添付・Context は regen が直す）。

    parent_topic は親トピックノートの表示名（例: 1-仏教）。階層は front matter ではなく本文の
    `### Context` のリンクで持つ（あとから Context のリンクを手で直しても変えられる）。
    """
    path = unique_note_path(folder)
    display = topic_display(fid, topic)
    fm = [_time_line(when), f"title: {display}"]
    body = [f"# {display}", "", f"![]({image_name})"]
    if parent_topic:
        for disp, ppath, _tp in scan_topic_notes(root or folder).get(fid, []):
            if disp == parent_topic:
                body += [CONTEXT_HEAD, markdown_link(disp, ppath, path.parent)]
                break
    write_note(path, fm, body)
    return path


def scan_topic_notes(root: Path, notes: Optional[list] = None) -> dict[str, list[tuple[str, Path, Optional[str]]]]:
    """トピックノート（title が `ID-トピック名`・本文がその画像を参照）→ {起点ID: [(表示名, ノート, 親トピック名), …]}。

    親トピック名（例: 1-仏教）は、本文の関係の節（Context など）にある、同じ起点IDの別のトピックノートへの
    リンクから求める。無ければ None（最上位）。"""
    notes = notes if notes is not None else load_notes(root)
    topics: dict[str, tuple[str, str]] = {}  # 正規化パス → (起点ID, 表示名)
    for n in notes:
        t = topic_of(n)
        if t:
            topics[os.path.normpath(str(n.path))] = t
    found: dict[str, list[tuple[str, Path, Optional[str]]]] = {}
    for n in notes:
        t = topic_of(n)
        if not t:
            continue
        fid, title = t
        parent = None
        for target in n.links:
            other = topics.get(target)
            if other and other[0] == fid and other[1] != title:
                parent = other[1]
                break
        found.setdefault(fid, []).append((title, n.path, parent))
    for lst in found.values():
        lst.sort(key=lambda t: natural_key(t[0]))
    return found


def find_id_index(root: Path, fid: str, notes: Optional[list] = None) -> Optional[Path]:
    """起点IDの番号別Index（グループ）ノート: title が `<ID>-Index`（旧表記 `<ID>_Index` も）の `attribute: group`。"""
    for n in (notes if notes is not None else load_notes(root)):
        if n.group and n.title in (f"{fid}-Index", f"{fid}_Index"):
            return n.path
    return None


def paper_diary_groups(notes: list) -> dict:
    """紙の日記の月・年・一番上のグループを、リンク階層で見つける（front matter の目印は使わない）。
    戻り値: {"months": {YYYY-MM: path}, "years": {YYYY: path}, "tops": [path…]}。
    - 月 … title が YYYY-MM の attribute: group で、リンク先に紙の日記ノートがある
    - 年 … title が YYYY の attribute: group で、リンク先に紙の日記の月グループがある
    - 一番上 … title が「日記」（旧: 紙の日記）の attribute: group で、リンク先に紙の日記の月/年グループがある
    デジタル日記の同名のグループは、リンク先が紙の日記ではないので含まれない。"""
    diaries = {os.path.normpath(str(n.path)) for n in notes if diary_date_of(n)}
    months: dict[str, Path] = {}
    for n in notes:
        if n.group and re.fullmatch(r"\d{4}-\d{2}", n.title) and any(l in diaries for l in n.links):
            months.setdefault(n.title, n.path)
    month_norms = {os.path.normpath(str(p)) for p in months.values()}
    years: dict[str, Path] = {}
    for n in notes:
        if n.group and re.fullmatch(r"\d{4}", n.title) and any(l in month_norms for l in n.links):
            years.setdefault(n.title, n.path)
    child_norms = month_norms | {os.path.normpath(str(p)) for p in years.values()}
    tops = [n.path for n in notes
            if n.group and n.title in (DIARY_GROUP_TITLE, OLD_DIARY_GROUP_TITLE) and any(l in child_norms for l in n.links)]
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

    found = _target(index_path) or _target(Path(root) / FOLGE_INDEX)
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
                            id_index_paths: dict[str, Path]) -> None:
    """各最上位IDの専用ノート folgezettel-Index-N を作る/作り直す。

    中身: 配下IDの `## <ID>` 見出し + 画像をフォルゲゼッテル自然順で並べ、
    トピックIndex（1-Index）があればそのリンクも入れる。Parent は Folgezettel-Index。
    """
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
        if id_index is not None:
            fm_g, _bg = read_note(id_index)
            gd = fm_value(fm_g, "title") or id_index.stem
            inner.append(markdown_link(gd, id_index, path.parent))
        inner += [CONTEXT_HEAD,
                  markdown_link(FOLGE_INDEX[:-3], root / FOLGE_INDEX, path.parent)]
        write_note(path, fm_fi, merge_note_body(old_fi_body, inner))


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


def _write_diary_group(root: Path, existing: Optional[Path], value: str, links: list[str],
                       strip_targets: set[str], desired: list[tuple[Path, str]],
                       extra_tail: Optional[list[str]] = None) -> Path:
    """紙の日記の月／年グループを作る／作り直す（題 = 値。`attribute: group`。目印の front matter は持たない）。
    本文のリンクはその場で直し（古い構造のリンクは strip_targets で外す）、それ以外の手書きは残す。"""
    path = existing
    if path is None:
        path = unique_note_path(root)
        write_note(path, [_time_line(), f"title: {value}", "attribute: group"], [f"# {value}", ""],
                   keep_trailing_blank=True)
    fm, old_body = read_note(path)
    base = path.parent
    old_body = _sync_link_block(old_body, base, strip_targets, desired)
    fm = [ln for ln in fm if not re.match(r"^\s*(title|attribute)\s*:", ln)]
    fm.insert(1 if fm else 0, f"title: {value}")
    fm.insert(2 if len(fm) > 1 else len(fm), "attribute: group")
    write_note(path, fm, merge_note_body(old_body, [f"# {value}", "", *links, *(extra_tail or [])]))
    return path


def build_diary_hierarchy(root: Path, diaries: dict[str, Path],
                          notes: Optional[list] = None) -> tuple[list[Path], set[str]]:
    """紙の日記を 年・月別のグループにまとめる。戻り値: (一番上のグループ「日記」の直下に並べるノート, 構造ノートの正規化パス)。

    - 日（日記ノート）は月グループ（題 YYYY-MM）の本文に日付順に並ぶ。
    - **年グループ（題 YYYY）は、日記が 2 つ以上の年にまたがってから**作る（年が変わるまでは作らない）。
      またがったら、すべての年に年グループを作り、その本文に月グループを並べる。
    - 年が変わる前は「日記」の直下に月グループが並び、変わったあとは年グループが並ぶ。
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
    # 古い構造のリンク（日・月・年）は、どのグループからも必要なものだけその場で直す
    strip = {os.path.normpath(str(p)) for p in diaries.values()}
    strip |= {os.path.normpath(str(p)) for p in month_paths.values()}
    strip |= {os.path.normpath(str(p)) for p in year_paths.values()}

    for month, days in sorted(by_month.items()):
        links = [markdown_link(diary_title(d), p, root) for d, p in days]
        month_paths[month] = _write_diary_group(root, month_paths.get(month), month, links, strip,
                                                [(p, lk) for (d, p), lk in zip(days, links)])
        strip.add(os.path.normpath(str(month_paths[month])))
    if not use_years:
        # 年グループを作らなかった（まだ作らない）。前に作っていたら残す（消さない）が、並べない
        return [month_paths[m] for m in sorted(month_paths) if m in by_month], strip
    top: list[Path] = []
    for y in years:
        ms = [m for m in sorted(by_month) if m.startswith(y)]
        links = [markdown_link(m, month_paths[m], root) for m in ms]
        year_paths[y] = _write_diary_group(root, year_paths.get(y), y, links, strip,
                                           [(month_paths[m], lk) for m, lk in zip(ms, links)])
        strip.add(os.path.normpath(str(year_paths[y])))
        top.append(year_paths[y])
    return top, strip


def regen(root: Path, do_sync: bool = True) -> bool:
    """Index・グループ・Folgezettel-Index・スキャンノートの本文を再生成する。"""
    root = Path(root).resolve()
    index_path = migrate_paper_index(root)  # 旧タイムスタンプ名なら Paper-Zettelkasten-Index.md へ移す
    if index_path is None:
        return False
    # 旧い front matter の目印（folgezettel: など）を、新しい判定で確かめられたものから外す。
    # 確かめられないものは消さず、警告として残す。
    report = migrate_legacy_metadata(root)
    notes = load_notes(root)
    for fid, paths in sorted(find_scan_conflicts(root, notes).items(), key=lambda kv: natural_key(kv[0])):
        report.append(f"ID {fid} が重複しています（title: {fid} のスキャンノートが複数）: "
                      + ", ".join(p.name for p in paths))
    LAST_REPORT[:] = report
    for msg in report:
        print(f"paper_pkm: {msg}", file=sys.stderr)
    index_display = index_title(index_path)

    entries: list[dict] = []
    index_write = root / INDEX_WRITE
    keyword_line_order: list[tuple[int, dict]] = []
    if index_write.is_file():
        iw_fm, body = read_note(index_write)
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
        elif keyword_line_order:
            write_note(index_write, iw_fm, body)
    entries.sort(key=keyword_sort_key)

    # 紙の日記があれば、キーワード「日記」を 1 つだけ入れる（Index-write に同名のキーワードが
    # あればそれに日記を足す。無ければ自動で追加する）。regen のたびに作り直すので消えない。
    diaries = scan_diary_notes(root, notes)
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

    folge = scan_folgezettel_notes(root, notes)

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
            # 紙の日記の「日記」: デジタル日記のグループも題が「日記」なので、題ではなく Index のリンク階層で見つける
            group_path = find_diary_group(root, index_path, notes)
            if group_path is None and not entry["ids"]:
                group_path = _new_group_note(root, display, readings[display], title=group_title)
        else:
            group_path = None
        if group_path is None:
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
        old_group_body_extra = None
        if entry.get("diary"):
            # 紙の日記は 年・月別のグループにまとめる（年グループは年が変わってから）。
            # 一番上の「日記」グループには、月グループ（年が変わったあとは年グループ）を並べる
            top_children, diary_structure = build_diary_hierarchy(root, diaries, load_notes(root))
            top_links = [markdown_link(fm_value(read_note(p)[0], "title") or p.stem, p, group_path.parent)
                         for p in top_children]
            inner += top_links
            old_group_body_extra = (diary_structure, list(zip(top_children, top_links)))
        inner.append(CONTEXT_HEAD)
        inner.append(markdown_link(index_display, index_path, group_path.parent))

        fm, old_group_body = read_note(group_path)
        old_title = fm_value(fm, "title") or ""
        if old_title in (OLD_DIARY_GROUP_TITLE,) and entry.get("diary"):
            old_group_body = [f"# {group_title}" if ln.strip() == f"# {old_title}" else ln for ln in old_group_body]
        if old_group_body_extra:
            structure, desired_top = old_group_body_extra
            old_group_body = _sync_link_block(old_group_body, group_path.parent, structure, desired_top)
        # キーワードから外した ID のリンクは、グループの本文からも外す（残りのリンクはその場のまま）
        id_ids = sorted((f for f in entry["ids"] if f in folge), key=natural_key)
        old_group_body = _sync_link_block(
            old_group_body, group_path.parent, {os.path.normpath(str(p)) for p in folge.values()},
            [(folge[f], markdown_link(f, folge[f], group_path.parent)) for f in id_ids])
        fm = _fm_title_attr(fm, group_title if entry.get("diary") else display)
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
    fm = _fm_title_attr(fm, fm_value(fm, "title") or DEFAULT_INDEX_TITLE)
    fixed_links = [f"[{INDEX_WRITE[:-3]}]({INDEX_WRITE})", f"[{FOLGE_INDEX[:-3]}]({FOLGE_INDEX})"]
    body = [f"# {index_display}", "", *fixed_links, *inner]
    merged = merge_note_body(old_index_body, body)
    # Index-write・Folgezettel-Index の固定リンクは連続させ、その次のキーワード一覧との間に空行を 1 行置く
    fi_at = next((k for k, ln in enumerate(merged) if ln.strip() == fixed_links[1]), None)
    if fi_at is not None and fi_at + 1 < len(merged) and _IS_LINK_LINE.match(merged[fi_at + 1]):
        merged.insert(fi_at + 1, "")
    write_note(index_path, fm, merged)

    # --- Folgezettel-Index（日記 → 最上位IDを自然順。各リンクは専用ノート folgezettel-Index-N#N） ---
    folge_index = root / FOLGE_INDEX
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
        write_note(folge_index, [_time_line(), f"title: {FOLGE_INDEX[:-3]}", "attribute: group"],
                   [f"# {FOLGE_INDEX[:-3]}", ""], keep_trailing_blank=True)
    fm, old_folge_body = read_note(folge_index)
    # 旧い `[diary](…)` の行（英語表記）は、日記グループへの `[日記](…)` に置き換える（位置も一番上へ）
    old_folge_body = [ln for ln in old_folge_body if ln.strip() != f"[diary]({_rel(folge_index.parent, diary_top)})"] \
        if diary_top is not None else old_folge_body
    structure = {os.path.normpath(str(t)) for t, _ in desired}
    if diary_top is not None:
        structure.add(os.path.normpath(str(diary_top)))
    old_folge_body = _sync_link_block(old_folge_body, folge_index.parent, structure, desired)
    fm = _fm_title_attr(fm, FOLGE_INDEX[:-3])
    write_note(folge_index, fm, merge_note_body(old_folge_body, [
        f"# {FOLGE_INDEX[:-3]}", "", *[ln for _, ln in desired],
        CONTEXT_HEAD,
        markdown_link(index_display, index_path, folge_index.parent)]))

    # --- トピック別Index（B案: `1-Index` グループにノートと `1-仏教` を入れる） ---
    notes = load_notes(root)
    topics = scan_topic_notes(root, notes)
    id_index_paths: dict[str, Path] = {}

    def _parent_link_lines(fid: str, base_dir: Path, exclude: Optional[Path] = None) -> list[str]:
        id_index = id_index_paths.get(fid) or find_id_index(root, fid, notes)
        if id_index is not None and id_index != exclude:
            id_index_paths[fid] = id_index
            fm_g, _b = read_note(id_index)
            gd = fm_value(fm_g, "title") or id_index.stem
            return [markdown_link(gd, id_index, base_dir)]
        pid = parent_id(fid)
        if pid is not None and pid in folge:
            return [markdown_link(pid, folge[pid], base_dir)]
        if pid is None:
            return [markdown_link(index_display, index_path, base_dir)]
        return []

    for fid in sorted(topics, key=natural_key):
        tlist = topics[fid]
        gid = find_id_index(root, fid, notes)
        if gid is None:
            gid = unique_note_path(root)
            fm_g = [_time_line(), f"title: {fid}-Index", "attribute: group"]
            write_note(gid, fm_g, [f"# {fid}-Index", ""], keep_trailing_blank=True)
        else:
            fm_g, _b = read_note(gid)
            # 旧表記 `1_Index` を `1-Index` に改名（手書きの別名は残す）
            fm_g = [f"title: {fid}-Index" if ln.strip() == f"title: {fid}_Index" else ln
                    for ln in fm_g]
        id_index_paths[fid] = gid
        # 子トピック順: 親トピック（本文の Context にあるリンクから求めたもの。無い/親が見つからないものは
        # 最上位）を辿って、子は親の直下に 2スペースずつインデントして並べる。順序は表示名の自然順。
        # 手書きで Context の親トピックのリンクを変えれば、次回 regen で反映される。
        tmap = {disp: (path, tp) for disp, path, tp in tlist}
        used_t: set[str] = set()

        def _topic_lines(disp: str, indent: int, children_out: list[str]) -> None:
            path, _tp = tmap[disp]
            used_t.add(disp)
            children_out.append("  " * indent + markdown_link(disp, path, gid.parent))
            for disp_c in sorted((d for d, _p, tp in tlist if tp == disp),
                                 key=natural_key):
                _topic_lines(disp_c, indent + 1, children_out)

        children = []
        if fid in folge:
            children.append(markdown_link(fid, folge[fid], gid.parent))
        for disp in sorted((d for d, _p, tp in tlist if not tp or tp not in tmap),
                           key=natural_key):
            _topic_lines(disp, 0, children)
        # 親が見つからない子孫は階層で拾えないので最後に列挙する
        for disp, _path, _tp in tlist:
            if disp not in used_t:
                children.append(markdown_link(disp, tmap[disp][0], gid.parent))
        p_lines = _parent_link_lines(fid, gid.parent, exclude=gid)
        fm_g = _fm_title_attr(fm_g, f"{fid}-Index")
        write_note(gid, fm_g, merge_note_body(read_note(gid)[1], [f"# {fid}-Index"] + children + [CONTEXT_HEAD] + p_lines))
        # トピックノート自身の Context（既存の `### Context` 以降を置き換え）
        for disp, tpath, tp in tlist:
            fm_t, body_t = read_note(tpath)
            ci = _first_section(body_t)
            if ci is not None:
                body_t = body_t[:ci]
            while body_t and body_t[-1].strip() == "":
                body_t.pop()
            # Context は folgezettel-Index-N ＋（親トピックがあればそのリンク、
            # 無ければトピックIndex 1-Index）を表示する
            folge_link = markdown_link(folge_index_display(fid),
                                       folge_index_path(root, fid), tpath.parent)
            parent_disp = tp if tp in tmap else None
            if parent_disp is not None:
                p_lines = [markdown_link(parent_disp, tmap[parent_disp][0],
                                         tpath.parent), folge_link]
            else:
                head = _parent_link_lines(fid, tpath.parent)
                p_lines = head + [folge_link] if head else [folge_link]
            body_t += [CONTEXT_HEAD] + p_lines
            write_note(tpath, fm_t, body_t)

    # --- 番号専用ノート folgezettel-Index-N ----------------------------------
    write_folge_index_notes(root, folge, id_index_paths)

    # --- スキャンノートの親子リンク -----------------------------------------
    for fid, note_path in folge.items():
        children = sorted(
            (c for c in folge if parent_id(c) == fid), key=natural_key
        )
        fm, old_body = read_note(note_path)
        images = [ln for ln in old_body if re.match(r"^!\[\]\(", ln.strip())]
        intra = [
            markdown_link(c, folge[c], note_path.parent) for c in children
        ]
        inner = [f"# {fid}", "", *images]
        inner += intra + [CONTEXT_HEAD]

        # 専用ノート folgezettel-Index-N の自ID節（#ID）を Context に入れる。
        # 最上位IDはこれだけ、子は親ID の下に並べる（BackLink に出さない）。
        root_fid = _root_id(fid)
        dedicated = markdown_link(folge_index_display(root_fid),
                                  folge_index_path(root, root_fid),
                                  note_path.parent, frag=fid)
        if parent_id(fid) is None:
            p_lines = [dedicated]
        else:
            p_lines = _parent_link_lines(fid, note_path.parent) + [dedicated]
        inner += p_lines

        mapping = {
            e["display"]: readings[e["display"]]
            for e in entries
            if len(e["ids"]) == 1 and e["ids"][0] == fid
        }
        fm = _update_yomi(fm, mapping)
        write_note(note_path, fm, merge_note_body(old_body, inner))

    if do_sync:
        jy.clear_memos()
        import note_format_v2  # 同ディレクトリの SYN 同期エンジン

        note_format_v2.simple_sync(root)
    return True


def _write_new_paper_index(index_path: Path) -> None:
    fm = [
        _time_line(),
        f"title: {DEFAULT_INDEX_TITLE}",
        "attribute: group",
    ]
    body = [
        f"# {DEFAULT_INDEX_TITLE}",
        "",
        f"[{INDEX_WRITE[:-3]}]({INDEX_WRITE})",
        f"[{FOLGE_INDEX[:-3]}]({FOLGE_INDEX})",
    ]
    write_note(index_path, fm, body)


def create_paper_index(root: Path) -> Path:
    """紙PKM Index一式（Index-write・Paper-Zettelkasten-Index・Folgezettel-Index）を作る。

    既に Index があればそれを再利用する。作成/更新後に regen（同期込み）を実行。
    """
    root = Path(root).resolve()
    index_write = root / INDEX_WRITE
    old_index_write = root / OLD_INDEX_WRITE
    if not index_write.is_file() and old_index_write.is_file():
        old_index_write.rename(index_write)
    if not index_write.is_file():
        write_note(
            index_write,
            [_time_line(), f"title: {INDEX_WRITE[:-3]}"],
            [f"# {INDEX_WRITE[:-3]}", ""],
        )
    else:
        fm, body = read_note(index_write)
        if f"title: {INDEX_WRITE[:-3]}" not in fm:
            fm = [f"title: {INDEX_WRITE[:-3]}" if ln.startswith("title:") else ln
                  for ln in fm]
            body = [INDEX_WRITE[:-3] if ln.strip() == OLD_INDEX_WRITE[:-3] else ln
                    for ln in body]
            write_note(index_write, fm, body)
    index_path = migrate_paper_index(root)
    if index_path is None:
        index_path = root / PAPER_INDEX_NAME
        if index_path.exists():
            # 固定名に同名のノートがある（題が Paper-Zettelkasten-Index のときだけ Index として使う。別のノートなら止める）
            fm0, body0 = read_note(index_path)
            if fm_value(fm0, "title") != DEFAULT_INDEX_TITLE:
                raise RuntimeError(f"{PAPER_INDEX_NAME} は紙PKM Index ではない別のノートです。名前を変えてから実行してください")
            write_note(index_path, fm0, body0, keep_trailing_blank=True)
        else:
            _write_new_paper_index(index_path)
    else:
        fm, body = read_note(index_path)
        old_title = fm_value(fm, "title")
        if old_title != DEFAULT_INDEX_TITLE:
            fm = [f"title: {DEFAULT_INDEX_TITLE}" if ln.startswith("title:") else ln
                  for ln in fm]
            body = [DEFAULT_INDEX_TITLE if ln.strip() == "#" + old_title else ln
                    for ln in body]
            write_note(index_path, fm, body)

    # vault 親Index（index.md）に Paper-Zettelkasten-Index へのリンクを足す
    parent_index = root / "index.md"
    if parent_index.is_file():
        fm, body = read_note(parent_index)
        if all(index_path.name not in ln for ln in body):
            # 空行は入れない: 最後のリンク行（内容のある最後の行）の直後に 1 行足す
            link = f"[{DEFAULT_INDEX_TITLE}]({_rel(parent_index.parent, index_path)})"
            last = max((i for i, ln in enumerate(body) if ln.strip()), default=-1)
            body.insert(last + 1, link)
            write_note(parent_index, fm, body)

    regen(root)
    return index_path


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
    existing = scan_folgezettel_notes(root)
    topics = {disp: _p for _ids in scan_topic_notes(root).values()
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
        if not ID_PATTERN.fullmatch(fid):
            errors.append((src, fid, "IDの形式が不正です"))
            continue
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
            print("paper_pkm: 紙PKM Index（Paper-Zettelkasten-Index）がありません", file=sys.stderr)
            return 1
        return 0

    if args.mode == "migrate":
        path = migrate_paper_index(Path(args.root))
        if path is None:
            print("paper_pkm: 紙PKM Index（Paper-Zettelkasten-Index）がありません", file=sys.stderr)
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
