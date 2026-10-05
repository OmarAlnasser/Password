import 'dart:convert';
import 'dart:typed_data';

/// A previous password kept when an entry's password changes, or when a sync
/// conflict overwrites a different version.
class PasswordHistoryItem {
  const PasswordHistoryItem({required this.password, required this.changedAt});

  factory PasswordHistoryItem.fromJson(Map<String, Object?> j) =>
      PasswordHistoryItem(
        password: j['p']! as String,
        changedAt: DateTime.fromMillisecondsSinceEpoch(
          j['t']! as int,
          isUtc: true,
        ),
      );

  final String password;
  final DateTime changedAt;

  Map<String, Object?> toJson() => {
    'p': password,
    't': changedAt.millisecondsSinceEpoch,
  };
}

/// Decrypted vault entry. Only ever exists in memory while unlocked; on disk
/// and on the server it is a single XChaCha20-Poly1305 envelope.
class VaultEntry {
  VaultEntry({
    required this.id,
    this.title = '',
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    List<String>? tags,
    this.favorite = false,
    this.totpSecret = '',
    List<PasswordHistoryItem>? history,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? passwordChangedAt,
  }) : tags = tags ?? const [],
       history = history ?? const [],
       createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc(),
       passwordChangedAt = passwordChangedAt ?? DateTime.now().toUtc();

  /// Strict parser: entry blobs are authenticated, but imports and future
  /// format versions must still not crash the app on unexpected shapes.
  factory VaultEntry.fromJson(Map<String, Object?> j) {
    String str(String k) => (j[k] as String?) ?? '';
    DateTime time(String k) =>
        DateTime.fromMillisecondsSinceEpoch((j[k] as int?) ?? 0, isUtc: true);
    return VaultEntry(
      id: j['id']! as String,
      title: str('title'),
      username: str('user'),
      password: str('pass'),
      url: str('url'),
      notes: str('notes'),
      tags: ((j['tags'] as List?) ?? const []).cast<String>(),
      favorite: (j['fav'] as bool?) ?? false,
      totpSecret: str('totp'),
      history: ((j['hist'] as List?) ?? const [])
          .map((e) => PasswordHistoryItem.fromJson((e as Map).cast()))
          .toList(),
      createdAt: time('created'),
      updatedAt: time('updated'),
      passwordChangedAt: time('pwChanged'),
    );
  }

  factory VaultEntry.fromBytes(Uint8List bytes) => VaultEntry.fromJson(
    (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>(),
  );

  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final List<String> tags;
  final bool favorite;
  final String totpSecret;
  final List<PasswordHistoryItem> history;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime passwordChangedAt;

  static const int maxHistory = 20;

  /// Returns an updated copy. If the password changes, the old one is pushed
  /// into the history.
  VaultEntry edit({
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    List<String>? tags,
    bool? favorite,
    String? totpSecret,
    DateTime? now,
  }) {
    final t = (now ?? DateTime.now()).toUtc();
    final pwChanged = password != null && password != this.password;
    return VaultEntry(
      id: id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      favorite: favorite ?? this.favorite,
      totpSecret: totpSecret ?? this.totpSecret,
      history: pwChanged && this.password.isNotEmpty
          ? _capped([
              PasswordHistoryItem(password: this.password, changedAt: t),
              ...history,
            ])
          : history,
      createdAt: createdAt,
      updatedAt: t,
      passwordChangedAt: pwChanged ? t : passwordChangedAt,
    );
  }

  /// Adds a password to history (used when a sync conflict discards a
  /// version whose password differs from the winner).
  VaultEntry withHistoryPassword(String pw, DateTime at) {
    if (pw.isEmpty || pw == password || history.any((h) => h.password == pw)) {
      return this;
    }
    return VaultEntry(
      id: id,
      title: title,
      username: username,
      password: password,
      url: url,
      notes: notes,
      tags: tags,
      favorite: favorite,
      totpSecret: totpSecret,
      history: _capped([
        PasswordHistoryItem(password: pw, changedAt: at),
        ...history,
      ]),
      createdAt: createdAt,
      updatedAt: updatedAt,
      passwordChangedAt: passwordChangedAt,
    );
  }

  static List<PasswordHistoryItem> _capped(List<PasswordHistoryItem> h) =>
      h.length > maxHistory ? h.sublist(0, maxHistory) : h;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'user': username,
    'pass': password,
    'url': url,
    'notes': notes,
    'tags': tags,
    'fav': favorite,
    'totp': totpSecret,
    'hist': history.map((h) => h.toJson()).toList(),
    'created': createdAt.millisecondsSinceEpoch,
    'updated': updatedAt.millisecondsSinceEpoch,
    'pwChanged': passwordChangedAt.millisecondsSinceEpoch,
  };

  /// The caller must wipe the returned buffer after encrypting it.
  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Lower-cased host of [url], used for autofill matching and display.
  String get host {
    final raw = url.trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    return uri?.host.toLowerCase() ?? '';
  }

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        username.toLowerCase().contains(q) ||
        url.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }
}
