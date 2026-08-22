package com.example.libview

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.Locale
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val downloadsChannel = "com.example.libview/downloads"
    private val documentsChannel = "com.example.libview/phone_documents"
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, documentsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listDocuments" -> {
                        thread {
                            try {
                                val docs = listPhoneDocuments()
                                mainHandler.post { result.success(docs) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("DOCUMENTS_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "copyDocument" -> {
                        val uri = call.argument<String>("uri")
                        val path = call.argument<String>("path")
                        val fileName = call.argument<String>("fileName")
                        thread {
                            try {
                                val copied = copyDocumentToCache(uri, path, fileName)
                                mainHandler.post { result.success(copied) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("COPY_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "openDocument" -> {
                        val uri = call.argument<String>("uri")
                        val path = call.argument<String>("path")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        try {
                            openDownload(uri, path, fileName, mimeType)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_ERROR", e.message, null)
                        }
                    }
                    "documentThumbnail" -> {
                        val uri = call.argument<String>("uri")
                        val path = call.argument<String>("path")
                        val fileName = call.argument<String>("fileName")
                        val modifiedMs = call.argument<Number>("modifiedMs")?.toLong() ?: 0L
                        thread {
                            try {
                                val thumb = createDocumentThumbnail(uri, path, fileName, modifiedMs)
                                mainHandler.post { result.success(thumb) }
                            } catch (_: Exception) {
                                mainHandler.post { result.success(null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
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

    private val documentExtensions = setOf(
        "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx",
        "txt", "rtf", "odt", "ods", "odp", "csv",
    )

    private val documentMimeTypes = arrayOf(
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "text/plain",
        "text/csv",
        "application/rtf",
        "text/rtf",
        "application/vnd.oasis.opendocument.text",
        "application/vnd.oasis.opendocument.spreadsheet",
        "application/vnd.oasis.opendocument.presentation",
    )

    private val skipDirectoryNames = setOf(
        "dcim", "pictures", "movies", "music", "alarms",
        "ringtones", "notifications", "podcasts", "audiobooks",
        "cache", "obb", ".thumbnails", ".trashed",
    )

    private fun listPhoneDocuments(): List<Map<String, Any?>> {
        val byKey = LinkedHashMap<String, Map<String, Any?>>()

        queryMediaStoreFiles(byKey)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            queryDownloadsCollection(byKey)
        }
        scanCommonDocumentFolders(byKey)

        return byKey.values.sortedByDescending {
            (it["modifiedMs"] as? Number)?.toLong() ?: 0L
        }
    }

    @Suppress("DEPRECATION")
    private fun queryMediaStoreFiles(into: MutableMap<String, Map<String, Any?>>) {
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.MIME_TYPE,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Files.FileColumns.DATA,
        )
        val likeClauses = documentExtensions.joinToString(" OR ") {
            "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?"
        }
        val mimeClauses = documentMimeTypes.joinToString(" OR ") {
            "${MediaStore.Files.FileColumns.MIME_TYPE}=?"
        }
        val selection = "($mimeClauses) OR ($likeClauses)"
        val args = documentMimeTypes + documentExtensions.map { "%.$it" }
        val collection = MediaStore.Files.getContentUri("external")

        try {
            contentResolver.query(
                collection,
                projection,
                selection,
                args,
                "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC",
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndex(MediaStore.Files.FileColumns._ID)
                val nameIdx = cursor.getColumnIndex(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val mimeIdx = cursor.getColumnIndex(MediaStore.Files.FileColumns.MIME_TYPE)
                val sizeIdx = cursor.getColumnIndex(MediaStore.Files.FileColumns.SIZE)
                val modifiedIdx = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATE_MODIFIED)
                val dataIdx = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA)

                while (cursor.moveToNext()) {
                    val name = if (nameIdx >= 0) cursor.getString(nameIdx) else null
                    if (name.isNullOrBlank() || !isDocumentFile(name)) continue
                    val id = if (idIdx >= 0) cursor.getLong(idIdx) else -1L
                    val path = if (dataIdx >= 0) cursor.getString(dataIdx) else null
                    val uri = if (id >= 0) {
                        ContentUris.withAppendedId(collection, id).toString()
                    } else {
                        null
                    }
                    addDocument(
                        into,
                        name = name,
                        path = path,
                        uri = uri,
                        mime = if (mimeIdx >= 0) cursor.getString(mimeIdx) else null,
                        size = if (sizeIdx >= 0) cursor.getLong(sizeIdx) else 0L,
                        modifiedMs = if (modifiedIdx >= 0) cursor.getLong(modifiedIdx) * 1000L else 0L,
                    )
                }
            }
        } catch (_: Exception) {
        }
    }

    @Suppress("DEPRECATION")
    private fun queryDownloadsCollection(into: MutableMap<String, Map<String, Any?>>) {
        val projection = arrayOf(
            MediaStore.Downloads._ID,
            MediaStore.Downloads.DISPLAY_NAME,
            MediaStore.Downloads.MIME_TYPE,
            MediaStore.Downloads.SIZE,
            MediaStore.Downloads.DATE_MODIFIED,
            MediaStore.MediaColumns.DATA,
        )
        try {
            contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                "${MediaStore.Downloads.DATE_MODIFIED} DESC",
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndex(MediaStore.Downloads._ID)
                val nameIdx = cursor.getColumnIndex(MediaStore.Downloads.DISPLAY_NAME)
                val mimeIdx = cursor.getColumnIndex(MediaStore.Downloads.MIME_TYPE)
                val sizeIdx = cursor.getColumnIndex(MediaStore.Downloads.SIZE)
                val modifiedIdx = cursor.getColumnIndex(MediaStore.Downloads.DATE_MODIFIED)
                val dataIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)

                while (cursor.moveToNext()) {
                    val name = if (nameIdx >= 0) cursor.getString(nameIdx) else null
                    if (name.isNullOrBlank() || !isDocumentFile(name)) continue
                    val id = if (idIdx >= 0) cursor.getLong(idIdx) else -1L
                    addDocument(
                        into,
                        name = name,
                        path = if (dataIdx >= 0) cursor.getString(dataIdx) else null,
                        uri = if (id >= 0) {
                            ContentUris.withAppendedId(
                                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                id,
                            ).toString()
                        } else {
                            null
                        },
                        mime = if (mimeIdx >= 0) cursor.getString(mimeIdx) else null,
                        size = if (sizeIdx >= 0) cursor.getLong(sizeIdx) else 0L,
                        modifiedMs = if (modifiedIdx >= 0) cursor.getLong(modifiedIdx) * 1000L else 0L,
                    )
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun scanCommonDocumentFolders(into: MutableMap<String, Map<String, Any?>>) {
        val roots = mutableListOf<File>()
        val storage = Environment.getExternalStorageDirectory()
        if (storage != null) {
            roots.add(File(storage, Environment.DIRECTORY_DOWNLOADS))
            roots.add(File(storage, Environment.DIRECTORY_DOCUMENTS))
            roots.add(File(storage, "Download"))
            roots.add(File(storage, "Documents"))
            roots.add(File(storage, "WhatsApp/Media/WhatsApp Documents"))
            roots.add(File(storage, "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents"))
            roots.add(File(storage, "Telegram/Telegram Documents"))
            roots.add(File(storage, "Bluetooth"))

            val canScanAll = Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
                Environment.isExternalStorageManager()
            if (canScanAll) {
                scanDirectory(storage, into, depth = 0, maxDepth = 6)
                return
            }
        }

        for (root in roots) {
            scanDirectory(root, into, depth = 0, maxDepth = 8)
        }
    }

    private fun scanDirectory(
        directory: File,
        into: MutableMap<String, Map<String, Any?>>,
        depth: Int,
        maxDepth: Int,
    ) {
        if (depth > maxDepth || into.size > 2500 || !directory.exists() || !directory.isDirectory) {
            return
        }
        val name = directory.name.lowercase(Locale.US)
        val parentName = directory.parentFile?.name?.lowercase(Locale.US)
        if (depth > 0 && (name.startsWith(".") || skipDirectoryNames.contains(name))) {
            return
        }
        if (parentName == "android" && (name == "data" || name == "obb")) {
            return
        }

        val children = try {
            directory.listFiles()
        } catch (_: Exception) {
            null
        } ?: return

        for (child in children) {
            try {
                if (child.isDirectory) {
                    scanDirectory(child, into, depth + 1, maxDepth)
                } else if (isDocumentFile(child.name)) {
                    addDocument(
                        into,
                        name = child.name,
                        path = child.absolutePath,
                        uri = null,
                        mime = mimeFromName(child.name),
                        size = child.length(),
                        modifiedMs = child.lastModified(),
                    )
                }
            } catch (_: Exception) {
            }
        }
    }

    private fun addDocument(
        into: MutableMap<String, Map<String, Any?>>,
        name: String,
        path: String?,
        uri: String?,
        mime: String?,
        size: Long,
        modifiedMs: Long,
    ) {
        val key = when {
            !path.isNullOrBlank() -> path.lowercase(Locale.US)
            !uri.isNullOrBlank() -> uri
            else -> "name:${name.lowercase(Locale.US)}:$size:$modifiedMs"
        }
        val existing = into[key]
        if (existing != null) {
            val existingModified = (existing["modifiedMs"] as? Number)?.toLong() ?: 0L
            if (existingModified >= modifiedMs) {
                return
            }
        }
        into[key] = mapOf(
            "name" to name,
            "path" to path,
            "uri" to uri,
            "mime" to (mime ?: mimeFromName(name)),
            "size" to size,
            "modifiedMs" to modifiedMs,
        )
    }

    private fun isDocumentFile(name: String): Boolean {
        val ext = name.substringAfterLast('.', "").lowercase(Locale.US)
        return documentExtensions.contains(ext)
    }

    private fun mimeFromName(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase(Locale.US)
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    private fun createDocumentThumbnail(
        uriString: String?,
        path: String?,
        fileName: String?,
        modifiedMs: Long,
    ): String? {
        val name = fileName ?: path ?: return null
        val ext = name.substringAfterLast('.', "").lowercase(Locale.US)
        if (ext != "pdf") return null

        val keySource = (path ?: uriString ?: name) + ":$modifiedMs"
        val cacheName = "thumb_${keySource.hashCode().toUInt()}.jpg"
        val dest = File(File(cacheDir, "doc_thumbs"), cacheName)
        if (dest.exists() && dest.length() > 0) {
            return dest.absolutePath
        }
        dest.parentFile?.mkdirs()

        val pfd = openDocumentDescriptor(uriString, path) ?: return null
        pfd.use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                if (renderer.pageCount < 1) return null
                renderer.openPage(0).use { page ->
                    val maxWidth = 400
                    val scale = maxWidth.toFloat() / page.width.coerceAtLeast(1)
                    val width = maxWidth
                    val height = (page.height * scale).toInt().coerceAtLeast(1)
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    bitmap.eraseColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    dest.outputStream().use { output ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, output)
                    }
                    bitmap.recycle()
                }
            }
        }
        return if (dest.exists() && dest.length() > 0) dest.absolutePath else null
    }

    private fun openDocumentDescriptor(
        uriString: String?,
        path: String?,
    ): ParcelFileDescriptor? {
        if (!path.isNullOrBlank()) {
            val file = File(path)
            if (file.exists()) {
                return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            }
        }
        if (!uriString.isNullOrBlank()) {
            return contentResolver.openFileDescriptor(Uri.parse(uriString), "r")
        }
        return null
    }

    private fun copyDocumentToCache(uriString: String?, path: String?, fileName: String?): String {
        val safeName = (fileName ?: "document").replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val dest = File(cacheDir, "phone_doc_${System.currentTimeMillis()}_$safeName")

        if (!path.isNullOrBlank()) {
            val source = File(path)
            if (source.exists()) {
                source.copyTo(dest, overwrite = true)
                return dest.absolutePath
            }
        }

        if (!uriString.isNullOrBlank()) {
            contentResolver.openInputStream(Uri.parse(uriString))?.use { input ->
                dest.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: throw Exception("Could not open the selected document")
            return dest.absolutePath
        }

        throw Exception("Selected file could not be found")
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
