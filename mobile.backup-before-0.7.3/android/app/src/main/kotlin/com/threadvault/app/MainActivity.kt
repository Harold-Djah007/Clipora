package com.threadvault.app

import android.content.ContentValues
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.threadvault.app/platform"

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
                else -> result.notImplemented()
            }
        }
    }

    private fun publishMedia(sourcePath: String, fileName: String, mimeType: String): String {
        val source = File(sourcePath)
        require(source.exists() && source.length() > 0) { "Source file is missing or empty" }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // The app keeps its private copy on legacy Android. Android 10+ is
            // the supported public MediaStore publishing path.
            return source.absolutePath
        }

        val (collection, relativePath) = when {
            mimeType.startsWith("video/") -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_MOVIES}/ThreadVault"
            mimeType.startsWith("image/") -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_PICTURES}/ThreadVault"
            else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_DOWNLOADS}/ThreadVault"
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
                FileInputStream(source).use { input -> input.copyTo(output, 256 * 1024) }
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

    private fun isOnWifi(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }
}
