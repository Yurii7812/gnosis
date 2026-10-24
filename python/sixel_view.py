#!/usr/bin/env python3
"""ノートの画像を sixel で端末に出すための補助（Vim のポップアップから呼ぶ）。

  list   NOTE.md [TEXTFILE]      … ノート内の画像を JSON で（path / label / exists）。
                                   TEXTFILE があれば本文はそちらから読む（Vim の未保存の内容）
  render IMAGE COLS ROWS         … 1 行目に「幅セル 高さセル」、2 行目以降に sixel 本体
  cell                           … 端末の 1 セルのピクセル「幅x高さ」
  inline CACHEDIR MAXCOLS MAXROWS IMAGE…
                                 … ノートの中に画像を出すための下ごしらえ。画像ごとに sixel を CACHEDIR に作り
                                   （同じ画像・大きさなら作り直さない）、JSON {画像: {cols, rows, file}} を出す

セルの大きさは /dev/tty の ioctl（TIOCGWINSZ）から取る。取れなければ環境変数
GNOSIS_CELL_PX（例 10x20）、それも無ければ 10x20。端末へは何も問い合わせない
（Vim が端末を使っている最中に応答が混ざらないようにするため）。
"""
import json
import os
import sys
from pathlib import Path

ESC = "\x1b"
DEFAULT_CELL = (10, 20)


def cell_px():
    env = os.environ.get("GNOSIS_CELL_PX", "")
    try:
        w, h = env.lower().split("x")
        if int(w) > 0 and int(h) > 0:
            return int(w), int(h)
    except ValueError:
        pass
    try:
        import fcntl
        import struct
        import termios

        fd = os.open("/dev/tty", os.O_RDONLY)
        try:
            rows, cols, xpx, ypx = struct.unpack("HHHH", fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8))
        finally:
            os.close(fd)
        if cols and rows and xpx and ypx:
            return max(1, xpx // cols), max(1, ypx // rows)
    except (OSError, ImportError):
        pass
    return DEFAULT_CELL


def list_images(note, textfile=None):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import gallery

    note_path = Path(note).resolve()
    text = Path(textfile or note_path).read_text(encoding="utf-8", errors="replace")
    out = []
    for item in gallery.iter_markdown_images(note_path, text):
        p = Path(str(item["path"]))
        out.append({"path": str(p), "label": p.name, "exists": p.is_file()})
    return out


def _run(prev, run):
    ch = chr(63 + prev)
    return f"!{run}{ch}" if run > 3 else ch * run


def to_sixel(img, colors=128):
    from PIL import Image

    img = img.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
    w, h = img.size
    pal = img.getpalette()
    px = img.load()
    out = [f'{ESC}P0;1;0q"1;1;{w};{h}']
    for i in sorted(set(img.tobytes())):
        r, g, b = pal[i * 3: i * 3 + 3]
        out.append(f"#{i};2;{r * 100 // 255};{g * 100 // 255};{b * 100 // 255}")
    for y0 in range(0, h, 6):
        rows = range(y0, min(y0 + 6, h))
        bits = {}
        for x in range(w):
            for k, y in enumerate(rows):
                c = px[x, y]
                a = bits.get(c)
                if a is None:
                    a = bits[c] = [0] * w
                a[x] |= 1 << k
        first = True
        for c, a in bits.items():
            if not first:
                out.append("$")
            first = False
            out.append(f"#{c}")
            run, prev = 0, None
            for v in a:
                if v == prev:
                    run += 1
                    continue
                if prev is not None:
                    out.append(_run(prev, run))
                prev, run = v, 1
            out.append(_run(prev, run))
        out.append("-")
    out.append(ESC + "\\")
    return "".join(out)


def _fit(path, cols, rows, colors):
    """画像を cols×rows セルに収まる大きさに縮めて (幅セル, 高さセル, sixel) を返す（拡大はしない）"""
    from PIL import Image, ImageOps

    cw, ch = cell_px()
    img = ImageOps.exif_transpose(Image.open(path))
    img.thumbnail((max(cw, cols * cw), max(ch, rows * ch)))
    w, h = img.size
    # sixel は 6 行単位。端末のセルに収まる大きさに切り上げた分を使う
    return -(-w // cw), -(-h // ch), to_sixel(img, colors)


def render(path, cols, rows):
    cells_w, cells_h, six = _fit(path, cols, rows, 128)
    return f"{cells_w} {cells_h}\n" + six


def inline(cache_dir, cols, rows, paths):
    import hashlib

    cache = Path(cache_dir)
    cache.mkdir(parents=True, exist_ok=True)
    cw, ch = cell_px()
    out = {}
    for p in paths:
        try:
            st = os.stat(p)
            key = hashlib.sha1(f"{p}|{st.st_mtime_ns}|{st.st_size}|{cols}x{rows}|{cw}x{ch}".encode()).hexdigest()
            meta = cache / (key + ".json")
            six = cache / (key + ".six")
            if not (meta.is_file() and six.is_file()):
                c, r, data = _fit(p, cols, rows, 64)
                six.write_text(data, encoding="latin-1")
                meta.write_text(json.dumps({"cols": c, "rows": r}), encoding="utf-8")
            m = json.loads(meta.read_text(encoding="utf-8"))
            out[p] = {"cols": m["cols"], "rows": m["rows"], "file": str(six)}
        except Exception:
            continue
    return out


def main(argv):
    if len(argv) >= 3 and argv[1] == "list":
        print(json.dumps(list_images(argv[2], argv[3] if len(argv) > 3 else None), ensure_ascii=False))
    elif len(argv) >= 5 and argv[1] == "render":
        sys.stdout.write(render(argv[2], int(argv[3]), int(argv[4])))
    elif len(argv) >= 6 and argv[1] == "inline":
        print(json.dumps(inline(argv[2], int(argv[3]), int(argv[4]), argv[5:]), ensure_ascii=False))
    elif len(argv) >= 2 and argv[1] == "cell":
        print("%dx%d" % cell_px())
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
