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

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "syn-view-swap-"));

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
