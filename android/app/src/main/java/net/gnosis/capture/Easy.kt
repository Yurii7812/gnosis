package net.gnosis.capture

import android.Manifest
import android.net.Uri
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/*
 * 「らくらく」画面（アプリを開いて最初に出る）。
 *   文字は大きく（本文 24sp 以上・ボタンの文字 22sp 以上）、ボタンは高さ 72dp 以上で文字つき。
 *   長押し・スワイプ・︙メニューは使わない。1 画面に 1 つのことだけ。取り返しのつかない操作（消す）は、大きな 2 つのボタンで確かめる。
 *   ふだん使わない操作（統合・移動・トピック・Folgezettel の木・つながりの編集など）は「くわしい操作」の画面から、
 *   いままでの画面（CaptureScreen）を大きな文字で開く。
 */

/** 高コントラストの配色（背景と文字の差を大きく取る）。 */
val EasyColors = darkColorScheme(
    primary = Color(0xFF8CC8FF), onPrimary = Color(0xFF00162B),
    primaryContainer = Color(0xFF1F5FA8), onPrimaryContainer = Color(0xFFFFFFFF),
    secondary = Color(0xFFFFD27A), onSecondary = Color(0xFF241A00),
    secondaryContainer = Color(0xFF6B5410), onSecondaryContainer = Color(0xFFFFFFFF),
    tertiary = Color(0xFFA6E3A1), onTertiary = Color(0xFF062008),
    tertiaryContainer = Color(0xFF1F6B2E), onTertiaryContainer = Color(0xFFFFFFFF),
    background = Color(0xFF0B0F14), onBackground = Color(0xFFFFFFFF),
    surface = Color(0xFF0B0F14), onSurface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFF1E2630), onSurfaceVariant = Color(0xFFF0F4F8),
    surfaceContainerLowest = Color(0xFF05080B), surfaceContainerLow = Color(0xFF121820),
    surfaceContainer = Color(0xFF18202A), surfaceContainerHigh = Color(0xFF1E2630),
    surfaceContainerHighest = Color(0xFF26303C),
    error = Color(0xFFFF8A80), onError = Color(0xFF330000),
    errorContainer = Color(0xFFB3261E), onErrorContainer = Color(0xFFFFFFFF),
    outline = Color(0xFFC3CED9), outlineVariant = Color(0xFF55616E),
)

private val EASY_BUTTON_HEIGHT = 80.dp
private val easyTime = SimpleDateFormat("M月d日（E） HH:mm", Locale.JAPAN)

/** 大きなボタン。文字つき・高さ 80dp・文字 24sp。 */
@Composable
fun BigButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null,
              container: Color = MaterialTheme.colorScheme.primaryContainer, content: Color = Color.White, enabled: Boolean = true) {
    Button(onClick = onClick, enabled = enabled, modifier = modifier.fillMaxWidth().heightIn(min = EASY_BUTTON_HEIGHT),
        shape = RoundedCornerShape(20.dp),
        colors = ButtonDefaults.buttonColors(containerColor = container, contentColor = content,
            disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant, disabledContentColor = MaterialTheme.colorScheme.outline)) {
        if (icon != null) { Icon(icon, null, Modifier.size(36.dp)); Spacer(Modifier.width(14.dp)) }
        Text(label, fontSize = 24.sp, fontWeight = FontWeight.Bold)
    }
}

/** 画面の見出し（大きな文字）と、いちばん上の「もどる」。 */
@Composable
private fun EasyScaffold(title: String, onBack: (() -> Unit)?, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding().navigationBarsPadding()
        .padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (onBack != null) BigButton("← もどる", onBack, container = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.heightIn(min = 72.dp))
        Text(title, fontSize = 30.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground)
        content()
    }
}

/** 2 つの大きなボタンで確かめる画面。取り返しのつかない操作に使う。 */
@Composable
private fun EasyConfirm(title: String, message: String, yes: String, no: String, danger: Boolean, onYes: () -> Unit, onNo: () -> Unit) {
    EasyScaffold(title, null) {
        Text(message, fontSize = 24.sp, color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()))
        BigButton(no, onNo, container = MaterialTheme.colorScheme.primaryContainer)
        BigButton(yes, onYes, container = if (danger) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.tertiaryContainer)
    }
}

/** 本文の最初の行を、一覧に出す短さに。 */
private fun headline(text: String, n: Int = 60): String = short(text, n)

/** 選んだメモを消す（画像のファイルも）。ほかのメモの親・文脈から外す。MainActivity の deleteEntries と同じ。 */
fun removeEntries(list: MutableList<Entry>, ids: Set<String>, store: Store) {
    list.filter { it.id in ids }.flatMap { it.images }.forEach { File(store.imageDir, it).delete() }
    list.removeAll { it.id in ids }
    for (k in list.indices) {
        val e = list[k]
        if (e.parent in ids || e.contexts.any { it in ids })
            list[k] = e.copy(parent = e.parent.takeIf { it !in ids }, contexts = e.contexts.filter { it !in ids }, exported = false)
    }
}

/** アプリの入口。ホームと、らくらくの各画面、くわしい操作の画面を切り替える。 */
@Composable
fun EasyApp(store: Store, promptState: MutableState<Boolean>) {
    val ctx = LocalContext.current
    var screen by rememberSaveable { mutableStateOf("home") }
    var openId by rememberSaveable { mutableStateOf("") }
    var flash by remember { mutableStateOf("") }
    val entries = remember { mutableStateListOf<Entry>().apply { addAll(store.load()) } }
    fun reload() { entries.clear(); entries.addAll(store.load()) }
    fun go(s: String) { if (s == "home") reload(); screen = s }
    val prompt by promptState
    // アラームの通知から開いたら、日記を書く画面へ
    LaunchedEffect(prompt) { if (prompt) { openId = ""; screen = "diary" } }
    LaunchedEffect(flash) { if (flash.isNotEmpty()) { delay(3500); flash = "" } }
    BackHandler(enabled = screen != "home" && !screen.startsWith("classic:")) { go("home") }

    when {
        screen == "home" -> HomeScreen(store, entries, flash, ::go)
        screen == "write" || screen == "diary" -> WriteScreen(store, entries, diary = screen == "diary" || prompt,
            onDone = { msg -> promptState.value = false; flash = msg; go("home") }, onCancel = { promptState.value = false; go("home") })
        screen == "read" -> ReadScreen(entries, onOpen = { openId = it; screen = "detail" }, onBack = { go("home") })
        screen == "detail" -> {
            val e = entries.firstOrNull { it.id == openId }
            if (e == null) go("read") else DetailScreen(e, store, onBack = { go("read") }, onDelete = { screen = "delete" })
        }
        screen == "delete" -> {
            val e = entries.firstOrNull { it.id == openId }
            if (e == null) go("read") else EasyConfirm("このメモを消しますか？", headline(e.text, 120) + "\n\n消すと元に戻せません。",
                yes = "消す", no = "やめる（消さない）", danger = true,
                onYes = { removeEntries(entries, setOf(e.id), store); store.save(entries.toList()); flash = "消しました"; go("read") },
                onNo = { screen = "detail" })
        }
        screen == "scan" -> {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, d.fontScale * 1.2f)) { ScanScreen(onClose = { go("home") }) }
        }
        screen == "alarm" -> AlarmScreen(store, onMore = { screen = "classic:settings" }, onBack = { go("home") })
        screen == "more" -> MoreScreen(onOpen = { screen = "classic:$it" }, onBack = { go("home") })
        screen.startsWith("classic:") -> {
            val d = LocalDensity.current
            BackHandler { go("more") }
            CompositionLocalProvider(LocalDensity provides Density(d.density, d.fontScale * 1.25f)) {
                CaptureScreen(store, promptState, start = screen.removePrefix("classic:"), onHome = { go("home") })
            }
        }
        else -> go("home")
    }
}

@Composable
private fun HomeScreen(store: Store, entries: List<Entry>, flash: String, go: (String) -> Unit) {
    val ctx = LocalContext.current
    val imported = remember(entries.size) { store.importedIds() }
    val pending = entries.count { it.id !in imported }
    val settings = remember(entries.size) { store.loadSettings() }
    val next = remember(entries.size) { Alarm.scheduledTime(ctx) }
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding().navigationBarsPadding()
        .padding(horizontal = 16.dp, vertical = 12.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("メモ", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground)
        Text(if (flash.isNotEmpty()) "✓ $flash" else if (pending == 0) "パソコンに送っていないメモはありません" else "パソコンに送っていないメモ: $pending 件",
            fontSize = 22.sp, color = if (flash.isNotEmpty()) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onBackground, fontWeight = FontWeight.Medium)
        BigButton("メモを書く", { go("write") }, icon = Icons.Filled.Edit, container = Color(0xFF1F5FA8))
        BigButton("メモを見る（${entries.size} 件）", { go("read") }, icon = Icons.Filled.Notes, container = Color(0xFF6B5410))
        BigButton("紙を撮る", { go("scan") }, icon = Icons.Filled.CameraAlt, container = Color(0xFF1F6B2E))
        BigButton(if (settings.alarmOn) "予定・アラーム（オン）" else "予定・アラーム（オフ）", { go("alarm") }, icon = Icons.Filled.Alarm, container = Color(0xFF7A3B8C))
        if (settings.alarmOn && next > 0) Text("次のアラーム: " + SimpleDateFormat("M月d日 HH:mm", Locale.JAPAN).format(Date(next)), fontSize = 20.sp, color = MaterialTheme.colorScheme.outline)
        Spacer(Modifier.height(8.dp))
        BigButton("くわしい操作", { go("more") }, icon = Icons.Filled.Settings, container = MaterialTheme.colorScheme.surfaceVariant)
    }
}

@Composable
private fun WriteScreen(store: Store, entries: MutableList<Entry>, diary: Boolean, onDone: (String) -> Unit, onCancel: () -> Unit) {
    val ctx = LocalContext.current
    var text by rememberSaveable { mutableStateOf("") }
    val images = remember { mutableStateListOf<String>() }
    var askDiscard by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { delay(200); try { focus.requestFocus() } catch (_: IllegalStateException) {} }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        if (uri != null) {
            val name = "img-" + System.currentTimeMillis() + ".jpg"
            ctx.contentResolver.openInputStream(uri)?.use { i -> File(store.imageDir, name).outputStream().use { i.copyTo(it) } }
            images.add(name)
        }
    }
    fun save(asDiary: Boolean) {
        val t = text.trim()
        if (t.isEmpty() && images.isEmpty()) return
        val now = System.currentTimeMillis()
        entries.add(Entry(id = Store.newId(now, entries), created = now, topic = if (asDiary) DIARY else UNASSIGNED, text = t, images = images.toList()))
        store.save(entries.toList())
        onDone(if (asDiary) "日記に保存しました" else "保存しました")
    }
    fun cancel() { if (text.isNotBlank() || images.isNotEmpty()) askDiscard = true else onCancel() }
    BackHandler { cancel() }
    if (askDiscard) {
        EasyConfirm("書いたものを捨てますか？", "まだ保存していません。", yes = "捨てる", no = "続けて書く", danger = true,
            onYes = { onCancel() }, onNo = { askDiscard = false })
        return
    }
    EasyScaffold(if (diary) "今まで何してた？（日記）" else "メモを書く", onBack = { cancel() }) {
        OutlinedTextField(text, { text = it }, modifier = Modifier.fillMaxWidth().weight(1f).focusRequester(focus),
            textStyle = TextStyle(fontSize = 26.sp, lineHeight = 36.sp), placeholder = { Text("ここに書く", fontSize = 24.sp) },
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, keyboardType = KeyboardType.Text),
            shape = RoundedCornerShape(16.dp))
        if (images.isNotEmpty()) Text("写真 ${images.size} 枚つけました", fontSize = 22.sp, color = MaterialTheme.colorScheme.tertiary)
        BigButton("写真をつける", { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            icon = Icons.Filled.Image, container = MaterialTheme.colorScheme.surfaceVariant)
        if (diary) BigButton("日記に保存する", { save(true) }, icon = Icons.Filled.Check, container = Color(0xFF1F6B2E), enabled = text.isNotBlank() || images.isNotEmpty())
        else {
            BigButton("保存する", { save(false) }, icon = Icons.Filled.Check, container = Color(0xFF1F6B2E), enabled = text.isNotBlank() || images.isNotEmpty())
            BigButton("日記として保存する", { save(true) }, icon = Icons.Filled.Book, container = MaterialTheme.colorScheme.primaryContainer, enabled = text.isNotBlank() || images.isNotEmpty())
        }
    }
}

@Composable
private fun ReadScreen(entries: List<Entry>, onOpen: (String) -> Unit, onBack: () -> Unit) {
    val list = remember(entries.toList()) { entries.sortedByDescending { it.created } }
    EasyScaffold("メモを見る", onBack) {
        if (list.isEmpty()) Text("まだメモがありません。", fontSize = 24.sp, color = MaterialTheme.colorScheme.onBackground)
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(list, key = { it.id }) { e ->
                Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth().heightIn(min = 88.dp).clickable { onOpen(e.id) }) {
                    Column(Modifier.padding(16.dp)) {
                        Text(easyTime.format(Date(e.created)) + if (e.topic == DIARY) "　日記" else "", fontSize = 20.sp, color = MaterialTheme.colorScheme.outline)
                        Text(if (e.text.isBlank()) "（写真）" else e.text, fontSize = 24.sp, maxLines = 3, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurface)
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailScreen(e: Entry, store: Store, onBack: () -> Unit, onDelete: () -> Unit) {
    EasyScaffold(easyTime.format(Date(e.created)), onBack) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            e.images.forEach { name ->
                AsyncImage(File(store.imageDir, name), null, Modifier.fillMaxWidth().heightIn(max = 420.dp), contentScale = ContentScale.Fit)
            }
            Text(e.text.ifBlank { "（本文なし）" }, fontSize = 26.sp, lineHeight = 38.sp, color = MaterialTheme.colorScheme.onBackground)
        }
        BigButton("このメモを消す", onDelete, icon = Icons.Filled.Delete, container = MaterialTheme.colorScheme.errorContainer)
    }
}

@Composable
private fun AlarmScreen(store: Store, onMore: () -> Unit, onBack: () -> Unit) {
    val ctx = LocalContext.current
    var settings by remember { mutableStateOf(store.loadSettings()) }
    var next by remember { mutableStateOf(Alarm.scheduledTime(ctx)) }
    var needNotify by remember { mutableStateOf(!Alarm.notificationsEnabled(ctx)) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { needNotify = !Alarm.notificationsEnabled(ctx) }
    fun apply(s: Settings) {
        settings = s; store.saveSettings(s)
        if (s.alarmOn && Build.VERSION.SDK_INT >= 33 && !Alarm.hasNotificationPermission(ctx)) ask.launch(Manifest.permission.POST_NOTIFICATIONS)
        Alarm.ensureChannel(ctx); Alarm.schedule(ctx, s)
        next = Alarm.scheduledTime(ctx)
    }
    EasyScaffold("予定・アラーム", onBack) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(if (settings.alarmOn) "アラームは「オン」です" else "アラームは「オフ」です", fontSize = 28.sp, fontWeight = FontWeight.Bold,
                color = if (settings.alarmOn) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onBackground)
            if (settings.alarmOn && next > 0) Text("次: " + SimpleDateFormat("M月d日 HH:mm", Locale.JAPAN).format(Date(next)), fontSize = 24.sp, color = MaterialTheme.colorScheme.onBackground)
            if (settings.alarmOn) Text("${settings.fromHour} 時から ${if (settings.toHour == 24) "24" else settings.toHour.toString()} 時まで、${if (settings.alarmMinutes % 60 == 0) "${settings.alarmMinutes / 60} 時間" else "${settings.alarmMinutes} 分"}おきに鳴ります。",
                fontSize = 22.sp, color = MaterialTheme.colorScheme.outline)
            if (needNotify) Text("通知が許可されていません。鳴らすには、スマホの設定で許可してください。", fontSize = 22.sp, color = MaterialTheme.colorScheme.error)
            BigButton(if (settings.alarmOn) "アラームをオフにする" else "アラームをオンにする", { apply(settings.copy(alarmOn = !settings.alarmOn)) },
                icon = Icons.Filled.Alarm, container = if (settings.alarmOn) MaterialTheme.colorScheme.errorContainer else Color(0xFF1F6B2E))
            Text("鳴らす間隔", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground)
            listOf(30 to "30 分おき", 60 to "1 時間おき", 120 to "2 時間おき").forEach { (m, label) ->
                val on = settings.alarmMinutes == m
                BigButton(if (on) "✓ $label" else label, { apply(settings.copy(alarmMinutes = m)) },
                    container = if (on) Color(0xFF1F5FA8) else MaterialTheme.colorScheme.surfaceVariant)
            }
            BigButton("くわしい設定", onMore, icon = Icons.Filled.Settings, container = MaterialTheme.colorScheme.surfaceVariant)
        }
    }
}

@Composable
private fun MoreScreen(onOpen: (String) -> Unit, onBack: () -> Unit) {
    EasyScaffold("くわしい操作", onBack) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("ふだん使わない操作です。ここから先は、いままでの画面が大きな文字で開きます。", fontSize = 22.sp, color = MaterialTheme.colorScheme.outline)
            BigButton("まとめて選ぶ\n（統合・移動・消す）", { onOpen("select") }, icon = Icons.Filled.Checklist)
            BigButton("トピックを選ぶ・作る", { onOpen("topics") }, icon = Icons.Filled.Label)
            BigButton("つながりの木を見る", { onOpen("folge") }, icon = Icons.Filled.AccountTree)
            BigButton("メモを探す", { onOpen("search") }, icon = Icons.Filled.Search)
            BigButton("アラームのくわしい設定", { onOpen("settings") }, icon = Icons.Filled.Alarm)
            BigButton("すべての操作（くわしい画面）", { onOpen("") }, icon = Icons.Filled.Settings, container = MaterialTheme.colorScheme.surfaceVariant)
        }
    }
}
