Fixtures for the Dart update tests, produced by tool/make_update_manifest.py.

* update.json         the signed manifest, exactly as the release tool writes it
* update.json.sig     base64 of the 64-byte Ed25519 signature, plus a newline
* public_key.txt      base64 of the raw 32-byte public key that verifies it
* android.apk         a tiny stand-in package (a zip with AndroidManifest.xml);
                      the manifest lists its real size and SHA-256
* windows-x64.zip     a tiny stand-in package (app.exe and flutter_windows.dll at
                      the zip root); the manifest lists its real size and SHA-256

The key is a THROWAWAY test key: its seed is SHA-256 of the public string
"update-tools-test-fixture: throwaway key, never a release key". It is not the
release key (release/update_public_key.txt), and nothing real may ever be
signed with it. The manifest and its URLs are those of version 0.2.0, build
2000, tag v0.2.0, with the generic asset names android.apk and windows-x64.zip.

tool/test_update_tools.py checks that these files are consistent (the signature
verifies, the hashes match, re-running the tool on the stored packages gives the
same bytes). To rewrite them, run

    python3 tool/test_update_tools.py --write-fixtures
