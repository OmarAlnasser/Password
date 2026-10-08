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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/l10n/app_localizations.dart';
import 'package:vaultsnap/services/breach_checker.dart';
import 'package:vaultsnap/services/ocr/ocr_parser.dart';
import 'package:vaultsnap/services/ocr/ocr_scanner.dart';
import 'package:vaultsnap/services/sync/sync_service.dart';
import 'package:vaultsnap/ui/app_scope.dart';
import 'package:vaultsnap/ui/dashboard_screen.dart';
import 'package:vaultsnap/ui/generator_screen.dart';
import 'package:vaultsnap/ui/import/import_review_screen.dart';
import 'package:vaultsnap/ui/ocr/ocr_import_screen.dart';
import 'package:vaultsnap/ui/ocr/ocr_widgets.dart';
import 'package:vaultsnap/ui/ocr/quick_save_sheet.dart';
import 'package:vaultsnap/ui/settings_screen.dart';

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
      // A test may build several screens over the same vault.
      if (services.session.isUnlocked) return;
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

  // --- security dashboard -----------------------------------------------------

  /// Services whose breach checker knows `123456` and `password1`.
  AppServices withBreaches() {
    final hits = {
      for (final p in ['123456', 'password1'])
        BreachChecker.sha1Hex(p).substring(
          0,
          5,
        ): '${BreachChecker.sha1Hex(p).substring(5)}:${p == '123456' ? 9659365 : 2400}',
    };
    return AppServices(
      session: services.session,
      settings: services.settings,
      clipboard: services.clipboard,
      generator: services.generator,
      strength: services.strength,
      importExport: services.importExport,
      bridge: services.bridge,
      favicons: services.favicons,
      breaches: BreachChecker(
        client: MockClient((req) async {
          final prefix = req.url.pathSegments.last;
          return http.Response(hits[prefix] ?? '', 200);
        }),
      ),
    );
  }

  testWidgets('dashboard', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const DashboardScreen(),
      'tools-dashboard',
      sizes: [ShotSize.custom('tall', 390, 1100), ShotSize.desktop],
      wrap: scope(),
    );
  });

  testWidgets('dashboard: after the breach check, large text, empty', (
    tester,
  ) async {
    await vault(tester);
    final breach = withBreaches();
    Future<void> check(WidgetTester t) async {
      await t.ensureVisible(find.text(_l(t).checkBreaches));
      await t.tap(find.text(_l(t).checkBreaches));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pump(const Duration(milliseconds: 200));
    }

    await pumpScreenshots(
      tester,
      const DashboardScreen(),
      'tools-dashboard-breach',
      sizes: [ShotSize.custom('tall', 390, 1900), ShotSize.desktop],
      themes: [Brightness.dark, Brightness.light],
      locales: [const Locale('en')],
      wrap: (app) => AppScope(services: breach, child: app),
      afterPump: check,
    );
    await pumpScreenshots(
      tester,
      const DashboardScreen(),
      'tools-dashboard-x15',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      textScale: 1.5,
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const DashboardScreen(),
      'tools-dashboard-x2',
      sizes: [ShotSize.narrow],
      themes: [Brightness.dark],
      locales: [const Locale('ar')],
      textScale: 2,
      wrap: scope(),
    );
  });

  testWidgets('dashboard: nothing in the vault', (tester) async {
    await vault(tester, withEntries: false);
    await pumpScreenshots(
      tester,
      const DashboardScreen(),
      'tools-dashboard-empty',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      wrap: scope(),
    );
  });

  // --- settings ---------------------------------------------------------------

  testWidgets('settings', (tester) async {
    await vault(tester);
    final tall = ShotSize.custom('tall', 390, 1700);
    await pumpScreenshots(
      tester,
      const SettingsScreen(),
      'tools-settings',
      sizes: [tall, ShotSize.desktop],
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const SettingsScreen(),
      'tools-settings-x15',
      sizes: [ShotSize.custom('tall', 390, 2600)],
      themes: [Brightness.dark],
      locales: [const Locale('en')],
      textScale: 1.5,
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const SettingsScreen(),
      'tools-settings-x2',
      sizes: [ShotSize.custom('narrow', 360, 3600)],
      themes: [Brightness.dark],
      locales: [const Locale('ar')],
      textScale: 2,
      wrap: scope(),
    );
  });

  testWidgets('settings: sync on, a menu open', (tester) async {
    await vault(tester);
    await tester.runAsync(
      () => services.settings.update((x) => x.syncEmail = _email),
    );
    final synced = AppServices(
      session: services.session,
      settings: services.settings,
      clipboard: services.clipboard,
      generator: services.generator,
      strength: services.strength,
      importExport: services.importExport,
      bridge: services.bridge,
      breaches: services.breaches,
      favicons: services.favicons,
      sync: _FakeSync(),
    );
    await pumpScreenshots(
      tester,
      const SettingsScreen(),
      'tools-settings-sync',
      sizes: [ShotSize.custom('tall', 390, 1900)],
      themes: [Brightness.dark, Brightness.light],
      locales: [const Locale('en'), const Locale('ar')],
      wrap: (app) => AppScope(services: synced, child: app),
    );
    await pumpScreenshots(
      tester,
      const SettingsScreen(),
      'tools-settings-menu',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark, Brightness.light],
      locales: [const Locale('en')],
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.text(_l(t).minutes(2)));
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  });

  // --- CSV import review --------------------------------------------------------

  testWidgets('import review', (tester) async {
    await vault(tester);
    final parsed = services.importExport.importCsv(
      [
        'name,url,username,password,note',
        'mail.contoso-test.com,https://mail.contoso-test.com/login,'
            '$_email,$_password,',
        'shop.fabrikam-test.org,https://shop.fabrikam-test.org/,'
            '$_email,Hb5nRw3kYs7d,',
        'shop.fabrikam-test.org,https://shop.fabrikam-test.org/cart,'
            '$_email,Hb5nRw3kYs7d,',
        'github.com,https://github.com/login,$_email,$_password,',
        'forum.tailspin-test.net,https://forum.tailspin-test.net/,'
            '$_password,$_email,',
        'docs.example.org,https://docs.example.org/,,Zk3pLq9rTw2m,',
        'news.example.net,http://news.example.net/,reader,Qw8vNm4xHb7c,',
      ].join('\n'),
    );
    Widget screen() =>
        ImportReviewScreen(imported: parsed.entries, skipped: parsed.skipped);
    await pumpScreenshots(
      tester,
      screen(),
      'tools-import',
      sizes: [ShotSize.custom('tall', 390, 1500), ShotSize.desktop],
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      screen(),
      'tools-import-x15',
      sizes: [ShotSize.custom('tall', 390, 2200)],
      themes: [Brightness.dark],
      locales: [const Locale('en')],
      textScale: 1.5,
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      screen(),
      'tools-import-edit',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.byType(ListTile).first);
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  });

  // --- screenshot import ------------------------------------------------------

  Future<File> picked() async {
    final f = File('${dir.path}/picked.png')
      ..writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);
    return f;
  }

  Future<void> ocrScreen(
    WidgetTester tester,
    String name,
    List<String> lines, {
    Finder? until,
    List<Size> sizes = const [],
    List<Brightness> themes = const [Brightness.dark, Brightness.light],
    List<Locale> locales = const [Locale('en'), Locale('ar')],
    double textScale = 1,
  }) async {
    await vault(tester);
    mockOcr(tester, (_, _) => lines);
    final file = await picked();
    await pumpScreenshots(
      tester,
      OcrImportScreen(initial: PickedImage(path: file.path, isTempCopy: false)),
      name,
      sizes: sizes.isEmpty
          ? [ShotSize.custom('tall', 390, 1500), ShotSize.desktop]
          : [for (final s in sizes) ShotSize.custom('s', s.width, s.height)],
      themes: themes,
      locales: locales,
      textScale: textScale,
      wrap: scope(),
      afterPump: (t) async {
        await pumpUntilFound(t, until ?? find.text(_l(t).addEntry));
        await t.pump(const Duration(milliseconds: 900));
      },
    );
  }

  testWidgets('screenshot import: found', (tester) async {
    await ocrScreen(tester, 'tools-ocr', [
      'My account',
      'example.org',
      _email,
      _password,
    ]);
  });

  testWidgets('screenshot import: only the password, large text', (
    tester,
  ) async {
    await ocrScreen(
      tester,
      'tools-ocr-partial',
      ['abcde07', _password, 'hotmai1.com'],
      themes: [Brightness.dark],
      locales: [const Locale('en')],
      textScale: 1.5,
      sizes: [const Size(390, 2000)],
    );
  });

  testWidgets('screenshot import: nothing read', (tester) async {
    await vault(tester);
    mockOcr(tester, (_, _) => <String>[]);
    final file = await picked();
    await pumpScreenshots(
      tester,
      OcrImportScreen(initial: PickedImage(path: file.path, isTempCopy: false)),
      'tools-ocr-nothing',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark, Brightness.light],
      locales: [const Locale('en'), const Locale('ar')],
      wrap: scope(),
      afterPump: (t) async {
        await pumpUntilFound(t, find.byKey(const ValueKey('ocr.failure')));
        await t.pump(const Duration(milliseconds: 900));
      },
    );
  });

  testWidgets('screenshot import: the first visit', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const OcrImportScreen(),
      'tools-ocr-start',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark, Brightness.light],
      locales: [const Locale('en'), const Locale('ar')],
      wrap: scope(),
    );
  });

  // --- the save sheet -----------------------------------------------------------

  Future<void> sheet(
    WidgetTester tester,
    String name,
    OcrResult found, {
    List<ScanPass> passes = const [],
    bool advanced = false,
    List<ShotSize>? sizes,
    List<Brightness> themes = const [Brightness.dark, Brightness.light],
    List<Locale> locales = const [Locale('en'), Locale('ar')],
    double textScale = 1,
    Future<void> Function(WidgetTester)? more,
  }) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () =>
                  QuickSaveSheet.show(context, found, passes: passes),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      name,
      sizes: sizes ?? [ShotSize.phone, ShotSize.desktop],
      themes: themes,
      locales: locales,
      textScale: textScale,
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.text('open'));
        await t.pump(const Duration(milliseconds: 500));
        await t.pump(const Duration(milliseconds: 500));
        if (advanced) {
          await t.tap(find.text(_l(t).advancedMode));
          await t.pump(const Duration(milliseconds: 400));
        }
        await more?.call(t);
      },
    );
  }

  const complete = OcrResult(
    chips: [_email, _password, 'My account', 'example.org'],
    email: _email,
    username: _email,
    password: _password,
    title: 'My account',
    emailCandidates: [_email, 'abcde07@hotmail.co.uk'],
    passwordCandidates: [_password, 'xQmR42abCD5K', 'xQmR42abCDSk'],
  );

  testWidgets('save sheet: quick', (tester) async {
    await sheet(tester, 'tools-sheet', complete);
  });

  testWidgets('save sheet: advanced, folds open, large text', (tester) async {
    await sheet(
      tester,
      'tools-sheet-adv',
      complete,
      advanced: true,
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      locales: [const Locale('en')],
    );
    await sheet(
      tester,
      'tools-sheet-x15',
      complete,
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      locales: [const Locale('en')],
      textScale: 1.5,
    );
    await sheet(
      tester,
      'tools-sheet-x2',
      complete,
      sizes: [ShotSize.narrow],
      themes: [Brightness.dark],
      locales: [const Locale('ar')],
      textScale: 2,
    );
  });

  testWidgets('save sheet: incomplete reading and what was read', (
    tester,
  ) async {
    await sheet(
      tester,
      'tools-sheet-partial',
      const OcrResult(
        chips: ['abcde07', _password, 'hotmai1.com', 'Sign in', 'example.org'],
        password: _password,
        passwordCandidates: [_password],
      ),
      passes: const [
        ScanPass(name: 'original', lines: [], quality: 0),
        ScanPass(
          name: 'inverted',
          lines: ['abcde07', 'xQmR 42abCD5k', 'hotmai1.com'],
          quality: 0.5,
        ),
        ScanPass(
          name: 'upscaled',
          lines: [],
          quality: 0,
          error: ScanError.failed,
        ),
      ],
      sizes: [ShotSize.phone, ShotSize.desktop],
      themes: [Brightness.dark, Brightness.light],
      locales: [const Locale('en')],
      more: (t) async {
        final read = find.byKey(const ValueKey('ocr.read'));
        await t.ensureVisible(read);
        await t.tap(find.text(_l(t).ocrWhatWasRead));
        await t.pump(const Duration(milliseconds: 500));
      },
    );
  });

  testWidgets('failure dialog and clipboard offer', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showOcrFailureDialog(
                context,
                error: ScanError.noLanguage,
                passes: const [
                  ScanPass(
                    name: 'original',
                    lines: [],
                    quality: 0,
                    error: ScanError.noLanguage,
                  ),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      'tools-ocr-dialog',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark, Brightness.light],
      locales: [const Locale('en'), const Locale('ar')],
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.text('open'));
        await t.pump(const Duration(milliseconds: 600));
      },
    );
    await pumpScreenshots(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => offerClearClipboard(context, screenshot: true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      'tools-clipboard-dialog',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark, Brightness.light],
      locales: [const Locale('en'), const Locale('ar')],
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.text('open'));
        await t.pump(const Duration(milliseconds: 600));
      },
    );
  });
}

/// The strings of the language the screen is shown in.
AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));

/// A sync service that is on and has synced, for the picture of its rows.
class _FakeSync extends ChangeNotifier implements SyncService {
  @override
  bool get enabled => true;

  @override
  SyncStatus get status => SyncStatus.idle;

  @override
  DateTime? get lastSync => DateTime(2026, 3, 12, 9, 41);

  @override
  Future<void> syncNow() async {}

  @override
  Future<void> disable() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
