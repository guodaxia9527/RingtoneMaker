package com.ringtone.ringtone_maker

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ringtone.ringtone_maker/ringtone"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasWriteSettingsPermission" -> {
                    result.success(hasWriteSettingsPermission())
                }
                "requestWriteSettingsPermission" -> {
                    requestWriteSettingsPermission()
                    result.success(true)
                }
                "setAsRingtone" -> {
                    val path = call.argument<String>("path")
                    val type = call.argument<Int>("type") ?: 0
                    if (path != null) {
                        val success = setAsRingtone(path, type)
                        result.success(success)
                    } else {
                        result.error("INVALID_PATH", "File path is null", null)
                    }
                }
                "deleteFile" -> {
                    val uri = call.argument<String>("uri")
                    if (uri != null) {
                        val success = deleteRingtoneFile(uri)
                        result.success(success)
                    } else {
                        result.error("INVALID_URI", "File URI is null", null)
                    }
                }
                "createFile" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    if (sourcePath != null && fileName != null) {
                        val resultUri = createFileViaMediaStore(sourcePath, fileName)
                        if (resultUri != null) {
                            result.success(resultUri)
                        } else {
                            result.error("CREATE_FAILED", "Failed to create file", null)
                        }
                    } else {
                        result.error("INVALID_PARAMS", "Missing sourcePath or fileName", null)
                    }
                }
                "queryRingtones" -> {
                    val ringtones = queryRingtonesFromMediaStore()
                    result.success(ringtones)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun hasWriteSettingsPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.System.canWrite(this)
        } else {
            true
        }
    }

    private fun requestWriteSettingsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        }
    }

    private fun setAsRingtone(filePath: String, type: Int): Boolean {
        return try {
            val ringtoneType = when (type) {
                0 -> RingtoneManager.TYPE_RINGTONE      // 来电铃声
                1 -> RingtoneManager.TYPE_ALARM          // 闹钟铃声
                2 -> RingtoneManager.TYPE_NOTIFICATION    // 通知铃声
                else -> RingtoneManager.TYPE_RINGTONE
            }

            // 复制文件到系统铃声目录
            val file = File(filePath)
            if (!file.exists()) {
                return false
            }

            // 获取 MIME 类型
            val extension = MimeTypeMap.getFileExtensionFromUrl(filePath)
            val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "audio/mpeg"

            // 创建 ContentValues
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.SIZE, file.length())

                when (ringtoneType) {
                    RingtoneManager.TYPE_RINGTONE -> {
                        put(MediaStore.Audio.Media.IS_RINGTONE, true)
                    }
                    RingtoneManager.TYPE_ALARM -> {
                        put(MediaStore.Audio.Media.IS_ALARM, true)
                    }
                    RingtoneManager.TYPE_NOTIFICATION -> {
                        put(MediaStore.Audio.Media.IS_NOTIFICATION, true)
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_RINGTONES)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }

            // 获取音频文件 URI
            val audioUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }

            // 插入到媒体库
            val uri = contentResolver.insert(audioUri, values)

            if (uri != null) {
                // 复制文件内容
                contentResolver.openOutputStream(uri)?.use { outputStream ->
                    FileInputStream(file).use { inputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }

                // 如果是 Android 10+，需要标记为非 pending
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                }

                // 设置为铃声
                RingtoneManager.setActualDefaultRingtoneUri(this, ringtoneType, uri)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun deleteRingtoneFile(fileUri: String): Boolean {
        return try {
            // 直接解析 URI 并删除
            val uri = Uri.parse(fileUri)
            val deleted = contentResolver.delete(uri, null, null)
            deleted > 0
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun createFileViaMediaStore(sourcePath: String, fileName: String): String? {
        return try {
            val sourceFile = File(sourcePath)
            if (!sourceFile.exists()) return null

            val mimeType = "audio/mp4a-latm"

            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.SIZE, sourceFile.length())

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/RingtoneMaker")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }

            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }

            val uri = contentResolver.insert(collection, values) ?: return null

            contentResolver.openOutputStream(uri)?.use { outputStream ->
                FileInputStream(sourceFile).use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            }

            // 返回 URI 字符串而不是路径
            uri.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun queryRingtonesFromMediaStore(): List<Map<String, Any>> {
        val ringtones = mutableListOf<Map<String, Any>>()
        
        try {
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }
            
            val projection = arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.SIZE,
                MediaStore.MediaColumns.DURATION,
                MediaStore.MediaColumns.DATA
            )
            
            // 查询 RingtoneMaker 目录下的 m4a 文件
            val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
            val selectionArgs = arrayOf("%RingtoneMaker%", "%.m4a")
            
            contentResolver.query(collection, projection, selection, selectionArgs, "${MediaStore.MediaColumns.DATE_ADDED} DESC")?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DURATION)
                val dataColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idColumn)
                    val name = cursor.getString(nameColumn)
                    val size = cursor.getLong(sizeColumn)
                    val duration = cursor.getLong(durationColumn)
                    val data = cursor.getString(dataColumn)
                    
                    val uri = ContentUris.withAppendedId(collection, id)
                    
                    ringtones.add(mapOf(
                        "uri" to uri.toString(),
                        "name" to name,
                        "path" to data,
                        "size" to size,
                        "duration" to duration
                    ))
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return ringtones
    }

}
