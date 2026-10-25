// 配色（palette）を CSS の変数に反映する。アプリ（app.js）と見た目の試験（test/look_e2e.mjs）で共有する。
// 基準は CUI（colors/gnosis.vim）: 本文 fg・補助の文字 muted・リンク link・見出し heading・強調 strong・リンクの番号の札は
// 「背景色の文字 × 補助色の札」（CUI のダークと同じ。ライトでも同じ灰色と黒にする）。

const mix = (a, b, pct) => `color-mix(in srgb, ${a} ${pct}%, ${b})`;

export function applyPalette(p, el = document.documentElement) {
  const r = el.style;
  const dark = p.base === "dark";
  r.setProperty("--bg", p.bg);
  r.setProperty("--fg", p.fg);
  r.setProperty("--link", p.link);
  r.setProperty("--accent", p.link);
  r.setProperty("--heading", p.heading);
  r.setProperty("--subheading", p.subheading || p.heading);
  r.setProperty("--selection", p.selection);
  r.setProperty("--cursorline", p.cursorline);
  r.setProperty("--bg-2", mix(p.fg, p.bg, dark ? 8 : 4));
  r.setProperty("--bg-3", mix(p.fg, p.bg, dark ? 14 : 8));
  // 補助の文字は CUI と同じ muted（無ければ fg と bg から作る）
  r.setProperty("--fg-dim", p.muted && /^#[0-9a-f]{6}$/i.test(p.muted) ? p.muted : mix(p.fg, p.bg, 62));
  r.setProperty("--line", mix(p.fg, p.bg, dark ? 22 : 18));
  // 強調（太字・斜体）: CUI は本文より明るく（ダーク）。ライトは GitHub と同じく本文と同じ色
  r.setProperty("--strong", dark ? `color-mix(in srgb, ${p.fg} 40%, #ffffff)` : p.fg);
  // リンクの番号の札: CUI ダークの GnosisLinkHint（文字=背景色・札=補助の色）。ライトも同じ灰色と黒（赤・橙にしない）
  const hex = (v) => (typeof v === "string" && /^#[0-9a-f]{6}$/i.test(v) ? v : "");
  r.setProperty("--hint-fg", dark ? hex(p.hintfg) || p.bg : hex(p.hintfg) || "#1e1e1e");
  r.setProperty("--hint-bg", dark ? hex(p.hintbg) || hex(p.muted) || mix(p.fg, p.bg, 62) : hex(p.hintbg) || "#b3b3b3");
  el.style.colorScheme = dark ? "dark" : "light";
  // ライトのときだけ、Markdown Viewer 拡張（GitHub スタイル）の見え方にする（styles.css の html.theme-light）
  el.classList.toggle("theme-light", !dark);
  el.classList.toggle("theme-dark", dark);
}
