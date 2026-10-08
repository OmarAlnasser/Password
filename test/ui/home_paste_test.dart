import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/app.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/widgets/secret_text.dart';

import 'helpers.dart';

/// "Paste" on the entry list: clipboard text or a screenshot becomes a login
/// in a bottom sheet. All values are synthetic.
void main() {
  late Directory dir;
  late AppServices services;
  late List<String> nativeCalls;

  /// The files the OCR engine was asked to read, in order.
  late List<String> ocrSeen;

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
  /// `readClipboard` with [clipboard] and OCR with [ocrLines], or with what
  /// [ocr] returns for each image the scanner hands to the engine.
  Future<void> openVault(
    WidgetTester tester, {
    required Map<String, Object?> clipboard,
    List<String> ocrLines = const [],
    FutureOr<List<String>> Function(int call, String path)? ocr,
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
    ocrSeen = mockOcr(tester, ocr ?? (_, _) => ocrLines);
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      if (entries.isNotEmpty) await services.session.saveEntries(entries);
    });
    await tester.pumpWidget(HisnApp(services: services));
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

    // Quick: the detected values, editable. The password is masked; the eye
    // shows a preview with look-alike characters highlighted. No advanced
    // fields.
    expect(find.text('Save login'), findsOneWidget);
    expect(field('abcde07@hotmail.com'), findsOneWidget);
    expect(field('xQmR42abCD5k'), findsOneWidget);
    final preview = find.byWidgetPredicate(
      (w) => w is SecretText && w.text == 'xQmR42abCD5k',
    );
    expect(preview, findsNothing);
    await tester.tap(find.byTooltip('Show'));
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);
    // The Name field has a label and no example text.
    expect(
      tester.widget<TextField>(field('Name')).decoration!.hintText,
      isNull,
    );
    expect(find.textContaining('e.g.'), findsNothing);
    expect(field('Where is it from? (link)'), findsNothing);

    await tester.enterText(field('Name'), 'My account');
    await save(tester, 'Clear the copied text from your clipboard?');

    final e = services.session.entries.single;
    expect(e.title, 'My account');
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
    expect(find.text('My account'), findsOneWidget);
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
    await tester.enterText(field('Name'), 'My account');
    await tester.enterText(
      field('Where is it from? (link)'),
      'https://account.example.com/',
    );
    await tester.enterText(field('Why / notes'), 'Alt account for C2 pulls');
    await tester.enterText(field('Tags (comma separated)'), 'games, alt');
    await save(tester, 'Clear the copied text from your clipboard?');

    final e = services.session.entries.single;
    expect(e.title, 'My account');
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
    // The scanner reads the image file: real I/O.
    await pumpUntilFound(tester, find.text('Save login'));
    await tester.pumpAndSettle();

    expect(shot.existsSync(), isFalse, reason: 'plaintext screenshot copy');
    expect(field('abcde07@hotmail.com'), findsOneWidget);
    expect(field('xQmR42abCD5k'), findsOneWidget);

    await tester.enterText(field('Name'), 'My account');
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

  // ---------------------------------------------------------------------
  // Scanning a pasted screenshot. Every login here is synthetic; the engine
  // (ML Kit's channel on the test host) is played by the test.
  // ---------------------------------------------------------------------
  group('a pasted screenshot', () {
    const email = 'abcde07@hotmail.com';
    const password = 'xQmR42abCD5k';

    /// The clipboard screenshot. [real] is a decodable dark crop that the
    /// scanner can enlarge; otherwise the bytes are not an image, so only the
    /// original is ever read.
    Future<File> clipboardShot(WidgetTester tester, {bool real = false}) async {
      final bytes = real
          ? (await tester.runAsync(darkCropPng))!
          : Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
      return File('${dir.path}/clip-test.png')..writeAsBytesSync(bytes);
    }

    Future<void> paste(WidgetTester tester, Finder until) async {
      await tester.tap(find.widgetWithIcon(IconButton, Icons.content_paste));
      // The scanner reads and writes image files: real I/O.
      await pumpUntilFound(tester, until);
      await tester.pumpAndSettle();
    }

    /// The chip of a piece of text read from the image.
    Finder chip(String text) => find.ancestor(
      of: find.byWidgetPredicate((w) => w is SecretText && w.text == text),
      matching: find.byType(Chip),
    );

    Finder dialogTitle(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    void expectNoCopiesLeft(File shot) {
      expect(shot.existsSync(), isFalse, reason: 'clipboard copy');
      for (final p in ocrSeen) {
        expect(File(p).existsSync(), isFalse, reason: 'copy of the image');
      }
    }

    testWidgets('clean lines are read in one pass', (tester) async {
      final shot = await clipboardShot(tester);
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocrLines: [email, password],
      );
      await paste(tester, find.text('Save login'));

      expect(field(email), findsOneWidget);
      expect(field(password), findsOneWidget);
      expect(ocrSeen, [shot.path]);
      expectNoCopiesLeft(shot);
    });

    testWidgets('a first pass that reads nothing is followed by a better one', (
      tester,
    ) async {
      final shot = await clipboardShot(tester, real: true);
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocr: (call, _) => call == 0 ? [] : [email, password],
      );
      await paste(tester, find.text('Save login'));

      expect(field(email), findsOneWidget);
      expect(field(password), findsOneWidget);
      // The original first, then enlarged copies in the scanner's own
      // private directory, all gone now.
      expect(ocrSeen.first, shot.path);
      expect(ocrSeen.length, greaterThan(1));
      for (final p in ocrSeen.skip(1)) {
        expect(p, contains('hisn-ocr'));
      }
      expectNoCopiesLeft(shot);

      // The sheet can show what each pass read.
      await tester.ensureVisible(find.text('What was read'));
      await tester.tap(find.text('What was read'));
      await tester.pumpAndSettle();
      expect(find.text('Pass 1: original'), findsOneWidget);
      expect(find.text('Nothing read'), findsOneWidget);
      // What was read is masked until the eye of the panel is pressed.
      final read = find.byKey(const ValueKey('ocr.read'));
      expect(
        find.descendant(of: read, matching: find.text(password)),
        findsNothing,
      );
      await tester.tap(
        find.descendant(of: read, matching: find.byTooltip('Show')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: read, matching: find.text(password)),
        findsOneWidget,
      );
    });

    testWidgets('letter-spaced output is closed up', (tester) async {
      final shot = await clipboardShot(tester);
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocrLines: [
          'a b c d e 0 7 @ h o t m a i l . c o m',
          'x Q m R 4 2 a b C D 5 k',
        ],
      );
      await paste(tester, find.text('Save login'));

      expect(field(email), findsOneWidget);
      expect(field(password), findsOneWidget);
    });

    testWidgets('only the password found: the sheet opens with the text to '
        'pick from, and "Use as" fills the username', (tester) async {
      final shot = await clipboardShot(tester, real: true);
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocrLines: ['abcde07', password],
      );
      await paste(tester, find.text('Save login'));

      // No dead end: what was found is filled in, the rest can be picked.
      expect(field(password), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Email / username')).controller!.text,
        isEmpty,
      );
      expect(find.textContaining('Not sure which text'), findsOneWidget);
      expect(find.text('Detected text'), findsOneWidget);
      expect(chip('abcde07'), findsOneWidget);
      expect(chip(password), findsOneWidget);
      expectNoCopiesLeft(shot);

      await tester.ensureVisible(chip('abcde07'));
      await tester.tap(chip('abcde07'));
      await tester.pumpAndSettle();
      expect(find.text('Use as…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ocr.useAs.username')));
      await tester.pumpAndSettle();
      expect(field('abcde07'), findsOneWidget);

      await save(tester, 'Clear the screenshot from your clipboard?');
      final e = services.session.entries.single;
      expect(e.username, 'abcde07');
      expect(e.password, password);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
    });

    testWidgets('"Use as" can fill the password, the name and the link', (
      tester,
    ) async {
      final shot = await clipboardShot(tester);
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocrLines: ['Hotmail', 'example.org', email],
      );
      await paste(tester, find.text('Save login'));

      Future<void> useAs(String text, String field) async {
        await tester.ensureVisible(chip(text));
        await tester.tap(chip(text));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('ocr.useAs.$field')));
        await tester.pumpAndSettle();
      }

      await useAs('Hotmail', 'name');
      await useAs('example.org', 'link');
      await useAs('Hotmail', 'password');
      // The link is shown now, so it is saved.
      expect(field('Where is it from? (link)'), findsOneWidget);
      await save(tester, 'Clear the screenshot from your clipboard?');
      final e = services.session.entries.single;
      expect(e.title, 'Hotmail');
      expect(e.url, 'example.org');
      expect(e.password, 'Hotmail');
      expect(e.username, email);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
    });

    testWidgets('other readings of the address can be picked', (tester) async {
      final shot = await clipboardShot(tester);
      // A cut ".co" may be ".com" or ".co.uk".
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocrLines: ['abcde07@hotmail.co', password],
      );
      await paste(tester, find.text('Save login'));

      expect(find.text('Other readings'), findsOneWidget);
      final other = find.widgetWithText(ChoiceChip, 'abcde07@hotmail.co.uk');
      expect(other, findsOneWidget);
      await tester.tap(other);
      await tester.pumpAndSettle();
      expect(field('abcde07@hotmail.co.uk'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(other).selected, isTrue);
    });

    testWidgets('nothing read: a message with tips, no sheet', (tester) async {
      final shot = await clipboardShot(tester, real: true);
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocr: (_, _) => <String>[],
      );
      await paste(tester, dialogTitle('No text found in the image'));

      expect(dialogTitle('No text found in the image'), findsOneWidget);
      expect(find.textContaining('Copy a bigger area'), findsOneWidget);
      expect(find.textContaining('clearly visible'), findsOneWidget);
      expect(find.textContaining('try again'), findsOneWidget);
      expect(find.text('Save login'), findsNothing);
      // Enlarged copies were tried before giving up, and are gone.
      expect(ocrSeen.length, greaterThan(1));
      expectNoCopiesLeft(shot);

      // What each pass read, for diagnosing.
      await tester.tap(find.text('What was read'));
      await tester.pumpAndSettle();
      expect(find.text('Pass 1: original'), findsOneWidget);
      expect(find.text('Nothing read'), findsWidgets);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Save login'), findsNothing);
    });

    testWidgets('nothing read: "Paste again" reads the clipboard again', (
      tester,
    ) async {
      final shot = await clipboardShot(tester);
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocr: (_, _) => <String>[],
      );
      await paste(tester, dialogTitle('No text found in the image'));
      await tester.tap(find.text('Paste again'));
      await tester.pump(const Duration(seconds: 1));
      // The second read: until its message is up (a spinner turns meanwhile).
      for (var i = 0; i < 200; i++) {
        final twice =
            nativeCalls.where((c) => c == 'readClipboard').length == 2;
        final spinning = find.byType(CircularProgressIndicator).evaluate();
        if (twice &&
            spinning.isEmpty &&
            find.byType(AlertDialog).evaluate().isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(nativeCalls.where((c) => c == 'readClipboard'), hasLength(2));
      expect(dialogTitle('No text found in the image'), findsOneWidget);
    });

    testWidgets('nothing read: "Fill in by hand" opens an empty sheet', (
      tester,
    ) async {
      final shot = await clipboardShot(tester);
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocr: (_, _) => <String>[],
      );
      await paste(tester, dialogTitle('No text found in the image'));
      await tester.tap(find.text('Fill in by hand'));
      await tester.pumpAndSettle();

      expect(find.text('Save login'), findsOneWidget);
      await tester.enterText(field('Email / username'), email);
      await tester.enterText(field('Password'), password);
      await save(tester, 'Clear the screenshot from your clipboard?');
      expect(services.session.entries.single.username, email);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
    });

    testWidgets('a copied image the native side could not convert: a message '
        'with a way forward, no "copy a screenshot" dead end', (tester) async {
      await openVault(tester, clipboard: {'imageError': 'image_unreadable'});
      await paste(tester, dialogTitle("This image can't be read"));

      expect(dialogTitle("This image can't be read"), findsOneWidget);
      expect(find.textContaining('Copy it again'), findsOneWidget);
      expect(find.text('Paste again'), findsOneWidget);
      expect(find.text('Fill in by hand'), findsOneWidget);
      expect(
        find.textContaining('No login found on the clipboard'),
        findsNothing,
      );
      expect(find.text('Save login'), findsNothing);
      // There was no file to read.
      expect(ocrSeen, isEmpty);

      await tester.tap(find.text('Fill in by hand'));
      await tester.pumpAndSettle();
      expect(find.text('Save login'), findsOneWidget);
    });

    testWidgets('a copied image that could not be converted, with a login in '
        'text next to it: the text is used', (tester) async {
      await openVault(
        tester,
        clipboard: {
          'imageError': 'image_unreadable',
          'text': '$email\n$password',
        },
      );
      await tester.tap(find.widgetWithIcon(IconButton, Icons.content_paste));
      await tester.pumpAndSettle();

      expect(find.text('Save login'), findsOneWidget);
      expect(field(email), findsOneWidget);
      expect(field(password), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('no OCR language installed: how to add one', (tester) async {
      final shot = await clipboardShot(tester, real: true);
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocr: (_, _) => throw PlatformException(code: 'ocr_no_language'),
      );
      await paste(tester, dialogTitle('Windows has no OCR language installed'));

      expect(
        dialogTitle('Windows has no OCR language installed'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Settings > Time & language > Language & region'),
        findsOneWidget,
      );
      expect(find.textContaining('Add a language'), findsOneWidget);
      expect(find.textContaining('Optical character recognition'), findsOne);
      expect(find.text('Save login'), findsNothing);
      // Every other pass would fail the same way: only one was tried.
      expect(ocrSeen, [shot.path]);
      expectNoCopiesLeft(shot);

      // The stacked buttons take more of this 800 x 600 window, so the
      // dialog's content scrolls: bring the panel into view first.
      await tester.ensureVisible(find.text('What was read'));
      await tester.tap(find.text('What was read'));
      await tester.pumpAndSettle();
      expect(find.text('Failed (noLanguage)'), findsOneWidget);
    });

    for (final (code, title) in [
      ('ocr_image_too_large', 'The image is too large to scan'),
      ('ocr_unsupported_image', "This image can't be read"),
      ('ocr_file_unreadable', "The image file couldn't be opened"),
      ('ocr_failed', 'Text recognition failed'),
    ]) {
      testWidgets('the engine fails with $code: "$title"', (tester) async {
        final shot = await clipboardShot(tester);
        await openVault(
          tester,
          clipboard: {'imagePath': shot.path},
          ocr: (_, _) => throw PlatformException(code: code),
        );
        await paste(tester, dialogTitle(title));
        expect(dialogTitle(title), findsOneWidget);
        expect(find.text('Save login'), findsNothing);
        expectNoCopiesLeft(shot);
      });
    }

    testWidgets('locking while a screenshot is being read abandons the scan '
        'and still deletes the copy', (tester) async {
      final shot = await clipboardShot(tester);
      final engine = Completer<List<String>>();
      await openVault(
        tester,
        clipboard: {'imagePath': shot.path},
        ocr: (_, _) => engine.future,
      );
      await tester.tap(find.widgetWithIcon(IconButton, Icons.content_paste));
      for (var i = 0; i < 100 && ocrSeen.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(ocrSeen, [shot.path]);

      await tester.runAsync(services.session.lock);
      for (var i = 0; i < 100 && shot.existsSync(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(shot.existsSync(), isFalse);
      expect(find.text('Save login'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      engine.complete([]);
    });
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
    await tester.pumpWidget(HisnApp(services: services));
    await tester.pumpAndSettle();

    Finder inTile(String title, Finder f) =>
        find.descendant(of: find.widgetWithText(ListTile, title), matching: f);
    expect(inTile('Example', find.byType(Image)), findsOneWidget);
    expect(inTile('Notebook', find.byType(Image)), findsNothing);
    expect(inTile('Notebook', find.text('N')), findsOneWidget);
  });
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
