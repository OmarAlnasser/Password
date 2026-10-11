/// Render-and-look pictures of the entry list's sort menu, selection mode and
/// mass-delete dialog. Skipped by default; run with
///
/// ```sh
/// SHOTS_DIR=/some/dir flutter test --run-skipped -t screenshots test/ui/home_selection_shots_test.dart
/// ```
///
/// Synthetic data only. Nothing is asserted: a `RenderFlex overflowed` error
/// fails the test, which is the point.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/entry_sort.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/services/sync/sync_service.dart';
import 'package:hisn/ui/home_screen.dart';
import 'package:hisn/ui/settings_screen.dart';
import 'package:hisn/ui/widgets/entry_sort_button.dart';

import '../tool/screenshot_harness.dart';
import 'fake_sync.dart';
import 'helpers.dart';

List<VaultEntry> _entries() {
  DateTime day(int m, int d) => DateTime.utc(2020, m, d);
  VaultEntry entry(
    String id,
    String title, {
    String user = '',
    String url = '',
    List<String> tags = const [],
    bool favorite = false,
    required int created,
    required int updated,
  }) => VaultEntry(
    id: id,
    title: title,
    username: user,
    password: 'hunter-test-$id',
    url: url,
    tags: tags,
    favorite: favorite,
    createdAt: day(1, created),
    updatedAt: day(2, updated),
  );
  return [
    entry(
      'mail',
      'Mail',
      user: 'someone@example.test',
      url: 'https://mail.example.test',
      tags: ['work'],
      favorite: true,
      created: 3,
      updated: 4,
    ),
    entry(
      'forum',
      'Old forum',
      user: 'someone@example.test',
      url: 'https://forum.example.test',
      created: 5,
      updated: 20,
    ),
    entry(
      'shop',
      'متجر الكتب',
      user: 'reader-01',
      url: 'https://books.example.test',
      tags: ['personal'],
      created: 9,
      updated: 18,
    ),
    entry(
      'trial',
      'Free trial nobody uses',
      user: 'trial.account.that.has.a.long.name@example.test',
      url: 'https://trial.example.test',
      created: 11,
      updated: 16,
    ),
    entry(
      'game',
      'Game launcher',
      user: 'player-7',
      url: 'https://games.example.test',
      tags: ['personal'],
      created: 13,
      updated: 14,
    ),
    entry(
      'news',
      'News site',
      user: 'someone@example.test',
      url: 'https://news.example.test',
      created: 15,
      updated: 12,
    ),
    entry('router', 'Home router', tags: ['home'], created: 17, updated: 10),
    entry(
      'bank',
      'البنك',
      user: 'customer-42',
      url: 'https://bank.example.test',
      tags: ['money'],
      favorite: true,
      created: 19,
      updated: 8,
    ),
    entry(
      'photos',
      'Photo backup',
      user: 'someone@example.test',
      url: 'https://photos.example.test',
      created: 21,
      updated: 6,
    ),
  ];
}

void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_select_shots');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Widget Function(Widget) scope() =>
      (app) => AppScope(services: services, child: app);

  Future<void> vault(WidgetTester tester) => tester.runAsync(() async {
    await services.session.init();
    await services.session.createVault(testMasterPassword);
    await services.session.saveEntries(_entries());
  });

  AppLocalizations l(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(Scaffold).first));

  bool isWide(WidgetTester t) =>
      t.view.physicalSize.width / t.view.devicePixelRatio >= 900;

  /// Long-presses the first row, then ticks two more.
  Future<void> pickThree(WidgetTester t) async {
    await t.longPress(find.text('Old forum'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Free trial nobody uses'));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('News site'));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('sort menu open', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-sort-menu',
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.byType(EntrySortButton));
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  });

  testWidgets('selection mode, three ticked', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-three',
      wrap: scope(),
      afterPump: (t) async {
        // Wide: an entry is open in the pane; selecting leaves it alone.
        if (isWide(t)) {
          await t.tap(find.text('Mail'));
          await t.pump(const Duration(milliseconds: 300));
        }
        await pickThree(t);
      },
    );
  });

  testWidgets('delete dialog', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-delete',
      wrap: scope(),
      afterPump: (t) async {
        await pickThree(t);
        final strings = l(t);
        await t.tap(
          isWide(t)
              ? find.widgetWithText(FilledButton, strings.delete)
              : find.byTooltip(strings.deleteSelected),
        );
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  });

  testWidgets('a row under the mouse, and other sort orders', (tester) async {
    await vault(tester);
    // One mouse for every variant: a second one on the same device trips
    // the mouse tracker.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-hover',
      sizes: [ShotSize.desktop],
      themes: [Brightness.dark, Brightness.light],
      locales: [const Locale('en')],
      wrap: scope(),
      afterPump: (t) async {
        await mouse.moveTo(Offset.zero);
        await t.pump();
        await mouse.moveTo(t.getCenter(find.text('Old forum')));
        await t.pump(const Duration(milliseconds: 300));
      },
    );
    services.settings.entrySort = EntrySort.title;
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-by-name',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      wrap: scope(),
    );
  });

  testWidgets('large text', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-x2-list',
      sizes: [ShotSize.narrow],
      themes: [Brightness.dark],
      textScale: 2,
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-x2-three',
      sizes: [ShotSize.narrow],
      themes: [Brightness.dark],
      textScale: 2,
      wrap: scope(),
      afterPump: (t) async {
        await t.longPress(find.text('البنك'));
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.text('Mail'));
        await t.pump(const Duration(milliseconds: 300));
      },
    );
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-x2-menu',
      sizes: [ShotSize.narrow],
      themes: [Brightness.light],
      textScale: 2,
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.byType(EntrySortButton));
        await t.pump(const Duration(milliseconds: 400));
      },
    );
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-x2-delete',
      sizes: [ShotSize.narrow],
      themes: [Brightness.dark],
      textScale: 2,
      wrap: scope(),
      afterPump: (t) async {
        await t.longPress(find.text('Mail'));
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.byTooltip(l(t).deleteSelected));
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  });

  // --- sync waiting for the user ----------------------------------------------

  AppServices synced(SyncService sync) => AppServices(
    session: services.session,
    settings: services.settings,
    clipboard: services.clipboard,
    generator: services.generator,
    strength: services.strength,
    importExport: services.importExport,
    bridge: services.bridge,
    breaches: services.breaches,
    favicons: services.favicons,
    sync: sync,
  );

  testWidgets('another device deleted most of the vault', (tester) async {
    await vault(tester);
    await tester.runAsync(
      () => services.settings.update((x) => x.syncEmail = 'me@example.test'),
    );
    final sync = FakeSync(pending: 7);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-sync-prompt',
      wrap: (app) => AppScope(services: synced(sync), child: app),
    );
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-sync-prompt-x2',
      sizes: [ShotSize.narrow],
      themes: [Brightness.dark],
      textScale: 2,
      wrap: (app) => AppScope(services: synced(sync), child: app),
    );
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-sync-prompt-confirm',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      wrap: (app) => AppScope(services: synced(sync), child: app),
      afterPump: (t) async {
        await t.tap(find.text(l(t).syncDeletionApply));
        await t.pump(const Duration(milliseconds: 400));
      },
    );
    await pumpScreenshots(
      tester,
      const SettingsScreen(),
      'sel-sync-prompt-settings',
      sizes: [ShotSize.custom('tall', 390, 1900), ShotSize.desktop],
      wrap: (app) => AppScope(services: synced(sync), child: app),
    );
  });

  testWidgets('delete dialog: hidden rows and the other devices', (
    tester,
  ) async {
    await vault(tester);
    final sync = FakeSync();
    Future<void> pickMostThenSearch(WidgetTester t) async {
      final strings = l(t);
      // The first row: on screen at every size and text scale.
      await t.longPress(find.text('Mail'));
      await t.pump(const Duration(milliseconds: 300));
      // Every row (with labels on a wide window, an icon button otherwise).
      final all = find.text(strings.selectAll);
      await t.tap(
        all.evaluate().isEmpty ? find.byTooltip(strings.selectAll) : all,
      );
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byType(SearchBar), 'news');
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(
        isWide(t)
            ? find.widgetWithText(FilledButton, strings.delete)
            : find.byTooltip(strings.deleteSelected),
      );
      await t.pump(const Duration(milliseconds: 400));
    }

    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-delete-notes',
      wrap: (app) => AppScope(services: synced(sync), child: app),
      afterPump: pickMostThenSearch,
    );
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'sel-delete-notes-x2',
      sizes: [ShotSize.narrow],
      themes: [Brightness.dark],
      textScale: 2,
      wrap: (app) => AppScope(services: synced(sync), child: app),
      afterPump: pickMostThenSearch,
    );
  });
}
