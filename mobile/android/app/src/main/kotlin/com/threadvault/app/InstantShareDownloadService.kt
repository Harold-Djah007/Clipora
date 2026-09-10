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
        val cleanUrls = urls.mapNotNull { extractFirstUrl(it) }.distinct().take(20)
        if (cleanUrls.isEmpty()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        activeJobs.incrementAndGet()
        startForeground(NOTIFICATION_ID, progressNotification("Queued ${cleanUrls.size} Clipora link${if (cleanUrls.size == 1) "" else "s"}…"))
        Thread { runSharedDownload(cleanUrls, startId) }.start()
        return START_NOT_STICKY
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
                        val temp = downloadToTemp(mediaUrl, ext)
                        try {
                            publishMedia(temp, fileName, mimeType)
                            saved++
                        } finally {
                            temp.delete()
                        }
                    }
                } catch (error: Exception) {
                    failed++
                    errors.add(error.message ?: error.toString())
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
            completeNotification("Clipora needs resolver", error.message ?: error.toString(), false)
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
        return normalizeBaseUrl("http://127.0.0.1:8010")
    }

    @Suppress("DEPRECATION")
    private fun bundledResolverUrl(): String {
        val appInfo = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
        return appInfo.metaData?.getString(RESOLVER_URL_META_DATA).orEmpty()
    }

    private fun resolvePost(baseUrl: String, sourceUrl: String): JSONObject {
        val endpoint = URL("$baseUrl/api/resolve/universal")
        val body = JSONObject().put("url", sourceUrl).toString().toByteArray(Charsets.UTF_8)
        val conn = (endpoint.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 2500
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

    private fun downloadToTemp(mediaUrl: String, ext: String): File {
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
            return temp
        } finally {
            conn.disconnect()
        }
    }

    private fun publishMedia(source: File, fileName: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return source.absolutePath
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

    private fun updateProgress(message: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, progressNotification(message))
    }

    private fun completeNotification(title: String, message: String, success: Boolean) {
        ensureChannels(this)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val id = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        manager.notify(id, completeNotificationBuilder(title, message, success))
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

    private fun completeNotificationBuilder(title: String, message: String, success: Boolean): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, COMPLETE_CHANNEL_ID) else Notification.Builder(this)
        return builder
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(if (success) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_notify_error)
            .setContentIntent(launchPendingIntent())
            .setOngoing(false)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_STATUS)
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
        private const val COMPLETE_CHANNEL_ID = "clipora_instant_share_complete"
        private const val NOTIFICATION_ID = 7117
        private const val RESOLVER_URL_META_DATA = "com.threadvault.app.CLIPORA_RESOLVER_URL"

        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Clipora instant saves", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Saves shared links without opening the Clipora screen."
                    setShowBadge(false)
                }
            )
            manager.createNotificationChannel(
                NotificationChannel(COMPLETE_CHANNEL_ID, "Clipora instant save complete", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Shows when a shared link has finished saving."
                    setShowBadge(true)
                }
            )
        }

        private fun extractFirstUrl(raw: String): String? {
            return Regex("https?://[^\\s<>\"]+", RegexOption.IGNORE_CASE)
                .find(raw)
                ?.value
                ?.trim()
                ?.trimEnd(',', '.', ';', ')')
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
                lower.contains("image/png") || lower.contains(".png") -> ".png"
                lower.contains("image/") || lower.contains(".jpg") || lower.contains(".jpeg") -> ".jpg"
                else -> ".mp4"
            }
        }

        private fun safePart(raw: String): String {
            val cleaned = raw.replace(Regex("[^A-Za-z0-9._-]+"), "_").trim('_', '.', '-')
            return cleaned.take(80).ifBlank { "clipora" }
        }
    }
}
