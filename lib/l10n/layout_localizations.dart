import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_localizations.dart';
import 'app_localizations_ar_ltr.dart';

/// The localization delegates of every `MaterialApp` in the app.
///
/// Arabic keeps the English, left-to-right layout unless
/// `AppSettings.mirrorArabic` is on; in that layout the Arabic strings come
/// from [AppLocalizationsArLtr], which keeps each sentence reading right to
/// left. Pair it with [layoutDirection] in `MaterialApp.builder`.
List<LocalizationsDelegate<Object?>> appLocalizationsDelegates({
  required bool mirrorArabic,
}) => [
  LayoutLocalizationsDelegate(arabicLtr: !mirrorArabic),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// [child] laid out left to right, except in Arabic with [mirrorArabic] on.
/// Use it in `MaterialApp.builder`, under the app's `Localizations`.
Widget layoutDirection(
  BuildContext context, {
  required bool mirrorArabic,
  required Widget child,
}) {
  final arabic = Localizations.maybeLocaleOf(context)?.languageCode == 'ar';
  if (!arabic || mirrorArabic) return child;
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

/// `AppLocalizations.delegate`, with [AppLocalizationsArLtr] for Arabic when
/// [arabicLtr] is set.
class LayoutLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const LayoutLocalizationsDelegate({required this.arabicLtr});

  final bool arabicLtr;

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.delegate.isSupported(locale);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      arabicLtr && locale.languageCode == 'ar'
      ? SynchronousFuture<AppLocalizations>(AppLocalizationsArLtr())
      : AppLocalizations.delegate.load(locale);

  @override
  bool shouldReload(LayoutLocalizationsDelegate old) =>
      old.arabicLtr != arabicLtr;
}
