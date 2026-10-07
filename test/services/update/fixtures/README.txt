Fixture for update_fixture_test.dart: a manifest, its signature and the
public key, all produced OUTSIDE Dart (python3 + the `cryptography` package,
Ed25519), so the test proves that the Dart verifier accepts what the Python
release tooling signs.

* update.json            the exact bytes that were signed (UTF-8, with Arabic
                         text, 2-space indent, trailing newline)
* update.json.sig        base64 of the raw 64-byte Ed25519 signature, no newline
* fixture_public_key.txt base64 of the raw 32-byte public key

The key is a THROWAWAY test key (its seed is the SHA-256 of a public string).
It is not the release key (release/update_public_key.txt) and must never be
used for anything real. The assets named in the manifest are not stored:
the tests serve payload(3000, seed 1) and payload(5000, seed 2) from
update_test_kit.dart, whose bytes ((i * 31 + seed) & 0xff) the generator also
used to compute the sizes and SHA-256 values.

To regenerate (only needed if the manifest schema changes), sign any manifest
with tool/make_update_manifest.py and a throwaway key, and put the three files
here.
