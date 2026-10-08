import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/import_export.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/import/import_review_screen.dart';

import 'helpers.dart';

/// The CSV import review: nothing is saved until the user has seen what
/// each login will do. All values are synthetic.
void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_review');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  testWidgets('groups logins by site, fixes one, imports the ticked ones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      await services.session.saveEntries([
        VaultEntry(
          id: 'contoso',
          title: 'Contoso mail',
          username: 'abcde07@hotmail.com',
          password: 'Tz8pLq2wXv9m',
          url: 'https://mail.contoso-test.com/',
        ),
        VaultEntry(
          id: 'northwind',
          title: 'Northwind',
          username: 'abcde07@hotmail.com',
          password: 'Hb5nRw3kYs7d',
          url: 'https://www.northwind-test.com/',
        ),
      ]);
    });
    final parsed = services.importExport.importCsv(
      [
        'name,url,username,password,note',
        // In the vault with another password: update.
        'mail.contoso-test.com,https://mail.contoso-test.com/login?next=x,'
            'abcde07@hotmail.com,xQmR42abCD5k,',
        // Twice in the file: one merged new entry.
        'shop.fabrikam-test.org,https://shop.fabrikam-test.org/,'
            'abcde07@hotmail.com,Hb5nRw3kYs7d,',
        'shop.fabrikam-test.org,https://shop.fabrikam-test.org/cart,'
            'abcde07@hotmail.com,Hb5nRw3kYs7d,',
        // Exactly as in the vault: nothing to do.
        'northwind-test.com,https://northwind-test.com/,'
            'abcde07@hotmail.com,Hb5nRw3kYs7d,',
        // Username and password in each other's columns.
        'forum.tailspin-test.net,https://forum.tailspin-test.net/,'
            'xQmR42abCD5k,abcde07@hotmail.com,',
      ].join('\n'),
    );
    int? saved;
    var closed = false;
    await tester.pumpWidget(
      _Host(
        services: services,
        parsed: parsed,
        onClosed: (n) {
          saved = n;
          closed = true;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Summary.
    expect(find.text('4 logins in the file'), findsOneWidget);
    for (final pill in [
      'Update: 1',
      'Merged duplicates: 1',
      'Already saved: 1',
      'Needs attention: 1',
    ]) {
      expect(find.text(pill), findsOneWidget, reason: pill);
    }
    expect(find.textContaining('New:'), findsNothing);

    // One group per site, sorted by name.
    final headers = [
      'Contoso Test',
      'Fabrikam Test',
      'Northwind Test',
      'Tailspin Test',
    ];
    final tops = [for (final h in headers) tester.getTopLeft(find.text(h)).dy];
    expect(tops, [...tops]..sort());

    Finder tile(String site) =>
        find.ancestor(of: find.text(site), matching: find.byType(ListTile));
    Finder inTile(String url, Finder f) =>
        find.descendant(of: tile(url), matching: f);
    bool ticked(String url) =>
        tester.widget<Checkbox>(inTile(url, find.byType(Checkbox))).value!;

    // Status and issue chips per login; broken and identical ones unticked.
    const contoso = 'https://mail.contoso-test.com/';
    const fabrikam = 'https://shop.fabrikam-test.org/';
    const northwind = 'https://northwind-test.com/';
    const tailspin = 'https://forum.tailspin-test.net/';
    expect(inTile(contoso, find.text('Update')), findsOneWidget);
    expect(
      inTile(contoso, find.text('Saved with another password')),
      findsOneWidget,
    );
    expect(inTile(fabrikam, find.text('Merged duplicates')), findsOneWidget);
    expect(inTile(fabrikam, find.text('Duplicate in file')), findsOneWidget);
    expect(inTile(northwind, find.text('Already saved')), findsOneWidget);
    expect(inTile(tailspin, find.text('Needs attention')), findsOneWidget);
    expect(
      inTile(tailspin, find.text('Password looks like an email')),
      findsOneWidget,
    );
    expect(ticked(contoso), isTrue);
    expect(ticked(fabrikam), isTrue);
    expect(ticked(northwind), isFalse);
    expect(ticked(tailspin), isFalse);
    expect(find.text('Import 2'), findsOneWidget);

    // Fix the swapped columns: the login becomes a new, ticked entry.
    await tester.tap(tile(tailspin));
    await tester.pumpAndSettle();
    expect(find.text('Edit login'), findsOneWidget);
    await tester.tap(find.text('Swap username and password'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(inTile(tailspin, find.text('New')), findsOneWidget);
    expect(ticked(tailspin), isTrue);
    expect(find.text('Import 3'), findsOneWidget);

    // Leave the merged duplicate out.
    await tester.tap(inTile(fabrikam, find.byType(Checkbox)));
    await tester.pump();
    expect(find.text('Import 2'), findsOneWidget);

    await tester.runAsync(() => tester.tap(find.text('Import 2')));
    await pumpUntilFound(tester, find.text('open'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(saved, 2);

    final entries = {for (final e in services.session.entries) e.url: e};
    expect(entries.keys, hasLength(3)); // contoso, northwind, tailspin
    final updated = services.session.byId('contoso')!;
    expect(updated.password, 'xQmR42abCD5k');
    expect(updated.title, 'Contoso mail');
    expect(updated.history.map((h) => h.password), ['Tz8pLq2wXv9m']);
    final fixed = entries[tailspin]!;
    expect(fixed.username, 'abcde07@hotmail.com');
    expect(fixed.password, 'xQmR42abCD5k');
    expect(services.session.byId('northwind')!.password, 'Hb5nRw3kYs7d');
    expect(entries.keys.where((u) => u.contains('fabrikam')), isEmpty);
  });

  testWidgets('leaving the review saves nothing', (tester) async {
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
    });
    final parsed = services.importExport.importCsv(
      'name,url,username,password\n'
      'example.com,https://example.com/,abcde07@hotmail.com,xQmR42abCD5k',
    );
    var closed = false;
    int? saved;
    await tester.pumpWidget(
      _Host(
        services: services,
        parsed: parsed,
        onClosed: (n) {
          saved = n;
          closed = true;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Import 1'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(saved, isNull);
    expect(services.session.entries, isEmpty);
  });
}

/// Opens the review screen on tap and reports what it popped with.
class _Host extends StatelessWidget {
  const _Host({
    required this.services,
    required this.parsed,
    required this.onClosed,
  });

  final AppServices services;
  final ImportResult parsed;
  final void Function(int? saved) onClosed;

  @override
  Widget build(BuildContext context) => AppScope(
    services: services,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => onClosed(
              await Navigator.of(context).push<int>(
                MaterialPageRoute(
                  builder: (_) => ImportReviewScreen(
                    imported: parsed.entries,
                    skipped: parsed.skipped,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}
