// ライトの見え方（ブラウザの Markdown Viewer 拡張＝GitHub スタイルと同じ）と、ダークが変わらないことの試験。
// 実際の Chromium で view.js + styles.css を描き、計算済みスタイルを確かめる。
//   node test/look_e2e.mjs            … 検査
//   LOOK_SHOT=/path/dir node test/look_e2e.mjs  … 検査に加えて light.png / dark.png を保存（目視用）
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(here, "..");
const repo = path.resolve(web, "..");
const base = process.env.TMPDIR || path.join(os.homedir(), "gnosis-work", "test");
fs.mkdirSync(base, { recursive: true });
const tmp = fs.mkdtempSync(path.join(base, "look-e2e-"));
const pal = JSON.parse(fs.readFileSync(path.join(repo, "assets", "themes", "builtin.json"), "utf8"));

const DOC = `# 見出し 1

本文の段落です。**太字**・*斜体*・\`inline code\`・[リンク](a.md) を含みます。

リンクの行: [リンク先](b.md) と続きの文字

## 見出し 2

> 引用文です。

### 見出し 3

\`\`\`
code block
\`\`\`

| 列 A | 列 B |
| --- | --- |
| 1 | 2 |
| 3 | 4 |

---

終わり
`;

fs.writeFileSync(path.join(tmp, "entry.js"), `
import { createView } from ${JSON.stringify(path.join(web, "src/view.js"))};
import { applyPalette } from ${JSON.stringify(path.join(web, "src/look.js"))};
const PAL = ${JSON.stringify(pal)};
const params = new URLSearchParams(location.search);
const which = params.get("t") === "dark" ? "dark" : "gui_light";
const scn = params.get("s") || "";
const p = PAL[which];
applyPalette(p);
const v = createView({ parent: document.body, getImageURL: () => null });
v.setText(${JSON.stringify(DOC)});
// カーソルは「リンクの行」のリンクの上（2 文字目）。リンクの番号のしるし（Vim の仮想テキスト）も付ける
const LNK = ${JSON.stringify("リンクの行: [")};
const curByte = new TextEncoder().encode(LNK).length + 1 + new TextEncoder().encode("リ").length;
v.setVtext([[5, new TextEncoder().encode(LNK).length + 1, "1", "GnosisLinkHint"]]);
const TBL = ${JSON.stringify(DOC.split("\n").findIndex((l) => l.startsWith("| 3 |")) + 1)};
if (scn === "tbl-i" || scn === "tbl-n") v.setVim({ cur: [TBL, scn === "tbl-i" ? 4 : 3], mode: scn === "tbl-i" ? "i" : "n" });   // 表の「3」のセルの中（| 3 | 4 |）
else if (scn === "lk-open") v.setVim({ cur: [5, new TextEncoder().encode(LNK).length], mode: "n" });                    
else if (scn === "lk-url") v.setVim({ cur: [5, new TextEncoder().encode(LNK).length + 1 + new TextEncoder().encode("リンク先").length + 2], mode: "n" });
else if (scn === "lk-url-i") v.setVim({ cur: [5, new TextEncoder().encode(LNK).length + 1 + new TextEncoder().encode("リンク先").length + 2], mode: "i" });
else v.setVim({ cur: [5, curByte], mode: "n" });
const cs = (sel, prop) => { const e = document.querySelector(sel); return e ? getComputedStyle(e)[prop] : null; };
setTimeout(() => {
  const out = {
    bodyBg: getComputedStyle(document.body).backgroundColor,
    contentMaxWidth: cs(".cm-content", "maxWidth"), contentPad: cs(".cm-content", "paddingLeft"),
    lineHeight: cs(".cm-scroller", "lineHeight"),
    fontFamily: cs(".cm-scroller", "fontFamily"),
    bodyColor: getComputedStyle(document.body).color,
    h1: { size: cs(".cm-md-h1", "fontSize"), weight: cs(".cm-md-h1", "fontWeight"), color: cs(".cm-md-h1", "color"), border: cs(".cm-md-h1", "borderBottomWidth") + " " + cs(".cm-md-h1", "borderBottomStyle") },
    h2: { size: cs(".cm-md-h2", "fontSize"), border: cs(".cm-md-h2", "borderBottomWidth") },
    h3: { size: cs(".cm-md-h3", "fontSize"), color: cs(".cm-md-h3", "color"), border: cs(".cm-md-h3", "borderBottomWidth") },
    code: { bg: cs(".cm-md-code", "backgroundColor"), size: cs(".cm-md-code", "fontSize"), pad: cs(".cm-md-code", "paddingLeft") },
    link: cs(".cm-md-link-md", "color"), linkDeco: cs(".cm-md-link-md", "textDecorationColor"),
    quote: { border: cs(".cm-md-quote", "borderLeftWidth"), color: cs(".cm-md-quote", "color") },
    fence: { bg: cs(".cm-md-fence", "backgroundColor"), pad: cs(".cm-md-fence", "paddingLeft") },
    th: { border: cs("table.cm-md-table th", "borderTopWidth"), pad: cs("table.cm-md-table th", "paddingLeft"), weight: cs("table.cm-md-table th", "fontWeight") },
    tdEven: cs("table.cm-md-table tbody tr:nth-child(even) td", "backgroundColor"),
    hasLightClass: document.documentElement.classList.contains("theme-light"),
    tbl: { table: !!document.querySelector("table.cm-md-table"), editCell: document.querySelector("td.cm-md-cell-edit")?.textContent ?? null,
      bar: !!document.querySelector("td .cm-vim-bar"), block: document.querySelector("td .cm-vim-block")?.textContent ?? null, rawLine: document.querySelector(".cm-content").textContent.includes("| 3 | 4 |") },
    cursor: (() => { const e = document.querySelector(".cm-vim-block"); if (!e) return null; const c = getComputedStyle(e); return { text: e.textContent, color: c.color, bg: c.backgroundColor, inLink: !!e.closest(".cm-md-link") || !!e.querySelector(".cm-md-link") }; })(),
    cursorLink: (() => { const e = document.querySelector(".cm-vim-block"); return e ? { text: e.textContent, inLink: !!e.closest(".cm-md-link") } : null; })(),
    barLink: (() => { const e = document.querySelector(".cm-vim-bar"); return e ? { visible: e.getBoundingClientRect().width >= 0 && e.getBoundingClientRect().height > 0, prev: e.previousSibling ? e.previousSibling.textContent.slice(-1) : "" } : null; })(),
    hint: (() => { const e = document.querySelector(".cm-vtext"); if (!e) return null; const c = getComputedStyle(e); return { color: c.color, bg: c.backgroundColor }; })(),
  };
  document.title = "RESULT=" + JSON.stringify(out);
}, 500);
`);
fs.writeFileSync(path.join(tmp, "index.html"),
  `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="${path.join(web, "styles.css")}"><title>x</title></head><body style="background:var(--bg);color:var(--fg)"><script src="bundle.js"></script></body></html>`);
execFileSync(path.join(web, "node_modules/.bin/esbuild"), [path.join(tmp, "entry.js"), "--bundle", "--format=iife", "--target=chrome100", `--outfile=${path.join(tmp, "bundle.js")}`, "--log-level=error"]);

function findChrome() {
  const b = path.join(os.homedir(), ".cache/ms-playwright");
  if (fs.existsSync(b)) for (const d of fs.readdirSync(b)) if (d.startsWith("chromium-")) { const c = path.join(b, d, "chrome-linux64/chrome"); if (fs.existsSync(c)) return c; }
  for (const c of ["chromium", "chromium-browser", "google-chrome"]) { try { return execFileSync("which", [c], { encoding: "utf8" }).trim(); } catch { /* next */ } }
  return null;
}
const chrome = findChrome();
if (!chrome) { console.error("SKIP: chromium が無いので省略"); fs.rmSync(tmp, { recursive: true, force: true }); process.exit(0); }
const url = (t, sc = "") => "file://" + path.join(tmp, "index.html") + "?t=" + t + (sc ? "&s=" + sc : "");
const dump = (t, sc = "") => {
  const dom = execFileSync(chrome, ["--headless=new", "--no-sandbox", "--disable-gpu", "--allow-file-access-from-files", "--window-size=1200,1000", "--virtual-time-budget=5000", "--dump-dom", url(t, sc)],
    { encoding: "utf8", maxBuffer: 32 * 1024 * 1024, stdio: ["ignore", "pipe", "ignore"] });
  const m = /<title>RESULT=(.*?)<\/title>/s.exec(dom);
  if (!m) throw new Error("no RESULT (" + t + ")");
  return JSON.parse(m[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">"));
};
let failed = 0;
const check = (ok, msg) => { if (!ok) { console.error("FAIL: " + msg); failed = 1; } };
try {
  const L = dump("light"), D = dump("dark"), TI = dump("light", "tbl-i"), TN = dump("dark", "tbl-n"), LO = dump("light", "lk-open"), LU = dump("light", "lk-url"), LUI = dump("dark", "lk-url-i");
  // ライト = GitHub スタイル（Markdown Viewer 拡張の既定）
  check(L.hasLightClass, "light: html.theme-light が付く");
  check(L.bodyBg === "rgb(255, 255, 255)", "light: 背景は白 " + L.bodyBg);
  check(L.contentMaxWidth === "980px" && L.contentPad === "45px", "light: 本文の幅 980px・余白 45px " + L.contentMaxWidth + " " + L.contentPad);
  check(L.lineHeight === "24px", "light: 行間 1.5（16px → 24px） " + L.lineHeight);
  check(/Segoe UI|Helvetica|Noto Sans/.test(L.fontFamily) && !/^"?Noto Sans JP"?,/.test(L.fontFamily), "light: GitHub のフォントスタック " + L.fontFamily);
  check(L.h1.size === "32px" && L.h1.weight === "600" && L.h1.border === "1px solid", "light: h1 は 2em・太さ 600・下線 " + JSON.stringify(L.h1));
  check(L.h1.color === L.bodyColor, "light: 見出しは本文と同じ色（茶色にしない） " + L.h1.color + " / " + L.bodyColor);
  check(L.h2.size === "24px" && L.h2.border === "1px", "light: h2 は 1.5em・下線 " + JSON.stringify(L.h2));
  check(L.h3.size === "20px" && L.h3.border === "0px", "light: h3 は 1.25em・下線なし " + JSON.stringify(L.h3));
  check(L.code.bg === "rgba(129, 139, 152, 0.12)" && L.code.pad === "5.44px", "light: インラインコード " + JSON.stringify(L.code));
  check(L.link === "rgb(9, 105, 218)", "light: リンクは #0969DA " + L.link);
  check(L.quote.border === "4px" && L.quote.color === "rgb(89, 99, 110)", "light: 引用は左線 .25em・#59636E " + JSON.stringify(L.quote));
  check(L.fence.bg === "rgb(246, 248, 250)" && L.fence.pad === "16px", "light: コードブロック " + JSON.stringify(L.fence));
  check(L.th.border === "1px" && L.th.pad === "13px" && L.th.weight === "600", "light: 表のセル " + JSON.stringify(L.th));
  check(L.tdEven === "rgb(246, 248, 250)", "light: 表の偶数行 " + L.tdEven);
  // カーソルがリンクの上でも、文字が読める（背景 = 本文色・文字 = 背景色）。番号の札は CUI ダークと同じ灰色と黒（赤・橙にしない）
  check(L.cursor && L.cursor.bg === "rgb(31, 35, 40)" && L.cursor.color === "rgb(255, 255, 255)", "light: カーソルは本文色の塊に背景色の文字 " + JSON.stringify(L.cursor));
  check(L.hint && L.hint.bg === "rgb(179, 179, 179)" && L.hint.color === "rgb(30, 30, 30)", "light: 番号の札は灰色（#B3B3B3）と黒（#1E1E1E） " + JSON.stringify(L.hint));
  check(D.hint && D.hint.bg === "rgb(179, 179, 179)" && D.hint.color === "rgb(30, 30, 30)", "dark: 番号の札は CUI ダークと同じ " + JSON.stringify(D.hint));
  check(D.cursor && D.cursor.bg === "rgb(218, 218, 218)" && D.cursor.color === "rgb(30, 30, 30)", "dark: カーソルは本文色の塊 " + JSON.stringify(D.cursor));
  check(L.bodyColor === "rgb(31, 35, 40)", "light: 本文は #1F2328（GitHub） " + L.bodyColor);
  // 表: 挿入モードでも、カーソルが表の中にあっても、表の見た目のまま（元の | の行にならない）。カーソルはセルの中の文字の位置に出る
  check(TI.tbl.table && !TI.tbl.rawLine && TI.tbl.bar && TI.tbl.editCell === "3", "table: insert mode keeps the table look and shows the bar cursor in the cell " + JSON.stringify(TI.tbl));
  check(TN.tbl.table && !TN.tbl.rawLine && TN.tbl.block === "3", "table: normal mode with the cursor inside keeps the table look and shows the block cursor on the char " + JSON.stringify(TN.tbl));
  check(L.tbl.table && !L.tbl.bar && L.tbl.editCell === null, "table: cursor outside the table = formatted table " + JSON.stringify(L.tbl));
  // リンクの隠れた文字（`[` と `](ファイル)`）の上にカーソルがあっても、見えている名前の上にカーソルが出る（Tab でリンクに移ったとき）
  check(LO.cursorLink && LO.cursorLink.text === "リ", "link: cursor on the hidden `[` is shown on the first visible char " + JSON.stringify(LO.cursorLink));
  check(LU.cursorLink && LU.cursorLink.text === "先", "link: cursor inside the hidden `](url)` is shown on the last visible char " + JSON.stringify(LU.cursorLink));
  check(LUI.barLink && LUI.barLink.visible && LUI.barLink.prev === "先", "link: insert cursor inside the hidden part is shown right after the name " + JSON.stringify(LUI.barLink));
  // ダークは変えない（従来の見え方）
  check(!D.hasLightClass, "dark: html.theme-light は付かない");
  check(D.contentMaxWidth === "860px", "dark: 本文の幅は従来どおり 860px " + D.contentMaxWidth);
  check(D.h1.weight === "700", "dark: 見出しの太さは従来どおり " + D.h1.weight);
  check(D.lineHeight === "28.8px", "dark: 行間は従来どおり 1.8 " + D.lineHeight);
  if (process.env.LOOK_SHOT) {
    fs.mkdirSync(process.env.LOOK_SHOT, { recursive: true });
    for (const t of ["light", "dark"]) {
      execFileSync(chrome, ["--headless=new", "--no-sandbox", "--disable-gpu", "--allow-file-access-from-files", "--window-size=1200,1000", "--virtual-time-budget=5000",
        `--screenshot=${path.join(process.env.LOOK_SHOT, t + ".png")}`, url(t)], { stdio: "ignore" });
    }
  }
  if (!failed) console.log("look e2e: OK (ライトは GitHub スタイル（Markdown Viewer 拡張と同じ）・ダークは従来どおり)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
process.exit(failed);
