package net.gnosis.capture

import android.Manifest
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.isSystemInDarkTheme
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
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
            val dark = isSystemInDarkTheme()
            MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxSize()) { CaptureScreen(Store(this), promptState) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(Alarm.EXTRA_PROMPT, false)) promptState.value = true
    }
}

private val timeFmt = SimpleDateFormat("HH:mm", Locale.JAPAN)
private val dayFmt = SimpleDateFormat("M月d日（E）", Locale.JAPAN)
private fun dayKey(t: Long) = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date(t))

private fun short(s: String, n: Int = 24): String {
    val one = s.replace('\n', ' ').trim()
    return if (one.length <= n) one.ifEmpty { "（画像）" } else one.take(n) + "…"
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun CaptureScreen(store: Store, promptState: MutableState<Boolean>) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val entries = remember { mutableStateListOf<Entry>().apply { addAll(store.load()) } }
    var settings by remember { mutableStateOf(store.loadSettings()) }
    var topic by remember { mutableStateOf(settings.lastTopic.takeIf { it in settings.topics } ?: DIARY) }
    var input by remember { mutableStateOf("") }
    val pendingImages = remember { mutableStateListOf<String>() }
    var replyTo by remember { mutableStateOf<String?>(null) }      // 次に書くものの Branch の親
    var contextFor by remember { mutableStateOf<String?>(null) }   // 文脈をつなぐ相手を選んでいる途中のメモ
    var editing by remember { mutableStateOf<String?>(null) }
    var sheetFor by remember { mutableStateOf<String?>(null) }
    var topicDialogFor by remember { mutableStateOf<String?>(null) }
    var addTopicOpen by remember { mutableStateOf(false) }
    var settingsOpen by remember { mutableStateOf(false) }
    var exportOpen by remember { mutableStateOf(false) }
    var exportResult by remember { mutableStateOf<Exporter.Result?>(null) }
    var exporting by remember { mutableStateOf(false) }
    var deleteFor by remember { mutableStateOf<String?>(null) }
    val prompt by promptState
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val listState = rememberLazyListState()
    val byId = entries.associateBy { it.id }

    fun persist() = store.save(entries.toList())
    fun setTopic(t: String) {
        topic = t
        settings = settings.copy(lastTopic = t); store.saveSettings(settings)
    }

    // 開いたらすぐ書ける: 入力欄にカーソルを置き、キーボードを出す
    LaunchedEffect(Unit) {
        delay(150); focus.requestFocus(); keyboard?.show()
    }
    LaunchedEffect(prompt) {
        if (prompt) { setTopic(DIARY); delay(150); focus.requestFocus(); keyboard?.show() }
    }
    LaunchedEffect(entries.size) { if (entries.isNotEmpty()) listState.animateScrollToItem(0) }

    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        if (uri != null) {
            val name = "img-" + System.currentTimeMillis() + ".jpg"
            ctx.contentResolver.openInputStream(uri)?.use { i -> File(store.imageDir, name).outputStream().use { i.copyTo(it) } }
            pendingImages.add(name)
        }
    }
    val askNotify = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }

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
            entries.add(Entry(id = Store.newId(now, entries), created = now, topic = topic, text = text,
                images = pendingImages.toList(), parent = replyTo))
            replyTo = null
        }
        input = ""; pendingImages.clear(); promptState.value = false
        persist()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    val n = entries.count { !it.exported }
                    Column {
                        Text("メモ", fontWeight = FontWeight.Bold)
                        Text(if (n == 0) "すべて書き出し済み" else "まだ書き出していない: $n 件", fontSize = 12.sp)
                    }
                },
                actions = {
                    IconButton(onClick = { exportOpen = true }) { Icon(Icons.Filled.Upload, "書き出す") }
                    IconButton(onClick = { settingsOpen = true }) { Icon(Icons.Filled.Alarm, "アラームと設定") }
                },
            )
        },
        bottomBar = {
            Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding().padding(horizontal = 8.dp, vertical = 4.dp)) {
                // つなぎ方の案内（WhatsApp の返信のように、何に続けて書いているかを見せる）
                val banner: Pair<String, () -> Unit>? = when {
                    contextFor != null -> "文脈にするメモをタップ（「${short(byId[contextFor]?.text ?: "")}」の文脈になります）" to { contextFor = null }
                    editing != null -> "編集中: ${short(byId[editing]?.text ?: "")}" to { editing = null; input = "" }
                    replyTo != null -> "↳ 続きとして書く（Branch の子）: ${short(byId[replyTo]?.text ?: "")}" to { replyTo = null }
                    else -> null
                }
                if (banner != null) {
                    Surface(tonalElevation = 3.dp, shape = RoundedCornerShape(10.dp), modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
                        Row(Modifier.padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(banner.first, Modifier.weight(1f), fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            IconButton(onClick = banner.second) { Icon(Icons.Filled.Close, "やめる") }
                        }
                    }
                }
                // トピック（1 タップで切り替え。＋で増やす）
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(settings.topics) { t ->
                        FilterChip(selected = t == topic, onClick = { setTopic(t) }, label = { Text(t) },
                            leadingIcon = if (t == DIARY) ({ Icon(Icons.Filled.Book, null, Modifier.size(16.dp)) }) else null)
                    }
                    item { AssistChip(onClick = { addTopicOpen = true }, label = { Text("＋ トピック") }) }
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
                    IconButton(onClick = { pickImage.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                        Icon(Icons.Filled.Image, "画像を付ける")
                    }
                    OutlinedTextField(
                        value = input, onValueChange = { input = it },
                        modifier = Modifier.weight(1f).focusRequester(focus),
                        placeholder = { Text(if (prompt) "今まで何してた？" else if (topic == DIARY) "日記（時刻は自動で付きます）" else "$topic に書く") },
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
        val shown = entries.sortedByDescending { it.created }
        LazyColumn(Modifier.fillMaxSize().padding(pad), state = listState, reverseLayout = true,
            contentPadding = PaddingValues(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            shown.forEachIndexed { i, e ->
                item(key = e.id) {
                    Bubble(e, byId, store, selecting = contextFor != null && contextFor != e.id,
                        onTap = {
                            val cf = contextFor
                            if (cf != null && cf != e.id) {
                                val k = entries.indexOfFirst { it.id == cf }
                                if (k >= 0 && e.id !in entries[k].contexts) {
                                    entries[k] = entries[k].copy(contexts = entries[k].contexts + e.id, exported = false); persist()
                                }
                                contextFor = null
                            }
                        },
                        onLong = { sheetFor = e.id })
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
            if (entries.isEmpty()) item {
                Text("ここに書いたものは 1 件ずつ Gnosis のノートになります。\n「日記」で書くと、その日の日記に時刻つきで入ります。\n長押しで「続けて書く（Branch）」「文脈につなぐ」などができます。",
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
                    add(Triple(Icons.Filled.Link, "文脈につなぐ\n（相手をタップ）") { contextFor = target.id; replyTo = null })
                    add(Triple(Icons.Filled.Edit, "書き直す") { editing = target.id; input = target.text })
                    add(Triple(Icons.Filled.Label, "トピックを変える") { topicDialogFor = target.id })
                    add(Triple(Icons.Filled.ContentCopy, "コピー") {
                        ctx.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("memo", target.text))
                    })
                    if (target.parent != null) add(Triple(Icons.Filled.LinkOff, "親から外す") {
                        val k = entries.indexOfFirst { it.id == target.id }
                        if (k >= 0) { entries[k] = entries[k].copy(parent = null, exported = false); persist() }
                    })
                    if (target.contexts.isNotEmpty()) add(Triple(Icons.Filled.LinkOff, "文脈を外す") {
                        val k = entries.indexOfFirst { it.id == target.id }
                        if (k >= 0) { entries[k] = entries[k].copy(contexts = emptyList(), exported = false); persist() }
                    })
                    add(Triple(Icons.Filled.Delete, "消す") { deleteFor = target.id })
                }
                acts.chunked(2).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(bottom = 10.dp)) {
                        row.forEach { (icon, label, act) ->
                            OutlinedButton(onClick = { act(); sheetFor = null; scope.launch { delay(100); focus.requestFocus() } },
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
                Column { settings.topics.forEach { t ->
                    TextButton(onClick = {
                        val k = entries.indexOfFirst { it.id == id }
                        if (k >= 0) { entries[k] = entries[k].copy(topic = t, exported = false); persist() }
                        topicDialogFor = null
                    }) { Text(t, fontSize = 18.sp) }
                } }
            })
    }

    if (addTopicOpen) {
        var name by remember { mutableStateOf("") }
        AlertDialog(onDismissRequest = { addTopicOpen = false },
            title = { Text("トピックを足す") },
            text = { OutlinedTextField(name, { name = it }, singleLine = true, placeholder = { Text("例: アイデア") }) },
            confirmButton = { TextButton(onClick = {
                val t = name.trim()
                if (t.isNotEmpty() && t !in settings.topics) { settings = settings.copy(topics = settings.topics + t); store.saveSettings(settings) }
                if (t.isNotEmpty()) setTopic(t)
                addTopicOpen = false
            }) { Text("足す") } },
            dismissButton = { TextButton(onClick = { addTopicOpen = false }) { Text("やめる") } })
    }

    deleteFor?.let { id ->
        AlertDialog(onDismissRequest = { deleteFor = null }, title = { Text("消しますか？") },
            text = { Text(short(byId[id]?.text ?: "", 80)) },
            confirmButton = { TextButton(onClick = {
                entries.removeAll { it.id == id }
                for (k in entries.indices) {
                    val e = entries[k]
                    if (e.parent == id || id in e.contexts) entries[k] = e.copy(parent = e.parent.takeIf { it != id }, contexts = e.contexts - id)
                }
                persist(); deleteFor = null
            }) { Text("消す") } },
            dismissButton = { TextButton(onClick = { deleteFor = null }) { Text("やめる") } })
    }

    if (exportOpen) {
        val fresh = entries.filter { !it.exported }
        AlertDialog(onDismissRequest = { if (!exporting) exportOpen = false },
            title = { Text("PC へ書き出す") },
            text = { Text(if (exporting) "書き出しています…" else
                "鍵付きの .7z を作り、パスワードをクリップボードに入れます。\nダウンロード/Gnosis にも置くので、USB でつないで PC から取れます。\n\nまだ書き出していないもの: ${fresh.size} 件") },
            confirmButton = { TextButton(enabled = !exporting && fresh.isNotEmpty(), onClick = {
                exporting = true
                scope.launch {
                    // 関係の相手（親・文脈）が前に書き出し済みでも、取り込み側が探せるよう一緒に入れる
                    val ids = fresh.flatMap { listOfNotNull(it.parent) + it.contexts }.toSet()
                    val list = fresh + entries.filter { it.exported && it.id in ids }
                    val r = withContext(Dispatchers.IO) { runCatching { Exporter.export(ctx, store, list) } }
                    exporting = false; exportOpen = false
                    r.onSuccess { res ->
                        val clip = ClipData.newPlainText("password", res.password)
                        if (Build.VERSION.SDK_INT >= 33) clip.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
                        ctx.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
                        for (k in entries.indices) if (!entries[k].exported) entries[k] = entries[k].copy(exported = true)
                        persist(); exportResult = res
                    }
                }
            }) { Text("書き出す") } },
            dismissButton = { TextButton(enabled = !exporting, onClick = { exportOpen = false }) { Text("やめる") } })
    }

    exportResult?.let { res ->
        AlertDialog(onDismissRequest = { exportResult = null },
            title = { Text("書き出しました（${res.count} 件）") },
            text = { Column {
                Text("パスワード（クリップボードに入れました）:")
                Text(res.password, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 8.dp))
                Text(res.savedTo?.let { "置き場所: $it" } ?: "ダウンロードには置けませんでした。「送る」で PC へ送ってください。")
                Text("PC の Gnosis で :GnosisCaptureImport を実行し、このパスワードを貼り付けます。", fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
            } },
            confirmButton = { TextButton(onClick = {
                val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".files", res.file)
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "application/octet-stream"; putExtra(Intent.EXTRA_STREAM, uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                ctx.startActivity(Intent.createChooser(send, "PC へ送る"))
            }) { Text("送る") } },
            dismissButton = { TextButton(onClick = { exportResult = null }) { Text("閉じる") } })
    }

    if (settingsOpen) {
        var on by remember { mutableStateOf(settings.alarmOn) }
        var minutes by remember { mutableStateOf(settings.alarmMinutes.toString()) }
        var from by remember { mutableStateOf(settings.fromHour.toString()) }
        var to by remember { mutableStateOf(settings.toHour.toString()) }
        var cleanAsk by remember { mutableStateOf(false) }
        AlertDialog(onDismissRequest = { settingsOpen = false }, title = { Text("アラームと設定") },
            text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("定期的に鳴らす", Modifier.weight(1f)); Switch(on, { on = it })
                }
                OutlinedTextField(minutes, { minutes = it.filter(Char::isDigit) }, label = { Text("何分おき") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(from, { from = it.filter(Char::isDigit) }, label = { Text("何時から") }, singleLine = true,
                        modifier = Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                    OutlinedTextField(to, { to = it.filter(Char::isDigit) }, label = { Text("何時まで") }, singleLine = true,
                        modifier = Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
                Text("鳴ったら通知を押すと「今まで何してた？」が日記で開きます。", fontSize = 13.sp)
                HorizontalDivider()
                TextButton(onClick = { cleanAsk = true }) { Text("書き出し済みのメモをスマホから消す") }
                if (cleanAsk) Text("PC に取り込んだのを確かめてから消してください。もう一度押すと消します。", fontSize = 13.sp)
            } },
            confirmButton = { TextButton(onClick = {
                settings = settings.copy(alarmOn = on, alarmMinutes = (minutes.toIntOrNull() ?: 60).coerceIn(1, 24 * 60),
                    fromHour = (from.toIntOrNull() ?: 9).coerceIn(0, 23), toHour = (to.toIntOrNull() ?: 23).coerceIn(0, 24))
                store.saveSettings(settings)
                if (on && Build.VERSION.SDK_INT >= 33) askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
                Alarm.ensureChannel(ctx); Alarm.schedule(ctx, settings)
                settingsOpen = false
            }) { Text("保存") } },
            dismissButton = { TextButton(onClick = {
                if (cleanAsk) {
                    val gone = entries.filter { it.exported }.map { it.id }.toSet()
                    entries.filter { it.id in gone }.flatMap { it.images }.forEach { File(store.imageDir, it).delete() }
                    entries.removeAll { it.id in gone }
                    for (k in entries.indices) {
                        val e = entries[k]
                        if (e.parent in gone || e.contexts.any { it in gone }) entries[k] = e.copy(parent = e.parent.takeIf { it !in gone }, contexts = e.contexts.filter { it !in gone })
                    }
                    persist(); settingsOpen = false
                } else settingsOpen = false
            }) { Text(if (cleanAsk) "消す" else "閉じる") } })
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Bubble(e: Entry, byId: Map<String, Entry>, store: Store, selecting: Boolean, onTap: () -> Unit, onLong: () -> Unit) {
    val diary = e.topic == DIARY
    val colors = if (diary) CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
    else CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Card(colors = colors, shape = RoundedCornerShape(14.dp),
            border = if (selecting) CardDefaults.outlinedCardBorder() else null,
            modifier = Modifier.widthIn(max = 340.dp).combinedClickable(onClick = onTap, onLongClick = onLong)) {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                e.parent?.let { p ->
                    Text("↳ ${short(byId[p]?.text ?: "（書き出し済み）")} の続き", fontSize = 12.sp, color = MaterialTheme.colorScheme.primary)
                }
                if (e.contexts.isNotEmpty()) {
                    Text("文脈: " + e.contexts.joinToString("、") { short(byId[it]?.text ?: "（書き出し済み）", 12) },
                        fontSize = 12.sp, color = MaterialTheme.colorScheme.tertiary)
                }
                e.images.forEach { name ->
                    AsyncImage(File(store.imageDir, name), null, Modifier.padding(vertical = 4.dp).heightIn(max = 220.dp).fillMaxWidth(),
                        contentScale = ContentScale.Fit)
                }
                if (e.text.isNotEmpty()) Text(e.text, fontSize = 16.sp)
                Row(Modifier.align(Alignment.End), verticalAlignment = Alignment.CenterVertically) {
                    Text(e.topic, fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
                    Spacer(Modifier.width(6.dp))
                    Text(timeFmt.format(Date(e.created)) + if (e.edited > 0) "（編集）" else "", fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
                    if (e.exported) { Spacer(Modifier.width(4.dp)); Icon(Icons.Filled.DoneAll, "書き出し済み", Modifier.size(14.dp), tint = MaterialTheme.colorScheme.outline) }
                }
            }
        }
    }
}
