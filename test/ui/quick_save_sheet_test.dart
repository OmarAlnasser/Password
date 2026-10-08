import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/ocr/ocr_parser.dart';
import 'package:hisn/services/ocr/ocr_scanner.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/ocr/ocr_widgets.dart';
import 'package:hisn/ui/ocr/quick_save_sheet.dart';
import 'package:hisn/ui/widgets/secret_text.dart';

import 'helpers.dart';

/// The save sheet on its own, with readings made up for it: other readings
/// to pick from, the text to tap and use, and what each scan pass read.
/// All values are synthetic.
void main() {
  const email = 'abcde07@hotmail.com';
  const password = 'xQmR42abCD5k';

  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_sheet');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  /// Opens the sheet over a page with a button.
  Future<void> openSheet(
    WidgetTester tester,
    OcrResult found, {
    List<ScanPass> passes = const [],
    Locale? locale,
    Size size = const Size(800, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockChannel(tester, platformChannel, (_) async => null);
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
          home: Builder(
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
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);
  Finder chip(String text) => find.ancestor(
    of: find.byWidgetPredicate((w) => w is SecretText && w.text == text),
    matching: find.byType(Chip),
  );
  String textOf(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;

  testWidgets('the Name field has a label and no example text', (tester) async {
    await openSheet(
      tester,
      const OcrResult(
        chips: [email, password],
        email: email,
        username: email,
        password: password,
      ),
    );
    final name = tester.widget<TextField>(field('Name'));
    expect(name.decoration!.hintText, isNull);
    expect(find.textContaining('e.g.'), findsNothing);
  });

  testWidgets('Arabic: the Name field has no example text either', (
    tester,
  ) async {
    await openSheet(
      tester,
      const OcrResult(
        chips: [email, password],
        email: email,
        username: email,
        password: password,
      ),
      locale: const Locale('ar'),
    );
    final name = tester.widget<TextField>(field('الاسم'));
    expect(name.decoration!.hintText, isNull);
    expect(find.textContaining('مثال'), findsNothing);
  });

  testWidgets('a complete reading: no hint, the text read stays folded', (
    tester,
  ) async {
    await openSheet(
      tester,
      const OcrResult(
        chips: [email, password],
        email: email,
        username: email,
        password: password,
      ),
    );
    expect(find.textContaining('Not sure which text'), findsNothing);
    expect(find.text('Detected text'), findsOneWidget);
    expect(chip(password), findsNothing);
    // Nothing from a scan: no "What was read".
    expect(find.text('What was read'), findsNothing);

    await tester.tap(find.text('Detected text'));
    await tester.pumpAndSettle();
    expect(chip(password), findsOneWidget);
  });

  testWidgets('an incomplete reading: the text read is open, with a hint', (
    tester,
  ) async {
    await openSheet(
      tester,
      const OcrResult(
        chips: ['abcde07', password],
        password: password,
        passwordCandidates: [password],
      ),
    );
    expect(find.textContaining('Not sure which text'), findsOneWidget);
    expect(chip('abcde07'), findsOneWidget);
    expect(textOf(tester, 'Email / username'), isEmpty);
    expect(textOf(tester, 'Password'), password);
  });

  testWidgets('no text read and nothing found: an empty sheet to type in', (
    tester,
  ) async {
    await openSheet(tester, const OcrResult(chips: []));
    expect(find.text('Detected text'), findsNothing);
    expect(find.textContaining('Not sure which text'), findsNothing);
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(field('Password'), password);
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('other readings of the address and the password can be picked', (
    tester,
  ) async {
    await openSheet(
      tester,
      const OcrResult(
        chips: [email, password],
        email: email,
        username: email,
        password: password,
        emailCandidates: [email, 'abcde07@hotmail.co.uk', 'abcde07@hotmail.co'],
        passwordCandidates: [password, 'xQmR42abCD5K', 'xQmR42abCDSk'],
      ),
    );
    expect(find.text('Other readings'), findsNWidgets(2));
    final firstEmail = find.widgetWithText(ChoiceChip, email);
    final secondEmail = find.widgetWithText(
      ChoiceChip,
      'abcde07@hotmail.co.uk',
    );
    expect(tester.widget<ChoiceChip>(firstEmail).selected, isTrue);
    expect(tester.widget<ChoiceChip>(secondEmail).selected, isFalse);

    await tester.tap(secondEmail);
    await tester.pumpAndSettle();
    expect(textOf(tester, 'Email / username'), 'abcde07@hotmail.co.uk');
    expect(tester.widget<ChoiceChip>(secondEmail).selected, isTrue);
    expect(tester.widget<ChoiceChip>(firstEmail).selected, isFalse);

    final otherPassword = find.widgetWithText(ChoiceChip, 'xQmR42abCDSk');
    await tester.ensureVisible(otherPassword);
    await tester.tap(otherPassword);
    await tester.pumpAndSettle();
    expect(textOf(tester, 'Password'), 'xQmR42abCDSk');

    // Typing a value of one's own deselects them all.
    await tester.enterText(field('Password'), 'something else');
    await tester.pump();
    expect(tester.widget<ChoiceChip>(otherPassword).selected, isFalse);
  });

  testWidgets('a single reading offers no alternatives', (tester) async {
    await openSheet(
      tester,
      const OcrResult(
        chips: [email, password],
        email: email,
        username: email,
        password: password,
        emailCandidates: [email],
        passwordCandidates: [password],
      ),
    );
    expect(find.text('Other readings'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('"Use as" a link shows the link field, so it is saved', (
    tester,
  ) async {
    await openSheet(
      tester,
      const OcrResult(
        chips: ['example.org', 'My account', email, password],
        email: email,
        username: email,
        password: password,
      ),
    );
    expect(field('Where is it from? (link)'), findsNothing);
    await tester.tap(find.text('Detected text'));
    await tester.pumpAndSettle();

    Future<void> useAs(String text, String as) async {
      await tester.ensureVisible(chip(text));
      await tester.tap(chip(text));
      await tester.pumpAndSettle();
      expect(find.text('Use as…'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('ocr.useAs.$as')));
      await tester.pumpAndSettle();
    }

    await useAs('example.org', 'link');
    expect(field('Where is it from? (link)'), findsOneWidget);
    expect(textOf(tester, 'Where is it from? (link)'), 'example.org');
    await useAs('My account', 'name');
    expect(textOf(tester, 'Name'), 'My account');

    await tester.ensureVisible(find.text('Save'));
    await tester.runAsync(() => tester.tap(find.text('Save')));
    // The vault's database works on a real isolate; the sheet closes after.
    for (
      var i = 0;
      i < 200 && find.byType(QuickSaveSheet).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    final e = services.session.entries.single;
    expect(e.title, 'My account');
    expect(e.url, 'example.org');
    expect(e.username, email);
  });

  testWidgets('a long list of text shows the first chips and "Show all"', (
    tester,
  ) async {
    final many = [for (var i = 0; i < 45; i++) 'word$i'];
    await openSheet(tester, OcrResult(chips: many, password: password));
    expect(chip('word0'), findsOneWidget);
    expect(chip('word29'), findsOneWidget);
    expect(chip('word30'), findsNothing);
    await tester.ensureVisible(find.text('Show all (45)'));
    await tester.tap(find.text('Show all (45)'));
    await tester.pumpAndSettle();
    expect(chip('word44'), findsOneWidget);
    expect(find.text('Show all (45)'), findsNothing);
  });

  testWidgets('"What was read": each pass, what it read and why it failed', (
    tester,
  ) async {
    await openSheet(
      tester,
      const OcrResult(chips: [password], password: password),
      passes: const [
        ScanPass(name: 'original', lines: [], quality: 0),
        ScanPass(
          name: 'inverted',
          lines: ['xQmR 42abCD5k', 'hotmai1.com'],
          quality: 0.5,
        ),
        ScanPass(
          name: 'upscaled',
          lines: [],
          quality: 0,
          error: ScanError.failed,
        ),
      ],
    );
    expect(find.text('What was read'), findsOneWidget);
    expect(find.text('Pass 1: original'), findsNothing);

    await tester.ensureVisible(find.text('What was read'));
    await tester.tap(find.text('What was read'));
    await tester.pumpAndSettle();
    expect(find.text('Pass 1: original'), findsOneWidget);
    expect(find.text('Nothing read'), findsOneWidget);
    expect(find.text('Pass 2: inverted'), findsOneWidget);
    expect(find.text('xQmR 42abCD5k'), findsOneWidget);
    expect(find.text('hotmai1.com'), findsOneWidget);
    expect(find.text('Pass 3: upscaled'), findsOneWidget);
    expect(find.text('Failed (failed)'), findsOneWidget);
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets('a narrow phone (${locale.languageCode}): long values, chips '
        'and passes fit', (tester) async {
      const longEmail =
          'first.middle.lastname.with.a.long.local.part@hotmail.com';
      final longLine =
          'a very long line of text that OCR read: ${'word ' * 14}';
      await openSheet(
        tester,
        OcrResult(
          chips: [longLine, longEmail, password, 'abcde07'],
          email: longEmail,
          username: longEmail,
          emailCandidates: const [
            longEmail,
            'first.middle.lastname@hotmail.co.uk',
          ],
          passwordCandidates: const [password, 'xQmR42abCD5K', 'xQmR42abCDSk'],
        ),
        passes: [
          ScanPass(
            name: 'original',
            lines: [longLine, longEmail],
            quality: 0.4,
          ),
          const ScanPass(
            name: 'inverted-alt',
            lines: [],
            quality: 0,
            error: ScanError.noLanguage,
          ),
        ],
        size: const Size(360, 740),
        locale: locale,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('ocr.read')));
      await tester.tap(find.byKey(const ValueKey('ocr.read')));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a narrow phone: the failure message fits', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
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
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Windows has no OCR language installed'), findsOne);
    expect(find.text('Paste again'), findsOneWidget);
    expect(find.text('Fill in by hand'), findsOneWidget);
    // The message scrolls inside the dialog on a small screen.
    await tester.ensureVisible(find.text('What was read'));
    await tester.tap(find.text('What was read'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Failed (noLanguage)'));
    expect(find.text('Failed (noLanguage)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
