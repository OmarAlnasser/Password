package app.hisn.hisn

import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID

/**
 * FlutterFragmentActivity (not FlutterActivity) because BiometricPrompt used
 * by local_auth / biometric_storage requires a FragmentActivity.
 */
class MainActivity : FlutterFragmentActivity() {
    private var pendingPick: MethodChannel.Result? = null
    private var pendingDelete: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Block screenshots, screen recording, casting and the recents
        // thumbnail before any content is drawn.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
        PlatformChannel.deleteStaleImageCopies(cacheDir)
        ApkInstaller.deleteStaleUpdates(cacheDir)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlatformChannel.register(flutterEngine, this, object : PlatformChannel.Host {
            override fun pickImage(result: MethodChannel.Result) {
                pendingPick = result
                val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                    .setType("image/*")
                startActivityForResult(intent, REQ_PICK)
            }

            override fun deleteImage(uri: Uri, result: MethodChannel.Result) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Android 11+: the system shows its own confirmation.
                    pendingDelete = result
                    val req = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
                    startIntentSenderForResult(req.intentSender, REQ_DELETE, null, 0, 0, 0)
                } else {
                    result.success(
                        try { contentResolver.delete(uri, null, null) > 0 } catch (e: SecurityException) { false }
                    )
                }
            }
        })
    }

    @Deprecated("Uses startActivityForResult for compatibility with API 21+")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_PICK -> {
                val result = pendingPick ?: return
                pendingPick = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return
                }
                // Copy to our private cache for OCR; Dart deletes it after.
                val out = File(cacheDir, "ocr-${UUID.randomUUID()}.img")
                contentResolver.openInputStream(uri)?.use { input ->
                    out.outputStream().use { input.copyTo(it) }
                }
                result.success(mapOf("path" to out.absolutePath, "uri" to uri.toString()))
            }
            REQ_DELETE -> {
                pendingDelete?.success(resultCode == Activity.RESULT_OK)
                pendingDelete = null
            }
        }
    }

    companion object {
        private const val REQ_PICK = 4101
        private const val REQ_DELETE = 4102
    }
}

/** Channel shared by MainActivity and AutofillAuthActivity. */
object PlatformChannel {
    interface Host {
        fun pickImage(result: MethodChannel.Result)
        fun deleteImage(uri: Uri, result: MethodChannel.Result)
    }

    private var lastCopied: String? = null

    fun register(engine: FlutterEngine, activity: Activity, host: Host?) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.vaultsnap/platform")
            .setMethodCallHandler { call, result ->
                val cm = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                when (call.method) {
                    "copySensitive" -> {
                        val text = call.argument<String>("text") ?: ""
                        val clip = ClipData.newPlainText("Khazna", text)
                        // Hide from the clipboard preview / keyboard
                        // suggestions (Android 13+; the string key works on 12L-).
                        val extras = PersistableBundle()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            extras.putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                        } else {
                            extras.putBoolean("android.content.extra.IS_SENSITIVE", true)
                        }
                        clip.description.extras = extras
                        cm.setPrimaryClip(clip)
                        lastCopied = text
                        result.success(true)
                    }
                    "clearClipboardIfMatches" -> {
                        val text = call.argument<String>("text")
                        // Reading the clipboard is only allowed while we are in
                        // the foreground; when backgrounded we compare against
                        // what we last set and clear unconditionally on 28+.
                        val current = try {
                            cm.primaryClip?.getItemAt(0)?.text?.toString()
                        } catch (e: Exception) { null }
                        // Clear if it still holds our secret, or if we cannot
                        // read it (backgrounded, Android 10+) and our secret
                        // was the last thing we put there.
                        if (current == text || (current == null && lastCopied == text)) {
                            clearPrimaryClip(cm)
                        }
                        lastCopied = null
                        result.success(true)
                    }
                    "readClipboard" -> readClipboard(activity, cm, result)
                    "clearClipboard" -> {
                        clearPrimaryClip(cm)
                        lastCopied = null
                        result.success(true)
                    }
                    "setSecureScreen" -> {
                        val on = call.argument<Boolean>("enabled") ?: true
                        activity.runOnUiThread {
                            if (on) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    // In-app update (lib/services/update/android_installer.dart).
                    // Only the main activity may install: the autofill
                    // activity registers this channel without a host.
                    "canInstallPackages" ->
                        result.success(host != null && ApkInstaller.canInstall(activity))
                    "openInstallSettings" ->
                        result.success(host != null && ApkInstaller.openInstallSettings(activity))
                    // The GitHub release page, for installing by hand.
                    "openReleasePage" ->
                        result.success(
                            host != null && ApkInstaller.openReleasePage(activity, call.argument<String>("url")),
                        )
                    "prepareUpdatesDir" -> {
                        if (host == null) {
                            result.error("unsupported", "not available here", null)
                        } else {
                            try {
                                result.success(ApkInstaller.prepareUpdatesDir(activity).path)
                            } catch (e: IOException) {
                                result.error("updates_dir_unavailable", "cannot prepare the updates folder", null)
                            }
                        }
                    }
                    "installApk" -> {
                        if (host == null) {
                            result.error("unsupported", "not available here", null)
                        } else {
                            ApkInstaller.installApk(
                                activity,
                                call.argument<String>("path"),
                                call.argument<Boolean>("verifyOnly") ?: false,
                                result,
                            )
                        }
                    }
                    "pickImage" -> host?.pickImage(result) ?: result.success(null)
                    "deleteImage" -> {
                        val raw = call.argument<String>("uri") ?: ""
                        if (raw.startsWith("content://") && host != null) {
                            host.deleteImage(Uri.parse(raw), result)
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private const val MAX_CLIP_IMAGE_BYTES = 64L * 1024 * 1024
    private const val STALE_COPY_AGE_MS = 10L * 60 * 1000

    /**
     * Deletes screenshot copies (clip-*.img from Paste, ocr-*.img from the OCR
     * import) left in [dir] when the app died before Dart could delete them.
     * Recent ones may still be read by an OCR pass and are kept.
     */
    fun deleteStaleImageCopies(dir: File) {
        Thread {
            val cutoff = System.currentTimeMillis() - STALE_COPY_AGE_MS
            dir.listFiles()?.forEach { f ->
                val ours = (f.name.startsWith("clip-") || f.name.startsWith("ocr-")) &&
                    f.name.endsWith(".img")
                if (ours && f.isFile && f.lastModified() < cutoff) f.delete()
            }
        }.start()
    }

    private fun clearPrimaryClip(cm: ClipboardManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            cm.clearPrimaryClip()
        } else {
            cm.setPrimaryClip(ClipData.newPlainText("", ""))
        }
    }

    /**
     * For the "Paste" button: a copied image (screenshot) is copied to our
     * private cache and returned as "imagePath" (Dart deletes it after OCR),
     * otherwise the clip's "text". Android 10+ only hands out the clip while
     * we have window focus, which we do: the user just tapped Paste.
     */
    private fun readClipboard(activity: Activity, cm: ClipboardManager, result: MethodChannel.Result) {
        val clip = try { cm.primaryClip } catch (e: SecurityException) { null }
        if (clip == null || clip.itemCount == 0) {
            result.success(emptyMap<String, String>())
            return
        }
        val image = (0 until clip.itemCount).firstNotNullOfOrNull { i ->
            clip.getItemAt(i).uri?.takeIf { isForeignContent(activity, it) && isImage(activity, clip.description, it) }
        }
        if (image == null) {
            val item = clip.getItemAt(0)
            val uri = item.uri
            // coerceToText reads a URI-only item's content: never ours.
            val text = if (item.text == null && uri != null && !isForeignContent(activity, uri)) {
                null
            } else {
                try { item.coerceToText(activity)?.toString() } catch (e: Exception) { null }
            }
            // A non-text URI is "coerced" to the URI string itself.
            val usable = !text.isNullOrEmpty() && text != uri?.toString()
            result.success(if (usable) mapOf("text" to text) else emptyMap<String, String?>())
            return
        }
        // We were granted read access to the URI along with the clip. Copy
        // off the main thread: the provider may be slow (e.g. cloud gallery).
        val resolver = activity.contentResolver
        val out = File(activity.cacheDir, "clip-${UUID.randomUUID()}.img")
        Thread {
            val ok = copyLimited(resolver, image, out)
            activity.runOnUiThread {
                result.success(if (ok) mapOf("imagePath" to out.absolutePath) else emptyMap<String, String>())
            }
        }.start()
    }

    /**
     * Only content:// URIs of other apps: any app can put a URI on the
     * clipboard, and a file:// one or one of our own providers would make us
     * read our private files.
     */
    @Suppress("DEPRECATION") // resolveContentProvider(String, Int), API 33
    private fun isForeignContent(activity: Activity, uri: Uri): Boolean {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return false
        val authority = uri.authority ?: return false
        val owner = activity.packageManager.resolveContentProvider(authority, 0)?.packageName
        return owner != activity.packageName
    }

    private fun isImage(activity: Activity, description: ClipDescription, uri: Uri): Boolean {
        val type = try { activity.contentResolver.getType(uri) } catch (e: Exception) { null }
        return type?.startsWith("image/") ?: description.hasMimeType("image/*")
    }

    /** Copies [uri] to [out]; on any failure deletes [out] and returns false. */
    private fun copyLimited(resolver: ContentResolver, uri: Uri, out: File): Boolean {
        try {
            val input = resolver.openInputStream(uri) ?: return false
            input.use { src ->
                out.outputStream().use { dst ->
                    val buf = ByteArray(64 * 1024)
                    var total = 0L
                    var n = src.read(buf)
                    while (n >= 0) {
                        total += n
                        if (total > MAX_CLIP_IMAGE_BYTES) throw IOException("clipboard image too large")
                        dst.write(buf, 0, n)
                        n = src.read(buf)
                    }
                }
            }
            return true
        } catch (e: Exception) {
            out.delete()
            return false
        }
    }
}
