#!/usr/bin/env python3
"""試験用: ファイルの真ん中の 1 バイトを反転する（バックアップが壊れたときの検証を試すため）。"""
import sys

p = sys.argv[1]
b = bytearray(open(p, "rb").read())
b[len(b) // 2] ^= 0xFF
open(p, "wb").write(b)
