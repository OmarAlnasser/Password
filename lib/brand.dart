/// The one place that names the app in UI code.
///
/// The owner has not chosen the final name yet. UI code must read the name
/// from here and never write it as a string literal. `tool/rename_app.py`
/// rewrites [appName] (and [appNameAr]) together with the `appTitle` strings
/// in `lib/l10n/*.arb`; see `docs/RENAMING.md`.
library;

import 'dart:ui' show Locale;

/// Display name in Latin script.
const String appName = 'Hisn';

/// Display name used in the Arabic UI. Until the owner picks an Arabic name it
/// is the Latin one (brand names are normally kept in Latin script).
const String appNameAr = 'حصن';

/// One-line promise shown under the name on the lock screen and in "About".
/// Texts that belong to a language live in `lib/l10n/*.arb`; these two are the
/// brand's own tagline, kept next to the name so a rename can touch both.
const String appTagline = 'Your passwords, protected.';

/// Arabic tagline.
const String appTaglineAr = 'كلمات مرورك، في حماية كاملة.';

/// The name to show for [locale] (Arabic UI gets [appNameAr]).
String appNameFor(Locale? locale) =>
    locale?.languageCode == 'ar' ? appNameAr : appName;

/// The tagline to show for [locale].
String appTaglineFor(Locale? locale) =>
    locale?.languageCode == 'ar' ? appTaglineAr : appTagline;

/// First letter of [appName], upper-cased, for the brand tile fallback.
/// Computed at run time so a rename needs no other edit.
String get appInitial {
  final name = appName.trim();
  if (name.isEmpty) return '?';
  return String.fromCharCode(name.runes.first).toUpperCase();
}
