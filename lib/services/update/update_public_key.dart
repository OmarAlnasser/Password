/// The Ed25519 public key that every `update.json` must be signed with.
///
/// Base64 of the raw 32 bytes. It is pinned in the app on purpose: whoever
/// controls the GitHub account or the release assets still cannot make an
/// installed app accept a manifest, because they do not have the matching
/// private key (it lives only in the `UPDATE_SIGNING_KEY` GitHub secret).
///
/// Must equal `release/update_public_key.txt`; a test checks it. To rotate the
/// key, ship an app version that trusts the new key before signing with it.
const String updatePublicKeyBase64 =
    'OmQm+7K4vp3mVjAj2QbCzJJ9ORNemHI/VTrC73SUYjE=';
