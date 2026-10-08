import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/app.dart';
import 'package:vaultsnap/brand.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/l10n/app_localizations.dart';
import 'package:vaultsnap/ui/app_scope.dart';
import 'package:vaultsnap/ui/entry_detail_screen.dart';
import 'package:vaultsnap/ui/entry_edit_screen.dart';
import 'package:vaultsnap/ui/quick_search_screen.dart';
import 'package:vaultsnap/ui/widgets/secret_text.dart';
import 'package:vaultsnap/ui/widgets/surface_card.dart';
import 'package:vaultsnap/ui/widgets/totp_view.dart';

import 'helpers.dart';

/// The vault screens: the entry list (phone and two-pane desktop layouts),
/// an entry's detail, the entry form and the quick-search palette. Every
/// login here is synthetic.
void main() {
  const email = 'abcde07@hotmail.com';
  const exampleKey = 'Tz8pLq2wXv9m';
  const notebookKey = 'xQmR42abCD5k';

  late Directory dir;
  late AppServices services;
  late List<MethodCall> nativeCalls;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_vault_ui');
    services = await buildTestServices(dir);
    nativeCalls = [];
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  List<VaultEntry> entries() => [
    VaultEntry(
      id: 'a',
      title: 'Example',
      username: email,
      password: exampleKey,
      url: 'https://www.example.com/',
      tags: const ['work'],
      favorite: true,
    ),
    VaultEntry(
      id: 'b',
      title: 'Notebook',
      username: 'notes@mail.com',
      password: notebookKey,
      tags: const ['home'],
    ),
  ];

  /// An unlocked vault with [list], shown in a window of [size].
  Future<void> openVault(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    List<VaultEntry>? list,
    bool app = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
      final all = list ?? entries();
      if (all.isNotEmpty) await services.session.saveEntries(all);
    });
    if (app) {
      await tester.pumpWidget(VaultSnapApp(services: services));
      await tester.pumpAndSettle();
    }
  }

  Finder row(String title) => find.widgetWithText(ListTile, title);

  /// The password of what is shown, as a [SecretText] that is masked or not.
  Finder secret(String text, {required bool masked}) => find.byWidgetPredicate(
    (w) => w is SecretText && w.text == text && w.obscure == masked,
  );

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey k,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(k);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  group('entry list on a phone', () {
    testWidgets('rows open the detail screen; Paste and Add float', (
      tester,
    ) async {
      await openVault(tester);
      expect(row('Example'), findsOneWidget);
      expect(row('Notebook'), findsOneWidget);
      // Compact: the header has no paste button, two floating buttons do.
      expect(
        find.widgetWithIcon(IconButton, Icons.content_paste),
        findsNothing,
      );
      expect(find.byType(FloatingActionButton), findsNWidgets(2));
      expect(find.text('Paste login'), findsOneWidget);

      await tester.tap(row('Example'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailScreen), findsOneWidget);
      expect(find.byType(EntryDetailView), findsOneWidget);
      // The name is in the header card, the password is masked.
      expect(find.text('Example'), findsWidgets);
      expect(secret(exampleKey, masked: true), findsOneWidget);
      expect(find.text(exampleKey), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailScreen), findsNothing);
    });

    testWidgets('a new vault shows an empty state with the two actions', (
      tester,
    ) async {
      await openVault(tester, list: const []);
      expect(find.text('No entries yet'), findsOneWidget);
      expect(find.text(appTaglineFor(const Locale('en'))), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add entry'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Paste login'),
        findsOneWidget,
      );
      // The empty state carries them, so no floating buttons repeat them.
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Add entry'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryEditScreen), findsOneWidget);
    });

    testWidgets('pills filter by favourite and tag; "All items" resets', (
      tester,
    ) async {
      await openVault(tester);
      Finder pill(String label) => find.widgetWithText(ChoiceChip, label);
      expect(tester.widget<ChoiceChip>(pill('All items')).selected, isTrue);

      await tester.tap(pill('Favorites'));
      await tester.pumpAndSettle();
      expect(row('Example'), findsOneWidget);
      expect(row('Notebook'), findsNothing);
      expect(tester.widget<ChoiceChip>(pill('All items')).selected, isFalse);

      await tester.tap(pill('All items'));
      await tester.pumpAndSettle();
      expect(row('Notebook'), findsOneWidget);

      await tester.ensureVisible(pill('home'));
      await tester.pumpAndSettle();
      await tester.tap(pill('home'));
      await tester.pumpAndSettle();
      expect(row('Example'), findsNothing);
      expect(row('Notebook'), findsOneWidget);
    });

    testWidgets('a search that matches nothing offers to clear it', (
      tester,
    ) async {
      await openVault(tester);
      await tester.enterText(find.byType(SearchBar), 'zzz');
      await tester.pumpAndSettle();
      expect(row('Example'), findsNothing);
      // A search that matches nothing is "No results", not an empty vault.
      expect(find.text('No results'), findsOneWidget);
      expect(find.text('No entries yet'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        isEmpty,
      );
      expect(row('Example'), findsOneWidget);
    });

    testWidgets('the copy button copies the password and says nothing '
        'about it', (tester) async {
      await openVault(tester);
      final card = find.ancestor(
        of: row('Example'),
        matching: find.byType(SurfaceCard),
      );
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip('Copy')),
      );
      await tester.pumpAndSettle();
      final copy = nativeCalls.where((c) => c.method == 'copySensitive');
      expect((copy.single.arguments as Map)['text'], exampleKey);
      expect(find.textContaining(exampleKey), findsNothing);
      await services.clipboard.clearNow();
    });

    testWidgets('Ctrl+F focuses the search field, Ctrl+N starts an entry', (
      tester,
    ) async {
      await openVault(tester);
      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyF,
      );
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).focusNode!.hasFocus,
        isTrue,
      );
      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyN,
      );
      expect(find.byType(EntryEditScreen), findsOneWidget);
    });
  });

  group('entry list on a wide window', () {
    const wide = Size(1280, 800);

    testWidgets('a row opens in the pane; the next row starts masked', (
      tester,
    ) async {
      await openVault(tester, size: wide);
      // Header buttons instead of floating ones; no entry open yet.
      expect(
        find.widgetWithIcon(IconButton, Icons.content_paste),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(EntryDetailView), findsNothing);
      expect(find.text(appNameFor(const Locale('en'))), findsOneWidget);

      await tester.tap(row('Example'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailScreen), findsNothing);
      expect(find.byType(EntryDetailView), findsOneWidget);
      expect(secret(exampleKey, masked: true), findsOneWidget);

      await tester.tap(find.byTooltip('Show'));
      await tester.pumpAndSettle();
      expect(secret(exampleKey, masked: false), findsOneWidget);

      await tester.tap(row('Notebook'));
      await tester.pumpAndSettle();
      expect(secret(exampleKey, masked: false), findsNothing);
      expect(secret(notebookKey, masked: true), findsOneWidget);
      // The one that was open before is not on screen any more.
      expect(find.text(exampleKey), findsNothing);
    });

    testWidgets('arrow keys in the search field move the open row, Escape '
        'clears the search', (tester) async {
      await openVault(tester, size: wide);
      await tester.tap(find.byType(SearchBar));
      await tester.pumpAndSettle();

      String open() =>
          tester.widget<EntryDetailView>(find.byType(EntryDetailView)).entryId;
      await key(tester, LogicalKeyboardKey.arrowDown);
      final first = open();
      await key(tester, LogicalKeyboardKey.arrowDown);
      final second = open();
      expect(second, isNot(first));
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(open(), first);

      await tester.enterText(find.byType(SearchBar), 'Exa');
      await tester.pumpAndSettle();
      expect(row('Notebook'), findsNothing);
      await key(tester, LogicalKeyboardKey.escape);
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        isEmpty,
      );
      expect(row('Notebook'), findsOneWidget);
    });

    testWidgets('deleting the open entry from the pane asks first and '
        'empties the pane', (tester) async {
      await openVault(tester, size: wide);
      await tester.tap(row('Notebook'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      // Cancel keeps it.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(services.session.entries, hasLength(2));

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Delete')),
      );
      for (var i = 0; i < 100 && services.session.entries.length > 1; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(services.session.entries.map((e) => e.id), ['a']);
      expect(find.byType(EntryDetailView), findsNothing);
      expect(row('Notebook'), findsNothing);
    });
  });

  group('entry detail', () {
    testWidgets('shows the one-time code and keeps it out of the labels', (
      tester,
    ) async {
      final withCode = VaultEntry(
        id: 'c',
        title: 'Example',
        username: email,
        password: exampleKey,
        // RFC 6238 example secret, tied to no account.
        totpSecret: 'JBSWY3DPEHPK3PXP',
      );
      await openVault(tester, list: [withCode], app: false);
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const EntryDetailScreen(entryId: 'c'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TotpView), findsOneWidget);
      expect(find.text('One-time code'), findsOneWidget);
      final code = find.byWidgetPredicate(
        (w) => w is SecretText && RegExp(r'^\d{3} \d{3}$').hasMatch(w.text),
      );
      expect(code, findsOneWidget);
      // The username, the password's strength and the tooltips never carry
      // the password or the code.
      final handle = tester.ensureSemantics();
      final text = (code.evaluate().single.widget as SecretText).text;
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(text))), findsNothing);
      expect(find.bySemanticsLabel(RegExp(exampleKey)), findsNothing);
      handle.dispose();

      // Unmount: the code refreshes on a timer.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an entry that is gone leaves a blank screen with a back '
        'button', (tester) async {
      await openVault(tester, app: false);
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: Text('before')),
          ),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const EntryDetailScreen(entryId: 'nope'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailView), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  group('entry form', () {
    testWidgets('Add entry saves what was typed', (tester) async {
      await openVault(tester, list: const []);
      await tester.tap(find.widgetWithText(FilledButton, 'Add entry'));
      await tester.pumpAndSettle();

      Finder field(String label) => find.widgetWithText(TextField, label);
      await tester.enterText(field('Title'), 'Work email');
      await tester.enterText(field('Email / username'), email);
      await tester.enterText(field('Password'), notebookKey);
      await tester.pumpAndSettle();
      // Typed passwords are masked until asked for.
      expect(tester.widget<TextField>(field('Password')).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show'));
      await tester.pumpAndSettle();
      expect(secret(notebookKey, masked: false), findsOneWidget);

      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Save')),
      );
      for (var i = 0; i < 200 && services.session.entries.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final saved = services.session.entries.single;
      expect(saved.title, 'Work email');
      expect(saved.username, email);
      expect(saved.password, notebookKey);
      expect(find.byType(EntryEditScreen), findsNothing);
      expect(row('Work email'), findsOneWidget);
    });

    testWidgets('a bad TOTP secret is reported and nothing is saved', (
      tester,
    ) async {
      await openVault(tester, list: const []);
      await tester.tap(find.widgetWithText(FilledButton, 'Add entry'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'TOTP secret or otpauth:// URI'),
        '!!not base32!!',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid TOTP secret'), findsOneWidget);
      expect(services.session.entries, isEmpty);
    });
  });

  group('quick search', () {
    Future<void> openPalette(WidgetTester tester) async {
      await openVault(tester, size: const Size(640, 520), app: false);
      mockChannel(tester, const MethodChannel('window_manager'), (_) async {
        return null;
      });
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const QuickSearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('typing filters; Enter copies the password, Shift+Enter '
        'the username', (tester) async {
      await openPalette(tester);
      expect(find.text('Example'), findsOneWidget);
      expect(find.text('Notebook'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'note');
      await tester.pumpAndSettle();
      expect(find.text('Example'), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      final copied = nativeCalls
          .where((c) => c.method == 'copySensitive')
          .map((c) => (c.arguments as Map)['text'])
          .toList();
      expect(copied, [notebookKey]);
      await services.clipboard.clearNow();
    });

    testWidgets('a row can be tapped to copy its password', (tester) async {
      await openPalette(tester);
      await tester.tap(find.text('Example'));
      await tester.pumpAndSettle();
      final copied = nativeCalls
          .where((c) => c.method == 'copySensitive')
          .map((c) => (c.arguments as Map)['text'])
          .toList();
      expect(copied, [exampleKey]);
      await services.clipboard.clearNow();
    });

    testWidgets('Shift+Enter copies the username instead', (tester) async {
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'note');
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      final copied = nativeCalls
          .where((c) => c.method == 'copySensitive')
          .map((c) => (c.arguments as Map)['text'])
          .toList();
      expect(copied, ['notes@mail.com']);
      await services.clipboard.clearNow();
    });

    testWidgets('the arrow keys move the highlight', (tester) async {
      await openPalette(tester);
      Finder selectedRow() => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected == true,
      );
      expect(selectedRow(), findsOneWidget);
      final before = tester.getTopLeft(selectedRow().first);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(tester.getTopLeft(selectedRow().first), isNot(before));
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(tester.getTopLeft(selectedRow().first), before);
    });

    testWidgets('nothing found shows the empty message', (tester) async {
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'qqq');
      await tester.pumpAndSettle();
      // The vault has entries; nothing matched the query.
      expect(find.text('No results'), findsOneWidget);
      expect(find.text('No entries yet'), findsNothing);
    });
  });
}
