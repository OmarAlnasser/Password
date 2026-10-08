/// Render-and-look pictures of the vault screens (entry list, entry detail,
/// entry form, quick search). Skipped by default; run with
///
/// ```sh
/// SHOTS_DIR=/some/dir flutter test --run-skipped -t screenshots test/ui/vault_shots_test.dart
/// ```
///
/// Fake data only. Nothing is asserted: a `RenderFlex overflowed` error fails
/// the test, which is the point.
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/entry_detail_screen.dart';
import 'package:hisn/ui/entry_edit_screen.dart';
import 'package:hisn/ui/home_screen.dart';
import 'package:hisn/ui/quick_search_screen.dart';

import '../tool/screenshot_harness.dart';
import 'helpers.dart';

/// A valid Base32 secret (the RFC 6238 example), not tied to any account.
const _totp = 'JBSWY3DPEHPK3PXP';

List<VaultEntry> _entries() {
  final github = VaultEntry(
    id: 'github',
    title: 'GitHub',
    username: 'abcde07@hotmail.com',
    password: 'xQmR42abCD5k',
    url: 'https://github.com/login',
    notes: 'Recovery codes are in the safe.',
    tags: const ['work', 'dev'],
    favorite: true,
    totpSecret: _totp,
  ).edit(password: 'Tz8pLq2wXv9m!Kd', now: DateTime(2026, 3, 12));
  return [
    github,
    VaultEntry(
      id: 'google',
      title: 'Google',
      username: 'abcde07@gmail.com',
      password: 'violet-harbor-quantum-71-lantern',
      url: 'https://google.com',
      tags: const ['personal'],
      favorite: true,
    ),
    VaultEntry(
      id: 'mail',
      title: 'Work email',
      username: 'abcde07@hotmail.com',
      password: 'Rb7#mVq9zLp2',
      url: 'https://outlook.example.com',
      tags: const ['work'],
    ),
    VaultEntry(
      id: 'notion',
      title: 'Notion',
      username: 'abcde07@hotmail.com',
      password: 'Tz8pLq2wXv9m',
      url: 'https://notion.so',
      tags: const ['work', 'dev'],
    ),
    VaultEntry(
      id: 'bank',
      title: 'البنك الأهلي',
      username: 'abcde07',
      password: 'Nf4%tYu81hQe',
      url: 'https://bank.example.com',
      tags: const ['finance'],
    ),
    VaultEntry(
      id: 'router',
      title: 'Home Wi-Fi router',
      password: 'correct-horse-battery-staple',
      notes: 'Admin page: 192.168.1.1',
    ),
    VaultEntry(
      id: 'long',
      title: 'A very long entry name that has to be cut with an ellipsis',
      username: 'a.very.long.username.that.does.not.fit@example-company.com',
      password: 'xQmR42abCD5k',
      url: 'https://example-company.com',
    ),
    VaultEntry(
      id: 'dropbox',
      title: 'Dropbox',
      username: 'abcde07@hotmail.com',
      password: 'Hk3&pWz70xMc',
      url: 'https://dropbox.com',
      tags: const ['personal'],
    ),
    VaultEntry(
      id: 'stream',
      title: 'Streaming',
      username: 'family@example.com',
      password: 'Lp9!aSd24fGh',
      url: 'https://stream.example.com',
      tags: const ['personal'],
    ),
    VaultEntry(
      id: 'travel',
      title: 'Travel miles',
      username: 'abcde07',
      password: 'Qw5^eRt67yUi',
      tags: const ['personal'],
    ),
  ];
}

/// A 64 px icon on a transparent background, drawn here: a dark disc with a
/// light notch (what a black logo looks like) or a coloured square.
Future<Uint8List> _icon({required bool dark}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..color = dark ? const Color(0xFF1B1F24) : const Color(0xFF4285F4);
  if (dark) {
    canvas.drawCircle(const Offset(32, 32), 30, paint);
    canvas.drawCircle(
      const Offset(32, 36),
      11,
      ui.Paint()..color = const Color(0x00000000),
    );
  } else {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 6, 52, 52),
        const Radius.circular(12),
      ),
      paint,
    );
    canvas.drawCircle(
      const Offset(32, 32),
      12,
      ui.Paint()..color = const Color(0xFFFFFFFF),
    );
  }
  final image = await recorder.endRecording().toImage(64, 64);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_vault_shots');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Widget Function(Widget) scope() =>
      (app) => AppScope(services: services, child: app);

  /// A vault with [entries] and, for GitHub, Notion and Google, a stored icon.
  Future<void> vault(WidgetTester tester, {bool withEntries = true}) async {
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      if (!withEntries) return;
      final all = _entries();
      await services.session.saveEntries(all);
      final dark = await _icon(dark: true);
      final blue = await _icon(dark: false);
      for (final (host, bytes) in [
        ('github.com', dark),
        ('notion.so', dark),
        ('google.com', blue),
      ]) {
        await services.session.db.putFavicon(
          host: host,
          bytes: bytes,
          contentType: 'image/png',
          fetchedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
      await services.favicons!.prefetch([for (final e in all) e.url]);
    });
  }

  testWidgets('home: list', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home',
      sizes: [ShotSize.phone],
      wrap: scope(),
    );
  });

  testWidgets('home: two panes, nothing open and one open', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home-none',
      sizes: [ShotSize.desktop],
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home-open',
      sizes: [ShotSize.desktop],
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.text('GitHub').first);
        await t.pump(const Duration(milliseconds: 100));
      },
    );
  });

  testWidgets('home: medium width (tablet portrait)', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home-medium',
      sizes: [ShotSize.custom('tablet', 768, 1024)],
      themes: [Brightness.dark],
      wrap: scope(),
    );
  });

  testWidgets('home: filter, no results, empty vault', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home-fav',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.text(_l(t).favorites).first);
        await t.pump(const Duration(milliseconds: 200));
      },
    );
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home-noresults',
      sizes: [ShotSize.phone, ShotSize.desktop],
      themes: [Brightness.dark],
      wrap: scope(),
      afterPump: (t) async {
        await t.enterText(find.byType(SearchBar), 'zzz');
        await t.pump(const Duration(milliseconds: 200));
      },
    );
  });

  testWidgets('home: scrolled, the header turns to glass', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home-scrolled',
      sizes: [ShotSize.phone],
      locales: [const Locale('en')],
      wrap: scope(),
      afterPump: (t) async {
        await t.drag(find.byType(ListView).first, const Offset(0, -330));
        await t.pump(const Duration(milliseconds: 600));
      },
    );
  });

  testWidgets('home: empty vault', (tester) async {
    await vault(tester, withEntries: false);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home-empty',
      wrap: scope(),
    );
  });

  testWidgets('home: large text', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home-x15',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      textScale: 1.5,
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const HomeScreen(),
      'e-home-x2',
      sizes: [ShotSize.narrow],
      themes: [Brightness.dark],
      locales: [const Locale('ar')],
      textScale: 2,
      wrap: scope(),
    );
  });

  testWidgets('detail', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const EntryDetailScreen(entryId: 'github'),
      'e-detail',
      sizes: [ShotSize.phone],
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const EntryDetailScreen(entryId: 'github'),
      'e-detail-open',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      wrap: scope(),
      afterPump: (t) async {
        await t.tap(find.byTooltip(_l(t).show));
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(find.text('${_l(t).passwordHistory} (1)'));
        await t.pump(const Duration(milliseconds: 400));
      },
    );
    await pumpScreenshots(
      tester,
      const EntryDetailScreen(entryId: 'github'),
      'e-detail-x15',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      textScale: 1.5,
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const EntryDetailScreen(entryId: 'router'),
      'e-detail-bare',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const EntryDetailScreen(entryId: 'github'),
      'e-detail-medium',
      sizes: [ShotSize.custom('tablet', 768, 1024)],
      themes: [Brightness.dark],
      locales: [const Locale('en')],
      wrap: scope(),
    );
  });

  testWidgets('form', (tester) async {
    await vault(tester);
    final github = services.session.byId('github')!;
    await pumpScreenshots(
      tester,
      EntryEditScreen(existing: github),
      'e-edit',
      sizes: [ShotSize.custom('phone', 390, 1300)],
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      EntryEditScreen(
        prefill: VaultEntry(
          id: 'new',
          username: 'abcde07@hotmail.com',
          password: 'xQmR42abCD5k',
        ),
      ),
      'e-edit-ocr',
      sizes: [ShotSize.phone],
      themes: [Brightness.dark],
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const EntryEditScreen(),
      'e-edit-new',
      sizes: [ShotSize.desktop],
      themes: [Brightness.dark],
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      EntryEditScreen(existing: github),
      'e-edit-x15',
      sizes: [ShotSize.custom('phone', 390, 1700)],
      themes: [Brightness.dark],
      textScale: 1.5,
      wrap: scope(),
    );
  });

  testWidgets('quick search', (tester) async {
    await vault(tester);
    await pumpScreenshots(
      tester,
      const QuickSearchScreen(),
      'e-quick',
      sizes: [ShotSize.custom('window', 640, 520), ShotSize.phone],
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const QuickSearchScreen(),
      'e-quick-typed',
      sizes: [ShotSize.custom('window', 640, 520)],
      themes: [Brightness.dark],
      locales: [const Locale('en')],
      wrap: scope(),
      afterPump: (t) async {
        await t.enterText(find.byType(TextField), 'g');
        await t.pump(const Duration(milliseconds: 200));
      },
    );
    await pumpScreenshots(
      tester,
      const QuickSearchScreen(),
      'e-quick-none',
      sizes: [ShotSize.custom('window', 640, 520)],
      themes: [Brightness.dark],
      locales: [const Locale('en')],
      wrap: scope(),
      afterPump: (t) async {
        await t.enterText(find.byType(TextField), 'qqq');
        await t.pump(const Duration(milliseconds: 200));
      },
    );
  });
}

/// The strings of the language the screen is shown in.
AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));
