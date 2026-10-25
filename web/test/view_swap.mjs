// マークダウン表示（src/view.js）の回帰テスト: 長いノートから短いノートへ入れ替えたとき、
// 前のノートの位置の装飾（カーソル・数字のしるし）が残って、CodeMirror が
// 「Position N is out of range for changeset」で落ちないこと。
//
//   node test/view_swap.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// 試験の一時フォルダは、デスクトップの test（TMPDIR があればそれ）。本物の vault には触らない。
function testBase() {
  const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
  fs.mkdirSync(base, { recursive: true });
  return base;
}
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const tmp = fs.mkdtempSync(path.join(testBase(), "syn-view-swap-"));

const longDoc = "---\ntime: 2026-10-10 11:48:20\ntitle: Index\nattribute: group\n---\n\n# Index\n"
  + Array.from({ length: 6 }, (_, i) => `[ノート ${i}](n${i}.md)`).join("\n") + "\n";
const shortDoc = "---\ntime: 2026-10-11 19:51:53\ntitle: 短い\n---\n\n# 短い\n\n\n\n### Parent\n[Index](index.md)\n### BackLink\n";

fs.writeFileSync(path.join(tmp, "entry.js"), `
import { createView } from ${JSON.stringify(path.join(web, "src/view.js"))};
const A = ${JSON.stringify(longDoc)}, B = ${JSON.stringify(shortDoc)};
const log = [];
window.addEventListener("error", (e) => log.push("async error: " + e.message));
const v = createView({ parent: document.body, getImageURL: () => null });
const step = (name, fn) => { try { fn(); log.push(name + ": ok"); } catch (e) { log.push(name + ": ERR " + e.message); } };
const n = (t) => t.split("\\n").length;
// 実際に起きた順: 長いノート → 末尾の行へ移動 → 短いノートへ入れ替え → 数字のしるし
step("setText long", () => v.setText(A));
step("vtext long", () => v.setVtext([[8, 1, "1 ", "Hint"], [9, 1, "2 ", "Hint"]]));
step("cursor on last line (G)", () => v.setVim({ cur: [n(A) - 1, 1], mode: "n" }));
step("setText short", () => v.setText(B));
step("vtext short", () => v.setVtext([[9, 1, "1 ", "Hint"]]));
step("cursor short", () => v.setVim({ cur: [1, 1], mode: "n" }));
// そのあとの往復・ビジュアル・挿入でも落ちない
for (let round = 0; round < 3; round++) {
  step("setText long", () => v.setText(A));
  step("vtext long", () => v.setVtext([[8, 1, "1 ", "Hint"]]));
  step("visual", () => v.setVim({ cur: [n(A) - 1, 3], mode: "V", vis: [2, 1] }));
  step("setText short", () => v.setText(B));
  step("vtext short", () => v.setVtext([]));
  step("insert at end of short", () => v.setVim({ cur: [n(B) - 1, 13], mode: "i" }));
}
// HTML の <img src="…" width="50%"> も画像として描き、width を反映すること（インサート中は文字のまま）
step("html img is rendered with its width", () => {
  const holder = document.createElement("div");
  document.body.appendChild(holder);
  const v = createView({ parent: holder, getImageURL: () => "data:image/gif;base64,R0lGODlhAQABAAAAACw=" });
  v.setText("# 画像\\n\\n<img src='a.jpeg' width='50%'>\\n\\n文\\n");
  v.setVim({ cur: [4, 1], mode: "n" });
  const im = document.querySelector(".cm-md-img img");
  if (!im) throw new Error("html img not rendered");
  if (im.style.width !== "50%") throw new Error("width not applied: " + im.style.width);
  v.setVim({ cur: [4, 1], mode: "i" });
  if (document.querySelector(".cm-md-img img")) throw new Error("html img should be text in insert mode");
});
// Markdown の表が本物の表として描かれ、カーソルが表の中・インサート中は文字のままであること
step("table is rendered as a real table", () => {
  const doc = "# 表\\n\\n| 曜日 | 種目 | 備考 |\\n| --- | :-: | --: |\\n| 月 | **腕立て** | 10回 |\\n| 火 | 懸垂 | — |\\n\\n文\\n";
  v.setText(doc);
  v.setVim({ cur: [8, 1], mode: "n" });
  const t = document.querySelector("table.cm-md-table");
  if (!t) throw new Error("table not rendered");
  const rows = t.querySelectorAll("tr").length, ths = [...t.querySelectorAll("th")].map((e) => e.textContent).join(",");
  if (rows !== 3 || ths !== "曜日,種目,備考") throw new Error("bad table: " + rows + " " + ths);
  if (!t.querySelector("td strong")) throw new Error("bold in cell not rendered");
  if (t.querySelector("th:nth-child(2)").style.textAlign !== "center") throw new Error("alignment lost");
  // 実際のノートの表（幅をそろえた空白つき・太字・「—」入り）も 14 行 × 5 列で描かれる
  const big = ["| 曜日       | 種目         | セット数 | 主に鍛える部位 | 備考 |", "| ---------- | ------------ | -------- | -------------- | ---- |"]
    .concat(Array.from({ length: 14 }, (_, i) => "| 月・水・金 | カーフレイズ | 4セット  | ふくらはぎ(腓腹筋) | **15〜20回**。段差 " + i + " |")).join("\\n");
  v.setText("# 表\\n\\n" + big + "\\n\\n文\\n");
  v.setVim({ cur: [20, 1], mode: "n" });
  const bt = document.querySelector("table.cm-md-table");
  if (!bt || bt.querySelectorAll("tbody tr").length !== 14 || bt.querySelectorAll("th").length !== 5) throw new Error("real-note table not rendered");
  v.setText(doc);
  v.setVim({ cur: [8, 1], mode: "n" });
  v.setVim({ cur: [5, 1], mode: "n" });
  // 表はカーソルが中にあっても、挿入モードでも、表の見た目のまま（カーソルのあるセルだけ文字のまま出る）
  if (!document.querySelector("table.cm-md-table")) throw new Error("table should stay a table when the cursor is inside");
  v.setVim({ cur: [8, 1], mode: "i" });
  if (!document.querySelector("table.cm-md-table")) throw new Error("table should stay a table in insert mode");
});
// 中身が空の Context / BackLink の見出しは出さない。中身がある節と、カーソルがある見出しは出す
step("empty relation sections are hidden", () => {
  const doc = "# 題\\n\\n本文\\n\\n### Context\\n[A](a.md)\\n### Group\\n### BackLink\\n";
  v.setText(doc);
  v.setVim({ cur: [3, 1], mode: "n" });
  const shown = () => [...document.querySelectorAll(".cm-line")].filter((e) => !e.classList.contains("cm-md-sec-empty")).map((e) => e.textContent.trim());
  const t = shown();
  if (!t.includes("Context") && !t.some((x) => x.includes("Context"))) throw new Error("Context (has a link) should be shown: " + JSON.stringify(t));
  if (t.some((x) => /Group|BackLink/.test(x))) throw new Error("empty Group/BackLink should be hidden: " + JSON.stringify(t));
  v.setVim({ cur: [8, 1], mode: "n" });
  if (!shown().some((x) => /BackLink/.test(x))) throw new Error("heading under the cursor should be shown");
});
// カーソル行や A 相当の行末でもリンク先は隠し、明示的なモードだけで展開する。
step("link source is explicitly toggled", () => {
  v.setText("# 題\\n\\n- [ ] [修正](261020131029.md)\\n");
  const shown = () => v.view.contentDOM.textContent;
  v.setVim({ cur: [3, 1], mode: "n" });
  if (shown().includes("261020131029.md")) throw new Error("normal cursor revealed link source");
  v.setVim({ cur: [3, 99], mode: "i" });
  if (shown().includes("261020131029.md")) throw new Error("append revealed link source");
  v.setLinkSource(true);
  if (!shown().includes("261020131029.md")) throw new Error("source mode did not reveal link");
  v.setLinkSource(false);
  if (shown().includes("261020131029.md")) throw new Error("source off did not hide link");
});
// アンカー（#見出し）つきのリンクも、クリックできるノートのリンク（data-md-href）になること
step("anchor link is a clickable note link", () => {
  v.setText("# 見出し\\n\\n[二](n.md#2f)\\n[普通](m.md)\\n[外部](https://example.com/a.md#x)\\n");
  v.setVim({ cur: [1, 1], mode: "n" });
  const hrefs = [...document.querySelectorAll("[data-md-href]")].map((e) => e.getAttribute("data-md-href"));
  if (!hrefs.includes("n.md#2f")) throw new Error("anchor link not clickable: " + JSON.stringify(hrefs));
  if (!hrefs.includes("m.md")) throw new Error("plain link not clickable: " + JSON.stringify(hrefs));
});
// 見出しの下のリンクをクリックした位置が、そのリンクの行に対応すること（見出しに縦の margin があると、
// CodeMirror が高さに入れられず、下の行がずれて、隣の行のリンクが開いていた）
step("click position maps to the right line below headings", () => {
  const doc = "---\\ntime: 2026-10-11 10:00:00\\ntitle: t\\n---\\n\\n# 見出し1\\n\\n## 見出し2\\n\\n[a](n.md#x)\\n### 見出し3\\n[b](m.md)\\n[c](o.md)\\n";
  v.setText(doc);
  v.setVim({ cur: [10, 1], mode: "n" });
  const ed = v.view;
  for (const href of ["n.md#x", "m.md", "o.md"]) {
    const el = document.querySelector('[data-md-href="' + href + '"]');
    if (!el) throw new Error("link element missing: " + href);
    const r = el.getBoundingClientRect();
    const pos = ed.posAtCoords({ x: r.left + r.width / 2, y: r.top + r.height / 2 });
    const line = pos == null ? "(none)" : ed.state.doc.lineAt(pos).text;
    if (!line.includes("](" + href + ")")) throw new Error("click at " + href + " maps to line: " + line);
  }
});
// インサートモード中は画像を文字（![](…)）のまま、ノーマルモードでは画像として描く
step("images are raw text in insert mode and images in normal mode", () => {
  v.setText("# 題\\n\\n![](img.png)\\n本文\\n");
  v.setVim({ cur: [4, 1], mode: "i" });
  const inInsert = document.querySelectorAll(".cm-md-img").length;
  const rawInsert = document.querySelector(".cm-content").textContent.includes("![](img.png)");
  v.setVim({ cur: [4, 1], mode: "n" });
  const inNormal = document.querySelectorAll(".cm-md-img").length;
  if (inInsert !== 0 || !rawInsert) throw new Error("insert mode: images=" + inInsert + " raw=" + rawInsert);
  if (inNormal !== 1) throw new Error("normal mode: images=" + inNormal);
});
setTimeout(() => { document.title = "RESULT=" + JSON.stringify(log); }, 600);
`);
fs.writeFileSync(path.join(tmp, "index.html"),
  `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="${path.join(web, "styles.css")}"><title>x</title></head><body><script src="bundle.js"></script></body></html>`);
execFileSync(path.join(web, "node_modules/.bin/esbuild"), [path.join(tmp, "entry.js"), "--bundle", "--format=iife", "--target=chrome100", `--outfile=${path.join(tmp, "bundle.js")}`, "--log-level=error"]);

function findChrome() {
  const base = path.join(os.homedir(), ".cache/ms-playwright");
  if (fs.existsSync(base)) for (const d of fs.readdirSync(base)) if (d.startsWith("chromium-")) { const c = path.join(base, d, "chrome-linux64/chrome"); if (fs.existsSync(c)) return c; }
  for (const c of ["chromium", "chromium-browser", "google-chrome"]) { try { return execFileSync("which", [c], { encoding: "utf8" }).trim(); } catch { /* next */ } }
  throw new Error("chromium not found");
}
let failed = 0;
try {
  const dom = execFileSync(findChrome(), ["--headless=new", "--no-sandbox", "--disable-gpu", "--allow-file-access-from-files", "--virtual-time-budget=5000", "--dump-dom", "file://" + path.join(tmp, "index.html")],
    { encoding: "utf8", maxBuffer: 32 * 1024 * 1024, stdio: ["ignore", "pipe", "ignore"] });
  const m = /<title>RESULT=(.*?)<\/title>/s.exec(dom);
  if (!m) throw new Error("no RESULT");
  const log = JSON.parse(m[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">"));
  const bad = log.filter((l) => !l.endsWith(": ok"));
  if (bad.length) { console.error("FAIL:\n  " + bad.join("\n  ")); failed = 1; }
  else console.log(`view swap: OK (${log.length} steps, 長いノート⇄短いノートの入れ替えでエラー無し)`);
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
process.exit(failed);
