/// Render-and-look pictures of the tool screens (generator, security
/// dashboard, settings, CSV import review, screenshot import, save sheet).
/// Skipped by default; run with
///
/// ```sh
/// SHOTS_DIR=/some/dir flutter test --run-skipped -t screenshots test/ui/tools_shots_test.dart
/// ```
///
/// Fake data only. Nothing is asserted: a `RenderFlex overflowed` error fails
/// the test, which is the point.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/l10n/app_localizations.dart';
import 'package:vaultsnap/ui/app_scope.dart';
import 'package:vaultsnap/ui/generator_screen.dart';

import '../tool/screenshot_harness.dart';
import 'helpers.dart';

const _email = 'abcde07@hotmail.com';
const _password = 'xQmR42abCD5k';

/// Synthetic logins with every kind of finding: weak, reused and old.
List<VaultEntry> _entries() {
  final old = DateTime.now().subtract(const Duration(days: 500));
  return [
    VaultEntry(
      id: 'github',
      title: 'GitHub',
      username: _email,
      password: _password,
      url: 'https://github.com/login',
    ),
    VaultEntry(
      id: 'google',
      title: 'Google',
      username: 'abcde07@gmail.com',
      password: 'violet-harbor-quantum-71-lantern',
      url: 'https://google.com',
    ),
    VaultEntry(
      id: 'mail',
      title: 'Work email',
      username: _email,
      password: 'Rb7#mVq9zLp2',
      url: 'https://outlook.example.com',
    ),
    VaultEntry(
      id: 'notion',
      title: 'Notion',
      username: _email,
      password: '123456',
      url: 'https://notion.so',
    ),
    VaultEntry(
      id: 'dropbox',
      title: 'Dropbox',
      username: _email,
      password: '123456',
      url: 'https://dropbox.com',
    ),
    VaultEntry(
      id: 'bank',
      title: 'البنك الأهلي',
      username: 'abcde07',
      password: 'Nf4%tYu81hQe',
      url: 'https://bank.example.com',
      createdAt: old,
      updatedAt: old,
      passwordChangedAt: old,
    ),
    VaultEntry(
      id: 'long',
      title: 'A very long entry name that has to be cut with an ellipsis',
      username: 'a.very.long.username.that.does.not.fit@example-company.com',
      password: 'password1',
      url: 'https://example-company.com',
    ),
  ];
}

void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_tools_shots');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Widget Function(Widget) scope() =>
      (app) => AppScope(services: services, child: app);

  Future<void> vault(WidgetTester tester, {bool withEntries = true}) async {
    mockChannel(tester, platformChannel, (_) async => null);
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      if (withEntries) await services.session.saveEntries(_entries());
    });
  }

  testWidgets('generator', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const GeneratorScreen(),
      'tools-generator',
      wrap: scope(),
    );
  });

  testWidgets('generator: passphrase, picker mode, large text', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const GeneratorScreen(returnResult: true),
      'tools-generator-pass',
      sizes: [ShotSize.phone, ShotSize.desktop],
      themes: [Brightness.dark],
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.text(_l(t).passphrase));
        await t.pump(const Duration(milliseconds: 300));
      },
    );
    await pumpScreenshots(
      tester,
      const GeneratorScreen(),
      'tools-generator-x15',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      textScale: 1.5,
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const GeneratorScreen(),
      'tools-generator-x2',
      sizes: [ShotSize.narrow],
      themes: [Brightness.dark],
      locales: [const Locale('ar')],
      textScale: 2,
      wrap: scope(),
    );
  });
}

/// The strings of the language the screen is shown in.
AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));
