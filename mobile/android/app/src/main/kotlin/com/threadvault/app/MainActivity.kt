package com.threadvault.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.media.MediaScannerConnection
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.threadvault.app/platform"
    private var sharedUrl: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureSharedUrl(intent)
        requestRuntimePermissionsIfNeeded()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureSharedUrl(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "publishDownload" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Missing sourcePath or fileName", null)
                    } else {
                        try {
                            result.success(publishMedia(sourcePath, fileName, mimeType))
                        } catch (e: Exception) {
                            result.error("PUBLISH_FAILED", e.message ?: "Could not publish media", null)
                        }
                    }
                }
                "isOnWifi" -> result.success(isOnWifi())
                "startDownloadService", "updateDownloadService" -> {
                    val title = call.argument<String>("title") ?: "Clipora"
                    val message = call.argument<String>("message") ?: "Saving media…"
                    try {
                        DownloadForegroundService.start(this, title, message)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_FAILED", e.message ?: "Could not start download service", null)
                    }
                }
                "showDownloadComplete" -> {
                    val title = call.argument<String>("title") ?: "Clipora"
                    val message = call.argument<String>("message") ?: "Download finished."
                    val success = call.argument<Boolean>("success") ?: true
                    try {
                        DownloadForegroundService.complete(this, title, message, success)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_FAILED", e.message ?: "Could not show completion notification", null)
                    }
                }
                "stopDownloadService" -> {
                    try {
                        DownloadForegroundService.stop(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_FAILED", e.message ?: "Could not stop download service", null)
                    }
                }
                "returnToSourceApp" -> {
                    try {
                        moveTaskToBack(true)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RETURN_FAILED", e.message ?: "Could not return to the previous app", null)
                    }
                }
                "takeSharedUrl" -> {
                    val value = sharedUrl
                    sharedUrl = null
                    result.success(value)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestRuntimePermissionsIfNeeded() {
        val missing = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            missing.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            missing.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), 7108)
    }

    private fun captureSharedUrl(intent: Intent?) {
        if (intent == null) return
        val raw = intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
            ?: intent.data?.toString()
        if (raw.isNullOrBlank()) return

        val urls = Regex("https?://[^\\s<>\"]+", RegexOption.IGNORE_CASE)
            .findAll(raw)
            .map { it.value.trim().trimEnd(',', '.', ';', ')') }
            .filter { it.isNotBlank() }
            .distinct()
            .take(20)
            .toList()

        sharedUrl = if (urls.isNotEmpty()) urls.joinToString("\n") else raw.trim()
    }

    private fun publishMedia(sourcePath: String, fileName: String, mimeType: String): String {
        val source = File(sourcePath)
        require(source.exists() && source.length() > 0) { "Source file is missing or empty" }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return publishLegacyMedia(source, fileName, mimeType)
        }

        val (collection, relativePath) = when {
            mimeType.startsWith("video/") -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_MOVIES}/Clipora"
            mimeType.startsWith("image/") -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_PICTURES}/Clipora"
            else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_DOWNLOADS}/Clipora"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val resolver = contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Android could not create the media file")

        try {
            resolver.openOutputStream(uri, "w")?.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output, 1024 * 1024) }
            } ?: throw IllegalStateException("Android could not open the destination file")

            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun publishLegacyMedia(source: File, fileName: String, mimeType: String): String {
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            throw IllegalStateException("Storage permission is required on this Android version. Open Clipora once and allow storage access.")
        }
        val parent = when {
            mimeType.startsWith("video/") -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
            mimeType.startsWith("image/") -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            else -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        }
        val folder = File(parent, "Clipora").apply { mkdirs() }
        val destination = uniqueLegacyFile(folder, fileName)
        FileInputStream(source).use { input -> destination.outputStream().use { output -> input.copyTo(output, 1024 * 1024) } }
        MediaScannerConnection.scanFile(this, arrayOf(destination.absolutePath), arrayOf(mimeType), null)
        return destination.absolutePath
    }

    private fun uniqueLegacyFile(folder: File, fileName: String): File {
        val requested = File(folder, fileName)
        if (!requested.exists()) return requested
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val suffix = if (dot > 0) fileName.substring(dot) else ""
        for (index in 2..999) {
            val candidate = File(folder, "${stem}_$index$suffix")
            if (!candidate.exists()) return candidate
        }
        return File(folder, "${stem}_${System.currentTimeMillis()}$suffix")
    }

    private fun isOnWifi(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }
}
