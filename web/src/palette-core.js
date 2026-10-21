// コマンドパレットの検索・順位付け（DOM に触れない純関数）。
// クエリの文字が、ラベル（とキーワード）に順に現れれば一致。語頭・連続・短いほど高得点。空白で区切った語はすべて一致が必要。
// 日本語の検索用: 全角半角・大小文字をそろえ、カタカナをひらがなにする（「ぐらふ」で「グラフ」が見つかる）
export function fold(str) {
  return String(str).normalize("NFKC").toLowerCase().replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60));
}

// 漢字のラベルを、ひらがなで打って探せるようにする読み（ラベルに含まれる語の読みを、検索の対象に足す）。
// 漢字は読みを推測できないので、よく使う語だけ。足りない語は項目の keywords に直接書く。
const READINGS = {
  "索引": "さくいん", "索引語": "さくいんご", "探す": "さがす", "検索": "けんさく", "載せる": "のせる", "作る": "つくる", "新しい": "あたらしい",
  "日記": "にっき", "予定": "よてい", "曼荼羅": "まんだら まんだらーと", "機能": "きのう", "一覧": "いちらん", "番号": "ばんごう", "分析": "ぶんせき",
  "時間": "じかん", "時系列": "じけいれつ", "階層": "かいそう", "地図": "ちず", "成長": "せいちょう", "仮説": "かせつ", "実験": "じっけん", "記憶": "きおく",
  "宮殿": "きゅうでん", "迷路": "めいろ", "思考": "しこう", "対戦": "たいせん", "比較": "ひかく", "孤立": "こりつ", "未参照": "みさんしょう", "未索引": "みさくいん",
  "戻る": "もどる", "進む": "すすむ", "開く": "ひらく", "閉じた": "とじた", "再開": "さいかい", "分割": "ぶんかつ", "解除": "かいじょ", "右": "みぎ", "下": "した",
  "更新": "こうしん", "最新": "さいしん", "編集": "へんしゅう", "閲覧": "えつらん", "専用": "せんよう", "本物": "ほんもの", "太字": "ふとじ", "斜体": "しゃたい",
  "取り消し線": "とりけしせん", "見出し": "みだし", "箇条書き": "かじょうがき", "番号つき": "ばんごうつき", "引用": "いんよう", "切り替え": "きりかえ",
  "保存": "ほぞん", "元に戻す": "もとにもどす", "リンク": "りんく", "文脈": "ぶんみゃく", "親": "おや", "今日": "きょう", "今": "いま", "全部": "ぜんぶ", "表示": "ひょうじ",
  "隠す": "かくす", "出す": "だす", "起点": "きてん", "項目": "こうもく", "追加": "ついか", "既存": "きぞん", "選んで": "えらんで", "題": "だい", "夢": "ゆめ", "記録": "きろく",
};
const READING_KEYS = Object.keys(READINGS).sort((a, b) => b.length - a.length);
export function readings(label) {
  const out = [];
  for (const k of READING_KEYS) if (label.includes(k)) out.push(READINGS[k]);
  return out.join(" ");
}

export function score(query, text) {
  const q = fold(query), s = fold(text);
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
