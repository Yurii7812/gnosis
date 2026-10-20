" =============================================================================
" plugin/Gnosis.vim
" Gnosis - Vimwiki 非依存 Markdown PKM プラグイン
" =============================================================================

if exists('g:loaded_gnosis')
  finish
endif
let g:loaded_gnosis = 1

" ---------------------------------------------------------------------------
" 旧設定名の互換（simple-yurii-note → Gnosis）
"   vimrc の g:simple_yurii_note_* / g:simple_yurii_search_* / g:yurii_* は、同じ意味の
"   g:gnosis_* / g:gnosis_search_* にそのまま引き継ぐ。両方あるときは g:gnosis_* が優先。
"   （設定画面で変える項目は vault の .gnosis/settings.json が優先。autoload/gnosis/settings.vim）
" ---------------------------------------------------------------------------
for [s:old_prefix, s:new_prefix] in [['simple_yurii_search_', 'gnosis_search_'], ['simple_yurii_note_', 'gnosis_'], ['yurii_', 'gnosis_']]
  for s:old in keys(g:)
    if stridx(s:old, s:old_prefix) == 0
      let s:new = s:new_prefix . strpart(s:old, len(s:old_prefix))
      if !has_key(g:, s:new)
        let g:[s:new] = g:[s:old]
      endif
    endif
  endfor
endfor
unlet! s:old_prefix s:new_prefix s:old s:new

" ---------------------------------------------------------------------------
" デフォルト設定
" ---------------------------------------------------------------------------

" このプラグインは nc/np/ca/bu/bc/mp/mm/tt/yn/gm/gp/pe 等、素の単発
" コマンド（a, n, c, b, m, t, y, g, p, …）と1文字目が被る2文字マッピングを
" 大量に持つ。Vimの既定 timeoutlen=1000ms のままだと、それらの素の1文字
" キーを押すたびに「2文字目が来るかどうか」を最大1秒待ってから確定する
" ため、素のVimと比べて a 等の反応が明らかに遅く感じる。
" 該当キーの体感を悪化させずに待ち時間だけ短縮する（0 で変更しない）。
" 300msだと nt 等（1文字目と2文字目の間隔が nc 等より空きがち）が
" タイムアウトで無反応になることがあったため 500ms に調整。
if !exists('g:gnosis_timeoutlen')
  let g:gnosis_timeoutlen = 500
endif
if g:gnosis_timeoutlen > 0
  let &timeoutlen = g:gnosis_timeoutlen
endif

if !exists('g:gnosis_root')
  let g:gnosis_root = ''
endif
if !exists('g:gnosis_default_child_prefix')
  let g:gnosis_default_child_prefix = 'C'
endif
if !exists('g:gnosis_default_quick_prefix')
  let g:gnosis_default_quick_prefix = 'F'
endif
if !exists('g:gnosis_default_atomic_prefix')
  let g:gnosis_default_atomic_prefix = 'C'
endif
if !exists('g:gnosis_history_max')
  let g:gnosis_history_max = 200
endif
if !exists('g:gnosis_history')
  let g:gnosis_history = []
endif
" autosync: 保存後に自動更新するか (1=有効, 0=無効)
if !exists('g:gnosis_autosync')
  let g:gnosis_autosync = 1
endif
if !exists('g:gnosis_auto_save_on_command')
  " Heavy: saving on every :command causes CmdlineLeave lag and accidental redraw/reload.
  let g:gnosis_auto_save_on_command = 0
endif
if !exists('g:gnosis_sync_before_link_navigation')
  " Link jumps must stay instant; save-time AutoSync keeps links consistent.
  let g:gnosis_sync_before_link_navigation = 0
endif
if !exists('g:gnosis_save_before_link_navigation')
  " Do not write/trigger BufWritePost just because Enter follows a link.
  let g:gnosis_save_before_link_navigation = 0
endif
if !exists('g:gnosis_global_bare_link_navigation')
  " Avoid recursive root scans on Enter for bare filenames by default.
  let g:gnosis_global_bare_link_navigation = 0
endif
if !exists('g:gnosis_realtime_link_sync')
  " Heavy: TextChanged scans and may write linked notes; keep save-time sync as default.
  let g:gnosis_realtime_link_sync = 0
endif
if !exists('g:gnosis_realtime_link_sync_delay')
  let g:gnosis_realtime_link_sync_delay = 800
endif
if !exists('g:gnosis_realtime_link_sync_max_lines')
  let g:gnosis_realtime_link_sync_max_lines = 2000
endif
if !exists('g:gnosis_realtime_backlink_sync')
  let g:gnosis_realtime_backlink_sync = 0
endif
if !exists('g:gnosis_markdown_conceal_links')
  " Keep link URLs hidden by default; large/long-link buffers are guarded below.
  let g:gnosis_markdown_conceal_links = 1
endif
if !exists('g:gnosis_markdown_conceal_max_lines')
  " 1 万行の Index でもリンクをたたんで表示名だけ見せる（0 で無制限）。
  " 実測で 1 万行の描画は conceal 有無で差が出ないため既定を引き上げた。
  let g:gnosis_markdown_conceal_max_lines = 20000
endif
if !exists('g:gnosis_markdown_conceal_max_line_length')
  let g:gnosis_markdown_conceal_max_line_length = 0
endif
" リンク色は .vimrc 側で設定する想定

" Python スクリプトのパス
let s:plugin_root = fnamemodify(expand('<sfile>:p'), ':h:h')

" ノート形式。既定 'v2' = --- 境界 + 型付きセクション（詳細は repo の NOTE_FORMAT.md）。
" 旧 Parent:/Child:/BackLink: 形式に固定したい場合のみ 'v1' を明示する。
" v1 のノートは v2 sync で初回に自動変換される（Parent/Child リンク -> 関連:、Index -> グループ:）。
if !exists('g:gnosis_format')
  let g:gnosis_format = 'v2'
endif
if !exists('g:gnosis_python')
  if g:gnosis_format ==# 'v1'
    let g:gnosis_python = s:plugin_root . '/legacy/simple_yurii_note_sync.py'
  else
    let g:gnosis_python = s:plugin_root . '/python/note_format_v2.py'
  endif
endif
if !exists('g:gnosis_expand_s_python')
  let g:gnosis_expand_s_python = s:plugin_root . '/python/expand_s.py'
endif
if !exists('g:gnosis_expand_v2_python')
  let g:gnosis_expand_v2_python = s:plugin_root . '/python/expand_v2.py'
endif
if !exists('g:gnosis_gallery_python')
  let g:gnosis_gallery_python = s:plugin_root . '/python/gallery.py'
endif
if !exists('g:gnosis_gallery_port')
  let g:gnosis_gallery_port = 8765
endif

" :!rm % / :silent !rm % など Vim の :! でノートを消してもゴミ箱へ回す（bash 限定）。
" 非対話 bash が $BASH_ENV を読む性質を使い、rm をラップする（shell/gnosis-rm-guard.sh）。
if !exists('g:gnosis_rm_guard')
  let g:gnosis_rm_guard = 1
endif
if g:gnosis_rm_guard && !has('win32') && executable('bash')
  let s:rm_guard = s:plugin_root . '/shell/gnosis-rm-guard.sh'
  if filereadable(s:rm_guard)
    if empty($BASH_ENV)
      let $BASH_ENV = s:rm_guard
    elseif $BASH_ENV !=# s:rm_guard
      let g:gnosis_rm_guard = 0
      echohl WarningMsg | echom gnosis#i18n#tr('Gnosis: $BASH_ENV が既にあるため rm ゴミ箱ガードは無効') | echohl NONE
    endif
  endif
endif

augroup gnosis_shell_trash
  autocmd!
  " :!rm などでノートのファイルが消えていたら、バッファを閉じて同期する
  autocmd ShellCmdPost * call gnosis#after_shell_rm()
augroup END

" 挿入モードの <C-G> が timeoutlen 待ちにならないようにする。
" vim-surround は挿入モードに <C-G>s / <C-G>S / <C-S> を張るため、素の
" <C-G>u（undo 区切り）などが「s が続くかも」で待たされる。挿入モードの
" surround を使わないなら無効化してよい（ノーマル/ビジュアルの ys/cs/ds/S は残る）。
if !exists('g:surround_no_insert_mappings')
  let g:surround_no_insert_mappings = 1
endif

" ---------------------------------------------------------------------------
" コマンド定義
" ---------------------------------------------------------------------------

command!          GnosisToday call gnosis#diary_today()
command!          GnosisTabs call gnosis#tabs#popup()
command!          GnosisWNext call gnosis#write_next()
command! -bang -nargs=* GnosisContextMigrate call gnosis#context#migrate_command(<q-args>, <bang>0)
command!          GnosisFolgezettelMove call gnosis#folgezettel#toggle()
command!          GnosisBranchCheck call gnosis#branch#check_command()
command!          GnosisBranchFromContext call gnosis#branch#context_migrate()
command!          GnosisOpenLinkTab call gnosis#tabs#open_link()
command!          GnosisRefreshColors call gnosis#color#refresh()
command!          GnosisColorDoctor call gnosis#color#doctor()
command!          GnosisDiaryAdopt call gnosis#diary_adopt()
command!          SimpleDiaryUpdate call gnosis#diary_update()
command! -nargs=? UpdateMD   call gnosis#update_md(<q-args>)
command! -nargs=? UpdateAll  call gnosis#update_all(<q-args>)
command! -nargs=? UpdateALL  call gnosis#update_all(<q-args>)
command!          CheckPrefix call gnosis#check_missing_prefix_in_current_dir()
command! -nargs=* NF         call gnosis#new_quick(<q-args>)
command!          NA         call gnosis#new_here_typed('A')
command! -nargs=? NP         call gnosis#v2_new_parent(<q-args>)
command! -nargs=? NC         call gnosis#v2_new_child(<q-args>)
command!          NH         call gnosis#v2_new_here()
command! -nargs=? V2Migrate  call gnosis#v2_migrate(<q-args>)
command! -nargs=* CA         call gnosis#add_clipboard_to_branch()
command! -nargs=* CU         call gnosis#add_clipboard_before_up()
command! -nargs=* TT         call gnosis#add_clipboard_to_top()
command! -nargs=? NT         call gnosis#rename_title(<q-args>)
command! -nargs=? RenameLinkText call gnosis#rename_link_text(<q-args>)
command! -range=0 RenameChildLinkTitles call gnosis#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -range=0 RenameDownLinkTitles call gnosis#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -nargs=? LT         call gnosis#rename_link_text(<q-args>)
command! -nargs=* BC         call gnosis#add_from_clipboard(<f-args>)
command!          YN         call gnosis#yank_name()
command!          AT         call gnosis#at_add()
command!          Linkify    call gnosis#linkify_filename_under_cursor()
command!          LinkifySelection call gnosis#linkify_selection_new_note()
command!          PasteLink  call gnosis#paste_clipboard_link_here()
command! -range=0 ToggleCheckbox call gnosis#toggle_checkbox(<line1>, <line2>, <range>)
command!          SortYomi   call gnosis#sort_yomi()
command! -range=0 -bang SortTime call gnosis#sort_time(<bang>0, <line1>, <line2>, <range>)

" 旧名エイリアス（yurii_PKM から移行した習慣用。中身は simple 側）
command! -nargs=? ExpandLinks call gnosis#expand_s_under_cursor(<q-args>)
command!          JumpLastLinkBeforeParent call gnosis#jump_last_link_before_up()
command!          JumpParent call gnosis#jump_up()
command!          JumpChildTop call gnosis#jump_down_top()
command!          JumpChildBottom call gnosis#jump_down_bottom()
command!          JumpLastLinkBeforeUp call gnosis#jump_last_link_before_up()
command!          JumpUp     call gnosis#jump_up()
command!          JumpDownTop call gnosis#jump_down_top()
command!          JumpDownBottom call gnosis#jump_down_bottom()

command! -nargs=? ExpandToT  call gnosis#expand_s_under_cursor(<q-args>)
command! -nargs=? SE         call gnosis#expand_s_under_cursor(<q-args>)
command!          RP         call gnosis#rename_prefix()
command!          OutlineEdit call gnosis#outline_edit()
command! -nargs=? Gallery    call gnosis#open_gallery(<q-args>)
command! -nargs=? GalleryFolder call gnosis#open_folder_gallery(<q-args>)
" テーブル操作コマンド
command! -nargs=* TN         call gnosis#table_new(<q-args>)
command! -nargs=* NewTable   call gnosis#table_new(<q-args>)
command!          TA         call gnosis#table_align_current()
command!          TRE        call gnosis#table_row_edit()
command!          TCSV       call gnosis#table_csv_edit()
command!          TableCsvEdit call gnosis#table_csv_edit()
command!          TableCsvApplySaved call gnosis#table_csv_editor_apply_saved()
command!          TCE        call gnosis#table_to_csv()
command!          TableToCsv call gnosis#table_to_csv()
command!          CsvToTable call gnosis#csv_to_table()
command!          TableCsvNew call gnosis#csv_new()
command!          TCN        call gnosis#csv_new()
command!          TDR        call gnosis#table_del_row()
command!          TDC        call gnosis#table_del_col()
command!          TAR        call gnosis#table_add_row()
command!          TAC        call gnosis#table_add_col()

" ---- Yurii* の統一別名（既存の名前と同じ動作。既存は残す） ----
" 入口だけのコマンド（:PlugInstall 等の prefix と同じ役割）。Tab で Yurii* の候補を出す用。
command! -nargs=0 Gnosis echo gnosis#i18n#tr('Gnosis のコマンドは :Gnosis<Tab> で候補を表示')
command! -nargs=? GnosisUpdateMD call gnosis#update_md(<q-args>)
command! -nargs=? GnosisUpdateAll call gnosis#update_all(<q-args>)
command!          GnosisCheckPrefix call gnosis#check_missing_prefix_in_current_dir()
command! -nargs=* GnosisNF call gnosis#new_quick(<q-args>)
command!          GnosisNA call gnosis#new_here_typed('A')
command! -nargs=? GnosisNP call gnosis#v2_new_parent(<q-args>)
command! -nargs=? GnosisNC call gnosis#v2_new_child(<q-args>)
command!          GnosisNH call gnosis#v2_new_here()
command! -nargs=? GnosisV2Migrate call gnosis#v2_migrate(<q-args>)
command! -nargs=* GnosisCA call gnosis#add_clipboard_to_branch()
command! -nargs=* GnosisCU call gnosis#add_clipboard_before_up()
command! -nargs=* GnosisTT call gnosis#add_clipboard_to_top()
command! -nargs=? GnosisNT call gnosis#rename_title(<q-args>)
command! -nargs=? GnosisRenameLinkText call gnosis#rename_link_text(<q-args>)
command! -range=0 GnosisRenameChildLinkTitles call gnosis#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -range=0 GnosisRenameDownLinkTitles call gnosis#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -nargs=? GnosisLT call gnosis#rename_link_text(<q-args>)
command! -nargs=* GnosisBC call gnosis#add_from_clipboard(<f-args>)
command!          GnosisYN call gnosis#yank_name()
command!          GnosisAT call gnosis#at_add()
command!          GnosisLinkify call gnosis#linkify_filename_under_cursor()
command!          GnosisLinkifySelection call gnosis#linkify_selection_new_note()
command!          GnosisPasteLink call gnosis#paste_clipboard_link_here()
command! -range=0 GnosisToggleCheckbox call gnosis#toggle_checkbox(<line1>, <line2>, <range>)
command!          GnosisSortYomi call gnosis#sort_yomi()
command! -range=0 -bang GnosisSortTime call gnosis#sort_time(<bang>0, <line1>, <line2>, <range>)
command!          GnosisIndex call gnosis#open_index()
command!          GnosisDiaryUpdate call gnosis#diary_update()
command!          GnosisStart call gnosis#start#open()
command!          GnosisVaults call gnosis#start#open_vaults()
command!          GnosisSettings call gnosis#settings_ui#open()
command! -nargs=1 GnosisThemeAdd call gnosis#theme#add_command(<q-args>)
command!          GnosisThemeReset call gnosis#settings#set('theme', {'kind': 'builtin'})
" 文字サイズ（Gnosis 全体。:GnosisFontSize 20 / +1 / -1 / reset。引数なしで今の大きさ）
command! -nargs=? GnosisFontSize call gnosis#termfont#command(<q-args>)
" リンクの元の Markdown（[表示名](ファイル名)）を見せる・隠すの切り替え（このバッファだけ）
command! -nargs=?  GnosisLinkSource call gnosis#toggle_link_source(<f-args>)

" BranchGroup の起点を親にする動作（セッション全体。zn と za の両方）。
function! s:group_parent_mode(...) abort
  if a:0 && index(['on', 'off'], a:1) < 0
    echoerr 'GnosisGroupParent [on|off]'
    return
  endif
  let g:gnosis_group_inherit_parent = a:0 ? a:1 ==# 'on' : !get(g:, 'gnosis_group_inherit_parent', 1)
  echo gnosis#i18n#tr('BranchGroup の起点を親にする: %s', g:gnosis_group_inherit_parent ? 'ON' : 'OFF')
endfunction
command! -nargs=? GnosisGroupParent call s:group_parent_mode(<f-args>)

command!          GnosisChooseIndexDir call gnosis#choose_index_root()
command!          GnosisChooseIndex call gnosis#choose_index_root()
command!          GnosisGuide call gnosis#write_guide()
command!          GnosisPaperIndex call gnosis#paper_index()
command!          GnosisScan call gnosis#paper_scan()
command! -nargs=? GnosisExpandLinks call gnosis#expand_s_under_cursor(<q-args>)
command! -nargs=? GnosisExpandToT call gnosis#expand_s_under_cursor(<q-args>)
command! -nargs=? GnosisSE call gnosis#expand_s_under_cursor(<q-args>)
command!          GnosisJumpLastLinkBeforeParent call gnosis#jump_last_link_before_up()
command!          GnosisJumpLastLinkBeforeUp call gnosis#jump_last_link_before_up()
command!          GnosisJumpParent call gnosis#jump_up()
command!          GnosisJumpUp call gnosis#jump_up()
command!          GnosisJumpChildTop call gnosis#jump_down_top()
command!          GnosisJumpDownTop call gnosis#jump_down_top()
command!          GnosisJumpChildBottom call gnosis#jump_down_bottom()
command!          GnosisJumpDownBottom call gnosis#jump_down_bottom()
command!          GnosisRP call gnosis#rename_prefix()
command!          GnosisOutlineEdit call gnosis#outline_edit()
command! -nargs=? GnosisGallery call gnosis#open_gallery(<q-args>)
command! -nargs=? GnosisGalleryFolder call gnosis#open_folder_gallery(<q-args>)
command!          GnosisWeb call gnosis#open_web()
command!          GnosisTrash call gnosis#trash_current()
command!          GnosisTrashList call gnosis#trash_list()
command!          GnosisTrashEmpty call gnosis#trash_empty()
command!          GnosisSetPassword call gnosis#set_password()
command!          GnosisRemovePassword call gnosis#remove_password()
command!          GnosisMount call gnosis#mount_vault()
command! -bang    GnosisLock call gnosis#lock_vault(<bang>0)
" 暗号箱(.crypt)を vault のパスワードで 7z 化して <出力先>/<日時>-<名前>.7z に出力
command! -nargs=? -complete=dir GnosisBackup call gnosis#backup_vault(<q-args>)
command!          GnosisExitCleanup call gnosis#exit_cleanup()
command! -nargs=* GnosisTableNew call gnosis#table_new(<q-args>)
command!          GnosisTableAlign call gnosis#table_align_current()
command!          GnosisTableRowEdit call gnosis#table_row_edit()
command!          GnosisTableCsvEdit call gnosis#table_csv_edit()
command!          GnosisTableCsvApplySaved call gnosis#table_csv_editor_apply_saved()
command!          GnosisTableToCsv call gnosis#table_to_csv()
command!          GnosisCsvToTable call gnosis#csv_to_table()
command!          GnosisTableCsvNew call gnosis#csv_new()
command!          GnosisTableDelRow call gnosis#table_del_row()
command!          GnosisTableDelCol call gnosis#table_del_col()
command!          GnosisTableAddRow call gnosis#table_add_row()
command!          GnosisTableAddCol call gnosis#table_add_col()

" 別ファイル（plugin/*.vim）で定義された既存コマンドへの別名
command!          GnosisRename Rename
command! -range   GnosisSetImageSize <line1>,<line2>SetImageSize
command!          GnosisAutocwindow Autocwindow
command!          GnosisFSearch call gnosis_search#run()
command!          GnosisSearch call gnosis_search#run()
command!          GnosisLinkPick call gnosis_search#pick_insert_link()
command! -nargs=+ GnosisFileContentSearch FileContentSearch <args>
command!          GnosisCopyStack CopyStack


" ---- 旧名（互換）: :Yurii* は :Gnosis* と同じ動作。g:gnosis_legacy_commands = 0 で定義しない ----
if get(g:, 'gnosis_legacy_commands', get(g:, 'simple_yurii_note_legacy_commands', 1))
  command! YuriiToday call gnosis#diary_today()
  command! YuriiDiaryAdopt call gnosis#diary_adopt()
  command! -nargs=? YuriiUpdateMD call gnosis#update_md(<q-args>)
  command! -nargs=? YuriiUpdateAll call gnosis#update_all(<q-args>)
  command! YuriiCheckPrefix call gnosis#check_missing_prefix_in_current_dir()
  command! -nargs=* YuriiNF call gnosis#new_quick(<q-args>)
  command! YuriiNA call gnosis#new_here_typed('A')
  command! -nargs=? YuriiNP call gnosis#v2_new_parent(<q-args>)
  command! -nargs=? YuriiNC call gnosis#v2_new_child(<q-args>)
  command! YuriiNH call gnosis#v2_new_here()
  command! -nargs=? YuriiV2Migrate call gnosis#v2_migrate(<q-args>)
  command! -nargs=* YuriiCA call gnosis#add_clipboard_to_branch()
  command! -nargs=* YuriiCU call gnosis#add_clipboard_before_up()
  command! -nargs=* YuriiTT call gnosis#add_clipboard_to_top()
  command! -nargs=? YuriiNT call gnosis#rename_title(<q-args>)
  command! -nargs=? YuriiRenameLinkText call gnosis#rename_link_text(<q-args>)
  command! -range=0 YuriiRenameChildLinkTitles call gnosis#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
  command! -range=0 YuriiRenameDownLinkTitles call gnosis#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
  command! -nargs=? YuriiLT call gnosis#rename_link_text(<q-args>)
  command! -nargs=* YuriiBC call gnosis#add_from_clipboard(<f-args>)
  command! YuriiYN call gnosis#yank_name()
  command! YuriiAT call gnosis#at_add()
  command! YuriiLinkify call gnosis#linkify_filename_under_cursor()
  command! YuriiLinkifySelection call gnosis#linkify_selection_new_note()
  command! YuriiPasteLink call gnosis#paste_clipboard_link_here()
  command! -range=0 YuriiToggleCheckbox call gnosis#toggle_checkbox(<line1>, <line2>, <range>)
  command! YuriiSortYomi call gnosis#sort_yomi()
  command! -range=0 -bang YuriiSortTime call gnosis#sort_time(<bang>0, <line1>, <line2>, <range>)
  command! YuriiIndex call gnosis#open_index()
  command! YuriiChooseIndexDir call gnosis#choose_index_root()
  command! YuriiChooseIndex call gnosis#choose_index_root()
  command! YuriiGuide call gnosis#write_guide()
  command! YuriiPaperIndex call gnosis#paper_index()
  command! YuriiScan call gnosis#paper_scan()
  command! -nargs=? YuriiExpandLinks call gnosis#expand_s_under_cursor(<q-args>)
  command! -nargs=? YuriiExpandToT call gnosis#expand_s_under_cursor(<q-args>)
  command! -nargs=? YuriiSE call gnosis#expand_s_under_cursor(<q-args>)
  command! YuriiJumpLastLinkBeforeParent call gnosis#jump_last_link_before_up()
  command! YuriiJumpLastLinkBeforeUp call gnosis#jump_last_link_before_up()
  command! YuriiJumpParent call gnosis#jump_up()
  command! YuriiJumpUp call gnosis#jump_up()
  command! YuriiJumpChildTop call gnosis#jump_down_top()
  command! YuriiJumpDownTop call gnosis#jump_down_top()
  command! YuriiJumpChildBottom call gnosis#jump_down_bottom()
  command! YuriiJumpDownBottom call gnosis#jump_down_bottom()
  command! YuriiRP call gnosis#rename_prefix()
  command! YuriiOutlineEdit call gnosis#outline_edit()
  command! -nargs=? YuriiGallery call gnosis#open_gallery(<q-args>)
  command! -nargs=? YuriiGalleryFolder call gnosis#open_folder_gallery(<q-args>)
  command! YuriiWeb call gnosis#open_web()
  command! YuriiTrash call gnosis#trash_current()
  command! YuriiTrashList call gnosis#trash_list()
  command! YuriiTrashEmpty call gnosis#trash_empty()
  command! YuriiSetPassword call gnosis#set_password()
  command! YuriiRemovePassword call gnosis#remove_password()
  command! YuriiMount call gnosis#mount_vault()
  command! -bang YuriiLock call gnosis#lock_vault(<bang>0)
  command! -nargs=? -complete=dir YuriiBackup call gnosis#backup_vault(<q-args>)
  command! YuriiExitCleanup call gnosis#exit_cleanup()
  command! -nargs=* YuriiTableNew call gnosis#table_new(<q-args>)
  command! YuriiTableAlign call gnosis#table_align_current()
  command! YuriiTableRowEdit call gnosis#table_row_edit()
  command! YuriiTableCsvEdit call gnosis#table_csv_edit()
  command! YuriiTableCsvApplySaved call gnosis#table_csv_editor_apply_saved()
  command! YuriiTableToCsv call gnosis#table_to_csv()
  command! YuriiCsvToTable call gnosis#csv_to_table()
  command! YuriiTableCsvNew call gnosis#csv_new()
  command! YuriiTableDelRow call gnosis#table_del_row()
  command! YuriiTableDelCol call gnosis#table_del_col()
  command! YuriiTableAddRow call gnosis#table_add_row()
  command! YuriiTableAddCol call gnosis#table_add_col()
  command! YuriiRename Rename
  command! -range YuriiSetImageSize <line1>,<line2>SetImageSize
  command! YuriiAutocwindow Autocwindow
  command! YuriiFSearch call gnosis_search#run()
  command! YuriiLinkPick call gnosis_search#pick_insert_link()
  command! -nargs=+ YuriiFileContentSearch FileContentSearch <args>
  command! YuriiCopyStack CopyStack
  command! -nargs=0 Yurii Gnosis
endif

nnoremap <silent> \tn  :NewTable<CR>
nnoremap <silent> \ta  :TA<CR>
nnoremap <silent> \te  :TRE<CR>
nnoremap <silent> \tc  :TableToCsv<CR>
nnoremap <silent> \tt  :CsvToTable<CR>
nnoremap <silent> \tnc :TableCsvNew<CR>
nnoremap <silent> \tar :TAR<CR>
nnoremap <silent> \tac :TAC<CR>
nnoremap <silent> \tdr :TDR<CR>
nnoremap <silent> \tdc :TDC<CR>
nnoremap <silent> \ua  :UpdateAll<CR>
nnoremap <silent> \d   <Cmd>call gnosis#diary_today()<CR>
" 時刻: Ctrl-T で「時:分 」を入れる（ノーマルでは挿入モードに入って入れる。Vim 標準の Ctrl-T の字下げ・タグ戻りの代わり）
" \T で時刻モード（Enter のたびに空行と次の行の頭に時刻）をオン／オフ
inoremap <silent> <C-t> <C-r>=gnosis#time_stamp()<CR>
nnoremap <silent> <C-t> i<C-r>=gnosis#time_stamp()<CR>
nnoremap <silent> \T   <Cmd>call gnosis#time_mode_toggle()<CR>
command! GnosisTimeMode call gnosis#time_mode_toggle()
" 時刻モードはそのノートだけ: 開いたときに決め（時系列記録のノートはオン）、閉じる・ほかのノートへ移ると取りやめる。書き始めた行の頭に時刻
augroup gnosis_time_mode
  autocmd!
  autocmd BufWinEnter *.md call gnosis#time_mode_on_enter(str2nr(expand('<abuf>')))
  autocmd BufWinLeave,BufUnload *.md call gnosis#time_mode_on_leave(str2nr(expand('<abuf>')))
  autocmd InsertCharPre *.md call gnosis#time_char_pre()
augroup END
" 時系列記録（夢など。日記と同じ形で日ごとのノート）: \R で選んで今日のノートを作る・開く
nnoremap <silent> \R   <Cmd>call gnosis#record_pick()<CR>
command! GnosisRecord call gnosis#record_pick()
command! -nargs=? GnosisRecordNew call gnosis#record_new(<q-args>)
command! -nargs=+ GnosisRecordMigrate call gnosis#record_migrate(<f-args>)
command! -nargs=* GnosisRecordMerge call gnosis#record_merge(<f-args>)
" zw … 今のノート（日記でなくてもよい）の本文の一番下、空行を 1 つ空けたところから書き始める。
nnoremap <silent> zw  <Cmd>call gnosis#write_at_bottom()<CR>
" \\r はリンクの内容を触らず、Vim側の検索/matchハイライトと色を再適用。
nnoremap <silent> \r   <Cmd>call gnosis#color#refresh()<CR>

nnoremap <silent> \se  <Cmd>call <SID>expand_s_and_open()<CR>
nnoremap <nowait> <silent> mp  <Cmd>call gnosis#rename_prefix()<CR>

" ---------------------------------------------------------------------------
" キーマッピング
" ---------------------------------------------------------------------------

" リンクナビゲーション
nnoremap <silent> <Tab>    <Cmd>call gnosis#jump_link(1)<CR>
nnoremap <silent> <S-Tab>  <Cmd>call gnosis#jump_link(0)<CR>
" 注意: 以前は Shift-Tab 保険で `\<Esc>[Z` を nnoremap していたが、これを張ると
" 素の Esc が「[Z が続くかも」と timeoutlen（既定500ms）待つため、Esc がワンテンポ
" 遅れていた。端末互換は s:setup_backtab() の `set <S-Tab>=\e[Z`（termcap）で足りる。
nnoremap <silent> <CR>     <Cmd>call gnosis#open_link_under_cursor()<CR>
nnoremap <silent> <BS>     <Cmd>call gnosis#go_back()<CR>
" 履歴を前へ（⌫ の対）。戻りが可逆になるので、戻るのを躊躇しなくなる。
nnoremap <silent> <S-BS>   <Cmd>call gnosis#go_forward()<CR>
nnoremap <silent> \.       <Cmd>call gnosis#go_forward()<CR>
" 直前ノートとの1キー往復（A⇄B）。読むもの・選ぶものゼロの最速移動。
nnoremap <silent> _        <Cmd>call gnosis#toggle_alternate()<CR>
" \h は永続的な保管リスト。\H で現在のノートを追加する。
" 旧 \1..\9 / \0 は不要なので廃止。通常の数字入力を妨げない。
nnoremap <silent> \h       <Cmd>call gnosis#hub_open()<CR>
nnoremap <silent> \H       <Cmd>call gnosis#hub_set()<CR>
" \a … 未所属（Folgezettel ID の無い）ノートの一覧（全体を見て整理する）。\N も同じ（押しにくいので \a を足した）
nnoremap <silent> \a       <Cmd>call gnosis#orphans_open()<CR>
nnoremap <silent> \N       <Cmd>call gnosis#orphans_open()<CR>
nnoremap <silent> \n       <Cmd>call gnosis#quick_note()<CR>
nnoremap <silent> \M       <Cmd>call gnosis#capture_import()<CR>
command! GnosisQuick call gnosis#quick_note()
command! -nargs=? -complete=file GnosisCaptureImport call gnosis#capture_import(<q-args>)
command! GnosisCaptureConflicts call gnosis#capture_conflicts()
command! -nargs=+ GnosisCaptureResolve call gnosis#capture_resolve(<f-args>)
command! GnosisApkInstall call gnosis#apk_install()
command! -nargs=? -range GnosisTopic call gnosis#topic#assign(<line1>, <line2>, <q-args>)
command! GnosisOrphans call gnosis#orphans_open()
" \l → m でマージしたノートを元に戻す
command! GnosisMergeUndo call gnosis#merge#undo()
command! GnosisYomiReview call gnosis#yomi_review()
command! GnosisReview call gnosis#review_reopen()
" \q は作業タブ管理。\o はリンクを別の論理タブとして開く。
nnoremap <silent> \q       <Cmd>call gnosis#tabs#popup()<CR>
nnoremap <silent> \o       <Cmd>call gnosis#tabs#open_link()<CR>
" ノート移動では現作業タブの内容だけ更新（新タブは増やさない）。
augroup gnosis_work_tabs
  autocmd!
  autocmd BufEnter *.md call gnosis#tabs#on_enter()
augroup END
" ゴミ箱（ソフト削除）: \tr=一覧（⏎=開く / ^r=復元 / ^e=空） / \tD=今のノートをゴミ箱へ / \tE=空にする
"   （\td は \tdr/\tdc（表の行・列削除）と待ちが被るので \tD にする）
nnoremap <silent> \tr       <Cmd>call gnosis#trash_list()<CR>
nnoremap <silent> \tD       <Cmd>call gnosis#trash_current()<CR>
nnoremap <silent> \tE       <Cmd>call gnosis#trash_empty()<CR>
" \i … index.md を開く（2打）。\s は \se（展開）の前置きと被って待たされるので使わない。
nnoremap <silent> \i       <Cmd>call gnosis#open_index()<CR>
" \f … 紙PKM Index を開く（無ければ作成。更新は \ua）
" \F … スキャン画像にフォルゲゼッテルIDを付けて vault 直下へ移動（番号付け GUI）
nnoremap <silent> \f       <Cmd>call gnosis#paper_index()<CR>
nnoremap <silent> \F       <Cmd>call gnosis#paper_scan()<CR>
" \S … リンク行を表示名のよみ順（五十音 → ローマ字は末尾）に安定ソート。
"   ビジュアル=選択範囲 / ノーマル=バッファ全体（主に index.md）。
"   よみはリンク先ノートの front matter `yomi:`（\zy で登録）、無ければ pykakasi。
nnoremap <silent> \S <Cmd>call gnosis#sort_yomi()<CR>
xnoremap <silent> \S :<C-u>call gnosis#sort_selection()<CR>
" <Space> / gs … ノートナビゲータ。状態は「打つ / 打たない」の1つだけ。
"   ⏎ で打つのをやめる、i で打ちに戻る。/ はクエリを消して打つ。
"   打たない状態のキーはローカルでもグローバルでも完全に同じ。
"   スコープ（ローカル=今のノートのリンク / グローバル=全ノート）は ⇥ で切替。
"   上のバー: 「検索 …▏」= 打てる / 「◎ ノート名」「全ノート」= 打たない。
"
"   打たない（コマンド）
"     ラベル(1-0/英字)= ローカルは潜る / 検索結果は移動だけ（⏎ 開く・l 潜る）
"     jk 選択 / gG 端 / ⏎ 開く / ⌫ h 戻る
"     ␣ アンカーを開く / f b プレビュー / c p 子親に追加 / y ヤンク / m M マーク
"     a アンカー移動 / i 打つ / / 消して打つ / ⇥ スコープ / ⎋ 取消
"
"   打つ（入力）
"     打つ=絞る（ラベルが無いので数字もクエリに入る）/ ⌫ 消す(空なら戻る)
"     ↑↓ 選択 / → 潜る / ← 戻る / ⏎ 入力終了 / ⎋ 消して終了 / ⇥ スコープ
"     + - * = も記号としてそのまま打てる（子親追加・マーク・ヤンクは ⏎ で
"     入力を終えたコマンド状態か、英字キー c/p/m/y で行う）
" <S-Space> … ポップアップを出さずカーソルだけ次の関係リンクへ（従来動作）。
nnoremap <silent> <Space>   <Cmd>call gnosis#relation_link_popup()<CR>
nnoremap <silent> <S-Space> <Cmd>call gnosis#jump_relation_link(1)<CR>
" 数字 1-9,0 … 本文 → Parent/Child の順で通し番号にした N 番目のリンクへ移動
"（0 は10番目）。該当リンクが無い所ではそのままカウント/行頭移動として働く
"（v:count 付きの 0 や、該当リンクが無いときの生の 0 は素通しされる）。
" 11番目以降は「文字+数字」の2打、1→0順（n1, n2, …, n9, n0, c1, …）。
" 頭文字はこのプラグインが既に2打コマンドの頭文字として使っている
" n/t/c/b/m/p/y のみを使うので、他の生キー（a, i, o 等）とは干渉しない。
" リンクの手前にラベルが仮想テキストで表示されるので、数えずに押す
" キーが分かる（g:gnosis_link_hints=0 で表示だけ無効化）。
for s:n in range(1, 9)
  execute printf('nnoremap <silent> %d <Cmd>call gnosis#digit_key(%d, "%d")<CR>', s:n, s:n, s:n)
endfor
nnoremap <silent> 0 <Cmd>call gnosis#digit_key(10, "0")<CR>
unlet s:n
augroup gnosis_link_hints
  autocmd!
  " ノートを開いた時は即時に（1回だけ）。挿入モードを抜けた時（Esc）は
  " 重い再計算（大きいノートで約45ms）を同期でやると Esc がもっさりするので、
  " TextChanged と同じ debounce に回す。ラベルは少し遅れて更新されるが、
  " 数字ジャンプ等は s:hint_positions を直接見るので機能は遅れない。
  " 外から読み直された（同期・別ウィンドウの保存）・ウィンドウを移った・ファイル種別が決まった、
  " ときも作り直す（読み直しでテキストプロパティが消えるのに、番号が出ないままになるのを防ぐ）。
  autocmd BufEnter,BufWinEnter,BufReadPost,WinEnter,FileChangedShellPost *.md call s:refresh_link_hints_now()
  autocmd FileType markdown,vimwiki call s:refresh_link_hints_now()
  " ノートを画面に出したとき・外から読み直したときは、画面全体を描き直す（前のページの文字が端末に残らないように）。
  " その場で描く（遅れて描くと、そのあとに出る質問の案内が消える）
  autocmd BufWinEnter,FileChangedShellPost *.md if mode() ==# 'n' && &buftype ==# '' | redraw! | endif
  autocmd TextChanged,InsertLeave *.md call s:schedule_refresh_link_hints()
  " 念のための安全網: 本文が変わったのに番号が古いままなら、カーソルを動かした・止めたときに作り直す。
  autocmd CursorMoved,CursorHold *.md if get(g:, 'gnosis_link_hints', 1) && (&l:filetype ==# 'markdown' || &l:filetype ==# 'vimwiki') && get(b:, 'gnosis_hint_built_tick', -1) != b:changedtick | call s:schedule_refresh_link_hints() | endif
  " ラベルはドキュメント順で固定なのでスクロールでの振り直しは不要。
augroup END

" 連続する TextChanged をまとめて、最後の 1 回だけヒントを更新する。
function! s:schedule_refresh_link_hints() abort
  if exists('b:gnosis_hint_timer')
    call timer_stop(b:gnosis_hint_timer)
  endif
  if has('timers')
    let b:gnosis_hint_timer =
          \ timer_start(get(g:, 'gnosis_link_hints_delay', 120),
          \ {-> s:refresh_link_hints_now()})
  else
    call gnosis#refresh_link_hints()
  endif
endfunction

" 番号を作り直して、すぐ画面に出す。タイマーや autocmd の中で足した仮想テキストは、
" 再描画しないと次のキー入力（カーソル移動）まで画面に出ないことがある。
function! s:refresh_link_hints_now() abort
  call gnosis#refresh_link_hints()
  if mode() ==# 'n'
    redraw
  endif
endfunction
" 標準のジャンプリスト戻りでも、E37 を出さず保存してから移動する
nnoremap <silent> <C-O>    <Cmd>call gnosis#save_before_normal_jump("\<C-O>")<CR>
" \bu（旧 bu）: 「b」は素の後退移動と1文字目が被り、素の b が timeoutlen 待ちに
"   なるため \ 側へ移した（素のキーを即時にする）
nnoremap <nowait> <silent> \bu <Cmd>call gnosis#jump_last_link_before_up()<CR>
" \k / \j / \J（旧 ,, / ,. / ,/）: 1文字目が素の「,」（f/t リピート）と被り
" timeoutlen 待ちになるため \ 側へ移した。k=上 / j=下 の連想。
nnoremap <nowait> <silent> \k  <Cmd>call gnosis#jump_up_cursor()<CR>
nnoremap <nowait> <silent> \j  <Cmd>call gnosis#jump_down_top()<CR>
" \m … 本文の終わりから一番近い関係の見出し（ChildBranch: / Related: / BackLink: など）へ
nnoremap <nowait> <silent> \m  <Cmd>call gnosis#jump_last_section()<CR>
nnoremap <nowait> <silent> \J  <Cmd>call gnosis#jump_down_bottom()<CR>

" ノート作成（リレーションは書かず、位置だけを選ぶ）
"   zn … ノート作成。作成後に位置キー1つで、素のリンク 1 行を現ノート側に置く:
"        h=カーソル直下（本文 → 相手には バックリンク:）/ Enter=Child末尾 /
"        t=見出しの下（今のノートの見出しを選ぶと、その本文の最後に空行を挟んでリンクを置く。
"        検索は見出し優先で、見出しの下の本文にもヒット）/
"        o=リンク無し(孤立) / p=Parent末尾。関係（ノート: 等）はあとから手で書く。
"   zk … グループノート作成（attribute: グループ）。位置キーは zn と同じ。
"   zh … カーソル直下にリンク（zn の h と同じ。本文リンク扱い）
" 頭文字は n ではなく z を使う（z は素のVimでも単独では何も起きない接頭辞
" なので、検索リピートの n/N とバッティングしない）。<nowait> は付けない
" — 付けると zk/zn 等より z が即座に確定してしまい、それらに繋がらなくなる。
" timeoutlen 経過後だけ発火する。
nnoremap <nowait> <silent> zh  <Cmd>call gnosis#v2_new_here()<CR>
nnoremap <nowait> <silent> zn  <Cmd>call gnosis#v2_new_plain()<CR>
nnoremap <nowait> <silent> zk  <Cmd>call gnosis#v2_new_group()<CR>
" zk（ビジュアル）… 選択範囲を中身にしたグループノートを作る（選択はグループへのリンクに置換）。
xnoremap <nowait> <silent> zk  :<C-u>call gnosis#v2_new_group_visual()<CR>
"" za: クリップボード／ヤンクしたリンクを、位置キーで今のノートに入れる（\l と同じ位置キー）
nnoremap <nowait> <silent> za  <Cmd>call gnosis#add_clipboard_before_up_note()<CR>
" （旧操作 ca / cu / \ca / tt / ta / \at / \bc / zp / zap のキー割り当ては廃止。関数と :CA などのコマンドは互換のため残す）
" zA: za と同じだが、追加前に「表示名」を入力する（既定は za が使う表示名。
"     空 Enter / Esc で中止）。Vim 標準の折りたたみ zA は上書きされる。
nnoremap <nowait> <silent> zA  <Cmd>call gnosis#add_clipboard_before_up_note_named()<CR>
" \e（旧 pe）: 現ノートを起点に親/子/文中/関連を辿って 1 つの md へ展開（v2 専用、.trash/T_<timestamp>.md）。
" シンプル（深さ1つ）/ 詳細（親・子・文中・関連を別々の深さ、前回設定を再利用可）を選ぶ。
" 「p」は素の貼り付けと1文字目が被り、素の p が timeoutlen 待ちになるため \ 側へ移した。
nnoremap <nowait> <silent> \e  <Cmd>call gnosis#v2_expand()<CR>
" zt: タイトル変更（空欄から開始）
nnoremap <nowait> <silent> zt  <Cmd>call gnosis#rename_title_with_default('')<CR>
" zT: 現在タイトルを残して編集
nnoremap <nowait> <silent> zT  <Cmd>call gnosis#rename_title('')<CR>
" zl: リンク表示名変更（空欄から開始）
nnoremap <nowait> <silent> zl  <Cmd>call gnosis#rename_link_text_with_default('')<CR>
" zL: 現在のリンク表示名を残して編集
nnoremap <nowait> <silent> zL  <Cmd>call gnosis#rename_link_text('')<CR>
" zy: 今開いているノートのタイトルのよみを
"     空欄から変更する（zt と同じ流儀。Esc で中止）。
"     よみは \S / :SortYomi の表示名ソートで使う。
nnoremap <nowait> <silent> zy  <Cmd>call gnosis#rename_yomi_with_default('')<CR>
" zY: 現在のよみ（未登録なら pykakasi 推測）を残して編集（zT と同じ流儀。
"     全部消して Enter でよみを削除）。
nnoremap <nowait> <silent> zY  <Cmd>call gnosis#rename_yomi('')<CR>
" zd: Child: のリンク表示名をリンク先 YAML title に更新
nnoremap <nowait> <silent> zd  <Cmd>RenameChildLinkTitles<CR>
vnoremap <nowait> <silent> zd  :<C-u>'<,'>RenameChildLinkTitles<CR>
" yn: 現在のファイル名をヤンク
nnoremap <nowait> <silent> yn  <Cmd>call gnosis#yank_name()<CR>
" \y: 題と本文だけをコピー（YAML と関係のブロックは除く。ノートへのリンクは表示名だけ）
nnoremap <nowait> <silent> \y  <Cmd>call gnosis#yank_title_body()<CR>

" \v / \V: システムクリップボード（PCの直近のコピー / Vimでヤンクしたもの）を貼り付け。
"   p / P は Vim 標準のまま（" レジスタ）。PC の内容は \v で貼る。
nnoremap <silent> \v <Cmd>call gnosis#paste_clipboard('p', v:count)<CR>
nnoremap <silent> \V <Cmd>call gnosis#paste_clipboard('P', v:count)<CR>
" gp: 以前の独自貼り付け（改行末尾を落として行下に追加）
nnoremap <silent> gp <Cmd>call gnosis#paste_charwise()<CR>
" .: 標準の「直前の変更を繰り返す」動作を明示的に使用する
nnoremap <silent> . .
nnoremap <silent> \L        <Cmd>call gnosis#linkify_filename_under_cursor()<CR>
xnoremap <silent> \L        :<C-u>call gnosis#linkify_selection_new_note()<CR>
nnoremap <nowait> <silent> mx  <Cmd>ToggleCheckbox<CR>
xnoremap <nowait> <silent> mx  :<C-u>'<,'>ToggleCheckbox<CR>
nnoremap <silent> \p        <Cmd>call gnosis#paste_clipboard_link_here()<CR>
xnoremap <silent> \p        :<C-u>call gnosis#linkify_selection_from_clipboard()<CR>
" \P … カーソル下の .md リンク先 B の Context: に、今のノート A を確認なしで足す。
" ビジュアルでは、選んだ範囲の中の複数のリンク先それぞれに同じことをする。
nnoremap <nowait> <silent> \P <Cmd>call gnosis#add_current_as_parent_here()<CR>
xnoremap <nowait> <silent> \P :<C-u>call gnosis#add_current_as_parent_range(line("'<"), line("'>"))<CR>
" \o を2打で確定させるため、従来の \oe は \O へ移動。
nnoremap <silent> \O        <Cmd>OutlineEdit<CR>
" zo … カーソル下の .md リンク先ノートの見出し（アウトライン）を選び、
" リンク先に #スラッグ（GitHub 互換）を付ける。先頭の「（見出しなし）」で解除。
nnoremap <nowait> <silent> zo <Cmd>call gnosis#link_to_outline()<CR>
nnoremap <silent> \gi       <Cmd>call gnosis#open_gallery_smart()<CR>
" アプリ (Electron / ブラウザ) を開く。vault はアプリ側 (既定 ~/files/yurii-note)。
" 既定では使われていない \A。(\w は other.vim の :wa なので使わない)
nnoremap <silent> \A        <Cmd>call gnosis#open_web()<CR>

" ---------------------------------------------------------------------------
" Shift-Tab / BackTab の端末互換
" ---------------------------------------------------------------------------

function! s:setup_backtab() abort
  if has('gui_running')
    return
  endif
  " 多くの端末は Shift-Tab を ESC [ Z で送る
  silent! execute "set <S-Tab>=\<Esc>[Z"
endfunction

call s:setup_backtab()
" ---------------------------------------------------------------------------
" expand_s_and_open: \se で展開して T ファイルを警告なしで開く
" ---------------------------------------------------------------------------

function! s:expand_s_and_open() abort
  let l:file = expand('%:p')
  let l:root = fnamemodify(l:file, ':h')
  let l:py   = g:gnosis_expand_s_python
  let l:cmd  = printf('%s %s expand_s %s %s 1', gnosis#python_cmd(),
        \ shellescape(l:py),
        \ shellescape(l:file),
        \ shellescape(l:root))
  let l:result = gnosis#sh#system(l:cmd)
  if gnosis#sh#error()
    echohl ErrorMsg | echo 'expand_s failed: ' . l:result | echohl None
    return
  endif
  let l:t_path = substitute(l:result, '\n\+$', '', '')
  " BS で戻れるよう元ファイルを履歴に積む（go_back が期待する辞書形式）
  call add(g:gnosis_history, {'file': l:file, 'pos': getpos('.')})
  if len(g:gnosis_history) > g:gnosis_history_max
    call remove(g:gnosis_history, 0)
  endif
  " T ファイルを開く
  execute 'keepjumps edit ' . fnameescape(l:t_path)
endfunction




" ---------------------------------------------------------------------------
" Markdown table helpers (vimwiki-like)
"   Insert mode <Tab>/<S-Tab>/<CR> はテーブル内のみ挙動変更
"   コマンド一覧:
"     :TN [{cols} {rows}]  新規テーブル挿入
"     :TA                  整形（列幅を揃える）
"     :TRE                 行を別バッファで編集
"     :TCE                 テーブルを同じページで CSV 行に変換（逆は :CsvToTable）
"     :TDR / :TDC          行・列を削除
"     :TAR / :TAC          行・列を追加
" ---------------------------------------------------------------------------

augroup gnosis_table
  autocmd!
  autocmd FileType markdown,vimwiki call s:setup_table_keys()
  autocmd BufRead,BufNewFile *.md   call s:setup_table_keys()
augroup END

function! s:setup_table_keys() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return
  endif
  inoremap <buffer><silent> <Tab>   <Cmd>call gnosis#table_tab_action()<CR>
  inoremap <buffer><silent> <S-Tab> <Cmd>call gnosis#table_stab_action()<CR>
  inoremap <buffer><silent> <CR>    <Cmd>call gnosis#table_cr_action()<CR>
  " <leader>t + 1文字: テーブル操作
  "   ta  整形          te  行編集       tc  CSV編集
  "   tdr 行削除        tdc 列削除
  "   tar 行追加        tac 列追加
  nnoremap <buffer><silent> <leader>ta  <Cmd>TA<CR>
  nnoremap <buffer><silent> <leader>te  <Cmd>TRE<CR>
  nnoremap <buffer><silent> <leader>tc  <Cmd>TCSV<CR>
  nnoremap <buffer><silent> <leader>tdr <Cmd>TDR<CR>
  nnoremap <buffer><silent> <leader>tdc <Cmd>TDC<CR>
  nnoremap <buffer><silent> <leader>tar <Cmd>TAR<CR>
  nnoremap <buffer><silent> <leader>tac <Cmd>TAC<CR>
endfunction

" ---------------------------------------------------------------------------
" Markdown リンクの concealment
"   [テキスト](url)  →  テキスト  のみ表示
"   ノーマルモードではカーソル行でも中身を隠す（concealcursor=n）。
"   挿入・ビジュアルモードでもリンク先を隠す。明示的な LinkSource モードで編集する。
"   隠れた範囲の上にはカーソルを表示できないため、←/→ と h/l は隠れた範囲を
"   まとめて飛び越える（gnosis#move_visible）。
" ---------------------------------------------------------------------------

augroup gnosis_conceal
  autocmd!
  autocmd FileType markdown,vimwiki call s:setup_conceal()
  autocmd BufRead,BufNewFile *.md   call s:setup_conceal()
  " 配色を変えても（:colorscheme・テーマの切り替え）リンクの色と下線を保つ
  autocmd ColorScheme * call s:link_highlight()
augroup END

function! s:link_highlight() abort
  call gnosis#link_highlight()
endfunction

function! s:setup_conceal() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return
  endif

  let l:max_lines = get(g:, 'gnosis_markdown_conceal_max_lines', 20000)
  " 1 行の長さの上限は既定で無し（0）。日本語は strlen がバイト数で 3 倍に数えるため、
  " 長い段落が 1 つあるだけでファイル全体の conceal が切れていた。極端に長い行の
  " 負荷は Vim 標準の 'synmaxcol' が抑える。上限を使うなら正の数を設定する。
  let l:max_len = get(g:, 'gnosis_markdown_conceal_max_line_length', 0)
  let l:too_large_for_conceal = (l:max_lines > 0 && line('$') > l:max_lines)
        \ || (l:max_len > 0
        \     && max(map(getline(1, min([line('$'), 200])), 'strchars(v:val)')) > l:max_len)

  if get(g:, 'gnosis_markdown_conceal_links', 0) && !l:too_large_for_conceal
    setlocal conceallevel=2
    " A で行末に追記するときも表示名だけを見せる。
    " :GnosisLinkSource on / off で元の Markdown を編集するモードを切り替える。
    setlocal concealcursor=nvi
    augroup gnosis_conceal_eol
      autocmd! * <buffer>
      autocmd InsertEnter,CursorMovedI,TextChangedI <buffer> call gnosis#conceal_eol_fix()
      autocmd InsertLeave <buffer> if &l:conceallevel > 0 | setlocal concealcursor=nvi | endif
    augroup END
    nnoremap <buffer><silent> <Right> :<C-u>call gnosis#move_visible(1, v:count1)<CR>
    nnoremap <buffer><silent> <Left>  :<C-u>call gnosis#move_visible(0, v:count1)<CR>
    nnoremap <buffer><silent> l :<C-u>call gnosis#move_visible(1, v:count1)<CR>
    nnoremap <buffer><silent> h :<C-u>call gnosis#move_visible(0, v:count1)<CR>
    " conceal + linebreak の組み合わせで、隠した URL 部分を基準に不自然な折返しが
    " 発生しやすいため、markdown では行折返しを通常の wrap に戻す。
    setlocal nolinebreak
  else
    setlocal conceallevel=0
    setlocal concealcursor=
    silent! nunmap <buffer> <Left>
    silent! nunmap <buffer> <Right>
    silent! nunmap <buffer> h
    silent! nunmap <buffer> l
    setlocal linebreak
  endif

  if get(b:, 'gnosis_link_source_on', 0)
    setlocal conceallevel=0 concealcursor=
  endif

  " リンクの構文（[ と ](…) を隠し、表示名に色と下線）は autoload の gnosis#link_syntax。
  " 構文ファイルの後に読まれる after/syntax/markdown.vim からも呼ぶ（:syntax on の読み直しや
  " filetype だけを設定したバッファでも、Markdown の構文がリンクの構文を消さないように）。
  call gnosis#link_syntax()
endfunction

" ---------------------------------------------------------------------------
" Persistent undo: ファイルをまたいでも・再起動後も undo 履歴を保持
" ---------------------------------------------------------------------------

if !exists('g:gnosis_persistent_undo')
  let g:gnosis_persistent_undo = 1
endif

if g:gnosis_persistent_undo
  set undofile
  set undolevels=10000
  set undoreload=100000
endif

" ---------------------------------------------------------------------------
" AutoSave: 「保存が要る瞬間」に vault の .md / .csv を自動書き込み
"   g:gnosis_autosave        (既定 1。0 で無効)
"   g:gnosis_autosave_delay  (既定 1500ms。最後の変更からこの時間で保存)
"   - 対象は vault 配下の .md / .csv（同期が走るのは .md だけ）
"   - 無操作デバウンス（挿入・置換中も含む）+ Esc で即保存 +
"     バッファ/ウィンドウを離れるとき即保存
"   - 外部アプリで開く前（gm / \A）・ゴミ箱へ移す前（\tD）・同期の前も
"     呼び出し側が gnosis#save_current_note() で書き出す
"   - ターミナルを×で閉じる（SIGHUP）は Vim 側でフックできないため、
"     挿入中でも短めのデバウンスで書き、未保存の窓を小さくしている
" ---------------------------------------------------------------------------

if !exists('g:gnosis_autosave')
  let g:gnosis_autosave = 1
endif
if !exists('g:gnosis_autosave_delay')
  let g:gnosis_autosave_delay = 1500
endif

" 非同期同期プロセスが編集途中のノートをディスク上で上書きしないためのガード。
" `TextChanged` だけでなく `InsertEnter` でも立て、最初の入力と同期完了が
" 競合する時間を減らす。別の Vim との衝突を避け、ファイル名には PID を含める。
let $GNOSIS_SYNC_GUARD_DIR = gnosis#home#path('state', 'sync-dirty')
let s:gnosis_dirty_guard_paths = {}

function! s:dirty_guard_mark() abort
  let l:file = expand('%:p')
  if &buftype !=# '' || empty(l:file) || !gnosis#is_vault_path(l:file)
    return
  endif
  let l:dir = $GNOSIS_SYNC_GUARD_DIR
  if !isdirectory(l:dir)
    try
      call mkdir(l:dir, 'p')
    catch
      return
    endtry
  endif
  let l:marker = l:dir . '/' . strpart(sha256(fnamemodify(l:file, ':p')), 0, 16)
        \ . '.' . getpid() . '.dirty'
  if !filereadable(l:marker)
    call writefile([], l:marker, 'S')
  endif
  let b:gnosis_sync_dirty_guard = l:marker
  let s:gnosis_dirty_guard_paths[l:marker] = 1
endfunction

function! s:dirty_guard_clear(...) abort
  let l:marker = get(b:, 'gnosis_sync_dirty_guard', '')
  if !empty(l:marker)
    call delete(l:marker)
    unlet! b:gnosis_sync_dirty_guard
    if has_key(s:gnosis_dirty_guard_paths, l:marker)
      call remove(s:gnosis_dirty_guard_paths, l:marker)
    endif
  endif
endfunction

function! s:dirty_guard_after_save() abort
  " デバウンスによる挿入中の保存では、次のキー入力に備えてガードを残す。
  if mode(1) !~# '^[iR]'
    call s:dirty_guard_clear()
  endif
endfunction

function! s:dirty_guard_after_leave() abort
  if !&modified
    call s:dirty_guard_clear()
  endif
endfunction

function! s:dirty_guard_clear_all() abort
  for l:marker in keys(s:gnosis_dirty_guard_paths)
    call delete(l:marker)
  endfor
  let s:gnosis_dirty_guard_paths = {}
endfunction

function! s:schedule_autosave() abort
  if !g:gnosis_autosave || !has('timers') | return | endif
  if exists('s:autosave_timer') && s:autosave_timer > 0
    call timer_stop(s:autosave_timer)
  endif
  let s:autosave_timer = timer_start(g:gnosis_autosave_delay,
        \ {-> s:autosave_now()})
endfunction

function! s:autosave_now(...) abort
  let s:autosave_timer = 0
  if !g:gnosis_autosave
    return
  endif
  " 操作待ち（d の途中）・コマンドライン中・ビジュアル/セレクト選択中はもう一度
  " 待つ。選択中に書くと（保存に続く同期や再読込で）選択が解除されてしまう。
  " 挿入・置換中でも「書くだけ」は安全なので保存する（未保存の窓を小さくするため）。
  let l:mode = mode(1)
  if index(['o', 'c', 'v', 'V', "\<C-v>", 's', 'S', "\<C-s>"], l:mode) >= 0
    call s:schedule_autosave()
    return
  endif
  call s:autosave_write()
endfunction

" 対象（vault 配下の .md / .csv）で modified なら書き出す。
" 書いたら 1、対象外・変更なしなら 0。
function! s:autosave_write() abort
  if !&modified || &buftype !=# '' || &readonly
    return 0
  endif
  let l:file = expand('%:p')
  if !gnosis#is_autosave_target(l:file)
    return 0
  endif
  if exists('s:autosave_timer') && s:autosave_timer > 0
    call timer_stop(s:autosave_timer)
    let s:autosave_timer = 0
  endif
  return gnosis#conflict#safe_update()
endfunction

" Esc（挿入モードを抜けた時）は無操作デバウンスを待たず即保存する。
" 保存回数は増えず、保存のタイミングが前倒しになるだけ。
function! s:autosave_on_insert_leave() abort
  if !g:gnosis_autosave
    return
  endif
  " InsertLeave の最中は mode() がまだ 'i' のことがあるため、モード判定はしない
  call s:autosave_write()
endfunction

" バッファ/ウィンドウを離れるとき・フォーカスを失ったときは、デバウンスを
" 待たずに今すぐ保存する。リンク間の移動（:buffer 等で既に開いているノートへ
" 移る場合）は 'autowriteall' が効かないため、ここで書き残しを防ぐ。
function! s:autosave_before_leave() abort
  if !g:gnosis_autosave
    return
  endif
  call s:autosave_write()
endfunction

augroup gnosis_autosave
  autocmd!
  autocmd InsertEnter *.md call s:dirty_guard_mark()
  " Gnosis が書き換えてすぐ保存したあとにも TextChanged は遅れて届く。保存済みなら印を付けない
  " （残った印のせいで、同期や zk・b などが「未保存の編集がある」と断るのを防ぐ）
  autocmd TextChanged,TextChangedI *.md if &modified | call s:dirty_guard_mark() | endif
  autocmd TextChanged,TextChangedI *.md,*.csv call s:schedule_autosave()
  " nested が要る: autocmd の中で :write すると、nested が無いと BufWritePost が発火せず、
  " 保存の記録（gnosis#conflict#record）も保存後の同期（autosync）も走らない。
  " 記録が古いままだと、次の保存で「別のウィンドウが書き換えた」と誤検知する。
  autocmd InsertLeave *.md,*.csv nested call s:autosave_on_insert_leave() | call s:dirty_guard_after_leave()
  autocmd BufLeave,WinLeave *.md,*.csv nested call s:autosave_before_leave() | call s:dirty_guard_after_leave()
  autocmd FocusLost *.md,*.csv nested call s:autosave_before_leave()
  autocmd BufWritePost *.md call s:dirty_guard_after_save()
  autocmd BufUnload,BufDelete *.md call s:dirty_guard_clear()
  autocmd VimLeavePre * call s:dirty_guard_clear_all()
augroup END

" ---------------------------------------------------------------------------
" Swap なし + ロックファイル（2026-10-04）
"   vault のノートは swap を作らない（Obsidian 的に .swp の残骸と E325 を無くす。
"   クラッシュ時に失うのは最大で自動保存の間隔ぶんだけ）。
"   アプリとの衝突検知は state dir の PID 入りロックで行う。
" ---------------------------------------------------------------------------

autocmd BufReadPre,BufNewFile *.md if gnosis#is_vault_path(expand('<afile>:p')) | setlocal noswapfile | endif
" ハブも swap を作らない（vault 外なので上記が効かず、残骸 .swp から E325 と読専化が出る）。
autocmd BufReadPre,BufNewFile */.state/hubs/*.md setlocal noswapfile noundofile
execute 'autocmd BufReadPre,BufNewFile ' . escape(printf('%s/hubs/*.md', gnosis#state_dir()), '\\ ') . ' setlocal noswapfile noundofile'
" vault を切り替えても効くよう、場所は決め打ちしない（.state/hubs/review-*.md）
autocmd BufEnter */.state/hubs/review-*.md call gnosis#review_setup()

augroup gnosis_lock
  autocmd!
  autocmd BufReadPost,BufNewFile,BufEnter *.md call gnosis#lock_add(expand('<afile>:p'))
  autocmd BufUnload,BufDelete,VimLeavePre *.md call gnosis#lock_remove(expand('<afile>:p'))
augroup END

" vault の暗号（gocryptfs箱）
"   ・起動時にロック中ならパスワードを聞いてマウント
"   ・終了時に自動でロック（閉じるとロック）
"   ・:GnosisSetPassword = パスワード変更
" ---------------------------------------------------------------------------
augroup gnosis_vault
  autocmd!
  autocmd VimLeave  * call gnosis#quit_unmount()
  " viminfo は VimLeavePre の後に書かれる。ロック中なら書き先を無効化する
  autocmd VimLeavePre * call gnosis#before_write_viminfo()
  autocmd BufWritePre * call gnosis#guard_vault_write(expand('<afile>:p'))
  autocmd TextChangedI,TextChanged,InsertLeave *.md call gnosis#strip_stray_escape()
  autocmd TextChangedI,InsertLeave *.md call gnosis#fix_fullwidth_heading()
  autocmd BufWritePre *.md call gnosis#strip_stray_escape_all()
augroup END


" 旧 state_dir の状態を vault 内 .state/ へ1回だけ移行（root.txt は残す）
augroup gnosis_migrate_state
  autocmd!
augroup END

augroup gnosis_color_on_note
  autocmd!
  autocmd BufWinEnter *.md,*.markdown call gnosis#color#on_note_enter()
augroup END

" ---------------------------------------------------------------------------
" AutoSync: BufWritePost で update_one を起動
" ---------------------------------------------------------------------------

augroup gnosis_autosync
  autocmd!
  autocmd BufReadPost *.md call gnosis#remember_title()
  " record は on_write_post より先に置く（同期が付ける「自分の同期」の印を、record が消さないように）
  autocmd BufReadPost,BufWritePost,FileChangedShellPost *.md call gnosis#conflict#record(expand('<abuf>'))
  " グループに増えたメンバーに気づくのは、同期が書き直して読み直す（控えが取り直される）より前
  autocmd BufWritePost *.md call gnosis#group_review_check()
  autocmd BufWritePost *.md call s:on_write_post()
  " 見出しを書き換えたら、その見出しへのリンクも直す（保存の前の見出しを控えて比べる）
  autocmd BufWritePre *.md call gnosis#heading_links_before()
  autocmd BufWritePost *.md call gnosis#heading_links_after()
  autocmd BufReadPost *.md call gnosis#group_review_snapshot()
  if get(g:, 'gnosis_realtime_link_sync', 0)
    autocmd BufReadPost,BufEnter *.md call gnosis#realtime_sync_snapshot()
    autocmd TextChanged,TextChangedI *.md call gnosis#realtime_sync_on_text_changed()
  endif
  " 他のウィンドウ・プロセスが同じノートを書き換えたとき: 未保存の変更が無ければ読み直す。
  " 未保存の変更があれば読み直さず、退避して警告する（変更を失わない・相手の変更も上書きしない）
  autocmd FileChangedShell *.md call gnosis#conflict#on_changed_shell()
augroup END

function! s:on_write_post() abort
  try
    call gnosis#diary_on_save()
  catch
  endtry
  if !g:gnosis_autosync
    call gnosis#autosync_log('on_write_post: autosync is off')
    return
  endif
  try
    call gnosis#autosync_on_save()
  catch
    " silent! update の中で起きた例外は握りつぶされるので、ログに残してから再送出する
    call gnosis#autosync_log('  EXCEPTION: ' . v:exception . ' @ ' . v:throwpoint)
    call gnosis#autosync_problem('exception: ' . v:exception . ' @ ' . v:throwpoint)
    throw v:exception
  endtry
endfunction

function! s:normalize_cmdline(cmdline) abort
  let l:cmd = trim(a:cmdline)
  while 1
    let l:new = substitute(l:cmd,
          \ '^\c\%(silent!?\|verbose\|keepalt\|keeppatterns\|keepjumps\|lockmarks\|confirm\|noswapfile\)\s\+', '', '')
    if l:new ==# l:cmd
      break
    endif
    let l:cmd = trim(l:new)
  endwhile
  return l:cmd
endfunction

function! s:auto_save_before_command() abort
  if !get(g:, 'gnosis_auto_save_on_command', 1)
    return
  endif
  if getcmdtype() !=# ':'
    return
  endif
  if &buftype !=# '' || !&modifiable || !&modified || empty(expand('%:p'))
    return
  endif

  let l:cmd = s:normalize_cmdline(getcmdline())
  if empty(l:cmd)
    return
  endif

  " 保存せずに抜けたい系のコマンドは除外
  if l:cmd =~# '^\c\%(q\%[uit]\|qa\%[ll]\|cq\%[uit]\|cquit\|bd\%[elete]\|bw\%[ipeout]\|bunload\|bdel\|bwipe\)\>.*!\?$'
    return
  endif

  silent! update
endfunction

augroup gnosis_auto_save_on_command
  autocmd!
  autocmd CmdlineLeave : call s:auto_save_before_command()
augroup END

" GUI 版 Vim: Ctrl + / Ctrl - / Ctrl 0 で文字の大きさをその場だけ変える（設定の文字サイズは変えない）
if has('gui_running') || has('gui')
  nnoremap <silent> <C-=> <Cmd>call gnosis#settings#gui_zoom(1)<CR>
  nnoremap <silent> <C-+> <Cmd>call gnosis#settings#gui_zoom(1)<CR>
  nnoremap <silent> <C--> <Cmd>call gnosis#settings#gui_zoom(-1)<CR>
  nnoremap <silent> <C-0> <Cmd>call gnosis#settings#gui_zoom(0)<CR>
endif

" 起動: 起動画面（Chnoubis・vault の選択）を出すか、そのまま vault を開く。
" vault を開く処理（マウント・ロック掃除・状態の移行・Index・操作ガイド・描き直し）は
" gnosis#startup_sequence() が順に行う（起動画面のときは Enter を押したあと）。
augroup gnosis_startup
  autocmd!
  autocmd VimEnter * ++once call gnosis#start#on_vim_enter()
augroup END

augroup gnosis_startup_prefix_check
  autocmd!
augroup END

" ---------------------------------------------------------------------------
" Wayland クリップボード橋渡し（Vim → PC 方向）
" ---------------------------------------------------------------------------
" Vim（vim.gtk3）の +/* レジスタは XWayland 側のクリップボードを見るため、
" 大きなヤンクを XWayland のブリッジに通すと KWin / Klipper ごと固まることがある。
" そこで X11 側は使わず（other.vim で clipboard= に固定）、`yy` / `x` / `ciw` などの
" 無名レジスタと `"+y` / `"*y` を wl-copy（Wayland ネイティブ）へ流す。
" これで Vim でヤンクした内容を `\v` でも PC 側アプリでも貼れる。
if !has('nvim')
  function! s:wayland_clipboard_yank() abort
    let l:reg = get(v:event, 'regname', '')
    if l:reg !=# '' && l:reg !=# '+' && l:reg !=# '*'
      return
    endif
    let l:lines = get(v:event, 'regcontents', [])
    if empty(l:lines)
      return
    endif
    call gnosis#clipboard_copy(join(l:lines, "\n"))
  endfunction

  augroup gnosis_wayland_clipboard
    autocmd!
    autocmd TextYankPost * call s:wayland_clipboard_yank()
  augroup END
endif

" ---------------------------------------------------------------------------
" CopyStack コマンド
" ---------------------------------------------------------------------------
nnoremap <silent> \sc <Cmd>CopyStack<CR>
command! CopyStack call gnosis#stack_copy_toggle()

" 終了時に recent.json / viminfo を消す（vault 内に寄せたものを残留させない）
augroup gnosis_exit_cleanup
  autocmd!
  autocmd VimLeave * call gnosis#exit_cleanup()
  " ふだんの端末の窓で文字サイズをその場で変えていたら元に戻す（kitty・Alacritty）
  autocmd VimLeave * call gnosis#termfont#restore_on_exit()
augroup END

" ---------------------------------------------------------------------------
