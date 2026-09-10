package com.threadvault.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.Toast

class InstantShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    private fun handleShare(intent: Intent?) {
        val urls = extractUrls(intent)
        if (urls.isEmpty()) {
            Toast.makeText(this, "Clipora needs a link to save.", Toast.LENGTH_SHORT).show()
            closeImmediately()
            return
        }

        val serviceIntent = Intent(this, InstantShareDownloadService::class.java).apply {
            putStringArrayListExtra(InstantShareDownloadService.EXTRA_URLS, ArrayList(urls.take(20)))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        Toast.makeText(
            this,
            if (urls.size == 1) "Clipora is saving in the background." else "Clipora is saving ${urls.size} links in the background.",
            Toast.LENGTH_SHORT,
        ).show()
        closeImmediately()
    }

    private fun closeImmediately() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask()
        } else {
            finish()
        }
        overridePendingTransition(0, 0)
    }

    private fun extractUrls(intent: Intent?): List<String> {
        if (intent == null) return emptyList()
        val raw = buildString {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.let { appendLine(it) }
            intent.getStringExtra(Intent.EXTRA_SUBJECT)?.let { appendLine(it) }
            intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.let { appendLine(it) }
            intent.dataString?.let { appendLine(it) }
        }
        if (raw.isBlank()) return emptyList()
        val seen = linkedSetOf<String>()
        Regex("https?://[^\\s<>\"]+", RegexOption.IGNORE_CASE).findAll(raw).forEach { match ->
            val url = match.value.trim().trimEnd(',', '.', ';', ')')
            if (url.isNotBlank()) seen.add(url)
        }
        return seen.toList()
    }

    companion object {
        fun shareIntent(context: Context, urls: ArrayList<String>): Intent = Intent(context, InstantShareActivity::class.java).apply {
            putStringArrayListExtra(InstantShareDownloadService.EXTRA_URLS, urls)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
    }
}
