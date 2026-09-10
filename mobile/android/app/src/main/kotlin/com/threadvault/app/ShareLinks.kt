package com.threadvault.app

import android.content.Intent
import android.net.Uri
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

object ShareLinks {
    private val urlPattern = Regex("https?://[^\\s<>\"]+", RegexOption.IGNORE_CASE)
    private val facebookIdPattern = Regex("/(?:reel|reels|videos|watch|share/v|share/r|share/reel)/(?:([A-Za-z0-9_-]+))", RegexOption.IGNORE_CASE)
    private val supportedHosts = listOf(
        "threads.com", "threads.net",
        "tiktok.com", "vm.tiktok.com", "vt.tiktok.com",
        "instagram.com", "instagr.am",
        "x.com", "twitter.com",
        "pinterest.com", "pin.it",
        "facebook.com", "fb.watch", "fb.me",
        "snapchat.com",
        "youtube.com", "youtu.be", "youtube-nocookie.com",
    )

    fun extractFromIntent(intent: Intent?): List<String> {
        if (intent == null) return emptyList()
        val extras = intent.getStringArrayListExtra(InstantShareDownloadService.EXTRA_URLS)
        if (!extras.isNullOrEmpty()) return normalize(extras)
        val raw = buildString {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.let { appendLine(it) }
            intent.getStringExtra(Intent.EXTRA_SUBJECT)?.let { appendLine(it) }
            intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.let { appendLine(it) }
            intent.dataString?.let { appendLine(it) }
        }
        return normalize(extractUrls(raw))
    }

    fun extractUrls(raw: String): List<String> {
        return urlPattern.findAll(raw)
            .map { it.value.trim().trimEnd(',', '.', ';', ')') }
            .filter { it.isNotBlank() }
            .toList()
    }

    fun normalize(urls: List<String>): List<String> {
        val unwrapped = urls.flatMap { extractUrls(it).ifEmpty { listOf(it) } }
            .map { unwrapFacebookClickWrapper(it) }
            .filter { it.isNotBlank() && !isFacebookClickWrapper(it) && isSupported(it) }
        val seen = linkedSetOf<String>()
        val out = mutableListOf<String>()
        for (url in unwrapped) {
            val key = identityKey(url)
            if (seen.add(key)) out.add(url)
        }
        return out.take(20)
    }

    fun unwrapFacebookClickWrapper(url: String): String {
        val uri = Uri.parse(url)
        val path = uri.path?.lowercase(Locale.US) ?: return url
        if (!path.endsWith("/l.php") && !path.endsWith("l.php")) return url
        val dest = uri.getQueryParameter("u") ?: return url
        return if (dest.startsWith("http://") || dest.startsWith("https://")) dest else url
    }

    fun isFacebookClickWrapper(url: String): Boolean {
        val path = Uri.parse(url).path?.lowercase(Locale.US) ?: return false
        return path.endsWith("/l.php") || path.endsWith("l.php")
    }

    fun isSupported(url: String): Boolean {
        val host = Uri.parse(url).host?.lowercase(Locale.US)?.removePrefix("www.") ?: return false
        return supportedHosts.any { host == it || host.endsWith(".$it") } || host.startsWith("pinterest.")
    }

    fun identityKey(url: String): String {
        val uri = Uri.parse(url)
        val host = uri.host?.lowercase(Locale.US)?.removePrefix("www.") ?: return url
        val videoId = uri.getQueryParameter("v")
        if (!videoId.isNullOrBlank() && videoId.length >= 5 && (host.contains("facebook.com") || host.contains("fb.watch"))) {
            return "facebook:id:$videoId"
        }
        facebookIdPattern.find(uri.path ?: "")?.groupValues?.getOrNull(1)?.let { id ->
            if (host.contains("facebook.com") || host.contains("fb.watch") || host.contains("fb.me")) {
                return "facebook:id:$id"
            }
        }
        return "$host${uri.path ?: ""}".lowercase(Locale.US)
    }
}

object ShareJobs {
    private val recent = ConcurrentHashMap<String, Long>()
    private const val WINDOW_MS = 12_000L

    fun claim(urls: List<String>): Boolean {
        val key = urls.sorted().joinToString("\n")
        val now = System.currentTimeMillis()
        recent.entries.removeIf { now - it.value > WINDOW_MS }
        return recent.putIfAbsent(key, now) == null
    }
}
