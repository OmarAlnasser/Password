import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hisn/brand.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/breach_checker.dart';
import 'package:hisn/services/settings.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/dashboard_screen.dart';
import 'package:hisn/ui/generator_screen.dart';
import 'package:hisn/ui/settings_screen.dart';
import 'package:hisn/ui/widgets/stat_tile.dart';

import 'helpers.dart';

/// Settings that never touch the disk: `update` writes a file, which never
/// finishes inside `testWidgets`' fake clock. The change itself is applied
/// first, as in the real class.
class _MemorySettings extends AppSettings {
  _MemorySettings() : super(File('/virtual/settings.json'));

  @override
  Future<void> update(void Function(AppSettings s) change) async {
    change(this);
    notifyListeners();
  }
}

/// The tool screens (generator, security dashboard, settings): what they show
/// and what a tap on them changes. All values are synthetic.
void main() {
  late Directory dir;
  late AppServices services;
  late _MemorySettings settings;
  late List<String> nativeCalls;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_tools');
    final base = await buildTestServices(dir);
    settings = _MemorySettings();
    nativeCalls = [];
    services = AppServices(
      session: base.session,
      settings: settings,
      clipboard: base.clipboard,
      generator: base.generator,
      strength: base.strength,
      importExport: base.importExport,
      bridge: base.bridge,
      // Knows `123456` and nothing else.
      breaches: BreachChecker(
        client: MockClient((req) async {
          final hash = BreachChecker.sha1Hex('123456');
          return http.Response(
            req.url.pathSegments.last == hash.substring(0, 5)
                ? '${hash.substring(5)}:9659365'
                : '',
            200,
          );
        }),
      ),
    );
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    Locale? locale,
    Size size = const Size(800, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockChannel(tester, platformChannel, (call) async {
      nativeCalls.add(call.method);
      return switch (call.method) {
        'copySensitive' || 'clearClipboardIfMatches' => true,
        _ => null,
      };
    });
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openVault(WidgetTester tester, List<VaultEntry> entries) async {
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      if (entries.isNotEmpty) await services.session.saveEntries(entries);
    });
  }

  group('generator', () {
    testWidgets('makes a password, switches to a passphrase, hands it back', (
      tester,
    ) async {
      String? result;
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await Navigator.of(context)
                  .push<String>(
                    MaterialPageRoute(
                      builder: (_) => const GeneratorScreen(returnResult: true),
                    ),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // A password: the length slider and the character options.
      expect(find.text('Length: 20'), findsOneWidget);
      expect(find.text('Lowercase (a-z)'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);

      await tester.tap(find.text('Passphrase'));
      await tester.pumpAndSettle();
      expect(find.text('Words: 5'), findsOneWidget);
      expect(find.text('Lowercase (a-z)'), findsNothing);

      await tester.tap(find.text('Password'));
      await tester.pumpAndSettle();
      expect(find.text('Length: 20'), findsOneWidget);

      await tester.tap(find.text('Use this password'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.length, 20);
    });

    testWidgets('Copy copies the value as a secret', (tester) async {
      await pumpScreen(tester, const GeneratorScreen());
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(nativeCalls, contains('copySensitive'));
      expect(find.textContaining('Clipboard clears'), findsOneWidget);
      await tester.runAsync(services.clipboard.clearNow);
    });
  });

  group('security dashboard', () {
    // One weak, two sharing a password and one old: every login has a finding.
    final old = DateTime.now().subtract(const Duration(days: 500));
    List<VaultEntry> entries() => [
      VaultEntry(
        id: 'weak',
        title: 'Notion',
        username: 'abcde07@hotmail.com',
        password: '123456',
      ),
      VaultEntry(
        id: 'a',
        title: 'Work email',
        username: 'abcde07@hotmail.com',
        password: 'Rb7#mVq9zLp2',
      ),
      VaultEntry(
        id: 'b',
        title: 'Dropbox',
        username: 'abcde07@hotmail.com',
        password: 'Rb7#mVq9zLp2',
      ),
      VaultEntry(
        id: 'old',
        title: 'GitHub',
        username: 'abcde07@hotmail.com',
        password: 'violet-harbor-quantum-71-lantern',
        passwordChangedAt: old,
      ),
    ];

    Finder tile(String label) => find.widgetWithText(StatTile, label);

    testWidgets('a score, the four counts, and lists behind them', (
      tester,
    ) async {
      await openVault(tester, entries());
      await pumpScreen(tester, const DashboardScreen());

      // The counts sit on stat tiles; the breached one waits for the check.
      expect(
        find.descendant(of: tile('Weak passwords'), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile('Reused passwords'), matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('Old passwords (> 1 year)'),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('Found in data breaches'),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      // Weak and breached count fully, reused 0.6, old 0.35: 100 x (1 - 2.55 / 4).
      expect(find.text('36'), findsOneWidget);
      expect(find.text('4 of 4 logins need a look'), findsOneWidget);
      expect(find.text('Security score'), findsOneWidget);

      // The lists are folded; a tile opens its list.
      expect(find.text('Notion'), findsNothing);
      await tester.tap(tile('Weak passwords'));
      await tester.pumpAndSettle();
      expect(find.text('Notion'), findsOneWidget);
      expect(find.text('GitHub'), findsNothing);

      // So does the list's own header.
      await tester.tap(
        find.widgetWithText(InkWell, 'Old passwords (> 1 year)').last,
      );
      await tester.pumpAndSettle();
      expect(find.text('GitHub'), findsOneWidget);
    });

    testWidgets('the breach check runs on the button and counts', (
      tester,
    ) async {
      await openVault(tester, entries());
      await pumpScreen(tester, const DashboardScreen());

      await tester.runAsync(() async {
        await tester.tap(find.text('Check for breaches'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: tile('Found in data breaches'),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      // The breached login is listed in its own folding card.
      await tester.tap(tile('Found in data breaches'));
      await tester.pumpAndSettle();
      expect(find.text('× 9659365'), findsOneWidget);
    });

    testWidgets('the breach check can be turned off', (tester) async {
      settings.hibpEnabled = false;
      await openVault(tester, entries());
      await pumpScreen(tester, const DashboardScreen());
      expect(find.text('Check for breaches'), findsNothing);
      expect(tile('Found in data breaches'), findsNothing);
    });

    testWidgets('an empty vault has no score to show', (tester) async {
      await openVault(tester, const []);
      await pumpScreen(tester, const DashboardScreen());
      expect(find.text('No passwords to check yet'), findsOneWidget);
      expect(find.text('Security score'), findsNothing);
    });

    testWidgets('Arabic: the score and the counts read right to left', (
      tester,
    ) async {
      await openVault(tester, entries());
      await pumpScreen(
        tester,
        const DashboardScreen(),
        locale: const Locale('ar'),
      );
      expect(find.text('درجة الأمان'), findsOneWidget);
      expect(find.text('4 من 4 حسابات تحتاج إلى انتباه'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('settings', () {
    testWidgets('pills set the theme and the language', (tester) async {
      await pumpScreen(tester, const SettingsScreen());
      expect(settings.themeMode, ThemeMode.dark);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.light);
      await tester.tap(find.text('System').first);
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.system);

      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      expect(settings.locale, const Locale('ar'));
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(settings.locale, const Locale('en'));
    });

    testWidgets('a pill opens a menu of choices', (tester) async {
      await pumpScreen(tester, const SettingsScreen());
      expect(settings.autoLockSeconds, 120);

      await tester.tap(find.text('2 min'));
      await tester.pumpAndSettle();
      expect(find.text('15 min'), findsOneWidget);
      await tester.tap(find.text('5 min'));
      await tester.pumpAndSettle();
      expect(settings.autoLockSeconds, 300);
      expect(find.text('5 min'), findsOneWidget);

      await tester.tap(find.text('30 s'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('60 s'));
      await tester.pumpAndSettle();
      expect(settings.clipboardClearSeconds, 60);
    });

    testWidgets('a stored value that is not in the list is still shown', (
      tester,
    ) async {
      settings.autoLockSeconds = 90;
      await pumpScreen(tester, const SettingsScreen());
      expect(find.text('90 s'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switches save at once', (tester) async {
      await pumpScreen(tester, const SettingsScreen());
      expect(settings.lockOnBackground, isTrue);
      await tester.tap(find.text('Lock when app goes to background'));
      await tester.pumpAndSettle();
      expect(settings.lockOnBackground, isFalse);
    });

    testWidgets('About names the app from the brand constant', (tester) async {
      await pumpScreen(tester, const SettingsScreen());
      expect(find.text('About'), findsOneWidget);
      expect(find.text(appName.toUpperCase()), findsOneWidget);
      expect(find.text(appTagline), findsOneWidget);
    });

    testWidgets('Arabic: groups and rows read right to left', (tester) async {
      await pumpScreen(
        tester,
        const SettingsScreen(),
        locale: const Locale('ar'),
      );
      expect(find.text('حول التطبيق'), findsOneWidget);
      expect(find.text(appTaglineAr), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
