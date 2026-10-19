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
    var topic by remember { mutableStateOf(settings.lastTopic) }
    val topics = (settings.topics + entries.map { it.topic }).filter { it.isNotEmpty() && it != ALL }.distinct()
    val selected = remember { mutableStateListOf<String>() }
    var selecting by remember { mutableStateOf(false) }
    var moveSelectedOpen by remember { mutableStateOf(false) }
    var deleteSelectedOpen by remember { mutableStateOf(false) }
    var notificationsEnabled by remember { mutableStateOf(Alarm.notificationsEnabled(ctx)) }
    var exactEnabled by remember { mutableStateOf(Alarm.canScheduleExact(ctx)) }
    var nextAlarm by remember { mutableStateOf(Alarm.scheduledTime(ctx)) }
    var input by remember { mutableStateOf("") }
    val pendingImages = remember { mutableStateListOf<String>() }
    var replyTo by remember { mutableStateOf<String?>(null) }      // 次に書くものの Branch の親
    var contextFor by remember { mutableStateOf<String?>(null) }   // 文脈をつなぐ相手を選んでいる途中のメモ
    var editing by remember { mutableStateOf<String?>(null) }
    var sheetFor by remember { mutableStateOf<String?>(null) }
    var topicDialogFor by remember { mutableStateOf<String?>(null) }
    var addTopicOpen by remember { mutableStateOf(false) }
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
    LifecycleResumeEffect(Unit) {
        imported = store.importedIds()
        notificationsEnabled = Alarm.notificationsEnabled(ctx)
        exactEnabled = Alarm.canScheduleExact(ctx)
        Alarm.ensureScheduled(ctx, settings)
        nextAlarm = Alarm.scheduledTime(ctx)
        onPauseOrDispose { }
    }
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
    val askNotify = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        notificationsEnabled = Alarm.notificationsEnabled(ctx)
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
        val text = input
        if (text.isBlank() && pendingImages.isEmpty()) return
        val ed = editing
        if (ed != null) {
            val i = entries.indexOfFirst { it.id == ed }
            if (i >= 0) entries[i] = entries[i].copy(text = text, images = entries[i].images + pendingImages, edited = System.currentTimeMillis(), exported = false)
            editing = null
        } else {
            val now = System.currentTimeMillis()
            entries.add(Entry(id = Store.newId(now, entries), created = now, topic = writingTopic(topic), text = text,
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
                    val n = entries.count { it.id !in imported }
                    Column {
                        Text(if (selecting) "${selected.size} 件選択" else topicLabel(topic), fontWeight = FontWeight.Bold)
                        Text(if (n == 0) "すべて PC に取り込み済み" else "PC にまだ取り込んでいない: $n 件", fontSize = 12.sp)
                    }
                },
                actions = {
                    IconButton(onClick = { selecting = !selecting; selected.clear(); contextFor = null; if (selecting) keyboard?.hide() }) {
                        Icon(if (selecting) Icons.Filled.Close else Icons.Filled.Checklist, if (selecting) "選択をやめる" else "複数選択")
                    }
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
                            OutlinedButton(onClick = { moveSelectedOpen = true }, enabled = selected.isNotEmpty(), modifier = Modifier.weight(1f)) { Text("移動") }
                            OutlinedButton(onClick = { deleteSelectedOpen = true }, enabled = selected.isNotEmpty(), modifier = Modifier.weight(1f)) { Text("消す") }
                        }
                    }
                }
                // 表示と書き込み先を同時に切り替える。全部表示からは未選択で保存。
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(listOf(ALL, UNASSIGNED) + topics) { t ->
                        FilterChip(selected = t == topic, onClick = { setTopic(t) }, label = { Text(topicLabel(t)) },
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
                        placeholder = { Text(if (prompt) "今まで何してた？" else if (topic == DIARY) "日記（時刻は自動で付きます）" else if (writingTopic(topic).isEmpty()) "メモを書く（トピック未選択）" else "$topic に書く") },
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
        val shown = visibleEntries(entries, topic).sortedByDescending { it.created }
        LazyColumn(Modifier.fillMaxSize().padding(pad), state = listState, reverseLayout = true,
            contentPadding = PaddingValues(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            shown.forEachIndexed { i, e ->
                item(key = e.id) {
                    Bubble(e, e.id in imported, byId, store, selecting = contextFor != null && contextFor != e.id, selected = e.id in selected, selectionMode = selecting,
                        onTap = {
                            val cf = contextFor
                            if (selecting) toggleSelection(e.id)
                            else if (cf != null && cf != e.id) {
                                val k = entries.indexOfFirst { it.id == cf }
                                if (k >= 0 && e.id !in entries[k].contexts) {
                                    entries[k] = entries[k].copy(contexts = entries[k].contexts + e.id, exported = false); persist()
                                }
                                contextFor = null
                            }
                        },
                        onLong = { if (selecting) toggleSelection(e.id) else sheetFor = e.id })
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
                    add(Triple(Icons.Filled.Link, "文脈につなぐ\n（相手をタップ）") { contextFor = target.id; replyTo = null })
                    add(Triple(Icons.Filled.Edit, "書き直す") { editing = target.id; input = target.text })
                    add(Triple(Icons.Filled.Checklist, "複数選択") { selecting = true; selected.clear(); selected.add(target.id); contextFor = null; keyboard?.hide() })
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
                            OutlinedButton(onClick = { act(); sheetFor = null; if (!selecting) scope.launch { delay(100); focus.requestFocus() } },
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

    if (addTopicOpen) {
        var name by remember { mutableStateOf("") }
        AlertDialog(onDismissRequest = { addTopicOpen = false },
            title = { Text("トピックを足す") },
            text = { OutlinedTextField(name, { name = it }, singleLine = true, placeholder = { Text("例: アイデア") }) },
            confirmButton = { TextButton(onClick = {
                val t = normalizedTopic(name.trim()).takeUnless { it == ALL || it == "全部表示" || it == "トピック未選択" } ?: ""
                if (t.isNotEmpty() && t !in settings.topics) { settings = settings.copy(topics = settings.topics + t); store.saveSettings(settings) }
                if (t.isNotEmpty()) setTopic(t)
                addTopicOpen = false
            }) { Text("足す") } },
            dismissButton = { TextButton(onClick = { addTopicOpen = false }) { Text("やめる") } })
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
        var cleanAsk by remember { mutableStateOf(false) }
        AlertDialog(onDismissRequest = { settingsOpen = false }, title = { Text("アラームと設定") },
            text = { Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("定期的に鳴らす", Modifier.weight(1f)); Switch(on, { on = it })
                }
                OutlinedTextField(minutes, { minutes = it.filter(Char::isDigit) }, label = { Text("何分おき") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                FilterChip(selected = from == "0" && to == "24", onClick = { from = "0"; to = "24" }, label = { Text("24時間") })
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(from, { from = it.filter(Char::isDigit) }, label = { Text("何時から") }, singleLine = true,
                        modifier = Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                    OutlinedTextField(to, { to = it.filter(Char::isDigit) }, label = { Text("何時まで") }, singleLine = true,
                        modifier = Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
                Text("鳴ったら通知を押すと「今まで何してた？」が日記で開きます。", fontSize = 13.sp)
                if (from == to) Text("開始と終了が同じ場合も24時間鳴らします。", fontSize = 13.sp)
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
                TextButton(onClick = { cleanAsk = true }) { Text("PC に取り込み済みのメモをスマホから消す") }
                if (cleanAsk) Text("取り込んだ vault にメモが残っていることを確認してください。テスト用 vault だけに取り込んだ場合や、別の vault にも取り込む場合は消さないでください。取り込みだけでスマホの原本が消えることはありません。", fontSize = 13.sp)
            } },
            confirmButton = { TextButton(onClick = {
                settings = settings.copy(alarmOn = on, alarmMinutes = (minutes.toIntOrNull() ?: 60).coerceIn(1, 24 * 60),
                    fromHour = (from.toIntOrNull() ?: 9).coerceIn(0, 23), toHour = (to.toIntOrNull() ?: 23).coerceIn(0, 24))
                store.saveSettings(settings)
                if (on && Build.VERSION.SDK_INT >= 33 && !Alarm.hasNotificationPermission(ctx)) askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
                Alarm.ensureChannel(ctx); Alarm.schedule(ctx, settings)
                nextAlarm = Alarm.scheduledTime(ctx)
                settingsOpen = false
            }) { Text("保存") } },
            dismissButton = { TextButton(onClick = {
                if (cleanAsk) {
                    val gone = entries.filter { it.id in imported }.map { it.id }.toSet()
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
private fun Bubble(e: Entry, done: Boolean, byId: Map<String, Entry>, store: Store, selecting: Boolean, selected: Boolean, selectionMode: Boolean, onTap: () -> Unit, onLong: () -> Unit) {
    val diary = e.topic == DIARY
    val colors = if (selected) CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
    else if (diary) CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
    else CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Card(colors = colors, shape = RoundedCornerShape(14.dp),
            border = if (selecting) CardDefaults.outlinedCardBorder() else null,
            modifier = Modifier.widthIn(max = 340.dp).combinedClickable(onClick = onTap, onLongClick = onLong)) {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                if (selectionMode) Checkbox(checked = selected, onCheckedChange = { onTap() })
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
                    Text(topicLabel(e.topic), fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
                    Spacer(Modifier.width(6.dp))
                    Text(timeFmt.format(Date(e.created)) + if (e.edited > 0) "（編集）" else "", fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
                    if (done) { Spacer(Modifier.width(4.dp)); Icon(Icons.Filled.DoneAll, "PC に取り込み済み", Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary) }
                }
            }
        }
    }
}
