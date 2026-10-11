import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/sync/sync_service.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/home_screen.dart';
import 'package:hisn/ui/settings_screen.dart';
import 'package:hisn/ui/theme/app_theme.dart';
import 'package:hisn/ui/widgets/sync_deletion_prompt.dart';

import 'fake_sync.dart';
import 'helpers.dart';

/// The prompt that a sync holding another device's mass deletion shows (on
/// the entry list and in the settings), and the line the delete dialog adds
/// when this device is the one deleting that many. Every login is synthetic.
void main() {
  late Directory dir;
  late AppServices base;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_sync_prompt');
    base = await buildTestServices(dir);
  });
  tearDown(() async {
    await base.session.lock();
    dir.deleteSync(recursive: true);
  });

  AppServices withSync(SyncService? sync) => AppServices(
    session: base.session,
    settings: base.settings,
    clipboard: base.clipboard,
    generator: base.generator,
    strength: base.strength,
    importExport: base.importExport,
    bridge: base.bridge,
    breaches: base.breaches,
    favicons: base.favicons,
    sync: sync,
  );

  Future<void> vault(WidgetTester tester) async {
    mockChannel(tester, platformChannel, (_) async => null);
    await tester.runAsync(() async {
      await base.session.init();
      await base.session.createVault(testMasterPassword);
      await base.session.saveEntries([
        for (var i = 0; i < 5; i++)
          VaultEntry(
            id: 'e$i',
            title: 'Site $i',
            username: 'user$i@example.test',
            password: 'hunter-test-$i',
          ),
      ]);
      await base.settings.update((x) => x.syncEmail = 'me@example.test');
    });
  }

  Future<void> show(
    WidgetTester tester,
    AppServices services,
    Widget home, {
    Size size = const Size(390, 844),
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(locale),
          darkTheme: AppTheme.dark(locale),
          themeMode: ThemeMode.dark,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('on the entry list', () {
    testWidgets('says how many; "Keep them" keeps them and the card goes', (
      tester,
    ) async {
      await vault(tester);
      final sync = FakeSync(pending: 6);
      await show(tester, withSync(sync), const HomeScreen());
      expect(find.byType(SyncDeletionPrompt), findsOneWidget);
      expect(find.text('Another device deleted 6 entries'), findsOneWidget);
      expect(
        find.text(
          'This device has not deleted them yet. If you keep them, they come '
          'back on your other devices too.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Keep them'));
      expect(sync.calls, ['keep']);
      expect(find.byType(SyncDeletionPrompt), findsNothing);
    });

    testWidgets('"Delete here too" asks first', (tester) async {
      await vault(tester);
      final sync = FakeSync(pending: 6);
      await show(tester, withSync(sync), const HomeScreen());
      await tap(tester, find.text('Delete here too'));
      expect(find.text('Delete 6 entries?'), findsOneWidget);
      expect(
        find.text(
          'They were deleted on another device. This cannot be undone.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(sync.calls, isEmpty);
      expect(find.byType(SyncDeletionPrompt), findsOneWidget);

      await tap(tester, find.text('Delete here too'));
      await tap(tester, find.widgetWithText(FilledButton, 'Delete'));
      expect(sync.calls, ['apply']);
      expect(find.byType(SyncDeletionPrompt), findsNothing);
    });

    testWidgets('the sync button does not fail while it waits', (tester) async {
      await vault(tester);
      final sync = FakeSync(pending: 6);
      await show(tester, withSync(sync), const HomeScreen());
      await tap(tester, find.byTooltip('Sync now'));
      expect(sync.calls, ['sync']);
      expect(tester.takeException(), isNull);
      expect(find.byType(SyncDeletionPrompt), findsOneWidget);
    });

    testWidgets('nothing waiting: no card', (tester) async {
      await vault(tester);
      await show(tester, withSync(FakeSync()), const HomeScreen());
      expect(find.byType(SyncDeletionPrompt), findsNothing);
    });

    testWidgets('Arabic at 200% on a small phone: Arabic words, nothing '
        'overflows', (tester) async {
      await vault(tester);
      await show(
        tester,
        withSync(FakeSync(pending: 6)),
        const HomeScreen(),
        size: const Size(360, 640),
        locale: const Locale('ar'),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('حذف جهاز آخر 6 عناصر'), findsOneWidget);
      expect(find.text('احذفها هنا أيضًا'), findsOneWidget);
      expect(find.text('أبقِها'), findsOneWidget);
    });
  });

  group('in the settings', () {
    testWidgets('the sync group shows it; Sync now does not fail', (
      tester,
    ) async {
      await vault(tester);
      final sync = FakeSync(pending: 7);
      await show(
        tester,
        withSync(sync),
        const SettingsScreen(),
        size: const Size(390, 2400),
      );
      expect(find.text('Another device deleted 7 entries'), findsOneWidget);
      // A row of the sync card, not a card of its own.
      expect(
        tester
            .widget<SyncDeletionPrompt>(find.byType(SyncDeletionPrompt))
            .framed,
        isFalse,
      );
      await tap(tester, find.byTooltip('Sync now'));
      expect(sync.calls, ['sync']);
      expect(tester.takeException(), isNull);

      await tap(tester, find.text('Keep them'));
      expect(sync.calls, ['sync', 'keep']);
      expect(find.byType(SyncDeletionPrompt), findsNothing);
    });
  });

  group('the delete dialog with sync on', () {
    Future<void> deleteTicked(WidgetTester tester, int n) async {
      await tester.longPress(find.text('Site 0'));
      await tester.pumpAndSettle();
      for (var i = 1; i < n; i++) {
        await tap(tester, find.text('Site $i'));
      }
      await tap(tester, find.byTooltip('Delete selected'));
      expect(find.text('Delete $n entries?'), findsOneWidget);
    }

    const warning = 'Your other devices will ask before deleting this many.';

    testWidgets('says the other devices will ask, for most of the vault', (
      tester,
    ) async {
      await vault(tester);
      await show(tester, withSync(FakeSync()), const HomeScreen());
      await deleteTicked(tester, 5);
      expect(find.text(warning), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, 'Cancel'));
    });

    testWidgets('not for a few', (tester) async {
      await vault(tester);
      await show(tester, withSync(FakeSync()), const HomeScreen());
      await deleteTicked(tester, 3);
      expect(find.text(warning), findsNothing);
      await tap(tester, find.widgetWithText(TextButton, 'Cancel'));
    });

    testWidgets('not without sync', (tester) async {
      await vault(tester);
      await show(tester, withSync(null), const HomeScreen());
      await deleteTicked(tester, 5);
      expect(find.text(warning), findsNothing);
      await tap(tester, find.widgetWithText(TextButton, 'Cancel'));
    });

    testWidgets('Arabic', (tester) async {
      await vault(tester);
      await show(
        tester,
        withSync(FakeSync()),
        const HomeScreen(),
        locale: const Locale('ar'),
      );
      await tester.longPress(find.text('Site 0'));
      await tester.pumpAndSettle();
      for (var i = 1; i < 5; i++) {
        await tap(tester, find.text('Site $i'));
      }
      await tap(tester, find.byTooltip('حذف المحدد'));
      expect(find.text('حذف 5 عناصر؟'), findsOneWidget);
      expect(
        find.text('ستطلب أجهزتك الأخرى تأكيدًا قبل حذف هذا العدد.'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(TextButton, 'إلغاء'));
    });
  });

  test('the counts use the right plural forms', () {
    final ar = lookupAppLocalizations(const Locale('ar'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.syncDeletionTitle(1), 'Another device deleted 1 entry');
    expect(en.syncDeletionTitle(12), 'Another device deleted 12 entries');
    expect(
      [
        for (final n in [1, 2, 5, 11, 100]) ar.syncDeletionTitle(n),
      ],
      [
        'حذف جهاز آخر عنصرًا واحدًا',
        'حذف جهاز آخر عنصرين',
        'حذف جهاز آخر 5 عناصر',
        'حذف جهاز آخر 11 عنصرًا',
        'حذف جهاز آخر 100 عنصر',
      ],
    );
    expect(
      [
        for (final n in [1, 2, 3]) ar.deleteHiddenCount(n),
      ],
      [
        'عنصر واحد منها لا يظهر بسبب البحث أو التصفية.',
        'عنصران منها لا يظهران بسبب البحث أو التصفية.',
        '3 منها لا تظهر بسبب البحث أو التصفية.',
      ],
    );
    expect(
      en.deleteHiddenCount(2),
      '2 of them are hidden by the search or filter.',
    );
  });
}
