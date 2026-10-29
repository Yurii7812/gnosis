#!/usr/bin/env python3
"""\\M の診断と移行（既定は dry-run。実データは --apply を付けたときだけ書く）。

duplicates ROOT          … 旧版が「本文を書き直すと別版ノートを作る」仕様だったときにできた、`<id>-2.md` のような別版の一覧
strip-meta ROOT [--apply] … 取り込みで付いた front matter の `capture:` `capture_id:` `capture_topic:` と、それと一緒にある `topic:` を消す
                            （親子関係があるので不要。`topic:` だけのノートには触らない。消した行は .state/capture_strip.log に残す）
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


STRIP_KEYS = ("capture:", "capture_id:", "capture_topic:")


def strip_meta(root: Path, apply: bool) -> list[dict]:
    """取り込みの印（capture 系）がある front matter から、capture 系と topic: の行を消す計画（apply なら書く）。"""
    plan = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            p = Path(dirpath) / name
            try:
                text = p.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            lines = text.split("\n")
            if not lines or lines[0] != "---" or "---" not in lines[1:]:
                continue
            end = lines.index("---", 1)
            fm = lines[1:end]
            if not any(ln.startswith(STRIP_KEYS) for ln in fm):
                continue
            drop = [i + 1 for i, ln in enumerate(fm) if ln.startswith(STRIP_KEYS) or ln.startswith("topic:")]
            plan.append({"file": str(p.relative_to(root)), "lines": [lines[i] for i in drop], "at": drop})
    if apply and plan:
        log = root / ".state" / "capture_strip.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("a", encoding="utf-8") as f:
            for item in plan:
                p = root / item["file"]
                lines = p.read_text(encoding="utf-8").split("\n")
                for i in reversed(item["at"]):
                    del lines[i]
                tmp = p.with_name(p.name + ".gnosis-tmp")
                tmp.write_text("\n".join(lines), encoding="utf-8")
                os.replace(tmp, p)
                f.write(json.dumps({"file": item["file"], "removed": item["lines"]}, ensure_ascii=False) + "\n")
    return plan


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "duplicates":
        print(json.dumps(duplicates(Path(argv[1])), ensure_ascii=False))
        return 0
    if len(argv) in (2, 3) and argv[0] == "strip-meta":
        apply = len(argv) == 3 and argv[2] == "--apply"
        print(json.dumps({"applied": apply, "items": strip_meta(Path(argv[1]), apply)}, ensure_ascii=False))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
