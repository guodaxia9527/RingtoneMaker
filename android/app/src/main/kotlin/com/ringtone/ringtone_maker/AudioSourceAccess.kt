package com.ringtone.ringtone_maker

import android.content.Context
import android.media.MediaExtractor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.security.MessageDigest

/** Keep the provider URI, instead of copying every import to a new timestamped path. */
object AudioSourceAccess {
    fun open(extractor: MediaExtractor, context: Context, path: String) {
        if (path.startsWith("content://")) extractor.setDataSource(context, Uri.parse(path), null)
        else extractor.setDataSource(path)
    }

    fun hash(text: String): String = MessageDigest.getInstance("SHA-256")
        .digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

    fun describe(context: Context, path: String): Map<String, Any> {
        if (!path.startsWith("content://")) {
            val file = File(path)
            return mapOf("path" to path, "name" to file.name, "size" to file.length(),
                "modified" to file.lastModified(), "mime" to "")
        }
        val uri = Uri.parse(path)
        var name = "音频"
        var size = -1L
        var modified = 0L
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                fun number(column: String): Long {
                    val i = cursor.getColumnIndex(column)
                    return if (i >= 0 && !cursor.isNull(i)) cursor.getLong(i) else 0L
                }
                val i = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (i >= 0 && !cursor.isNull(i)) name = cursor.getString(i)
                size = number(OpenableColumns.SIZE)
                modified = number(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                if (modified == 0L) modified = number("date_modified") * 1000
            }
        }
        return mapOf("path" to path, "name" to name, "size" to size,
            "modified" to modified, "mime" to (context.contentResolver.getType(uri) ?: ""))
    }

    fun fingerprint(context: Context, path: String, cancelled: () -> Boolean): String {
        val info = describe(context, path)
        if ((info["modified"] as Long) > 0 && (info["size"] as Long) > 0) {
            return hash("$path:${info["size"]}:${info["modified"]}")
        }
        // Providers without trustworthy modification metadata must be verified
        // by content, otherwise replacing a file can reuse a stale waveform.
        val digest = MessageDigest.getInstance("SHA-256")
        val stream = if (path.startsWith("content://"))
            context.contentResolver.openInputStream(Uri.parse(path)) ?: error("无法读取文件")
            else File(path).inputStream()
        stream.use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                if (cancelled() || Thread.currentThread().isInterrupted) throw InterruptedException("操作已取消")
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun prepare(context: Context, uri: Uri): Map<String, Any> {
        val info = describe(context, uri.toString()).toMutableMap()
        val seekable = runCatching {
            context.contentResolver.openFileDescriptor(uri, "r")!!.use {
                Os.lseek(it.fileDescriptor, 0, OsConstants.SEEK_CUR)
            }
        }.isSuccess
        if (!seekable) {
            // A pipe/cloud stream cannot be sought by the decoder or player.
            // Materialize it once, atomically, under its content fingerprint.
            val temp = File.createTempFile("source_", ".tmp", context.cacheDir)
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                context.contentResolver.openInputStream(uri)!!.use { input ->
                    temp.outputStream().buffered().use { output ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            digest.update(buffer, 0, n)
                            output.write(buffer, 0, n)
                        }
                    }
                }
                val key = digest.digest().joinToString("") { "%02x".format(it) }
                val target = File(context.cacheDir, "source_$key.audio")
                check(target.exists() || temp.renameTo(target)) { "无法缓存音频" }
                info["path"] = target.absolutePath
            } finally { temp.delete() }
        }
        return info
    }
}
