#!/usr/bin/env python3
"""i18n/ja.json・i18n/en.json に文言を足す（開発用）。
    python3 tools/i18n_add.py key '日本語' 'English' [key '日本語' 'English' ...]
    python3 tools/i18n_add.py --ja '日本語の既存メッセージ' 'English'   … gnosis#i18n#tr() 用の対応表
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "i18n"


def load(name):
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


def save(name, data):
    (ROOT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main(argv):
    ja, en = load("ja.json"), load("en.json")
    en.setdefault("ja", {})
    if argv and argv[0] == "--ja":
        args = argv[1:]
        for i in range(0, len(args), 2):
            en["ja"][args[i]] = args[i + 1]
    else:
        for i in range(0, len(argv), 3):
            ja["msg"][argv[i]] = argv[i + 1]
            en["msg"][argv[i]] = argv[i + 2]
    save("ja.json", ja)
    save("en.json", en)


if __name__ == "__main__":
    main(sys.argv[1:])
