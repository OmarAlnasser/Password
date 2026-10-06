import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/l10n/app_localizations.dart';
import 'package:vaultsnap/ui/app_scope.dart';
import 'package:vaultsnap/ui/ocr/ocr_import_screen.dart';
import 'package:vaultsnap/ui/widgets/secret_text.dart';

import 'helpers.dart';

/// "Import from screenshot": pick an image, OCR it, review what was found.
/// The engine is played by the test; every login here is synthetic.
void main() {
  const email = 'abcde07@hotmail.com';
  const password = 'xQmR42abCD5k';

  late Directory dir;
  late AppServices services;
  late List<String> nativeCalls;

  /// The files the OCR engine was asked to read, in order.
  late List<String> ocrSeen;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_ocrimport');
    services = await buildTestServices(dir);
    nativeCalls = [];
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  /// The image the user picked: [real] is a decodable dark crop that the
  /// scanner can enlarge; otherwise the bytes are not an image, so only the
  /// original is ever read.
  Future<File> pickedFile(WidgetTester tester, {bool real = false}) async {
    final bytes = real
        ? (await tester.runAsync(darkCropPng))!
        : Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
    return File('${dir.path}/picked.png')..writeAsBytesSync(bytes);
  }

  /// Opens the screen on [image] and waits until [until] shows.
  Future<void> openImport(
    WidgetTester tester, {
    required File image,
    required FutureOr<List<String>> Function(int call, String path) ocr,
    required Finder until,
    bool isTempCopy = true,
    Locale? locale,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockChannel(tester, platformChannel, (call) async {
      nativeCalls.add(call.method);
      return switch (call.method) {
        'copySensitive' || 'clearClipboardIfMatches' => true,
        _ => null,
      };
    });
    ocrSeen = mockOcr(tester, ocr);
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
    });
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OcrImportScreen(
            initial: PickedImage(path: image.path, isTempCopy: isTempCopy),
          ),
        ),
      ),
    );
    // The scanner reads and writes image files: real I/O.
    await pumpUntilFound(tester, until);
    await tester.pumpAndSettle();
  }

  Finder secret(String text) =>
      find.byWidgetPredicate((w) => w is SecretText && w.text == text);

  /// A value in the card of what was found (not the chips below it).
  Finder shown(String text) =>
      find.descendant(of: find.byType(ListTile), matching: secret(text));

  /// A piece of text read from the image, as a chip.
  Finder chip(String text) =>
      find.ancestor(of: secret(text), matching: find.byType(Chip));

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> useAs(WidgetTester tester, String text, String field) async {
    await tester.ensureVisible(chip(text));
    await tester.tap(chip(text));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('ocr.useAs.$field')));
    await tester.pumpAndSettle();
  }

  void expectNoCopiesLeft() {
    for (final p in ocrSeen.skip(1)) {
      expect(File(p).existsSync(), isFalse, reason: 'copy of the image');
    }
  }

  testWidgets('clean lines: the login is shown and the temp copy deleted', (
    tester,
  ) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => [email, password],
      until: find.text('Add entry'),
    );
    expect(shown(email), findsOneWidget);
    expect(shown(password), findsOneWidget);
    expect(ocrSeen, [image.path]);
    expect(image.existsSync(), isFalse, reason: 'our plaintext copy');

    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    expect(field(email), findsOneWidget);
    expect(field(password), findsOneWidget);
  });

  testWidgets("the user's own file is never deleted by the scan", (
    tester,
  ) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => [email, password],
      until: find.text('Add entry'),
      isTempCopy: false,
    );
    expect(image.existsSync(), isTrue);
  });

  testWidgets('a first pass that reads nothing is followed by a better one', (
    tester,
  ) async {
    final image = await pickedFile(tester, real: true);
    await openImport(
      tester,
      image: image,
      ocr: (call, _) => call == 0 ? [] : [email, password],
      until: find.text('Add entry'),
    );
    expect(shown(email), findsOneWidget);
    expect(ocrSeen.first, image.path);
    expect(ocrSeen.length, greaterThan(1));
    expect(image.existsSync(), isFalse);
    expectNoCopiesLeft();
  });

  testWidgets('letter-spaced output is closed up', (tester) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => [
        'a b c d e 0 7 @ h o t m a i l . c o m',
        'x Q m R 4 2 a b C D 5 k',
      ],
      until: find.text('Add entry'),
    );
    expect(shown(email), findsOneWidget);
    expect(shown(password), findsOneWidget);
  });

  testWidgets('only the password found: tap a chip, use it as the username', (
    tester,
  ) async {
    final image = await pickedFile(tester, real: true);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => ['abcde07', password],
      until: find.text('Add entry'),
    );
    // No dead end: what was found, and the text to pick from.
    expect(shown(password), findsOneWidget);
    expect(chip('abcde07'), findsOneWidget);
    expect(chip(password), findsOneWidget);
    expect(find.text('Detected text'), findsOneWidget);
    expectNoCopiesLeft();

    await useAs(tester, 'abcde07', 'username');
    expect(shown('abcde07'), findsOneWidget);

    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    expect(field('abcde07'), findsOneWidget);
    expect(field(password), findsOneWidget);
  });

  testWidgets('"Use as" can set the link and the name', (tester) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => ['Hotmail', 'example.org', email, password],
      until: find.text('Add entry'),
    );
    await useAs(tester, 'Hotmail', 'name');
    await useAs(tester, 'example.org', 'link');

    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    expect(field('Hotmail'), findsOneWidget);
    expect(field('example.org'), findsOneWidget);
    expect(field(email), findsOneWidget);
    expect(field(password), findsOneWidget);
  });

  testWidgets('a chip can be copied, as a secret', (tester) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => [email, password],
      until: find.text('Add entry'),
    );
    await tester.ensureVisible(chip(password));
    await tester.tap(chip(password));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ocr.copy')));
    await tester.pumpAndSettle();
    expect(nativeCalls, contains('copySensitive'));
    expect(find.textContaining('Clipboard clears'), findsOneWidget);
    await tester.runAsync(services.clipboard.clearNow);
  });

  testWidgets('other readings of the address can be picked', (tester) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      // A cut ".co" may be ".com" or ".co.uk".
      ocr: (_, _) => ['abcde07@hotmail.co', password],
      until: find.text('Add entry'),
    );
    expect(find.text('Other readings'), findsOneWidget);
    final other = find.widgetWithText(ChoiceChip, 'abcde07@hotmail.co.uk');
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(other).selected, isTrue);
    expect(shown('abcde07@hotmail.co.uk'), findsOneWidget);

    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    expect(field('abcde07@hotmail.co.uk'), findsOneWidget);
  });

  testWidgets('"What was read" lists the lines each pass recognised', (
    tester,
  ) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => [email, password],
      until: find.text('What was read'),
    );
    expect(find.text('Pass 1: original'), findsNothing);
    await tester.ensureVisible(find.text('What was read'));
    await tester.tap(find.text('What was read'));
    await tester.pumpAndSettle();
    expect(find.text('Pass 1: original'), findsOneWidget);
    final read = find.byKey(const ValueKey('ocr.read'));
    expect(
      find.descendant(of: read, matching: find.text(email)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: read, matching: find.text(password)),
      findsOneWidget,
    );
  });

  testWidgets('nothing read: a message with tips and a way forward', (
    tester,
  ) async {
    final image = await pickedFile(tester, real: true);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => <String>[],
      until: find.text('No text found in the image'),
    );
    expect(find.byKey(const ValueKey('ocr.failure')), findsOneWidget);
    expect(find.textContaining('Copy a bigger area'), findsOneWidget);
    expect(find.textContaining('clearly visible'), findsOneWidget);
    expect(find.text('Add entry'), findsNothing);
    expect(ocrSeen.length, greaterThan(1));
    expect(image.existsSync(), isFalse);
    expectNoCopiesLeft();

    await tester.ensureVisible(find.text('What was read'));
    await tester.tap(find.text('What was read'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing read'), findsWidgets);

    await tester.ensureVisible(find.text('Fill in by hand'));
    await tester.tap(find.text('Fill in by hand'));
    await tester.pumpAndSettle();
    expect(field('Title'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('no OCR language installed: how to add one', (tester) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => throw PlatformException(code: 'ocr_no_language'),
      until: find.text('Windows has no OCR language installed'),
    );
    expect(
      find.textContaining('Settings > Time & language > Language & region'),
      findsOneWidget,
    );
    expect(find.textContaining('Add a language'), findsOneWidget);
    expect(find.textContaining('Optical character recognition'), findsOne);
    expect(ocrSeen, [image.path]);
    expect(image.existsSync(), isFalse);
  });

  testWidgets('the engine fails some other way: it says so', (tester) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => throw PlatformException(code: 'ocr_image_too_large'),
      until: find.text('The image is too large to scan'),
    );
    expect(find.textContaining('smaller area'), findsOneWidget);
    expect(find.text('Add entry'), findsNothing);
  });

  testWidgets('Arabic: the messages are translated', (tester) async {
    final image = await pickedFile(tester);
    await openImport(
      tester,
      image: image,
      ocr: (_, _) => throw PlatformException(code: 'ocr_no_language'),
      until: find.text('لا توجد لغة للتعرّف على النص في Windows'),
      locale: const Locale('ar'),
    );
    expect(find.textContaining('الوقت واللغة'), findsOneWidget);
  });
}
