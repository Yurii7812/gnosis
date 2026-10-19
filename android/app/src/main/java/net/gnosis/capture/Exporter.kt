package net.gnosis.capture

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import net.lingala.zip4j.ZipFile
import org.apache.commons.compress.archivers.sevenz.SevenZOutputFile
import net.lingala.zip4j.model.ZipParameters
import net.lingala.zip4j.model.enums.AesKeyStrength
import net.lingala.zip4j.model.enums.EncryptionMethod
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 書き出し: capture.json（書いたもの全部の中身と関係）と images/ を、鍵付きの .7z（AES-256）にする。
 * .7z が作れなかったときだけ、鍵付きの zip（AES-256）にする。どちらも 7-Zip と Gnosis の
 * :GnosisCaptureImport で開ける。パスワードは毎回作り、呼び出し側がクリップボードへ入れる。
 */
object Exporter {
    data class Result(val file: File, val password: String, val count: Int, val savedTo: String?)

    private const val PW_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"

    fun newPassword(): String {
        val r = SecureRandom()
        return (1..16).map { PW_CHARS[r.nextInt(PW_CHARS.length)] }.joinToString("")
    }

    /** a:entries … 書き出すもの。関係の相手が書き出しに含まれないときも、id だけは書く（取り込み側が前回分から探す）。 */
    fun export(ctx: Context, store: Store, entries: List<Entry>): Result {
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val work = File(ctx.cacheDir, "export-$stamp").apply { deleteRecursively(); mkdirs() }
        val json = JSONObject()
        json.put("format", "gnosis-capture")
        json.put("version", 1)
        json.put("exported", System.currentTimeMillis())
        json.put("entries", JSONArray().apply { entries.forEach { put(Store.toJson(it)) } })
        File(work, "capture.json").writeText(json.toString(2))
        val imgOut = File(work, "images").apply { mkdirs() }
        entries.flatMap { it.images }.distinct().forEach { name ->
            val src = File(store.imageDir, name)
            if (src.exists()) src.copyTo(File(imgOut, name), overwrite = true)
        }
        val pw = newPassword()
        val out = try {
            write7z(work, File(ctx.cacheDir, "gnosis-capture-$stamp.7z"), pw)
        } catch (e: Throwable) {
            writeZip(work, imgOut, File(ctx.cacheDir, "gnosis-capture-$stamp.zip"), pw)
        }
        work.deleteRecursively()
        val saved = saveToDownloads(ctx, out)
        return Result(out, pw, entries.size, saved)
    }

    private fun write7z(work: File, out: File, pw: String): File {
        out.delete()
        SevenZOutputFile(out, pw.toCharArray()).use { z ->
            work.walkTopDown().filter { it.isFile }.forEach { f ->
                val entry = z.createArchiveEntry(f, f.relativeTo(work).path)
                z.putArchiveEntry(entry)
                f.inputStream().use { input ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        z.write(buf, 0, n)
                    }
                }
                z.closeArchiveEntry()
            }
        }
        return out
    }

    private fun writeZip(work: File, imgOut: File, out: File, pw: String): File {
        out.delete()
        val params = ZipParameters().apply {
            isEncryptFiles = true
            encryptionMethod = EncryptionMethod.AES
            aesKeyStrength = AesKeyStrength.KEY_STRENGTH_256
        }
        val zip = ZipFile(out, pw.toCharArray())
        zip.addFile(File(work, "capture.json"), params)
        if (imgOut.listFiles()?.isNotEmpty() == true) zip.addFolder(imgOut, params)
        zip.close()
        return out
    }

    /** ダウンロード/Gnosis に同じものを置く（USB でつないで PC から取れるように）。 */
    private fun saveToDownloads(ctx: Context, f: File): String? {
        return try {
            if (Build.VERSION.SDK_INT >= 29) {
                val v = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, f.name)
                    put(MediaStore.Downloads.MIME_TYPE, if (f.name.endsWith(".7z")) "application/x-7z-compressed" else "application/zip")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Gnosis")
                }
                val uri = ctx.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v) ?: return null
                ctx.contentResolver.openOutputStream(uri)?.use { o -> f.inputStream().use { it.copyTo(o) } }
                "Download/Gnosis/${f.name}"
            } else {
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Gnosis").apply { mkdirs() }
                f.copyTo(File(dir, f.name), overwrite = true)
                "Download/Gnosis/${f.name}"
            }
        } catch (e: Exception) {
            null
        }
    }
}
