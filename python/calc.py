#!/usr/bin/env python3
"""安全な計算（ED14）。ノートの中の式を、シェルや Python の実行から切り離して評価する。

`eval` は使わない。式を構文木に直し、許可した形（数・四則・べき乗・剰余・括弧・単項の ±・決まった関数と定数）だけを評価する。
名前の参照（変数・属性・添字）・関数の定義・文字列・内包表記・ラムダは構文の段階で拒否する。べき乗の大きさ・式の長さ・入れ子の深さも制限する
（`9**9**9` のような固まる式で止まらないようにする）。

書き方（ノートの中）:
  {{= 12 * (3 + 4) }}              … 式。`:GnosisCalc` が `{{= 12 * (3 + 4) => 84 }}` にする（もう一度やると結果だけ更新）
  1280 / 16 =                      … 行末の `=` で終わる行は、`:GnosisCalc` が結果を後ろに足す
関数: sqrt abs round min max sum floor ceil sin cos tan log log10 exp   定数: pi e
CLI:  calc.py '式'            結果を 1 行で（JSON: {"ok":true,"value":…,"text":"…"} か {"ok":false,"error":"…"}）
      calc.py --fill 'テキスト'   テキストの中の `{{= … }}` と、行末が `=` の行を計算して返す
"""
from __future__ import annotations

import ast
import json
import math
import operator
import re
import sys

MAX_LEN = 300
MAX_DEPTH = 30
MAX_EXP = 1000          # べき乗の指数の上限
MAX_BITS = 20000        # 整数の大きさの上限（ビット）
BIN = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod, ast.Pow: operator.pow}
UN = {ast.UAdd: operator.pos, ast.USub: operator.neg}
FUNCS = {"sqrt": math.sqrt, "abs": abs, "round": round, "min": min, "max": max, "sum": lambda *a: sum(a), "floor": math.floor, "ceil": math.ceil,
         "sin": math.sin, "cos": math.cos, "tan": math.tan, "log": math.log, "log10": math.log10, "exp": math.exp}
CONSTS = {"pi": math.pi, "e": math.e}


class CalcError(ValueError):
    pass


def _check_num(v):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise CalcError("数以外の値は扱えません")
    if isinstance(v, int) and v.bit_length() > MAX_BITS:
        raise CalcError("結果が大きすぎます")
    if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
        raise CalcError("結果が数になりません（無限大・非数）")
    return v


def _ev(node, depth=0):
    if depth > MAX_DEPTH:
        raise CalcError("式の入れ子が深すぎます")
    if isinstance(node, ast.Expression):
        return _ev(node.body, depth + 1)
    if isinstance(node, ast.Constant):
        if isinstance(node.value, bool) or not isinstance(node.value, (int, float)):
            raise CalcError("数だけ書けます")
        return _check_num(node.value)
    if isinstance(node, ast.BinOp) and type(node.op) in BIN:
        a, b = _ev(node.left, depth + 1), _ev(node.right, depth + 1)
        if isinstance(node.op, ast.Pow):
            if abs(b) > MAX_EXP:
                raise CalcError("べき乗の指数が大きすぎます（%d まで）" % MAX_EXP)
            if isinstance(a, int) and isinstance(b, int) and b > 0 and a != 0 and abs(a) != 1 and b * max(1, abs(a).bit_length()) > MAX_BITS:
                raise CalcError("結果が大きすぎます")
        try:
            return _check_num(BIN[type(node.op)](a, b))
        except ZeroDivisionError:
            raise CalcError("0 では割れません") from None
        except OverflowError:
            raise CalcError("結果が大きすぎます") from None
    if isinstance(node, ast.UnaryOp) and type(node.op) in UN:
        return _check_num(UN[type(node.op)](_ev(node.operand, depth + 1)))
    if isinstance(node, ast.Name):
        if node.id in CONSTS:
            return CONSTS[node.id]
        raise CalcError("使えない名前です: " + node.id)
    if isinstance(node, ast.Call):
        if not isinstance(node.func, ast.Name) or node.func.id not in FUNCS or node.keywords:
            raise CalcError("使えない関数です")
        args = [_ev(a, depth + 1) for a in node.args]
        try:
            return _check_num(FUNCS[node.func.id](*args))
        except (ValueError, TypeError, ZeroDivisionError, OverflowError) as e:
            raise CalcError("計算できません: %s" % node.func.id) from e
    raise CalcError("使えない書き方です")


def evaluate(expr: str):
    expr = expr.strip().replace("×", "*").replace("÷", "/").replace("−", "-").replace("^", "**")
    if not expr:
        raise CalcError("式が空です")
    if len(expr) > MAX_LEN:
        raise CalcError("式が長すぎます")
    if "\n" in expr or "\x00" in expr:
        raise CalcError("式は 1 行で書いてください")
    try:
        tree = ast.parse(expr, mode="eval")
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        raise CalcError("式として読めません") from None
    try:
        return _ev(tree)
    except RecursionError:
        raise CalcError("式の入れ子が深すぎます") from None


def fmt(v) -> str:
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return str(int(v))
        return ("%.10g" % v)
    return str(v)


INLINE = re.compile(r"\{\{=\s*(.+?)\s*(?:=>\s*[^}]*?)?\s*\}\}")
TRAIL = re.compile(r"^(?P<head>.*?[0-9)πe])\s*=\s*$")


def fill(text: str) -> tuple[str, list[dict]]:
    """`{{= 式 }}` と、行末が `=` の行を計算する。計算できなかった式は元のまま残し、理由を返す。コードブロックの中は触らない。"""
    out, problems, fence = [], [], False
    for no, line in enumerate(text.split("\n"), 1):
        if line.strip().startswith(("```", "~~~")):
            fence = not fence
            out.append(line)
            continue
        if fence:
            out.append(line)
            continue
        def sub(m):
            try:
                return "{{= %s => %s }}" % (m.group(1), fmt(evaluate(m.group(1))))
            except CalcError as e:
                problems.append({"line": no, "expr": m.group(1), "error": str(e)})
                return m.group(0)
        new = INLINE.sub(sub, line)
        if new == line:
            t = TRAIL.match(line)
            if t and not line.lstrip().startswith(("#", "|")):
                expr = re.sub(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)", "", t.group("head"))
                try:
                    new = line.rstrip()[:-1].rstrip() + " = " + fmt(evaluate(expr))
                except CalcError as e:
                    if re.search(r"[0-9]", expr) and re.search(r"[+\-*/^×÷%()]", expr):
                        problems.append({"line": no, "expr": expr.strip(), "error": str(e)})
        out.append(new)
    return "\n".join(out), problems


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "--fill":
        t, p = fill(argv[1])
        print(json.dumps({"ok": not p, "text": t, "problems": p}, ensure_ascii=False))
        return 0 if not p else 1
    if len(argv) == 1:
        try:
            v = evaluate(argv[0])
            print(json.dumps({"ok": True, "value": v, "text": fmt(v)}, ensure_ascii=False))
            return 0
        except CalcError as e:
            print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
            return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
