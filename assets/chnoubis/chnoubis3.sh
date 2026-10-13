#!/usr/bin/env bash
# Gnosis / Chnoubis: 青系カラーパレット比較 & 起動画面プレビュー
# 元の Unicode Braille アート（44 / 60 / 80 文字幅）を維持。
# Usage: bash chnoubis.sh                # 全画面ギャラリー (対話端末)
#        bash chnoubis.sh --gallery      # 全配色の大画面比較
#        bash chnoubis.sh --screen       # 選択済み起動画面
#        bash chnoubis.sh --screen --palette sky-mist
# Works in a UTF-8, true-color ANSI terminal (e.g. Kitty, WezTerm, GNOME Terminal).
set -euo pipefail

# Each palette: ID, Japanese label, BACKGROUND, FOREGROUND.
# All palettes use blue in at least one of the two colors.
PALETTE_IDS=(
  sky-mist powder-blue ice-blue clear-sky sea-glass blue-gray
  morning-blue cloud-blue blue-on-cream night-sky deep-ocean dusk-blue
)
PALETTE_NAMES=(
  'スカイミスト' 'パウダーブルー' 'アイスブルー' '晴天の空'
  'シーグラス' 'ブルーグレー' '朝の青' '雲と青'
  'クリーム×青' '夜空×水色' '深海×シアン' '夕暮れの青'
)
PALETTE_BGS=(
  D7EFFB BFDFF2 EAF7FF 92CFEF CBF4F4 CADCE8
  AEC7DF F4F9FD FFF1D6 14283D 071B33 263A56
)
PALETTE_FGS=(
  164A72 16324F 2446A6 102A43 123C69 26465B
  26365E 0B5FA8 195FA8 79CFFF 83DDE9 98C6F3
)

show_help() {
  cat <<'HELP'
Usage: bash chnoubis.sh [options]
  --gallery, --all        全画面に大きなシンボルを並べて配色を比較
  --choose               --gallery と同じ（番号で拡大表示・保存）
  --list                 色見本のテキスト一覧を表示
  --palette ID|1..12     指定した配色を使用
  --screen               端末画面全体を背景色で塗り、中央に描画
  --tiny                 32文字幅の小型版
  --small                44文字幅
  --medium               60文字幅
  --large                80文字幅（画面に収まらない場合は自動調整）
  --mono, --no-color     配色せずにアートを描画
  -h, --help             このヘルプ

例:
  bash chnoubis.sh                   # 全画面ギャラリー
  bash chnoubis.sh --gallery --large # 大きな画像でページ切替
  bash chnoubis.sh --screen --palette sky-mist
  bash chnoubis.sh --screen          # 保存した配色を使用

保存先: ~/.config/gnosis/theme.conf（XDG_CONFIG_HOME が指定されていればそちら）
起動時のGnosis本体へ反映するには、Gnosis側でこの設定を読み込む必要があります。
HELP
}

palette_index() {
  local wanted="$1" i
  if [[ "$wanted" =~ ^([1-9]|1[0-2])$ ]]; then
    printf '%d' "$((wanted-1))"
    return 0
  fi
  for i in "${!PALETTE_IDS[@]}"; do
    if [[ "${PALETTE_IDS[$i]}" == "$wanted" ]]; then
      printf '%d' "$i"
      return 0
    fi
  done
  return 1
}

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/gnosis/theme.conf"
get_saved_palette() {
  local line value
  if [[ -r "$config_file" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == GNOSIS_PALETTE=* ]]; then
        value="${line#*=}"
        if palette_index "$value" >/dev/null; then
          printf '%s' "$value"
          return
        fi
      fi
    done < "$config_file"
  fi
  printf 'sky-mist'
}

rgb_codes() {
  local hex="$1"
  printf '%d;%d;%d'     "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

# Vars below are set by choose_colors.
fg_ansi='' bg_ansi='' reset_ansi=$'\033[0m'
choose_colors() {
  local idx="$1"
  fg_ansi="$(printf '\033[38;2;%sm' "$(rgb_codes "${PALETTE_FGS[$idx]}")")"
  bg_ansi="$(printf '\033[48;2;%sm' "$(rgb_codes "${PALETTE_BGS[$idx]}")")"
}

term_columns() {
  local n
  n="$(tput cols 2>/dev/null || printf '%s' "${COLUMNS:-80}")"
  [[ "$n" =~ ^[0-9]+$ ]] && ((n>0)) || n=80
  printf '%s' "$n"
}
term_rows() {
  local n
  n="$(tput lines 2>/dev/null || printf '%s' "${LINES:-24}")"
  [[ "$n" =~ ^[0-9]+$ ]] && ((n>0)) || n=24
  printf '%s' "$n"
}

art_width=auto palette_arg='' do_list=0 do_gallery=0 screen=0 mono=0
arg_count=$#
while (($#)); do
  case "$1" in
    --tiny)   art_width=32 ;;
    --small)  art_width=44 ;;
    --medium) art_width=60 ;;
    --large)  art_width=80 ;;
    --palette)
      if (($#<2)); then printf '%s\n' 'Missing palette ID' >&2; exit 2; fi
      palette_arg="$2"; shift ;;
    --list)   do_list=1 ;;
    --choose|--gallery|--all) do_gallery=1 ;;
    --screen) screen=1 ;;
    --mono|--no-color) mono=1 ;;
    -h|--help) show_help; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

can_color=0
if [[ -t 1 && "$mono" -eq 0 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  can_color=1
fi

list_palettes() {
  local i
  printf 'Gnosis / Chnoubis — 配色候補（背景 / シンボル）\n\n'
  for i in "${!PALETTE_IDS[@]}"; do
    if ((can_color)); then
      choose_colors "$i"
      printf '%2d  %b%b %-20s %b ' "$((i+1))" "$bg_ansi" "$fg_ansi" '  CHNOUBIS  ' "$reset_ansi"
    else
      printf '%2d  %-12s ' "$((i+1))" "${PALETTE_IDS[$i]}"
    fi
    printf '%-14s  #%s / #%s\n' "${PALETTE_NAMES[$i]}" "${PALETTE_BGS[$i]}" "${PALETTE_FGS[$i]}"
  done
}

pick_width() {
  local w="$1" cols="$2" rows="$3" fullscreen="$4" preview="${5:-0}"
  if [[ "$w" != auto ]]; then printf '%s' "$w"; return; fi
  if ((fullscreen)); then
    if ((cols >= 84 && rows >= 52+preview*2)); then printf 80
    elif ((cols >= 64 && rows >= 40+preview*2)); then printf 60
    elif ((cols >= 46 && rows >= 29+preview*2)); then printf 44
    else printf 32
    fi
  else
    if ((cols >= 84)); then printf 80
    elif ((cols >= 64)); then printf 60
    elif ((cols >= 46)); then printf 44
    else printf 32
    fi
  fi
}

print_art() {
  case "$1" in
    32) cat <<'ART_32'
⠀⠀⠀⠀⠀⠀⠀⢀⣀⡤⠖⣶⡒⠛⢛⡏⠉⠛⣿⠒⠲⢤⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣠⠖⠋⢦⣀⠀⢹⣿⡀⢸⣿⢠⣾⡟⢀⣴⠟⠈⠙⢶⣄⠀⠀⠀⠀⠀⠀
⠀⠀⠀⣠⠞⢥⣤⡀⠈⢿⣳⣾⡿⠿⠟⠛⠻⠯⢷⣿⣟⡤⣴⠞⠁⠙⢷⡄⠀⠀⠀⠀
⠀⠀⣰⠃⠀⠀⠙⠻⣟⣿⡟⠁⢀⣤⣶⠖⢾⣷⣦⡈⢻⣿⣁⣤⣤⠤⠀⠙⣦⠀⠀⠀
⠀⣰⠃⠀⠘⠛⠿⣖⣻⡾⢱⣿⣉⣞⣻⣶⣰⣷⣿⣿⢸⣼⡟⠋⠀⠀⠀⠀⠘⣧⠀⠀
⢰⠇⠀⠀⠀⣀⣠⣴⣿⢳⡈⣻⣷⠹⣋⣧⣿⡞⣿⣿⣿⣸⠯⠽⠷⠦⠄⠀⠀⢸⣇⠀
⢸⠀⠀⠀⠈⠉⠉⢉⣼⣿⣷⣌⠛⣿⠛⣿⣿⣿⣿⣿⣿⠻⢷⣦⡀⠀⠀⠀⠀⠀⢿⡄
⣿⠀⠀⠀⠀⠀⠴⠛⠉⢀⣟⡿⣿⣿⣶⡿⢻⣿⣿⡟⢿⣦⠀⠀⠁⠀⠀⠀⠀⠀⠸⡇
⡟⠀⠀⠀⠀⠀⠀⠀⢠⠟⠋⡞⠶⣾⣿⠳⣿⣿⡏⠀⠀⢙⣇⠀⢀⣴⠀⠀⠀⠀⠀⣷
⡇⠀⠀⢀⡔⡿⠛⠁⠀⠀⢠⢇⣻⣿⡏⣴⣿⡿⠀⠀⠀⢀⣻⠝⠋⣯⣀⣀⠀⠀⠀⣿
⡇⠀⠀⠈⢧⣣⣤⣴⠂⠀⣼⢁⣹⣿⢗⣿⣿⠀⠀⠀⠛⠛⢲⣦⣤⣺⡉⠁⠀⠀⠀⣿
⣷⠀⠀⠀⠀⠈⠉⠀⠀⠀⣿⣈⣹⡇⣺⣿⠇⠀⠀⣀⠀⠀⠛⠁⠀⠙⠣⠀⠀⠀⠀⡿
⢸⠀⠀⠀⠀⠀⠀⢀⣀⡀⢸⡗⢿⣗⣹⣿⣴⣿⣯⣽⣫⡟⣶⣄⡀⠀⠀⠀⠀⠀⢰⡇
⠈⢧⠀⠀⠀⢠⣞⣯⣽⣽⡆⣇⣽⢿⣽⣿⣿⡿⠛⠛⢿⣷⠾⢿⣿⠀⠀⠀⠀⢀⣾⠃
⠀⠘⣆⠀⠀⢸⣿⣿⡸⣿⣻⣼⣶⢺⣿⣦⢿⣶⣤⡤⡾⢿⣺⣿⡿⠀⠀⠀⠀⣼⠇⠀
⠀⠀⠙⣆⠀⠀⠻⣿⣿⣿⣿⣿⣿⠿⢿⣿⣼⣤⣼⣤⣿⣾⣿⠟⠀⠀⠀⢀⣼⠏⠀⠀
⠀⠀⠀⠈⠧⡀⠀⠀⠀⠈⠀⠙⠿⣷⣤⠄⠙⠛⠛⠛⠙⠉⠀⠀⠀⠀⣠⠾⠋⠀⠀⠀
⠀⠀⠀⠀⠀⠈⠳⣤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣴⠞⠁⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠉⠙⠦⠤⣤⣤⣤⣤⣤⣤⣤⠤⠴⠾⠋⠉⠀⠀⠀⠀⠀⠀⠀⠀
ART_32
      ;;
    44) cat <<'ART_44'
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⡤⢶⡖⠒⠛⠛⢻⡏⠉⠛⠛⣳⠶⠶⣤⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠴⡛⠉⠀⠀⠸⣿⡄⠀⠀⣿⣇⠀⠀⡴⣿⠀⠀⢀⣬⠛⠷⣤⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⢀⡴⠋⠁⠀⠹⣦⣄⠀⠀⣿⢻⣀⣀⣇⣿⣀⣞⣱⠇⢀⡴⣻⠃⠀⠀⠈⠙⢷⣄⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣠⠻⣤⣀⡀⠀⠀⠹⡝⢳⡴⢞⣻⠭⠷⠛⠛⠻⠿⢭⣓⠿⣼⠃⣀⡤⣶⠞⠁⠀⠙⢷⣄⠀⠀⠀⠀⠀⠀
⠀⠀⠀⢀⡞⠁⠀⠀⠙⢯⣓⠶⣤⡽⣫⠞⠉⠀⠀⣀⣀⣄⣠⣤⣄⡈⠙⢮⢿⣥⠞⠁⠀⠀⠀⠀⠀⠻⣦⠀⠀⠀⠀⠀
⠀⠀⢀⡞⠀⠀⢀⣀⣀⡀⠈⢳⡞⣼⠁⣀⣀⡤⠿⣿⡭⠀⠘⢮⠹⣿⣦⠀⢧⢻⡖⣒⣿⠿⠋⠁⠀⠀⠘⣧⡀⠀⠀⠀
⠀⢀⡞⠀⠀⠀⠈⠙⠻⢭⣉⣹⢳⠇⢰⡿⣆⢀⣞⢛⣽⢲⢈⣿⢳⣿⣿⡅⢸⣼⡟⠉⠀⠀⠀⠀⠀⠀⠀⠘⣧⠀⠀⠀
⠀⣼⠁⠀⠀⠀⠀⠀⠀⢀⣨⣽⡾⡄⠘⠷⢾⣦⢩⡿⠳⢈⡽⡣⠾⣿⣿⣿⣾⢸⣏⣛⣳⣶⣤⣀⡀⠀⠀⠀⠸⣧⠀⠀
⢠⡇⠀⠀⠀⠀⠠⠶⠾⠿⠶⠒⣧⡻⡄⠰⣟⣫⣤⣴⢞⣽⣯⣿⣄⣿⣿⣿⢫⡾⣅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⡆⠀
⢸⠁⠀⠀⠀⠀⠀⠀⠀⠀⣠⢞⣫⠷⣝⢦⡀⠁⣷⠀⠙⣼⣿⣿⣿⣿⣿⡿⡏⠙⠲⠿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠘⣷⠀
⣾⠀⠀⠀⠀⠀⠀⠀⣠⠾⠚⠉⠀⢀⡟⣳⢽⡞⣛⣲⣮⡿⠛⣿⣿⣿⡟⠲⣽⣆⠀⠀⠀⠉⠀⠀⠀⠀⠀⠀⠀⠀⣿⡄
⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣯⠞⢡⠞⣉⣩⣿⣿⢃⣼⣿⣿⡟⠁⠀⠈⠻⣆⠀⠀⠀⠀⡀⠀⠀⠀⠀⠀⠀⢸⡇
⡏⠀⠀⠀⠀⠀⠀⣀⣀⣀⠀⠠⠟⠁⠀⣽⠈⢙⣿⣿⡇⠘⣿⣿⡿⠁⠀⠀⠀⠀⢶⣄⠀⢀⣼⡇⠀⠀⠀⠀⠀⠀⢸⣿
⡇⠀⠀⠀⠀⢠⠎⡵⠚⠉⠁⠀⠀⠀⢠⡇⢈⢻⣿⣿⢁⣾⣿⣿⠇⠀⠀⠀⠀⠀⢘⣦⠙⠋⢸⣅⣀⣀⡀⠀⠀⠀⠀⣿
⡇⠀⠀⠀⠀⢻⠀⣇⠀⠀⢀⡀⠀⠀⢸⠆⠙⢿⣿⡏⠴⣿⣿⡏⠀⠀⠀⠠⠶⠾⠭⣤⠀⠀⢠⡴⠒⠋⠁⠀⠀⠀⠀⣿
⡇⠀⠀⠀⠀⠈⠓⠮⠭⠽⠛⠀⠀⠀⣟⠠⣶⣿⡾⠃⣴⣿⡿⠁⠀⠀⠀⠀⠀⠀⢠⣏⠞⠛⢦⣳⡀⠀⠀⠀⠀⠀⢸⣿
⢿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⢠⣀⣹⡇⢘⣿⣿⠃⠀⠀⠀⢀⠀⠀⠀⠘⠁⠀⠀⠀⠉⠓⠀⠀⠀⠀⠀⢸⡟
⢸⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡇⢼⣿⡥⠘⣿⣿⣠⣴⢟⡟⢉⡿⢛⡷⢦⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⡇
⠀⢧⠀⠀⠀⠀⠀⠀⢀⣤⡖⢲⡶⣄⠘⡇⠠⣾⣷⠰⣿⣿⣿⣿⣾⣿⣿⣷⣶⣆⡊⢽⣷⣦⠀⠀⠀⠀⠀⠀⠀⢀⣿⠁
⠀⠘⡆⠀⠀⠀⠀⢰⡯⢤⣷⢾⣷⢻⡆⢳⣠⠿⢻⣧⣽⣿⣿⡿⠋⠉⠉⠉⠻⣿⠇⠋⣻⣿⠀⠀⠀⠀⠀⠀⠀⣼⡏⠀
⠀⠀⠹⡄⠀⠀⠀⢸⣿⣻⣧⠀⣿⡧⢻⣀⣷⡆⠺⢿⣷⣀⡿⣷⣦⣤⣤⣤⡾⢟⠓⣿⣿⣿⠀⠀⠀⠀⠀⠀⣰⡿⠀⠀
⠀⠀⠀⠻⡄⠀⠀⠈⢻⣷⣟⣷⢾⣿⣧⡛⣿⣿⣶⣯⣅⣟⢀⡏⠈⢹⠁⢸⡆⣨⣷⣿⡿⠁⠀⠀⠀⠀⠀⣰⡿⠁⠀⠀
⠀⠀⠀⠀⠹⣄⠀⠀⠀⠙⠛⠿⠿⣿⠿⢿⣽⣟⠋⠙⠿⠿⣿⣷⣶⣿⣿⣿⣿⣿⠿⠟⠁⠀⠀⠀⠀⠀⣴⡟⠁⠀⠀⠀
⠀⠀⠀⠀⠀⠘⢦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠻⢿⣷⣦⡤⠀⠈⠉⠉⠉⠉⠁⠉⠀⠀⠀⠀⠀⠀⠀⣠⡾⠋⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠙⠶⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⡾⠋⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⠶⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣤⠾⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠓⠲⠤⣤⣤⣤⣤⣤⣤⣤⣤⣤⠶⠶⠟⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
ART_44
      ;;
    60) cat <<'ART_60'
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣠⣤⡤⠴⠒⠚⠛⠛⣿⠛⠛⠛⠛⠻⠶⣶⣤⣤⣀⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⠴⠚⠉⠉⠀⢻⣧⠀⠀⠀⠀⢰⢿⡄⠀⠀⠀⢀⣼⡇⠀⠈⠉⠛⠳⣶⣄⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⠞⠋⣄⠀⠀⠀⠀⠀⠸⡟⣧⠀⠀⠀⢸⠸⡇⠀⠀⣠⠟⣼⠀⠀⠀⢀⣴⡟⠀⠉⠻⢷⣄⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠘⣷⢄⡀⠀⠀⠀⣧⠹⣆⠀⠀⣿⡀⣷⡀⣰⠏⢰⠇⠀⢀⡴⢋⡟⠀⠀⠀⠀⠀⠙⢿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⣴⡋⠀⠀⠀⠀⠀⠀⠘⣮⠻⣦⣀⣀⣼⡶⠿⢛⣋⣩⣭⣭⣭⣟⣛⠻⠦⣤⡞⣡⡟⠀⠀⠀⣀⣠⡤⠂⠀⠈⢿⣦⡀
⠀⠀⠀⠀⠀⠀⣠⠞⠀⠉⠻⣶⢦⣄⡀⠀⠀⠘⣧⣨⠟⣋⡥⠖⠛⠉⠉⠀⠀⠀⠀⠈⠉⠙⠳⢦⡙⢿⣄⡤⠶⢋⣽⠏⠀⠀⠀⠀⠀⠙⢿⣆
⠀⠀⠀⠀⠀⣰⠋⠀⠀⠀⠀⠈⠳⢮⣙⠻⠶⣤⠞⢡⡞⠉⠀⠀⠀⠀⢀⣀⣠⣄⣠⣴⣤⣤⣀⠀⠉⢣⡹⣦⣴⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠻⣷⡀
⠀⠀⠀⠀⡰⠃⠀⠀⠀⠀⠀⠀⠀⠀⠙⢷⣴⠏⣰⠋⠀⠀⠀⢀⣰⣿⣭⣍⡁⠀⠸⣥⡋⢽⣿⣷⡀⠀⢷⠘⣧⡤⠴⠶⢒⣺⠿⠛⠁⠀⠀⠀⠹⣷⡀
⠀⠀⠀⣼⠁⠀⠀⠀⠐⠶⣶⣲⠶⠶⠶⢤⡟⢰⡏⠀⣰⣚⠛⠉⠉⣼⣿⡿⠄⣀⠀⢆⣿⣈⣿⣿⣿⠀⠈⣇⢹⣧⡶⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠘⣷⡀
⠀⠀⣰⠃⠀⠀⠀⠀⠀⠀⠀⠉⠛⠶⣤⣀⡇⣸⠀⠀⣿⠙⣥⠀⢼⡇⠀⣶⠇⣸⡀⣼⡆⢸⣯⣿⣿⣄⠀⣿⢸⣏⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣷
⠀⢀⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣨⣇⢹⡀⠀⠿⣶⣶⣦⡄⣀⣧⠻⠆⢈⡱⠟⢰⣾⣿⣿⣿⣿⣷⡍⢸⣏⢉⣛⡳⠶⢤⣄⠀⠀⠀⠀⠀⠀⠀⢹⣧
⠀⣸⠁⠀⠀⠀⠀⠀⠀⢀⣠⣤⣖⣛⣉⣁⣹⡌⣧⠀⠀⣤⣶⠿⠃⠈⢠⣠⠴⢿⡆⣿⣄⠀⣽⣷⣿⣿⣿⢃⣿⠉⠉⠉⠉⠉⠉⠉⠉⠁⠀⠀⠀⠀⠀⠀⣿⡆
⠀⡿⠀⠀⠀⠀⠀⠀⠈⠉⠉⠉⠉⠀⠀⠀⣠⣷⡘⢧⡀⠙⠶⠶⠿⡟⠛⢃⡼⢯⣿⣿⢏⢦⣼⡿⣽⣿⢡⣾⣙⠳⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿
⢀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⠞⣉⡤⠷⣌⠳⣄⠀⠀⠀⡇⠀⠀⠰⣜⣯⢮⣯⣿⣷⣿⣿⡟⣎⠀⠉⠛⠲⢿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⡇
⢸⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣯⠴⠋⠁⠀⠀⣼⠷⣌⡓⣦⠞⠷⢶⣤⣸⣿⡟⢿⣿⣿⣿⣿⡏⣦⡘⣧⠀⠀⠀⠀⠈⠉⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣧
⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠋⠉⠀⠀⠀⠀⠀⣼⢃⡴⠋⣹⡇⠴⠲⣼⣿⣿⠋⠀⣼⣿⣿⣿⡟⠀⠈⠙⢮⣷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿
⣼⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣥⠋⠀⡴⢋⣠⠄⣭⣾⣿⠟⢠⣴⣿⣿⣿⡏⠀⠀⠀⠀⠀⠙⢧⠀⠀⠀⠀⠀⢀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⡇
⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡼⠋⠀⠀⢀⡇⠈⠈⢻⣷⣿⡿⠀⠸⣿⣿⣿⣿⠁⠀⠀⠀⠀⠀⠀⣶⣄⠀⠀⠀⣠⢾⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣇
⣿⠀⠀⠀⠀⠀⠀⠀⣠⠖⢋⣭⠭⠷⠆⠀⠀⠀⠀⠀⣸⠁⠠⢶⣿⣽⣿⡇⢀⣴⣾⣿⣿⠁⠀⠀⠀⠀⠀⠀⠀⠘⣆⠑⢦⡴⠃⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⣿
⣟⠀⠀⠀⠀⠀⠀⣼⠁⢰⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⡿⠀⣠⢈⣻⣷⣿⠀⢮⣿⣿⣿⡟⠀⠀⠀⠀⠀⠀⠀⢀⣠⡼⠆⠀⠀⠀⠛⠶⠶⢦⣤⡤⠀⠀⠀⠀⠀⢸⣿
⣿⠀⠀⠀⠀⠀⠀⢹⠀⠸⡄⠀⠀⠀⢀⡀⠀⠀⠀⠀⡇⠀⠈⠽⣷⣾⡟⠰⢾⣿⣿⣿⠀⠀⠀⠀⠀⠠⠶⠾⠭⠤⢤⡄⠀⠀⠀⣤⠖⠚⠉⠁⠀⠀⠀⠀⠀⠀⢸⣿
⣿⠀⠀⠀⠀⠀⠀⠀⠳⣄⣉⠒⠒⣲⠟⠁⠀⠀⠀⣼⠃⢀⣤⣰⡬⣿⠇⠀⢤⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⢀⣴⠷⣤⡘⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿
⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠁⠀⠀⠀⠀⠀⢻⠀⠈⠑⢚⢻⡇⠀⣾⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡷⠋⠀⠀⠈⠙⠾⣇⠀⠀⠀⠀⠀⠀⠀⠀⣾⡿
⢸⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡀⠤⢤⣤⢽⡇⢀⣹⣿⣿⠁⠀⠀⠀⠀⢀⣀⡀⠀⠀⠀⠈⠀⠀⠀⠀⠀⠀⠀⠈⠁⠀⠀⠀⠀⠀⠀⠀⣿⡇
⠈⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣏⠠⣀⣿⣭⡄⠈⢟⣿⣿⠀⣀⣴⠟⣿⠋⢉⡽⠛⢛⣶⣤⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣿⠇
⠀⢻⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣀⡀⠀⠀⣟⠀⠀⣹⡿⡃⠀⣸⣿⣿⡛⣻⡏⣠⣇⡆⣼⣡⢀⢁⡀⠬⠿⣿⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿
⠀⠈⣇⠀⠀⠀⠀⠀⠀⠀⠀⣠⡾⢯⡁⠈⣏⢹⣦⠀⢸⠆⠈⢩⣾⣿⡈⢹⣿⣿⡿⣿⣿⣿⣿⣿⣿⣿⣿⣾⣦⡄⢨⣽⣿⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⡇
⠀⠀⠸⡄⠀⠀⠀⠀⠀⠀⢰⡷⠦⣤⣿⢾⣷⡾⢹⡇⠘⢧⠀⠼⠟⢽⣷⢨⣿⣿⣷⣽⠟⠉⠁⠀⠀⠀⠙⢿⣿⠇⠉⠉⢿⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⣿
⠀⠀⠀⢳⡀⠀⠀⠀⠀⠀⣸⣷⠶⢿⡇⠀⢸⣿⣉⣿⡀⠀⣧⣀⠀⡼⣿⣿⡅⠑⣿⣿⣤⡀⠀⠀⠀⣀⣠⣾⠿⠦⢽⣾⣽⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀⢰⣿⠃
⠀⠀⠀⠈⢷⠀⠀⠀⠀⠀⠸⣿⠗⠚⣷⣄⠈⢿⣏⡸⢷⣴⣿⣧⡀⢀⣩⠟⠶⣦⠛⢩⡟⠟⠿⡿⠛⢻⡟⠁⢠⡀⣔⣿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⠏
⠀⠀⠀⠀⠈⢧⠀⠀⠀⠀⠀⠹⣿⣯⡧⣼⠛⢻⡿⣷⣎⠉⣷⣻⣿⣿⣷⣤⣴⣇⠀⣸⠀⠀⢀⡇⠀⢀⣧⠠⡴⣿⣿⣿⡟⠀⠀⠀⠀⠀⠀⠀⠀⢰⣿⠏
⠀⠀⠀⠀⠀⠈⢷⡀⠀⠀⠀⠀⠈⠛⠿⣿⣿⣿⣿⣾⣿⣟⣽⣿⠛⠋⠙⢿⣿⣾⣷⣯⣶⣶⣾⣷⣿⣿⣿⣷⣿⣿⡿⠛⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⠋
⠀⠀⠀⠀⠀⠀⠀⠻⣄⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠁⠀⠹⣷⣟⣧⣀⠀⠀⠀⠀⠙⠿⠿⠿⠿⠿⠟⠛⠛⠛⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⡿⠃
⠀⠀⠀⠀⠀⠀⠀⠀⠘⢦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⠷⢯⡿⠟⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⣿⠋
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠳⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣴⡿⠛⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⠦⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣴⡾⠟⠉
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠶⢤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣠⣤⣶⠟⠛⠉
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠓⠶⠤⠤⣤⣤⣤⣤⣤⣤⣤⣤⣴⠶⠶⠟⠛⠛⠉⠁
ART_60
      ;;
    80) cat <<'ART_80'
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣤⡤⠶⠶⠶⠶⠾⣿⡟⠛⠛⠛⠿⠶⠶⣶⣶⣤⣤⣄⣀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣴⠶⠚⠛⠉⢿⣯⠀⠀⠀⠀⠀⠀⠀⣿⣇⠀⠀⠀⠀⠀⠀⢀⣼⡟⠉⠙⠛⠿⢷⣦⣤⣀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⠞⠋⠁⠀⠀⠀⠀⠀⢸⣿⣧⠀⠀⠀⠀⠀⢐⡇⣿⠀⠀⠀⠀⠀⣠⡞⣿⠁⠀⠀⠀⠀⠀⢀⣩⠻⢿⣦⣄⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠞⠉⠀⢦⡀⠀⠀⠀⠀⠀⠀⠀⣿⠸⣧⠀⠀⠀⠀⢸⡇⢹⡇⠀⠀⠀⣴⠟⣸⡏⠀⠀⠀⠀⣠⣶⣿⠃⠀⠀⠈⠛⢿⣶⣄
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠀⠘⣿⣦⣀⠀⠀⠀⠀⠀⢹⡇⢿⣧⠀⠀⠀⢺⡇⢸⣇⠀⢀⣾⠏⢀⣿⠁⠀⠀⢠⡾⢏⣾⠁⠀⠀⠀⠀⠀⠀⠙⠻⣷⣤⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠀⠀⠀⠀⠈⢷⡙⢷⣤⠀⠀⠀⠘⣷⣀⣿⣶⡶⠶⠿⠷⠾⠿⠷⠾⠷⣦⣾⣇⣀⢀⣴⠟⢡⡿⠃⠀⠀⠀⠀⠀⠀⣀⣀⠀⠈⠻⣿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⢦⣤⣀⡀⠀⠀⠀⠀⠀⠀⠈⢿⡄⠙⢿⣦⣶⡾⠟⢋⣡⣤⡶⠶⠞⠛⠛⠛⠛⠿⠶⢦⣤⣉⡙⠻⣷⣴⡿⠁⠀⠀⣀⣠⠴⣾⡿⠋⠀⠀⠀⠀⠈⠻⣿⣆
⠀⠀⠀⠀⠀⠀⠀⠀⣠⡟⠁⠀⠀⠉⠻⣿⡳⢶⣤⣀⠀⠀⠀⠈⢿⣴⠾⢋⣡⣴⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⢷⣄⠙⣿⣦⡶⠟⠋⣡⣾⠋⠀⠀⠀⠀⠀⠀⠀⠀⠘⢿⣷⡀
⠀⠀⠀⠀⠀⠀⠀⣰⠏⠀⠀⠀⠀⠀⠀⠈⠻⢦⣌⠙⠻⢷⣦⣤⡾⠁⣠⡞⠋⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣀⣀⣠⣤⣤⣄⣀⠀⠀⠈⠻⣄⠻⣷⣤⣾⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠻⣿⣆
⠀⠀⠀⠀⠀⠀⣸⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠻⣦⣀⣨⡟⠀⣼⠋⠀⠀⠀⠀⠀⢀⣴⡿⠛⠛⠛⠉⠉⢉⣟⡩⠿⣛⣿⣷⣄⠀⠀⠘⣆⠹⣿⡁⢀⣀⣀⣤⣤⠤⣶⣶⠶⠂⠀⠀⠀⠀⠘⣿⣦
⠀⠀⠀⠀⠀⣼⠁⠀⠀⠀⠀⢀⣀⣀⣀⣀⡀⠀⠀⠀⠈⢻⡿⢀⣾⠃⠀⠀⣀⣀⣤⠴⠾⠟⢿⣿⡷⠖⠀⠀⠀⠙⢻⣆⠹⢿⣿⣿⣷⡀⠀⠹⣆⢹⣿⠉⢉⣩⣴⣶⠞⠋⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣦
⠀⠀⠀⠀⣼⠁⠀⠀⠀⠀⠀⠈⠙⠿⢭⣍⡛⠛⠛⠛⠛⢿⠇⣸⡇⠀⢀⣾⣭⣍⠀⠀⠀⣴⠿⠿⠝⠗⠆⣦⠀⠉⣤⢿⣦⣼⣿⣻⣿⡇⠀⠀⢿⠈⣿⣿⠿⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢿⣧
⠀⠀⠀⣴⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠳⢦⣤⣀⣾⠀⣿⠀⠀⢸⣏⠉⢩⡄⠀⢸⣿⡀⢠⣶⡯⠁⣺⡀⣠⣿⠀⢸⣷⣞⢶⣿⣧⡀⠀⢼⠀⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣿⣆
⠀⠀⢠⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢉⣿⡀⣿⠀⠀⢸⣷⣤⣬⣥⣄⡀⠉⢸⣎⢻⣇⠀⠙⢃⣿⠟⣠⣼⣳⣾⣿⣿⣿⣿⣦⡻⠀⣿⠟⠛⠿⢷⣦⣤⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⡆
⠀⠀⣼⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣠⣴⠾⠟⢻⣇⢹⣆⠀⠀⠉⠙⢛⢻⣹⡧⠰⠿⠋⠀⠉⢁⣶⡋⢠⣄⠉⠛⠻⣯⣝⣷⣿⣿⣿⡇⢰⣿⠶⠶⠶⠶⠶⠦⠭⠿⠷⠦⢤⠀⠀⠀⠀⠀⠀⠀⠀⢹⣿⡀
⠀⢠⡏⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣤⣶⣿⣩⣥⣤⣤⡤⠤⣿⡀⢿⡄⠀⠀⣶⡿⠟⠛⡁⢀⢠⣰⣶⠚⣛⢹⣇⢸⣿⣦⠀⠴⣿⣿⣿⣿⣿⠿⢁⣾⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣧
⠀⢸⠇⠀⠀⠀⠀⠀⠀⠀⠀⠈⠁⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⣷⡀⢻⣄⠀⠈⠳⠾⡷⠿⣿⠛⠛⠁⣴⠿⣯⣻⣿⡟⣎⠳⣤⣿⠿⢭⣿⡏⣠⣿⣏⠙⠳⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡄
⠀⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣶⠟⢉⣠⣿⣄⠙⢧⡀⠀⠀⠀⠀⢻⠀⠀⠀⠩⢤⢸⣿⢳⡹⣝⣿⣿⣮⣿⣿⣿⢇⡟⠉⠙⠛⠷⣮⣽⣶⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣧
⢀⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⢋⣤⠞⠋⠉⠀⠘⣷⣌⠹⢦⣄⠀⣀⣾⠀⠀⠀⠠⣼⣷⣿⣧⣽⣿⣿⣿⣿⣿⣿⢋⠈⢿⣄⠀⠀⠀⠀⠈⠙⠛⠷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡀
⢸⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⠷⠚⠉⠀⠀⠀⠀⠀⣼⡟⠉⣳⣦⣬⡿⠉⠈⠉⣫⣵⣶⣽⣿⠏⢉⡿⣿⣿⣿⣿⣿⠇⠸⣷⣌⢻⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⡇
⢸⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠀⠀⠀⠀⠀⠀⠀⢀⣾⠏⣠⡾⠉⢀⣽⡇⠶⠛⢶⣭⣳⣝⣯⠁⠀⢨⣿⣿⣿⣿⣿⡟⠀⠀⠀⠙⢧⣙⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣷
⢸⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⢋⡼⠋⠀⣠⡿⠁⢠⣀⢈⣒⣾⣿⣿⠏⢀⣤⣭⣿⣿⣿⣿⠋⠀⠀⠀⠀⠀⠀⠙⠿⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣿⡀
⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⡿⠋⠀⠀⠀⣿⠐⠚⠒⣶⣯⣻⣿⣿⡇⠀⢿⣿⣿⣿⣿⣿⡟⠀⠀⠀⠀⠀⠀⠀⠀⢠⡈⠁⠀⠀⠀⠀⠀⢀⣼⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡇
⣼⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣠⣤⣤⣀⠀⠀⠀⠘⠉⠀⠀⠀⠀⢠⡇⠀⠀⠀⣰⣾⢿⣿⣿⠁⠀⠈⢿⣻⣿⣿⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⠳⣤⡀⠀⠀⣠⠟⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡇
⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠟⢉⣡⡴⠶⠚⠛⠂⠀⠀⠀⠀⠀⠀⠀⣾⠀⠀⠾⢛⣳⣮⣭⣿⡇⠀⢠⣾⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣧⠈⠛⢦⣴⠋⢀⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣷
⣿⠀⠀⠀⠀⠀⠀⠀⠀⢀⡟⠁⢀⡾⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡟⠀⢀⣀⢈⢲⣾⢾⣿⠁⢢⣽⣿⣿⣿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⡧⠀⠀⠀⠀⠘⠷⠦⠤⠤⣤⣤⣀⡀⠀⠀⠀⠀⠀⠀⠀⣿⣿
⣿⠀⠀⠀⠀⠀⠀⠀⠀⠸⡇⠀⢸⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡇⠀⠉⠳⢾⣭⣭⣿⡿⢀⣤⣽⣷⣿⣿⡿⠁⠀⠀⠀⠀⠀⠀⢀⣠⣤⠖⠛⢉⠁⣀⠀⠀⠀⠀⠀⢀⣀⣤⡴⠶⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿
⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⢷⡀⠀⠳⣄⠀⠀⠀⣀⣤⠖⠀⠀⠀⠀⠀⣸⡇⠀⠀⠈⠉⠿⢽⣿⡇⠀⠙⢛⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠉⠙⠛⢙⡏⠀⠀⣀⠀⠀⢿⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿
⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠓⢦⣄⡈⢉⣉⣩⡽⠋⠀⠀⠀⠀⠀⢰⡏⠀⢀⡐⢦⣙⣓⢞⡿⠁⠀⢰⣶⣿⣿⡿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⠃⣠⡾⠛⢷⣄⡈⢷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿
⢹⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠁⠀⠀⠀⠀⠀⠀⠀⠘⣧⠀⠐⠙⠷⠿⣛⡏⠀⠀⢾⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣿⡾⠋⠀⠀⠀⠉⠻⢮⣷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡇
⢸⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠀⡀⠀⠀⠩⢶⣧⠀⠀⢻⣿⣿⣿⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⠋⠀⠀⠀⠀⠀⠀⠀⠀⠉⠻⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡇
⠀⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⡆⠈⠙⢛⣛⣭⠟⠀⠠⠾⣿⣿⣿⠀⠀⠀⢀⣤⣤⣤⣴⠶⢶⣤⣀⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⣿
⠀⣿⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡇⠐⠦⣜⣒⣶⣶⠀⠐⢫⣽⣿⣿⢀⣠⣴⣿⠋⣸⡟⠁⠀⣴⠏⠉⢉⡽⢿⣶⣦⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿
⠀⠸⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⡇⠀⠀⠀⢹⣿⢇⠀⠀⣐⣿⣿⣿⡛⣝⣿⡇⡀⣿⣠⠄⣬⣇⣠⢀⠁⠀⠀⣬⠿⣿⣷⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡏
⠀⠀⢻⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣶⡛⠉⠉⢻⠟⢷⣆⠀⠀⢻⡆⠀⠚⠫⣵⣿⡇⠘⢻⣿⣿⣿⣿⣼⣿⣶⣷⣿⣿⣾⣿⣿⣷⣿⣼⣋⡀⠀⠐⢖⣻⣿⣷⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⠁
⠀⠀⠈⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⡿⠋⠉⢻⣄⢀⣼⡃⢸⡿⣇⠀⢸⡇⠀⠀⣭⢵⡿⣷⡄⠈⢿⣿⣿⣏⠻⣿⣿⡿⠿⠟⠛⠛⠛⠿⣿⣿⣿⣿⠀⠤⠿⠿⣿⣿⡷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡏
⠀⠀⠀⠹⣇⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⡛⠛⠷⣾⡿⠻⢿⣿⠏⢀⣿⡀⠀⠳⣄⡰⠛⠋⠐⣿⣿⣠⣿⢟⡿⢿⣷⡽⠋⠀⠀⠀⠀⠀⠀⠀⠀⠹⣿⡏⠁⠀⠀⣘⣻⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⣿⠁
⠀⠀⠀⠀⢹⣆⠀⠀⠀⠀⠀⠀⠀⢸⣿⣷⠶⢿⣿⠀⠀⠀⣿⣿⡉⣸⣧⠀⠀⢿⣅⣀⠀⣠⡾⣿⣿⣥⠀⠐⣿⣿⣷⣄⡀⠀⠀⠀⠀⠀⣀⣠⣾⣿⠿⠤⢬⣟⣮⣹⣿⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⠇
⠀⠀⠀⠀⠈⢿⡄⠀⠀⠀⠀⠀⠀⠈⣿⣿⣧⣴⣿⣧⡀⠀⢻⣿⣟⠁⣽⣧⣠⣼⣿⣅⠀⠁⠨⢻⣽⢫⢦⡄⣿⠛⣹⡟⣿⢷⣶⣶⡶⢿⣿⠿⠋⢁⡀⠀⡠⣝⣿⣿⣿⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⠏
⠀⠀⠀⠀⠀⠀⢷⡀⠀⠀⠀⠀⠀⠀⠹⣿⣵⣠⡶⡛⠻⣶⣤⣿⣿⣾⣁⡼⠿⣿⠱⡿⣦⣴⣶⣟⠉⠀⣸⡏⠀⠀⣿⠁⠀⠊⢸⡇⠀⠀⢻⡄⠀⢀⡹⣦⢻⣾⣿⣿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⠏
⠀⠀⠀⠀⠀⠀⠈⢷⡀⠀⠀⠀⠀⠀⠀⠘⢿⣿⣾⣞⣾⣇⣠⣽⣍⡟⣿⣧⡀⣸⣷⣽⣿⣿⣿⣿⣿⣶⣿⢣⢀⣰⡏⠀⠀⠀⣼⠇⡀⡀⣼⣷⣀⢷⣹⣿⣿⣿⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⠏
⠀⠀⠀⠀⠀⠀⠀⠈⢿⣄⠀⠀⠀⠀⠀⠀⠀⠙⠛⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣡⣾⣟⠛⠋⠉⠙⢿⣿⣿⣿⣿⣿⣱⣧⣇⣷⣿⣾⣧⣧⣿⣿⣿⣾⣿⣿⡿⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⠋
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠻⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⠉⠉⠉⠉⠹⣿⣧⠿⣧⡀⠀⠀⠀⠈⠉⠉⠻⣿⣿⣿⣿⣿⣿⣿⣿⠿⠿⠿⠿⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣿⡿⠃
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢿⣷⣿⣹⡶⣤⣤⣤⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⠟
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠛⠒⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠳⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣶⡿⠛⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⢶⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣶⣿⠿⠋
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠷⣤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣤⣾⡿⠟⠋
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠛⠶⢤⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣤⣴⣶⡿⠿⠛⠋
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠛⠳⠶⠶⢶⣶⣶⣶⣤⣶⣶⣶⣶⣶⣶⣶⠾⠿⠟⠛⠛⠋⠉⠁
ART_80
      ;;
  esac
}

render_plain() {
  local idx="$1" sz="$2" line
  if ((can_color)); then
    choose_colors "$idx"
    while IFS= read -r line; do
      printf '%b%b%s\033[K%b\n' "$bg_ansi" "$fg_ansi" "$line" "$reset_ansi"
    done < <(print_art "$sz")
  else
    print_art "$sz"
  fi
}

render_screen() {
  local idx="$1" sz="$2" cols="$3" rows="$4" preview="${5:-0}"
  local line lno=0 startrow startcol artheight artline
  local -a lines=()
  mapfile -t lines < <(print_art "$sz")
  artheight="${#lines[@]}"
  startrow=$(( (rows-artheight)/2+1 ))
  startcol=$(( (cols-sz)/2+1 ))
  ((startrow<1)) && startrow=1
  ((startcol<1)) && startcol=1
  choose_colors "$idx"
  # Clear using the chosen background (supported by mainstream ANSI terminals).
  printf '%b\033[2J\033[H' "$bg_ansi"
  for artline in "${lines[@]}"; do
    if ((startrow+lno>rows)); then break; fi
    printf '\033[%d;%dH%b%s' "$((startrow+lno))" "$startcol" "$fg_ansi" "$artline"
    ((lno+=1))
  done
  if ((preview)); then
    printf '\033[%d;2H%b%b [%d] %s    BG #%s  /  FG #%s  '       "$((rows-1))" "$bg_ansi" "$fg_ansi" "$((idx+1))" "${PALETTE_NAMES[$idx]}"       "${PALETTE_BGS[$idx]}" "${PALETTE_FGS[$idx]}"
    printf '\033[%d;2H%b%b 保存=s    一覧に戻る=Enter    終了=q : ' "$rows" "$bg_ansi" "$fg_ansi"
  else
    # Return prompt to terminal's usual colors; screen cells stay colored.
    printf '\033[%d;1H%b' "$rows" "$reset_ansi"
  fi
}

save_palette() {
  local idx="$1"
  ( umask 077
    mkdir -p "$(dirname "$config_file")"
    {
      printf 'GNOSIS_PALETTE=%s\n' "${PALETTE_IDS[$idx]}"
      printf 'GNOSIS_BACKGROUND=#%s\n' "${PALETTE_BGS[$idx]}"
      printf 'GNOSIS_FOREGROUND=#%s\n' "${PALETTE_FGS[$idx]}"
    } > "$config_file"
  )
}

# Full-screen gallery. Use actual terminal columns/rows, not a shrunken thumbnail
# sheet. Each cell contains one complete, original Chnoubis Braille drawing.
# A normal terminal cannot show twelve full-sized drawings in 24 lines; pages
# are used when necessary. A large terminal can show all twelve at once.
# IMPORTANT: no Python, image rendering package or GUI dependency is needed.

art_height() {
  case "$1" in
    32) printf 19 ;;
    44) printf 27 ;;
    60) printf 38 ;;
    80) printf 50 ;;
  esac
}

gallery_layout() {
  # Populates global G_WIDTH, G_COLS, G_ROWS, G_PER_PAGE.
  local cols="$1" rows="$2" request="$3" w h ncol nrow capacity
  local best_width=0 best_n=0
  local -a candidates=(80 60 44 32)
  if [[ "$request" != auto ]]; then
    candidates=("$request" 80 60 44 32)
  fi
  for w in "${candidates[@]}"; do
    h="$(art_height "$w")"
    # 2-column margin, 1-row title, 2-row footer; 2-column/1-row gaps
    ncol=$(( (cols-2+2)/(w+2+2) ))
    nrow=$(( (rows-3+1)/(h+1+1) ))
    (( ncol>0 && nrow>0 )) || continue
    ((ncol>12)) && ncol=12
    capacity=$((ncol*nrow))
    if [[ "$request" != auto ]]; then
      G_WIDTH="$w"; G_COLS="$ncol"; G_ROWS="$nrow"
      G_PER_PAGE="$capacity"
      return
    fi
    # Prefer enough resolution for larger symbols while keeping a usable grid.
    # If the entire gallery fits, use the largest artwork that fits all 12.
    if ((capacity>=12)); then
      G_WIDTH="$w"; G_COLS="$ncol"; G_ROWS="$nrow"
      G_PER_PAGE="$capacity"
      return
    fi
    if ((capacity>=4 && best_n<4)); then
      best_width="$w"; best_n="$capacity"
    elif ((capacity>=2 && best_n<2)); then
      best_width="$w"; best_n="$capacity"
    elif ((best_n==0)); then
      best_width="$w"; best_n="$capacity"
    fi
  done
  if ((best_width==0)); then
    printf '%s\n' '端末が小さすぎます。端末ウィンドウを広げてください。' >&2
    return 1
  fi
  G_WIDTH="$best_width"
  h="$(art_height "$best_width")"
  G_COLS=$(( (cols-2+2)/(best_width+4) ))
  G_ROWS=$(( (rows-3+1)/(h+2) ))
  ((G_COLS>12)) && G_COLS=12
  G_PER_PAGE=$((G_COLS*G_ROWS))
}

# Clear the full screen with a deep blue backdrop; paint every tile using the
# palette's own background color, making backgrounds visually comparable.
gallery_backdrop() {
  printf '\033[0m\033[48;2;9;26;49m\033[38;2;214;235;255m\033[2J\033[H'
}

gallery_draw() {
  local page="$1" w="$G_WIDTH" h ncol="$G_COLS" nrow="$G_ROWS"
  local count pagecount col row i x y left top grid_w grid_h
  local tile_w tile_h line artline idx pad
  local -a art=()
  h="$(art_height "$w")"
  tile_w=$((w+2)); tile_h=$((h+1))
  count="${#PALETTE_IDS[@]}"
  pagecount=$(( (count+G_PER_PAGE-1)/G_PER_PAGE ))
  gallery_backdrop
  printf '\033[1;2H GNOSIS  /  CHNOUBIS  -  COLOR GALLERY          %d / %d ' \
    "$((page+1))" "$pagecount"
  grid_w=$((ncol*tile_w+(ncol-1)*2))
  grid_h=$((nrow*tile_h+(nrow-1)))
  left=$(( (TCOLS-grid_w)/2+1 )); ((left<1)) && left=1
  top=$(( (TROWS-3-grid_h)/2+2 )); ((top<2)) && top=2
  mapfile -t art < <(print_art "$w")
  for ((i=page*G_PER_PAGE; i<count && i<(page+1)*G_PER_PAGE; i++)); do
    idx="$i"
    col=$(( (i-page*G_PER_PAGE)%ncol ))
    row=$(( (i-page*G_PER_PAGE)/ncol ))
    x=$((left+col*(tile_w+2)))
    y=$((top+row*(tile_h+1)))
    choose_colors "$idx"
    # Heading & drawing are embedded in the same full background block.
    printf '\033[%d;%dH%b%b ' "$y" "$x" "$bg_ansi" "$fg_ansi"
    printf '[%02d] %-*s' "$((i+1))" "$((w-6))" "${PALETTE_IDS[$idx]}"
    printf ' '
    for ((line=0; line<h; line++)); do
      artline="${art[$line]}"
      pad=$((w-${#artline})); ((pad<0)) && pad=0
      printf '\033[%d;%dH%b%b %s%*s ' \
        "$((y+line+1))" "$x" "$bg_ansi" "$fg_ansi" "$artline" "$pad" ''
    done
  done
  printf '\033[0m\033[48;2;9;26;49m\033[38;2;214;235;255m'
  printf '\033[%d;2H 番号+Enter=拡大   n=次ページ   p=前ページ   q=終了 ' "$((TROWS-1))"
  printf '\033[%d;2H サイズ: %s列の絵   %s個ずつ表示   選択: ' "$TROWS" "$w" "$G_PER_PAGE"
}

preview_width() {
  local width height h
  local -a sizes=(80 60 44 32)
  if [[ "$art_width" != auto ]]; then
    sizes=("$art_width" 80 60 44 32)
  fi
  for width in "${sizes[@]}"; do
    h="$(art_height "$width")"
    if ((width<=TCOLS-2 && h<=TROWS-4)); then
      printf '%s' "$width"
      return
    fi
  done
  # Terminal is exceptionally narrow; return the smallest drawing.
  printf 32
}

preview_draw() {
  local idx="$1" w="$2" h x y line artline pad
  local -a art=()
  mapfile -t art < <(print_art "$w")
  h="${#art[@]}"
  choose_colors "$idx"
  printf '%b\033[2J\033[H' "$bg_ansi"
  printf '\033[1;2H%b [%d] %s  BG #%s  FG #%s ' \
    "$fg_ansi" "$((idx+1))" "${PALETTE_NAMES[$idx]}" \
    "${PALETTE_BGS[$idx]}" "${PALETTE_FGS[$idx]}"
  x=$(( (TCOLS-w)/2+1 )); ((x<1)) && x=1
  y=$(( (TROWS-4-h)/2+2 )); ((y<2)) && y=2
  for ((line=0; line<h && y+line<TROWS-1; line++)); do
    artline="${art[$line]}"
    printf '\033[%d;%dH%b%s' "$((y+line))" "$x" "$fg_ansi" "$artline"
  done
  printf '\033[%d;2H%b s+Enter=この配色を保存  Enter=一覧へ戻る  q=終了 ' \
    "$((TROWS-1))" "$fg_ansi"
  printf '\033[%d;2H%b 入力: ' "$TROWS" "$fg_ansi"
}

gallery_cleanup() {
  # Restore cursor, normal color and user's previous terminal screen.
  printf '\033[0m\033[?25h\033[?1049l'
}

interactive_gallery() {
  local page=0 pagecount idx answer response w
  if [[ ! -t 0 || ! -t 1 ]]; then
    printf '%s\n' 'Error: --gallery requires an interactive terminal.' >&2
    return 2
  fi
  if ((!can_color)); then
    printf '%s\n' 'Error: --gallery requires a true-color terminal.' >&2
    return 2
  fi
  printf '\033[?1049h\033[?25l'
  trap gallery_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  while :; do
    TCOLS="$(term_columns)"; TROWS="$(term_rows)"
    gallery_layout "$TCOLS" "$TROWS" "$art_width" || return 1
    pagecount=$(( (${#PALETTE_IDS[@]}+G_PER_PAGE-1)/G_PER_PAGE ))
    ((page>=pagecount)) && page=$((pagecount-1))
    gallery_draw "$page"
    printf '\033[?25h'
    IFS= read -r answer || return 0
    printf '\033[?25l'
    case "$answer" in
      q|Q) return 0 ;;
      n|N|'') page=$(( (page+1)%pagecount )); continue ;;
      p|P) page=$(( (page+pagecount-1)%pagecount )); continue ;;
    esac
    if ! idx="$(palette_index "$answer")"; then
      continue
    fi
    while :; do
      TCOLS="$(term_columns)"; TROWS="$(term_rows)"
      w="$(preview_width)"
      preview_draw "$idx" "$w"
      printf '\033[?25h'
      IFS= read -r response || return 0
      printf '\033[?25l'
      case "$response" in
        s|S)
          save_palette "$idx"
          return 0 ;;
        q|Q) return 0 ;;
        ''|b|B) break ;;
      esac
    done
  done
}

if ((do_list)); then
  list_palettes
  exit 0
fi

# Running the script by itself opens the gallery on an interactive terminal.
# When redirected/piped, preserve its usable behavior as plain artwork.
if ((do_gallery)) || { ((arg_count==0)) && [[ -t 0 && -t 1 ]]; }; then
  interactive_gallery
  exit $?
fi

palette_arg="${palette_arg:-$(get_saved_palette)}"
if ! idx="$(palette_index "$palette_arg")"; then
  printf 'Unknown palette: %s (see --list)\n' "$palette_arg" >&2
  exit 2
fi
cols="$(term_columns)"; rows="$(term_rows)"
sz="$(pick_width "$art_width" "$cols" "$rows" "$screen")"
if ((screen && can_color)); then
  render_screen "$idx" "$sz" "$cols" "$rows"
else
  render_plain "$idx" "$sz"
fi