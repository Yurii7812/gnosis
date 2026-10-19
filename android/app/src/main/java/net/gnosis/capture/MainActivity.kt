package net.gnosis.capture

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings as AndroidSettings
import androidx.core.app.NotificationManagerCompat
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : ComponentActivity() {
    private val promptState = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        promptState.value = intent?.getBooleanExtra(Alarm.EXTRA_PROMPT, false) == true
        setContent {
            MaterialTheme(colorScheme = GnosisColors) {
                Surface(Modifier.fillMaxSize()) { CaptureScreen(Store(this), promptState) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(Alarm.EXTRA_PROMPT, false)) promptState.value = true
    }

    override fun onResume() {
        super.onResume()
        if (Alarm.takePrompt(this)) promptState.value = true
    }
}

/** PC の Gnosis のダーク（既定のテーマ・起動画面と同じ）に合わせた配色。文字は真っ白にせず、背景との差は十分に取る。 */
private val GnosisColors = darkColorScheme(
    primary = Color(0xFF6CB6FF), onPrimary = Color(0xFF0D1117),
    primaryContainer = Color(0xFF2D4F75), onPrimaryContainer = Color(0xFFE6EDF3),
    secondary = Color(0xFFE5C07B), onSecondary = Color(0xFF22272E),
    secondaryContainer = Color(0xFF3D3726), onSecondaryContainer = Color(0xFFF2E3C0),
    tertiary = Color(0xFF83AFE2), onTertiary = Color(0xFF22272E),
    background = Color(0xFF22272E), onBackground = Color(0xFFCDD5DE),
    surface = Color(0xFF22272E), onSurface = Color(0xFFCDD5DE),
    surfaceVariant = Color(0xFF2D333B), onSurfaceVariant = Color(0xFFADBAC7),
    surfaceContainerLowest = Color(0xFF1C2128), surfaceContainerLow = Color(0xFF262C34),
    surfaceContainer = Color(0xFF2A3038), surfaceContainerHigh = Color(0xFF30363F),
    surfaceContainerHighest = Color(0xFF373E47),
    outline = Color(0xFF909DAB), outlineVariant = Color(0xFF444C56),
)

private val timeFmt = SimpleDateFormat("HH:mm", Locale.JAPAN)
private val dayFmt = SimpleDateFormat("M月d日（E）", Locale.JAPAN)
private fun dayKey(t: Long) = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date(t))

private fun short(s: String, n: Int = 24): String {
    val one = MEMO_LINK.replace(s) { it.groupValues[1] }.replace('\n', ' ').trim()
    return if (one.length <= n) one.ifEmpty { "（画像）" } else one.take(n) + "…"
}

/** メモの本文の中の、ほかのメモへのリンク: [表示名](memo:ID)。PC で取り込むと Gnosis のリンクになる。 */
val MEMO_LINK = Regex("\\[([^\\]\\n]*)\\]\\(memo:([^)\\s]+)\\)")

/** リンクの表示名（メモにはタイトルが無いので、本文の最初の行を短く）。[ ] は使わない。 */
fun linkLabel(text: String): String =
    short(text.lineSequence().firstOrNull { it.isNotBlank() } ?: text, 20).replace("[", "").replace("]", "")

data class Pick(val kind: String, val forId: String?)   // kind: link / context / parent

/** メモを探して選ぶ画面。リンク・文脈は複数、親（parent）は 1 つ。新しい順。 */
@Composable
private fun PickDialog(entries: List<Entry>, kind: String, exclude: Set<String>, onDismiss: () -> Unit, onDone: (List<String>) -> Unit) {
    var q by remember { mutableStateOf("") }
    val chosen = remember { mutableStateListOf<String>() }
    val multi = kind != "parent"
    val list = entries.filter { it.id !in exclude && matchesQuery(it.text, q) }
        .sortedByDescending { it.created }
    AlertDialog(onDismissRequest = onDismiss,
        title = { Text(when (kind) { "link" -> "リンクするメモ"; "context" -> "文脈にするメモ"; else -> "親（Branch）にするメモ" }) },
        text = {
            Column {
                OutlinedTextField(q, { q = it }, placeholder = { Text("探す（本文の一部）") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                if (multi) Text("複数選べます（${chosen.size} 件）", fontSize = 12.sp, color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(top = 4.dp))
                LazyColumn(Modifier.heightIn(max = 360.dp).padding(top = 6.dp)) {
                    items(list, key = { it.id }) { e ->
                        Row(Modifier.fillMaxWidth().clickable {
                            if (!multi) onDone(listOf(e.id)) else if (e.id in chosen) chosen.remove(e.id) else chosen.add(e.id)
                        }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            if (multi) Checkbox(checked = e.id in chosen, onCheckedChange = { if (it) chosen.add(e.id) else chosen.remove(e.id) })
                            Column(Modifier.weight(1f)) {
                                Text(short(e.text, 40), fontSize = 15.sp)
                                Text(dayFmt.format(Date(e.created)) + " " + timeFmt.format(Date(e.created)) + "  " + topicLabel(e.topic),
                                    fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { if (multi) TextButton(onClick = { onDone(chosen.toList()) }, enabled = chosen.isNotEmpty()) { Text("決定") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("やめる") } })
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun CaptureScreen(store: Store, promptState: MutableState<Boolean>) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val entries = remember { mutableStateListOf<Entry>().apply { addAll(store.load()) } }
    var settings by remember { mutableStateOf(store.loadSettings()) }
    var topic by remember { mutableStateOf(settings.lastTopic) }
    val topics = (settings.topics + entries.map { it.topic }).filter { it.isNotEmpty() && it != ALL }.distinct()
    val selected = remember { mutableStateListOf<String>() }
    var selecting by remember { mutableStateOf(false) }
    var moveSelectedOpen by remember { mutableStateOf(false) }
    var fromPrompt by remember { mutableStateOf(false) }   // アラームから日記を開いている
    var pickingImage by remember { mutableStateOf(false) }
    var deleteSelectedOpen by remember { mutableStateOf(false) }
    var cleanImportedOpen by remember { mutableStateOf(false) }
    var notificationsEnabled by remember { mutableStateOf(Alarm.notificationsEnabled(ctx)) }
    var exactEnabled by remember { mutableStateOf(Alarm.canScheduleExact(ctx)) }
    var nextAlarm by remember { mutableStateOf(Alarm.scheduledTime(ctx)) }
    var input by remember { mutableStateOf("") }
    val pendingImages = remember { mutableStateListOf<String>() }
    var replyTo by remember { mutableStateOf<String?>(null) }      // 次に書くものの Branch の親
    val contextsTo = remember { mutableStateListOf<String>() }      // 次に書くものの文脈にするメモ（右スワイプで足す）
    var flash by remember { mutableStateOf<String?>(null) }
    var insertMenu by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }           // 上のバーの「＋」（チェックボックス・リンク・文脈・親）
    var pick by remember { mutableStateOf<Pick?>(null) }           // メモを探して選ぶ画面
    var relEditFor by remember { mutableStateOf<String?>(null) }   // 文脈・親を編集しているメモ        // 飛んだ先のメモを少しのあいだ目立たせる
    var contextFor by remember { mutableStateOf<String?>(null) }   // 文脈をつなぐ相手を選んでいる途中のメモ
    var editing by remember { mutableStateOf<String?>(null) }
    var sheetFor by remember { mutableStateOf<String?>(null) }
    var topicDialogFor by remember { mutableStateOf<String?>(null) }
    var addTopicOpen by remember { mutableStateOf(false) }
    var topicListOpen by remember { mutableStateOf(false) }       // 「その他」のトピック一覧
    var modeFor by remember { mutableStateOf<String?>(null) }      // 取り込み方（1 つのノートにまとめる・日時）を変えるトピック
    var search by remember { mutableStateOf<String?>(null) }      // 全文検索（null で閉じている）
    var settingsOpen by remember { mutableStateOf(false) }
    var imported by remember { mutableStateOf(store.importedIds()) }
    var deleteFor by remember { mutableStateOf<String?>(null) }
    val prompt by promptState
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val listState = rememberLazyListState()
    val byId = entries.associateBy { it.id }

    fun persist() { store.save(entries.toList()); imported = store.importedIds() }

    // PC が取り込むたびに imported.json が変わるので、戻ってくるたびに読み直す
    fun setTopic(t: String) {
        topic = t
        settings = settings.copy(lastTopic = t); store.saveSettings(settings)
    }
    LifecycleResumeEffect(Unit) {
        imported = store.importedIds()
        notificationsEnabled = Alarm.notificationsEnabled(ctx)
        exactEnabled = Alarm.canScheduleExact(ctx)
        Alarm.ensureScheduled(ctx, settings)
        nextAlarm = Alarm.scheduledTime(ctx)
        onPauseOrDispose {
            // アラームの日記を書き終えてアプリを閉じたら、全部表示に戻す（画像を選びに出たときは戻さない）
            if (fromPrompt && !pickingImage) { fromPrompt = false; promptState.value = false; setTopic(ALL) }
        }
    }

    // 開いたらすぐ書ける: 入力欄にカーソルを置き、キーボードを出す
    LaunchedEffect(Unit) {
        delay(150); focus.requestFocus(); keyboard?.show()
    }
    LaunchedEffect(prompt) {
        if (prompt) { fromPrompt = true; setTopic(DIARY); delay(150); focus.requestFocus(); keyboard?.show() }
    }
    LaunchedEffect(entries.size) { if (entries.isNotEmpty()) listState.animateScrollToItem(0) }

    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        pickingImage = false
        if (uri != null) {
            val name = "img-" + System.currentTimeMillis() + ".jpg"
            ctx.contentResolver.openInputStream(uri)?.use { i -> File(store.imageDir, name).outputStream().use { i.copyTo(it) } }
            pendingImages.add(name)
        }
    }
    val askNotify = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        notificationsEnabled = Alarm.notificationsEnabled(ctx)
    }
    /** child の親を parent にすると循環になるか（parent をたどって child に戻る）。 */
    fun wouldCycle(child: String, parent: String): Boolean {
        var p: String? = parent
        val seen = HashSet<String>()
        while (p != null && seen.add(p)) {
            if (p == child) return true
            p = entries.firstOrNull { it.id == p }?.parent
        }
        return false
    }

    /** 親（Branch）を付け替える。null で外す。循環になるときは変えない。 */
    fun setParent(id: String, parent: String?) {
        val k = entries.indexOfFirst { it.id == id }
        if (k < 0 || (parent != null && (parent == id || wouldCycle(id, parent)))) return
        entries[k] = entries[k].copy(parent = parent, exported = false); persist()
    }

    /** 文脈を足す。親が無ければ最初の文脈を親（Branch）にする（PC の Gnosis の c と同じ）。 */
    fun addContexts(id: String, ids: List<String>) {
        val k = entries.indexOfFirst { it.id == id }
        if (k < 0) return
        val e = entries[k]
        val cs = (e.contexts + ids).filter { it != id }.distinct()
        val parent = e.parent ?: cs.firstOrNull { !wouldCycle(id, it) }
        entries[k] = e.copy(contexts = cs, parent = parent, exported = false); persist()
    }

    fun removeContext(id: String, c: String) {
        val k = entries.indexOfFirst { it.id == id }
        if (k >= 0) { entries[k] = entries[k].copy(contexts = entries[k].contexts - c, exported = false); persist() }
    }

    /** 入力欄の最後に足す（行の途中なら改行してから）。 */
    fun appendInput(s: String, newLine: Boolean) {
        input = when {
            input.isEmpty() -> s
            newLine && !input.endsWith("\n") -> input + "\n" + s
            !newLine && !input.endsWith(" ") && !input.endsWith("\n") -> "$input $s"
            else -> input + s
        }
    }

    /** 文脈や Branch の親のメモへスクロールし、少しのあいだ色を変えて知らせる。 */
    fun jumpTo(id: String) {
        if (visibleEntries(entries, topic).none { it.id == id }) setTopic(ALL)
        scope.launch {
            delay(50)
            val list = visibleEntries(entries, topic).sortedByDescending { it.created }
            var idx = 0
            for ((i, x) in list.withIndex()) {
                if (x.id == id) break
                idx++
                val next = list.getOrNull(i + 1)
                if (next == null || dayKey(next.created) != dayKey(x.created)) idx++   // 日付の見出しの行
            }
            listState.animateScrollToItem(idx)
            flash = id; delay(1500); if (flash == id) flash = null
        }
    }

    /** 選んだメモを古い順に 1 件へまとめる（本文は空行で区切る。画像・文脈も引き継ぐ）。 */
    fun mergeEntries(ids: Set<String>) {
        val group = entries.filter { it.id in ids }.sortedBy { it.created }
        if (group.size < 2) return
        val base = group.first()
        val others = group.drop(1).map { it.id }.toSet()
        val merged = base.copy(
            text = group.map { it.text.trim() }.filter { it.isNotEmpty() }.joinToString("\n\n"),
            images = group.flatMap { it.images },
            parent = base.parent?.takeIf { it !in ids },
            contexts = group.flatMap { it.contexts }.filter { it !in ids }.distinct(),
            edited = System.currentTimeMillis(), exported = false)
        entries.removeAll { it.id in others }
        for (k in entries.indices) {
            val e = if (entries[k].id == base.id) merged else entries[k]
            val parent = if (e.parent in others) base.id else e.parent
            val contexts = e.contexts.map { if (it in others) base.id else it }.filter { it != e.id }.distinct()
            entries[k] = if (parent != e.parent || contexts != e.contexts) e.copy(parent = parent.takeIf { it != e.id }, contexts = contexts, exported = false) else e
        }
        persist()
    }

    fun toggleSelection(id: String) {
        if (id in selected) selected.remove(id) else selected.add(id)
    }
    fun moveEntries(ids: Collection<String>, destination: String) {
        val now = System.currentTimeMillis()
        for (k in entries.indices) if (entries[k].id in ids) {
            entries[k] = entries[k].copy(topic = destination, edited = now, exported = false)
        }
        persist()
    }

    fun deleteEntries(ids: Set<String>) {
        entries.filter { it.id in ids }.flatMap { it.images }.forEach { File(store.imageDir, it).delete() }
        entries.removeAll { it.id in ids }
        for (k in entries.indices) {
            val e = entries[k]
            if (e.parent in ids || e.contexts.any { it in ids }) entries[k] = e.copy(parent = e.parent.takeIf { it !in ids }, contexts = e.contexts.filter { it !in ids }, exported = false)
        }
        persist()
    }

    fun send() {
        val text = input.trim()
        if (text.isEmpty() && pendingImages.isEmpty()) return
        val ed = editing
        if (ed != null) {
            val i = entries.indexOfFirst { it.id == ed }
            if (i >= 0) entries[i] = entries[i].copy(text = text, images = entries[i].images + pendingImages, edited = System.currentTimeMillis(), exported = false)
            editing = null
        } else {
            val now = System.currentTimeMillis()
            entries.add(Entry(id = Store.newId(now, entries), created = now, topic = writingTopic(topic), text = text,
                images = pendingImages.toList(), parent = replyTo ?: contextsTo.firstOrNull(), contexts = contextsTo.toList()))
            replyTo = null; contextsTo.clear()
        }
        input = ""; pendingImages.clear(); promptState.value = false
        persist()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    val n = entries.count { it.id !in imported }
                    val sq = search
                    if (sq != null) {
                        val fr = remember { FocusRequester() }
                        OutlinedTextField(sq, { search = it }, placeholder = { Text("メモを全文検索") }, singleLine = true,
                            modifier = Modifier.fillMaxWidth().focusRequester(fr))
                        LaunchedEffect(Unit) { fr.requestFocus() }
                    } else Column {
                        Text(if (selecting) "${selected.size} 件選択" else topicLabel(topic), fontWeight = FontWeight.Bold,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(if (n == 0) "すべて取り込み済み" else "未取り込み $n 件", fontSize = 12.sp,
                            maxLines = 1, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                actions = {
                    IconButton(onClick = { search = if (search == null) "" else null }) {
                        Icon(if (search != null) Icons.Filled.Close else Icons.Filled.Search, if (search != null) "検索をやめる" else "全文検索")
                    }
                    if (search == null && !selecting) Box {
                        IconButton(onClick = { insertMenu = true }) { Icon(Icons.Filled.AddCircleOutline, "挿入（チェックボックス・リンク・文脈・親）") }
                        DropdownMenu(expanded = insertMenu, onDismissRequest = { insertMenu = false }) {
                            DropdownMenuItem(text = { Text("チェックボックス") }, leadingIcon = { Icon(Icons.Filled.CheckBox, null) }, onClick = {
                                insertMenu = false; appendInput("- [ ] ", true); scope.launch { delay(100); focus.requestFocus(); keyboard?.show() }
                            })
                            DropdownMenuItem(text = { Text("リンク（メモを探す）") }, leadingIcon = { Icon(Icons.Filled.InsertLink, null) }, onClick = {
                                insertMenu = false; pick = Pick("link", editing)
                            })
                            DropdownMenuItem(text = { Text("文脈（メモを探す）") }, leadingIcon = { Icon(Icons.Filled.Link, null) }, onClick = {
                                insertMenu = false; pick = Pick("context", editing)
                            })
                            DropdownMenuItem(text = { Text("親（Branch）") }, leadingIcon = { Icon(Icons.Filled.SubdirectoryArrowRight, null) }, onClick = {
                                insertMenu = false; pick = Pick("parent", editing)
                            })
                        }
                    }
                    // 選択中は「選択をやめる」だけを出す。ほかのあまり使わない操作は ⋮ のメニューに
                    if (selecting) IconButton(onClick = { selecting = false; selected.clear() }) { Icon(Icons.Filled.Close, "選択をやめる") }
                    else if (search == null) Box {
                        IconButton(onClick = { moreMenu = true }) { Icon(Icons.Filled.MoreVert, "そのほか") }
                        DropdownMenu(expanded = moreMenu, onDismissRequest = { moreMenu = false }) {
                            DropdownMenuItem(text = { Text("複数選択") }, leadingIcon = { Icon(Icons.Filled.Checklist, null) }, onClick = {
                                moreMenu = false; selecting = true; selected.clear(); contextFor = null; keyboard?.hide()
                            })
                            DropdownMenuItem(text = { Text("取り込み済みのメモを消す") }, leadingIcon = { Icon(Icons.Filled.DeleteSweep, null) }, onClick = {
                                moreMenu = false; cleanImportedOpen = true
                            })
                            DropdownMenuItem(text = { Text("アラームと設定") }, leadingIcon = { Icon(Icons.Filled.Alarm, null) }, onClick = {
                                moreMenu = false; settingsOpen = true
                            })
                        }
                    }
                },
            )
        },
        bottomBar = {
            Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding().padding(horizontal = 8.dp, vertical = 4.dp)) {
                // つなぎ方の案内（WhatsApp の返信のように、何に続けて書いているかを見せる）
                val banners = buildList<Pair<String, () -> Unit>> {
                    if (contextFor != null) add("文脈にするメモを続けてタップ（「${short(byId[contextFor]?.text ?: "")}」の文脈。終わったら ×）" to { contextFor = null })
                    if (editing != null) add("編集中: ${short(byId[editing]?.text ?: "")}" to { editing = null; input = "" })
                    if (replyTo != null) add("↳ 続きとして書く（Branch の子）: ${short(byId[replyTo]?.text ?: "")}" to { replyTo = null })
                    if (contextsTo.isNotEmpty()) add("⇢ 文脈 ${contextsTo.size} 件: " + contextsTo.joinToString("、") { short(byId[it]?.text ?: "", 10) } to { contextsTo.clear() })
                }
                banners.forEach { banner ->
                    Surface(tonalElevation = 3.dp, shape = RoundedCornerShape(10.dp), modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
                        Row(Modifier.padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(banner.first, Modifier.weight(1f), fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            IconButton(onClick = banner.second) { Icon(Icons.Filled.Close, "やめる") }
                        }
                    }
                }
                if (selecting) {
                    Column {
                        Row {
                            TextButton(onClick = {
                                selected.clear(); selected.addAll(visibleEntries(entries, topic).map { it.id })
                            }) { Text("表示中を全選択") }
                            TextButton(onClick = { selected.clear() }) { Text("選択解除") }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedButton(onClick = {
                                val text = entries.filter { it.id in selected }.sortedBy { it.created }.joinToString("\n\n") { it.text }
                                ctx.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("memo", text))
                                selected.clear(); selecting = false
                            }, enabled = selected.isNotEmpty(), modifier = Modifier.weight(1f)) { Text("コピー") }
                            OutlinedButton(onClick = { mergeEntries(selected.toSet()); selected.clear(); selecting = false }, enabled = selected.size >= 2, modifier = Modifier.weight(1f)) { Text("統合") }
                            OutlinedButton(onClick = { moveSelectedOpen = true }, enabled = selected.isNotEmpty(), modifier = Modifier.weight(1f)) { Text("移動") }
                            OutlinedButton(onClick = { deleteSelectedOpen = true }, enabled = selected.isNotEmpty(), modifier = Modifier.weight(1f)) { Text("消す") }
                        }
                    }
                }
                // 表示と書き込み先を同時に切り替える。全部表示からは未所属で保存。
                // 並べるのは 全部・未所属・日記・その他 だけ。その他を押すとトピックの一覧（探す・足す）
                val other = topic !in listOf(ALL, UNASSIGNED, DIARY)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(ALL, UNASSIGNED, DIARY).forEach { t ->
                        FilterChip(selected = t == topic, onClick = { setTopic(t) }, label = { Text(topicLabel(t)) },
                            leadingIcon = if (t == DIARY) ({ Icon(Icons.Filled.Book, null, Modifier.size(16.dp)) }) else null)
                    }
                    FilterChip(selected = other, onClick = { topicListOpen = true },
                        label = { Text(if (other) topic else "その他", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        trailingIcon = { Icon(Icons.Filled.ArrowDropDown, null, Modifier.size(18.dp)) })
                }
                if (pendingImages.isNotEmpty()) {
                    LazyRow(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(pendingImages.toList()) { name ->
                            Box {
                                AsyncImage(File(store.imageDir, name), null, Modifier.size(64.dp), contentScale = ContentScale.Crop)
                                IconButton(onClick = { pendingImages.remove(name) }, Modifier.size(24.dp).align(Alignment.TopEnd)) {
                                    Icon(Icons.Filled.Cancel, "外す")
                                }
                            }
                        }
                    }
                }
                Row(verticalAlignment = Alignment.Bottom) {
                    IconButton(onClick = { pickingImage = true; pickImage.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                        Icon(Icons.Filled.Image, "画像を付ける")
                    }
                    OutlinedTextField(
                        value = input, onValueChange = { input = it },
                        modifier = Modifier.weight(1f).focusRequester(focus),
                        placeholder = { Text(if (prompt) "今まで何してた？" else if (topic == DIARY) "日記（時刻は自動で付きます）" else if (writingTopic(topic).isEmpty()) "メモを書く（未所属）" else "$topic に書く") },
                        maxLines = 6, shape = RoundedCornerShape(20.dp),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, keyboardType = KeyboardType.Text),
                    )
                    IconButton(onClick = { send() }, enabled = input.isNotBlank() || pendingImages.isNotEmpty()) {
                        Icon(Icons.AutoMirrored.Filled.Send, "送る")
                    }
                }
            }
        },
    ) { pad ->
        // 検索中はトピックに関係なく、全部のメモの本文から探す
        val sq = search?.trim().orEmpty()
        val shown = (if (search != null && sq.isNotEmpty()) entries.filter { matchesQuery(it.text, sq) }
            else visibleEntries(entries, topic)).sortedByDescending { it.created }
        LazyColumn(Modifier.fillMaxSize().padding(pad), state = listState, reverseLayout = true,
            contentPadding = PaddingValues(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            shown.forEachIndexed { i, e ->
                item(key = e.id) {
                    // 右へスワイプ: このメモを文脈にして続ける / 左へスワイプ: このメモの Branch の子として続ける
                    val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { v ->
                        when (v) {
                            // 文脈は何件でも足せる（もう一度スワイプすると外す）。Branch の親は 1 つ。
                            SwipeToDismissBoxValue.StartToEnd -> { if (e.id in contextsTo) contextsTo.remove(e.id) else contextsTo.add(e.id); contextFor = null; editing = null }
                            SwipeToDismissBoxValue.EndToStart -> { replyTo = e.id; contextFor = null; editing = null }
                            else -> {}
                        }
                        if (v != SwipeToDismissBoxValue.Settled) scope.launch { delay(100); focus.requestFocus(); keyboard?.show() }
                        false   // メモ自体は動かさず元の位置に戻す
                    })
                    SwipeToDismissBox(swipe, enableDismissFromStartToEnd = !selecting, enableDismissFromEndToStart = !selecting,
                        backgroundContent = {
                            val toRight = swipe.dismissDirection == SwipeToDismissBoxValue.StartToEnd
                            val toLeft = swipe.dismissDirection == SwipeToDismissBoxValue.EndToStart
                            Row(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = if (toLeft) Arrangement.End else Arrangement.Start) {
                                if (toRight) { Icon(Icons.Filled.Link, null, tint = MaterialTheme.colorScheme.tertiary); Spacer(Modifier.width(6.dp)); Text("文脈で続ける", color = MaterialTheme.colorScheme.tertiary) }
                                if (toLeft) { Text("Branch で続ける", color = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(6.dp)); Icon(Icons.Filled.SubdirectoryArrowRight, null, tint = MaterialTheme.colorScheme.primary) }
                            }
                        }) {
                    Bubble(e, e.id in imported, byId, store, selecting = contextFor != null && contextFor != e.id, selected = e.id in selected || e.id == flash, selectionMode = selecting,
                        onTap = {
                            val cf = contextFor
                            if (search != null) { search = null; jumpTo(e.id) }   // 検索の結果を押すと、そのメモの場所へ
                            else if (selecting) toggleSelection(e.id)
                            else if (cf != null && cf != e.id) {
                                // 続けてタップして複数の文脈をつなぐ（もう一度タップすると外す）
                                val k = entries.indexOfFirst { it.id == cf }
                                if (k >= 0) {
                                    if (e.id in entries[k].contexts) removeContext(cf, e.id) else addContexts(cf, listOf(e.id))
                                }
                            }
                        },
                        onJump = { jumpTo(it) },
                        onLong = { if (selecting) toggleSelection(e.id) else sheetFor = e.id })
                    }
                }
                val next = shown.getOrNull(i + 1)
                if (next == null || dayKey(next.created) != dayKey(e.created)) {
                    item(key = "day-" + dayKey(e.created)) {
                        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                            Surface(shape = RoundedCornerShape(10.dp), tonalElevation = 2.dp) {
                                Text(dayFmt.format(Date(e.created)), Modifier.padding(horizontal = 10.dp, vertical = 3.dp), fontSize = 12.sp)
                            }
                        }
                    }
                }
            }
            if (shown.isEmpty()) item {
                Text("この表示にはまだメモがありません。\nここに書いたものは、USB でつないで Gnosis の \\M で取り込むと 1 件ずつノートになります。\n「日記」で書くと、その日の日記に時刻つきで入ります。\n長押しで「続けて書く（Branch）」「文脈につなぐ」などができます。",
                    Modifier.padding(24.dp), fontSize = 14.sp)
            }
        }
    }

    // 長押しのボタン（大きく、片手で押せるように 2 列）
    val target = sheetFor?.let { byId[it] }
    if (target != null) {
        ModalBottomSheet(onDismissRequest = { sheetFor = null }) {
            Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
                Text(short(target.text, 60), fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 12.dp))
                val acts = buildList<Triple<ImageVector, String, () -> Unit>> {
                    add(Triple(Icons.Filled.SubdirectoryArrowRight, "続けて書く\n（このメモの子）") { replyTo = target.id; contextFor = null })
                    add(Triple(Icons.Filled.Link, "文脈につなぐ\n（相手を続けてタップ）") { contextFor = target.id; replyTo = null })
                    add(Triple(Icons.Filled.Edit, "書き直す") { editing = target.id; input = target.text })
                    add(Triple(Icons.Filled.Checklist, "複数選択") { selecting = true; selected.clear(); selected.add(target.id); contextFor = null; keyboard?.hide() })
                    add(Triple(Icons.Filled.Label, "トピックを変える") { topicDialogFor = target.id })
                    add(Triple(Icons.Filled.ContentCopy, "コピー") {
                        ctx.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("memo", target.text))
                    })
                    add(Triple(Icons.Filled.AccountTree, "文脈・親を\n編集") { relEditFor = target.id })
                    add(Triple(Icons.Filled.Delete, "消す") { deleteFor = target.id })
                }
                acts.chunked(2).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(bottom = 10.dp)) {
                        row.forEach { (icon, label, act) ->
                            OutlinedButton(onClick = { act(); sheetFor = null; if (!selecting && relEditFor == null) scope.launch { delay(100); focus.requestFocus() } },
                                modifier = Modifier.weight(1f).heightIn(min = 64.dp), shape = RoundedCornerShape(14.dp)) {
                                Icon(icon, null); Spacer(Modifier.width(8.dp)); Text(label, fontSize = 14.sp)
                            }
                        }
                        if (row.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }

    topicDialogFor?.let { id ->
        AlertDialog(onDismissRequest = { topicDialogFor = null }, confirmButton = {}, title = { Text("トピック") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) { (listOf(UNASSIGNED) + topics).forEach { t ->
                    TextButton(onClick = {
                        moveEntries(listOf(id), t)
                        topicDialogFor = null
                    }) { Text(topicLabel(t), fontSize = 18.sp) }
                } }
            })
    }

    if (moveSelectedOpen) {
        AlertDialog(onDismissRequest = { moveSelectedOpen = false }, confirmButton = {},
            title = { Text("${selected.size} 件の移動先") }, text = {
                Column(Modifier.verticalScroll(rememberScrollState())) { (listOf(UNASSIGNED) + topics).forEach { t ->
                    TextButton(onClick = {
                        moveEntries(selected.toList(), t)
                        selected.clear(); selecting = false; moveSelectedOpen = false
                    }) { Text(topicLabel(t), fontSize = 18.sp) }
                } }
            })
    }

    if (topicListOpen) {
        var q by remember { mutableStateOf("") }
        val list = topics.filter { it != DIARY && matchesQuery(it, q) }
        AlertDialog(onDismissRequest = { topicListOpen = false }, title = { Text("トピック") },
            text = { Column {
                OutlinedTextField(q, { q = it }, placeholder = { Text("探す") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    leadingIcon = { Icon(Icons.Filled.Search, null) })
                LazyColumn(Modifier.heightIn(max = 360.dp).padding(top = 6.dp)) {
                    items(list) { t ->
                        val n = entries.count { it.topic == t }
                        Row(Modifier.fillMaxWidth().clickable { setTopic(t); topicListOpen = false }.padding(vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(t, fontSize = 16.sp, fontWeight = if (t == topic) FontWeight.Bold else null)
                                settings.topicModes[t]?.takeIf { it.single }?.let { m ->
                                    Text("1 つのノートにまとめる" + if (m.stamp) "・日時あり" else "", fontSize = 11.sp, color = MaterialTheme.colorScheme.primary)
                                }
                            }
                            Text("$n 件", fontSize = 12.sp, color = MaterialTheme.colorScheme.outline)
                            IconButton(onClick = { modeFor = t }) { Icon(Icons.Filled.Settings, "取り込み方") }
                        }
                    }
                    if (list.isEmpty()) item { Text(if (q.isBlank()) "まだトピックがありません" else "見つかりません", Modifier.padding(vertical = 8.dp), color = MaterialTheme.colorScheme.outline) }
                }
                OutlinedButton(onClick = { topicListOpen = false; addTopicOpen = true }, modifier = Modifier.fillMaxWidth().padding(top = 6.dp)) { Text("＋ 新しいトピック") }
            } },
            confirmButton = { TextButton(onClick = { topicListOpen = false }) { Text("閉じる") } })
    }

    // トピックの取り込み方: 1 件 = 1 ノート（既定）か、このトピックの 1 つのノートにまとめるか
    modeFor?.let { t ->
        val m = settings.topicModes[t] ?: TopicMode()
        fun save(n: TopicMode) { settings = settings.copy(topicModes = settings.topicModes + (t to n)); store.saveSettings(settings) }
        AlertDialog(onDismissRequest = { modeFor = null }, title = { Text("「$t」の取り込み方") },
            text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("1 つのノートにまとめる", Modifier.weight(1f)); Switch(m.single, { save(m.copy(single = it)) })
                }
                Text(if (m.single) "PC に取り込むと「$t」のノートに追記します（文脈・親・リンクでつないだメモは、別のノートにしてリンクします）。"
                    else "PC に取り込むと 1 件 = 1 ノートになります。", fontSize = 13.sp, color = MaterialTheme.colorScheme.outline)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("日時を付ける", Modifier.weight(1f), color = if (m.single) Color.Unspecified else MaterialTheme.colorScheme.outline)
                    Switch(m.stamp, { save(m.copy(stamp = it)) }, enabled = m.single)
                }
                Text("日時ありは、日付ごとの見出しの下に「時:分 本文」で入ります。なしは本文だけを足します。", fontSize = 13.sp, color = MaterialTheme.colorScheme.outline)
            } },
            confirmButton = { TextButton(onClick = { modeFor = null }) { Text("閉じる") } })
    }

    if (addTopicOpen) {
        var name by remember { mutableStateOf("") }
        var single by remember { mutableStateOf(false) }
        var stamp by remember { mutableStateOf(true) }
        AlertDialog(onDismissRequest = { addTopicOpen = false },
            title = { Text("トピックを足す") },
            text = { Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedTextField(name, { name = it }, singleLine = true, placeholder = { Text("例: アイデア") })
                Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(single, { single = it }); Text("1 つのノートにまとめる") }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(stamp, { stamp = it }, enabled = single)
                    Text("日時を付ける", color = if (single) Color.Unspecified else MaterialTheme.colorScheme.outline)
                }
            } },
            confirmButton = { TextButton(onClick = {
                val t = normalizedTopic(name.trim()).takeUnless { it == ALL || it == "全部" || it == "全部表示" || it == "未所属" || it == "トピック未選択" || it == "その他" } ?: ""
                if (t.isNotEmpty() && t !in settings.topics) { settings = settings.copy(topics = settings.topics + t); store.saveSettings(settings) }
                if (t.isNotEmpty() && t != DIARY && single) { settings = settings.copy(topicModes = settings.topicModes + (t to TopicMode(true, stamp))); store.saveSettings(settings) }
                if (t.isNotEmpty()) setTopic(t)
                addTopicOpen = false
            }) { Text("足す") } },
            dismissButton = { TextButton(onClick = { addTopicOpen = false }) { Text("やめる") } })
    }

    // 文脈・親の編集（長押し →「文脈・親を編集」）
    relEditFor?.let { id ->
        val e = entries.firstOrNull { it.id == id }
        if (e == null) { relEditFor = null; return@let }
        AlertDialog(onDismissRequest = { relEditFor = null }, title = { Text("文脈・親を編集") },
            text = { Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(short(e.text, 40), fontSize = 13.sp, color = MaterialTheme.colorScheme.outline)
                Text("親（Branch）", fontWeight = FontWeight.Bold)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(e.parent?.let { short(byId[it]?.text ?: "（書き出し済み）", 24) } ?: "なし", Modifier.weight(1f))
                    TextButton(onClick = { pick = Pick("parent", id) }) { Text("変える") }
                    if (e.parent != null) TextButton(onClick = { setParent(id, null) }) { Text("外す") }
                }
                HorizontalDivider()
                Text("文脈（${e.contexts.size}）", fontWeight = FontWeight.Bold)
                e.contexts.forEach { c ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(short(byId[c]?.text ?: "（書き出し済み）", 28), Modifier.weight(1f))
                        IconButton(onClick = { removeContext(id, c) }) { Icon(Icons.Filled.Close, "外す") }
                    }
                }
                OutlinedButton(onClick = { pick = Pick("context", id) }, modifier = Modifier.fillMaxWidth()) { Text("＋ 文脈を追加（探す）") }
                Text("親が無いときは、最初の文脈が親（Branch）になります。", fontSize = 12.sp, color = MaterialTheme.colorScheme.outline)
            } },
            confirmButton = { TextButton(onClick = { relEditFor = null }) { Text("閉じる") } })
    }

    // メモを探して選ぶ（リンク・文脈は複数、親は 1 つ）
    pick?.let { p ->
        PickDialog(entries = entries, kind = p.kind, exclude = setOfNotNull(p.forId),
            onDismiss = { pick = null },
            onDone = { ids ->
                pick = null
                val target = p.forId
                when (p.kind) {
                    "link" -> {
                        appendInput(ids.joinToString(" ") { id -> "[" + linkLabel(byId[id]?.text ?: "") + "](memo:" + id + ")" }, false)
                        scope.launch { delay(100); focus.requestFocus(); keyboard?.show() }
                    }
                    "context" -> if (target != null) addContexts(target, ids) else ids.forEach { if (it !in contextsTo) contextsTo.add(it) }
                    "parent" -> ids.firstOrNull()?.let { if (target != null) setParent(target, it) else replyTo = it }
                }
            })
    }

    if (cleanImportedOpen) {
        val gone = entries.filter { it.id in imported }.map { it.id }.toSet()
        AlertDialog(onDismissRequest = { cleanImportedOpen = false }, title = { Text("取り込み済みのメモを消す") },
            text = { Text(if (gone.isEmpty()) "PC に取り込み済みのメモはありません。"
                else "PC に取り込み済み（✓）の ${gone.size} 件をスマホから消します。取り込んだ vault にメモが残っていることを確認してください。テスト用 vault に取り込んだだけなら消さないでください。画像も消え、元に戻せません。") },
            confirmButton = { TextButton(enabled = gone.isNotEmpty(), onClick = { deleteEntries(gone); cleanImportedOpen = false }) { Text("消す") } },
            dismissButton = { TextButton(onClick = { cleanImportedOpen = false }) { Text("やめる") } })
    }

    if (deleteSelectedOpen) {
        AlertDialog(onDismissRequest = { deleteSelectedOpen = false }, title = { Text("${selected.size} 件を消しますか？") },
            text = { Text("画像も消えます。元に戻せません。") },
            confirmButton = { TextButton(onClick = {
                deleteEntries(selected.toSet()); selected.clear(); selecting = false; deleteSelectedOpen = false
            }) { Text("消す") } },
            dismissButton = { TextButton(onClick = { deleteSelectedOpen = false }) { Text("やめる") } })
    }

    deleteFor?.let { id ->
        AlertDialog(onDismissRequest = { deleteFor = null }, title = { Text("消しますか？") },
            text = { Text(short(byId[id]?.text ?: "", 80)) },
            confirmButton = { TextButton(onClick = {
                deleteEntries(setOf(id)); deleteFor = null
            }) { Text("消す") } },
            dismissButton = { TextButton(onClick = { deleteFor = null }) { Text("やめる") } })
    }

    if (settingsOpen) {
        var on by remember { mutableStateOf(settings.alarmOn) }
        var minutes by remember { mutableStateOf(settings.alarmMinutes.toString()) }
        var from by remember { mutableStateOf(settings.fromHour.toString()) }
        var to by remember { mutableStateOf(settings.toHour.toString()) }
        var allDay by remember { mutableStateOf(settings.fromHour == settings.toHour || (settings.fromHour == 0 && settings.toHour == 24)) }
        AlertDialog(onDismissRequest = { settingsOpen = false }, title = { Text("アラームと設定") },
            text = { Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("定期的に鳴らす", Modifier.weight(1f)); Switch(on, { on = it })
                }
                OutlinedTextField(minutes, { minutes = it.filter(Char::isDigit) }, label = { Text("何分おき") }, singleLine = true,
                    enabled = on, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("24時間鳴らす", Modifier.weight(1f), color = if (on) Color.Unspecified else MaterialTheme.colorScheme.outline)
                    Switch(allDay, {
                        allDay = it
                        // 24時間をやめたら、時間帯を普段の値で入れておく
                        if (!it && (from == to || (from == "0" && to == "24"))) { from = "9"; to = "23" }
                    }, enabled = on)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(from, { from = it.filter(Char::isDigit) }, label = { Text("何時から") }, singleLine = true, enabled = on && !allDay,
                        modifier = Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                    OutlinedTextField(to, { to = it.filter(Char::isDigit) }, label = { Text("何時まで") }, singleLine = true, enabled = on && !allDay,
                        modifier = Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
                Text("鳴ったら通知を押すと「今まで何してた？」が日記で開きます。", fontSize = 13.sp)
                if (on && !allDay && from == to) Text("開始と終了が同じ場合も24時間鳴らします。", fontSize = 13.sp)
                if (settings.alarmOn && nextAlarm > 0) Text("次回: " + SimpleDateFormat("M/d HH:mm", Locale.JAPAN).format(Date(nextAlarm)), fontSize = 13.sp)
                if (!notificationsEnabled) Text("通知が許可されていません。「通知と音の設定」で許可してください。", fontSize = 13.sp)
                TextButton(onClick = {
                    val action = if (NotificationManagerCompat.from(ctx).areNotificationsEnabled()) AndroidSettings.ACTION_CHANNEL_NOTIFICATION_SETTINGS else AndroidSettings.ACTION_APP_NOTIFICATION_SETTINGS
                    ctx.startActivity(Intent(action).putExtra(AndroidSettings.EXTRA_APP_PACKAGE, ctx.packageName).putExtra(AndroidSettings.EXTRA_CHANNEL_ID, Alarm.CHANNEL))
                }) { Text("通知と音の設定") }
                if (!exactEnabled && Build.VERSION.SDK_INT >= 31) {
                    Text("時刻どおりに鳴らすには「アラームとリマインダー」を許可してください。未許可では遅れる場合があります。", fontSize = 13.sp)
                    TextButton(onClick = { ctx.startActivity(Intent(AndroidSettings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${ctx.packageName}"))) }) { Text("アラームの時刻を許可") }
                }
                TextButton(onClick = {
                    if (Build.VERSION.SDK_INT >= 33 && !Alarm.hasNotificationPermission(ctx)) askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
                    else Alarm.notify(ctx)
                }) { Text("テスト通知を鳴らす") }
                HorizontalDivider()
                Text("PC へは USB でつなぎ、Gnosis で \\M を押すと取り込めます（パスワードは要りません）。", fontSize = 13.sp)
            } },
            confirmButton = { TextButton(onClick = {
                settings = settings.copy(alarmOn = on, alarmMinutes = (minutes.toIntOrNull() ?: 60).coerceIn(1, 24 * 60),
                    fromHour = if (allDay) 0 else (from.toIntOrNull() ?: 9).coerceIn(0, 23),
                    toHour = if (allDay) 24 else (to.toIntOrNull() ?: 23).coerceIn(0, 24))
                store.saveSettings(settings)
                if (on && Build.VERSION.SDK_INT >= 33 && !Alarm.hasNotificationPermission(ctx)) askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
                Alarm.ensureChannel(ctx); Alarm.schedule(ctx, settings)
                nextAlarm = Alarm.scheduledTime(ctx)
                settingsOpen = false
            }) { Text("保存") } },
            dismissButton = { TextButton(onClick = { settingsOpen = false }) { Text("閉じる") } })
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Bubble(e: Entry, done: Boolean, byId: Map<String, Entry>, store: Store, selecting: Boolean, selected: Boolean, selectionMode: Boolean, onTap: () -> Unit, onLong: () -> Unit, onJump: (String) -> Unit) {
    // 日記も他のメモと同じ色（トピックは右下の小さな文字で分かる）
    val colors = if (selected) CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
    else CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Card(colors = colors, shape = RoundedCornerShape(14.dp),
            border = if (selecting) CardDefaults.outlinedCardBorder() else null,
            modifier = Modifier.widthIn(max = 340.dp).combinedClickable(onClick = onTap, onLongClick = onLong)) {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                if (selectionMode) Checkbox(checked = selected, onCheckedChange = { onTap() })
                // 押すとそのメモへ飛ぶ
                e.parent?.let { p ->
                    Text("↳ ${short(byId[p]?.text ?: "（書き出し済み）")} の続き", fontSize = 12.sp, color = MaterialTheme.colorScheme.primary,
                        textDecoration = if (p in byId) TextDecoration.Underline else null,
                        modifier = if (p in byId) Modifier.clickable { onJump(p) }.padding(vertical = 2.dp) else Modifier)
                }
                e.contexts.forEach { c ->
                    Text("文脈: " + short(byId[c]?.text ?: "（書き出し済み）", 20), fontSize = 12.sp, color = MaterialTheme.colorScheme.tertiary,
                        textDecoration = if (c in byId) TextDecoration.Underline else null,
                        modifier = if (c in byId) Modifier.clickable { onJump(c) }.padding(vertical = 2.dp) else Modifier)
                }
                e.images.forEach { name ->
                    AsyncImage(File(store.imageDir, name), null, Modifier.padding(vertical = 4.dp).heightIn(max = 220.dp).fillMaxWidth(),
                        contentScale = ContentScale.Fit)
                }
                if (e.text.isNotEmpty()) {
                    // [表示名](memo:ID) は表示名だけを下線つきで見せる。押して飛ぶのは下の「リンク:」の行
                    val linkColor = MaterialTheme.colorScheme.primary
                    Text(buildAnnotatedString {
                        var last = 0
                        for (m in MEMO_LINK.findAll(e.text)) {
                            append(e.text.substring(last, m.range.first))
                            withStyle(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)) { append(m.groupValues[1]) }
                            last = m.range.last + 1
                        }
                        append(e.text.substring(last))
                    }, fontSize = 16.sp)
                    MEMO_LINK.findAll(e.text).map { it.groupValues[2] }.distinct().forEach { id ->
                        Text("リンク: " + short(byId[id]?.text ?: "（書き出し済み）", 20), fontSize = 12.sp, color = MaterialTheme.colorScheme.primary,
                            textDecoration = if (id in byId) TextDecoration.Underline else null,
                            modifier = if (id in byId) Modifier.clickable { onJump(id) }.padding(vertical = 2.dp) else Modifier)
                    }
                }
                Row(Modifier.align(Alignment.End), verticalAlignment = Alignment.CenterVertically) {
                    Text(topicLabel(e.topic), fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
                    Spacer(Modifier.width(6.dp))
                    Text(timeFmt.format(Date(e.created)) + if (e.edited > 0) "（編集）" else "", fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
                    if (done) { Spacer(Modifier.width(4.dp)); Icon(Icons.Filled.DoneAll, "PC に取り込み済み", Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary) }
                }
            }
        }
    }
}
