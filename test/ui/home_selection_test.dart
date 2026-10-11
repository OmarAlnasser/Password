import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/entry_sort.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/entry_detail_screen.dart';
import 'package:hisn/ui/home_screen.dart';
import 'package:hisn/ui/quick_search_screen.dart';
import 'package:hisn/ui/theme/app_theme.dart';
import 'package:hisn/ui/widgets/brand_mark.dart';
import 'package:hisn/ui/widgets/entry_sort_button.dart';
import 'package:hisn/ui/widgets/surface_card.dart';

import 'helpers.dart';

/// The entry list's sort control, "recently used" tracking, selection mode
/// and mass delete, with the real `VaultSession`. Every login is synthetic.
void main() {
  late Directory dir;
  late AppServices services;
  late List<MethodCall> nativeCalls;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_home_select');
    services = await buildTestServices(dir);
    nativeCalls = [];
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  // Dates far in the past, so "now" (a use) is always newer.
  DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

  /// Five entries whose three orders all differ:
  /// * recent (by updatedAt): delta, alpha, charlie, bravo
  /// * name: alpha, bravo, charlie, delta
  /// * added (by createdAt): charlie, bravo, alpha, delta
  /// and echo, a favourite, pinned above them in every order.
  List<VaultEntry> entries() => [
    VaultEntry(
      id: 'alpha',
      title: 'Alpha Mail',
      username: 'alpha@example.test',
      password: 'hunter-test-1',
      url: 'https://mail.example.test',
      tags: const ['work'],
      createdAt: day(2020, 1, 1),
      updatedAt: day(2020, 3, 1),
    ),
    VaultEntry(
      id: 'bravo',
      title: 'Bravo Bank',
      username: 'bravo@example.test',
      password: 'hunter-test-2',
      tags: const ['money'],
      createdAt: day(2020, 2, 1),
      updatedAt: day(2020, 1, 15),
    ),
    VaultEntry(
      id: 'charlie',
      title: 'Charlie Chat',
      username: 'charlie@example.test',
      password: 'hunter-test-3',
      // RFC 6238 example secret, tied to no account.
      totpSecret: 'JBSWY3DPEHPK3PXP',
      tags: const ['work'],
      createdAt: day(2020, 3, 1),
      updatedAt: day(2020, 2, 1),
    ),
    VaultEntry(
      id: 'delta',
      title: 'Delta Docs',
      username: 'delta@example.test',
      password: 'hunter-test-4',
      tags: const ['work'],
      createdAt: day(2019, 12, 1),
      updatedAt: day(2020, 4, 1),
    ),
    VaultEntry(
      id: 'echo',
      title: 'Echo Games',
      username: 'echo@example.test',
      password: 'hunter-test-5',
      favorite: true,
      tags: const ['fun'],
      createdAt: day(2019, 6, 1),
      updatedAt: day(2019, 6, 1),
    ),
  ];

  /// An unlocked vault with [entries], the clipboard channel mocked.
  Future<void> vault(WidgetTester tester, {List<VaultEntry>? list}) async {
    mockChannel(tester, platformChannel, (call) async {
      nativeCalls.add(call);
      return switch (call.method) {
        'copySensitive' || 'clearClipboardIfMatches' => true,
        _ => null,
      };
    });
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      await services.session.saveEntries(list ?? entries());
    });
  }

  /// [home] in a window of [size], in [locale], at [textScale].
  Future<void> show(
    WidgetTester tester, {
    Widget home = const HomeScreen(),
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

  Finder row(String title) => find.widgetWithText(ListTile, title);

  /// The titles of the rows, top to bottom.
  List<String> order(WidgetTester tester) => [
    for (final t in tester.widgetList<ListTile>(find.byType(ListTile)))
      (t.title! as EntryTitle).text,
  ];

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  Future<void> longPress(WidgetTester tester, String title) async {
    await tester.longPress(row(title));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Set<String> ids() => {for (final e in services.session.entries) e.id};

  /// Lets the database transaction of a delete run until [done].
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  group('sort control', () {
    testWidgets('shows the active order and switches it; favourites stay on '
        'top; the choice is saved in the settings', (tester) async {
      await vault(tester);
      await show(tester);
      // Nothing used yet: "Recently used" falls back to the last edit.
      expect(services.settings.entrySort, EntrySort.recent);
      expect(find.text('Recently used'), findsOneWidget);
      expect(order(tester), [
        'Echo Games',
        'Delta Docs',
        'Alpha Mail',
        'Charlie Chat',
        'Bravo Bank',
      ]);

      await tap(tester, find.byType(EntrySortButton));
      // The menu lists the three orders.
      expect(find.text('Name (A–Z)'), findsOneWidget);
      expect(find.text('Recently added'), findsOneWidget);
      await tap(tester, find.text('Name (A–Z)'));
      expect(services.settings.entrySort, EntrySort.title);
      expect(find.text('Name (A–Z)'), findsOneWidget);
      expect(find.text('Recently used'), findsNothing);
      expect(order(tester), [
        'Echo Games',
        'Alpha Mail',
        'Bravo Bank',
        'Charlie Chat',
        'Delta Docs',
      ]);

      await tap(tester, find.byType(EntrySortButton));
      await tap(tester, find.text('Recently added'));
      expect(services.settings.entrySort, EntrySort.added);
      expect(order(tester), [
        'Echo Games',
        'Charlie Chat',
        'Bravo Bank',
        'Alpha Mail',
        'Delta Docs',
      ]);
    });

    testWidgets('a setting changed elsewhere reorders the list', (
      tester,
    ) async {
      await vault(tester);
      await show(tester);
      services.settings.entrySort = EntrySort.title;
      await tester.pumpAndSettle();
      expect(order(tester).take(2), ['Echo Games', 'Alpha Mail']);
      expect(find.text('Name (A–Z)'), findsOneWidget);
    });

    testWidgets('the menu marks the active order for a screen reader and the '
        'pill names itself', (tester) async {
      await vault(tester);
      await show(tester);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Sorted by Recently used'), findsOneWidget);
      await tap(tester, find.byType(EntrySortButton));
      expect(
        tester.getSemantics(find.text('Recently used').last),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.text('Name (A–Z)')),
        isSemantics(isSelected: false),
      );
      // Escape closes the menu and changes nothing.
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.text('Name (A–Z)'), findsNothing);
      expect(services.settings.entrySort, EntrySort.recent);
      handle.dispose();
    });
  });

  group('recently used', () {
    testWidgets('copying from a row marks the entry; searching does not; the '
        'row stays under the finger until the list is shown again', (
      tester,
    ) async {
      await vault(tester);
      await show(tester);
      await tester.enterText(find.byType(SearchBar), 'bank');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), '');
      await tester.pumpAndSettle();
      expect(services.session.lastUsedMap, isEmpty);
      final before = order(tester);
      expect(before.last, 'Bravo Bank');

      final card = find.ancestor(
        of: row('Bravo Bank'),
        matching: find.byType(SurfaceCard),
      );
      final copy = find.descendant(of: card, matching: find.byTooltip('Copy'));
      final spot = tester.getCenter(copy);
      await tap(tester, copy);
      expect(services.session.lastUsedAt('bravo'), isNotNull);
      expect(services.session.lastUsedMap.keys, ['bravo']);
      // Nothing moved: a second tap on the same spot copies the same
      // password, not the one of the entry that would have slid under it.
      expect(order(tester), before);
      await tester.tapAt(spot);
      await tester.pumpAndSettle();
      final copied = nativeCalls.where((c) => c.method == 'copySensitive');
      expect(
        [for (final c in copied) (c.arguments as Map)['text']],
        ['hunter-test-2', 'hunter-test-2'],
      );

      // Back from an entry, the list shows the use: first after the pinned
      // favourite.
      await tap(tester, row('Alpha Mail'));
      expect(find.byType(EntryDetailScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(order(tester).take(2), ['Echo Games', 'Bravo Bank']);
      await services.clipboard.clearNow();
    });

    testWidgets('two panes: showing the password of the open entry does not '
        'move its row; coming back to the app does', (tester) async {
      await vault(tester);
      await show(tester, size: const Size(1280, 800));
      final before = order(tester);
      expect(before.last, 'Bravo Bank');
      await tap(tester, row('Bravo Bank'));
      await tap(tester, find.byTooltip('Show'));
      expect(services.session.lastUsedAt('bravo'), isNotNull);
      expect(order(tester), before);

      // The app went to the background (a browser, to paste) and back.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(order(tester).take(2), ['Echo Games', 'Bravo Bank']);
      // Unmount: the open entry's one-time code view is not there, but the
      // reveal timer is.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a new search shows the newest order', (tester) async {
      await vault(tester);
      await show(tester);
      await tester.runAsync(() => services.session.markUsed('bravo'));
      await tester.pumpAndSettle();
      expect(order(tester).last, 'Bravo Bank');
      await tester.enterText(find.byType(SearchBar), 'example');
      await tester.pumpAndSettle();
      expect(order(tester).take(2), ['Echo Games', 'Bravo Bank']);
    });

    testWidgets('the detail screen: opening is not a use; copying the '
        'username, showing the password and copying the one-time code are', (
      tester,
    ) async {
      await vault(tester);
      // Keyed: a fresh screen per entry, as a pushed route would be.
      Future<void> detail(String id) => show(
        tester,
        home: EntryDetailScreen(key: ValueKey(id), entryId: id),
      );

      /// The copy button on the line labelled [label].
      Finder copyOf(String label) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byTooltip('Copy'),
      );

      await detail('alpha');
      expect(services.session.lastUsedAt('alpha'), isNull);
      await tap(tester, copyOf('Email / username'));
      expect(services.session.lastUsedAt('alpha'), isNotNull);

      await detail('bravo');
      expect(services.session.lastUsedAt('bravo'), isNull);
      await tap(tester, find.byTooltip('Show'));
      expect(services.session.lastUsedAt('bravo'), isNotNull);

      await detail('charlie');
      expect(services.session.lastUsedAt('charlie'), isNull);
      await tap(tester, copyOf('One-time code'));
      expect(services.session.lastUsedAt('charlie'), isNotNull);
      // Nothing secret was shown in a toast.
      expect(find.textContaining('hunter-test'), findsNothing);
      await services.clipboard.clearNow();
      // Unmount: the one-time code refreshes on a timer.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quick search: copying a result marks it', (tester) async {
      await vault(tester);
      mockChannel(tester, const MethodChannel('window_manager'), (_) async {
        return null;
      });
      await show(
        tester,
        home: const QuickSearchScreen(),
        size: const Size(640, 520),
      );
      await tester.enterText(find.byType(TextField), 'delta');
      await tester.pumpAndSettle();
      expect(services.session.lastUsedAt('delta'), isNull);
      await tap(tester, find.text('Delta Docs'));
      expect(services.session.lastUsedAt('delta'), isNotNull);
      expect(services.session.lastUsedMap.keys, ['delta']);
      await services.clipboard.clearNow();
    });
  });

  group('selection mode on a phone', () {
    testWidgets('a long press enters it; taps tick rows; Escape leaves it', (
      tester,
    ) async {
      await vault(tester);
      await show(tester);
      expect(find.byType(FloatingActionButton), findsNWidgets(2));

      await longPress(tester, 'Alpha Mail');
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(BrandLockup), findsNothing);
      expect(find.byTooltip('Done selecting'), findsOneWidget);
      // No floating buttons and no copy buttons while selecting.
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('Copy'), findsNothing);
      expect(find.byType(Checkbox), findsNWidgets(5));

      await tap(tester, row('Bravo Bank'));
      expect(find.text('2 selected'), findsOneWidget);
      // A tap ticks, it does not open.
      expect(find.byType(EntryDetailScreen), findsNothing);
      await tap(tester, row('Alpha Mail'));
      expect(find.text('1 selected'), findsOneWidget);
      // Ticking the box itself works too.
      final alphaBox = find.descendant(
        of: find.ancestor(of: row('Alpha Mail'), matching: find.byType(Row)),
        matching: find.byType(Checkbox),
      );
      await tap(tester, alphaBox.first);
      expect(find.text('2 selected'), findsOneWidget);

      await key(tester, LogicalKeyboardKey.escape);
      expect(find.textContaining('selected'), findsNothing);
      expect(find.byType(BrandLockup), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      // Out of selection mode a tap opens the entry again.
      await tap(tester, row('Bravo Bank'));
      expect(find.byType(EntryDetailScreen), findsOneWidget);
    });

    testWidgets('Back leaves selection mode first; the close button too', (
      tester,
    ) async {
      await vault(tester);
      await show(tester);
      await longPress(tester, 'Alpha Mail');
      expect(find.text('1 selected'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);

      await longPress(tester, 'Alpha Mail');
      await tap(tester, find.byTooltip('Done selecting'));
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('"Select" in the menu starts with nothing ticked; Delete '
        'waits for a tick', (tester) async {
      await vault(tester);
      await show(tester);
      await tap(tester, find.byIcon(Icons.more_vert_rounded));
      await tap(tester, find.text('Select'));
      expect(find.text('None selected'), findsOneWidget);
      final delete = find.widgetWithIcon(
        IconButton,
        Icons.delete_outline_rounded,
      );
      expect(tester.widget<IconButton>(delete).onPressed, isNull);
      await tap(tester, row('Delta Docs'));
      expect(tester.widget<IconButton>(delete).onPressed, isNotNull);
    });

    testWidgets('Escape in the search field leaves selection mode before it '
        'clears the search', (tester) async {
      await vault(tester);
      await show(tester);
      await longPress(tester, 'Alpha Mail');
      await tester.tap(find.byType(SearchBar));
      await tester.enterText(find.byType(SearchBar), 'mail');
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.textContaining('selected'), findsNothing);
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        'mail',
      );
    });

    testWidgets('select all works on the listed rows; the search can change '
        'and the count stays the real number', (tester) async {
      await vault(tester);
      await show(tester);
      await longPress(tester, 'Echo Games');
      await tester.enterText(find.byType(SearchBar), 'work');
      await tester.pumpAndSettle();
      expect(order(tester), ['Delta Docs', 'Alpha Mail', 'Charlie Chat']);
      // Echo is filtered out but still ticked.
      expect(find.text('1 selected'), findsOneWidget);

      await tap(tester, find.byTooltip('Select all'));
      expect(find.text('4 selected'), findsOneWidget);
      // All listed rows are ticked: the action now clears the selection,
      // all of it, the tick the search hides too.
      expect(find.byTooltip('Select all'), findsNothing);
      await tap(tester, find.byTooltip('Clear selection'));
      expect(find.text('None selected'), findsOneWidget);
      await tap(tester, find.byTooltip('Select all'));
      expect(find.text('3 selected'), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), 'bank');
      await tester.pumpAndSettle();
      expect(order(tester), ['Bravo Bank']);
      expect(find.text('3 selected'), findsOneWidget);

      // Deleting while the ticked rows are hidden: the dialog says so.
      await tap(tester, find.byTooltip('Delete selected'));
      expect(find.text('Delete 3 entries?'), findsOneWidget);
      expect(
        find.text('3 of them are hidden by the search or filter.'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(TextButton, 'Cancel'));

      await tester.enterText(find.byType(SearchBar), '');
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);

      // Delete takes exactly the three ticked ones; none is hidden now.
      await tap(tester, find.byTooltip('Delete selected'));
      expect(find.text('Delete 3 entries?'), findsOneWidget);
      expect(find.textContaining('hidden by the search'), findsNothing);
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Delete')),
      );
      await settleUntil(tester, () => ids().length < 5);
      expect(ids(), {'bravo', 'echo'});
    });

    testWidgets('one hidden tick is named in the dialog, in English and '
        'Arabic', (tester) async {
      await vault(tester);
      await show(tester, locale: const Locale('ar'));
      await longPress(tester, 'Echo Games');
      await tester.enterText(find.byType(SearchBar), 'work');
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('حذف المحدد'));
      expect(find.text('حذف عنصر واحد؟'), findsOneWidget);
      expect(
        find.text('عنصر واحد منها لا يظهر بسبب البحث أو التصفية.'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(TextButton, 'إلغاء'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        en.deleteHiddenCount(1),
        '1 of them is hidden by the search or filter.',
      );
    });

    testWidgets('delete: Cancel keeps everything; Delete removes exactly the '
        'ticked entries in one go and says how many', (tester) async {
      await vault(tester);
      var syncCalls = 0;
      services.session.onLocalChange.add(() => syncCalls++);
      await show(tester);
      await longPress(tester, 'Alpha Mail');
      await tap(tester, row('Charlie Chat'));
      await tap(tester, row('Echo Games'));
      expect(find.text('3 selected'), findsOneWidget);

      await tap(tester, find.byTooltip('Delete selected'));
      expect(find.text('Delete 3 entries?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(ids(), hasLength(5));
      expect(find.text('3 selected'), findsOneWidget);
      expect(syncCalls, 0);

      await tap(tester, find.byTooltip('Delete selected'));
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Delete')),
      );
      await settleUntil(tester, () => ids().length < 5);
      expect(ids(), {'bravo', 'delta'});
      // One batch: sync was told once.
      expect(syncCalls, 1);
      expect(find.text('3 entries deleted'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);
      expect(order(tester), ['Delta Docs', 'Bravo Bank']);
    });

    testWidgets('an entry that disappears while ticked is not counted and '
        'not deleted again', (tester) async {
      await vault(tester);
      await show(tester);
      await longPress(tester, 'Alpha Mail');
      await tap(tester, row('Bravo Bank'));
      expect(find.text('2 selected'), findsOneWidget);
      // Deleted elsewhere (sync, the other pane).
      await tester.runAsync(() => services.session.deleteEntry('bravo'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(row('Bravo Bank'), findsNothing);

      await tap(tester, find.byTooltip('Delete selected'));
      expect(find.text('Delete 1 entry?'), findsOneWidget);
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Delete')),
      );
      await settleUntil(tester, () => ids().length < 4);
      expect(ids(), {'charlie', 'delta', 'echo'});
      expect(find.text('1 entry deleted'), findsOneWidget);
    });

    testWidgets('a screen reader hears each row as selected or not, and the '
        'count as a live region; never a password', (tester) async {
      await vault(tester);
      await show(tester);
      final handle = tester.ensureSemantics();
      await longPress(tester, 'Alpha Mail');
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Alpha Mail, alpha@example.test'),
        ),
        isSemantics(
          hasSelectedState: true,
          isSelected: true,
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Bravo Bank, bravo@example.test'),
        ),
        isSemantics(
          hasSelectedState: true,
          isSelected: false,
          hasCheckedState: true,
          isChecked: false,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('1 selected')),
        isSemantics(isLiveRegion: true),
      );
      expect(find.bySemanticsLabel(RegExp('hunter-test')), findsNothing);
      handle.dispose();
    });
  });

  group('selection mode on a wide window', () {
    const wide = Size(1280, 800);

    testWidgets('selecting never opens the pane; Ctrl+click starts it; the '
        'bar has labelled buttons', (tester) async {
      await vault(tester);
      await show(tester, size: wide);
      await longPress(tester, 'Alpha Mail');
      expect(find.byType(EntryDetailView), findsNothing);
      await tap(tester, row('Bravo Bank'));
      expect(find.byType(EntryDetailView), findsNothing);
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Select all'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);

      // Open one, then Ctrl+click another: it is ticked, the pane stays.
      await tap(tester, row('Delta Docs'));
      expect(
        tester.widget<EntryDetailView>(find.byType(EntryDetailView)).entryId,
        'delta',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(row('Charlie Chat'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        tester.widget<EntryDetailView>(find.byType(EntryDetailView)).entryId,
        'delta',
      );
      // The bar's Delete takes the ticked entry, not the open one.
      await tap(tester, find.widgetWithText(FilledButton, 'Delete'));
      expect(find.text('Delete 1 entry?'), findsOneWidget);
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Delete').last),
      );
      await settleUntil(tester, () => ids().length < 5);
      expect(ids().contains('charlie'), isFalse);
      expect(ids().contains('delta'), isTrue);
    });

    testWidgets('the arrow keys in the search field leave the pane alone '
        'while selecting', (tester) async {
      await vault(tester);
      await show(tester, size: wide);
      Finder pane() => find.byType(EntryDetailView);
      String? open() => pane().evaluate().isEmpty
          ? null
          : tester.widget<EntryDetailView>(pane()).entryId;

      // Outside selection mode the arrows move the open row.
      await tap(tester, row('Alpha Mail'));
      expect(open(), 'alpha');
      await tester.tap(find.byType(SearchBar));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(open(), isNot('alpha'));
      await tap(tester, row('Alpha Mail'));
      expect(open(), 'alpha');

      await longPress(tester, 'Charlie Chat');
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byType(SearchBar));
      await tester.pumpAndSettle();
      final scrolled = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .pixels;
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(open(), 'alpha');
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .pixels,
        scrolled,
      );

      // Nothing open: the arrows open nothing either.
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpWidget(const SizedBox());
      await show(tester, size: wide);
      await longPress(tester, 'Charlie Chat');
      await tester.tap(find.byType(SearchBar));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(pane(), findsNothing);
    });

    testWidgets('under a mouse a row shows a check box that starts '
        'selection', (tester) async {
      await vault(tester);
      await show(tester, size: wide);
      expect(find.byType(Checkbox), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(row('Alpha Mail')));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsOneWidget);
      final box = tester.getCenter(find.byType(Checkbox));
      await mouse.down(box);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(EntryDetailView), findsNothing);
      // The ticked box is where the pointer is.
      final ticked = find.byWidgetPredicate(
        (w) => w is Checkbox && w.value == true,
      );
      expect((tester.getCenter(ticked) - box).distance, lessThan(2));
    });
  });

  group('Arabic and large text', () {
    testWidgets('Arabic: right to left, Arabic plurals, Arabic sort names', (
      tester,
    ) async {
      await vault(tester);
      await show(tester, locale: const Locale('ar'));
      expect(find.text('المستخدمة مؤخرًا'), findsOneWidget);
      await longPress(tester, 'Alpha Mail');
      expect(find.text('عنصر واحد محدد'), findsOneWidget);
      await tap(tester, row('Bravo Bank'));
      expect(find.text('عنصران محددان'), findsOneWidget);
      await tap(tester, row('Charlie Chat'));
      expect(find.text('3 عناصر محددة'), findsOneWidget);
      // The check box leads the row: on the right in Arabic.
      final alpha = find.ancestor(
        of: row('Alpha Mail'),
        matching: find.byType(Row),
      );
      final box = find.descendant(
        of: alpha.first,
        matching: find.byType(Checkbox),
      );
      expect(
        tester.getCenter(box).dx,
        greaterThan(tester.getCenter(row('Alpha Mail')).dx),
      );
      await tap(tester, find.byTooltip('حذف المحدد'));
      expect(find.text('حذف 3 عناصر؟'), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, 'إلغاء'));
      expect(ids(), hasLength(5));
      expect(tester.takeException(), isNull);
    });

    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets('200% text on a small phone (${locale.languageCode}): the '
          'heading, selection bar, sort menu and dialog fit', (tester) async {
        await vault(tester);
        await show(
          tester,
          size: const Size(360, 640),
          locale: locale,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        await tap(tester, find.byType(EntrySortButton));
        expect(tester.takeException(), isNull);
        await key(tester, LogicalKeyboardKey.escape);
        await longPress(tester, 'Echo Games');
        expect(tester.takeException(), isNull);
        final l = lookupAppLocalizations(locale);
        await tap(tester, find.byTooltip(l.deleteSelected));
        expect(find.text(l.deleteEntriesTitle(1)), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tap(tester, find.widgetWithText(TextButton, l.cancel));
      });
    }

    testWidgets('200% text on a wide window: the labelled bar gives way to '
        'icon buttons', (tester) async {
      await vault(tester);
      await show(tester, size: const Size(1280, 800), textScale: 2);
      await longPress(tester, 'Echo Games');
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Delete selected'), findsOneWidget);
    });
  });

  test('Arabic and English counts use the right plural forms', () {
    final ar = lookupAppLocalizations(const Locale('ar'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      [
        for (final n in [0, 1, 2, 3, 10, 11, 99, 100, 101]) ar.selectedCount(n),
      ],
      [
        'لا عناصر محددة',
        'عنصر واحد محدد',
        'عنصران محددان',
        '3 عناصر محددة',
        '10 عناصر محددة',
        '11 عنصرًا محددًا',
        '99 عنصرًا محددًا',
        '100 عنصر محدد',
        '101 عنصر محدد',
      ],
    );
    expect(ar.deleteEntriesTitle(12), 'حذف 12 عنصرًا؟');
    expect(ar.entriesDeleted(2), 'تم حذف عنصرين');
    expect(en.selectedCount(1), '1 selected');
    expect(en.deleteEntriesTitle(1), 'Delete 1 entry?');
    expect(en.deleteEntriesTitle(12), 'Delete 12 entries?');
    expect(en.entriesDeleted(12), '12 entries deleted');
  });
}
