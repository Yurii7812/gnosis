This note is the Gnosis guide. **Every key is collected here.**
When you change the language in the settings (`:GnosisSettings`), this guide is rebuilt in that language. **Vim basics are at the end.**

## Everyday flow

- Write … in the current note, `zn` → `Enter` (link at the end of the body) or `h` (below the cursor). A Branch is added automatically: the original note is the parent and the new note the child (`ParentBranch:` / `ChildBranch:`)
- Keep what led to it … `c` after `zn` / `\l` / `za`. The current note (A) goes into the other note's (B) `Context:`. Then choose where in A to put B (`Enter` / `t` / `h` / `w`)
- Collect … on a group such as the Index, `zn` → `Enter`. Add the new note to the group with a display name; the index is re-sorted by the same rule as `\S`
- Branch off … on the starting note, `zk` → `n`. Makes a group that branches from that note (BranchGroup; e.g. a topic index. Not made on a group)
- Connect … find and place with `\l`. To join a group, choose the group with `\l` and press `g`. To add only context, `\P`
- End of the day … the notes you made that day appear under "today's notes" of the `\d` diary. Paper diaries imported with `\F` are linked from that day's diary

## Start, vaults and settings

- Start screen … the Chnoubis symbol, the selected vault, and `Enter` to start. `v` chooses / manages vaults, `s` opens the settings, `q` quits
- Vault list … `j` / `k` select ・ `Enter` opens ・ `a` registers an existing folder ・ `n` creates a new vault ・ `d` removes it from the list (notes and folders are kept) ・ `Esc` goes back
- `:GnosisStart` start screen ・ `:GnosisVaults` vault list (switch while working) ・ `:GnosisSettings` settings
- Settings are per vault (`.gnosis/settings.json`): language, maximize on start, normal window size, light / dark, theme, custom colors. Font size, font, line spacing and terminal are Gnosis-wide (`terminal.json` in the Gnosis home)
- `:GnosisThemeAdd` `Plug 'author/repo'` … adds a Vim theme from GitHub and uses it for this vault ・ `:GnosisThemeReset` back to the standard theme
- The color editor ("Make / edit colors" in settings) lets you set the **text and background colors of the number before each link (1-9, 0, g1 …)** as well as background, text, links, headings, selection and cursor line. The preview (with numbered examples) updates immediately. If you set nothing, the old look stays (text = background color, badge = muted color)
- `:GnosisFontSize` font size (`20` / `+1` / `-1` / `reset`; saved, and applied at once where the terminal allows) ・ `:GnosisLinkSource` show / hide the Markdown source of links
- In the app, `Ctrl` + `+` / `-` / `0` zooms the whole window in / out / back (only for now; the font size setting is not changed)
- In GUI Vim, `<C-=>` / `<C-+>` / `<C-->` / `<C-0>` change the font size for now only. The terminal's own `Ctrl` + `+` / `-` / `0` are handled by the terminal and not saved. The saved size is changed with `+` / `-` / `0` on the font size row of the settings screen (immediately in Gnosis windows of Konsole, kitty, Alacritty; elsewhere the next time a Gnosis window opens)

## Creating notes

- `zn` … create a note. Choose one position key (other keys do nothing):
  `Enter`=end of the body / `t`=under a heading / `h`=below the cursor / `c`=Context (the current note into the new note's `Context:`) / `b`=ChildBranch (direct child) / `p`=ParentBranch (direct parent) / `o`=no link (orphan) / `r`=Related (both directions)
  `Enter` / `t` / `h` / `c` also add a Branch, separately from where the link goes: the original note is the parent and the new note the child (the original note's `ChildBranch:`, the new note's `ParentBranch:`). Only `c` adds Context. `b` records only the Branch, `p` reverses its direction, `o` is an orphan. `r` adds only Related, with no automatic Branch, Context or body link. Automatic Branch and duplicate handling for notes made from the diary are unchanged
- After `c` (same in `zn` / `\l` / `za`) … the current note (A) goes into the other note's (B) `Context:`. Then choose where in A to put the link to B: `Enter`=end of the body / `t`=choose a heading, end of that section / `h`=below the cursor / `w`=do not place it; yank B the same way as `yn` (A stays open; paste it yourself). `Esc` cancels and nothing changes (all questions come before any change)
- `b` (ChildBranch = direct child) / `p` (ParentBranch = direct parent) (position keys of `zn` / `za` / `\l`) … with `b` the current note is the parent and the chosen (new) note the child; with `p` the chosen (new) note is the parent and the current note the child. Both use the same code and write the link into **the parent's `ChildBranch:` and the child's `ParentBranch:`**. With `p` only one note can be chosen as the parent. A note can have at most one parent (ParentBranch); children are unlimited. A note that already has a parent, a self reference, or a pair that would form a cycle is rejected and neither note is changed (the existing parent is never replaced; the current parent's title is shown). It is a separate relation from Context / Related. Check consistency with `:GnosisBranchCheck`
- `zn` on a group … `Enter`=type a display name, then create the note and add it to this group (a link with the display name in the group's body, the group in the new note's `Group:`; the new note opens and the index is re-sorted by the same rule as `\S`) / `o`=orphan (not linked anywhere; sort it out later with `\N`). Other keys do nothing. No Context and no Branch (same for `index.md`)
- `zk` … on an ordinary note, only `n`: make a group (G) that branches from the current note (A). G goes into A's `BranchGroup:` and `ChildBranch:`, A into G's `ParentBranch:`. No Context. A group in `BranchGroup:` is not shown again in A's `Group:` (the link to A in G's body stays). `zk` cannot be used on a group (visual too)
- Relation headings use the same "Name:" form as `Group:` / `Context:` (`ParentBranch:` / `ChildBranch:` / `Related:` / `BackLink:`; empty ones are not written). The old `### Name` headings are still read and are rewritten to "Name:" at the next sync (`:UpdateAll`; no link is lost). Only the old `### Context` is moved with `:GnosisContextMigrate! all`
- Inside `BranchGroup:` the entries are simply listed from top to bottom (no link or relation is added). Nothing is indented automatically. To indent by hand, `:GnosisBranchNest` (one level down) / `:GnosisBranchUnnest` (one level up) … on the selected lines (`:'<,'>`) or, with no range, the current line, if it is a link line in `BranchGroup:`. Topics of the paper PKM (`\F`) go into the `BranchGroup:` of that number's scan note (after the parent topic and its children, if there is a parent)
- Deleting a group link from a note's `Group:` removes that note's link from the group's body at the next sync, so it leaves the group (it does not come back; deleting it from the group's body still removes it from `Group:` as before)
- `zk` (visual) … on an ordinary note, create a group whose content is the selection, and replace the selection with a link to the group (not on a group)
- `zh` … link right below the cursor (as body → BackLink on the other side)
- Groups (BranchGroup style) … the entry point (Index) is never replaced. For a topic index, use `zk` → `n` on the starting note. Add a note to a group with `zn` → `Enter` on the group, or `\l` → `g`

## Links

- `\L` (normal) … turn the file name under the cursor into a Markdown link
- `\L` (visual) … replace the selection with a link to a new note named by the selection (the new note's title stays the timestamp; no Context = the original note shows up in BackLink; use `\P` to add it)
- `\p` (normal) … add one link from under the cursor or the clipboard (choose the position with `h`/`Enter`)
- `\p` (visual) … turn the selection into a link to the clipboard file name / URL (nothing if there is none)
- `za` … add the copied / yanked links to the current note (all lines, all links). Same position keys as `\l` (`Enter` / `t` / `h` / `c` / `b` / `p` / `r`, and `g` if the target is a group). `Enter` only puts the link at the end of the body; it never adds the note to a group, even if the target is a group
- `zA` … like `za`, but asks for the **display name** first (empty Enter / Esc cancels)
- `Related:` … a paired relation on both notes (deleting it on one side removes it from both at the next sync; not shown in BackLink). Choose `r` at the first selection in normal-note `zn` / `\l` / `za`. It preserves existing relations and body text, avoids duplicates, and repairs a missing reverse link. It is separate from the placement selection after `c`
- `\P` … put the current note (A) into the `Context:` of the linked note under the cursor (B), without asking. In visual mode, every linked note in the selection. Nothing changes for A itself, missing notes, or a B with unsaved changes
- Retired keys: `ca` / `cu` / `\ca` / `tt` / `ta` / `\at` / `\bc` / `zp` / `zap` (the functions and commands such as `:CA` remain; use the `c` flow and `\P` instead)
- `\l` (normal) … full-text search of all notes (titles first) → after choosing, pick where to put the link: `Enter`=end of the body / `t`=under a heading / `h`=below the cursor / `c`=Context (the current note into the target's `Context:`) / `b`=ChildBranch / `p`=ParentBranch / `r`=Related (mutual) / `g`=add the current note to the chosen group (only when the chosen note is a group). Other keys do nothing (`:GnosisLinkPick`)
- `\l` → `g` … **add the current note to the chosen note, which must be a group** (`attribute: group`). Search with `\l`, choose the group, press `g`: a link to the current note goes into the group's body and the group shows in the current note's `Group:`. You are asked for the display name (starting empty: empty `Enter` = the current note's title, typed text + `Enter` = that text, `Esc` = cancel). If the chosen note is not a group nothing happens. No link is put in the current note's body. The same with `za` (the copied link). It also works when the current note is a group (puts a group into another group)
- `\l` (visual) … replace the selection with a link to the note chosen by the same search (the display name is the selected text; no position is asked)
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
- `1`〜`9` / `0` … open links by their running number (top to bottom of the document, including the Context at the top)
- `\k` / `\m` / `\j` / `\J` … to the topmost "Name:" line (Group:, Context:, etc.) / to the bottommost "Name:" line / to the first BackLink / to the last BackLink
- `\bu` … last link near Context ・ `<S-Space>` … pick from the link list and move
- `\h` / `\0` … hub screen (an editable list of links) ・ `\H` … add the current note to the hub ・ Whenever a member is added to a group (or the Index), in any way, a **name and reading check screen** opens (`[name](…) — reading`; guesses are marked (guess). Edit names and readings; delete a line to remove it from the group. `Enter` views the note. `q` saves and sorts, `Q` sorts without saving. `:GnosisReview` returns to it; `:GnosisYomiReview` reviews every member) ・ Enter in insert mode on a `- [ ]` line … starts the next line with `- [ ] ` (Enter on an empty item ends the list) ・ `\n` (`:GnosisQuick`) … quick note (a blank note with no questions; listed in the diary automatically; connect it later) ・ `\M` (`:GnosisCaptureImport`) … import the Gnosis memo APK's memos from a phone connected by USB ・ `\N` (`:GnosisOrphans`) … list of notes not connected to anything (connect rough notes later)
- `\1`〜`\9` … jump to the Nth hub entry (inside the hub, normal link numbers)
- `\i` … open `index.md` ・ `\A` … the note app (Electron / browser)
- `\q` … list of work tabs (shown by note **title**; duplicate titles also show the file name). Pick with `↑` / `↓` (`j` / `k`), switch with `Enter`, close with `Esc` (`q`). `/` filters by title, `a` add ・ `x` close ・ `X` close others ・ `C` close all (`:GnosisTabs`)
- `\o` … open the link under the cursor in a new work tab (`<CR>` moves inside the current tab; `:GnosisOpenLinkTab`)
- `Alt+V` in the app (`\A`) … view-only mode ⇔ normal Vim. View-only (VIEW at the bottom) shows no cursor and does not send editing keys. Scroll with `j`/`k`, arrows, PageUp/Down, `gg`/`G`, `Ctrl-d`/`Ctrl-u`. Search with `/` `?` `n` `N` `*` `#`. Also usable: `gs`, `gm`, Space, Tab, `<CR>`, `<BS>`, `_`, digits, `\h` `\H` `\0` `\i` `\d` `\.` `\L` `\gi` `\r` `\bu` `\k` `\j` `\J` `\sc`
- `Alt` + click on a link in the app … moves only the cursor onto the link without opening it (to move only the cursor onto a link)
- The app also draws tables (`| a | b |`) and `<img src="…" width="50%">`. Inside a table or in insert mode the cursor line stays plain text
- `\d` … open today's diary (created if missing; `:GnosisToday`). Notes you create are added to the diary's "today's notes" automatically (`:GnosisDiaryUpdate` updates all diaries; `:GnosisDiaryAdopt` registers the current note as the diary of its date)
- `zw` … start writing at the bottom of the body of the open note (any note, not only a diary): the cursor goes on the line after one blank line below the last sentence (with one more blank line below it)
- `\I` … change the size of image markup (visual: the selection)

## Expanding, images and more

- `\e` … expand the notes around the current one into one md (`expand_v2.py`; choose **simple/detailed**; detailed takes 5 values and can save / load / delete named presets; output `.trash/T_*.md`)
- `\se` … expand an S note into an A note (`expand_s.py`; output `.trash/T_*.md`)
- `\gi` … image gallery (the note's images, or all images under the Index, in the browser)
- `\oe` / `\O` … edit headings in a separate buffer (`:write` applies them to the note; `:OutlineEdit`)
- `\sc` … CopyStack (stack lines / selections with `y`, run `:CopyStack` again to put them in the clipboard)
- `mx` … toggle the checkbox `[ ]` / `[x]` of the line (visual: the selection)

## Search (fzf)

- `gs` … full-text search of the vault (titles first; titles on the left, hits highlighted on the right) → `⏎` opens the hit line (`:GnosisSearch`)
- `<Space>` … search the notes linked from the current note (titles first; their bodies too) → `⏎` opens
- `\l` … choose a note with the same search and put a link with a position key (`:GnosisLinkPick`)
- Search modes (shared by `gs` and normal / visual `\l`) … `Ctrl+→` / `Ctrl+↓` cycle forward, `Ctrl+←` / `Ctrl+↑` backward: All → Groups → Groups + index names → Notes. The screen shows the current mode. Switching preserves the query and works with zero results. Plain arrows keep their existing behavior
- Index names … body links in groups (`index.md`, topic indexes, etc.) supply independent candidates pointing to their destination only when that destination's `Group:` lists the source group. Relation fields, code, and ordinary notes' body links are excluded. Different names for one destination stay separate; identical destination/name pairs are deduplicated. Normal `\l` inserts that display name, visual `\l` keeps the selected text. `gs` opens the destination (a name-only hit does not jump to a made-up body hit line)
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
- `:GnosisMount` … mount by hand ・ `:GnosisLock` … lock by hand (unmount). A vault that another window or app is using is not locked (`:GnosisLock!` forces it)
- Several windows (Vim, the `\A` app) can open different vaults, or the same vault, at the same time. An encrypted vault is locked only when **the last window using it** ends (or switches to another vault). The registry lives outside the vault (`sessions/` in the Gnosis home), and entries of processes that crashed are removed automatically. If a note you are editing in several windows was changed elsewhere, autosave does not overwrite it: your unsaved content is backed up to `.state/conflicts/` and you get a warning
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
- **Context is a `Context:` block at the top of the body (right after the H1 title)** (plain text line, not a Markdown heading; the links follow directly). A link added with `c` goes to the end of the existing links, and the same note is never added twice. The old `### Context` is still read (a note you add to with `c` moves to the new format without losing links; old-style notes are not rewritten just by opening them or syncing; migrate explicitly with `:GnosisContextMigrate` (current note) / `:GnosisContextMigrate all` (dry run) / `:GnosisContextMigrate! all` (whole vault)). A `Context:` inside a code block is not a Context
- Links to groups (`attribute: group`) go to `Group:`, links to normal notes to `Context:`, sorted by sync. Empty sections (ParentBranch / Group / ChildBranch / Related / BackLink) have no heading
- Order in a note: `ParentBranch:` → `BranchGroup:` → `Group:` → `Context:` (blocks above the body, right after the H1; a block is only the link lines that follow it and ends at a blank line) → body → `ChildBranch:` → `Related:` → `BackLink:` (sections below the body). Empty ones are not written. `ParentBranch:` / `ChildBranch:` are relations set explicitly with `b` / `p`; sync neither adds nor removes them (it only follows titles and removes links to deleted files; never converts them to Context). `h` (below the cursor) with the cursor on one of these blocks puts the link in the body (never into the block)

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
- Text lines (not links), code blocks, and links in the blocks above the body (`ParentBranch:` / `BranchGroup:` / `Group:` / `Context:`) and in or after `ChildBranch:` / `Related:` / `BackLink:` never move. With 0–1 links nothing changes
- The reading comes from the target note's front matter `yomi:` (display name → reading) first; missing ones are added to `yomi:` by pykakasi
- `zy` / `zY` fix / delete the reading per display name by hand

## Paper PKM (Folgezettel)

- `\f` … open the paper PKM Index (`Paper-Zettelkasten-Index.md`), creating it if missing (`:GnosisPaperIndex`). Index-write and Folgezettel-Index are created too. Update with `\ua`
- `\F` … number scanned images and move them to the vault root (`:GnosisScan`; opens the numbering GUI). In the GUI, `d` = **register as a paper diary**
- `Index-write` … write `keyword(reading): 1,1a10b,3` by hand. Keywords with several IDs become group notes, single IDs become direct links in the paper PKM Index (regenerated on save)
- `\S` … in Index-write, keyword lines are sorted by reading too
- Folgezettel-Index lists all existing IDs (natural order). It is generated, so no `\S`
- Paper notes `1` and `1a` … `1` goes into `1a`'s `ParentBranch:` and `1a` into `1`'s `ChildBranch:` (Context is not used for this). A topic (`1-title`) has `1` as its `ParentBranch:`. Topics are also listed in the `## 1` section of `folgezettel-Index-1` (parent topic first, no indentation; the parent is the front matter `topic_parent:`; an unknown parent is never guessed)
- Paper diary … a `[紙の日記]` link is put under the title of that day's digital diary (one blank line, above the body; never duplicated on regeneration. If there is no digital diary that day, none is created; the link is added by `\ua` after the diary exists). Notes from scans carry `source: scan` in the front matter and are not listed in "today's notes"

## Phone memo (Gnosis memo APK)

- Open the app and start writing right away. One entry = one note. Entries in the diary topic go into the diary body with a timestamp when imported.
- Writing in "All" leaves the topic unselected. Switch between all, diary, individual topics and unselected, and move several entries by selecting them.
- PC `\N` also groups memos by topic regardless of device. Press `t` on one line or a visual selection to change topics (empty for unselected). `:GnosisTopic 仕事` also changes the topic.
- To move them to the PC, connect the phone by USB and press `\M` in Gnosis on the PC. No password is needed. Imported entries get a ✓ on the phone. Each vault imports independently; importing never deletes phone originals. Titles use the first 20 characters; the body stays intact.
- Periodic alarm (the clock at the top right of the phone app): off at first. Set "every N minutes", "from hour" and "until hour" as numbers.
  - To ring around the clock: press **24時間** (sets **from** 0 and **until** 24).
  - The "until" hour is not included (9 to 23 means the last ring is in the 22:xx hour).
  - Equal "from" and "until" hours also mean all day. Settings show notification permissions, sound, the next alarm time and a test notification.
- For installing on the phone (including the USB debugging permission), see "Build and install the APK" in `docs/11-スマホのメモ.md`.

## Ex commands

The canonical name of every command starts with `:Gnosis` (press Tab after `:Gnosis` for candidates). Old commands starting with `:Yurii` are aliases of the `:Gnosis` command with the same name (compatibility). Short old names (`:NF` etc.) are kept for compatibility too.

### Start, vaults and settings
- `:GnosisStart` `:GnosisVaults` `:GnosisSettings` `:GnosisThemeAdd` `:GnosisThemeReset` `:GnosisIndex` `:GnosisChooseIndex` `:GnosisChooseIndexDir` `:GnosisGuide` `:GnosisWeb`

### Creating and migrating notes
- `:GnosisNF` / `:NF` quick new note with a title ・ `:GnosisNA` / `:NA` "A" type below the cursor ・ `:GnosisNH` / `:NH` new note here
- `:GnosisNP` / `:NP` new as parent ・ `:GnosisNC` / `:NC` new as child ・ `:GnosisV2Migrate` / `:V2Migrate` migrate from the old format

### Links and relations
- `:GnosisLinkify` / `:Linkify` link the text under the cursor ・ `:GnosisLinkifySelection` / `:LinkifySelection` selection to a new note ・ `:GnosisPasteLink` / `:PasteLink` add links from the clipboard
- `:GnosisAT` `:GnosisBC` `:GnosisCA` `:GnosisCU` `:GnosisTT` / `:AT` `:BC` `:CA` `:CU` `:TT` … add from the clipboard with a relation (keys retired; commands remain) ・ `:GnosisYN` / `:YN` yank the file name
- `:GnosisLT` / `:LT` / `:GnosisRenameLinkText` / `:RenameLinkText` change a display name ・ `:GnosisNT` / `:NT` change the title ・ `:GnosisRenameChildLinkTitles` / `:RenameChildLinkTitles` / `:GnosisRenameDownLinkTitles` / `:RenameDownLinkTitles` update child link names
- `:GnosisWNext` open the next link target left by w ・ `:GnosisContextMigrate` migrate an old-style Context to the new format explicitly ・ `:GnosisBranchCheck` check Branch consistency (reports several parents, one-sided links, cycles and self references; rewrites nothing) ・ `:GnosisLinkPick` / `:LinkPick` search and insert a link ・ `:GnosisSearch` / `:GnosisFSearch` / `:FSearch` full-text search ・ `:GnosisFileContentSearch` / `:FileContentSearch` full-text search

### Moving
- `:GnosisTabs` list of work tabs (`\q`) ・ `:GnosisOpenLinkTab` open a link in a new work tab (`\o`)
- `:GnosisJumpParent` / `:JumpParent` / `:GnosisJumpUp` / `:JumpUp` to the parent ・ `:GnosisJumpChildTop` / `:JumpChildTop` / `:GnosisJumpDownTop` / `:JumpDownTop` first child ・ `:GnosisJumpChildBottom` / `:JumpChildBottom` / `:GnosisJumpDownBottom` / `:JumpDownBottom` last child
- `:GnosisJumpLastLinkBeforeParent` / `:JumpLastLinkBeforeParent` / `:GnosisJumpLastLinkBeforeUp` / `:JumpLastLinkBeforeUp` last link near Context

### Expanding and outline
- `:GnosisSE` / `:SE` / `:GnosisExpandToT` / `:ExpandToT` / `:GnosisExpandLinks` / `:ExpandLinks` expand an S note ・ `:GnosisOutlineEdit` / `:OutlineEdit` edit headings (apply with `:OutlineApply`)

### Diary, encryption, trash, paper PKM, images
- `:GnosisRefreshColors` clear leftover highlights and redraw the colors ・ `:GnosisColorDoctor` write a color diagnostics log to the logs folder of the Gnosis home
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
- `:GnosisApkInstall` build the phone memo APK and install it on the phone connected by USB (allow USB debugging on the phone first)
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
