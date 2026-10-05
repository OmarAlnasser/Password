import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/crypto/crypto.dart';
import 'vault_session.dart';

/// Keeps the iOS AutoFill extension's encrypted snapshot up to date.
///
/// Every time the unlocked vault changes, a fresh random 256-bit key is
/// generated, the (host, username, password) list is sealed with it
/// (XChaCha20-Poly1305, context "autofill-snapshot") and both are handed to
/// native code: the key goes into the shared Keychain behind
/// `.biometryCurrentSet`, the ciphertext into the App Group container.
class IosAutofillSnapshot {
  IosAutofillSnapshot(this._session) {
    if (!Platform.isIOS) return;
    _session.addListener(_schedule);
  }

  static const _ch = MethodChannel('app.vaultsnap/platform');
  final VaultSession _session;
  Timer? _debounce;

  void _schedule() {
    if (!_session.isUnlocked) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () => unawaited(update()));
  }

  Future<void> update() async {
    if (!_session.isUnlocked) return;
    final entries = _session.entries
        .where((e) => e.host.isNotEmpty && e.password.isNotEmpty)
        .toList();
    final pt = Uint8List.fromList(
      utf8.encode(
        jsonEncode([
          for (final e in entries)
            {
              'id': e.id,
              'title': e.title,
              'user': e.username,
              'pass': e.password,
              'host': e.host,
            },
        ]),
      ),
    );
    final crypto = _session.crypto;
    final key = crypto.randomKey();
    try {
      final sealed = crypto.seal(pt, key, 'autofill-snapshot');
      final raw = key.extractBytes();
      try {
        await _ch.invokeMethod<bool>('storeAutofillSnapshot', {
          'key': raw,
          'snapshot': sealed,
          'identities': [
            for (final e in entries)
              {'id': e.id, 'host': e.host, 'user': e.username},
          ],
        });
      } finally {
        wipe(raw);
      }
    } finally {
      wipe(pt);
      key.dispose();
    }
  }

  Future<void> clear() async {
    if (!Platform.isIOS) return;
    await _ch.invokeMethod<bool>('clearAutofill');
  }
}
