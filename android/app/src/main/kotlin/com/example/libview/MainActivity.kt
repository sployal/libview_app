package com.example.libview

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val downloadsChannel = "com.example.libview/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannel)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "saveToDownloads" -> {
                            val sourcePath = call.argument<String>("sourcePath")
                            val fileName = call.argument<String>("fileName")
                            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                            if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                                result.error("INVALID_ARGS", "sourcePath and fileName are required", null)
                                return@setMethodCallHandler
                            }
                            result.success(saveToDownloads(sourcePath, fileName, mimeType))
                        }
                        "openDownload" -> {
                            val uri = call.argument<String>("uri")
                            val filePath = call.argument<String>("filePath")
                            val fileName = call.argument<String>("fileName")
                            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                            openDownload(uri, filePath, fileName, mimeType)
                            result.success(true)
                        }
                        "deleteDownload" -> {
                            val uri = call.argument<String>("uri")
                            val filePath = call.argument<String>("filePath")
                            result.success(deleteDownload(uri, filePath))
                        }
                        "downloadExists" -> {
                            val uri = call.argument<String>("uri")
                            val filePath = call.argument<String>("filePath")
                            val fileName = call.argument<String>("fileName")
                            result.success(downloadExists(uri, filePath, fileName))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("DOWNLOADS_ERROR", e.message, null)
                }
            }
    }

    private fun saveToDownloads(sourcePath: String, fileName: String, mimeType: String): Map<String, String> {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw Exception("Downloaded temp file is missing")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("Could not create a file in Downloads")

            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(output)
                }
            } ?: throw Exception("Could not write to Downloads")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)

            val path = queryDownloadsPath(uri, fileName)
            return mapOf("path" to path, "uri" to uri.toString())
        }

        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!downloadsDir.exists()) {
            downloadsDir.mkdirs()
        }
        val dest = uniqueFile(downloadsDir, fileName)
        sourceFile.copyTo(dest, overwrite = false)
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            dest,
        )
        return mapOf("path" to dest.absolutePath, "uri" to uri.toString())
    }

    private fun openDownload(uriString: String?, filePath: String?, fileName: String?, mimeType: String) {
        val uri = resolveUri(uriString, filePath, fileName)
            ?: throw Exception("Permission denied")

        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            clipData = android.content.ClipData.newRawUri("", uri)
        }

        val matches = packageManager.queryIntentActivities(viewIntent, PackageManager.MATCH_DEFAULT_ONLY)
        for (info in matches) {
            grantUriPermission(
                info.activityInfo.packageName,
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }

        val chooser = Intent.createChooser(viewIntent, "Open with")
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(chooser)
    }

    private fun deleteDownload(uriString: String?, filePath: String?): Boolean {
        var deleted = false
        if (!uriString.isNullOrBlank() && uriString.startsWith("content://")) {
            try {
                deleted = contentResolver.delete(Uri.parse(uriString), null, null) > 0
            } catch (_: Exception) {
            }
        }
        if (!filePath.isNullOrBlank()) {
            val file = File(filePath)
            if (file.exists()) {
                deleted = file.delete() || deleted
            }
        }
        return deleted
    }

    private fun downloadExists(uriString: String?, filePath: String?, fileName: String?): Boolean {
        if (!uriString.isNullOrBlank() && uriString.startsWith("content://")) {
            try {
                contentResolver.openAssetFileDescriptor(Uri.parse(uriString), "r")?.use {
                    return true
                }
            } catch (_: Exception) {
            }
        }
        if (!filePath.isNullOrBlank() && File(filePath).exists()) {
            return true
        }
        return resolveMediaStoreUri(fileName) != null
    }

    private fun resolveUri(uriString: String?, filePath: String?, fileName: String?): Uri? {
        if (!uriString.isNullOrBlank()) {
            val parsed = Uri.parse(uriString)
            if (canRead(parsed)) {
                return parsed
            }
        }

        resolveMediaStoreUri(fileName)?.let { return it }

        if (!filePath.isNullOrBlank()) {
            val file = File(filePath)
            if (file.exists()) {
                return FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    file,
                )
            }
        }
        return null
    }

    private fun canRead(uri: Uri): Boolean {
        return try {
            contentResolver.openAssetFileDescriptor(uri, "r")?.use { true } ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun resolveMediaStoreUri(fileName: String?): Uri? {
        if (fileName.isNullOrBlank() || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return null
        }
        contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME}=?",
            arrayOf(fileName),
            "${MediaStore.Downloads.DATE_ADDED} DESC",
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                val uri = ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id)
                if (canRead(uri)) {
                    return uri
                }
            }
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun queryDownloadsPath(uri: Uri, fileName: String): String {
        val fallback = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            fileName,
        ).absolutePath

        contentResolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DATA),
            null,
            null,
            null,
        )?.use { cursor ->
            val index = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
            if (index >= 0 && cursor.moveToFirst()) {
                val path = cursor.getString(index)
                if (!path.isNullOrBlank()) {
                    return path
                }
            }
        }
        return fallback
    }

    private fun uniqueFile(directory: File, fileName: String): File {
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var dest = File(directory, fileName)
        var index = 1
        while (dest.exists()) {
            dest = File(directory, "$base ($index)$ext")
            index++
        }
        return dest
    }
}
