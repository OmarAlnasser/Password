/// Khazna crypto layer. Import this file rather than individual parts.
library;

import 'package:sodium/sodium_sumo.dart';

export 'base32.dart';
export 'crypto_exceptions.dart';
export 'kdf_params.dart';
export 'key_hierarchy.dart';
export 'recovery_key.dart';
export 'secure_bytes.dart';
export 'totp.dart';
export 'vault_crypto.dart';

/// Loads the libsodium build bundled by `package:sodium` (the sumo variant,
/// which is the one that includes Argon2id `crypto_pwhash`).
Future<SodiumSumo> loadSodium() async => await SodiumSumoInit.init();
