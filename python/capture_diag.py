#!/usr/bin/env python3
"""\\M の診断と移行（既定は dry-run。実データは --apply を付けたときだけ書く）。

duplicates ROOT          … 旧版が「本文を書き直すと別版ノートを作る」仕様だったときにできた、`<id>-2.md` のような別版の一覧
backfill ROOT [--apply]  … 取り込み記録（state）にあるが front matter に `capture_id:` が無い旧ノートへ、`capture_id:` を足す
                            （リネームしても追跡できるようにする。足すだけで他は変えない。書いた内容は .state/capture_backfill.log に残す）
自動で消したり統合したりしない。別版の統合は `\\l` → m（マージ。:GnosisMergeUndo で戻せる）で行う。
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capture_import as ci  # noqa: E402


def duplicates(root: Path) -> list[dict]:
    st = ci.load_state(root)
    out = []
    for mid, target in sorted(st.get("ids", {}).items()):
        if not target.endswith(".md") or "#" in target or not (root / target).is_file():
            continue
        stem = Path(target).stem
        sib = sorted(p.name for p in (root / Path(target).parent).glob(stem + "-*.md")
                     if re.fullmatch(re.escape(stem) + r"-\d+", p.stem))
        if sib:
            out.append({"id": mid, "original": target, "versions": sib})
    return out


def backfill(root: Path, apply: bool) -> list[dict]:
    st = ci.load_state(root)
    plan = []
    for mid, target in sorted(st.get("ids", {}).items()):
        if not target.endswith(".md") or "#" in target or not (root / target).is_file():
            continue
        lines = (root / target).read_text(encoding="utf-8").split("\n")
        if not lines or lines[0] != "---" or "---" not in lines[1:]:
            continue
        end = lines.index("---", 1)
        if any(ln.startswith("capture_id:") for ln in lines[1:end]):
            continue
        at = end
        for i in range(1, end):
            if lines[i].startswith("capture:"):
                at = i + 1
        plan.append({"id": mid, "file": target, "line": f"capture_id: {mid}", "at": at})
    if apply and plan:
        log = root / ".state" / "capture_backfill.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("a", encoding="utf-8") as f:
            for item in plan:
                p = root / item["file"]
                lines = p.read_text(encoding="utf-8").split("\n")
                lines.insert(item["at"], item["line"])
                tmp = p.with_name(p.name + ".gnosis-tmp")
                tmp.write_text("\n".join(lines), encoding="utf-8")
                os.replace(tmp, p)
                f.write(json.dumps({"file": item["file"], "added": item["line"]}, ensure_ascii=False) + "\n")
    return plan


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "duplicates":
        print(json.dumps(duplicates(Path(argv[1])), ensure_ascii=False))
        return 0
    if len(argv) in (2, 3) and argv[0] == "backfill":
        apply = len(argv) == 3 and argv[2] == "--apply"
        print(json.dumps({"applied": apply, "items": backfill(Path(argv[1]), apply)}, ensure_ascii=False))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
