#!/usr/bin/env python3
"""日本語 / 英語の文言の検査。

1. gnosis#i18n#t('キー') のキーが i18n/ja.json と i18n/en.json の両方にある
2. gnosis#i18n#tr('日本語') の文が i18n/en.json の対応表（"ja"）にある
3. 両言語で printf の %s / %d の数と順番が同じ
4. ja.json と en.json の msg のキーが同じ
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ja = json.loads((REPO / "i18n/ja.json").read_text(encoding="utf-8"))
en = json.loads((REPO / "i18n/en.json").read_text(encoding="utf-8"))
files = [p for p in (REPO / "autoload").rglob("*.vim") if p.name != "i18n.vim"] + list((REPO / "plugin").glob("*.vim")) + [REPO / "web/vim/gui.vim"]
js = list((REPO / "web/src").glob("*.js"))
ng = 0
fmt = lambda s: re.findall(r"%[sd]", s.replace("%%", ""))


def bad(msg):
    global ng
    print("NG: " + msg, file=sys.stderr)
    ng += 1


if set(ja["msg"]) != set(en["msg"]):
    bad("ja.json と en.json の msg のキーが違う: " + str(set(ja["msg"]) ^ set(en["msg"])))
for k in ja["msg"]:
    if k in en["msg"] and fmt(ja["msg"][k]) != fmt(en["msg"][k]):
        bad(f"{k}: printf の書式が違う")
for f in files:
    text = f.read_text(encoding="utf-8")
    for m in re.finditer(r"gnosis#i18n#t\('([^']+)'", text):
        if m.group(1) not in ja["msg"]:
            bad(f"{f.relative_to(REPO)}: キー {m.group(1)} が i18n に無い")
    for m in re.finditer(r"gnosis#i18n#tr\('((?:[^']|'')*)'", text):
        k = m.group(1).replace("''", "'")
        if k not in en.get("ja", {}):
            bad(f"{f.relative_to(REPO)}: 英語が無い: {k}")
        elif fmt(k) != fmt(en["ja"][k]):
            bad(f"英語の printf の書式が違う: {k}")
for f in js:
    for m in re.finditer(r"\bt\(\"([a-z_]+\.[a-zA-Z_.]*[a-zA-Z_])\"", f.read_text(encoding="utf-8")):
        if m.group(1) not in ja["msg"]:
            bad(f"{f.relative_to(REPO)}: キー {m.group(1)} が i18n に無い")
if ng:
    sys.exit(1)
print(f"i18n OK ({len(ja['msg'])} keys, {len(en.get('ja', {}))} messages)")
