package com.threadvault.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.Manifest
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.os.PowerManager
import android.provider.MediaStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

class InstantShareDownloadService : Service() {
    private val activeJobs = AtomicInteger(0)
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannels(this)
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val urls = intent?.getStringArrayListExtra(EXTRA_URLS)
            ?: intent?.getStringExtra(EXTRA_URL)?.let { arrayListOf(it) }
            ?: arrayListOf()
        val cleanUrls = ShareLinks.normalize(urls)
        if (cleanUrls.isEmpty()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (!ShareJobs.claim(cleanUrls)) {
            if (activeJobs.get() <= 0) stopSelf(startId)
            return START_NOT_STICKY
        }

        activeJobs.incrementAndGet()
        startForeground(NOTIFICATION_ID, progressNotification("Queued ${cleanUrls.size} Clipora link${if (cleanUrls.size == 1) "" else "s"}…"))
        Thread { runSharedDownload(cleanUrls, startId) }.start()
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun runSharedDownload(urls: List<String>, startId: Int) {
        var saved = 0
        var failed = 0
        val errors = mutableListOf<String>()
        try {
            val baseUrl = resolverBaseUrl()
            if (baseUrl.isBlank()) {
                throw IllegalStateException(
                    "No Clipora resolver URL is configured. Build with -PCLIPORA_RESOLVER_URL=https://your-resolver or --dart-define=CLIPORA_RESOLVER_URL=https://your-resolver."
                )
            }
            if (wifiOnlyEnabled() && !isOnWifi()) {
                throw IllegalStateException("Wi-Fi only is enabled. Connect to Wi-Fi or turn it off in Clipora Settings.")
            }

            urls.forEachIndexed { index, url ->
                try {
                    updateProgress("Resolving ${index + 1}/${urls.size}…")
                    val post = resolvePost(baseUrl, url)
                    val media = post.optJSONArray("media") ?: JSONArray()
                    if (media.length() == 0) throw IllegalStateException("Resolver returned no media.")
                    for (i in 0 until media.length()) {
                        val item = media.optJSONObject(i) ?: continue
                        val mediaUrl = absoluteUrl(baseUrl, item.optString("url"))
                        if (mediaUrl.isBlank()) continue
                        val kind = item.optString("media_type", item.optString("type", "video")).lowercase(Locale.US)
                        val mimeType = item.optString(
                            "mime_type",
                            if (kind.contains("image") || kind.contains("photo")) "image/jpeg" else "video/mp4",
                        )
                        val ext = extensionFor(mimeType, mediaUrl)
                        val author = safePart(post.optString("author", post.optString("platform", "clipora")))
                        val postId = safePart(post.optString("post_id", post.optString("id", UUID.randomUUID().toString())))
                        val fileName = "${author}_${postId}_${i + 1}$ext"
                        updateProgress("Saving ${i + 1}/${media.length()} from link ${index + 1}/${urls.size}…")
                        val temp = downloadToTemp(mediaUrl, ext, mimeType)
                        try {
                            publishMedia(temp, fileName, mimeType)
                            saved++
                        } finally {
                            temp.delete()
                        }
                    }
                } catch (error: Exception) {
                    failed++
                    errors.add(cleanError(error))
                }
            }

            val ok = saved > 0
            val message = when {
                failed == 0 -> "Saved $saved media item${if (saved == 1) "" else "s"}."
                saved > 0 -> "Saved $saved; $failed link${if (failed == 1) "" else "s"} failed. ${errors.firstOrNull().orEmpty()}"
                else -> "Clipora could not save this share. ${errors.firstOrNull().orEmpty()}"
            }
            completeNotification(if (ok) "Clipora saved media" else "Clipora share failed", message, ok)
        } catch (error: Exception) {
            completeNotification("Clipora could not save", cleanError(error), false)
        } finally {
            if (activeJobs.decrementAndGet() <= 0) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf(startId)
            }
        }
    }

    private fun resolverBaseUrl(): String {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val saved = prefs.getString("flutter.resolverUrl", null)
            ?: prefs.getString("resolverUrl", null)
            ?: ""
        val configured = normalizeBaseUrl(saved)
        if (configured.isNotBlank()) return configured
        val bundled = normalizeBaseUrl(bundledResolverUrl())
        if (bundled.isNotBlank()) return bundled
        return ""
    }

    private fun wifiOnlyEnabled(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getBoolean("flutter.wifiOnly", prefs.getBoolean("wifiOnly", false))
    }

    private fun isOnWifi(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    @Suppress("DiscouragedApi")
    private fun bundledResolverUrl(): String {
        val resourceId = resources.getIdentifier("clipora_resolver_url", "string", packageName)
        return if (resourceId == 0) "" else resources.getString(resourceId)
    }

    private fun resolvePost(baseUrl: String, sourceUrl: String): JSONObject {
        val endpoint = URL("$baseUrl/api/resolve/universal")
        val body = JSONObject().put("url", sourceUrl).toString().toByteArray(Charsets.UTF_8)
        val conn = (endpoint.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 5000
            readTimeout = 180000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
        }
        try {
            conn.outputStream.use { it.write(body) }
            val status = conn.responseCode
            val response = if (status in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
            }
            if (status !in 200..299) {
                val detail = runCatching { JSONObject(response).optString("detail") }.getOrNull().orEmpty()
                throw IllegalStateException(detail.ifBlank { "Resolver returned HTTP $status." })
            }
            return JSONObject(response)
        } finally {
            conn.disconnect()
        }
    }

    private fun downloadToTemp(mediaUrl: String, ext: String, mimeType: String): File {
        val temp = File(cacheDir, "clipora-${UUID.randomUUID()}$ext")
        val conn = (URL(mediaUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 5000
            readTimeout = 180000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "Clipora/2.0 Android")
        }
        try {
            val status = conn.responseCode
            if (status !in 200..299) throw IllegalStateException("Media download returned HTTP $status.")
            conn.inputStream.use { input ->
                FileOutputStream(temp).use { output -> input.copyTo(output, 1024 * 1024) }
            }
            if (!temp.exists() || temp.length() == 0L) throw IllegalStateException("Downloaded file was empty.")
            if (!matchesExpectedMedia(temp, mimeType)) {
                temp.delete()
                throw IllegalStateException("The media host returned a page or unsupported file instead of the expected media.")
            }
            return temp
        } finally {
            conn.disconnect()
        }
    }

    private fun matchesExpectedMedia(file: File, mimeType: String): Boolean {
        val bytes = FileInputStream(file).use { input -> ByteArray(128).let { buffer -> buffer.copyOf(input.read(buffer).coerceAtLeast(0)) } }
        fun byte(index: Int): Int = if (index < bytes.size) bytes[index].toInt() and 0xff else -1
        val isJpeg = byte(0) == 0xff && byte(1) == 0xd8 && byte(2) == 0xff
        val isPng = byte(0) == 0x89 && byte(1) == 0x50 && byte(2) == 0x4e && byte(3) == 0x47
        val isWebp = byte(0) == 0x52 && byte(1) == 0x49 && byte(2) == 0x46 && byte(3) == 0x46 &&
            byte(8) == 0x57 && byte(9) == 0x45 && byte(10) == 0x42 && byte(11) == 0x50
        val isGif = byte(0) == 0x47 && byte(1) == 0x49 && byte(2) == 0x46 && byte(3) == 0x38 &&
            (byte(4) == 0x37 || byte(4) == 0x39) && byte(5) == 0x61
        var isMp4 = false
        for (index in 0..(bytes.size - 4).coerceAtMost(32)) {
            if (byte(index) == 0x66 && byte(index + 1) == 0x74 && byte(index + 2) == 0x79 && byte(index + 3) == 0x70) {
                isMp4 = true
                break
            }
        }
        return if (mimeType.startsWith("image/")) isJpeg || isPng || isWebp || isGif else isMp4
    }

    private fun publishMedia(source: File, fileName: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return publishLegacyMedia(source, fileName, mimeType)
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
        val uri = contentResolver.insert(collection, values) ?: throw IllegalStateException("Android could not create the media file")
        try {
            contentResolver.openOutputStream(uri, "w")?.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output, 1024 * 1024) }
            } ?: throw IllegalStateException("Android could not open the destination file")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
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

    private fun updateProgress(message: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, progressNotification(message))
    }

    private fun completeNotification(title: String, message: String, success: Boolean) {
        CliporaNotifications.notifyResult(
            this,
            title,
            message,
            success,
            avoidIds = intArrayOf(NOTIFICATION_ID),
        )
    }

    private fun progressNotification(message: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        return builder
            .setContentTitle("Clipora background save")
            .setContentText(message)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(launchPendingIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .build()
    }

    private fun launchPendingIntent(): PendingIntent {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(this, 0, launchIntent, flags)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Clipora:InstantShareWakeLock").apply {
            setReferenceCounted(false)
            acquire(30L * 60L * 1000L)
        }
    }

    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_URLS = "urls"
        private const val CHANNEL_ID = "clipora_instant_share"
        private const val NOTIFICATION_ID = 7117

        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Clipora instant saves", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Saves shared links without opening the Clipora screen."
                    setShowBadge(false)
                }
            )
            CliporaNotifications.ensureResultChannel(context)
        }

        private fun normalizeBaseUrl(raw: String?): String {
            var value = raw?.trim().orEmpty()
            if (value.isBlank()) return ""
            if (!value.contains("://")) value = "https://$value"
            while (value.endsWith("/")) value = value.dropLast(1)
            return value
        }

        private fun absoluteUrl(baseUrl: String, raw: String): String {
            val value = raw.trim()
            if (value.startsWith("/")) return "$baseUrl$value"
            return value
        }

        private fun extensionFor(mimeType: String, url: String): String {
            val lower = "$mimeType $url".lowercase(Locale.US)
            return when {
                lower.contains("image/webp") || lower.contains(".webp") -> ".webp"
                lower.contains("image/gif") || lower.contains(".gif") -> ".gif"
                lower.contains("image/png") || lower.contains(".png") -> ".png"
                lower.contains("image/") || lower.contains(".jpg") || lower.contains(".jpeg") -> ".jpg"
                else -> ".mp4"
            }
        }

        private fun safePart(raw: String): String {
            val cleaned = raw.replace(Regex("[^A-Za-z0-9._-]+"), "_").trim('_', '.', '-')
            return cleaned.take(80).ifBlank { "clipora" }
        }

        private fun cleanError(error: Throwable): String {
            var text = error.message ?: error.toString()
            text = text.replace(Regex("\u001B(?:[@-Z\\-_]|\\[[0-?]*[ -/]*[@-~])"), "")
                .replace(Regex("\\s+"), " ")
                .replace(Regex("^(?:ERROR:\\s*)+", RegexOption.IGNORE_CASE), "")
                .trim()
            if (text.contains("tiktok.com/?_r=1", ignoreCase = true) ||
                text.contains("status code 0", ignoreCase = true) ||
                text.contains("tiktok", ignoreCase = true) && (
                    text.isBlank() ||
                        text.contains("could not extract", ignoreCase = true) ||
                        text.contains("no downloadable", ignoreCase = true)
                    )
            ) {
                return "TikTok did not return a public video or photo file for this link. Open the post in TikTok, tap Share, and send it to Clipora again."
            }
            if (text.isBlank()) return "The resolver could not extract downloadable media from this link."
            return if (text.length <= 280) text else text.take(279).trimEnd() + "…"
        }
    }
}
