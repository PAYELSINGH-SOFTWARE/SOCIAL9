package com.example.flutter_application_1

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.print.PrintAttributes
import android.print.PrintManager
import android.util.Base64
import android.webkit.WebView
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

/** Disk-backed exports and printing of the real page. No website session is copied. */
class Social9Device(private val activity: Activity, private val engine: FlutterEngine) {
    private data class Export(
        val file: File, val filename: String, val mime: String,
        val stream: FileOutputStream, var bytes: Long = 0, var sequence: Int = 0
    )
    private val handler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val active = mutableMapOf<String, Export>()
    private val saveQueue = ArrayDeque<Export>()
    private var saving: Export? = null
    @Volatile private var closed = false
    private val saveRequest = 21879

    fun register() {
        MethodChannel(engine.dartExecutor.binaryMessenger, "social9/device").setMethodCallHandler { call, result ->
            if (closed) {
                result.error("activity_closed", "Social9 has closed.", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "printCurrentPage" -> {
                    try {
                        val identifier = call.argument<Number>("webViewId")?.toLong() ?: error("Missing view")
                        val plugin = engine.plugins.get(WebViewFlutterPlugin::class.java) as? WebViewFlutterPlugin
                        val view = plugin?.instanceManager?.getInstance<WebView>(identifier) ?: error("Missing view")
                        require(Uri.parse(view.url).scheme == "https")
                        val title = call.argument<String>("title") ?: "Social9 report"
                        val manager = activity.getSystemService(Activity.PRINT_SERVICE) as PrintManager
                        manager.print(title, view.createPrintDocumentAdapter(title), PrintAttributes.Builder().build())
                        result.success(true)
                    } catch (_: Exception) { result.success(false) }
                }
                "openIntent" -> result.success(openIntent(call.argument<String>("url")))
                "startExport", "appendExport", "finishExport", "abortExport" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    io.execute {
                        try {
                            require(!closed)
                            val id = args["id"] as? String ?: error("Missing export")
                            require(id.matches(Regex("[a-zA-Z0-9-]{1,80}")))
                            var finished: Export? = null
                            when (call.method) {
                                "startExport" -> {
                                    require(active.size < 4 && !active.containsKey(id))
                                    val filename = (args["filename"] as? String ?: "social9-export")
                                        .substringAfterLast('/').substringAfterLast('\\').takeLast(180)
                                    val mime = (args["mime"] as? String ?: "application/octet-stream").substringBefore(';')
                                    val file = File.createTempFile("social9-${UUID.randomUUID()}-", ".export", activity.cacheDir)
                                    active[id] = Export(file, filename, mime, FileOutputStream(file))
                                }
                                "appendExport" -> {
                                    val export = active[id] ?: error("Missing export")
                                    val sequence = (args["sequence"] as Number).toInt()
                                    val encoded = args["data"] as String
                                    require(sequence == export.sequence && encoded.length <= 65536)
                                    val bytes = Base64.decode(encoded, Base64.NO_WRAP)
                                    require(bytes.size <= 48 * 1024)
                                    export.stream.write(bytes)
                                    export.bytes += bytes.size
                                    export.sequence++
                                }
                                "finishExport" -> {
                                    val export = active[id] ?: error("Missing export")
                                    require(export.bytes == (args["size"] as Number).toLong())
                                    export.stream.close()
                                    active.remove(id)
                                    finished = export
                                }
                                "abortExport" -> active.remove(id)?.let { it.stream.close(); it.file.delete() }
                            }
                            handler.post {
                                result.success(null)
                                finished?.let {
                                    if (closed) it.file.delete()
                                    else { saveQueue.addLast(it); showSaveDialog() }
                                }
                            }
                        } catch (_: Exception) {
                            handler.post { result.error("export_failed", "Unable to save this export. Check available storage and try again.", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun showSaveDialog() {
        if (closed || saving != null || saveQueue.isEmpty()) return
        val export = saveQueue.removeFirst()
        saving = export
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = export.mime.ifEmpty { "application/octet-stream" }
                putExtra(Intent.EXTRA_TITLE, export.filename)
            }
            activity.startActivityForResult(intent, saveRequest)
        } catch (_: Exception) {
            export.file.delete()
            saving = null
            Toast.makeText(activity, "No app can save this export.", Toast.LENGTH_LONG).show()
            showSaveDialog()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != saveRequest) return false
        if (closed) return true
        val export = saving ?: return true
        saving = null
        val destination = data?.data
        io.execute {
            try {
                if (resultCode == Activity.RESULT_OK && destination != null) {
                    activity.contentResolver.openOutputStream(destination, "w").use { output ->
                        requireNotNull(output)
                        export.file.inputStream().use { input -> input.copyTo(output, 64 * 1024) }
                    }
                }
            } catch (_: Exception) {
                handler.post { Toast.makeText(activity, "Unable to save this export. Please try again.", Toast.LENGTH_LONG).show() }
            } finally {
                export.file.delete()
                handler.post { showSaveDialog() }
            }
        }
        return true
    }

    private fun openIntent(raw: String?): Boolean {
        if (raw == null || !raw.startsWith("intent://")) return false
        return try {
            val parsed = Intent.parseUri(raw, Intent.URI_INTENT_SCHEME)
            val allowed = setOf("upi", "tez", "gpay", "phonepe", "paytmmp", "paytm")
            val fallback = parsed.getStringExtra("browser_fallback_url")
            if (parsed.data?.scheme !in allowed) return false
            parsed.action = Intent.ACTION_VIEW
            parsed.component = null
            parsed.selector = null
            parsed.flags = 0
            parsed.addCategory(Intent.CATEGORY_BROWSABLE)
            parsed.removeExtra("browser_fallback_url")
            try { activity.startActivity(parsed); true }
            catch (_: Exception) {
                val url = fallback?.let { Uri.parse(it) }
                if (url?.scheme == "https" && url.userInfo == null) {
                    activity.startActivity(Intent(Intent.ACTION_VIEW, url)); true
                } else false
            }
        } catch (_: Exception) { false }
    }

    fun close() {
        closed = true
        val queued = saveQueue.toList() + listOfNotNull(saving)
        saveQueue.clear()
        saving = null
        io.execute {
            active.values.forEach { try { it.stream.close() } catch (_: Exception) {} ; it.file.delete() }
            active.clear()
            queued.forEach { it.file.delete() }
        }
        io.shutdown()
    }
}
