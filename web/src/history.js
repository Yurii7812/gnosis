// GUI 編集モードの「元に戻す／やり直す」。文書の全体を覚える簡単な履歴（ノートは短いので十分）。
// 近い時間（既定 700ms）の連続した編集は 1 つの段にまとめる。上限を超えたら古い方から捨てる。
export function createHistory({ limit = 200, group = 700 } = {}) {
  let undo = [];   // [{ doc, time }]  … 戻る先の文書
  let redo = [];
  let lastTime = 0;
  return {
    // 変更の前の文書 prev を覚える（ユーザーの編集のたびに呼ぶ）
    // prev は文字列、または文字列を返す関数（まとめる編集のときは呼ばない。毎回の入力で文書全体を文字列にしないため）
    record(prev, now = Date.now()) {
      if (undo.length && now - lastTime < group) { lastTime = now; return; }   // 同じ段にまとめる（段の頭の文書を残す）
      undo.push({ doc: typeof prev === "function" ? prev() : prev });
      if (undo.length > limit) undo.shift();
      redo = [];
      lastTime = now;
    },
    canUndo: () => undo.length > 0,
    canRedo: () => redo.length > 0,
    // 戻る。今の文書 current を redo に積み、戻り先の文書を返す（無ければ null）
    undo(current) {
      const s = undo.pop();
      if (!s) return null;
      redo.push({ doc: current });
      lastTime = 0;
      return s.doc;
    },
    redo(current) {
      const s = redo.pop();
      if (!s) return null;
      undo.push({ doc: current });
      lastTime = 0;
      return s.doc;
    },
    // 文書が入れ替わったとき（別のノートを開いた・読み直した）は履歴を捨てる
    reset() { undo = []; redo = []; lastTime = 0; },
    size: () => undo.length,
  };
}
