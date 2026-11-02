#!/usr/bin/env python3
"""リストビューの検索。gs と同一の候補・順位・表示名・種別を使う。"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import note_search as ns


def search(root: str, query: str, scope: str = "all") -> list[dict]:
    # Legacy scope is accepted for compatibility but ignored.
    # There is only one unified search, without selectable scopes.
    base = Path(root).resolve()
    out = []
    for _exact, _tier, _quality, path, title, line, source, kind in ns.search_rows(root, query):
        try:
            rel = Path(path).resolve().relative_to(base).as_posix()
        except ValueError:
            continue
        out.append({"path": rel, "title": title, "line": line,
                    "kind": kind, "source": source,
                    "depth": 0, "via": ""})
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("root")
    p.add_argument("--query", default="")
    p.add_argument("--scope", default="all", help=argparse.SUPPRESS)  # Legacy ignored.
    a = p.parse_args()
    print(json.dumps(search(a.root, a.query), ensure_ascii=False))


if __name__ == "__main__":
    main()
