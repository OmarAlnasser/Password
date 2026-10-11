import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/l10n/app_localizations_ar.dart';
import 'package:hisn/l10n/app_localizations_ar_ltr.dart';
import 'package:hisn/l10n/layout_localizations.dart';

/// Arabic in the left-to-right layout (`AppSettings.mirrorArabic` off): every
/// string is a right-to-left isolate, except the ones that are data.
void main() {
  const rli = '\u2067';
  const pdi = '\u2069';
  const keep = {'appTitle', 'resetConfirmWord'};

  Set<String> members(String path, RegExp re) => {
    for (final m in re.allMatches(File(path).readAsStringSync())) m.group(1)!,
  };

  test('every string is overridden (re-run tool/gen_arabic_ltr.py)', () {
    final all = members(
      'lib/l10n/app_localizations.dart',
      RegExp(r'^  String (?:get )?(\w+)[;(]', multiLine: true),
    );
    final wrapped = members(
      'lib/l10n/app_localizations_ar_ltr.dart',
      RegExp(r'^  String (?:get )?(\w+)(?: =>|\()', multiLine: true),
    );
    expect(all.length, greaterThan(300));
    expect(wrapped, all.difference(keep));
  });

  test('strings are wrapped; data strings are not', () {
    final ar = AppLocalizationsAr();
    final ltr = AppLocalizationsArLtr();
    expect(ltr.createVault, '$rli${ar.createVault}$pdi');
    expect(ltr.selectedCount(3), '$rli${ar.selectedCount(3)}$pdi');
    expect(ltr.resetConfirmWord, ar.resetConfirmWord);
    expect(ltr.appTitle, ar.appTitle);
  });

  test('the delegate picks the class by layout', () async {
    const ar = Locale('ar');
    expect(
      await const LayoutLocalizationsDelegate(arabicLtr: true).load(ar),
      isA<AppLocalizationsArLtr>(),
    );
    final mirrored = await const LayoutLocalizationsDelegate(arabicLtr: false)
        .load(ar);
    expect(mirrored, isA<AppLocalizationsAr>());
    expect(mirrored, isNot(isA<AppLocalizationsArLtr>()));
    final en = await const LayoutLocalizationsDelegate(arabicLtr: true)
        .load(const Locale('en'));
    expect(
      en.createVault,
      lookupAppLocalizations(const Locale('en')).createVault,
    );
    expect(
      const LayoutLocalizationsDelegate(arabicLtr: true)
          .shouldReload(const LayoutLocalizationsDelegate(arabicLtr: false)),
      isTrue,
    );
  });
}
