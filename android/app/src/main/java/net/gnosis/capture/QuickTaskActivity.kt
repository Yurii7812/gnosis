package net.gnosis.capture

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.LocalDate

/**
 * クイックタスク追加（ウィジェットの「＋ タスク」・予定の画面から）。`- [ ] 本文 📅 日付` の 1 行を、このアプリのメモとして保存する。
 * PC の \M で取り込むと、そのノートのタスクとして Agenda に出る（スマホでノートを直接は書かない）。
 */
class QuickTaskActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setLayout(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.WRAP_CONTENT)   // 画面の幅いっぱいに。縦は中身の分だけ
        setContent {
            MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxWidth()) {
                    var text by remember { mutableStateOf("") }
                    var spec by remember { mutableStateOf(TaskSpec()) }
                    Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("タスクを足す", style = MaterialTheme.typography.titleLarge)
                        OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("やること") }, modifier = Modifier.fillMaxWidth())
                        TaskEditor(spec) { spec = it }
                        Button(onClick = {
                            val line = Agenda.taskLine(text, spec)
                            if (line == null) { Toast.makeText(this@QuickTaskActivity, "やることを入れてください", Toast.LENGTH_SHORT).show() }
                            else try {
                                val store = Store(this@QuickTaskActivity)
                                val es = store.load()
                                val now = System.currentTimeMillis()
                                store.save(es + Entry(Store.newId(now, es), now, UNASSIGNED, line))
                                Toast.makeText(this@QuickTaskActivity, "メモに保存しました（PC の \\M で取り込むとタスクになります）", Toast.LENGTH_LONG).show()
                                finish()
                            } catch (e: Exception) { Toast.makeText(this@QuickTaskActivity, "保存できませんでした", Toast.LENGTH_LONG).show() }
                        }) { Text("保存") }
                    }
                }
            }
        }
    }
}
