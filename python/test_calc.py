#!/usr/bin/env python3
import contextlib
import io
import math
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import calc


class CalcTest(unittest.TestCase):
    def test_arithmetic(self):
        for expr, want in (("1+2*3", 7), ("(1+2)*3", 9), ("10/4", 2.5), ("10//4", 2), ("10%4", 2), ("2**10", 1024), ("-3+5", 2), ("+4", 4), ("2^3", 8), ("6×7", 42), ("9÷3", 3), ("1_000+1", 1001),
                           ("sqrt(16)", 4), ("abs(-3)", 3), ("max(1,5,3)", 5), ("min(4,2)", 2), ("sum(1,2,3)", 6), ("round(2.567, 2)", 2.57), ("floor(2.9)", 2), ("ceil(2.1)", 3), ("log10(1000)", 3)):
            self.assertEqual(calc.evaluate(expr), want, expr)
        self.assertAlmostEqual(calc.evaluate("pi*2"), 2 * math.pi)
        self.assertAlmostEqual(calc.evaluate("sin(pi/2)"), 1.0)
        self.assertAlmostEqual(calc.evaluate("e"), math.e)

    def test_float_formatting(self):
        self.assertEqual(calc.fmt(calc.evaluate("0.1+0.2")), "0.3")                 # 10 桁で丸めて 0.30000000000000004 を見せない
        self.assertEqual(calc.fmt(calc.evaluate("4/2")), "2")
        self.assertEqual(calc.fmt(calc.evaluate("1/3")), "0.3333333333")
        self.assertEqual(calc.fmt(calc.evaluate("2**64")), "18446744073709551616")  # 整数は丸めない

    def test_rejects_anything_that_is_not_arithmetic(self):
        bad = ["__import__('os').system('id')", "open('/etc/passwd')", "().__class__", "x", "a+1", "'abc'", "True", "None", "[1,2]", "{1:2}", "lambda: 1", "1 if 1 else 2",
               "(1).real", "abs.__call__(1)", "print(1)", "eval('1')", "sqrt(1)(2)", "min(key=abs)", "1;2", "1 and 2", "1 < 2", "not 1", "[x for x in (1,)]", "f'{1}'", "1j", "...", "b'a'", "sqrt", "1 +", "", "   "]
        for expr in bad:
            with self.assertRaises(calc.CalcError, msg=expr):
                calc.evaluate(expr)

    def test_resource_limits(self):
        for expr, msg in (("9**9**9", "指数"), ("2**100000", "指数"), ("10000000**1000", "大きすぎ"), ("1e308*10", "数になりません"), ("1/0", "0 では"), ("5%0", "0 では"),
                          ("sqrt(-1)", "計算できません"), ("log(0)", "計算できません"), ("-" * 40 + "1", "深すぎ"), ("1+" * 200 + "1", "長すぎ"), ("1\n+2", "1 行")):
            t = time.time()
            with self.assertRaises(calc.CalcError, msg=expr) as cm:
                calc.evaluate(expr)
            self.assertIn(msg, str(cm.exception), expr)
            self.assertLess(time.time() - t, 2, "固まらない: " + expr)

    def test_deep_parentheses_do_not_hang_or_crash(self):
        for n in (50, 150, 500, 5000):
            try:
                v = calc.evaluate("(" * n + "1" + ")" * n)
                self.assertEqual(v, 1)                                         # 括弧は構文木の深さにならないので計算できる
            except calc.CalcError:
                pass                                                           # パーサが拒否するほど深い場合は「読めません」で止まる(落ちない)

    def test_large_but_allowed_values(self):
        self.assertEqual(len(str(calc.evaluate("10**1000"))), 1001)              # 上限の内側は計算できる
        self.assertEqual(calc.evaluate("2**1000") % 1000, 376)

    def test_fill_inline_and_trailing_equals(self):
        text = "合計 {{= 12 * (3 + 4) }} です\n1280 / 16 =\n- 3 + 4 =\n見出しの = は計算しない\n{{= 2 * 3 => 古い結果 }}\n"
        out, problems = calc.fill(text)
        self.assertEqual(problems, [])
        self.assertEqual(out.split("\n"), ["合計 {{= 12 * (3 + 4) => 84 }} です", "1280 / 16 = 80", "- 3 + 4 = 7", "見出しの = は計算しない", "{{= 2 * 3 => 6 }}", ""])
        again, _ = calc.fill(out)
        self.assertEqual(again, out)                                              # 何度やっても同じ(結果だけ更新)

    def test_fill_leaves_bad_expressions_and_code_blocks_alone(self):
        text = "{{= 1/0 }}\n```\n1+1 =\n{{= 2+2 }}\n```\n| a | b = |\n# 章 1 =\n名前 =\n"
        out, problems = calc.fill(text)
        self.assertEqual(out, text)                                               # コードの中・表・見出し・式でない行は不変
        self.assertEqual([(p["line"], p["error"]) for p in problems], [(1, "0 では割れません")])

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = calc.main(list(a))
            return rc, buf.getvalue()
        rc, out = run("2+2")
        self.assertEqual((rc, '"text": "4"' in out), (0, True))
        self.assertEqual(run("1/0")[0], 1)
        self.assertEqual(run("--fill", "1+1 =")[0], 0)
        self.assertEqual(run("--fill", "{{= 1/0 }}")[0], 1)
        self.assertEqual(run()[0], 2)


if __name__ == "__main__":
    unittest.main()
