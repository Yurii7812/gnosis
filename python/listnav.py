#!/usr/bin/env python3
"""リスト / Folgezettel の検索。gs と同じ候補・検索式・順位・索引名を使う。"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import note_search as ns


def search(root: str, query: str, scope: str = "all") -> list[dict]:
    base = Path(root).resolve()
    out = []
    for _nh, _th, _sort, path, title, line, source in ns.search_rows(root, query, scope):
        try:
            rel = Path(path).resolve().relative_to(base).as_posix()
        except ValueError:
            continue
        out.append({"path": rel, "title": title, "line": line,
                    "kind": "index" if source else "note", "source": source,
                    "depth": 0, "via": ""})
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("root")
    p.add_argument("--query", default="")
    p.add_argument("--scope", choices=ns.MODES, default="all")
    a = p.parse_args()
    print(json.dumps(search(a.root, a.query, a.scope), ensure_ascii=False))


if __name__ == "__main__":
    main()
