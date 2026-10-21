// コマンドパレットの検索・順位付け（DOM に触れない純関数）。
// クエリの文字が、ラベル（とキーワード）に順に現れれば一致。語頭・連続・短いほど高得点。空白で区切った語はすべて一致が必要。
export function score(query, text) {
  const q = query.toLowerCase(), s = text.toLowerCase();
  if (!q) return 0;
  let pos = 0, total = 0, prev = -2;
  for (const ch of q) {
    const k = s.indexOf(ch, pos);
    if (k < 0) return -1;
    total += 10 + (k === prev + 1 ? 15 : 0) + (k === 0 || /[\s:_\-/（(]/.test(s[k - 1]) ? 10 : 0);
    prev = k; pos = k + 1;
  }
  return total - Math.floor(s.length / 4);
}

export function rank(items, query, limit = 60) {
  const terms = query.trim().split(/\s+/).filter(Boolean);
  if (!terms.length) return items.slice(0, limit);
  const out = [];
  items.forEach((it, i) => {
    const hay = it.label + " " + (it.keywords || "") + " " + (it.group || "");
    let sum = 0;
    for (const t of terms) {
      const a = score(t, it.label), b = score(t, hay);
      const best = Math.max(a >= 0 ? a + 20 : -1, b);       // ラベルに当たったものを優先
      if (best < 0) { sum = -1; break; }
      sum += best;
    }
    if (sum >= 0) out.push({ it, sum, i });
  });
  return out.sort((x, y) => y.sum - x.sum || x.i - y.i).slice(0, limit).map((o) => o.it);
}

// Vim の Gnosis コマンド名（GnosisCaptureImport）を、読みやすい見出しにする（Gnosis を除き、単語の区切りで分ける）
export function vimLabel(name) {
  return ":" + name;
}
