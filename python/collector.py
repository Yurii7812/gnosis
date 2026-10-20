#!/usr/bin/env python3
"""外部情報の収集（AI11）。利用者が明示的に許可した RSS / Atom の URL だけを読み、新しい記事を「新しいノート」として受信箱に置く。

**既定では何も通信しない。** 通信は次の 3 つがそろったときだけ:
  1. `<vault>/.gnosis/collector.json` の `"enabled": true`（`enable` で利用者が自分で入れる）
  2. 許可した URL の一覧（`allow URL` で利用者が足したものだけ）
  3. `run` を実行した（手動、または cron / systemd timer などから。常駐するプロセスはこのツールには無い）
読むだけ: ノートへの書き込みは、`収集/` フォルダへの**新しいノートの作成だけ**。既存のノートは変えない。API キー・ログイン・Cookie は扱わない。

安全策:
  - XML は `DOCTYPE`/`ENTITY` を含むものを拒否（外部実体・巨大展開を防ぐ）。応答は 2 MB まで・15 秒まで・1 フィードあたり新しい記事は 20 件まで。
  - リダイレクトは、同じホストとポートの中だけ。別のホストへ飛ばされたら止める。http / https 以外は拒否。
  - 本文は文字だけにする（HTML のタグ・スクリプトは捨てる）。リンクは http / https のものだけ。
  - 一度取り込んだ記事（GUID / リンク）は `.state/collector.json` に覚え、消されても作り直さない。
  - 失敗（接続・形式・大きさ）はそのフィードだけ記録して、ほかのフィードは続ける。

CLI（JSON）:
  collector.py ROOT status                  設定・許可した URL・最後の実行
  collector.py ROOT enable | disable        収集を有効／無効にする
  collector.py ROOT allow URL | deny URL    許可する URL を足す／外す
  collector.py ROOT run                     許可した URL を読んで、新しい記事をノートにする（無効なら何もしない）
cron の例（1 時間ごと）:  0 * * * *  python3 /path/to/collector.py /path/to/vault run
"""
from __future__ import annotations

import datetime as dt
import hashlib
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path

CONFIG = ".gnosis/collector.json"
STATE = ".state/collector.json"
INBOX = "収集"
MAX_BYTES = 2 * 1024 * 1024
TIMEOUT = 15
MAX_NEW = 20
UA = "Gnosis-collector/1.0 (+local; read-only)"


class Blocked(Exception):
    pass


def _cfg_path(root: Path) -> Path:
    return root / CONFIG


def load_config(root: Path) -> dict:
    try:
        d = json.loads(_cfg_path(root).read_text(encoding="utf-8"))
        if not isinstance(d, dict):
            raise ValueError
    except (OSError, ValueError):
        d = {}
    urls = [u for u in d.get("allow", []) if isinstance(u, str) and _valid_url(u)]
    return {"enabled": d.get("enabled") is True, "allow": urls, "last_run": d.get("last_run", "")}


def _save(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, path)


def _valid_url(u: str) -> bool:
    p = urllib.parse.urlsplit(u)
    return p.scheme in ("http", "https") and bool(p.hostname) and not p.username and not p.password and len(u) <= 500


def set_enabled(root: str | Path, on: bool) -> dict:
    root = Path(root).resolve()
    c = load_config(root)
    c["enabled"] = on
    _save(_cfg_path(root), c)
    return {"enabled": on}


def allow(root: str | Path, url: str) -> dict:
    root = Path(root).resolve()
    if not _valid_url(url):
        raise ValueError("http または https の URL（ユーザー名・パスワードなし）を指定してください")
    c = load_config(root)
    if url not in c["allow"]:
        c["allow"].append(url)
    _save(_cfg_path(root), c)
    return {"allow": c["allow"]}


def deny(root: str | Path, url: str) -> dict:
    root = Path(root).resolve()
    c = load_config(root)
    if url not in c["allow"]:
        raise ValueError("許可の一覧にありません: " + url)
    c["allow"].remove(url)
    _save(_cfg_path(root), c)
    return {"allow": c["allow"]}


class _SameHost(urllib.request.HTTPRedirectHandler):
    def __init__(self, origin: tuple[str, int | None]):
        self.origin = origin

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        p = urllib.parse.urlsplit(newurl)
        if p.scheme not in ("http", "https") or (p.hostname, p.port) != self.origin:
            raise Blocked("別のホストへのリダイレクトは辿りません: " + newurl[:80])
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def default_fetch(url: str) -> bytes:
    p = urllib.parse.urlsplit(url)
    opener = urllib.request.build_opener(_SameHost((p.hostname, p.port)))
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml"})
    with opener.open(req, timeout=TIMEOUT) as r:
        data = r.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise Blocked("応答が大きすぎます（%d MB まで）" % (MAX_BYTES // 1024 // 1024))
    return data


class _Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out: list[str] = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.skip += 1
        elif tag in ("p", "div", "h1", "h2", "h3", "h4"):
            self.out.append("\n\n")                                  # 段落は空行で区切る(Markdown では単独の改行だと段落がつながる)
        elif tag in ("br", "li", "tr"):
            self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self.skip:
            self.skip -= 1

    def handle_data(self, d):
        if not self.skip:
            self.out.append(d)


def to_text(s: str, limit: int = 1500) -> str:
    p = _Text()
    try:
        p.feed(s or "")
        p.close()
    except Exception:
        return re.sub(r"<[^>]*>", "", s or "")[:limit]
    t = re.sub(r"[ \t　]+", " ", "".join(p.out))
    t = re.sub(r"\n\s*\n+", "\n\n", t).strip()
    t = re.sub(r"^[#>`~|\-=*]+", "", t, flags=re.M)               # 行頭の Markdown の記号を無効にする(見出し・引用・コードに化けさせない)
    return t[:limit]


def parse_feed(data: bytes) -> list[dict]:
    head = data[:4096].decode("utf-8", errors="ignore").lower()
    if "<!doctype" in head or "<!entity" in head or b"<!ENTITY" in data or b"<!DOCTYPE" in data:
        raise Blocked("XML に DOCTYPE / ENTITY があるので読みません")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as e:
        raise Blocked("フィードとして読めません: " + str(e)[:80]) from None
    strip = lambda t: t.split("}", 1)[-1]
    items = []
    for el in root.iter():
        if strip(el.tag) not in ("item", "entry"):
            continue
        d = {strip(c.tag): c for c in el}
        def txt(*names):
            for n in names:
                if n in d:
                    t = (d[n].text or "").strip()
                    if t:
                        return t
            return ""
        link = txt("link")
        if not link and "link" in d:
            link = d["link"].get("href", "")
        for c in el:
            if strip(c.tag) == "link" and c.get("rel", "alternate") == "alternate" and c.get("href"):
                link = c.get("href")
                break
        guid = txt("guid", "id") or link or txt("title")
        if not guid:
            continue
        items.append({"guid": guid, "title": txt("title") or "(無題)", "link": link if link.startswith(("http://", "https://")) else "",
                      "summary": to_text(txt("description", "summary", "content", "encoded")), "date": txt("pubDate", "published", "updated", "date")})
    return items


def _slug(s: str) -> str:
    s = re.sub(r"[\\/:*?\"<>|#\[\]\s]+", "_", s.strip())[:40].strip("._")
    return s or "item"


def _note_text(item: dict, feed: str, now: dt.datetime) -> str:
    title = re.sub(r"\s+", " ", to_text(item["title"], 200)) or "(無題)"
    fm_title = title.replace("\n", " ")
    body = item["summary"] or ""
    lines = ["---", f"time: {now:%Y-%m-%d %H:%M:%S}", f"title: {fm_title}", "source: web", f"feed: {feed}"]
    if item["date"]:
        lines.append("published: " + re.sub(r"[\n\r]", " ", item["date"])[:60])
    lines += ["---", "", "# " + fm_title, "", body, ""]
    if item["link"]:
        lines += [f"[元の記事]({item['link'].replace(' ', '%20').replace(')', '%29')})", ""]
    return "\n".join(lines)


def run(root: str | Path, fetch=default_fetch, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    cfg = load_config(root)
    if not cfg["enabled"]:
        return {"ran": False, "reason": "収集が有効になっていません（enable で有効にします）。通信しませんでした。"}
    if not cfg["allow"]:
        return {"ran": False, "reason": "許可した URL がありません（allow URL）。通信しませんでした。"}
    now = now or dt.datetime.now()
    try:
        state = json.loads((root / STATE).read_text(encoding="utf-8"))
        seen = state.get("seen", {}) if isinstance(state, dict) else {}
    except (OSError, ValueError):
        seen = {}
    report = []
    for url in cfg["allow"]:
        row = {"url": url, "new": 0, "skipped": 0, "error": ""}
        try:
            items = parse_feed(fetch(url))
        except (Blocked, urllib.error.URLError, OSError, ValueError) as e:
            row["error"] = str(getattr(e, "reason", e))[:160]
            report.append(row)
            continue
        for it in items:
            key = hashlib.sha256((url + "\0" + it["guid"]).encode("utf-8")).hexdigest()[:20]
            if key in seen:
                row["skipped"] += 1
                continue
            if row["new"] >= MAX_NEW:
                break
            name = f"{INBOX}/{now:%Y%m%d}-{_slug(it['title'])}-{key[:6]}.md"
            target = root / name
            if target.exists():
                seen[key] = name
                row["skipped"] += 1
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            tmp = target.with_name(target.name + ".tmp")
            tmp.write_text(_note_text(it, url, now), encoding="utf-8")
            os.replace(tmp, target)
            seen[key] = name
            row["new"] += 1
        report.append(row)
    _save(root / STATE, {"seen": seen})
    cfg["last_run"] = now.strftime("%Y-%m-%d %H:%M:%S")
    _save(_cfg_path(root), cfg)
    return {"ran": True, "feeds": report, "new": sum(r["new"] for r in report), "errors": sum(1 for r in report if r["error"])}


def status(root: str | Path) -> dict:
    root = Path(root).resolve()
    return load_config(root)


def main(argv: list[str]) -> int:
    try:
        root, cmd, rest = argv[0], argv[1], argv[2:]
        if cmd == "status":
            r = status(root)
        elif cmd in ("enable", "disable"):
            r = set_enabled(root, cmd == "enable")
        elif cmd == "allow":
            r = allow(root, rest[0])
        elif cmd == "deny":
            r = deny(root, rest[0])
        elif cmd == "run":
            r = run(root)
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
