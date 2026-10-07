import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultsnap/services/settings.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('settings-test-');
    file = File(p.join(dir.path, 'settings.json'));
  });
  tearDown(() async => dir.delete(recursive: true));

  test('defaults: automatic checks on, nothing seen or skipped', () {
    final s = AppSettings(file);
    expect(s.checkUpdates, isTrue);
    expect(s.lastUpdateCheck, 0);
    expect(s.highestSeenBuild, 0);
    expect(s.skippedBuild, 0);
  });

  test(
    'a settings file from an older version loads with the defaults',
    () async {
      await file.writeAsString(jsonEncode({'theme': 'dark', 'autoLock': 300}));
      final s = AppSettings(file);
      await s.load();
      expect(s.autoLockSeconds, 300);
      expect(s.checkUpdates, isTrue);
      expect(s.highestSeenBuild, 0);
    },
  );

  test('the update fields persist like the others', () async {
    final s = AppSettings(file);
    await s.update((s) {
      s.checkUpdates = false;
      s.lastUpdateCheck = 1790000000000;
      s.highestSeenBuild = 2001;
      s.skippedBuild = 2000;
      s.fetchIcons = false;
    });
    final r = AppSettings(file);
    await r.load();
    expect(r.checkUpdates, isFalse);
    expect(r.lastUpdateCheck, 1790000000000);
    expect(r.highestSeenBuild, 2001);
    expect(r.skippedBuild, 2000);
    expect(r.fetchIcons, isFalse, reason: 'other fields are untouched');
  });

  test('notifies listeners on change', () async {
    final s = AppSettings(file);
    var n = 0;
    s.addListener(() => n++);
    await s.update((s) => s.skippedBuild = 5);
    expect(n, 1);
  });

  test('negative or non-integer values from the file become 0', () async {
    for (final bad in [
      -5,
      'x',
      1.5,
      null,
      true,
      [1],
    ]) {
      await file.writeAsString(
        jsonEncode({'updChecked': bad, 'updHighest': bad, 'updSkipped': bad}),
      );
      final s = AppSettings(file);
      await s.load();
      expect(s.lastUpdateCheck, 0, reason: '$bad');
      expect(s.highestSeenBuild, 0, reason: '$bad');
      expect(s.skippedBuild, 0, reason: '$bad');
    }
  });

  test('negative values are clamped when saved', () async {
    final s = AppSettings(file);
    await s.update((s) {
      s.lastUpdateCheck = -1;
      s.highestSeenBuild = -1;
      s.skippedBuild = -1;
    });
    expect(s.lastUpdateCheck, 0);
    expect(s.highestSeenBuild, 0);
    expect(s.skippedBuild, 0);
  });

  test('the settings file holds no URL, path or version text', () async {
    final s = AppSettings(file);
    await s.update((s) => s.highestSeenBuild = 2000);
    final text = await file.readAsString();
    expect(text, isNot(contains('http')));
    expect(text, isNot(contains(dir.path)));
  });
}
