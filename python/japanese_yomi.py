#!/usr/bin/env python3
"""日本語のよみ（読み）ユーティリティ（Gnosis 用）。

- よみ（表示名 → よみ）の保存。2026-10-23〜 vault の ``.gnosis/yomi/<2桁16進>.jsonl``（ノートのファイル名のハッシュで
  最大 256 個に分ける JSON Lines。1 行 1 件 ``{"n": ノート, "k": 表示名, "y": よみ}``）。ノート本体の YAML には書かない。
  読むときは JSON を先に見て、古いノートの front matter の ``yomi:`` マップも読む（同期が JSON へ移す）
- pykakasi による かな化（未導入時は入力をそのまま使うフォールバック）
- 五十音順のソートキー（ローマ字は末尾）

古い ``yomi:`` の形（今は読むだけ）::

    yomi:
      "筋トレ": "きんとれ"

キーはリンクの表示名、値はよみ。行は JSON のダブルクォート文字列で保存する
（YAML のダブルクォートスカラーとしても読める）。pykakasi は遅延 import なので
このモジュールは未導入でも import できる。
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

# 五十音の並び。濁点・半濁点は基本区別せず清音と同じランクにする
# （同ランクは安定ソートで元の順を保つ）。小書きは対応する清音の直後。
# 促音 っ は と の直後。
_GOJUON = (
    "あぁいぃうぅえぇおぉ"
    "かきくけこ"
    "さしすせそ"
    "たちつてとっ"
    "なにぬねの"
    "はひふへほ"
    "まみむめも"
    "やゃゆゅよょ"
    "らりるれろ"
    "わゎをん"
)
_RANK = {ch: i for i, ch in enumerate(_GOJUON)}
# 濁音・半濁音は清音と同じランクに寄せる（が→か・ぱ→は・ゔ→う …）。
_DAKUTEN_BASE = {
    "が": "か", "ぎ": "き", "ぐ": "く", "げ": "け", "ご": "こ",
    "ざ": "さ", "じ": "し", "ず": "す", "ぜ": "せ", "ぞ": "そ",
    "だ": "た", "ぢ": "ち", "づ": "つ", "で": "て", "ど": "と",
    "ば": "は", "び": "ひ", "ぶ": "ふ", "べ": "へ", "ぼ": "ほ",
    "ぱ": "は", "ぴ": "ひ", "ぷ": "ふ", "ぺ": "へ", "ぽ": "ほ",
    "ゔ": "う",
}


# 並べ替えで無視する文字（長音・中黒・空白・句読点など）
_IGNORE = set("ー・･ 　\t〜～-－=~.，,、。!！?？「」『』（）()［］[]")
_MIX_SEP = "\uffff"


def _rank_of(ch: str):
    """かな 1 文字の五十音ランク（濁点・半濁点は清音に寄せる）。無ければ None。"""
    return _RANK.get(_DAKUTEN_BASE.get(ch, ch))

_LINK_RE = re.compile(r"\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)")
_YOMI_HEAD_RE = re.compile(r"^yomi\s*:\s*$")
_YOMI_PAIR_RE = re.compile(r'^\s+("(?:[^"\\]|\\.)*")\s*:\s*("(?:[^"\\]|\\.)*")\s*$')
# 並べ替えの対象は「リンクだけの行」（`— 注記` 付きも可）。文章に埋もれた
# リンク（例: 「〜は [これ](x.md) を参照」）は行ごと動かさない。
_LINK_LINE_RE = re.compile(r"^\s*\[(?:\\.|[^\]\\])*\]\([^)]+\)\s*(?:—\s*\S+)?\s*$")
# ここから後ろ（### ParentBranch / ### ChildBranch / ### Context / ### Related / ### BackLink など）は本文ではない。
_SECTION_HEAD_RE = re.compile(
    r"^(?:###\s*(?:ParentBranch|ChildBranch|Parent|Context|Group|Related|BackLink)|(?:ChildBranch|Related|BackLink):)\s*$")
# 本文の上の先頭のブロック。中のリンクは並べ替えない（追加した順のまま）
_TOP_BLOCK_HEADS = ("ParentBranch:", "BranchGroup:", "ThisNoteGroup:", "Group:", "Context:")

# --- pykakasi（遅延 import） ------------------------------------------------

_pykakasi = None
_pykakasi_checked = False


def _load_pykakasi():
    global _pykakasi, _pykakasi_checked
    if not _pykakasi_checked:
        _pykakasi_checked = True
        try:
            import pykakasi  # type: ignore

            _pykakasi = pykakasi.kakasi()
        except Exception:
            _pykakasi = None
    return _pykakasi


def has_pykakasi() -> bool:
    return _load_pykakasi() is not None


def pykakasi_installed() -> bool:
    """pykakasi が import 可能かだけを確認する（import はしない＝速い）。

    `\\S` は全よみが登録済みなら pykakasi を一度も使わない。警告のためだけに
    import して 0.6 秒級のロードを毎回払わないための軽い判定。
    """
    from importlib.util import find_spec

    try:
        return find_spec("pykakasi") is not None
    except (ImportError, ValueError):
        return False


# テスト用に読み関数を差し替える（None で既定へ戻す）
_READER = None


def set_reader(fn) -> None:
    global _READER
    _READER = fn


def reset_reader() -> None:
    global _READER
    _READER = None


# 変換不要（変換しても同じ）文字だけの文字列。かな・英数・記号。
# 登録済みの `yomi:` はひらがななので、\S の再ソートで pykakasi を
# 1 万回呼び直さないための近道（1 回の変換は速いが 1 万回で数秒になる）。
_NO_CONVERT_RE = re.compile(
    r"^[ぁ-ゖァ-ヺー・"
    r"A-Za-z0-9０-９"
    r"!\"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~ \t\r\n]*$"
)


def reading_for(text: str) -> str:
    """text のよみを返す。pykakasi 未導入なら text をそのまま返す。"""
    if _READER is not None:
        return _READER(text)
    if _NO_CONVERT_RE.match(text):
        return text
    kks = _load_pykakasi()
    if kks is None:
        return text
    try:
        return "".join(item.get("hira", "") for item in kks.convert(text))
    except Exception:
        return text


def kata2hira(text: str) -> str:
    out = []
    for ch in text:
        code = ord(ch)
        if 0x30A1 <= code <= 0x30F6:
            out.append(chr(code - 0x60))
        else:
            out.append(ch)
    return "".join(out)


def reading_key(text: str) -> tuple:
    """五十音順のソートキー。かな語 → (0, ...)、ローマ字等 → (1, ...)。

    英字で始まるよみ（例: "simple-yurii-note そうさがいど"）は、かなを含んで
    いても英字の側（末尾グループ）に入れる。かなで始まって途中に英字を含む
    もの（例: "かみのPKMのすきゃん"）はかなの順に置く。
    """
    hira = kata2hira(reading_for(text))
    ranks: list[str] = []
    others: list[str] = []
    first_kind: str | None = None
    for ch in hira:
        if ch in _IGNORE or ch.isspace():
            continue
        r = _rank_of(ch)
        if r is not None:
            if first_kind is None:
                first_kind = "kana"
            ranks.append(chr(0x100 + r))
        else:
            if first_kind is None:
                first_kind = "other"
            others.append(ch.lower() if ch.isascii() else ch)
    if first_kind == "other":
        tail = _MIX_SEP + "".join(ranks) if ranks else ""
        return (1, "".join(others) + tail, "")
    if first_kind == "kana":
        if not others:
            return (0, "".join(ranks), "")
        return (0, "".join(ranks) + _MIX_SEP + "".join(others), "")
    return (2, "", text.casefold())


# --- よみの保存（vault の .gnosis/yomi/ の JSON Lines） ------------------------------------
# 100 万ノートでも、ファイルは最大 256 個。書くのは読みが要る表示名（漢字を含むもの）だけ。
# 1 行 1 件で、ノートのファイル名の順に書くので、git で同期しても行単位でマージできる。

import hashlib
import tempfile

SHARDS_NOTE = "256 個に分ける（ノートのファイル名の blake2b の先頭 1 バイト）"
_KANJI = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff々〇]")


def needs_reading(name: str) -> bool:
    """よみが要る表示名か。漢字を含むときだけ（ひらがな・カタカナ・英数字・記号だけの名前は、そのまま並べ替えに使える）。"""
    return bool(_KANJI.search(name or ""))


_ROOT_MEMO: dict[str, "Path | None"] = {}
_STORES: dict[str, "YomiStore"] = {}


def find_root(path) -> "Path | None":
    """ノート path の vault（.gnosis があるいちばん近い上のフォルダ。無ければ index.md があるいちばん近い上のフォルダ）。"""
    p = Path(os.path.abspath(str(path)))
    d = p if p.is_dir() else p.parent
    key = str(d)
    if key in _ROOT_MEMO:
        return _ROOT_MEMO[key]
    found = None
    for q in [d, *d.parents]:
        if (q / ".gnosis").is_dir():
            found = q
            break
    if found is None:
        for q in [d, *d.parents]:
            if (q / "index.md").is_file():
                found = q
                break
    _ROOT_MEMO[key] = found
    return found


def _shard_of(note_id: str) -> str:
    return hashlib.blake2b(note_id.encode("utf-8"), digest_size=1).hexdigest()


class YomiStore:
    def __init__(self, root: Path):
        self.root = Path(root)
        self.dir = self.root / ".gnosis" / "yomi"
        self._data: dict[str, dict[str, dict[str, str]]] = {}   # 殻 → {ノート: {表示名: よみ}}

    def note_id(self, path) -> str:
        try:
            return Path(os.path.abspath(str(path))).relative_to(self.root).as_posix()
        except ValueError:
            return ""

    def _file(self, sh: str) -> Path:
        return self.dir / f"{sh}.jsonl"

    def _load(self, sh: str) -> dict[str, dict[str, str]]:
        if sh in self._data:
            return self._data[sh]
        out: dict[str, dict[str, str]] = {}
        try:
            for ln in self._file(sh).read_text(encoding="utf-8").split("\n"):
                if not ln.strip():
                    continue
                try:
                    d = json.loads(ln)
                    out.setdefault(d["n"], {})[d["k"]] = d["y"]
                except Exception:
                    continue
        except OSError:
            pass
        self._data[sh] = out
        return out

    def _save(self, sh: str) -> None:
        data = self._data.get(sh, {})
        f = self._file(sh)
        rows = [json.dumps({"n": n, "k": k, "y": y}, ensure_ascii=False, separators=(",", ":"))
                for n in sorted(data) for k, y in data[n].items()]
        if not rows:
            try:
                f.unlink()
            except OSError:
                pass
            return
        self.dir.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=str(self.dir), prefix=".tmp-", suffix=".jsonl")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write("\n".join(rows) + "\n")
            os.replace(tmp, f)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

    def get(self, note_id: str, name: str) -> str:
        return self._load(_shard_of(note_id)).get(note_id, {}).get(name, "")

    def names(self, note_id: str) -> list[str]:
        return list(self._load(_shard_of(note_id)).get(note_id, {}))

    def set(self, note_id: str, name: str, reading: str) -> bool:
        sh = _shard_of(note_id)
        data = self._load(sh)
        cur = data.get(note_id, {})
        if reading:
            if cur.get(name) == reading:
                return False
            data.setdefault(note_id, {})[name] = reading
        else:
            if name not in cur:
                return False
            del cur[name]
            if not cur:
                data.pop(note_id, None)
        self._save(sh)
        return True

    def import_map(self, note_id: str, mapping: dict[str, str]) -> bool:
        """YAML から移すとき: すでに JSON にある名前は上書きしない。"""
        sh = _shard_of(note_id)
        data = self._load(sh)
        changed = False
        for k, y in mapping.items():
            if y and k not in data.get(note_id, {}):
                data.setdefault(note_id, {})[k] = y
                changed = True
        if changed:
            self._save(sh)
        return changed

    def prune(self, used: set[str], existing: "set[str] | None" = None) -> int:
        """使われていない表示名のよみ（と、ノートが無くなったものの分）を消す。消した件数。"""
        n = 0
        try:
            files = sorted(self.dir.glob("*.jsonl"))
        except OSError:
            return 0
        for f in files:
            sh = f.stem
            data = self._load(sh)
            changed = False
            for note in list(data):
                if existing is not None and note not in existing:
                    n += len(data.pop(note))
                    changed = True
                    continue
                for k in [k for k in data[note] if k not in used]:
                    del data[note][k]
                    n += 1
                    changed = True
                if not data[note]:
                    del data[note]
            if changed:
                self._save(sh)
        return n

    def all_count(self) -> int:
        return sum(len(v) for sh in (f.stem for f in self.dir.glob("*.jsonl")) for v in self._load(sh).values())


def store_for(path, create: bool = False) -> "YomiStore | None":
    root = find_root(path)
    if root is None:
        return None
    key = str(root)
    if key not in _STORES:
        _STORES[key] = YomiStore(root)
    return _STORES[key]


# --- yomi マップ（古い形: front matter） -------------------------------------------


def parse_yomi_map(fm: list[str]) -> dict[str, str]:
    """front matter 行から ``yomi:`` マップを取り出す（順序保持）。"""
    out: dict[str, str] = {}
    in_block = False
    for ln in fm:
        if not in_block:
            if _YOMI_HEAD_RE.match(ln):
                in_block = True
            continue
        m = _YOMI_PAIR_RE.match(ln)
        if m:
            try:
                out[json.loads(m.group(1))] = json.loads(m.group(2))
            except Exception:
                pass
            continue
        if ln.strip() == "":
            continue
        if not ln[:1].isspace():
            in_block = False
    return out


def set_yomi_map(fm: list[str], mapping: dict[str, str]) -> list[str]:
    """front matter 行の ``yomi:`` ブロックを mapping で置き換える。

    mapping が空ならブロックを削除する。time 行（無ければ title 行）の直後に置く。
    """
    lines = list(fm)
    start = None
    for i, ln in enumerate(lines):
        if _YOMI_HEAD_RE.match(ln):
            start = i
            break
    if start is not None:
        end = start + 1
        while end < len(lines) and (lines[end][:1].isspace() or lines[end].strip() == ""):
            end += 1
        del lines[start:end]
    if mapping:
        block = ["yomi:"] + [
            "  %s: %s"
            % (json.dumps(k, ensure_ascii=False), json.dumps(v, ensure_ascii=False))
            for k, v in mapping.items()
        ]
        at = None
        for i, ln in enumerate(lines):
            if re.match(r"^\s*(title|time)\s*:", ln):
                at = i + 1
                if ln.lstrip().startswith("title"):
                    break
        if at is None:
            at = max(1, len(lines) - 1)
        at = min(at, len(lines))
        lines[at:at] = block
    return lines


def split_front_matter(lines: list[str]) -> tuple[list[str], list[str]]:
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return lines[: i + 1], lines[i + 1:]
    return [], list(lines)


# 1 プロセス（= 1 回の sort/set 実行）内で front matter を 1 回だけ読む。
# \S は「未登録よみの書き込み」と「ソート」で同じ 1 万ノートを 2 周参照する。
# 読み直しをやめると 1 万行 Index で数秒変わる。書き込んだらメモも更新する。
_NOTE_MEMO: dict[str, "dict | None"] = {}
_RESOLVE_MEMO: dict[tuple[str, str], "Path | None"] = {}


def clear_memos() -> None:
    _NOTE_MEMO.clear()
    _RESOLVE_MEMO.clear()
    _ROOT_MEMO.clear()
    _STORES.clear()


def _note_entry(path) -> "dict | None":
    p = Path(path)
    key = os.path.abspath(str(p))
    if key in _NOTE_MEMO:
        return _NOTE_MEMO[key]
    try:
        text = p.read_text(encoding="utf-8")
    except OSError:
        _NOTE_MEMO[key] = None
        return None
    lines = text.split("\n")
    if text.endswith("\n") and lines and lines[-1] == "":
        lines.pop()
    fm, rest = split_front_matter(lines)
    ent = {"path": p, "fm": fm, "rest": rest, "map": parse_yomi_map(fm)}
    _NOTE_MEMO[key] = ent
    return ent


def get_yomi(path, name: str) -> str:
    """表示名 name のよみ。vault の JSON を先に見て、無ければノートの古い front matter の yomi: マップを見る。"""
    st = store_for(path)
    if st is not None:
        nid = st.note_id(path)
        if nid:
            got = st.get(nid, name)
            if got:
                return got
    ent = _note_entry(path)
    return ent["map"].get(name, "") if ent else ""


def list_yomi_names(path) -> list[str]:
    """ノートに登録されたよみの表示名を登録順に返す（JSON、続けて古い front matter の分）。"""
    out: list[str] = []
    st = store_for(path)
    if st is not None:
        nid = st.note_id(path)
        if nid:
            out = st.names(nid)
    ent = _note_entry(path)
    if ent:
        out += [k for k in ent["map"] if k not in out]
    return out


def set_yomi(path, name: str, reading: str) -> bool:
    """表示名 name のよみを登録（reading 空で削除）。変更したら True。

    vault があれば JSON に書き、ノートに古い front matter の yomi: が残っていればその名前の分を外す。
    vault が見つからないときだけ、ノートの front matter に書く（古い形）。
    """
    st = store_for(path)
    nid = st.note_id(path) if st is not None else ""
    if st is not None and nid:
        changed = st.set(nid, name, reading)
        ent = _note_entry(path)
        if ent is not None and name in ent["map"]:
            mapping = dict(ent["map"])
            del mapping[name]
            new_fm = set_yomi_map(ent["fm"], mapping)
            ent["path"].write_text("\n".join(new_fm + ent["rest"]) + "\n", encoding="utf-8")
            ent["fm"] = new_fm
            ent["map"] = mapping
            changed = True
        return changed
    ent = _note_entry(path)
    if ent is None:
        return False
    p = ent["path"]
    fm = ent["fm"] or ["---", "---"]
    mapping = dict(ent["map"])
    if reading:
        if mapping.get(name) == reading:
            return False
        mapping[name] = reading
    else:
        if name not in mapping:
            return False
        del mapping[name]
    new_fm = set_yomi_map(fm, mapping)
    p.write_text("\n".join(new_fm + ent["rest"]) + "\n", encoding="utf-8")
    ent["fm"] = new_fm
    ent["map"] = mapping
    return True


# --- ソート -----------------------------------------------------------------


def display_name(line: str) -> str:
    """行の最初の Markdown リンクの表示名。リンクが無ければ行全体。"""
    m = _LINK_RE.search(line)
    if m:
        return m.group(1)
    return line.strip()


def link_target(line: str) -> str:
    m = _LINK_RE.search(line)
    return m.group(2) if m else ""


def resolve_note(base_dir, target: str) -> Path | None:
    t = (target or "").strip()
    if t.startswith("file://"):
        t = t[7:]
    t = t.split("#", 1)[0]
    if not t.lower().endswith(".md"):
        return None
    key = (os.path.abspath(str(base_dir)), t)
    if key in _RESOLVE_MEMO:
        return _RESOLVE_MEMO[key]
    p = Path(t) if os.path.isabs(t) else Path(base_dir) / t
    _RESOLVE_MEMO[key] = p
    return p


def line_reading(line: str, base_dir) -> str:
    """行のよみ。リンク行は表示名（対象ノートに yomi があれば優先）。"""
    m = _LINK_RE.search(line)
    if not m:
        return line.strip()
    disp = m.group(1)
    note = resolve_note(base_dir, m.group(2))
    if note is not None:
        y = get_yomi(note, disp)
        if y:
            return y
    return disp


_FENCE_RE = re.compile(r"^\s{0,3}(```|~~~)")


def sort_lines(lines: list[str], base_dir, extra_key_fn=None) -> list[str]:
    """リンクだけの行（＋ extra_key_fn がキーを返す行）をよみ順に安定ソートする。

    対象外の行は位置ごと動かさない（散文や見出しは元の位置に残る）。
    `### Parent` / `### Related` / `### BackLink` の見出しが来たらそこで打ち
    切る（グループの Parent や BackLink のリンクは動かさない。ソート後に
    本文と入れ替わってしまうのを防ぐ）。文章に埋もれたリンクも動かさない。
    extra_key_fn は行 → ソートキー tuple（対象外は None）。紙PKM の
    Index-write のキーワード行（`バナナ(ばなな): 1,2`）を並べるのに使う。
    """
    slots: list[int] = []
    in_fence = False
    in_ctx = False  # `Context:` ブロックのリンクは、追加した順のまま並べ替えない
    for i, ln in enumerate(lines):
        if _FENCE_RE.match(ln):
            in_fence = not in_fence
            continue
        if in_fence:
            continue  # コードブロックの中の文字列は対象にしない
        if ln.strip() in _TOP_BLOCK_HEADS:
            in_ctx = True
            continue
        if in_ctx and _LINK_LINE_RE.match(ln):
            continue
        in_ctx = False
        if _SECTION_HEAD_RE.match(ln.strip()):
            break
        if _LINK_LINE_RE.match(ln):
            slots.append(i)
        elif extra_key_fn is not None and extra_key_fn(ln) is not None:
            slots.append(i)
    keyed = []
    for i in slots:
        if _LINK_RE.search(lines[i]):
            key = reading_key(line_reading(lines[i], base_dir))
        else:
            key = extra_key_fn(lines[i])
        keyed.append((key, i, lines[i]))
    keyed.sort(key=lambda t: (t[0], t[1]))
    out = list(lines)
    for slot, (_k, _i, ln) in zip(slots, keyed):
        out[slot] = ln
    return out


# グループの見出し（A-Z は旧版が生成した見出しの除去にも使う）。
# Gnosis が作る行なので、付け直すときはこの形の行を全部外してから入れ直す。
KANA_HEAD_RE = re.compile(r"^(?:[ぁ-ゖ]|[A-Z]|英字|0-9|その他)$")
KANA_HEAD_MIN = 30
_SMALL_KANA = str.maketrans("ぁぃぅぇぉっゃゅょゎゕゖ", "あいうえおつやゆよわかけ")


def kana_initial(reading: str) -> str:
    """よみの頭文字の見出し名。かなは清音の大きい字（が→か・ゃ→や）、英字は大文字、数字は 0-9、ほかは その他。"""
    import unicodedata
    for ch in kata2hira(reading):
        if ch in _IGNORE or ch.isspace():
            continue
        base = unicodedata.normalize("NFD", ch)[0].translate(_SMALL_KANA)
        if "ぁ" <= base <= "ゖ":
            return base
        if base.isascii() and base.isalpha():
            return base.upper()
        if base.isdigit():
            return "0-9"
        return "その他"
    return "その他"


def strip_kana_heads(lines: list[str]) -> list[str]:
    """kana_heads が入れた見出しの行を外す（コードブロックの中は触らない）。"""
    out: list[str] = []
    in_fence = False
    for ln in lines:
        if _FENCE_RE.match(ln):
            in_fence = not in_fence
        if not in_fence and KANA_HEAD_RE.match(ln.strip()):
            continue
        out.append(ln)
    return out


def kana_heads(lines: list[str], base_dir, minimum: int = KANA_HEAD_MIN) -> list[str]:
    """本文のリンクが minimum 本以上なら五十音の行見出し、その行が minimum を超えれば字ごとに分ける。

    前に入れた見出しはいったん全部外す（本数が減れば見出しは無くなる）。対象は sort_lines と同じ
    （本文の上のブロック・コードブロック・ChildBranch: などの節より後ろは見ない）。
    """
    lines = strip_kana_heads(lines)
    slots: list[int] = []
    in_fence = False
    in_ctx = False
    for i, ln in enumerate(lines):
        if _FENCE_RE.match(ln):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if ln.strip() in _TOP_BLOCK_HEADS:
            in_ctx = True
            continue
        if in_ctx and _LINK_LINE_RE.match(ln):
            continue
        in_ctx = False
        if _SECTION_HEAD_RE.match(ln.strip()):
            break
        if _LINK_LINE_RE.match(ln):
            slots.append(i)
    if len(slots) < minimum:
        return lines
    rows = ["あいうえお", "かきくけこ", "さしすせそ", "たちつてと", "なにぬねの",
            "はひふへほ", "まみむめも", "やゆよ", "らりるれろ", "わゐゑをん"]
    row_of = {ch: row[0] for row in rows for ch in row}
    initials = {i: kana_initial(line_reading(lines[i], base_dir)) for i in slots}
    counts: dict[str, int] = {}
    for ini in initials.values():
        row = row_of.get(ini, ini)
        counts[row] = counts.get(row, 0) + 1
    heads: dict[int, str] = {}
    prev = None
    for i in slots:
        ini = initials[i]
        row = row_of.get(ini, ini)
        ini = ini if counts[row] > minimum else row
        if ini.isascii() and ini.isalpha():
            ini = "英字"
        if ini != prev:
            heads[i] = ini
            prev = ini
    out: list[str] = []
    for i, ln in enumerate(lines):
        if i in heads:
            out.append(heads[i])
        out.append(ln)
    return out


def persist_readings(lines: list[str], base_dir) -> int:
    """リンクだけの行の表示名のよみが未登録なら、pykakasi で作って yomi: に書き込む。

    `\\S` のソート時に呼ぶ。対象は `sort_lines` と揃える（`### Parent` 以降と
    文章に埋もれたリンクは書かない）。ローマ字のまま等でよみが変わらない
    表示名は書かない。書いた件数を返す。
    """
    count = 0
    seen: set[tuple[str, str]] = set()
    in_fence = False
    in_ctx = False
    for line in lines:
        if _FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if line.strip() in _TOP_BLOCK_HEADS:
            in_ctx = True
            continue
        if in_ctx and _LINK_LINE_RE.match(line):
            continue
        in_ctx = False
        if _SECTION_HEAD_RE.match(line.strip()):
            break
        if not _LINK_LINE_RE.match(line):
            continue
        m = _LINK_RE.search(line)
        disp = m.group(1)
        note = resolve_note(base_dir, m.group(2))
        if note is None or not note.is_file():
            continue
        key = (str(note), disp)
        if key in seen:
            continue
        seen.add(key)
        if get_yomi(note, disp):
            continue
        reading = reading_for(disp)
        if not reading or reading == disp:
            continue
        if not any(_rank_of(ch) is not None for ch in kata2hira(reading)):
            continue
        if set_yomi(note, disp, reading):
            count += 1
    return count
