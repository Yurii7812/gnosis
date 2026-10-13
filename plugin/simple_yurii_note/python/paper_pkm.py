#!/usr/bin/env python3
"""紙のPKM（フォルゲゼッテル）連携（simple_yurii_note 用）。

紙に書いたノート（フォルゲゼッテル）をスキャンして vault へ取り込む。

- スキャン画像にフォルゲゼッテルIDを付けて vault 直下へ移す（GUI: folgezettel_scan.py）
- 各スキャンは**タイムスタンプ名ノート**（title=ID、front matter `folgezettel: ID`）。
  画像は `<ID>.<拡張子>` として同じフォルダに置き、ノートが埋め込む。
- `Index-write.md`（手書き）::

      キーワード: フォルゲゼッテル
      バナナ(ばなな): 1,1a10b,3
      オザーク(ドラマ): 2

  の各行から、Paper-Zettelkasten-Index（`Paper-Zettelkasten-Index.md` 固定・`paper_index: true`）の
  キーワードリンクを生成する。旧タイムスタンプ名の Index は regen / create が
  `Paper-Zettelkasten-Index.md` へ改名して移行する（他ノートからのリンクも書き換える）。**複数IDのキーワードはグループノート**
  （`attribute: group`、中に各IDノートへのリンク）、単一IDは直接リンク。
- `Folgezettel-Index.md`: 存在する全IDを自然順で並べた一覧。
- **紙の日記**: `\\F` の GUI で「日記として登録」した画像は、日記が書かれた日付ごとに 1 ノート
  （タイムスタンプ名・`paper_diary: YYYY-MM-DD`・題 `YYYY-MM-DD-曜日2文字`（例 2026-10-13-TU。曜日は日付から自動計算。デジタル日記と同じ形）にまとめる。
  複数ページは同じノートに画像を並べる。ノートの `time:` はスキャンした日時で、日記の日付とは別。
  日記があると Paper-Zettelkasten-Index のキーワードに「日記」が 1 つ自動で入り、
  開くと日付順に日記の一覧（グループ `紙の日記`）になる。デジタル日記（`\\d`）とは題の形が違い、
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

FM_FOLGEZETTEL = "folgezettel"
FM_PAPER_KEYWORD = "paper_keyword"
FM_PAPER_INDEX = "paper_index"
FM_PAPER_DIARY = "paper_diary"          # 紙の日記ノートのfm（値=日記が書かれた日付 YYYY-MM-DD）
DIARY_KEYWORD = "日記"                   # Paper-Zettelkasten-Index のキーワード表示名
DIARY_GROUP_TITLE = "紙の日記"           # そのグループノートの題（デジタル日記のグループ「日記」と区別する）
DIARY_IMAGE_PREFIX = "paper-diary-"
FM_PAPER_TOPIC = "paper_topic"          # トピック別Indexノートのfm（値=起点ID）
FM_PAPER_TOPIC_INDEX = "paper_topic_index"  # 番号別Index（グループ）のfm（値=起点ID）
FM_PAPER_FOLGE_INDEX = "folgezettel_index"  # 番号専用ノート folgezettel-Index-N のfm（値=起点ID）
FM_TOPIC_PARENT = "topic_parent"        # 上位トピック（親トピックノートの title）。手書き管理

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
        ins = list(head_add)
        if p > 0 and out[p - 1].strip():
            ins.insert(0, "")
        if p < len(out) and _is_section_head(out[p]):
            ins.append("")
        out[p:p] = ins

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
                if out and out[-1].strip():
                    out.append("")
                out += [CONTEXT_HEAD, *parent_links]
        else:
            e = next((k for k in range(p + 1, len(out)) if _is_heading(out[k])), len(out))
            last = e
            while last > p + 1 and not out[last - 1].strip():
                last -= 1
            out[last:last] = parent_links
    return out


def write_note(path: Path, fm: list[str], body: list[str]) -> None:
    text = "---\n" + "\n".join(fm) + "\n---\n" + "\n".join(body).rstrip("\n") + "\n"
    path.write_text(text, encoding="utf-8")


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


def scan_folgezettel_notes(root: Path) -> dict[str, Path]:
    """front matter に `folgezettel:` を持つノート → {ID: ノート}。"""
    found: dict[str, Path] = {}
    for p in iter_md(root):
        try:
            fm, _ = read_note(p)
        except OSError:
            continue
        value = fm_value(fm, FM_FOLGEZETTEL)
        if value:
            fid = normalize_id(value)
            if ID_PATTERN.fullmatch(fid):
                found.setdefault(fid, p)
    return found


def _marked_paper_indexes(root: Path) -> list[Path]:
    """`paper_index:` マーカーのあるノート（名前順）。"""
    found: list[Path] = []
    for p in iter_md(root):
        try:
            fm, _ = read_note(p)
        except OSError:
            continue
        if fm_value(fm, FM_PAPER_INDEX):
            found.append(p)
    return sorted(found, key=lambda p: p.name)


def find_paper_index(root: Path) -> Optional[Path]:
    """Paper-Zettelkasten-Index。固定ファイル名 `Paper-Zettelkasten-Index.md`（`paper_index:`
    マーカー付き）を優先し、無ければ旧タイムスタンプ名などのマーカー付きノート
    （複数あれば名前の新しい方）を返す。"""
    fixed = Path(root) / PAPER_INDEX_NAME
    if fixed.is_file():
        try:
            fm, _ = read_note(fixed)
        except OSError:
            fm = []
        if fm_value(fm, FM_PAPER_INDEX):
            return fixed
    found = _marked_paper_indexes(Path(root))
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


def scan_diary_notes(root: Path) -> dict[str, Path]:
    """front matter に `paper_diary: YYYY-MM-DD` を持つ紙の日記ノート → {日付: ノート}。"""
    found: dict[str, Path] = {}
    for p in iter_md(root):
        try:
            fm, _ = read_note(p)
        except OSError:
            continue
        value = fm_value(fm, FM_PAPER_DIARY)
        if value and DATE_RE.fullmatch(value.strip()):
            found.setdefault(value.strip(), p)
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
    Vim 側のデジタル日記の機能は front matter の `paper_diary:` で紙の日記を見分けて無視する。"""
    return diary_label(date)


def _diary_image_name(date: str, page: int, suffix: str) -> str:
    return f"{DIARY_IMAGE_PREFIX}{date.replace('-', '')}-{page}{suffix.lower()}"


_IMAGE_LINE_RE = re.compile(r"^!\[[^\]]*\]\((.+)\)$")


def register_diary_pages(
    root: Path,
    dest: Path,
    pages: list[tuple[Path, str]],
) -> tuple[list[tuple[str, Path]], list[tuple[Path, str, str]]]:
    """スキャン画像を「紙の日記」として登録する。

    pages: [(画像パス, 日記が書かれた日付)]（指定順がページ順）。同じ日付の画像は 1 つの
    ノート（`paper_diary: 日付`・題 `日付-曜日2文字`）に画像を並べる。同じ日付の日記が既にあれば
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
            fm = [_time_line(when), f"title: {diary_title(date)}", f"{FM_PAPER_DIARY}: {date}"]
            body = [f"# {diary_title(date)}"]
        # 画像行を、最初の関係の節の手前（無ければ末尾）に、空行を挟んで足す
        fs = _first_section(body)
        end = fs if fs is not None else len(body)
        while end > 0 and not body[end - 1].strip():
            end -= 1
        new_lines: list[str] = []
        for name in added:
            new_lines += ["", f"![]({name})"]
        body = body[:end] + new_lines + ([""] + body[end:] if fs is not None else [])
        write_note(note_path, fm, body)
        moved[date] = note_path
    return list(moved.items()), errors


def find_group(root: Path, keyword: str) -> Optional[Path]:
    """`paper_keyword:` が keyword のグループノート。"""
    for p in iter_md(root):
        try:
            fm, _ = read_note(p)
        except OSError:
            continue
        if fm_value(fm, FM_PAPER_KEYWORD) == keyword:
            return p
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
    """スキャン1枚をタイムスタンプ名ノートにする（本文は regen が作り直す）。"""
    path = unique_note_path(folder)
    fm = [_time_line(when), f"title: {fid}", f"{FM_FOLGEZETTEL}: {fid}"]
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
) -> Path:
    """トピック別Indexノート（例: title: 1-仏教・画像添付・Parent は regen が直す）。

    parent_topic は親トピックノートの表示名（例: 1-仏教）→ fm `topic_parent:`。
    階層は YAML 管理（あとから手書きでも変えられる）。
    """
    path = unique_note_path(folder)
    display = topic_display(fid, topic)
    fm = [_time_line(when), f"title: {display}",
          f"{FM_PAPER_TOPIC}: {fid}",
          f"{FM_TOPIC_PARENT}: {parent_topic or ''}"]
    if parent_topic:
        fm.append(f"{FM_TOPIC_PARENT}: {parent_topic}")
    body = [f"# {display}", "", f"![]({image_name})"]
    write_note(path, fm, body)
    return path


def scan_topic_notes(root: Path) -> dict[str, list[tuple[str, Path, Optional[str]]]]:
    """`paper_topic:` を持つノート → {起点ID: [(表示名, ノート, 親トピック名), …]}。

    親トピック名（例: 1-仏教）は fm `topic_parent:`。無ければ None（最上位）。
    """
    found: dict[str, list[tuple[str, Path, Optional[str]]]] = {}
    for p in iter_md(root):
        try:
            fm, _ = read_note(p)
        except OSError:
            continue
        fid = fm_value(fm, FM_PAPER_TOPIC)
        if not fid or not ID_PATTERN.fullmatch(fid):
            continue
        title = fm_value(fm, "title") or p.stem
        found.setdefault(fid, []).append((title, p, fm_value(fm, FM_TOPIC_PARENT)))
    for lst in found.values():
        lst.sort(key=lambda t: natural_key(t[0]))
    return found


def find_id_index(root: Path, fid: str) -> Optional[Path]:
    """起点IDの番号別Index（グループ）ノート（`paper_topic_index: <fid>`）。"""
    for p in iter_md(root):
        try:
            fm, _ = read_note(p)
        except OSError:
            continue
        if fm_value(fm, FM_PAPER_TOPIC_INDEX) == fid:
            return p
    return None


def _new_group_note(root: Path, display: str, reading: str) -> Path:
    path = unique_note_path(root)
    fm = [
        _time_line(),
        f"title: {display}",
        f"{FM_PAPER_KEYWORD}: {display}",
        "attribute: group",
    ]
    if reading and reading != display:
        fm = jy.set_yomi_map(fm, {display: reading})
    body = [f"# {display}", ""]
    write_note(path, fm, body)
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
            write_note(path, [_time_line(), f"title: {display}",
                              f"{FM_PAPER_FOLGE_INDEX}: {fid}"], [])
        fm_fi, old_fi_body = read_note(path)
        if fm_value(fm_fi, FM_PAPER_FOLGE_INDEX) is None:
            fm_fi.append(f"{FM_PAPER_FOLGE_INDEX}: {fid}")
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


def regen(root: Path, do_sync: bool = True) -> bool:
    """Index・グループ・Folgezettel-Index・スキャンノートの本文を再生成する。"""
    root = Path(root).resolve()
    index_path = migrate_paper_index(root)  # 旧タイムスタンプ名なら Paper-Zettelkasten-Index.md へ移す
    if index_path is None:
        return False
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
    diaries = scan_diary_notes(root)
    for date, dpath in diaries.items():
        fm_d, body_d = read_note(dpath)
        if fm_value(fm_d, "title") != diary_title(date):
            old_t = fm_value(fm_d, "title") or ""
            fm_d = [f"title: {diary_title(date)}" if re.match(r"^\s*title\s*:", ln) else ln for ln in fm_d]
            body_d = [f"# {diary_title(date)}" if ln.strip() == f"# {old_t}" else ln for ln in body_d]
            write_note(dpath, fm_d, body_d)
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

    folge = scan_folgezettel_notes(root)

    # --- グループ（複数IDのキーワード） -------------------------------------
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
        group_path = find_group(root, display)
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
            # 紙の日記を日付順に並べる（古い日記から）。並びを保つため、既存の日記リンクは作り直す
            diary_targets = {os.path.normpath(str(p)) for p in diaries.values()}
            inner += [markdown_link(diary_title(date), path, group_path.parent)
                      for date, path in sorted(diaries.items())]
            old_group_body_extra = diary_targets
        inner.append(CONTEXT_HEAD)
        inner.append(markdown_link(index_display, index_path, group_path.parent))

        fm, old_group_body = read_note(group_path)
        if old_group_body_extra:
            def _is_diary_link(ln: str, base=group_path.parent) -> bool:
                m = re.search(r"\]\(([^)#]+)", ln)
                return bool(m) and os.path.normpath(str(base / m.group(1))) in old_group_body_extra
            old_group_body = [ln for ln in old_group_body if not _is_diary_link(ln)]
        fm = [ln for ln in fm if not re.match(r"^\s*(title|attribute)\s*:", ln)]
        fm.insert(1 if fm else 0, f"title: {group_title}")
        fm.append("attribute: group")
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
    body = [
        f"# {index_display}",
        "",
        f"[{INDEX_WRITE[:-3]}]({INDEX_WRITE})",
        f"[{FOLGE_INDEX[:-3]}]({FOLGE_INDEX})",
    ]
    if inner:
        # キーワードリンクがあるときだけ Folgezettel-Index との間に空行を置く
        body += ["", *inner]
    write_note(index_path, fm, merge_note_body(old_index_body, body))

    # --- Folgezettel-Index（最上位IDだけ。各リンクは専用ノート folgezettel-Index-N#N） ---
    folge_index = root / FOLGE_INDEX
    inner = [
        markdown_link(fid, folge_index_path(root, fid), folge_index.parent, frag=fid)
        for fid in top_level_ids(folge)
    ]
    if not folge_index.is_file():
        fm_fi = [_time_line(), f"title: {FOLGE_INDEX[:-3]}"]
        write_note(folge_index, fm_fi, [])
    fm, old_folge_body = read_note(folge_index)
    write_note(folge_index, fm, merge_note_body(old_folge_body, [
        f"# {FOLGE_INDEX[:-3]}", "", *inner,
        CONTEXT_HEAD,
        markdown_link(index_display, index_path, folge_index.parent)]))

    # --- トピック別Index（B案: `1-Index` グループにノートと `1-仏教` を入れる） ---
    topics = scan_topic_notes(root)
    id_index_paths: dict[str, Path] = {}

    def _parent_link_lines(fid: str, base_dir: Path, exclude: Optional[Path] = None) -> list[str]:
        id_index = id_index_paths.get(fid) or find_id_index(root, fid)
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

    def _parent_is_group(fid: str) -> bool:
        """_parent_link_lines(fid) の先頭がグループ（1-Index か Paper index）か。"""
        if (id_index_paths.get(fid) or find_id_index(root, fid)) is not None:
            return True
        pid = parent_id(fid)
        return pid is None

    for fid in sorted(topics, key=natural_key):
        tlist = topics[fid]
        gid = find_id_index(root, fid)
        if gid is None:
            gid = unique_note_path(root)
            fm_g = [
                _time_line(),
                f"title: {fid}-Index",
                f"{FM_PAPER_TOPIC_INDEX}: {fid}",
                "attribute: group",
            ]
            write_note(gid, fm_g, [])
        else:
            fm_g, _b = read_note(gid)
            # 旧表記 `1_Index` を `1-Index` に改名（手書きの別名は残す）
            fm_g = [f"title: {fid}-Index" if ln.strip() == f"title: {fid}_Index" else ln
                    for ln in fm_g]
        id_index_paths[fid] = gid
        # 子トピック順: fm topic_parent（無い/親が見つからないものは最上位）を
        # 辿って、子は親の直下に 2スペースずつインデントして並べる。
        # 順序は表示名の自然順。手書き fm `topic_parent:` の変更は次回 regen で反映。
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
        write_note(gid, fm_g, merge_note_body(read_note(gid)[1], [f"# {fid}-Index"] + children + [CONTEXT_HEAD] + p_lines))
        # トピックノート自身の Parent（既存の `### Context` 以降を置き換え）+
        # fm `topic_parent:` は常に持たせる（無ければ追加・手書きで変更可）
        for disp, tpath, tp in tlist:
            fm_t, body_t = read_note(tpath)
            if fm_value(fm_t, FM_TOPIC_PARENT) is None:
                if tp is not None:
                    fm_t.insert(1, f"{FM_TOPIC_PARENT}: {tp}")
                else:
                    key_idx = next((i for i, ln in enumerate(fm_t)
                                    if ln.strip().startswith(f"{FM_PAPER_TOPIC}:")), None)
                    if key_idx is not None:
                        fm_t.insert(key_idx + 1, f"{FM_TOPIC_PARENT}: ")
            ci = _first_section(body_t)
            if ci is not None:
                body_t = body_t[:ci]
            while body_t and body_t[-1].strip() == "":
                body_t.pop()
            # Parent は folgezettel-Index-N ＋（親トピックがあればそのリンク、
            # 無ければトピックIndex 1-Index）を表示する
            folge_link = markdown_link(folge_index_display(fid),
                                       folge_index_path(root, fid), tpath.parent)
            parent_disp = tp if tp in tmap else None
            if parent_disp is not None:
                p_lines = [markdown_link(parent_disp, tmap[parent_disp][0],
                                         tpath.parent), folge_link]
            else:
                head = _parent_link_lines(fid, tpath.parent)
                if head and _parent_is_group(fid):
                    # Parent の並び: グループは上、空行、普通のノートは下（sync の規則と同じ）
                    p_lines = head + ["", folge_link]
                else:
                    p_lines = [folge_link] + head
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
        if images or intra:
            inner.append("")
        inner += intra + [CONTEXT_HEAD]

        # 専用ノート folgezettel-Index-N の自ID節（#ID）を Parent に入れる。
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
        f"{FM_PAPER_INDEX}: true",
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
            # 固定名に同名の別ノートがある: 中身を壊さないよう、マーカーだけ足して Index として使う
            # （題が Paper-Zettelkasten-Index のときだけ。別のノートなら止める）
            fm0, body0 = read_note(index_path)
            if fm_value(fm0, "title") != DEFAULT_INDEX_TITLE:
                raise RuntimeError(f"{PAPER_INDEX_NAME} は紙PKM Index ではない別のノートです。名前を変えてから実行してください")
            write_note(index_path, fm0 + [f"{FM_PAPER_INDEX}: true"], body0)
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
            print("paper_pkm: 紙PKM Index（paper_index: true）がありません", file=sys.stderr)
            return 1
        return 0

    if args.mode == "migrate":
        path = migrate_paper_index(Path(args.root))
        if path is None:
            print("paper_pkm: 紙PKM Index（paper_index: true）がありません", file=sys.stderr)
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
