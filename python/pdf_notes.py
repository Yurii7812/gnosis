#!/usr/bin/env python3
"""PDF の注釈・選択テキスト・ページリンク（LR08）。読み取り専用（`digest --write` が新しいノートを作るときだけ書く）。

- `annotations`: PDF の注釈（ハイライト・下線・取り消し線・波線・メモ・自由テキスト）を、ページ・種類・コメント・**ハイライトされた文字**つきで取り出す。
  ハイライトの文字は、注釈の `QuadPoints` の範囲にある単語を `pdftotext -bbox` の座標から拾う（PDF の描画命令は解釈しない）。
  解析は自前の最小限の読み取り（オブジェクト・圧縮オブジェクトストリーム・ページ木・注釈の辞書）。壊れた・暗号化された PDF は、そう伝えて何もしない。
- `digest`: 注釈から読書メモの草稿を作る。各項目に `[p.12](ファイル.pdf#page=12)` のページリンクを付ける。`--write` は新しいノートだけ（上書きしない）。
- `check`: ノートの中の「引用 + ページリンク」（`> 引用 [p.12](x.pdf#page=12)` や `…(x.pdf#page=12)` と同じ行の引用）が、**本当にそのページに書かれているか**を確かめる。
  文字の揺れ（空白・改行・全角半角）は無視して比べる。見つからなければ「ずれている」と報告し、近いページがあればそれも示す。
- `page`: 指定ページの本文テキスト。

外部ツール: poppler の `pdftotext` / `pdfinfo`（引数の配列で呼ぶ。シェルは通さない）。無ければ、そう伝える。PDF は vault の中の 50 MB までのものだけ。

CLI（JSON。--md なら Markdown）:
  pdf_notes.py ROOT annotations FILE.pdf
  pdf_notes.py ROOT digest FILE.pdf [--write NEWFILE]
  pdf_notes.py ROOT check [NOTE]                     vault 全体（または 1 つのノート）の引用とページリンクの検査
  pdf_notes.py ROOT page FILE.pdf N
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tasks as tk  # noqa: E402

MAX_PDF = 50 * 1024 * 1024
TIMEOUT = 60
KINDS = {"Highlight": "ハイライト", "Underline": "下線", "StrikeOut": "取り消し線", "Squiggly": "波線", "Text": "メモ", "FreeText": "自由テキスト"}
TEXT_KINDS = ("Highlight", "Underline", "StrikeOut", "Squiggly")


class PdfError(ValueError):
    pass


# ---------- PDF の最小限の読み取り ----------
OBJ = re.compile(rb"(?<![0-9])(\d+)\s+(\d+)\s+obj\b")


def _objects(data: bytes) -> dict[int, bytes]:
    """オブジェクト番号 → 辞書（とストリームがあればその展開後の本文）の生バイト。圧縮オブジェクトストリームの中身も展開して加える。"""
    objs: dict[int, bytes] = {}
    pos = 0
    pending_streams: list[tuple[int, bytes]] = []
    for m in OBJ.finditer(data):
        if m.start() < pos:
            continue
        end = data.find(b"endobj", m.end())
        if end < 0:
            break
        body = data[m.end():end]
        pos = end
        num = int(m.group(1))
        sm = re.search(rb"stream\r?\n", body)
        head = body if not sm else body[:sm.start()]
        objs[num] = head
        if sm and re.search(rb"/FlateDecode", head):
            raw = body[sm.end():]
            raw = re.sub(rb"\r?\nendstream\s*$", b"", raw)
            try:
                dec = zlib.decompress(raw)
            except zlib.error:
                dec = b""
            if re.search(rb"/Type\s*/ObjStm", head):
                pending_streams.append((num, dec))
                m_n, m_first = re.search(rb"/N\s+(\d+)", head), re.search(rb"/First\s+(\d+)", head)
                if m_n and m_first:
                    n, first = int(m_n.group(1)), int(m_first.group(1))
                    nums = [int(x) for x in re.findall(rb"\d+", dec[:first])][: 2 * n]
                    pairs = list(zip(nums[0::2], nums[1::2]))
                    for i, (onum, off) in enumerate(pairs):
                        nxt = pairs[i + 1][1] if i + 1 < len(pairs) else len(dec) - first
                        objs.setdefault(onum, dec[first + off:first + nxt])
    return objs


def _ref(b: bytes, key: bytes) -> int | None:
    m = re.search(rb"/" + key + rb"\s+(\d+)\s+\d+\s+R", b)
    return int(m.group(1)) if m else None


def _refs(b: bytes) -> list[int]:
    return [int(x) for x in re.findall(rb"(\d+)\s+\d+\s+R", b)]


def _array(b: bytes, key: bytes, objs: dict[int, bytes]) -> bytes:
    """/Key [ ... ] の中身。/Key 12 0 R（間接）なら、そのオブジェクトの中身。"""
    m = re.search(rb"/" + key + rb"\s*\[([^\]]*)\]", b)
    if m:
        return m.group(1)
    r = _ref(b, key)
    if r is not None and r in objs:
        m2 = re.search(rb"\[([^\]]*)\]", objs[r])
        return m2.group(1) if m2 else b""
    return b""


def _pages(objs: dict[int, bytes]) -> list[int]:
    root = None
    for b in objs.values():
        m = re.search(rb"/Root\s+(\d+)\s+\d+\s+R", b)
        if m:
            root = int(m.group(1)); break
    if root is None:                                         # xref ストリームの辞書が圧縮されていない場合の探索に失敗したとき: Catalog を探す
        root = next((n for n, b in objs.items() if re.search(rb"/Type\s*/Catalog", b)), None)
    pages_root = _ref(objs.get(root, b""), b"Pages") if root is not None else None
    if pages_root is None:
        pages_root = next((n for n, b in objs.items() if re.search(rb"/Type\s*/Pages", b) and not re.search(rb"/Parent", b)), None)
    out: list[int] = []
    seen: set[int] = set()

    def walk(n: int):
        if n in seen or n not in objs:
            return
        seen.add(n)
        b = objs[n]
        if re.search(rb"/Kids", b):
            for k in _refs(_array(b, b"Kids", objs)):
                walk(k)
        else:
            out.append(n)
    if pages_root is not None:
        walk(pages_root)
    return out


def _inherited(objs: dict[int, bytes], n: int, key: bytes) -> bytes | None:
    seen = set()
    while n is not None and n in objs and n not in seen:
        seen.add(n)
        m = re.search(rb"/" + key + rb"\s*\[([^\]]*)\]", objs[n])
        if m:
            return m.group(1)
        n = _ref(objs[n], b"Parent")
    return None


def _nums(b: bytes | None) -> list[float]:
    return [float(x) for x in re.findall(rb"-?\d+(?:\.\d+)?", b or b"")]


def _read_string(b: bytes, key: bytes) -> str:
    """/Key (…) または /Key <…> の文字列を読む。UTF-16BE（BOM つき）か、そうでなければ Latin-1 として。"""
    m = re.search(rb"/" + key + rb"\s*([(<])", b)
    if not m:
        return ""
    i = m.end() - 1
    if b[i:i + 1] == b"<":
        j = b.find(b">", i)
        hx = re.sub(rb"\s+", b"", b[i + 1:j])
        if len(hx) % 2:
            hx += b"0"
        raw = bytes.fromhex(hx.decode("ascii", "ignore")) if re.fullmatch(rb"[0-9A-Fa-f]*", hx) else b""
    else:
        depth, j, buf = 0, i, bytearray()
        while j < len(b):
            c = b[j:j + 1]
            if c == b"\\":
                nx = b[j + 1:j + 2]
                esc = {b"n": b"\n", b"r": b"\r", b"t": b"\t", b"b": b"\b", b"f": b"\f", b"(": b"(", b")": b")", b"\\": b"\\"}
                if nx in esc:
                    buf += esc[nx]; j += 2; continue
                om = re.match(rb"[0-7]{1,3}", b[j + 1:j + 4])
                if om:
                    buf.append(int(om.group(0), 8) & 255); j += 1 + len(om.group(0)); continue
                j += 2; continue
            if c == b"(":
                depth += 1
                if depth > 1:
                    buf += c
            elif c == b")":
                depth -= 1
                if depth == 0:
                    break
                buf += c
            else:
                buf += c
            j += 1
        raw = bytes(buf)
    if raw[:2] == b"\xfe\xff":
        return raw[2:].decode("utf-16-be", errors="replace")
    if raw[:2] == b"\xff\xfe":
        return raw[2:].decode("utf-16-le", errors="replace")
    return raw.decode("utf-8") if _is_utf8(raw) else raw.decode("latin-1")


def _is_utf8(raw: bytes) -> bool:
    try:
        raw.decode("utf-8")
        return any(x > 127 for x in raw)
    except UnicodeDecodeError:
        return False


def _tool(name: str) -> str:
    exe = shutil.which(name)
    if not exe:
        raise PdfError(f"{name} が見つかりません（poppler-utils を入れてください）")
    return exe


def _check_pdf(root: Path, pdf: str) -> Path:
    p = (root / pdf).resolve()
    try:
        rel = p.relative_to(root)
    except ValueError:
        raise PdfError("vault の外は扱いません") from None
    if any(part.startswith(".") for part in rel.parts) or p.suffix.lower() != ".pdf" or not p.is_file():
        raise PdfError("vault の中の PDF を指定してください: " + pdf)
    if p.stat().st_size > MAX_PDF:
        raise PdfError("大きすぎる PDF です（50 MB まで）")
    return p


def _run(args: list[str]) -> str:
    r = subprocess.run(args, capture_output=True, timeout=TIMEOUT)
    if r.returncode != 0:
        raise PdfError((r.stderr.decode("utf-8", "replace") or "実行に失敗しました")[:200])
    return r.stdout.decode("utf-8", "replace")


def page_count(p: Path) -> int:
    out = _run([_tool("pdfinfo"), str(p)])
    m = re.search(r"^Pages:\s+(\d+)", out, re.M)
    if not m:
        raise PdfError("ページ数を読めませんでした")
    return int(m.group(1))


def page_text(p: Path, n: int) -> str:
    return _run([_tool("pdftotext"), "-f", str(n), "-l", str(n), "-layout", str(p), "-"])


def _words(p: Path, n: int) -> list[tuple[float, float, float, float, str]]:
    """そのページの単語と座標（pdftotext -bbox。原点は左上・単位はポイント）。"""
    xml = _run([_tool("pdftotext"), "-f", str(n), "-l", str(n), "-bbox", str(p), "-"])
    xml = re.sub(r"<!DOCTYPE[^>]*>", "", xml)
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return []
    out = []
    for w in root.iter():
        if w.tag.endswith("word") and w.text:
            out.append((float(w.get("xMin")), float(w.get("yMin")), float(w.get("xMax")), float(w.get("yMax")), w.text))
    return out


def annotations(root: str | Path, pdf: str) -> dict:
    root = Path(root).resolve()
    p = _check_pdf(root, pdf)
    data = p.read_bytes()
    if b"/Encrypt" in data[-2048:] or re.search(rb"/Encrypt\s+\d+\s+\d+\s+R", data):
        raise PdfError("暗号化された PDF は読めません")
    objs = _objects(data)
    pages = _pages(objs)
    if not pages:
        raise PdfError("PDF のページ構造を読めませんでした")
    out = []
    for pno, pn in enumerate(pages, 1):
        b = objs[pn]
        annots = _refs(_array(b, b"Annots", objs))
        if not annots:
            continue
        mb = _nums(_inherited(objs, pn, b"MediaBox")) or [0, 0, 612, 792]
        height = mb[3] - mb[1] if len(mb) == 4 else 792
        words = None
        for a in annots:
            ab = objs.get(a)
            if ab is None:
                continue
            sm = re.search(rb"/Subtype\s*/(\w+)", ab)
            if not sm or sm.group(1).decode() not in KINDS:
                continue
            kind = sm.group(1).decode()
            contents = _read_string(ab, b"Contents").replace("\r\n", "\n").replace("\r", "\n").strip()
            text = ""
            if kind in TEXT_KINDS:
                q = _nums(_array(ab, b"QuadPoints", objs))
                if words is None:
                    words = _words(p, pno)
                picked = []
                for i in range(0, len(q) - 7, 8):
                    xs, ys = q[i:i + 8:2], q[i + 1:i + 8:2]
                    x0, x1, y0, y1 = min(xs), max(xs), height - max(ys), height - min(ys)       # PDF の原点は左下 → 左上へ
                    for (wx0, wy0, wx1, wy1, w) in words:
                        cx, cy = (wx0 + wx1) / 2, (wy0 + wy1) / 2
                        if x0 - 1 <= cx <= x1 + 1 and y0 - 1 <= cy <= y1 + 1:
                            picked.append((round(wy0), wx0, w))
                text = " ".join(w for _, _, w in sorted(picked)).strip()
            out.append({"page": pno, "kind": kind, "kind_ja": KINDS[kind], "contents": contents, "text": text, "author": _read_string(ab, b"T")})
    return {"pdf": p.relative_to(root).as_posix(), "pages": len(pages), "annotations": out}


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).lower()
    return re.sub(r"[\s　\-‐‑–—・、。，．,.「」『』“”\"'`]+", "", s)


def digest(root: str | Path, pdf: str, write: str | None = None, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    a = annotations(root, pdf)
    if not a["annotations"]:
        raise PdfError("注釈がありません")
    name = Path(pdf).name
    link = lambda pg: f"[p.{pg}]({a['pdf'].replace(' ', '%20')}#page={pg})"
    L = [f"# {Path(pdf).stem}の読書メモ（PDF の注釈から）", "", "PDF の注釈（ハイライトとコメント）を集めた草稿です。自分の言葉での要約は、この下に書き足してください。", ""]
    for x in sorted(a["annotations"], key=lambda x: (x["page"], x["kind"])):
        if x["text"]:
            L.append(f"> {x['text']}\n> — {link(x['page'])}" + (f"\n\nコメント: {x['contents']}" if x["contents"] else "") + "\n")
        elif x["contents"]:
            L.append(f"- {x['kind_ja']}: {x['contents']}（{link(x['page'])}）")
    L += ["", "## 自分の言葉で", "", ""]
    body = "\n".join(L)
    res = {"pdf": a["pdf"], "count": len(a["annotations"]), "draft": body}
    if write:
        t = (root / write).resolve()
        try:
            rel = t.relative_to(root)
        except ValueError:
            raise PdfError("vault の外には書きません") from None
        if any(part.startswith(".") for part in rel.parts) or t.suffix != ".md":
            raise PdfError("書き先は vault の中の .md（ドット始まりのフォルダ以外）にしてください")
        if t.exists():
            raise PdfError("すでにあります（上書きしません）: " + str(rel))
        now = now or dt.datetime.now()
        title = f"{Path(pdf).stem}の読書メモ"
        t.parent.mkdir(parents=True, exist_ok=True)
        tmp = t.with_name(t.name + ".tmp")
        tmp.write_text(f"---\ntime: {now:%Y-%m-%d %H:%M:%S}\ntitle: {title}\nsource: pdf\n---\n\n" + body + "\n", encoding="utf-8")
        os.replace(tmp, t)
        res["written"] = rel.as_posix()
    return res


PDF_LINK = re.compile(r"\]\(([^)\s#]+\.pdf)#page=(\d+)[^)]*\)", re.I)


def _refs_in(text: str):
    """(行番号, 引用文, pdf パス, ページ)。`> 引用` の次の行にリンクがある形・同じ行に引用とリンクがある形を拾う。"""
    lines = text.split("\n")
    fence = False
    for i, ln in enumerate(lines):
        if ln.strip().startswith(("```", "~~~")):
            fence = not fence
            continue
        if fence:
            continue
        for m in PDF_LINK.finditer(ln):
            before = ln[:m.start()]
            before = re.sub(r"\[[^\]]*$", "", before)                       # リンクの表示文字の手前まで
            quote = re.sub(r"^\s*>\s*", "", before).strip(" 　—-–「」『』\"“”")
            if len(_norm(quote)) < 6 and i > 0 and lines[i - 1].lstrip().startswith(">"):      # 引用が前の行にあるとき
                quote = "".join(re.sub(r"^\s*>\s*", "", x) for x in _quote_block(lines, i - 1))
            if len(_norm(quote)) >= 6:
                yield i + 1, quote, unquote(m.group(1)), int(m.group(2))


def _quote_block(lines: list[str], end: int) -> list[str]:
    j = end
    while j - 1 >= 0 and lines[j - 1].lstrip().startswith(">"):
        j -= 1
    return [x for x in lines[j:end + 1] if not re.search(r"\]\([^)]*#page=", x)]


def check(root: str | Path, note: str | None = None) -> dict:
    root = Path(root).resolve()
    results, cache, counts = [], {}, {"ok": 0, "mismatch": 0, "unreadable": 0}
    for p in tk.iter_notes(root):
        rel = p.relative_to(root).as_posix()
        if note and rel != note and p.name != note and p.stem != note:
            continue
        for line, quote, pdfrel, page in _refs_in(p.read_text(encoding="utf-8")):
            target = (p.parent / pdfrel).resolve()
            try:
                pdf = _check_pdf(root, target.relative_to(root).as_posix())
                key = (str(pdf), page)
                if key not in cache:
                    cache[key] = _norm(page_text(pdf, page))
                if _norm(quote) in cache[key]:
                    counts["ok"] += 1
                    results.append({"file": rel, "line": line, "pdf": pdfrel, "page": page, "status": "ok", "quote": quote[:80]})
                    continue
                near = []
                for n in range(max(1, page - 3), min(page_count(pdf), page + 3) + 1):
                    if n != page:
                        k2 = (str(pdf), n)
                        if k2 not in cache:
                            cache[k2] = _norm(page_text(pdf, n))
                        if _norm(quote) in cache[k2]:
                            near.append(n)
                counts["mismatch"] += 1
                results.append({"file": rel, "line": line, "pdf": pdfrel, "page": page, "status": "mismatch", "quote": quote[:80], "found_on": near})
            except (PdfError, ValueError, OSError) as e:
                counts["unreadable"] += 1
                results.append({"file": rel, "line": line, "pdf": pdfrel, "page": page, "status": "unreadable", "quote": quote[:80], "error": str(e)[:120]})
    return {"counts": counts, "refs": results}


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    if kind == "annotations":
        L = [f"# PDF の注釈: {r['pdf']}（{r['pages']} ページ・{len(r['annotations'])} 件）", ""]
        for x in r["annotations"]:
            L.append(f"- p.{x['page']} {x['kind_ja']}" + (f"「{x['text']}」" if x["text"] else "") + (f" — {x['contents']}" if x["contents"] else ""))
    elif kind == "check":
        c = r["counts"]
        L = ["# 引用とページリンクの検査", "", f"一致 {c['ok']}・ずれ {c['mismatch']}・読めない {c['unreadable']}", ""]
        for x in r["refs"]:
            if x["status"] == "ok":
                continue
            where = f"[{x['file']}]({x['file'].replace(' ', '%20')}):{x['line']}"
            if x["status"] == "mismatch":
                L.append(f"- {where} 「{x['quote']}」は {x['pdf']} の p.{x['page']} に見つかりません" + (f"（p.{', '.join(map(str, x['found_on']))} にあります）" if x["found_on"] else ""))
            else:
                L.append(f"- {where} {x['pdf']} p.{x['page']}: {x['error']}")
    elif kind == "page":
        L = [f"# {r['pdf']} p.{r['page']}", "", "```", r["text"].rstrip(), "```"]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        a = [x for x in argv if x != "--md"]
        write = None
        if "--write" in a:
            i = a.index("--write"); write = a[i + 1]; del a[i:i + 2]
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "annotations":
            r = annotations(root, rest[0])
        elif cmd == "digest":
            r = digest(root, rest[0], write)
            print(r["draft"] if md else json.dumps(r, ensure_ascii=False))
            return 0
        elif cmd == "check":
            r = check(root, rest[0] if rest else None)
        elif cmd == "page":
            p = _check_pdf(Path(root).resolve(), rest[0])
            r = {"pdf": rest[0], "page": int(rest[1]), "text": page_text(p, int(rest[1]))}
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
