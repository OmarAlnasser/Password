package app.hisn.hisn

import androidx.core.content.FileProvider

/**
 * Hands the system package installer read access to the verified update APK
 * in `<cache>/updates/` (see res/xml/update_paths.xml and [ApkInstaller]).
 *
 * A subclass of its own, and not androidx's FileProvider named directly in the
 * manifest, so it cannot collide with a FileProvider that a plugin declares:
 * the manifest merger treats two providers with the same class name as one.
 */
class UpdateFileProvider : FileProvider()
