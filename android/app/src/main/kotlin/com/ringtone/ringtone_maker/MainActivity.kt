package com.ringtone.ringtone_maker

import android.Manifest
import android.content.pm.PackageManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var pendingPicker: MethodChannel.Result? = null
    private var bridge: MethodChannel? = null
    private var pendingStoragePermission: MethodChannel.Result? = null
    private val executor = Executors.newFixedThreadPool(2)
    private val analyses = ConcurrentHashMap<String, AtomicBoolean>()
    private val folder = "Download/RingtoneMaker/"
    private val legacyFolder: File
        get() = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "RingtoneMaker")
    private fun collection(): Uri = if (Build.VERSION.SDK_INT >= 29)
        MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ringtone.ringtone_maker/ringtone")
        bridge = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "appInfo" -> {
                        try {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            val buildNumber = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                            result.success(mapOf("versionName" to info.versionName, "buildNumber" to buildNumber.toString()))
                        } catch (e: Exception) {
                            result.error("APP_INFO", "无法读取版本信息", null)
                        }
                    }
                    "saveSupportQr" -> executor.execute {
                        try {
                            val bytes = call.argument<ByteArray>("bytes") ?: error("没有图片数据")
                            require(bytes.isNotEmpty() && bytes.size <= 10 * 1024 * 1024)
                            val uri = saveSupportQr(bytes)
                            runOnUiThread { result.success(uri.toString()) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SAVE_IMAGE_FAILED", "保存图片失败", null) }
                        }
                    }
                    "consumeSelectionHint" -> {
                        val preferences = getSharedPreferences("editor", MODE_PRIVATE)
                        val seen = preferences.getBoolean("selectionHintSeen", false)
                        if (!seen) preferences.edit().putBoolean("selectionHintSeen", true).apply()
                        result.success(!seen)
                    }
                    "pickSource" -> {
                        if (pendingPicker != null) result.error("PICKER", "正在选择文件", null)
                        else try {
                            pendingPicker = result
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "video/*", "application/ogg"))
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }, 702)
                        } catch (e: Exception) {
                            pendingPicker = null
                            result.error("PICKER", e.message, null)
                        }
                    }
                    "ensureStoragePermission" -> {
                        val permissions = arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE)
                        if (Build.VERSION.SDK_INT >= 29 || permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
                            result.success(true)
                        } else if (pendingStoragePermission != null) {
                            result.error("PERMISSION", "正在等待存储授权", null)
                        } else {
                            pendingStoragePermission = result
                            requestPermissions(permissions, 701)
                        }
                    }
                    "hasWriteSettingsPermission" -> result.success(Settings.System.canWrite(this))
                    "requestWriteSettingsPermission" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:$packageName")))
                            result.success(null)
                        } catch (e: Exception) { result.error("SETTINGS", e.message, null) }
                    }
                    "cancelAnalysis" -> {
                        analyses[call.argument<String>("requestId")]?.set(true)
                        result.success(null)
                    }
                    else -> {
                        val cancelled = AtomicBoolean(false)
                        val requestId = call.argument<String>("requestId")
                        if (call.method == "waveform" && requestId != null) analyses[requestId] = cancelled
                        executor.execute {
                            try {
                                val response: Any? = when (call.method) {
                                    "waveform" -> WaveformAnalyzer.analyze(this, call.argument<String>("path")!!, cancelled::get) { snapshot ->
                                        runOnUiThread {
                                            if (!cancelled.get() && bridge === channel) channel.invokeMethod("waveformProgress", snapshot + ("requestId" to (requestId ?: "")))
                                        }
                                    }
                                    "export" -> {
                                        val temp = File.createTempFile("ringtone_", ".m4a", cacheDir)
                                        try {
                                            val ranges = call.argument<List<Map<String, Number>>>("ranges")?.map {
                                                Pair(it["startUs"]!!.toLong(), it["endUs"]!!.toLong())
                                            } ?: listOf(Pair(call.argument<Number>("startUs")!!.toLong(),
                                                call.argument<Number>("endUs")!!.toLong()))
                                            AudioProcessor.export(call.argument<String>("path")!!, temp, cacheDir, ranges, (call.argument<Number>("fadeInMs") ?: 0).toInt(), (call.argument<Number>("fadeOutMs") ?: 0).toInt(), this)
                                            saveExport(temp, cleanName(call.argument<String>("fileName")!!)).toString()
                                        } finally { temp.delete() }
                                    }
                                    "preview" -> {
                                        val ranges = call.argument<List<Map<String, Number>>>("ranges")!!.map {
                                            Pair(it["startUs"]!!.toLong(), it["endUs"]!!.toLong())
                                        }
                                        require(ranges.isNotEmpty() && ranges.all { it.first >= 0 && it.second > it.first })
                                        require(ranges.sumOf { it.second - it.first } <= 3000000) { "试听片段过长" }
                                        cacheDir.listFiles { f -> f.name.startsWith("preview_") && f.extension == "m4a" }
                                            ?.filter { System.currentTimeMillis() - it.lastModified() > 3600000 }
                                            ?.forEach { it.delete() }
                                        val temp = File.createTempFile("preview_", ".m4a", cacheDir)
                                        try {
                                            AudioProcessor.export(call.argument<String>("path")!!, temp, cacheDir, ranges,
                                                (call.argument<Number>("fadeInMs") ?: 0).toInt(),
                                                (call.argument<Number>("fadeOutMs") ?: 0).toInt(), this)
                                            temp.absolutePath
                                        } catch (e: Exception) { temp.delete(); throw e }
                                    }
                                    "releasePreview" -> {
                                        val file = File(call.argument<String>("path")!!).canonicalFile
                                        require(file.parentFile == cacheDir.canonicalFile && file.name.startsWith("preview_") && file.extension == "m4a")
                                        file.delete()
                                        null
                                    }
                                    "queryRingtones" -> queryRingtones()
                                    "renameFile" -> {
                                        val uri = Uri.parse(call.argument<String>("uri")!!)
                                        val name = cleanName(call.argument<String>("fileName")!!)
                                        require(queryRingtones(false).none { it["name"] == name && it["uri"] != uri.toString() }) { "已有同名铃声" }
                                        require(contentResolver.update(uri, ContentValues().apply {
                                            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                                        }, null, null) > 0) { "重命名失败" }
                                        null
                                    }
                                    "deleteFile" -> contentResolver.delete(Uri.parse(call.argument<String>("uri")!!), null, null) > 0
                                    "shareCopy" -> shareCopy(Uri.parse(call.argument<String>("uri")!!))
                                    "setAsRingtone" -> setRingtone(Uri.parse(call.argument<String>("path")!!), call.argument<Int>("type") ?: 0)
                                    else -> throw IllegalArgumentException("未知操作：${call.method}")
                                }
                                runOnUiThread { result.success(response) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("AUDIO_ERROR", e.message ?: "音频处理失败", null) }
                            } finally {
                                if (requestId != null) analyses.remove(requestId, cancelled)
                            }
                        }
                    }
                }
            }
    }

    private fun saveSupportQr(bytes: ByteArray): Uri {
        val name = "锅大侠_赞赏码_${System.currentTimeMillis()}.png"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= 29) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/RingtoneMaker/")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            } else {
                val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "RingtoneMaker")
                check(directory.exists() || directory.mkdirs()) { "无法创建图片文件夹" }
                put(MediaStore.Images.Media.DATA, File(directory, name).absolutePath)
            }
        }
        val images = if (Build.VERSION.SDK_INT >= 29)
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val uri = contentResolver.insert(images, values) ?: error("无法创建图片")
        try {
            val output = contentResolver.openOutputStream(uri) ?: error("无法写入图片")
            output.use { it.write(bytes) }
            if (Build.VERSION.SDK_INT >= 29) {
                check(contentResolver.update(uri, ContentValues().apply {
                    put(MediaStore.Images.Media.IS_PENDING, 0)
                }, null, null) > 0) { "无法发布图片" }
            }
            return uri
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
    }

    private fun cleanName(input: String): String {
        val stem = input.trim().removeSuffix(".m4a").map {
            if (it in "\\/:*?\"<>|" || it.code < 32) '_' else it
        }.joinToString("").trim().take(60)
        require(stem.isNotEmpty() && stem != "." && stem != "..") { "请输入有效文件名" }
        return "$stem.m4a"
    }

    private fun saveExport(source: File, requested: String): Uri {
        val names = queryRingtones(false).map { it["name"] }.toSet()
        var name = requested
        var index = 1
        while (name in names) { name = "${requested.removeSuffix(".m4a")} (${index++}).m4a" }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "audio/mp4")
            if (Build.VERSION.SDK_INT >= 29) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            } else {
                check(legacyFolder.exists() || legacyFolder.mkdirs()) { "无法创建导出文件夹" }
                put(MediaStore.MediaColumns.DATA, File(legacyFolder, name).absolutePath)
            }
        }
        val uri = contentResolver.insert(collection(), values) ?: error("无法创建导出文件")
        try {
            val output = contentResolver.openOutputStream(uri) ?: error("无法打开导出文件")
            output.use { target -> source.inputStream().use { it.copyTo(target) } }
            if (Build.VERSION.SDK_INT >= 29) {
                contentResolver.update(uri, ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }, null, null)
            }
            return uri
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
    }

    private fun queryRingtones(includeDuration: Boolean = true): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val column = if (Build.VERSION.SDK_INT >= 29) MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA
        val selection = if (Build.VERSION.SDK_INT >= 29) "$column = ?" else "$column LIKE ?"
        val argument = if (Build.VERSION.SDK_INT >= 29) folder else "${legacyFolder.absolutePath}/%"
        contentResolver.query(collection(), arrayOf(MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.DATE_ADDED),
            selection, arrayOf(argument), "${MediaStore.MediaColumns.DATE_ADDED} DESC")?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(1) ?: continue
                if (!name.endsWith(".m4a", ignoreCase = true)) continue
                val uri = ContentUris.withAppendedId(collection(), cursor.getLong(0))
                val metadata = MediaMetadataRetriever()
                val duration = if (!includeDuration) 0L else try {
                    metadata.setDataSource(this, uri)
                    metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                } catch (_: Exception) { 0L } finally { metadata.release() }
                result.add(mapOf("uri" to uri.toString(), "name" to name,
                    "size" to cursor.getLong(2), "duration" to duration, "createdAt" to cursor.getLong(3) * 1000))
            }
        }
        return result
    }

    private fun shareCopy(uri: Uri): String {
        val directory = File(cacheDir, "share").apply { mkdirs() }
        directory.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86400000 }?.forEach { it.delete() }
        val name = contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: "铃声.m4a"
        val file = File.createTempFile("share_", "_${cleanName(name)}", directory)
        try {
            val input = contentResolver.openInputStream(uri) ?: error("无法读取铃声")
            input.use { source -> file.outputStream().use { source.copyTo(it) } }
            return file.absolutePath
        } catch (e: Exception) { file.delete(); throw e }
    }

    private fun setRingtone(source: Uri, type: Int): Boolean {
        check(Settings.System.canWrite(this)) { "需要修改系统设置权限" }
        val ringtoneType = when (type) {
            1 -> RingtoneManager.TYPE_ALARM
            2 -> RingtoneManager.TYPE_NOTIFICATION
            else -> RingtoneManager.TYPE_RINGTONE
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "铃声_${System.currentTimeMillis()}.m4a")
            put(MediaStore.MediaColumns.MIME_TYPE, "audio/mp4")
            put(MediaStore.Audio.Media.IS_RINGTONE, ringtoneType == RingtoneManager.TYPE_RINGTONE)
            put(MediaStore.Audio.Media.IS_ALARM, ringtoneType == RingtoneManager.TYPE_ALARM)
            put(MediaStore.Audio.Media.IS_NOTIFICATION, ringtoneType == RingtoneManager.TYPE_NOTIFICATION)
            if (Build.VERSION.SDK_INT >= 29) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_RINGTONES)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            } else {
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_RINGTONES).apply { mkdirs() }
                put(MediaStore.MediaColumns.DATA, File(dir, "铃声_${System.currentTimeMillis()}.m4a").absolutePath)
            }
        }
        val target = contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values) ?: error("无法创建系统铃声")
        try {
            val input = contentResolver.openInputStream(source) ?: error("无法读取铃声")
            input.use { stream ->
                (contentResolver.openOutputStream(target) ?: error("无法写入系统铃声")).use { stream.copyTo(it) }
            }
            if (Build.VERSION.SDK_INT >= 29) contentResolver.update(target, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
            RingtoneManager.setActualDefaultRingtoneUri(this, ringtoneType, target)
            return true
        } catch (e: Exception) { contentResolver.delete(target, null, null); throw e }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 702) return
        val reply = pendingPicker ?: return
        pendingPicker = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) { reply.success(null); return }
        runCatching { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        executor.execute {
            try {
                val source = AudioSourceAccess.prepare(this, uri)
                runOnUiThread { reply.success(source) }
            } catch (e: Exception) { runOnUiThread { reply.error("SOURCE", e.message, null) } }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 701) {
            pendingStoragePermission?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            pendingStoragePermission = null
        }
    }

    override fun onDestroy() {
        bridge = null
        pendingPicker?.success(null)
        pendingPicker = null
        pendingStoragePermission?.error("CANCELLED", "授权已取消", null)
        pendingStoragePermission = null
        analyses.values.forEach { it.set(true) }
        executor.shutdownNow()
        super.onDestroy()
    }
}
