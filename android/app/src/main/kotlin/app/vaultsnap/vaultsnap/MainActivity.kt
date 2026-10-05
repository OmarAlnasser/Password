package app.vaultsnap.vaultsnap

import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
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
                        val clip = ClipData.newPlainText("VaultSnap", text)
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
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                cm.clearPrimaryClip()
                            } else {
                                cm.setPrimaryClip(ClipData.newPlainText("", ""))
                            }
                        }
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
}
