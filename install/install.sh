#!/bin/sh
# Gnosis のインストーラー（Linux / macOS）。新しく入れるときも、更新するときも同じ。
#
#   新しく入れる:  git clone https://github.com/Yurii7812/gnosis.git && cd gnosis && ./install/install.sh
#   更新する:      cd <入れたフォルダ> && ./install/install.sh      （GitHub の新しい版があれば取り込んでから入れ直す）
#
# 行うこと（ふだんの ~/.vimrc・~/.vim・vimfiles・~/.vim/pack は読まない・変えない）:
#   0. このフォルダが GitHub の最新か確かめる。古ければ git pull --ff-only で自動更新する。
#      未コミットの変更があるときは安全のため停止する（変更は消さない）。
#   1. 必要なものを確かめ、無ければ OS のパッケージ管理（apt / dnf / pacman / zypper / Homebrew）で入れる（確認してから）
#        必須   … Vim 8.2 以上（+job +channel +timers +textprop +popupwin）・git・Python 3
#        推奨   … fzf（検索。無ければ Gnosis 専用に取得）・ripgrep（全文検索）・クリップボード
#                  （Wayland は wl-clipboard、X11 は +clipboard の Vim＝Debian では vim-gtk3 か xclip）
#        機能別 … 暗号化 vault: gocryptfs と FUSE（--with-crypt、または暗号化 vault が登録済みのとき）
#                  紙の日記の取り込み（\F）: tkinter と Pillow（--with-scan）
#      必須のものが足りないままなら、成功とは表示せずに終わる（終了コード 1）
#   2. Gnosis ホームに、Gnosis 専用の vimrc・プラグイン領域（fzf / fzf.vim / vim-surround）・
#      Python の仮想環境（venv。よみ順の並べ替えの pykakasi など python/requirements.txt）を作る
#   3. Electron は --app が指定されたときだけ入れる（標準では不要）
#   4. ランチャー（~/.local/bin/gnosis）と、アイコン付きの起動項目を作り直す（前のインストール先を指していても
#      今回のフォルダに向け直す）
#        Linux … アプリメニュー（~/.local/share/applications/gnosis.desktop）。端末の窓を開いて Vim を起動
#        macOS … ~/Applications/Gnosis.app
#   5. 何を入れたか（場所・コミット・最新か）を表示する。あとから確かめるときは gnosis --doctor
# ノート・vault・vault の設定・暗号化したデータには触れない。
#
# オプション:
#   --yes          確認せずに進める
#   --no-system    OS のパッケージを入れない（足りないものは表示だけ）
#   --no-update    GitHub の新しい版を取り込まない
#   --with-crypt   暗号化 vault 用のもの（gocryptfs・FUSE）も入れる
#   --with-scan    紙の日記の取り込み用のもの（tkinter・Pillow）も入れる
#   --no-venv      Python の仮想環境を作らない（pykakasi は入れない）
#   --app          オプションの Electron アプリを追加で入れる
#   --no-app       Electron を入れない（標準動作）
#   --desktop-icon Linux でデスクトップにもアイコンを置く
#   --bin DIR      ランチャーを置く場所（既定 ~/.local/bin）
#   --help
# 環境変数: GNOSIS_HOME（Gnosis ホーム）、GNOSIS_PLUGIN_MIRROR（プラグインを取ってくる場所。
#           既定は GitHub。試験やオフライン用に、fzf / fzf.vim / vim-surround を置いたフォルダを指定できる）
set -eu

YES=0; NO_SYSTEM=0; NO_APP=1; DESKTOP_ICON=0; NO_UPDATE=0; WITH_CRYPT=0; WITH_SCAN=0; NO_VENV=0
BIN_DIR="$HOME/.local/bin"
ORIG_ARGS="$*"
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --no-system) NO_SYSTEM=1 ;;
    --no-update) NO_UPDATE=1 ;;
    --with-crypt) WITH_CRYPT=1 ;;
    --with-scan) WITH_SCAN=1 ;;
    --no-venv) NO_VENV=1 ;;
    --app) NO_APP=0 ;;
    --no-app) NO_APP=1 ;;
    --desktop-icon) DESKTOP_ICON=1 ;;
    --bin) shift; BIN_DIR=$1 ;;
    -h|--help) sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "不明なオプション / unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

GNOSIS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OS=$(uname -s)
if [ -z "${GNOSIS_HOME:-}" ]; then
  if [ "$OS" = Darwin ]; then GNOSIS_HOME="$HOME/Library/Application Support/Gnosis"
  else GNOSIS_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/gnosis"; fi
fi
JA=0; case "${LC_ALL:-${LANG:-}}" in ja*) JA=1 ;; esac
say() { if [ "$JA" = 1 ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
step() { printf '\n== %s\n' "$( [ "$JA" = 1 ] && echo "$1" || echo "$2" )"; }
ask() {
  [ "$YES" = 1 ] && return 0
  printf '%s [Y/n] ' "$( [ "$JA" = 1 ] && echo "$1" || echo "$2" )"
  read -r ans || ans=n
  case "$ans" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}
have() { command -v "$1" >/dev/null 2>&1; }
# シェル用に一重引用符で囲む（' を含むパスでも安全）
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# Vim の一重引用符の文字列
vimq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"; }
# desktop entry の Exec の引数（二重引用符で囲み、" ` $ \ をエスケープ。値の \ もエスケープ）
deskq() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g' | sed 's/\\/\\\\/g')"; }

# ---------------------------------------------------------------- 0. 本体の版
# 通常の再インストールは最新版へ自動更新する。意図的に固定したい場合だけ --no-update。
# 更新に失敗した場合、古い版を「インストール成功」として処理しない。
IS_GIT=0
if have git && git -C "$GNOSIS_DIR" rev-parse --git-dir >/dev/null 2>&1; then IS_GIT=1; fi
UPTODATE="?"
if [ "$IS_GIT" = 1 ]; then
  step "Gnosis 本体の版を確かめます: $GNOSIS_DIR" "Checking the Gnosis version: $GNOSIS_DIR"
  up=$(git -C "$GNOSIS_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [ "$NO_UPDATE" = 1 ]; then
    # 自動更新した同じインストーラーから再実行された場合だけ、最新確認済みとする。
    if [ "${GNOSIS_JUST_UPDATED:-0}" = 1 ]; then UPTODATE=yes; fi
    say "  --no-update: GitHub から更新せずに現在の版をインストールします。" \
        "  --no-update: installing the current revision without updating from GitHub."
  elif [ -z "$up" ]; then
    say "  エラー: 追跡するリモートブランチがありません。git branch -vv を確認してください。" \
        "  ERROR: no upstream branch. Check git branch -vv."
    say "  更新しないで入れるには ./install/install.sh --no-update を指定してください。" \
        "  To install without updating, use ./install/install.sh --no-update."
    exit 1
  elif ! git -C "$GNOSIS_DIR" fetch --quiet; then
    say "  エラー: GitHub の更新確認に失敗しました。古い版のままインストールしません。" \
        "  ERROR: unable to fetch updates. Refusing to silently install an old revision."
    exit 1
  else
    behind=$(git -C "$GNOSIS_DIR" rev-list --count "HEAD..$up" 2>/dev/null || echo 0)
    ahead=$(git -C "$GNOSIS_DIR" rev-list --count "$up..HEAD" 2>/dev/null || echo 0)
    if [ "$behind" -eq 0 ]; then
      if [ "$ahead" -gt 0 ]; then
        say "  注意: リモートより $ahead コミット進んだローカル版です（取り消しません）。" \
            "  Note: local branch is $ahead commit(s) ahead of $up (preserving local commits)."
      else
        UPTODATE=yes
        say "  GitHub の $up と一致しています。" "  Up to date with $up."
      fi
    elif [ "$ahead" -gt 0 ]; then
      say "  エラー: ローカルと $up の履歴が分岐しています。自動で上書きしません。" \
          "  ERROR: local branch has diverged from $up. No automatic overwrite."
      exit 1
    elif [ -n "$(git -C "$GNOSIS_DIR" status --porcelain --untracked-files=no)" ]; then
      say "  エラー: ローカルの Git 管理対象ファイルが変更されています。安全のため更新を停止します。" \
          "  ERROR: tracked local files are modified; stopping update to preserve them."
      git -C "$GNOSIS_DIR" status --short
      say "  変更をコミット/退避後に再実行してください。古い版を使うなら --no-update。" \
          "  Commit or stash changes and rerun; use --no-update to intentionally install the old revision."
      exit 1
    else
      say "  $up より $behind コミット古いため自動更新します。" \
          "  $behind commit(s) behind $up; updating automatically."
      if git -C "$GNOSIS_DIR" pull --ff-only --quiet; then
        say "  更新しました。新しいインストーラーで続行します。" \
            "  Updated. Continuing with the new installer."
        export GNOSIS_JUST_UPDATED=1
        # shellcheck disable=SC2086
        exec sh "$GNOSIS_DIR/install/install.sh" --no-update $ORIG_ARGS
      fi
      say "  エラー: git pull --ff-only に失敗しました。古い版は入れません。" \
          "  ERROR: git pull --ff-only failed. Not installing the old revision."
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------- 1. 必要なもの
PM=""
if [ "$OS" = Darwin ]; then have brew && PM=brew
elif have apt-get; then PM=apt
elif have dnf; then PM=dnf
elif have pacman; then PM=pacman
elif have zypper; then PM=zypper
fi

pkg_name() { # 汎用名 → パッケージ名（空ならこの OS では入れない）
  case "$PM:$1" in
    dnf:vim) echo vim-enhanced ;;
    *:vim) echo vim ;;
    apt:vim-clip) echo vim-gtk3 ;;
    *:vim-clip) echo "" ;;
    pacman:python3|brew:python3) echo python ;;
    *:python3) echo python3 ;;
    apt:venv) echo python3-venv ;;
    *:venv) echo "" ;;
    pacman:pip) echo python-pip ;;
    brew:pip) echo "" ;;
    *:pip) echo python3-pip ;;
    apt:node|dnf:node|zypper:node|pacman:node) echo nodejs npm ;;
    brew:node) echo node ;;
    *:rg) echo ripgrep ;;
    brew:wl-clipboard|brew:xclip) echo "" ;;
    brew:gocryptfs|brew:fuse) echo "" ;;
    apt:fuse|pacman:fuse|zypper:fuse) echo fuse3 ;;
    dnf:fuse) echo fuse ;;
    apt:tk) echo python3-tk ;; dnf:tk) echo python3-tkinter ;; pacman:tk) echo tk ;; zypper:tk) echo python3-tk ;; brew:tk) echo python-tk ;;
    apt:pil) echo python3-pil ;; dnf:pil) echo python3-pillow ;; pacman:pil) echo python-pillow ;; zypper:pil) echo python3-Pillow ;; brew:pil) echo pillow ;;
    *) echo "$1" ;;
  esac
}

pm_install() {
  pkgs=""
  for p in "$@"; do pkgs="$pkgs $(pkg_name "$p")"; done
  pkgs=$(echo $pkgs)
  [ -n "$PM" ] && [ -n "$pkgs" ] || return 1
  SUDO=""; [ "$PM" = brew ] || [ "$(id -u)" = 0 ] || SUDO=sudo
  say "  実行: $SUDO $PM で $pkgs" "  running: $SUDO $PM for $pkgs"
  case "$PM" in
    apt) $SUDO apt-get update && $SUDO apt-get install -y $pkgs ;;
    dnf) $SUDO dnf install -y $pkgs ;;
    pacman) $SUDO pacman -S --needed --noconfirm $pkgs ;;
    zypper) $SUDO zypper install -y $pkgs ;;
    brew) brew install $pkgs ;;
  esac
}

# Gnosis に要る Vim か（Vim 8.2 以上で +job +channel +timers +textprop +popupwin）
vim_ok() {
  v=$1
  have "$v" || return 1
  out=$("$v" --version 2>/dev/null | head -40) || return 1
  for f in job channel timers textprop popupwin; do
    printf '%s' "$out" | grep -q "+$f" || return 1
  done
  ver=$(printf '%s' "$out" | sed -n 's/.*Vi IMproved \([0-9]*\)\.\([0-9]*\).*/\1 \2/p' | head -1)
  set -- $ver
  [ "${1:-0}" -gt 8 ] || { [ "${1:-0}" -eq 8 ] && [ "${2:-0}" -ge 2 ]; }
}
find_vim_ok() {
  for v in vim /usr/local/bin/vim /opt/homebrew/bin/vim; do
    if vim_ok "$v"; then command -v "$v" || echo "$v"; return 0; fi
  done
  return 1
}

# 登録済みの vault に暗号化 vault（.crypt）があれば、暗号化の道具も要る
crypt_in_use() {
  [ -f "$GNOSIS_HOME/vaults.json" ] && have python3 || return 1
  python3 - "$GNOSIS_HOME/vaults.json" <<'PY' 2>/dev/null
import json, os, sys
reg = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if any(os.path.isdir(os.path.join(v.get("path", ""), ".crypt")) for v in reg.get("vaults", [])) else 1)
PY
}

step "必要なものを確かめます" "Checking requirements"
required=""; recommended=""; feature=""
VIM_BIN=$(find_vim_ok || true)
if [ -n "$VIM_BIN" ]; then
  say "  必須  Vim: $VIM_BIN（使えます。ふだんの設定は読み込みません）" "  required  Vim: $VIM_BIN (usable; your own Vim settings are not loaded)"
else
  required="$required vim"
fi
have git || required="$required git"
have python3 || required="$required python3"
if [ "$NO_VENV" = 0 ] && have python3 && ! python3 -c 'import venv, ensurepip' >/dev/null 2>&1; then recommended="$recommended venv"; fi
have fzf || [ -x "$GNOSIS_HOME/plugins/fzf/bin/fzf" ] || recommended="$recommended fzf"
have rg || recommended="$recommended rg"
if [ "$OS" != Darwin ]; then
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    have wl-copy || recommended="$recommended wl-clipboard"
  elif [ -n "${DISPLAY:-}" ]; then
    vc=0; [ -n "$VIM_BIN" ] && "$VIM_BIN" --version 2>/dev/null | grep -q '+clipboard' && vc=1
    if [ "$vc" = 0 ] && ! have xclip && ! have xsel; then
      if [ "$PM" = apt ]; then recommended="$recommended vim-clip"; else recommended="$recommended xclip"; fi
    fi
  fi
fi
if [ "$WITH_CRYPT" = 1 ] || crypt_in_use; then
  if [ "$OS" = Darwin ]; then
    have gocryptfs || say "  機能別 暗号化 vault: macOS では macFUSE と gocryptfs を手で入れてください" "  feature  encrypted vaults: on macOS install macFUSE and gocryptfs manually"
  else
    have gocryptfs || feature="$feature gocryptfs"
    have fusermount3 || have fusermount || feature="$feature fuse"
  fi
fi
if [ "$WITH_SCAN" = 1 ] && have python3; then
  python3 -c 'import tkinter' >/dev/null 2>&1 || feature="$feature tk"
  python3 -c 'import PIL' >/dev/null 2>&1 || feature="$feature pil"
fi
if [ "$NO_APP" = 0 ] && ! have npm; then feature="$feature node"; fi

[ -z "$required" ] || say "  必須で足りないもの:$required" "  Missing (required):$required"
[ -z "$recommended" ] || say "  推奨で足りないもの:$recommended" "  Missing (recommended):$recommended"
[ -z "$feature" ] || say "  使う機能に足りないもの:$feature" "  Missing (for the features you chose):$feature"
missing="$required$recommended$feature"
if [ -n "$missing" ]; then
  if [ "$NO_SYSTEM" = 0 ] && [ -n "$PM" ] && ask "  $PM で入れますか？（管理者のパスワードを聞かれることがあります）" "  Install them with $PM? (may ask for the administrator password)"; then
    # shellcheck disable=SC2086
    pm_install $missing || say "  一部を入れられませんでした。" "  Some packages could not be installed."
  else
    say "  OS のパッケージは入れません。" "  Not installing OS packages."
  fi
fi
[ -n "$VIM_BIN" ] || VIM_BIN=$(find_vim_ok || true)
FAIL=""
[ -n "$VIM_BIN" ] || FAIL="$FAIL Vim(8.2+,+job,+channel,+timers,+textprop,+popupwin)"
have git || FAIL="$FAIL git"
have python3 || FAIL="$FAIL python3"
if [ -n "$FAIL" ]; then
  say "必須のものが足りないため、インストールを終えられません:$FAIL" "Required tools are missing; installation cannot finish:$FAIL"
  say "入れてから、もう一度 ./install/install.sh を実行してください。" "Install them and run ./install/install.sh again."
  exit 1
fi
have rg || say "  注意: ripgrep が無いと全文検索が遅くなります。" "  Note: without ripgrep, full-text search is slower."

# ---------------------------------------------------------------- 2. Gnosis 専用の Vim 環境
step "Gnosis 専用の Vim 環境を作ります: $GNOSIS_HOME" "Creating the Gnosis-only Vim environment: $GNOSIS_HOME"
mkdir -p "$GNOSIS_HOME/plugins" "$GNOSIS_HOME/themes" "$GNOSIS_HOME/state" "$GNOSIS_HOME/logs"
plugin() { # name owner/repo
  dst="$GNOSIS_HOME/plugins/$1"
  if [ -d "$dst/.git" ]; then
    git -C "$dst" pull --ff-only --quiet || say "  $1 を更新できませんでした（今のまま使います）" "  could not update $1 (keeping it)"
  elif [ -n "${GNOSIS_PLUGIN_MIRROR:-}" ]; then
    git clone --quiet --depth 1 "$GNOSIS_PLUGIN_MIRROR/$1" "$dst"
  else
    git clone --quiet --depth 1 "https://github.com/$2.git" "$dst"
  fi
  say "  プラグイン: $1" "  plugin: $1"
}
plugin fzf junegunn/fzf
plugin fzf.vim junegunn/fzf.vim
plugin vim-surround tpope/vim-surround
if ! have fzf && [ ! -x "$GNOSIS_HOME/plugins/fzf/bin/fzf" ]; then
  say "  fzf 本体を取得します" "  Fetching the fzf binary"
  "$GNOSIS_HOME/plugins/fzf/install" --bin >/dev/null 2>&1 || say "  fzf を取得できませんでした（検索に fzf が要ります）" "  could not fetch fzf (search needs it)"
fi

# Python: Gnosis 専用の仮想環境（Debian などの externally-managed な Python にも入れられる）。
# OS の Python のモジュール（tkinter・Pillow）も使えるよう --system-site-packages。
PY_CMD=python3
if [ "$NO_VENV" = 0 ]; then
  VENV="$GNOSIS_HOME/venv"
  if [ ! -x "$VENV/bin/python" ]; then
    python3 -m venv --system-site-packages "$VENV" >/dev/null 2>&1 || rm -rf "$VENV"
  fi
  if [ -x "$VENV/bin/python" ]; then
    # Gnosis は Python のコマンドを文字列のままシェルに渡す箇所があるので、空白や引用符を含む場所の
    # venv は使わない（その場合は OS の python3）
    case "$VENV" in
      *[!A-Za-z0-9_./+-]*) say "  Python の仮想環境の場所に空白などが含まれるため、OS の python3 を使います" "  The venv path contains spaces or quotes; using the system python3" ;;
      *) PY_CMD="$VENV/bin/python" ;;
    esac
    if "$VENV/bin/python" -m pip install --quiet --disable-pip-version-check -r "$GNOSIS_DIR/python/requirements.txt" >/dev/null 2>&1; then
      say "  Python: $VENV（$(tr '\n' ' ' < "$GNOSIS_DIR/python/requirements.txt")）" "  Python: $VENV ($(tr '\n' ' ' < "$GNOSIS_DIR/python/requirements.txt"))"
    else
      say "  Python の追加モジュール（pykakasi）を入れられませんでした（よみ順の並べ替えは文字コード順になります）" \
          "  Could not install the extra Python modules (pykakasi); sorting by reading falls back to code order"
    fi
  else
    say "  Python の仮想環境を作れませんでした（python3-venv が必要）。OS の python3 を使います。" \
        "  Could not create a Python venv (needs python3-venv); using the system python3."
  fi
fi
"$PY_CMD" -c 'import json, pathlib, re, hashlib' >/dev/null 2>&1 || { say "Python 3 が動きません: $PY_CMD" "Python 3 does not work: $PY_CMD"; exit 1; }

# 専用の vimrc（本体の vimrc_gnosis を読むだけ。Gnosis だけの設定は vimrc.local に書ける）
q=$(vimq "$GNOSIS_DIR/vimrc_gnosis")
pyq=$(vimq "$PY_CMD")
cat > "$GNOSIS_HOME/vimrc" <<EOF
" Gnosis 専用の vimrc（インストーラーが作成。もう一度インストールすると作り直す）。
" この Vim は、ふだんの ~/.vimrc・~/.vim を読まない。Gnosis だけの追加設定は
" 同じフォルダの vimrc.local に書く（このファイルは書き換えない）。
if !exists('g:gnosis_python_cmd') && executable($pyq)
  let g:gnosis_python_cmd = $pyq
endif
execute 'source ' . fnameescape($q)
EOF
say "  vimrc: $GNOSIS_HOME/vimrc" "  vimrc: $GNOSIS_HOME/vimrc"

# ---------------------------------------------------------------- 3. アプリ
if [ "$NO_APP" = 0 ]; then
  step "アプリ（Electron）を入れます" "Installing the app (Electron)"
  if have npm; then
    (cd "$GNOSIS_DIR/web" && { [ -f package-lock.json ] && npm ci --no-audit --no-fund || npm install --no-audit --no-fund; } && npm run build) \
      || say "  アプリを入れられませんでした。端末・GUI 版 Vim で使えます。" "  Could not install the app; Gnosis still works in terminal / GUI Vim."
  else
    say "  Node.js（npm）が無いのでアプリは入れません。" "  No Node.js (npm); skipping the app."
  fi
fi

# ---- WezTerm is the standard display backend (separate from ~/.wezterm.lua).
# macOS uses Homebrew Cask. Linux uses the configured package manager only when
# a package is actually offered; missing repositories must not break the Vim setup.
# On WSL, the Windows installer manages host-side WezTerm instead.
step "Gnosis 用ターミナル WezTerm を確認" "Checking dedicated WezTerm terminal"
if ! have wezterm && [ "$NO_SYSTEM" = 0 ]; then
  if [ "$OS" = Darwin ]; then
    if have brew && ask "WezTermをHomebrewからインストールしますか？" "Install WezTerm via Homebrew Cask?"; then
      if ! brew install --cask wezterm; then
        say "  WezTerm導入失敗。Terminal.appを代替として使います。" "  WezTerm failed; Terminal.app remains available."
      fi
    elif ! have brew; then
      say "  Homebrewがありません。wezterm.org/install/macos.html からインストールできます。" \
          "  Homebrew missing. Install it first, or install WezTerm from wezterm.org/install/macos.html"
    fi
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    say "  WSL内です。Windows側のWezTermを使用します。" "  WSL detected: use host-side WezTerm."
  elif [ "$PM" = apt ] && have apt-cache && apt-cache show wezterm >/dev/null 2>&1; then
    if ask "WezTerm を追加しますか？" "Install WezTerm?"; then
      pm_install wezterm || say "  WezTermは導入できませんでした（既存端末を使用）。" "  WezTerm unavailable; using existing terminal."
    fi
  elif [ "$PM" = pacman ] || [ "$PM" = dnf ] || [ "$PM" = zypper ]; then
    if ask "WezTerm を追加しますか？" "Install WezTerm?"; then
      pm_install wezterm || say "  WezTermは導入できませんでした（既存端末を使用）。" "  WezTerm unavailable; using existing terminal."
    fi
  else
    say "  WezTermのパッケージがありません。既存端末を使えます。" \
        "  WezTerm package unavailable; Gnosis can still use installed terminals."
  fi
fi

# ---------------------------------------------------------------- 4. ランチャーとアイコン
step "ランチャーとアイコンを作ります" "Creating the launcher and icons"
# Git 管理下の PNG を更新するのではなく、Gnosis 専用ホームに毎回再生成する。
# Pillow が無くても SVG アイコンは生成できる。ユーザーの通常のアイコン設定には触らない。
ICON_OUT="$GNOSIS_HOME/generated-icons"
mkdir -p "$ICON_OUT"
if ! GNOSIS_ICON_OUTPUT_ROOT="$ICON_OUT" "$PY_CMD" "$GNOSIS_DIR/tools/build_icons.py"; then
  say "  アイコンの再生成に失敗したため、同梱の SVG を使用します。" \
      "  Icon rebuild failed. Falling back to the bundled SVG."
fi
ICON_SVG="$ICON_OUT/icons/gnosis-symbol.svg"
[ -f "$ICON_SVG" ] || ICON_SVG="$GNOSIS_DIR/assets/icons/gnosis-symbol.svg"
ICON_ICNS="$ICON_OUT/icons/gnosis.icns"
[ -f "$ICON_ICNS" ] || ICON_ICNS="$GNOSIS_DIR/assets/icons/gnosis.icns"
mkdir -p "$BIN_DIR"
LAUNCHER="$BIN_DIR/gnosis"
if [ -f "$LAUNCHER" ]; then
  prev=$(sed -n "s/^exec '\(.*\)' \"\$@\"$/\1/p" "$LAUNCHER" 2>/dev/null | head -1)
  if [ -n "$prev" ] && [ "$prev" != "$GNOSIS_DIR/bin/gnosis" ]; then
    say "  前のインストール先 $prev から、このフォルダ $GNOSIS_DIR へ切り替えます（前のフォルダは消しません）" \
        "  Switching from the previous install $prev to $GNOSIS_DIR (the old folder is not deleted)"
  fi
fi
H_Q=$(shq "$GNOSIS_HOME")
L_Q=$(shq "$GNOSIS_DIR/bin/gnosis")
cat > "$LAUNCHER" <<EOF
#!/bin/sh
# Gnosis のランチャー（インストーラーが作成）
GNOSIS_HOME=$H_Q
export GNOSIS_HOME
exec $L_Q "\$@"
EOF
chmod +x "$LAUNCHER" "$GNOSIS_DIR/bin/gnosis"
say "  ランチャー: $LAUNCHER" "  launcher: $LAUNCHER"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "  （$BIN_DIR を PATH に入れると、端末から gnosis で起動できます）" "  (add $BIN_DIR to PATH to run gnosis from a terminal)" ;; esac
# PATH でこのランチャーより前にある別の gnosis（古いインストールなど）
first=$(command -v gnosis 2>/dev/null || true)
if [ -n "$first" ] && [ "$first" != "$LAUNCHER" ]; then
  say "  注意: PATH では $first が先に見つかります（そちらが起動します）。消すか、$BIN_DIR を PATH の前に置いてください。" \
      "  Note: $first comes first on PATH and would be started instead. Remove it or put $BIN_DIR earlier on PATH."
fi

if [ "$OS" = Darwin ]; then
  APP="$HOME/Applications/Gnosis.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$ICON_ICNS" "$APP/Contents/Resources/gnosis.icns"
  cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Gnosis</string>
  <key>CFBundleDisplayName</key><string>Gnosis</string>
  <key>CFBundleIdentifier</key><string>io.github.yurii7812.gnosis</string>
  <key>CFBundleExecutable</key><string>Gnosis</string>
  <key>CFBundleIconFile</key><string>gnosis</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.5.0</string>
</dict></plist>
EOF
  LA_Q=$(shq "$LAUNCHER")
  cat > "$APP/Contents/MacOS/Gnosis" <<EOF
#!/bin/sh
exec $LA_Q --new-terminal
EOF
  chmod +x "$APP/Contents/MacOS/Gnosis"
  say "  アプリ: $APP（Finder・Launchpad から起動できます）" "  app: $APP (open it from Finder / Launchpad)"
  DESKTOP_FILE="$APP"
else
  ICON_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
  for s in 16 24 32 48 64 128 256 512; do
    mkdir -p "$ICON_BASE/${s}x${s}/apps"
    if [ -f "$ICON_OUT/icons/gnosis-$s.png" ]; then
      cp "$ICON_OUT/icons/gnosis-$s.png" "$ICON_BASE/${s}x${s}/apps/gnosis.png"
    fi
  done
  mkdir -p "$ICON_BASE/scalable/apps"
  cp "$ICON_SVG" "$ICON_BASE/scalable/apps/gnosis.svg"
  APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  mkdir -p "$APPS"
  # 端末の窓はランチャー自身が開く（--new-terminal）。Terminal=true にするとデスクトップが選んだ端末で
  # 開き、Gnosis の文字サイズを渡せないうえ、環境によっては何も起きないことがあるため。
  # Exec は空白などを含むパスでも動くよう二重引用符で囲む（desktop entry の規則）
  exec_path=$(deskq "$LAUNCHER")
  DESKTOP_FILE="$APPS/gnosis.desktop"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Gnosis
Comment=Markdown notes with Vim
Comment[ja]=Vim で書く Markdown のノート
Exec=$exec_path --new-terminal %F
Icon=$ICON_SVG
Terminal=false
Categories=Utility;TextEditor;
MimeType=text/markdown;
StartupNotify=false
EOF
  have update-desktop-database && update-desktop-database "$APPS" >/dev/null 2>&1 || true
  have gtk-update-icon-cache && gtk-update-icon-cache -q -t "$ICON_BASE" >/dev/null 2>&1 || true
  have kbuildsycoca6 && kbuildsycoca6 >/dev/null 2>&1 || true
  say "  アプリメニュー: $DESKTOP_FILE" "  app menu: $DESKTOP_FILE"
  desk=$(have xdg-user-dir && xdg-user-dir DESKTOP || echo "$HOME/Desktop")
  # デスクトップのアイコンは、頼まれたとき・前に置いたものがあるときだけ（あれば新しい内容にする）
  if [ -d "$desk" ] && { [ "$DESKTOP_ICON" = 1 ] || [ -f "$desk/gnosis.desktop" ]; }; then
    cp "$DESKTOP_FILE" "$desk/gnosis.desktop"
    chmod +x "$desk/gnosis.desktop"
    have gio && gio set "$desk/gnosis.desktop" metadata::trusted true >/dev/null 2>&1 || true
    say "  デスクトップ: $desk/gnosis.desktop" "  desktop: $desk/gnosis.desktop"
  fi
  for old in simple-yurii-note.desktop yurii-note.desktop; do
    [ -f "$APPS/$old" ] && say "  旧版のアプリメニュー項目があります（消していません）: $APPS/$old" "  An old app-menu entry exists (kept): $APPS/$old"
  done
fi

# ---------------------------------------------------------------- 旧 simple-yurii-note からの移行
if [ -f "$HOME/.vim/simple_yurii_note/root.txt" ] && [ ! -f "$GNOSIS_HOME/vaults.json" ]; then
  step "旧 simple-yurii-note の vault を見つけました" "Found a vault from simple-yurii-note"
  say "  最初に Gnosis を起動したとき、自動で vault の一覧に入ります（root.txt と旧環境はそのまま残ります）。" \
      "  It is added to the vault list automatically on the first start (root.txt and the old setup are kept)."
fi

# ---------------------------------------------------------------- 5. 何を入れたか
step "完了" "Done"
commit="(git 管理外)"
[ "$IS_GIT" = 1 ] && commit="$(git -C "$GNOSIS_DIR" rev-parse --short HEAD) ($(git -C "$GNOSIS_DIR" rev-parse --abbrev-ref HEAD))"
case "$UPTODATE" in yes) latest="最新 / latest" ;; no) latest="最新ではない / not the latest" ;; *) latest="確かめられず / unknown" ;; esac
if [ "$JA" = 1 ]; then
  printf '  インストール先    %s\n  Gnosis ホーム     %s\n  vimrc             %s\n  Vim               %s\n  Python            %s\n  コミット          %s\n  版                %s\n  ランチャー        %s\n  起動項目          %s\n' \
    "$GNOSIS_DIR" "$GNOSIS_HOME" "$GNOSIS_HOME/vimrc" "$VIM_BIN" "$PY_CMD" "$commit" "$latest" "$LAUNCHER" "$DESKTOP_FILE"
else
  printf '  Installed from    %s\n  Gnosis home       %s\n  vimrc             %s\n  Vim               %s\n  Python            %s\n  Commit            %s\n  Version           %s\n  Launcher          %s\n  App entry         %s\n' \
    "$GNOSIS_DIR" "$GNOSIS_HOME" "$GNOSIS_HOME/vimrc" "$VIM_BIN" "$PY_CMD" "$commit" "$latest" "$LAUNCHER" "$DESKTOP_FILE"
fi
say "  アイコン（アプリメニュー / Gnosis.app）か、端末で gnosis を実行すると起動します。" \
    "  Start Gnosis from its icon (app menu / Gnosis.app), or run gnosis in a terminal."
say "  開いている端末では、古い場所を覚えていることがあります。hash -r を実行するか、端末を開き直してください。" \
    "  An open shell may remember an old location; run hash -r or open a new terminal."
say "  確かめるには: gnosis --doctor     ふだんの Vim（vim / ~/.vimrc）は変えていません。" \
    "  To check: gnosis --doctor     Your normal Vim (vim / ~/.vimrc) was not changed."
