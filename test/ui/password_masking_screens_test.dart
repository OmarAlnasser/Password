import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/ocr/ocr_parser.dart';
import 'package:hisn/services/ocr/ocr_scanner.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/entry_edit_screen.dart';
import 'package:hisn/ui/generator_screen.dart';
import 'package:hisn/ui/import/import_review_screen.dart';
import 'package:hisn/ui/ocr/ocr_import_screen.dart';
import 'package:hisn/ui/ocr/quick_save_sheet.dart';
import 'package:hisn/ui/theme/app_theme.dart';
import 'package:hisn/ui/widgets/secret_text.dart';

import 'helpers.dart';
import 'secret_visibility_helpers.dart';

/// Every screen that shows a stored or scanned password shows it masked: no
/// plain text on screen, in a tooltip or in what a screen reader hears; an eye
/// of 48 dp shows it, and it is masked again after 15 s without interaction
/// (fake time here) or when the screen is left. Editing keeps working while
/// it is masked. All values are synthetic.
void main() {
  const email = 'user@example.com';
  const password = 'hunter-test-1';
  const second = 'hunter-test-2';
  const third = 'hunter-test-3';

  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_masking');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Widget host(Widget home, {Locale locale = const Locale('en')}) => AppScope(
    services: services,
    child: MaterialApp(
      theme: AppTheme.dark(locale),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );

  void phone(WidgetTester tester, {Size size = const Size(420, 2400)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> createVault(WidgetTester tester) => tester.runAsync(() async {
    await services.session.init();
    await services.session.createVault(testMasterPassword);
  });

  /// The eye inside [region] (a `Show` or a `Hide` button).
  Finder eye(Finder region) => find.descendant(
    of: region,
    matching: find.byWidgetPredicate(
      (w) =>
          w is IconButton &&
          (w.tooltip == 'Show' ||
              w.tooltip == 'Hide' ||
              w.tooltip == 'إظهار' ||
              w.tooltip == 'إخفاء'),
    ),
  );

  Future<void> tapEye(WidgetTester tester, Finder region) async {
    final button = eye(region);
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// A masked-or-not SecretText.
  Finder secretText(String text, {bool? masked}) => find.byWidgetPredicate(
    (w) =>
        w is SecretText &&
        w.text == text &&
        (masked == null || w.obscure == masked),
  );

  void expectEyeIs48(WidgetTester tester, Finder region) {
    final size = tester.getSize(eye(region));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  }

  group('entry form', () {
    final saved = VaultEntry(
      id: 'a',
      title: 'Example',
      username: email,
      password: password,
      url: 'https://example.com/',
    );

    Future<void> open(
      WidgetTester tester, {
      VaultEntry? existing,
      VaultEntry? prefill,
      Locale locale = const Locale('en'),
    }) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          EntryEditScreen(existing: existing, prefill: prefill),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
    }

    final passwordField = fieldLabelled('Password');

    testWithSemantics('an entry being edited shows its password masked', (
      tester,
    ) async {
      await open(tester, existing: saved);
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
      expectSecretHidden(tester, password);
      expect(secretText(password), findsNothing, reason: 'no preview');
      expectEyeIs48(tester, passwordField);
    });

    testWithSemantics(
      'a login read by OCR is masked too, not shown for checking',
      (tester) async {
        await open(tester, prefill: saved);
        expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
        expectSecretHidden(tester, password);
      },
    );

    testWithSemantics('the eye shows it with a preview; 15 s masks it again', (
      tester,
    ) async {
      await open(tester, existing: saved);
      await tapEye(tester, passwordField);
      expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
      expectSecretShown(tester, password);
      expect(secretText(password, masked: false), findsOneWidget);

      await tester.pump(const Duration(seconds: 14));
      expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
      expect(secretText(password), findsNothing);
      expectSecretHidden(tester, password);
    });

    testWithSemantics('typing in the password keeps it revealed longer', (
      tester,
    ) async {
      await open(tester, existing: saved);
      await tapEye(tester, passwordField);
      await tester.pump(const Duration(seconds: 12));
      await tester.enterText(passwordField, second);
      await tester.pump(const Duration(seconds: 12));
      expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
    });

    testWithSemantics('the password can be edited while masked', (
      tester,
    ) async {
      await open(tester, existing: saved);
      await tester.enterText(passwordField, second);
      await tester.pump();
      expect(tester.widget<TextField>(passwordField).controller!.text, second);
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
      expectSecretHidden(tester, second);
      expectSecretHidden(tester, password);
    });

    testWithSemantics('leaving the form masks it again', (tester) async {
      await open(tester, existing: saved);
      await tapEye(tester, passwordField);
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pump(const Duration(seconds: 20));
      await open(tester, existing: saved);
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
    });

    testWithSemantics(
      'Arabic: masked, the eye on the left, a preview left-to-right',
      (tester) async {
        await open(tester, existing: saved, locale: const Locale('ar'));
        final field = fieldLabelled('كلمة المرور');
        expect(tester.widget<TextField>(field).obscureText, isTrue);
        expect(
          tester.widget<TextField>(field).textDirection,
          TextDirection.ltr,
        );
        expectSecretHidden(tester, password);
        expect(find.byTooltip('إظهار'), findsOneWidget);

        await tester.tap(find.byTooltip('إظهار'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).obscureText, isFalse);
        expect(secretText(password, masked: false), findsOneWidget);
        // The preview box holds the value left-to-right.
        final preview = tester.widget<SelectableText>(
          find.descendant(
            of: find.byType(SecretBox),
            matching: find.byType(SelectableText),
          ),
        );
        expect(preview.textDirection, anyOf(isNull, TextDirection.ltr));
      },
    );
  });

  group('save sheet', () {
    const complete = OcrResult(
      chips: [email, password, second, 'Example site'],
      email: email,
      username: email,
      password: password,
      emailCandidates: [email, 'user@example.org'],
      passwordCandidates: [password, second, third],
    );
    const incomplete = OcrResult(
      chips: [email, password, 'Example site'],
      password: password,
      passwordCandidates: [password, second],
    );

    Future<void> open(
      WidgetTester tester,
      OcrResult found, {
      List<ScanPass> passes = const [],
      Locale locale = const Locale('en'),
      Size size = const Size(420, 2400),
    }) async {
      phone(tester, size: size);
      mockChannel(tester, platformChannel, (_) async => null);
      await tester.pumpWidget(
        host(
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
          locale: locale,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final passwordField = fieldLabelled('Password');
    final chips = find.byKey(const ValueKey('ocr.chips'));
    final read = find.byKey(const ValueKey('ocr.read'));

    testWithSemantics('opens with no password readable anywhere', (
      tester,
    ) async {
      await open(tester, complete);
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
      for (final v in [password, second, third]) {
        expectSecretHidden(tester, v);
      }
      // The other readings are offered, as bullets.
      expect(find.text('Other readings'), findsNWidgets(2));
      expect(secretText(second, masked: true), findsOneWidget);
      expect(secretText(third, masked: true), findsOneWidget);
      expect(secretText(password, masked: true), findsOneWidget);
      // The address is not a secret.
      expect(find.widgetWithText(ChoiceChip, 'user@example.org'), findsOne);
      // No preview, and nothing that says the characters are highlighted.
      expect(
        find.text('Highlighted characters are easy to misread (0/O, l/I/1)'),
        findsNothing,
      );
      expectEyeIs48(tester, passwordField);
    });

    testWithSemantics('the eye shows the field, the readings and a preview', (
      tester,
    ) async {
      await open(tester, complete);
      await tapEye(tester, passwordField);
      expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
      for (final v in [password, second, third]) {
        expectSecretShown(tester, v);
      }
      expect(secretText(password, masked: false), findsOneWidget);
      expect(
        find.text('Highlighted characters are easy to misread (0/O, l/I/1)'),
        findsOneWidget,
      );
      expect(find.byTooltip('Hide'), findsOneWidget);
    });

    testWithSemantics('15 s later all of it is masked again', (tester) async {
      await open(tester, complete);
      await tapEye(tester, passwordField);
      await tester.pump(const Duration(seconds: 15, milliseconds: 100));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
      for (final v in [password, second, third]) {
        expectSecretHidden(tester, v);
      }
      expect(secretText(password, masked: false), findsNothing);
    });

    testWithSemantics('picking a reading while revealed fills the field', (
      tester,
    ) async {
      await open(tester, complete);
      await tapEye(tester, passwordField);
      await tester.tap(find.widgetWithText(ChoiceChip, second));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(passwordField).controller!.text, second);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, second))
            .selected,
        isTrue,
      );
    });

    testWithSemantics('picking a masked reading works too', (tester) async {
      await open(tester, complete);
      // Second chip of the password readings: the masked ones, in order.
      final masked = find.descendant(
        of: find.byType(ChoiceChip),
        matching: secretText(second, masked: true),
      );
      await tester.tap(masked);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(passwordField).controller!.text, second);
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
    });

    testWithSemantics('the detected text is masked, with its own eye', (
      tester,
    ) async {
      await open(tester, incomplete);
      // An incomplete reading opens the panel; the text in it is bullets.
      expect(chips, findsOneWidget);
      expect(eye(chips), findsOneWidget);
      expectEyeIs48(tester, chips);
      Finder inPanel(String text, {required bool masked}) => find.descendant(
        of: chips,
        matching: secretText(text, masked: masked),
      );
      expect(inPanel(password, masked: true), findsOneWidget);
      expect(inPanel(email, masked: true), findsOneWidget);
      expect(inPanel(password, masked: false), findsNothing);

      await tapEye(tester, chips);
      expect(inPanel(password, masked: false), findsOneWidget);
      expect(inPanel(email, masked: false), findsOneWidget);
      expect(inPanel(password, masked: true), findsNothing);
      // The password field and its readings are separate: still masked.
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
      expect(secretText(second, masked: true), findsOneWidget);

      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(inPanel(password, masked: false), findsNothing);
      expect(inPanel(email, masked: true), findsOneWidget);
    });

    testWithSemantics('folding the detected text away masks it again', (
      tester,
    ) async {
      await open(tester, incomplete);
      await tapEye(tester, chips);
      expect(secretText(email, masked: false), findsOneWidget);

      await tester.tap(find.text('Detected text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detected text'));
      await tester.pumpAndSettle();
      expect(secretText(email, masked: true), findsOneWidget);
      expect(secretText(email, masked: false), findsNothing);
    });

    final passes = [
      const ScanPass(name: 'original', lines: [], quality: 0),
      ScanPass(name: 'inverted', lines: [email, password], quality: 0.5),
    ];

    testWithSemantics('what was read is masked until its eye is pressed', (
      tester,
    ) async {
      await open(tester, complete, passes: passes);
      await tester.ensureVisible(read);
      await tester.tap(read);
      await tester.pumpAndSettle();
      // The titles are not secrets; the lines are.
      expect(find.text('Pass 2: inverted'), findsOneWidget);
      expect(find.text('Nothing read'), findsOneWidget);
      expect(
        find.descendant(of: read, matching: find.text(password)),
        findsNothing,
      );
      expect(
        find.descendant(of: read, matching: find.byType(SecretText)),
        findsOneWidget,
      );
      expectEyeIs48(tester, read);

      await tapEye(tester, read);
      expect(
        find.descendant(of: read, matching: find.text(password)),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: read, matching: find.text(password)),
        findsNothing,
      );
    });

    testWithSemantics('folding what was read away masks it again', (
      tester,
    ) async {
      await open(tester, complete, passes: passes);
      await tester.ensureVisible(read);
      await tester.tap(read);
      await tester.pumpAndSettle();
      await tapEye(tester, read);
      expect(
        find.descendant(of: read, matching: find.text(password)),
        findsOneWidget,
      );
      await tester.tap(find.text('What was read'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('What was read'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: read, matching: find.text(password)),
        findsNothing,
      );
    });

    testWithSemantics('Arabic on a narrow phone: masked, nothing overflows', (
      tester,
    ) async {
      await open(
        tester,
        incomplete,
        passes: passes,
        locale: const Locale('ar'),
        size: const Size(360, 740),
      );
      final field = fieldLabelled('كلمة المرور');
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      expect(tester.widget<TextField>(field).textDirection, TextDirection.ltr);
      expectSecretHidden(tester, second);
      expect(find.byTooltip('إظهار'), findsWidgets);
      await tester.ensureVisible(read);
      await tester.tap(read);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('كلمة المرور مخفية'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tapEye(tester, field);
      expectSecretShown(tester, password);
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing a password while it is masked saves what was typed', (
      tester,
    ) async {
      await createVault(tester);
      await open(tester, const OcrResult(chips: []));
      await tester.enterText(passwordField, second);
      await tester.pump();
      expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

      await tester.runAsync(() => tester.tap(find.text('Save')));
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
      expect(services.session.entries.single.password, second);
    });
  });

  group('screenshot import', () {
    late List<String> nativeCalls;

    Future<File> picked(WidgetTester tester) async =>
        File('${dir.path}/p.png')
          ..writeAsBytesSync(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]));

    Future<void> open(
      WidgetTester tester,
      List<String> lines, {
      Locale locale = const Locale('en'),
    }) async {
      phone(tester, size: const Size(800, 2400));
      nativeCalls = [];
      mockChannel(tester, platformChannel, (call) async {
        nativeCalls.add(call.method);
        return switch (call.method) {
          'copySensitive' || 'clearClipboardIfMatches' => true,
          _ => null,
        };
      });
      mockOcr(tester, (_, _) => lines);
      await createVault(tester);
      final image = await picked(tester);
      await tester.pumpWidget(
        host(
          OcrImportScreen(initial: PickedImage(path: image.path)),
          locale: locale,
        ),
      );
      await pumpUntilFound(tester, find.text('Add entry'));
      await tester.pumpAndSettle();
    }

    /// The card with the found values: the row of the password.
    Finder passwordRow() => find.ancestor(
      of: secretText(password),
      matching: find.byType(ListTile),
    );

    testWithSemantics('the found password is masked, with an eye', (
      tester,
    ) async {
      await open(tester, [email, password]);
      expect(secretText(password, masked: true), findsWidgets);
      expect(secretText(password, masked: false), findsNothing);
      expectSecretHidden(tester, password);
      // The address next to it is not a secret.
      expect(secretText(email, masked: false), findsWidgets);
      expectEyeIs48(tester, passwordRow());
    });

    testWithSemantics('the eye shows it; 15 s later it is masked again', (
      tester,
    ) async {
      await open(tester, [email, password]);
      await tapEye(tester, passwordRow());
      // The row, and nothing else, was revealed: the chips are still masked.
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: secretText(password, masked: false),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Chip),
          matching: secretText(password, masked: false),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(secretText(password, masked: false), findsNothing);
      expectSecretHidden(tester, password);
    });

    testWithSemantics('the detected text has its own eye and starts masked', (
      tester,
    ) async {
      await open(tester, [email, password]);
      final chip = find.byType(Chip);
      expect(chip, findsWidgets);
      for (final c in tester.widgetList<Chip>(chip)) {
        expect(c.label, isNotNull);
      }
      expect(
        find.descendant(of: chip, matching: secretText(password, masked: true)),
        findsOneWidget,
      );
      final title = find.ancestor(
        of: find.text('Detected text'),
        matching: find.byType(Row),
      );
      await tapEye(tester, title.first);
      expect(
        find.descendant(
          of: chip,
          matching: secretText(password, masked: false),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: chip,
          matching: secretText(password, masked: false),
        ),
        findsNothing,
      );
    });

    testWithSemantics('what was read is masked', (tester) async {
      await open(tester, [email, password]);
      final read = find.byKey(const ValueKey('ocr.read'));
      await tester.ensureVisible(read);
      await tester.tap(find.text('What was read'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: read, matching: find.text(password)),
        findsNothing,
      );
      expectSecretHidden(tester, password);
      await tapEye(tester, read);
      expect(
        find.descendant(of: read, matching: find.textContaining(password)),
        findsOneWidget,
      );
    });

    testWithSemantics('the form it leads to shows the password masked', (
      tester,
    ) async {
      await open(tester, [email, password]);
      await tester.tap(find.text('Add entry'));
      await tester.pumpAndSettle();
      final field = fieldLabelled('Password');
      expect(tester.widget<TextField>(field).controller!.text, password);
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      expectSecretHidden(tester, password);
    });

    testWithSemantics('Arabic: masked, with the Arabic words for the eye', (
      tester,
    ) async {
      await open(tester, [email, password], locale: const Locale('ar'));
      expectSecretHidden(tester, password);
      expect(find.byTooltip('إظهار'), findsWidgets);
      expect(find.bySemanticsLabel('كلمة المرور مخفية'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('CSV import review', () {
    Future<void> openReview(WidgetTester tester) async {
      phone(tester, size: const Size(900, 1800));
      await createVault(tester);
      final parsed = services.importExport.importCsv(
        'name,url,username,password\n'
        'example.com,https://example.com/,$email,$password',
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<int>(
                  MaterialPageRoute(
                    builder: (_) => ImportReviewScreen(
                      imported: parsed.entries,
                      skipped: parsed.skipped,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWithSemantics('the rows do not carry the password at all', (
      tester,
    ) async {
      await openReview(tester);
      expect(find.text('Import 1'), findsOneWidget);
      expectSecretHidden(tester, password);
      expect(fieldsHolding(tester, password), isEmpty);
    });

    testWithSemantics('the edit dialog masks it; the eye shows it for 15 s', (
      tester,
    ) async {
      await openReview(tester);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.text('Edit login'), findsOneWidget);
      final field = fieldLabelled('Password');
      expect(tester.widget<TextField>(field).controller!.text, password);
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      expectSecretHidden(tester, password);
      expectEyeIs48(tester, field);

      await tapEye(tester, field);
      expect(tester.widget<TextField>(field).obscureText, isFalse);
      expectSecretShown(tester, password);

      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      expectSecretHidden(tester, password);
    });

    testWithSemantics('swap and edit work while it is masked', (tester) async {
      await openReview(tester);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      final field = fieldLabelled('Password');
      await tester.enterText(field, second);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, second);
      await tester.tap(find.text('Swap username and password'));
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, email);
      expect(tester.widget<TextField>(field).obscureText, isTrue);
    });
  });

  group('generator', () {
    testWithSemantics(
      'a freshly generated password stays readable, with Copy',
      (tester) async {
        phone(tester);
        await tester.pumpWidget(host(const GeneratorScreen()));
        await tester.pumpAndSettle();
        // The one place a password is shown at once: the user has to read it.
        final shown = find.byWidgetPredicate(
          (w) => w is SecretText && !w.obscure && w.text.isNotEmpty,
        );
        expect(shown, findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Copy'), findsOneWidget);
        // It is a new value every time, not a stored one: there is no history.
        expect(find.text('Password history'), findsNothing);
      },
    );
  });
}
