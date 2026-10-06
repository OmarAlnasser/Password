import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/app.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/ui/app_scope.dart';
import 'package:vaultsnap/ui/widgets/secret_text.dart';

import 'helpers.dart';

/// "Paste" on the entry list: clipboard text or a screenshot becomes a login
/// in a bottom sheet. All values are synthetic.
void main() {
  late Directory dir;
  late AppServices services;
  late List<String> nativeCalls;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_paste');
    services = await buildTestServices(dir);
    nativeCalls = [];
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  /// Shows the entry list of a new vault. The native side answers
  /// `readClipboard` with [clipboard] and OCR with [ocrLines].
  Future<void> openVault(
    WidgetTester tester, {
    required Map<String, Object?> clipboard,
    List<String> ocrLines = const [],
    List<VaultEntry> entries = const [],
  }) async {
    mockChannel(tester, platformChannel, (call) async {
      nativeCalls.add(call.method);
      return switch (call.method) {
        'readClipboard' => clipboard,
        'clearClipboard' ||
        'copySensitive' ||
        'clearClipboardIfMatches' => true,
        'ocr' => ocrLines, // Windows.Media.Ocr
        _ => null,
      };
    });
    // ML Kit (Android, iOS, and the test host).
    mockChannel(
      tester,
      const MethodChannel('google_mlkit_text_recognizer'),
      (call) async => call.method == 'vision#startTextRecognizer'
          ? _mlKitResult(ocrLines)
          : null,
    );
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      if (entries.isNotEmpty) await services.session.saveEntries(entries);
    });
    await tester.pumpWidget(VaultSnapApp(services: services));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> pressCtrlV(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String dialogTitle) async {
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    // The vault's database works on a real isolate.
    await tester.runAsync(() => tester.tap(find.text('Save')));
    await pumpUntilFound(tester, find.text(dialogTitle));
    await tester.pumpAndSettle();
  }

  testWidgets('pasted text: Quick save names the login and clears the '
      'clipboard', (tester) async {
    await openVault(
      tester,
      clipboard: {'text': 'abcde07@hotmail.com\nxQmR42abCD5k'},
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.content_paste));
    await tester.pumpAndSettle();

    // Quick: the detected values, editable, and the password preview with
    // look-alike characters highlighted. No advanced fields.
    expect(find.text('Save login'), findsOneWidget);
    expect(field('abcde07@hotmail.com'), findsOneWidget);
    expect(field('xQmR42abCD5k'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is SecretText && w.text == 'xQmR42abCD5k',
      ),
      findsOneWidget,
    );
    expect(find.text('e.g. Genshin Odette C2 acc'), findsOneWidget);
    expect(field('Where is it from? (link)'), findsNothing);

    await tester.enterText(field('Name'), 'Genshin Odette C2 acc');
    await save(tester, 'Clear the copied text from your clipboard?');

    final e = services.session.entries.single;
    expect(e.title, 'Genshin Odette C2 acc');
    expect(e.username, 'abcde07@hotmail.com');
    expect(e.password, 'xQmR42abCD5k');
    expect(e.url, isEmpty);
    expect(e.notes, isEmpty);

    // Clear is the default action.
    expect(nativeCalls, isNot(contains('clearClipboard')));
    final clear = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Clear'),
    );
    expect(clear.autofocus, isTrue);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(nativeCalls, contains('clearClipboard'));
    expect(find.text('Clipboard cleared'), findsOneWidget);
    expect(find.text('Genshin Odette C2 acc'), findsOneWidget);
  });

  testWidgets('Quick save leaves out a detected link the user never saw', (
    tester,
  ) async {
    await openVault(
      tester,
      clipboard: {
        'text':
            'Sign in at https://account.example.com/\n'
            'abcde07@hotmail.com\nxQmR42abCD5k',
      },
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.content_paste));
    await tester.pumpAndSettle();
    expect(field('Where is it from? (link)'), findsNothing);
    await save(tester, 'Clear the copied text from your clipboard?');

    final e = services.session.entries.single;
    expect(e.username, 'abcde07@hotmail.com');
    expect(e.password, 'xQmR42abCD5k');
    expect(e.url, isEmpty);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
  });

  testWidgets('Advanced save stores the link, notes and tags', (tester) async {
    await openVault(
      tester,
      clipboard: {
        'text': 'email: abcde07@hotmail.com / password: xQmR42abCD5k',
      },
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.content_paste));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(field('abcde07@hotmail.com'), findsOneWidget);
    expect(field('xQmR42abCD5k'), findsOneWidget);
    await tester.enterText(field('Name'), 'Genshin Odette C2 acc');
    await tester.enterText(
      field('Where is it from? (link)'),
      'https://account.example.com/',
    );
    await tester.enterText(field('Why / notes'), 'Alt account for C2 pulls');
    await tester.enterText(field('Tags (comma separated)'), 'games, alt');
    await save(tester, 'Clear the copied text from your clipboard?');

    final e = services.session.entries.single;
    expect(e.title, 'Genshin Odette C2 acc');
    expect(e.username, 'abcde07@hotmail.com');
    expect(e.password, 'xQmR42abCD5k');
    expect(e.url, 'https://account.example.com/');
    expect(e.notes, 'Alt account for C2 pulls');
    expect(e.tags, ['games', 'alt']);

    // Keeping the clipboard is allowed.
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(nativeCalls, isNot(contains('clearClipboard')));
  });

  testWidgets('Ctrl+V with a screenshot: OCR, temp copy deleted, offer to '
      'clear the screenshot', (tester) async {
    final shot = File('${dir.path}/clip-test.png')
      ..writeAsBytesSync(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]));
    await openVault(
      tester,
      clipboard: {'imagePath': shot.path},
      // OCR noise: spaces around "@" and ".corn".
      ocrLines: ['abcde07 @ hotmail .corn', 'xQmR42abCD5k'],
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(shot.existsSync(), isFalse, reason: 'plaintext screenshot copy');
    expect(field('abcde07@hotmail.com'), findsOneWidget);
    expect(field('xQmR42abCD5k'), findsOneWidget);

    await tester.enterText(field('Name'), 'Genshin Odette C2 acc');
    await save(tester, 'Clear the screenshot from your clipboard?');
    expect(services.session.entries.single.username, 'abcde07@hotmail.com');
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(nativeCalls, contains('clearClipboard'));
  });

  testWidgets('Ctrl+V in the search field pastes there, not a login', (
    tester,
  ) async {
    await openVault(tester, clipboard: {'text': 'xQmR42abCD5k'});
    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(nativeCalls, isNot(contains('readClipboard')));
    expect(find.text('Save login'), findsNothing);
  });

  // On desktop a click outside the search field moves focus to the route's
  // scope; Ctrl+V must keep working from there.
  testWidgets('Ctrl+V still works after clicking out of the search field', (
    tester,
  ) async {
    await openVault(
      tester,
      clipboard: {'text': 'abcde07@hotmail.com\nxQmR42abCD5k'},
    );
    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(Scaffold).first));
    await tester.pumpAndSettle();
    await pressCtrlV(tester);
    expect(nativeCalls, contains('readClipboard'));
    expect(find.text('Save login'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'Ctrl+V works again after searching, opening an entry and going back',
    (tester) async {
      await openVault(
        tester,
        clipboard: {'text': 'abcde07@hotmail.com\nxQmR42abCD5k'},
        entries: [
          VaultEntry(
            id: 'a',
            title: 'Example',
            username: 'abcde07@hotmail.com',
            password: 'Tz8pLq2wXv9m',
          ),
        ],
      );
      await tester.enterText(find.byType(SearchBar), 'Exa');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Example'));
      await tester.pumpAndSettle();

      // Not on another screen.
      await pressCtrlV(tester);
      expect(nativeCalls, isNot(contains('readClipboard')));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await pressCtrlV(tester);
      expect(nativeCalls, contains('readClipboard'));
      expect(find.text('Save login'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('nothing usable on the clipboard: a message, no sheet', (
    tester,
  ) async {
    await openVault(tester, clipboard: {});
    await tester.tap(find.byTooltip('Paste login').last);
    await tester.pumpAndSettle();
    expect(nativeCalls, contains('readClipboard'));
    expect(find.textContaining('No login found on the clipboard'), findsOne);
    expect(find.text('Save login'), findsNothing);
  });

  testWidgets('a vault password copied from the app is not offered as a new '
      'login', (tester) async {
    await openVault(tester, clipboard: {'text': 'xQmR42abCD5k'});
    await services.clipboard.copySecret('xQmR42abCD5k');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.content_paste));
    await tester.pumpAndSettle();
    expect(find.textContaining('No login found on the clipboard'), findsOne);
    await services.clipboard.clearNow();
  });

  testWidgets('stored icons are still shown with fetching turned off', (
    tester,
  ) async {
    const url = 'https://www.example.com/';
    await tester.runAsync(() async {
      final session = services.session;
      await session.init();
      await session.createVault(testMasterPassword);
      await session.saveEntry(
        VaultEntry(
          id: 'a',
          title: 'Example',
          password: 'Tz8pLq2wXv9m',
          url: url,
        ),
      );
      await session.db.putFavicon(
        host: 'www.example.com',
        bytes: _png1x1,
        contentType: 'image/png',
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await services.settings.update((s) => s.fetchIcons = false);
      services.prefetchIcons();
      for (var i = 0; i < 100 && services.favicons!.cached(url) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(services.favicons!.cached(url), isNotNull);
  });

  testWidgets('list tiles show a stored website icon, else the letter', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = services.session;
      await session.init();
      await session.createVault(testMasterPassword);
      await session.saveEntries([
        VaultEntry(
          id: 'a',
          title: 'Example',
          username: 'abcde07@hotmail.com',
          password: 'xQmR42abCD5k',
          url: 'https://www.example.com/',
        ),
        VaultEntry(id: 'b', title: 'Notebook', password: 'Tz8pLq2wXv9m'),
      ]);
      await session.db.putFavicon(
        host: 'www.example.com',
        bytes: _png1x1,
        contentType: 'image/png',
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await services.favicons!.prefetch([
        for (final e in session.entries) e.url,
      ]);
    });
    await tester.pumpWidget(VaultSnapApp(services: services));
    await tester.pumpAndSettle();

    Finder inTile(String title, Finder f) =>
        find.descendant(of: find.widgetWithText(ListTile, title), matching: f);
    expect(inTile('Example', find.byType(Image)), findsOneWidget);
    expect(inTile('Notebook', find.byType(Image)), findsNothing);
    expect(inTile('Notebook', find.text('N')), findsOneWidget);
  });
}

/// What ML Kit's method channel returns for [lines] (one block).
Map<String, Object?> _mlKitResult(List<String> lines) {
  Map<String, Object?> node(String text) => {
    'text': text,
    'rect': <String, Object?>{},
    'recognizedLanguages': <Object?>[],
    'points': <Object?>[],
  };
  return {
    'text': lines.join('\n'),
    'blocks': [
      {
        ...node(lines.join('\n')),
        'lines': [
          for (final l in lines) {...node(l), 'elements': <Object?>[]},
        ],
      },
    ],
  };
}

/// A valid 1x1 transparent PNG.
final _png1x1 = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7a, 0x5e, 0xab, 0x3f, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
