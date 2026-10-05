package app.vaultsnap.vaultsnap

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.widget.RemoteViews

/**
 * Android Autofill Service.
 *
 * The service itself never holds keys or plaintext. For every fill request
 * it returns one locked "Unlock VaultSnap" dataset whose authentication
 * intent opens [AutofillAuthActivity]; that activity unlocks the vault
 * (biometrics / master password), lets the user pick a matching entry and
 * returns the filled dataset to the system.
 *
 * Phishing protection: `webDomain` in the view structure is set by the
 * requesting app and can be forged by any app, so it is only trusted when
 * the requesting package is a known browser. For other apps we match on the
 * package name only (entries with URL `androidapp://<package>`).
 */
class VaultSnapAutofillService : AutofillService() {

    data class Fields(
        val username: AutofillId?,
        val password: AutofillId?,
        val webDomain: String?,
    )

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }
        val pkg = structure.activityComponent.packageName
        if (pkg == packageName) { // never fill into ourselves
            callback.onSuccess(null)
            return
        }
        val fields = parse(structure)
        val ids = listOfNotNull(fields.username, fields.password)
        if (ids.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val trustedDomain = if (pkg in TRUSTED_BROWSERS) fields.webDomain else null
        val auth = Intent(this, AutofillAuthActivity::class.java)
            .putExtra(AutofillAuthActivity.EXTRA_PACKAGE, pkg)
            .putExtra(AutofillAuthActivity.EXTRA_DOMAIN, trustedDomain)
            .putExtra(AutofillAuthActivity.EXTRA_USERNAME_ID, fields.username)
            .putExtra(AutofillAuthActivity.EXTRA_PASSWORD_ID, fields.password)
        val sender = PendingIntent.getActivity(
            this,
            REQUEST_CODE,
            auth,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ).intentSender

        val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1)
        presentation.setTextViewText(android.R.id.text1, "Unlock VaultSnap")

        @Suppress("DEPRECATION")
        val response = FillResponse.Builder()
            .setAuthentication(ids.toTypedArray(), sender, presentation)
            .build()
        callback.onSuccess(response)
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Saving from other apps is not supported; entries are created in-app.
        callback.onSuccess()
    }

    private fun parse(structure: AssistStructure): Fields {
        var user: AutofillId? = null
        var pass: AutofillId? = null
        var domain: String? = null
        fun visit(node: AssistStructure.ViewNode) {
            if (domain == null && !node.webDomain.isNullOrEmpty()) domain = node.webDomain
            val hints = node.autofillHints?.map { it.lowercase() } ?: emptyList()
            val idHint = (node.idEntry ?: "").lowercase() + " " + (node.hint ?: "").lowercase()
            val isPassword = View.AUTOFILL_HINT_PASSWORD in hints ||
                (node.inputType and InputType.TYPE_TEXT_VARIATION_PASSWORD) ==
                InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                (node.inputType and InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD) ==
                InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                "password" in idHint
            val isUser = View.AUTOFILL_HINT_USERNAME in hints ||
                View.AUTOFILL_HINT_EMAIL_ADDRESS in hints ||
                (node.inputType and InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS) ==
                InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
                "user" in idHint || "email" in idHint || "login" in idHint
            val id = node.autofillId
            if (id != null && node.autofillType == View.AUTOFILL_TYPE_TEXT) {
                if (isPassword && pass == null) pass = id
                else if (isUser && user == null) user = id
            }
            for (i in 0 until node.childCount) visit(node.getChildAt(i))
        }
        for (i in 0 until structure.windowNodeCount) visit(structure.getWindowNodeAt(i).rootViewNode)
        return Fields(user, pass, domain)
    }

    companion object {
        private const val REQUEST_CODE = 7301

        /** Browsers whose reported webDomain we trust. */
        val TRUSTED_BROWSERS = setOf(
            "com.android.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "org.mozilla.firefox",
            "org.mozilla.firefox_beta",
            "com.microsoft.emmx",
            "com.brave.browser",
            "com.sec.android.app.sbrowser",
            "com.duckduckgo.mobile.android",
        )
    }
}
