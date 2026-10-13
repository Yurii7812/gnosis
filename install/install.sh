#!/bin/sh
# Gnosis のインストーラー（Linux / macOS）。
#
#   git clone https://github.com/Yurii7812/gnosis.git
#   cd gnosis && ./install/install.sh
#
# 行うこと（ふだんの ~/.vimrc・~/.vim・vimfiles・~/.vim/pack は読まない・変えない）:
#   1. 必要なもの（Vim・git・Python 3・fzf・ripgrep、アプリ用に Node.js）を確かめ、
#      無ければ OS のパッケージ管理（apt / dnf / pacman / zypper / Homebrew）で入れる（確認してから）
#   2. Gnosis ホームに、Gnosis 専用の vimrc とプラグイン領域（fzf / fzf.vim / vim-surround）を作る
#   3. Electron は --app が指定されたときだけ入れる（標準では不要）
#   4. ランチャー（~/.local/bin/gnosis）と、アイコン付きの起動項目を作る
#        Linux … アプリメニュー（~/.local/share/applications/gnosis.desktop）
#        macOS … ~/Applications/Gnosis.app
#
# オプション:
#   --yes          確認せずに進める
#   --no-system    OS のパッケージを入れない（足りないものは表示だけ）
#   --app          オプションの Electron アプリを追加で入れる
#   --no-app       Electron を入れない（標準動作）
#   --desktop-icon Linux でデスクトップにもアイコンを置く
#   --bin DIR      ランチャーを置く場所（既定 ~/.local/bin）
#   --help
# 環境変数: GNOSIS_HOME（Gnosis ホーム）、GNOSIS_PLUGIN_MIRROR（プラグインを取ってくる場所。
#           既定は GitHub。試験やオフライン用に、fzf / fzf.vim / vim-surround を置いたフォルダを指定できる）
set -eu

YES=0; NO_SYSTEM=0; NO_APP=1; DESKTOP_ICON=0
BIN_DIR="$HOME/.local/bin"
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --no-system) NO_SYSTEM=1 ;;
    --app) NO_APP=0 ;;
    --no-app) NO_APP=1 ;;
    --desktop-icon) DESKTOP_ICON=1 ;;
    --bin) shift; BIN_DIR=$1 ;;
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# ---------------------------------------------------------------- 1. 必要なもの
PM=""
if [ "$OS" = Darwin ]; then have brew && PM=brew
elif have apt-get; then PM=apt
elif have dnf; then PM=dnf
elif have pacman; then PM=pacman
elif have zypper; then PM=zypper
fi

pkg_name() { # 汎用名 → パッケージ名
  case "$PM:$1" in
    apt:vim) echo vim ;; dnf:vim) echo vim-enhanced ;; pacman:vim) echo vim ;; zypper:vim) echo vim ;; brew:vim) echo vim ;;
    *:python3) case "$PM" in pacman) echo python ;; brew) echo python ;; *) echo python3 ;; esac ;;
    *:node) case "$PM" in apt) echo nodejs npm ;; dnf|zypper) echo nodejs npm ;; pacman) echo nodejs npm ;; brew) echo node ;; esac ;;
    *:rg) echo ripgrep ;;
    *) echo "$1" ;;
  esac
}

pm_install() {
  pkgs=""
  for p in "$@"; do pkgs="$pkgs $(pkg_name "$p")"; done
  [ -n "$PM" ] || return 1
  case "$PM" in
    apt) sudo apt-get update && sudo apt-get install -y $pkgs ;;
    dnf) sudo dnf install -y $pkgs ;;
    pacman) sudo pacman -S --needed --noconfirm $pkgs ;;
    zypper) sudo zypper install -y $pkgs ;;
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

step "必要なものを確かめます" "Checking requirements"
missing=""
VIM_BIN=""
for v in vim /usr/local/bin/vim /opt/homebrew/bin/vim; do
  if vim_ok "$v"; then VIM_BIN=$(command -v "$v" || echo "$v"); break; fi
done
if [ -n "$VIM_BIN" ]; then
  say "  Vim: $VIM_BIN（使えます。ふだんの設定は読み込みません）" "  Vim: $VIM_BIN (usable; your own Vim settings are not loaded)"
else
  missing="$missing vim"
fi
for c in git python3 fzf rg; do have "$c" || missing="$missing $c"; done
if [ "$NO_APP" = 0 ] && ! have npm; then missing="$missing node"; fi
if [ -n "$missing" ]; then
  say "  足りないもの:$missing" "  Missing:$missing"
  if [ "$NO_SYSTEM" = 0 ] && [ -n "$PM" ] && ask "  $PM で入れますか？" "  Install them with $PM?"; then
    # shellcheck disable=SC2086
    pm_install $missing || say "  一部を入れられませんでした。続けます。" "  Some packages could not be installed; continuing."
  else
    say "  OS のパッケージは入れません。" "  Not installing OS packages."
  fi
fi
if [ -z "$VIM_BIN" ]; then
  for v in vim /usr/local/bin/vim /opt/homebrew/bin/vim; do
    if vim_ok "$v"; then VIM_BIN=$(command -v "$v" || echo "$v"); break; fi
  done
fi
if [ -z "$VIM_BIN" ]; then
  say "Gnosis に使える Vim（8.2 以上、+job +channel +timers +textprop +popupwin）が見つかりません。入れてからもう一度実行してください。" \
      "No usable Vim found (8.2+, +job +channel +timers +textprop +popupwin). Install it and run again."
  exit 1
fi
have git || { say "git が必要です。" "git is required."; exit 1; }
have python3 || say "  注意: Python 3 が無いと、リンクの同期・検索が動きません。" "  Note: without Python 3, link sync and search do not work."

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
# 専用の vimrc（本体の vimrc_gnosis を読むだけ。Gnosis だけの設定は vimrc.local に書ける）
q=$(vimq "$GNOSIS_DIR/vimrc_gnosis")
cat > "$GNOSIS_HOME/vimrc" <<EOF
" Gnosis 専用の vimrc（インストーラーが作成。もう一度インストールすると作り直す）。
" この Vim は、ふだんの ~/.vimrc・~/.vim を読まない。Gnosis だけの追加設定は
" 同じフォルダの vimrc.local に書く（このファイルは書き換えない）。
execute 'source ' . fnameescape($q)
EOF
say "  vimrc: $GNOSIS_HOME/vimrc" "  vimrc: $GNOSIS_HOME/vimrc"
if have python3; then
  if python3 -c 'import pykakasi' >/dev/null 2>&1; then :
  elif python3 -m pip install --user --quiet pykakasi >/dev/null 2>&1; then say "  pykakasi（よみ順の並べ替え）を入れました" "  installed pykakasi (sorting by reading)"
  else say "  pykakasi は入れませんでした（よみ順の並べ替えは文字コード順になります）" "  pykakasi not installed (sorting by reading falls back to code order)"; fi
fi

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

# ---------------------------------------------------------------- 4. ランチャーとアイコン
step "ランチャーとアイコンを作ります" "Creating the launcher and icons"
mkdir -p "$BIN_DIR"
LAUNCHER="$BIN_DIR/gnosis"
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

if [ "$OS" = Darwin ]; then
  APP="$HOME/Applications/Gnosis.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$GNOSIS_DIR/assets/icons/gnosis.icns" "$APP/Contents/Resources/gnosis.icns"
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
exec $LA_Q
EOF
  chmod +x "$APP/Contents/MacOS/Gnosis"
  say "  アプリ: $APP（Finder・Launchpad から起動できます）" "  app: $APP (open it from Finder / Launchpad)"
else
  ICON_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
  for s in 16 24 32 48 64 128 256 512; do
    mkdir -p "$ICON_BASE/${s}x${s}/apps"
    cp "$GNOSIS_DIR/assets/icons/gnosis-$s.png" "$ICON_BASE/${s}x${s}/apps/gnosis.png"
  done
  mkdir -p "$ICON_BASE/scalable/apps"
  cp "$GNOSIS_DIR/assets/icons/gnosis-symbol.svg" "$ICON_BASE/scalable/apps/gnosis.svg"
  APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  mkdir -p "$APPS"
  # Exec は空白などを含むパスでも動くよう二重引用符で囲む（desktop entry の規則）
  exec_path=$(deskq "$LAUNCHER")
  cat > "$APPS/gnosis.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Gnosis
Comment=Markdown notes with Vim
Comment[ja]=Vim で書く Markdown のノート
Exec=$exec_path %F
Icon=gnosis
Terminal=true
Categories=Utility;TextEditor;
MimeType=text/markdown;
StartupNotify=true
EOF
  have update-desktop-database && update-desktop-database "$APPS" >/dev/null 2>&1 || true
  have gtk-update-icon-cache && gtk-update-icon-cache -q -t "$ICON_BASE" >/dev/null 2>&1 || true
  say "  アプリメニュー: $APPS/gnosis.desktop" "  app menu: $APPS/gnosis.desktop"
  if [ "$DESKTOP_ICON" = 1 ]; then
    desk=$(have xdg-user-dir && xdg-user-dir DESKTOP || echo "$HOME/Desktop")
    if [ -d "$desk" ]; then
      cp "$APPS/gnosis.desktop" "$desk/gnosis.desktop"
      chmod +x "$desk/gnosis.desktop"
      have gio && gio set "$desk/gnosis.desktop" metadata::trusted true >/dev/null 2>&1 || true
      say "  デスクトップ: $desk/gnosis.desktop" "  desktop: $desk/gnosis.desktop"
    fi
  fi
fi

# ---------------------------------------------------------------- 旧 simple-yurii-note からの移行
if [ -f "$HOME/.vim/simple_yurii_note/root.txt" ] && [ ! -f "$GNOSIS_HOME/vaults.json" ]; then
  step "旧 simple-yurii-note の vault を見つけました" "Found a vault from simple-yurii-note"
  say "  最初に Gnosis を起動したとき、自動で vault の一覧に入ります（root.txt と旧環境はそのまま残ります）。" \
      "  It is added to the vault list automatically on the first start (root.txt and the old setup are kept)."
fi

step "完了" "Done"
say "  アイコン（アプリメニュー / Gnosis.app）か、端末で gnosis を実行すると起動します。" \
    "  Start Gnosis from its icon (app menu / Gnosis.app), or run gnosis in a terminal."
say "  ふだんの Vim（vim / ~/.vimrc）は変えていません。" "  Your normal Vim (vim / ~/.vimrc) was not changed."
