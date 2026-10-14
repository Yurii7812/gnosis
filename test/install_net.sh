#!/bin/sh
# インストーラー（install/install.sh）の回帰網。一時フォルダの HOME で動かす（本物の HOME には触らない）。
#   - HOME・Gnosis のフォルダに空白・日本語・' を含める
#   - プラグインはこのマシンにある git リポジトリから取る（GNOSIS_PLUGIN_MIRROR。ネットに出ない）
#   - OS のパッケージは入れない（--no-system）。アプリは入れない（--no-app）
# 確かめること: 専用 vimrc とプラグイン領域ができる / ランチャーとアプリメニュー（アイコン付き）ができる /
#   ふだんの ~/.vimrc・~/.vim は変わらず、Gnosis の Vim はそれを読まない / ふつうの vim はそれを読む
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
H="$WORK/ホーム o'neil"
G="$WORK/Gnosis 本体's"
mkdir -p "$H" "$G" "$WORK/mirror"
fail() { echo "NG: install: $1" >&2; exit 1; }

# プラグインの代わりのリポジトリ（このマシンにあるもの。無ければ最小のものを作る）
for name in fzf fzf.vim vim-surround; do
  src=""
  for b in "$HOME/.local/share/gnosis/plugins" "$HOME/.vim-simple-yurii-note"; do
    [ -d "$b/$name/.git" ] && { src="$b/$name"; break; }
  done
  if [ -n "$src" ]; then
    git clone --quiet --depth 1 "file://$src" "$WORK/mirror/$name" 2>/dev/null || git clone --quiet "$src" "$WORK/mirror/$name"
  else
    mkdir -p "$WORK/mirror/$name/plugin" && echo '" dummy' > "$WORK/mirror/$name/plugin/$name.vim"
    git -C "$WORK/mirror/$name" init -q && git -C "$WORK/mirror/$name" add -A && git -C "$WORK/mirror/$name" -c user.email=t@t -c user.name=t commit -qm t
  fi
done
# Gnosis 本体（この作業中のもの）を、空白・日本語・' を含む場所へ
git -C "$REPO" ls-files -z | (cd "$REPO" && xargs -0 tar cf -) | (cd "$G" && tar xf -)

# ふだんの Vim の設定（変わらないこと・Gnosis が読まないことを確かめる）
printf 'let g:user_vimrc_loaded = 1\n' > "$H/.vimrc"
mkdir -p "$H/.vim/plugin" "$H/.vim/pack/p/start/x/plugin"
printf 'let g:user_plugin_loaded = 1\n' > "$H/.vim/plugin/mine.vim"
printf 'let g:user_pack_loaded = 1\n' > "$H/.vim/pack/p/start/x/plugin/x.vim"
before=$(cd "$H" && find .vimrc .vim -type f -exec md5sum {} + | sort)

# 前の別の場所へのインストール（古いランチャーと、古い形式のアプリメニュー項目）と、既存の vault
mkdir -p "$H/.local/bin" "$H/.local/share/applications" "$H/vault"
printf "#!/bin/sh\nGNOSIS_HOME='%s'\nexport GNOSIS_HOME\nexec '%s' \"\$@\"\n" "$H/.local/share/gnosis" "$WORK/old-gnosis/bin/gnosis" > "$H/.local/bin/gnosis"
chmod +x "$H/.local/bin/gnosis"
printf '[Desktop Entry]\nType=Application\nName=Gnosis\nExec="%s" %%F\nTerminal=false\nStartupWMClass=Gnosis\n' "$H/.local/bin/gnosis" > "$H/.local/share/applications/gnosis.desktop"
printf -- '---\ntitle: Index\n---\n\n# Index\n[メモ](m.md)\n' > "$H/vault/index.md"
printf -- '---\ntitle: メモ\n---\n\n# メモ\n大事な本文\n' > "$H/vault/m.md"
vault_before=$(cd "$H/vault" && find . -type f -exec md5sum {} + | sort)

# 必須のもの（Python 3）が無ければ、成功と言わずに終わる
mkdir -p "$WORK/nopy"
for f in /usr/bin/* /bin/*; do
  b=$(basename "$f"); case "$b" in python*) continue ;; esac
  [ -e "$WORK/nopy/$b" ] || ln -s "$f" "$WORK/nopy/$b"
done
if HOME="$H" XDG_DATA_HOME= GNOSIS_HOME= GNOSIS_PLUGIN_MIRROR="$WORK/mirror" PATH="$WORK/nopy" LANG=ja_JP.UTF-8 \
  sh "$G/install/install.sh" --yes --no-system --no-app --no-update >"$WORK/nopy.log" 2>&1; then
  cat "$WORK/nopy.log" >&2; fail "Python が無いのに成功と表示した"
fi
grep -q '必須のものが足りない' "$WORK/nopy.log" || { cat "$WORK/nopy.log" >&2; fail "必須のものが足りない説明が無い"; }
grep -q '^完了' "$WORK/nopy.log" && fail "Python が無いのに完了と表示した"

HOME="$H" XDG_DATA_HOME= GNOSIS_HOME= GNOSIS_PLUGIN_MIRROR="$WORK/mirror" PATH="$PATH" LANG=ja_JP.UTF-8 \
  sh "$G/install/install.sh" --yes --no-system --no-app --no-venv --no-update >"$WORK/install.log" 2>&1 || { cat "$WORK/install.log" >&2; fail "install.sh が失敗した"; }
grep -q "$WORK/old-gnosis/bin/gnosis" "$WORK/install.log" || fail "前のインストール先からの切り替えを知らせていない"
grep -q "インストール先" "$WORK/install.log" && grep -q "コミット" "$WORK/install.log" || fail "最後の要約（インストール先・コミット）が無い"

GH="$H/.local/share/gnosis"
[ -f "$GH/vimrc" ] || fail "専用 vimrc が無い"
for p in fzf fzf.vim vim-surround; do [ -d "$GH/plugins/$p" ] || fail "プラグイン $p が無い"; done
[ -x "$H/.local/bin/gnosis" ] || fail "ランチャーが無い"
[ -f "$H/.local/share/applications/gnosis.desktop" ] || fail "アプリメニューの項目が無い"
[ -f "$H/.local/share/icons/hicolor/256x256/apps/gnosis.png" ] || fail "アイコンが無い"
after=$(cd "$H" && find .vimrc .vim -type f -exec md5sum {} + | sort)
[ "$before" = "$after" ] || fail "ふだんの ~/.vimrc・~/.vim が変わった"
[ ! -e "$H/.gvimrc" ] && [ ! -e "$H/.vim/autoload/plug.vim" ] || fail "~/.gvimrc や ~/.vim に何か作られた"

# ランチャー: 空白・日本語・' を含むパスでも正しい場所を指す
where=$(HOME="$H" "$H/.local/bin/gnosis" --where)
printf '%s\n' "$where" | grep -qxF "Gnosis:        $G" || fail "ランチャーの Gnosis の場所: $where"
printf '%s\n' "$where" | grep -qxF "vimrc:         $GH/vimrc" || fail "ランチャーの vimrc: $where"

# アプリメニューの Exec を規則どおりに読むと、ランチャーを指す
python3 - "$H/.local/share/applications/gnosis.desktop" "$H/.local/bin/gnosis" <<'PY' || fail "desktop の Exec が読めない"
import re, sys
line = next(l for l in open(sys.argv[1], encoding="utf-8") if l.startswith("Exec="))[5:].rstrip("\n")
# 値の \\ を戻してから、二重引用符の中の \" \` \$ \\ を戻す
val = re.sub(r"\\(.)", r"\1", line)
m = re.match(r'"((?:\\.|[^"\\])*)"', val)
arg0 = re.sub(r'\\([\\"`$])', r"\1", m.group(1))
assert arg0 == sys.argv[2], (arg0, sys.argv[2])
desktop = open(sys.argv[1], encoding="utf-8").read()
assert re.search(r"^Icon=/.*gnosis(-symbol)?\.svg$", desktop, re.M), desktop  # 絶対パスの SVG（配色に合わせて再生成したもの。アイコンテーマの更新を待たずに表示される）
assert "Terminal=false" in desktop, desktop
assert re.search(r"^Exec=.* --new-terminal %F$", desktop, re.M), desktop
assert "StartupWMClass" not in desktop
PY
HOME="$H" "$H/.local/bin/gnosis" --where | grep -qxF "launcher:      $G/bin/gnosis" || fail "ランチャーが今回のフォルダを指していない"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$H/.local/share/applications/gnosis.desktop" || fail "desktop-file-validate"
fi

# Gnosis の Vim: ふだんの設定を読まない。専用のプラグインを読む
HOME="$H" GNOSIS_HOME="$GH" timeout 30 vim -u "$GH/vimrc" -N -es \
  -c 'call writefile([exists("g:user_vimrc_loaded"), exists("g:user_plugin_loaded"), exists("g:user_pack_loaded"), get(g:, "gnosis_managed", 0), exists(":Files") || exists("g:loaded_fzf_vim"), exists("g:loaded_surround")], $GNOSIS_HOME . "/check.txt")' \
  -c 'qa!' </dev/null >/dev/null 2>&1 || true
[ "$(tr '\n' ' ' < "$GH/check.txt")" = "0 0 0 1 1 1 " ] || fail "Gnosis の Vim の読み込み（ふだん, plugin, pack, managed, fzf.vim, surround）: $(tr '\n' ' ' < "$GH/check.txt")"
# ふつうの vim は、今までどおりふだんの設定を読む
HOME="$H" timeout 30 vim -N --not-a-term -c 'call writefile([exists("g:user_vimrc_loaded"), exists("g:user_plugin_loaded"), exists("g:loaded_gnosis")], $HOME . "/plain.txt")' -c 'qa!' </dev/null >/dev/null 2>&1 || true
[ "$(tr '\n' ' ' < "$H/plain.txt")" = "1 1 0 " ] || fail "ふつうの vim の読み込み（ふだん, plugin, gnosis）: $(tr '\n' ' ' < "$H/plain.txt")"
rm -f "$H/plain.txt"

# もう一度入れても壊れない（プラグインは更新、vimrc は作り直し）
HOME="$H" XDG_DATA_HOME= GNOSIS_HOME= GNOSIS_PLUGIN_MIRROR="$WORK/mirror" LANG=C \
  PIP_NO_INDEX=1 sh "$G/install/install.sh" --yes --no-system --no-app --no-update >"$WORK/install2.log" 2>&1 || { cat "$WORK/install2.log" >&2; fail "2 回目の install.sh が失敗した"; }
vault_after=$(cd "$H/vault" && find . -type f -exec md5sum {} + | sort)
[ "$vault_before" = "$vault_after" ] || fail "インストーラーの再実行で vault が変わった"
after2=$(cd "$H" && find .vimrc .vim -type f -exec md5sum {} + | sort)
[ "$before" = "$after2" ] || fail "2 回目でふだんの ~/.vimrc・~/.vim が変わった"
echo "install OK (専用 vimrc・プラグイン領域・ランチャー・アプリメニュー・アイコン、ふだんの Vim は不変、空白・日本語・' を含むパス)"
