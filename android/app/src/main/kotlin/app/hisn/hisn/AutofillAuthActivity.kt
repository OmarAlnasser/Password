package app.hisn.hisn

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Runs the Dart `autofillMain` entrypoint: unlock + pick an entry. The
 * selected username/password come back over a method channel and are
 * returned to the system as a Dataset; nothing is stored here.
 */
class AutofillAuthActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun getDartEntrypointFunctionName(): String = "autofillMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlatformChannel.register(flutterEngine, this, null)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.vaultsnap/autofill")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRequest" -> result.success(
                        mapOf(
                            "package" to intent.getStringExtra(EXTRA_PACKAGE),
                            "domain" to intent.getStringExtra(EXTRA_DOMAIN),
                        )
                    )
                    "fill" -> {
                        fill(call.argument<String>("username"), call.argument<String>("password"))
                        result.success(null)
                    }
                    "cancel" -> {
                        setResult(Activity.RESULT_CANCELED)
                        finish()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun fill(username: String?, password: String?) {
        val userId = parcelable<AutofillId>(EXTRA_USERNAME_ID)
        val passId = parcelable<AutofillId>(EXTRA_PASSWORD_ID)
        val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1)
        presentation.setTextViewText(android.R.id.text1, username ?: "Hisn")
        val builder = Dataset.Builder(presentation)
        if (userId != null && username != null) builder.setValue(userId, AutofillValue.forText(username))
        if (passId != null && password != null) builder.setValue(passId, AutofillValue.forText(password))
        val reply = Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, builder.build())
        setResult(Activity.RESULT_OK, reply)
        finish()
    }

    @Suppress("DEPRECATION")
    private inline fun <reified T : android.os.Parcelable> parcelable(key: String): T? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(key, T::class.java)
        else intent.getParcelableExtra(key)

    companion object {
        const val EXTRA_PACKAGE = "hisn.package"
        const val EXTRA_DOMAIN = "hisn.domain"
        const val EXTRA_USERNAME_ID = "hisn.usernameId"
        const val EXTRA_PASSWORD_ID = "hisn.passwordId"
    }
}
