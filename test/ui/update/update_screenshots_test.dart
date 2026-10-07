@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/services/update/update_failure.dart';
import 'package:vaultsnap/services/update/update_installer.dart';
import 'package:vaultsnap/services/update/update_service.dart';
import 'package:vaultsnap/ui/update/update_settings_tile.dart';

import '../../tool/screenshot_harness.dart'
    show loadBundledFonts, shotsDir, ShotSize;
import 'update_ui_kit.dart';

/// Render-and-look: the update banner, sheet and settings block as PNGs, for
/// review only (see `test/tool/screenshot_harness.dart` and `docs/DESIGN.md`
/// section 14). Skipped unless asked for:
///
/// ```sh
/// SHOTS_DIR=/some/dir flutter test --run-skipped -t screenshots \
///     test/ui/update/update_screenshots_test.dart
/// ```
void main() {
  final key = GlobalKey();

  Widget boundary(Widget app) => RepaintBoundary(key: key, child: app);

  Future<void> capture(WidgetTester tester, String name) async {
    final shadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await tester.pump(const Duration(milliseconds: 50));
      final file = File('${shotsDir().path}/$name.png');
      await tester.runAsync(() async {
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
    } finally {
      debugDisableShadows = shadows;
    }
  }

  // The buttons by kind, so the same steps work in both languages: the
  // sheet's primary button is the last FilledButton on screen.
  Finder primary() => find.byType(FilledButton).last;

  Future<void> tapPrimary(WidgetTester tester) async {
    await tester.ensureVisible(primary());
    await tester.pumpAndSettle();
    await tester.tap(primary());
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(
      find.descendant(of: bannerFinder(), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
  }

  // One state of the flow, rendered in several looks.
  final states = <String, Future<void> Function(WidgetTester t, UpdateRig r)>{
    'banner': (t, r) async {},
    'sheet-available': (t, r) async => openSheet(t),
    'sheet-downloading': (t, r) async {
      await openSheet(t);
      await tapPrimary(t);
      r.service.emitProgress(18 * 1024 * 1024, 42 * 1024 * 1024);
      await t.pumpAndSettle();
    },
    'sheet-ready': (t, r) async {
      await openSheet(t);
      await tapPrimary(t);
      r.service.finishDownload();
      await t.pumpAndSettle();
    },
    'sheet-permission': (t, r) async {
      r.installer
        ..outcome = InstallOutcome.permissionRequired
        ..callPrepareExit = false;
      await openSheet(t);
      await tapPrimary(t);
      r.service.finishDownload();
      await t.pumpAndSettle();
      await tapPrimary(t);
    },
    'sheet-failed': (t, r) async {
      r.installer.outcome = InstallOutcome.failed;
      await openSheet(t);
      await tapPrimary(t);
      r.service.finishDownload();
      await t.pumpAndSettle();
      await tapPrimary(t);
    },
    'sheet-rejected': (t, r) async {
      await openSheet(t);
      await tapPrimary(t);
      r.service.failDownload(UpdateFailure.signatureInvalid);
      await t.pumpAndSettle();
    },
  };

  const looks = [
    ('phone-dark-en', Size(390, 844), Brightness.dark, Locale('en')),
    ('phone-dark-ar', Size(390, 844), Brightness.dark, Locale('ar')),
    ('phone-light-en', Size(390, 844), Brightness.light, Locale('en')),
    ('phone-light-ar', Size(390, 844), Brightness.light, Locale('ar')),
    ('desktop-dark-en', Size(1280, 800), Brightness.dark, Locale('en')),
  ];

  for (final MapEntry(key: name, value: setup) in states.entries) {
    for (final (label, size, brightness, locale) in looks) {
      testWidgets('$name $label', (tester) async {
        await tester.runAsync(loadBundledFonts);
        final rig = UpdateRig();
        addTearDown(rig.dispose);
        rig.service.offerUpdate(
          testManifest(
            notes: {
              'en': 'Faster unlock on older phones.\nThe update check now asks GitHub at most once a day.\nSmall fixes to the password generator.',
              'ar': 'فتح أسرع على الهواتف القديمة.\nيسأل فحص التحديثات الآن GitHub مرة واحدة يوميًا على الأكثر.\nإصلاحات صغيرة في مولّد كلمات المرور.',
            },
          ),
        );
        await pumpUpdateApp(
          tester,
          controller: rig.controller,
          locale: locale,
          brightness: brightness,
          size: size,
          wrap: boundary,
        );
        await tester.pumpAndSettle();
        await setup(tester, rig);
        await capture(tester, 'update-$name-$label');
      });
    }
  }

  // The settings block.
  final tileStates = <String, Future<void> Function(WidgetTester, UpdateRig)>{
    'idle': (t, r) async {},
    'uptodate': (t, r) async {
      r.service.nextCheck = const UpdateUpToDate(2000);
      await t.tap(find.byType(OutlinedButton));
      await t.pumpAndSettle();
    },
    'available': (t, r) async {
      r.service.offerUpdate();
      await t.tap(find.byType(OutlinedButton));
      await t.pumpAndSettle();
    },
    'error': (t, r) async {
      r.service.nextCheck = const UpdateFailed(UpdateFailure.signatureInvalid);
      await t.tap(find.byType(OutlinedButton));
      await t.pumpAndSettle();
    },
  };
  for (final MapEntry(key: name, value: setup) in tileStates.entries) {
    for (final (label, size, brightness, locale) in looks.take(4)) {
      testWidgets('tile $name $label', (tester) async {
        await tester.runAsync(loadBundledFonts);
        final rig = UpdateRig();
        addTearDown(rig.dispose);
        rig.settings.lastUpdateCheck = DateTime(
          2026,
          10,
          7,
          9,
          5,
        ).millisecondsSinceEpoch;
        await pumpTile(
          tester,
          UpdateSettingsTile(
            controller: rig.controller,
            settings: rig.settings,
            installed: UpdateRig.installed,
          ),
          locale: locale,
          brightness: brightness,
          size: size,
          wrap: boundary,
        );
        await tester.pumpAndSettle();
        await setup(tester, rig);
        await capture(tester, 'update-tile-$name-$label');
      });
    }
  }

  // Text at 200 % on the smallest phone.
  testWidgets('sheet at 200% text', (tester) async {
    await tester.runAsync(loadBundledFonts);
    final rig = UpdateRig();
    addTearDown(rig.dispose);
    rig.service.offerUpdate();
    await pumpUpdateApp(
      tester,
      controller: rig.controller,
      size: ShotSize.narrow.size,
      textScale: 2,
      wrap: boundary,
    );
    await tester.pumpAndSettle();
    await openSheet(tester);
    await capture(tester, 'update-sheet-available-narrow-200');
  });
}
