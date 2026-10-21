// 書き出した静的サイトの追加ビュー（python/export_views2.py の VIEWS と同じ。test/extra_views_test.mjs が食い違いを検出する）。
// `\A` ではタブの種類 "v2"（params.key = ここのキー）として iframe に入れる。表示専用で、ノートは書き換えない。
export const EXTRA_VIEWS = [
  ["tree", "階層ツリー"],
  ["mindmap", "マインドマップ"],
  ["sunburst", "Sunburst"],
  ["treemap", "Treemap"],
  ["matrix", "隣接行列"],
  ["sankey", "Sankey"],
  ["compare", "比較"],
  ["orphans", "孤立・未参照・未索引"],
  ["kanban", "カンバン"],
  ["growth", "成長"],
  ["river", "ストーリーリバー"],
  ["map", "地図"],
  ["graph3d", "3D グラフ"],
  ["slides", "スライド"],
  ["whiteboard", "ホワイトボード"],
  ["gallery", "ギャラリー"],
  ["museum", "知識の博物館"],
  ["palace", "記憶の宮殿"],
  ["maze", "思考の迷路"],
  ["timelapse", "成長アニメーション"],
  ["ideas", "アイデア合成器"],
  ["hypotheses", "仮説実験室"],
  ["debate", "思考の対戦"],
];
export const EXTRA_KEYS = new Set(EXTRA_VIEWS.map((v) => v[0]));
export const extraTitle = (key) => (EXTRA_VIEWS.find((v) => v[0] === key) || [key, key])[1];
