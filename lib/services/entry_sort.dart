import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../data/models/vault_entry.dart';

/// How the entry list is ordered (a saved preference, see `AppSettings`).
///
/// Favourite pinning is not part of the order: the list screen decides
/// whether favourites stay on top (see `favoritesFirst` on [sortEntries]).
enum EntrySort {
  /// Last used first. The time of an entry that was never used is its
  /// `updatedAt`, so a freshly created or imported entry is not buried under
  /// entries used long ago. The default.
  recent,

  /// A to Z by the name shown in the list (title, else the site's host),
  /// ignoring case, accents and Arabic diacritics. Entries with no name at
  /// all come last.
  title,

  /// Newest first by `createdAt`.
  added,
}

/// Returns a new list with [entries] ordered by [sort]; [entries] is not
/// touched.
///
/// [lastUsed] is `VaultSession.lastUsedMap` (entry id -> last use). It only
/// matters for [EntrySort.recent].
///
/// The order is total and stable: whatever two entries tie on, they are
/// ordered by title (case-insensitive key, then the raw title), then by id,
/// then by their position in [entries]. The same input always gives the same
/// output.
///
/// With [favoritesFirst] the favourites are pinned above the rest and each
/// group keeps the order above. It is off by default so that this stays the
/// part of the list order that is not favourite pinning.
List<VaultEntry> sortEntries(
  List<VaultEntry> entries,
  EntrySort sort,
  Map<String, DateTime> lastUsed, {
  bool favoritesFirst = false,
}) {
  final rows = <_Row>[
    for (var i = 0; i < entries.length; i++) _Row(entries[i], i),
  ];
  // Newest first. Compared as instants, so UTC and local values mix safely.
  int newestFirst(int a, int b) => b.compareTo(a);

  final int Function(_Row, _Row) primary = switch (sort) {
    EntrySort.recent => (a, b) => newestFirst(
      (lastUsed[a.entry.id] ?? a.entry.updatedAt).millisecondsSinceEpoch,
      (lastUsed[b.entry.id] ?? b.entry.updatedAt).millisecondsSinceEpoch,
    ),
    EntrySort.added => (a, b) => newestFirst(
      a.entry.createdAt.millisecondsSinceEpoch,
      b.entry.createdAt.millisecondsSinceEpoch,
    ),
    EntrySort.title => _byName,
  };

  rows.sort((a, b) {
    if (favoritesFirst && a.entry.favorite != b.entry.favorite) {
      return a.entry.favorite ? -1 : 1;
    }
    final c = primary(a, b);
    if (c != 0) return c;
    final n = _byName(a, b);
    if (n != 0) return n;
    final id = a.entry.id.compareTo(b.entry.id);
    return id != 0 ? id : a.index.compareTo(b.index);
  });
  return [for (final r in rows) r.entry];
}

class _Row {
  _Row(this.entry, this.index) : key = entryNameKey(entry);

  final VaultEntry entry;

  /// Position in the input, the last tie-breaker.
  final int index;

  /// Computed once per sort, not once per comparison.
  final String key;
}

int _byName(_Row a, _Row b) {
  // Nameless entries (shown as a dash in the list) go last.
  if (a.key.isEmpty != b.key.isEmpty) return a.key.isEmpty ? 1 : -1;
  final c = a.key.compareTo(b.key);
  return c != 0 ? c : a.entry.title.compareTo(b.entry.title);
}

/// The key entries are compared by in [EntrySort.title], and the tie-break for
/// the other orders. Never shown. It follows what the list shows: the title,
/// or the host when there is no title.
///
/// * Case-insensitive.
/// * Latin accents are dropped ("Écoute" sorts as "ecoute").
/// * Arabic: short vowels and other marks (tashkeel), the tatweel stretcher
///   and the hamza on a letter are ignored, so "أحمد", "احمد" and "اَحْمَد" are
///   the same name; the alef forms, Persian yeh and kaf, and teh marbuta are
///   folded onto the plain Arabic letters; Arabic-Indic digits count as 0-9.
/// * Latin sorts before Arabic (by code point), and the Arabic letters keep
///   their alphabet order.
String entryNameKey(VaultEntry e) {
  final raw = e.title.trim().isEmpty ? e.host : e.title.trim();
  if (raw.isEmpty) return '';
  final lower = raw.toLowerCase();
  if (_ascii.hasMatch(lower)) return lower;
  final out = StringBuffer();
  for (final c in unorm.nfkd(lower).runes) {
    if (_isMark(c)) continue;
    out.writeCharCode(_fold[c] ?? _digit(c) ?? c);
  }
  return out.toString();
}

final RegExp _ascii = RegExp(r'^[\x00-\x7F]*$');

/// Combining marks (what NFKD splits accents and hamza into), Arabic marks
/// and the tatweel.
bool _isMark(int c) =>
    (c >= 0x0300 && c <= 0x036F) ||
    (c >= 0x0610 && c <= 0x061A) ||
    c == 0x0640 ||
    (c >= 0x064B && c <= 0x065F) ||
    c == 0x0670 ||
    (c >= 0x06D6 && c <= 0x06DC) ||
    (c >= 0x06DF && c <= 0x06E4) ||
    c == 0x06E7 ||
    c == 0x06E8 ||
    (c >= 0x06EA && c <= 0x06ED);

const Map<int, int> _fold = {
  0x0671: 0x0627, // alef wasla -> alef
  0x0629: 0x0647, // teh marbuta -> heh
  0x06CC: 0x064A, // Persian yeh -> yeh
  0x06A9: 0x0643, // Persian kaf -> kaf
};

/// Arabic-Indic (U+0660-0669) and Persian (U+06F0-06F9) digits as 0-9.
int? _digit(int c) {
  if (c >= 0x0660 && c <= 0x0669) return 0x30 + c - 0x0660;
  if (c >= 0x06F0 && c <= 0x06F9) return 0x30 + c - 0x06F0;
  return null;
}
