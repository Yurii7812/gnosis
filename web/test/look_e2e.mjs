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
const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
fs.mkdirSync(base, { recursive: true });
const tmp = fs.mkdtempSync(path.join(base, "look-e2e-"));
const pal = JSON.parse(fs.readFileSync(path.join(repo, "assets", "themes", "builtin.json"), "utf8"));

const DOC = `# 見出し 1

本文の段落です。**太字**・*斜体*・\`inline code\`・[リンク](a.md) を含みます。

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
const PAL = ${JSON.stringify(pal)};
const params = new URLSearchParams(location.search);
const which = params.get("t") === "dark" ? "dark" : "light";
const p = PAL[which];
const r = document.documentElement.style;
const dark = p.base === "dark";
r.setProperty("--bg", p.bg); r.setProperty("--fg", p.fg); r.setProperty("--link", p.link); r.setProperty("--heading", p.heading);
r.setProperty("--subheading", p.subheading || p.heading); r.setProperty("--selection", p.selection);
r.setProperty("--bg-2", "color-mix(in srgb, " + p.fg + " " + (dark ? 8 : 4) + "%, " + p.bg + ")");
r.setProperty("--fg-dim", "color-mix(in srgb, " + p.fg + " 62%, " + p.bg + ")");
r.setProperty("--line", "color-mix(in srgb, " + p.fg + " " + (dark ? 22 : 18) + "%, " + p.bg + ")");
document.documentElement.classList.toggle("theme-light", !dark);
document.documentElement.classList.toggle("theme-dark", dark);
const v = createView({ parent: document.body, getImageURL: () => null });
v.setText(${JSON.stringify(DOC)});
v.setVim({ cur: [28, 1], mode: "n" });   // カーソルは最後の行（ほかの行は全部「描いた見た目」になる）
const cs = (sel, prop) => { const e = document.querySelector(sel); return e ? getComputedStyle(e)[prop] : null; };
setTimeout(() => {
  const out = {
    bodyBg: getComputedStyle(document.body).backgroundColor,
    contentMaxWidth: cs(".cm-content", "maxWidth"), contentPad: cs(".cm-content", "paddingLeft"),
    lineHeight: cs(".cm-scroller", "lineHeight"),
    fontFamily: cs(".cm-scroller", "fontFamily"),
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
const url = (t) => "file://" + path.join(tmp, "index.html") + "?t=" + t;
const dump = (t) => {
  const dom = execFileSync(chrome, ["--headless=new", "--no-sandbox", "--disable-gpu", "--allow-file-access-from-files", "--window-size=1200,1000", "--virtual-time-budget=5000", "--dump-dom", url(t)],
    { encoding: "utf8", maxBuffer: 32 * 1024 * 1024, stdio: ["ignore", "pipe", "ignore"] });
  const m = /<title>RESULT=(.*?)<\/title>/s.exec(dom);
  if (!m) throw new Error("no RESULT (" + t + ")");
  return JSON.parse(m[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">"));
};
let failed = 0;
const check = (ok, msg) => { if (!ok) { console.error("FAIL: " + msg); failed = 1; } };
try {
  const L = dump("light"), D = dump("dark");
  // 2026-10-21〜 ライトもダークも Obsidian の組版（DECISIONS D008）: 行の幅 700px（＋余白 32px×2）・行間 1.5・見出し 1.618/1.462/1.318em の太字で本文の色・下線なし
  for (const [n, X, fg] of [["light", L, "rgb(34, 34, 34)"], ["dark", D, "rgb(218, 218, 218)"]]) {
    check(X.contentMaxWidth === "764px" && X.contentPad === "32px", n + ": 行の幅 700px（＋余白 32px） " + X.contentMaxWidth + " " + X.contentPad);
    check(X.lineHeight === "24px", n + ": 行間 1.5（16px → 24px） " + X.lineHeight);
    check(/ui-sans-serif/.test(X.fontFamily) && /Noto Sans JP/.test(X.fontFamily), n + ": Obsidian のフォントの並び（日本語は Noto Sans JP） " + X.fontFamily);
    check(X.h1.size === "25.888px" && X.h1.weight === "700" && X.h1.border === "0px none", n + ": h1 は 1.618em・太字・下線なし " + JSON.stringify(X.h1));
    check(X.h1.color === fg && X.h3.color === fg, n + ": 見出しは本文と同じ色 " + X.h1.color + " " + X.h3.color);
    check(X.h2.size === "23.392px" && X.h2.border === "0px" && X.h3.size === "21.088px", n + ": h2 1.462em・h3 1.318em " + JSON.stringify([X.h2, X.h3]));
    check(X.quote.border === "2px", n + ": 引用は左の細い線 " + JSON.stringify(X.quote));
    check(X.th.weight === "700" && X.tdEven === "rgba(0, 0, 0, 0)", n + ": 表は縞なし " + JSON.stringify([X.th, X.tdEven]));
  }
  check(L.hasLightClass && !D.hasLightClass, "html.theme-light はライトだけ");
  check(L.bodyBg === "rgb(255, 255, 255)" && D.bodyBg === "rgb(30, 30, 30)", "背景はライト白・ダーク #1E1E1E " + L.bodyBg + " " + D.bodyBg);
  check(L.link === "rgb(9, 105, 218)" && D.link === "rgb(108, 182, 255)", "リンクの色は今までどおり " + L.link + " " + D.link);
  if (process.env.LOOK_SHOT) {
    fs.mkdirSync(process.env.LOOK_SHOT, { recursive: true });
    for (const t of ["light", "dark"]) {
      execFileSync(chrome, ["--headless=new", "--no-sandbox", "--disable-gpu", "--allow-file-access-from-files", "--window-size=1200,1000", "--virtual-time-budget=5000",
        `--screenshot=${path.join(process.env.LOOK_SHOT, t + ".png")}`, url(t)], { stdio: "ignore" });
    }
  }
  if (!failed) console.log("look e2e: OK (ライトもダークも Obsidian の組版・リンクの色は今までどおり)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
process.exit(failed);
