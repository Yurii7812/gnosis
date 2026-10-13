This note is the Gnosis guide. **Every key is collected here.**
When you change the language in the settings (`:GnosisSettings`), this guide is rebuilt in that language. **Vim basics are at the end.**

## Start, vaults and settings

- Start screen … the Chnoubis symbol, the selected vault, and `Enter` to start. `v` chooses / manages vaults, `s` opens the settings, `q` quits
- Vault list … `j` / `k` select ・ `Enter` opens ・ `a` registers an existing folder ・ `n` creates a new vault ・ `d` removes it from the list (notes and folders are kept) ・ `Esc` goes back
- `:GnosisStart` start screen ・ `:GnosisVaults` vault list (switch while working) ・ `:GnosisSettings` settings
- Settings are per vault (`.gnosis/settings.json`): language, maximize on start, normal window size, font size, light / dark, theme, custom colors
- `:GnosisThemeAdd` `Plug 'author/repo'` … adds a Vim theme from GitHub and uses it for this vault ・ `:GnosisThemeReset` back to the standard theme
- `:GnosisFontSize` font size (`20` / `+1` / `-1` / `reset`; saved, and applied at once where the terminal allows) ・ `:GnosisLinkSource` show / hide the Markdown source of links
- In the app, `Ctrl` + `+` / `-` / `0` zooms the whole window in / out / back (only for now; the font size setting is not changed)
- In GUI Vim, `<C-=>` / `<C-+>` / `<C-->` / `<C-0>` change the font size only for now (`<C-0>` goes back to the setting). In terminal Vim the terminal decides the font (the Gnosis launcher passes the size only to supported terminals)

## Creating notes

- `zn` … create a note. Choose one position key:
  `h`=below the cursor (body) / `Enter`=end of the body / `t`=under a heading / `c`=end of Context / `o`=no link (orphan)
  With `h`/`Enter`, the new note gets the current note in its Context (in Group if the current note is a group).
- After `c` … choose how the new note (the link target) gets a link back to the current note: `Enter`=end of its body / `t`=choose a heading, end of that section / `o`=do not add (the link in the current note's Context is still added)
- `zk` … create a group note (`attribute: group`). Same position keys as `zn`. Also `g`=move the one link under the cursor into a new group (the old place becomes a link to the group; also works after selecting a link with the mouse)
- `zk` (visual) … create a group whose content is the selection, and replace the selection with a link to the group
- `zh` … link right below the cursor (as body → BackLink on the other side)
- When the target is a group (after `c`, `Enter` / `t`) … enter the **display name** of the link (starts empty; empty `Enter` = the current note's title, `Esc` = cancel)

## Links

- `\L` (normal) … turn the file name under the cursor into a Markdown link
- `\L` (visual) … replace the selection with a link to a new note named by the selection (the new note's title stays the timestamp; no Context = the original note shows up in BackLink; use `\P` to add it)
- `\p` (normal) … add one link from under the cursor or the clipboard (choose the position with `h`/`Enter`)
- `\p` (visual) … turn the selection into a link to the clipboard file name / URL (nothing if there is none)
- `za` … add the copied / yanked links to the current note (all lines, all links) (`h`=below the cursor / `Enter`=end of the body / `t`=under a heading / `c`=end of Context / `r`=Related). After `c`, choose how the target gets the current note (`Enter` / `t` / `o`)
- `zA` … like `za`, but asks for the **display name** first (empty Enter / Esc cancels)
- `zp` … same as `za`, and also writes the current note into the other note's Context
- `zap` … add the link under the cursor (or in the clipboard) to the end of the current note's Context (even if the body already has it)
- Related: pressing `r` in `za` etc. adds to `### Related` **on both notes** (deleting it on one side removes it from both at the next sync; not shown in BackLink)
- `\P` … add the current note to the Context of the linked note under the cursor, without asking
- Add from the clipboard with a relation: `ca` / `cu` / `\ca` / `tt` / `ta` / `\at` / `\bc` (`\ca`= reverse of `ca`, `\at`= reverse of `at`)
- `\l` (normal) … full-text search of all notes (titles first) → after choosing, pick where to put the link (`h`=new line below the cursor / `Enter`=end of the body / `t`=under a heading / `c`=end of Context / `r`=Related / `i`=right at the cursor / `n`=type a display name, end of the body) (`:GnosisLinkPick`)
- `\l` → `n` … the display name field starts empty. Empty `Enter` = the target note's title, typed text + `Enter` = that text, `Esc` = cancel (the note's title and file name are not changed)
- `\l` (visual) … replace the selection with a link to the note chosen by the same search
- Auto-generated BackLink entries are different from the links you add here. Added links (also with display names) stay after saving and syncing

## Titles and display names

- `zt` / `zT` … change the title (from empty / editing the current one)
- `zl` / `zL` … change a link's display name (from empty / editing the current one)
- `zo` … choose a heading (outline) of the .md link under the cursor and add `#slug` to the link (the first item "(no heading)" removes it; the title and Context/Group/Related/BackLink are not listed)
- `zy` / `zY` … change the **reading (yomi)** of the **current note** (`zy`=from empty / `zY`=keep the current one; with `zY`, delete everything and press Enter to remove it; Esc cancels). If `yomi:` has several display names, choose one by number
- `zd` … update the display names of child links to the targets' titles
- `mp` … change the YAML `filetype` ・ `yn` … yank the current file name

## Moving and reading

- `<Tab>` / `<S-Tab>` … next / previous link ・ `<CR>` … open the link under the cursor
- `<BS>` … back ・ `<S-BS>` / `\.` … forward ・ `_` … toggle with the previous note
- `1`〜`9` / `0` … open links by their running number (body → Context/Group/BackLink)
- `\k` / `\j` / `\J` … to Context / to the first BackLink / to the last BackLink
- `\bu` … last link near Context ・ `<S-Space>` … pick from the link list and move
- `\h` / `\0` … hub screen (an editable list of links) ・ `\H` … add the current note to the hub
- `\1`〜`\9` … jump to the Nth hub entry (inside the hub, normal link numbers)
- `\i` … open `index.md` ・ `\A` … the note app (Electron / browser)
- `Alt+V` in the app (`\A`) … view-only mode ⇔ normal Vim. View-only (VIEW at the bottom) shows no cursor and does not send editing keys. Scroll with `j`/`k`, arrows, PageUp/Down, `gg`/`G`, `Ctrl-d`/`Ctrl-u`. Search with `/` `?` `n` `N` `*` `#`. Also usable: `gs`, `gm`, Space, Tab, `<CR>`, `<BS>`, `_`, digits, `\h` `\H` `\0` `\i` `\d` `\.` `\L` `\gi` `\r` `\bu` `\k` `\j` `\J` `\sc`
- `Alt` + click on a link in the app … moves only the cursor onto the link without opening it (for `zk` → `g` and so on)
- The app also draws tables (`| a | b |`) and `<img src="…" width="50%">`. Inside a table or in insert mode the cursor line stays plain text
- `\d` … open today's diary (created if missing; `:GnosisToday`). Notes you create are added to the diary's "today's notes" automatically (`:GnosisDiaryUpdate` updates all diaries; `:GnosisDiaryAdopt` registers the current note as the diary of its date)
- `\I` … change the size of image markup (visual: the selection)

## Expanding, images and more

- `\e` … expand the notes around the current one into one md (`expand_v2.py`; choose **simple/detailed**; detailed takes 5 values and can save / load / delete named presets; output `.trash/T_*.md`)
- `\se` … expand an S note into an A note (`expand_s.py`; output `.trash/T_*.md`)
- `\gi` … image gallery (the note's images, or all images under the Index, in the browser)
- `\oe` … edit headings in a separate buffer (`:write` applies them to the note)
- `\sc` … CopyStack (stack lines / selections with `y`, run `:CopyStack` again to put them in the clipboard)
- `mx` … toggle the checkbox `[ ]` / `[x]` of the line (visual: the selection)

## Search (fzf)

- `gs` … full-text search of the vault (titles first; titles on the left, hits highlighted on the right) → `⏎` opens the hit line (`:GnosisSearch`)
- `<Space>` … search the notes linked from the current note (titles first; their bodies too) → `⏎` opens
- `\l` … choose a note with the same search and put a link with a position key (`:GnosisLinkPick`)
- `rg` … ripgrep line search (`:Rg`)

## Pasting (clipboard)

- `\v` / `\V` … paste the system clipboard (the latest copy on the PC / Vim's yank) like `p` / `P`
- `p` / `P` … standard Vim (`"` register) ・ `gp` … add below the line without the trailing newline
- What you yank in Vim (`yy` / `x` / `ciw`) also goes to the PC clipboard

## Tables

- `\tn` new / `\ta` align / `\te` edit a row in a separate buffer / `\tc` to CSV / `\tt` from CSV / `\tnc` new separate CSV
- `\tar` / `\tac` … add a row / column ・ `\tdr` / `\tdc` … delete a row / column
- In a table: `<Tab>` / `<S-Tab>` move between cells ・ `<CR>` confirm ・ `<Left>` / `<Right>` scroll ・ `\ta` `\te` `\tc` `\tar` `\tac` `\tdr` `\tdc` also work there

## Other environment keys

- `\w` … save all buffers (`:wa`) ・ `\r` … clear screen leftovers (`:redraw!`) ・ `gm` … open the current note in the default app
- Edits are saved automatically after about 1.5 seconds of inactivity (also while inserting, and right away on Esc; .md / .csv in the vault; also when leaving a buffer; disable with `g:gnosis_autosave=0`). `gm` / `\A` / `\tD` / syncing always save first. No swap files
- `<C-v>` … paste the system clipboard ・ `<C-c>` (visual) … copy to the system clipboard
- `j` / `k` / `<Up>` / `<Down>` … move by screen lines (also in insert mode, without leaving it, so the input method stays on)

## Vault encryption (gocryptfs)

- An encrypted vault is `A/note` (plain view) + `A/.crypt` (encrypted data) side by side. Gnosis asks for the password on start, mounts it, and locks it on exit
- `:GnosisMount` … mount by hand ・ `:GnosisLock` … lock by hand (unmount)
- `:GnosisBackup` `[destination]` … pack the project folder (`.crypt` and others; not the contents of `note/`) into a 7z with the vault password
- `:GnosisSetPassword` … encrypt an unencrypted vault, or change the password
- `:GnosisRemovePassword` … remove the encryption and go back to plain files
- `:GnosisExitCleanup` … cleanup on exit (writing viminfo etc.)
- `:GnosisChooseIndex` / `:GnosisChooseIndexDir` … choose the vault folder again by typing it (if `A/note` exists, it is always the root)
- Note: gocryptfs **refuses non-empty mount points**. Contents and file names are encrypted, but times, sizes and structure are visible

## Label notation (relation suffixes)

- `語:` … mirrored as `(語):` on the other side
- `語:;` … the other side also gets `語:;` (no parentheses)
- `語;` … nothing is written on the other side
- `語::` … `語:` in the same section on both sides
- Links to groups (`attribute: group`) go to `### Group`, links to normal notes to `### Context`, sorted by sync. Empty sections (Context / Group / Related / BackLink) have no heading

## Sync

- Synced automatically on save (`:UpdateMD` / `:UpdateAll` / `\ua` make everything consistent; `:UpdateAll` / `\ua` also sort index.md by reading)
- Labels are mirrored on the other side automatically. Remove the parentheses and edit by hand to make them sticky
- Links to deleted files are cleaned up automatically (whole lines; links inside sentences keep their text)

## Hub

- `\1`〜`\9` … jump to the hub ・ `\H` … register the current note ・ `\0` / `\h` … list
- The hub is saved per Index (vault). Another vault has its own hub

## Trash

- `\tD` … move the current note to the trash (`.trash/`) (soft delete; same as `:GnosisTrash`)
- `\tr` … browse the trash with fzf (with preview). `⏎`=just open / `^r`=restore to the vault root and open / `^e`=empty the trash (`:GnosisTrashList`)
- `\tE` … empty the whole trash (permanent, asks first; same as `:GnosisTrashEmpty`)
- `.trash/` starts with a dot, so it never appears in search, lists, sync or links

## Sorting by reading

- `\S` (normal) … sort the **link-only lines** by the reading of their display names (Japanese kana order → romaji last) (missing readings are added to `yomi:`)
- `\S` (normal, group) … in a group, only the last blank-line-separated block of the body is sorted (text and links above it stay)
- `\S` (visual) … sort the link-only lines in the selection the same way (nothing outside the selection changes)
- `:SortYomi` / `:GnosisSortYomi` … same as `\S` (normal)
- Text lines (not links), code blocks, and links in or after `### Context` / `### Related` / `### BackLink` never move. With 0–1 links nothing changes
- The reading comes from the target note's front matter `yomi:` (display name → reading) first; missing ones are added to `yomi:` by pykakasi
- `zy` / `zY` fix / delete the reading per display name by hand

## Paper PKM (Folgezettel)

- `\f` … open the paper PKM Index (`Paper-Zettelkasten-Index.md`), creating it if missing (`:GnosisPaperIndex`). Index-write and Folgezettel-Index are created too. Update with `\ua`
- `\F` … number scanned images and move them to the vault root (`:GnosisScan`; opens the numbering GUI). In the GUI, `d` = **register as a paper diary**
- `Index-write` … write `keyword(reading): 1,1a10b,3` by hand. Keywords with several IDs become group notes, single IDs become direct links in the paper PKM Index (regenerated on save)
- `\S` … in Index-write, keyword lines are sorted by reading too
- Folgezettel-Index lists all existing IDs (natural order). It is generated, so no `\S`

## Ex commands

The canonical name of every command starts with `:Gnosis` (press Tab after `:Gnosis` for candidates). Old commands starting with `:Yurii` are aliases of the `:Gnosis` command with the same name (compatibility). Short old names (`:NF` etc.) are kept for compatibility too.

### Start, vaults and settings
- `:GnosisStart` `:GnosisVaults` `:GnosisSettings` `:GnosisThemeAdd` `:GnosisThemeReset` `:GnosisIndex` `:GnosisChooseIndex` `:GnosisChooseIndexDir` `:GnosisGuide` `:GnosisWeb`

### Creating and migrating notes
- `:GnosisNF` / `:NF` quick new note with a title ・ `:GnosisNA` / `:NA` "A" type below the cursor ・ `:GnosisNH` / `:NH` new note here
- `:GnosisNP` / `:NP` new as parent ・ `:GnosisNC` / `:NC` new as child ・ `:GnosisV2Migrate` / `:V2Migrate` migrate from the old format

### Links and relations
- `:GnosisLinkify` / `:Linkify` link the text under the cursor ・ `:GnosisLinkifySelection` / `:LinkifySelection` selection to a new note ・ `:GnosisPasteLink` / `:PasteLink` add links from the clipboard
- `:GnosisAT` `:GnosisBC` `:GnosisCA` `:GnosisCU` `:GnosisTT` / `:AT` `:BC` `:CA` `:CU` `:TT` … add from the clipboard with a relation ・ `:GnosisYN` / `:YN` yank the file name
- `:GnosisLT` / `:LT` / `:GnosisRenameLinkText` / `:RenameLinkText` change a display name ・ `:GnosisNT` / `:NT` change the title ・ `:GnosisRenameChildLinkTitles` / `:RenameChildLinkTitles` / `:GnosisRenameDownLinkTitles` / `:RenameDownLinkTitles` update child link names
- `:GnosisLinkPick` / `:LinkPick` search and insert a link ・ `:GnosisSearch` / `:GnosisFSearch` / `:FSearch` full-text search ・ `:GnosisFileContentSearch` / `:FileContentSearch` full-text search

### Moving
- `:GnosisJumpParent` / `:JumpParent` / `:GnosisJumpUp` / `:JumpUp` to the parent ・ `:GnosisJumpChildTop` / `:JumpChildTop` / `:GnosisJumpDownTop` / `:JumpDownTop` first child ・ `:GnosisJumpChildBottom` / `:JumpChildBottom` / `:GnosisJumpDownBottom` / `:JumpDownBottom` last child
- `:GnosisJumpLastLinkBeforeParent` / `:JumpLastLinkBeforeParent` / `:GnosisJumpLastLinkBeforeUp` / `:JumpLastLinkBeforeUp` last link near Context

### Expanding and outline
- `:GnosisSE` / `:SE` / `:GnosisExpandToT` / `:ExpandToT` / `:GnosisExpandLinks` / `:ExpandLinks` expand an S note ・ `:GnosisOutlineEdit` / `:OutlineEdit` edit headings (apply with `:OutlineApply`)

### Diary, encryption, trash, paper PKM, images
- `:GnosisToday` `:GnosisDiaryAdopt` `:GnosisDiaryUpdate` / `:SimpleDiaryUpdate` diary
- `:GnosisMount` `:GnosisLock` `:GnosisSetPassword` `:GnosisRemovePassword` `:GnosisBackup` `:GnosisExitCleanup` encryption
- `:GnosisTrash` `:GnosisTrashList` `:GnosisTrashEmpty` trash ・ `:GnosisPaperIndex` paper PKM Index ・ `:GnosisScan` import scans
- `:GnosisSetImageSize` / `:SetImageSize` image size ・ `:GnosisGallery` / `:Gallery` ・ `:GnosisGalleryFolder` / `:GalleryFolder` image gallery

### Tables
- `:GnosisTableNew` / `:TN` / `:NewTable` new ・ `:GnosisTableAlign` / `:TA` align ・ `:GnosisTableRowEdit` / `:TRE` edit a row ・ `:GnosisTableCsvEdit` / `:TCSV` / `:TableCsvEdit` edit as CSV ・ `:GnosisTableCsvApplySaved` / `:TableCsvApplySaved` apply the CSV
- `:GnosisTableToCsv` / `:TCE` / `:TableToCsv` to CSV ・ `:GnosisCsvToTable` / `:CsvToTable` from CSV ・ `:GnosisTableCsvNew` / `:TCN` / `:TableCsvNew` separate CSV ・ `:GnosisTableAddRow` / `:TAR` `:GnosisTableAddCol` / `:TAC` add row/column ・ `:GnosisTableDelRow` / `:TDR` `:GnosisTableDelCol` / `:TDC` delete row/column

### Sync and more
- `:GnosisUpdateMD` / `:UpdateMD` / `:GnosisUpdateAll` / `:UpdateAll` / `:UpdateALL` sync ・ `:GnosisSortYomi` / `:SortYomi` by reading ・ `:GnosisSortTime` / `:SortTime` by time ・ `:GnosisToggleCheckbox` / `:ToggleCheckbox` toggle checkbox ・ `:GnosisCopyStack` / `:CopyStack`
- `:GnosisCheckPrefix` / `:CheckPrefix` check prefixes ・ `:GnosisRename` / `:Rename` rename the file ・ `:GnosisAutocwindow` / `:Autocwindow` toggle quickfix auto jump ・ `:GnosisRP` / `:RP` rename the prefix
- `:GnosisFcitxOn` `:GnosisFcitxOff` `:GnosisFcitxStatus` switch the Japanese input method (fcitx, Linux)
- `:Gnosis` … entry point (press Tab after `:Gnosis` for candidates)

## Vim basics (details)

### Modes
- Normal (on start; `Esc` returns here) … the base for moving, deleting, copying and pasting
- Insert … `i` before / `a` after / `I` line start / `A` line end / `o` new line below / `O` new line above
- Visual … `v` characters / `V` lines / `<C-v>` block. Select, then `y` copy `d` delete `c` change `>` `<` indent `~` case
- Command line … `:` (Ex commands) / `/` `?` (search)
- When lost, press `Esc` to go back to normal mode

### Moving the cursor
- `h` `j` `k` `l` … left down up right (here `j`/`k` = screen lines, like `gj`/`gk`)
- `w` next word / `b` previous word / `e` word end / `ge` previous word end
- `0` line start / `^` first non-blank / `$` line end
- `f<char>` next char / `t<char>` before it / `F` `T` backwards / `;` repeat / `,` repeat backwards
- `gg` top / `G` bottom / `{n}G` line n / `H` `M` `L` top, middle, bottom of the screen
- `<C-d>` half page down / `<C-u>` half page up / `<C-f>` page down / `<C-b>` page up
- `zz` center / `zb` bottom (scroll the screen)
- `{` `}` paragraphs / `(` `)` sentences / `%` matching bracket
- `<C-o>` previous jump / `<C-i>` next jump

### Editing
- Delete: `x` a char / `dd` a line / `dw` a word / `d$` to the line end / `d` + motion
- Change: `cc` a line / `cw` a word / `ciw` inside a word / `ci(` inside parentheses
- Copy: `yy` a line / `yw` a word / `y$` to the line end
- Paste: `p` after the cursor / `P` before (standard Vim; PC clipboard with `\v`)
- `r` replace a char / `R` overwrite / `J` join lines / `~` toggle case
- `u` undo / `<C-r>` redo / `.` repeat the last change
- Counts: put a number before a command, like `3j` `2dd` `5x`
- Indent: `>>` `<<` / in visual `>` `<` / `=` auto format

### Text objects (edit a range)
- `iw` word / `aw` word and space / `i"` `a"` inside quotes / `i(` `a(` inside parentheses / `it` inside a tag / `ip` paragraph
- Examples: `ciw` rewrites a word / `di"` deletes inside quotes / `ya(` copies with the parentheses

### Search
- `/word` search down / `?word` up / `n` next / `N` previous
- `*` search the word under the cursor / `#` backwards / `:noh` clear highlight

### Command line
- `:w` save / `:q` quit / `:wq` save and quit / `:q!` quit discarding / `:e file` open
- `:bnext` `:bprev` switch buffers / `:help word` help / `:marks` list marks
- Here, saving syncs automatically (`:UpdateMD` / `:UpdateAll` make everything consistent)

### Registers / clipboard
- Unnamed `"` / numbered `0`〜`9` / named `a`〜`z` / system `+` `*`
- `"ayy` copies to a / `"ap` pastes a
- Paste the PC clipboard with `\v`. What you copy with `yy` `dd` `ciw` etc. also goes to the PC

### Marks / macros
- `ma` sets mark a / backquote + `a` jumps there / `:marks` lists them
- `qa` start recording / `q` stop / `@a` play / `@@` play again

### Differences from standard Vim here
- `j`/`k` move by screen lines (wrapped lines one by one). For real lines use `+` / `-` or `{n}G`
- `1`〜`9` `0` jump to links by number (if there is no such link, the digit works as a count)
- `p` / `P` are standard Vim. Paste the PC clipboard with `\v` / `\V`
- `_` toggles with the previous note. `,` (f/t repeat) is standard
- `zt` changes the title (not Vim's "scroll to top"). `zA` adds links with a display name
- Two-key plugin commands use the `z` / `g` / `\` prefixes (so plain keys never wait)
