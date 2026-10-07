package app.vaultsnap.vaultsnap

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Hands a downloaded update APK to the system package installer.
 *
 * The Dart side has already checked the manifest signature and the file's
 * SHA-256. This is the second line of defence, on the platform's own terms:
 * the APK must sit in our private `updates` folder, must be a newer build of
 * this very package, and must be signed by the key that signed the installed
 * app. Android's installer enforces the same-key rule again, so a mismatch
 * here only gives the user a clear message before the installer shows its own.
 *
 * Error codes (lib/services/update/android_installer.dart maps them):
 * `bad_arguments`, `permission_denied`, `busy`, `path_not_allowed`,
 * `apk_unreadable`, `wrong_package`, `not_newer`, `signature_mismatch`,
 * `no_installer`, `install_failed`; the channel adds `unsupported` (not the
 * main activity) and `updates_dir_unavailable`. Messages are fixed texts: no
 * paths or other user data, because errors reach logs.
 */
object ApkInstaller {
    /** Sub-folder of the app's cache dir. Must match res/xml/update_paths.xml. */
    private const val UPDATES_DIR = "updates"

    private const val APK_MIME = "application/vnd.android.package-archive"

    /** The Dart side caps the download at the same size. */
    private const val MAX_APK_BYTES = 400L * 1024 * 1024

    /**
     * The installer copies the file into its own staging area within seconds
     * of starting; after this long our copy is no longer needed.
     */
    private const val STALE_AGE_MS = 2L * 60 * 1000

    private const val MAX_URL_LENGTH = 512

    /** `/<owner>/<repo>/releases`, optionally followed by plain path segments. */
    private val RELEASE_PAGE_PATH =
        Regex("^/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/releases(/[A-Za-z0-9._~%-]+)*/?$")

    private val busy = AtomicBoolean(false)

    private class Rejection(val code: String, message: String) : Exception(message)

    /** Whether the user has allowed this app to install packages (API 26+). */
    fun canInstall(context: Context): Boolean =
        context.packageManager.canRequestPackageInstalls()

    /**
     * Opens "Install unknown apps" for this app. False when the device has no
     * such screen.
     */
    fun openInstallSettings(activity: Activity): Boolean {
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.fromParts("package", activity.packageName, null),
        )
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /**
     * Opens the release page in the browser so the user can install by hand
     * when an in-app install is impossible. Accepts only an https address on
     * github.com under `/<owner>/<repo>/releases`, with no port and no
     * credentials (the Dart side checks the same and also pins the
     * repository); anything else is refused. False when it was refused or the
     * device has no browser.
     */
    fun openReleasePage(activity: Activity, rawUrl: String?): Boolean {
        if (rawUrl.isNullOrEmpty() || rawUrl.length > MAX_URL_LENGTH) return false
        val uri = Uri.parse(rawUrl)
        val path = uri.encodedPath ?: return false
        if (!"https".equals(uri.scheme, ignoreCase = true) ||
            !"github.com".equals(uri.host, ignoreCase = true) ||
            uri.port != -1 ||
            uri.userInfo != null ||
            !RELEASE_PAGE_PATH.matches(path)
        ) {
            return false
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    /**
     * The folder the update APK must be copied into, created empty (anything
     * left from an earlier attempt is deleted) and closed to other apps.
     */
    @Throws(IOException::class)
    fun prepareUpdatesDir(context: Context): File {
        val dir = File(context.cacheDir, UPDATES_DIR)
        dir.listFiles()?.forEach { it.delete() }
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("updates folder")
        dir.setReadable(false, false)
        dir.setWritable(false, false)
        dir.setExecutable(false, false)
        dir.setReadable(true, true)
        dir.setWritable(true, true)
        dir.setExecutable(true, true)
        return dir
    }

    /**
     * Deletes update copies older than [STALE_AGE_MS] from the cache dir: the
     * one the installer used before this process started, or one left by a
     * download that never reached the installer.
     */
    fun deleteStaleUpdates(cacheDir: File) {
        Thread {
            val cutoff = System.currentTimeMillis() - STALE_AGE_MS
            File(cacheDir, UPDATES_DIR).listFiles()?.forEach { f ->
                if (f.isFile && f.lastModified() < cutoff) f.delete()
            }
        }.start()
    }

    /**
     * Checks the APK at [rawPath] and starts the system installer for it. The
     * checks run on a worker thread (reading a large APK takes a moment); the
     * result is answered on the main thread, as soon as the installer screen
     * has been started. The install itself is finished by the user in the
     * system UI, and Android then restarts the app.
     *
     * With [verifyOnly] it stops after the checks and answers "verified": the
     * Dart side uses that to find out whether the update can be installed
     * before it locks the vault, and then calls again without it. Every call
     * runs all checks, so the file is checked again right before it is handed
     * over.
     */
    fun installApk(
        activity: Activity,
        rawPath: String?,
        verifyOnly: Boolean,
        result: MethodChannel.Result,
    ) {
        if (rawPath.isNullOrEmpty()) {
            result.error("bad_arguments", "path is missing", null)
            return
        }
        if (!canInstall(activity)) {
            result.error("permission_denied", "installing apps is not allowed", null)
            return
        }
        if (!busy.compareAndSet(false, true)) {
            result.error("busy", "an update is already being prepared", null)
            return
        }
        Thread {
            val checked = runCatching { verify(activity, rawPath) }
            activity.runOnUiThread {
                try {
                    val failure = checked.exceptionOrNull()
                    if (failure != null) {
                        // Only our own fixed texts leave here; the message of
                        // another exception could contain the file's path.
                        val rejection = failure as? Rejection
                        result.error(
                            rejection?.code ?: "apk_unreadable",
                            rejection?.message ?: "update file cannot be checked",
                            null,
                        )
                    } else if (verifyOnly) {
                        result.success("verified")
                    } else {
                        launch(activity, checked.getOrThrow(), result)
                    }
                } finally {
                    busy.set(false)
                }
            }
        }.start()
    }

    /**
     * Returns the canonical APK file when it passes every check, otherwise
     * throws a [Rejection] with the code to report.
     */
    @Suppress("DEPRECATION") // int-flag overloads, API 33; they work on API 26-37
    private fun verify(context: Context, rawPath: String): File {
        // Canonical paths resolve "..", symlinks and relative parts, so nothing
        // outside our own folder can get through, and nothing nested in it.
        val dir = File(context.cacheDir, UPDATES_DIR).canonicalFile
        val file = File(rawPath).canonicalFile
        if (file.parentFile != dir) {
            throw Rejection("path_not_allowed", "update file is outside the updates folder")
        }
        if (!file.isFile || !file.canRead()) {
            throw Rejection("apk_unreadable", "update file cannot be read")
        }
        val size = file.length()
        if (size <= 0L || size > MAX_APK_BYTES) {
            throw Rejection("apk_unreadable", "update file has an unexpected size")
        }

        val pm = context.packageManager
        // Parses the APK and, with the signing flag, verifies its signature
        // scheme blocks. Null when it is not a valid, correctly signed APK.
        val archive = pm.getPackageArchiveInfo(file.path, signingFlag())
            ?: throw Rejection("apk_unreadable", "update file is not a valid package")
        if (archive.packageName != context.packageName) {
            throw Rejection("wrong_package", "update is for a different app")
        }

        val installed = try {
            pm.getPackageInfo(context.packageName, signingFlag())
        } catch (e: PackageManager.NameNotFoundException) {
            throw Rejection("install_failed", "installed app info is unavailable")
        }
        if (versionCodeOf(archive) <= versionCodeOf(installed)) {
            throw Rejection("not_newer", "update is not newer than the installed app")
        }

        // Every certificate the installed app is signed with must also be one
        // the update vouches for (its own, or an earlier one in its rotation
        // lineage). Empty sets mean the platform gave no certificates: refuse.
        val ownSigners = signerDigests(installed, includeLineage = false)
        val updateSigners = signerDigests(archive, includeLineage = true)
        if (ownSigners.isEmpty() || !updateSigners.containsAll(ownSigners)) {
            throw Rejection("signature_mismatch", "update is signed with a different key")
        }

        // Nothing should write to it from here on; the installer only reads.
        file.setReadOnly()
        return file
    }

    /**
     * API 28 and later ask for both lists: some platform releases do not fill
     * `signingInfo` when an APK file is parsed with getPackageArchiveInfo, and
     * [signerDigests] then falls back to the legacy list.
     */
    @Suppress("DEPRECATION") // GET_SIGNATURES, replaced by GET_SIGNING_CERTIFICATES in API 28
    private fun signingFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES
        } else {
            PackageManager.GET_SIGNATURES
        }

    @Suppress("DEPRECATION") // versionCode, replaced by longVersionCode in API 28
    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }

    /**
     * Lower-case hex SHA-256 digests of the package's signing certificates.
     * With [includeLineage], a single-signer package also counts the earlier
     * certificates it proves with a key rotation (API 28+). When the platform
     * gives no `signingInfo` certificates, the legacy `signatures` list is used
     * (the app's key is never rotated, so nothing is lost).
     */
    @Suppress("DEPRECATION") // PackageInfo.signatures, the legacy list
    private fun signerDigests(info: PackageInfo, includeLineage: Boolean): Set<String> {
        val certs: Array<Signature>? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signing = info.signingInfo
                val modern: Array<Signature>? = when {
                    signing == null -> null
                    signing.hasMultipleSigners() -> signing.apkContentsSigners
                    includeLineage -> signing.signingCertificateHistory
                    else -> signing.apkContentsSigners
                }
                if (modern == null || modern.isEmpty()) info.signatures else modern
            } else {
                info.signatures
            }
        if (certs == null) return emptySet()
        val sha256 = MessageDigest.getInstance("SHA-256")
        return certs.mapTo(HashSet()) { cert ->
            sha256.digest(cert.toByteArray()).joinToString("") { b ->
                (b.toInt() and 0xff).toString(16).padStart(2, '0')
            }
        }
    }

    /** Starts the system installer for the checked [apk] and answers [result]. */
    @Suppress("DEPRECATION") // ACTION_INSTALL_PACKAGE, API 29; kept as a fallback
    private fun launch(activity: Activity, apk: File, result: MethodChannel.Result) {
        val uri = try {
            FileProvider.getUriForFile(activity, activity.packageName + ".updates", apk)
        } catch (e: IllegalArgumentException) {
            result.error("install_failed", "update file cannot be shared with the installer", null)
            return
        }
        for (action in listOf(Intent.ACTION_VIEW, Intent.ACTION_INSTALL_PACKAGE)) {
            val intent = Intent(action)
                .setDataAndType(uri, APK_MIME)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            try {
                activity.startActivity(intent)
                result.success("installer_started")
                return
            } catch (e: ActivityNotFoundException) {
                // Try the next action.
            } catch (e: SecurityException) {
                result.error("install_failed", "the installer refused to start", null)
                return
            }
        }
        result.error("no_installer", "no installer is available on this device", null)
    }
}
