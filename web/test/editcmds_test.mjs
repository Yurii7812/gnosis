// editcmds.js / history.js の試験（node test/editcmds_test.mjs）
import assert from "node:assert/strict";
import { toggleWrap, setHeading, toggleLinePrefix, toggleTaskAt, makeLink, enterInList, indentLines, apply } from "../src/editcmds.js";
import { createHistory } from "../src/history.js";

// --- 太字・斜体・コード ---
let d = "abc def ghi";
let r = toggleWrap(d, 4, 7, "**");
assert.equal(apply(d, r), "abc **def** ghi");
assert.deepEqual([r.anchor, r.head], [6, 9]);                              // 囲んだ文字が選択されたまま
let d2 = apply(d, r);
assert.equal(apply(d2, toggleWrap(d2, r.anchor, r.head, "**")), d, "もう一度で外れる");
assert.equal(apply(d2, toggleWrap(d2, 4, 11, "**")), d, "記号ごと選択していても外れる");
r = toggleWrap("x", 1, 1, "*");
assert.equal(apply("x", r), "x**");
assert.equal(r.anchor, 2);                                                  // 空の選択: 記号だけ入れて間にカーソル
assert.equal(apply("日本語", toggleWrap("日本語", 0, 3, "`")), "`日本語`");
assert.equal(apply("a", toggleWrap("a", 0, 1, "[", "]")), "[a]");          // open と close が違う

// --- 見出し ---
assert.equal(apply("本文", setHeading("本文", 1, 2)), "## 本文");
assert.equal(apply("## 本文", setHeading("## 本文", 5, 2)), "本文");           // 同じレベルは外す
assert.equal(apply("## 本文", setHeading("## 本文", 5, 3)), "### 本文");       // 付け替え
assert.equal(apply("a\nb\nc", setHeading("a\nb\nc", 2, 1)), "a\n# b\nc");     // 1 行だけ
r = setHeading("本文", 1, 1);
assert.equal(r.anchor, 3);                                                  // カーソルは文字に付いて動く

// --- 行頭の記号 ---
const L = "一\n二\n三";
assert.equal(apply(L, toggleLinePrefix(L, 0, L.length, "bullet")), "- 一\n- 二\n- 三");
assert.equal(apply("- 一\n- 二\n- 三", toggleLinePrefix("- 一\n- 二\n- 三", 0, 11, "bullet")), L, "全部付いていれば外す");
assert.equal(apply("- 一\n二", toggleLinePrefix("- 一\n二", 0, 5, "bullet")), "- 一\n- 二", "一部だけなら全部に付ける");
assert.equal(apply(L, toggleLinePrefix(L, 0, L.length, "task")), "- [ ] 一\n- [ ] 二\n- [ ] 三");
assert.equal(apply("- 一", toggleLinePrefix("- 一", 0, 3, "task")), "- [ ] 一", "箇条書き → チェックボックスに付け替え");
assert.equal(apply(L, toggleLinePrefix(L, 0, L.length, "quote")), "> 一\n> 二\n> 三");
assert.equal(apply(L, toggleLinePrefix(L, 0, L.length, "number")), "1. 一\n2. 二\n3. 三");
assert.equal(apply("  字下げ", toggleLinePrefix("  字下げ", 0, 5, "bullet")), "  - 字下げ", "字下げを保つ");
assert.equal(apply("a\n\nb", toggleLinePrefix("a\n\nb", 0, 4, "bullet")), "- a\n\n- b", "空行は触らない");
assert.equal(toggleLinePrefix("", 0, 0, "bullet"), null);

// --- チェックボックス ---
assert.equal(apply("- [ ] 買う", toggleTaskAt("- [ ] 買う", 4)), "- [x] 買う");
assert.equal(apply("- [x] 買う", toggleTaskAt("- [x] 買う", 4)), "- [ ] 買う");
assert.equal(apply("  - [X] 買う", toggleTaskAt("  - [X] 買う", 9)), "  - [ ] 買う");
assert.equal(toggleTaskAt("- 普通", 2), null);

// --- リンク ---
assert.equal(apply("見る", makeLink("見る", 0, 2, "a.md")), "[見る](a.md)");
r = makeLink("", 0, 0, "a.md");
assert.equal(apply("", r), "[](a.md)");
assert.equal(r.anchor, 1);

// --- Enter でリストを続ける ---
let e = enterInList("- 一", 3);
assert.equal(apply("- 一", e), "- 一\n- ");
assert.equal(e.anchor, 6);
assert.equal(apply("1. 一", enterInList("1. 一", 4)), "1. 一\n2. ");
assert.equal(apply("9) 一", enterInList("9) 一", 4)), "9) 一\n10) ");
assert.equal(apply("- [x] 買う", enterInList("- [x] 買う", 8)), "- [x] 買う\n- [ ] ");          // チェックボックスは未完了で
assert.equal(apply("  - 入れ子", enterInList("  - 入れ子", 7)), "  - 入れ子\n  - ");              // 字下げを保つ
assert.equal(apply("- 一\n- ", enterInList("- 一\n- ", 6)), "- 一\n", "空の項目で Enter → 項目をやめる");
assert.equal(apply("- [ ] ", enterInList("- [ ] ", 6)), "");
assert.equal(enterInList("- 一二", 3), null, "行の途中は普通の改行");
assert.equal(enterInList("ふつうの文", 5), null);

// --- Tab / Shift+Tab ---
assert.equal(apply("- a\n- b", indentLines("- a\n- b", 0, 7, 1)), "  - a\n  - b");
assert.equal(apply("  - a\n  - b", indentLines("  - a\n  - b", 0, 11, -1)), "- a\n- b");
assert.equal(apply("- a\n本文", indentLines("- a\n本文", 0, 6, 1)), "  - a\n本文", "リストでない行は触らない");
assert.equal(indentLines("本文", 0, 2, 1), null);
assert.equal(indentLines("- a", 0, 3, -1), null, "字下げが無ければ何もしない");

// --- 履歴 ---
const h = createHistory({ group: 700 });
assert.equal(h.undo("x"), null);
h.record("a", 1000); h.record("ab", 1100); h.record("abc", 1200);          // 700ms 以内の連続 → 1 段（頭の "a" に戻る）
assert.equal(h.size(), 1);
h.record("abcd", 2500);                                                    // 間が空く → 新しい段
assert.equal(h.size(), 2);
assert.equal(h.undo("abcde"), "abcd");
assert.equal(h.undo("abcd"), "a");
assert.equal(h.undo("a"), null);
assert.equal(h.redo("a"), "abcd");
assert.equal(h.redo("abcd"), "abcde");
assert.equal(h.redo("abcde"), null);
h.undo("abcde");
h.record("zzz", 9000);                                                     // 戻ったあとの新しい編集で、やり直しは捨てる
assert.equal(h.canRedo(), false);
let calls = 0;
const lazy = createHistory({ group: 700 });
lazy.record(() => { calls++; return "p0"; }, 100);
lazy.record(() => { calls++; return "p1"; }, 200);                        // まとめる編集では関数を呼ばない
assert.equal(calls, 1);
assert.equal(lazy.undo("now"), "p0");
const small = createHistory({ limit: 3, group: 0 });
for (let i = 0; i < 10; i++) small.record("d" + i, 100 * i);
assert.equal(small.size(), 3);                                             // 上限
small.reset();
assert.equal(small.size(), 0);
console.log("editcmds OK");
