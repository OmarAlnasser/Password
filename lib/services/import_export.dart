import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:sodium/sodium_sumo.dart';

import '../core/crypto/crypto.dart';
import '../data/models/vault_entry.dart';
import 'vault_session.dart';

class ImportException implements Exception {
  const ImportException(this.message);
  final String message;
  @override
  String toString() => 'ImportException: $message';
}

/// Result of parsing an import: entries plus a count of rows skipped.
class ImportResult {
  const ImportResult(this.entries, this.skipped);
  final List<VaultEntry> entries;
  final int skipped;
}

/// Encrypted export / import and CSV import.
///
/// Export file (JSON):
///   { "format": "vaultsnap-export", "v": 1, "kdf": {..}, "salt": b64,
///     "data": b64(envelope) }
/// key = BLAKE2b("VSnapEXP", Argon2id(NFKC(exportPassword), salt)),
/// envelope = XChaCha20-Poly1305 over the JSON entry list, context "export".
/// The export password is separate from the master password so a leaked
/// export file is not an oracle for the account password.
class ImportExport {
  ImportExport(this.crypto);

  final VaultCrypto crypto;

  static const ctxExport = 'VSnapEXP';
  static const int maxImportBytes = 32 * 1024 * 1024;
  static const int maxEntries = 50000;
  static const int maxFieldLength = 64 * 1024;

  Future<String> exportEncrypted(
    List<VaultEntry> entries,
    String exportPassword,
  ) async {
    final salt = crypto.newSalt();
    final key = await _exportKey(exportPassword, salt, KdfParams.recommended);
    final pt = Uint8List.fromList(
      utf8.encode(jsonEncode(entries.map((e) => e.toJson()).toList())),
    );
    try {
      final env = crypto.seal(pt, key, 'export');
      return jsonEncode({
        'format': 'vaultsnap-export',
        'v': 1,
        'kdf': KdfParams.recommended.toJson(),
        'salt': base64.encode(salt),
        'data': base64.encode(env),
      });
    } finally {
      wipe(pt);
      key.dispose();
    }
  }

  Future<ImportResult> importEncrypted(
    String file,
    String exportPassword,
  ) async {
    if (file.length > maxImportBytes) {
      throw const ImportException('File too large');
    }
    final Map<String, Object?> j;
    final KdfParams kdf;
    final Uint8List salt, env;
    try {
      j = (jsonDecode(file) as Map).cast<String, Object?>();
      if (j['format'] != 'vaultsnap-export' || j['v'] != 1) {
        throw const ImportException('Not a Khazna export');
      }
      kdf = KdfParams.fromJson((j['kdf']! as Map).cast());
      salt = base64.decode(j['salt']! as String);
      env = base64.decode(j['data']! as String);
    } on ImportException {
      rethrow;
    } on WeakKdfParamsException {
      throw const ImportException('Export uses unsafe KDF parameters');
    } on Object {
      throw const ImportException('Malformed export file');
    }
    if (salt.length != VaultCrypto.saltBytes) {
      throw const ImportException('Malformed export file');
    }
    final key = await _exportKey(exportPassword, salt, kdf);
    Uint8List? pt;
    try {
      pt = crypto.open(env, key, 'export');
    } on VaultCryptoException {
      throw const ImportException('Wrong password or corrupted file');
    } finally {
      key.dispose();
    }
    try {
      final list = jsonDecode(utf8.decode(pt)) as List;
      if (list.length > maxEntries) throw const ImportException('Too many');
      var skipped = 0;
      final out = <VaultEntry>[];
      for (final item in list) {
        try {
          out.add(
            _sanitize(VaultEntry.fromJson((item as Map).cast()), freshId: true),
          );
        } on Object {
          skipped++;
        }
      }
      return ImportResult(out, skipped);
    } on ImportException {
      rethrow;
    } on Object {
      throw const ImportException('Malformed export contents');
    } finally {
      wipe(pt);
    }
  }

  Future<SecureKey> _exportKey(String pw, Uint8List salt, KdfParams kdf) async {
    final bytes = VaultCrypto.passwordBytes(pw);
    try {
      final master = await crypto.deriveMasterKeyInBackground(
        passwordUtf8: bytes,
        salt: salt,
        params: kdf,
      );
      try {
        return crypto.deriveSubkey(master, ctxExport);
      } finally {
        master.dispose();
      }
    } finally {
      wipe(bytes);
    }
  }

  /// Parses a Chrome / Edge or Bitwarden CSV export.
  ///
  /// Chrome:    name,url,username,password,note
  /// Bitwarden: folder,favorite,type,name,notes,fields,reprompt,login_uri,
  ///            login_username,login_password,login_totp
  ImportResult importCsv(String text) {
    if (text.length > maxImportBytes) {
      throw const ImportException('File too large');
    }
    // dynamicTyping must stay off: otherwise a password like "0123" or
    // "true" would be silently converted to a number/boolean.
    final List<List<dynamic>> rows;
    try {
      rows = Csv(
        autoDetect: false,
        dynamicTyping: false,
      ).decode(text.startsWith('﻿') ? text.substring(1) : text);
    } on Object {
      throw const ImportException('Malformed CSV');
    }
    if (rows.isEmpty) throw const ImportException('Empty CSV');
    final header = rows.first.map((c) => '$c'.trim().toLowerCase()).toList();
    int col(String name) => header.indexOf(name);
    final isBitwarden = col('login_password') >= 0;
    final isChrome = col('password') >= 0 && col('username') >= 0;
    if (!isBitwarden && !isChrome) {
      throw const ImportException('Unrecognised CSV format');
    }
    if (rows.length - 1 > maxEntries) throw const ImportException('Too many');

    String cell(List<dynamic> row, String name) {
      final i = col(name);
      return i >= 0 && i < row.length ? '${row[i]}' : '';
    }

    final out = <VaultEntry>[];
    var skipped = 0;
    for (final row in rows.skip(1)) {
      try {
        if (isBitwarden && cell(row, 'type') != 'login') {
          skipped++;
          continue;
        }
        final entry = isBitwarden
            ? VaultEntry(
                id: VaultSession.newId(),
                title: cell(row, 'name'),
                username: cell(row, 'login_username'),
                password: cell(row, 'login_password'),
                url: cell(row, 'login_uri').split(',').first,
                notes: cell(row, 'notes'),
                totpSecret: cell(row, 'login_totp'),
                favorite: cell(row, 'favorite') == '1',
                tags: [if (cell(row, 'folder').isNotEmpty) cell(row, 'folder')],
              )
            : VaultEntry(
                id: VaultSession.newId(),
                title: cell(row, 'name'),
                username: cell(row, 'username'),
                password: cell(row, 'password'),
                url: cell(row, 'url'),
                notes: cell(row, 'note'),
              );
        if (entry.password.isEmpty && entry.username.isEmpty) {
          skipped++;
          continue;
        }
        out.add(_sanitize(entry));
      } on Object {
        skipped++;
      }
    }
    return ImportResult(out, skipped);
  }

  /// Enforces field limits and strips control characters that could hide
  /// content in the UI (bidi overrides, NUL, etc.).
  VaultEntry _sanitize(VaultEntry e, {bool freshId = false}) {
    String clean(String s, {bool multiline = false}) {
      var out = s.replaceAll(
        RegExp(
          multiline
              ? '[\u0000-\u0008\u000B-\u001F\u007F\u202A-\u202E\u2066-\u2069]'
              : '[\u0000-\u001F\u007F\u202A-\u202E\u2066-\u2069]',
        ),
        '',
      );
      if (out.length > maxFieldLength) out = out.substring(0, maxFieldLength);
      return out;
    }

    final url = clean(e.url).trim();
    final lowerUrl = url.toLowerCase();
    return VaultEntry(
      id: freshId ? VaultSession.newId() : e.id,
      title: clean(e.title).trim().isEmpty ? e.host : clean(e.title).trim(),
      username: clean(e.username),
      password: clean(e.password),
      // Only keep web-ish URLs; drop javascript:, data:, file: etc. so a
      // malicious import cannot plant a link that runs code when opened.
      url:
          (lowerUrl.startsWith('javascript:') ||
              lowerUrl.startsWith('data:') ||
              lowerUrl.startsWith('file:') ||
              lowerUrl.startsWith('vbscript:'))
          ? ''
          : url,
      notes: clean(e.notes, multiline: true),
      tags: e.tags
          .map((t) => clean(t).trim())
          .where((t) => t.isNotEmpty)
          .take(20)
          .toList(),
      favorite: e.favorite,
      totpSecret: clean(e.totpSecret).trim(),
      history: e.history.take(VaultEntry.maxHistory).toList(),
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
      passwordChangedAt: e.passwordChangedAt,
    );
  }
}
