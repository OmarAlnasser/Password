import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/services/settings.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vs_settings');
    file = File('${dir.path}/settings.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<AppSettings> reopened() async {
    final s = AppSettings(file);
    await s.load();
    return s;
  }

  Map<String, Object?> saved() =>
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

  test('the default is "recent", with or without a file', () async {
    expect(AppSettings(file).entrySort, EntrySort.recent);
    expect((await reopened()).entrySort, EntrySort.recent);
  });

  test('a choice made through update() is saved and restored', () async {
    for (final choice in EntrySort.values) {
      final s = AppSettings(file);
      await s.update((s) => s.entrySort = choice);
      expect(saved()['sort'], choice.name);
      expect((await reopened()).entrySort, choice);
    }
  });

  test('update() notifies once for the change', () async {
    final s = AppSettings(file);
    var n = 0;
    s.addListener(() => n++);
    await s.update((s) => s.entrySort = EntrySort.title);
    expect(n, 1);
    expect(s.entrySort, EntrySort.title);
  });

  test('assigning the property directly notifies at once and saves', () async {
    final s = AppSettings(file);
    var n = 0;
    s.addListener(() => n++);

    s.entrySort = EntrySort.added;

    expect(s.entrySort, EntrySort.added);
    expect(n, 1, reason: 'synchronously, before the file is written');
    // The save runs in the background.
    for (var i = 0; i < 100 && !file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect((await reopened()).entrySort, EntrySort.added);
    expect(n, 1, reason: 'one change, one notification');
  });

  test('setting the value it already has does nothing', () async {
    final s = AppSettings(file);
    var n = 0;
    s.addListener(() => n++);
    s.entrySort = EntrySort.recent;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(n, 0);
    expect(file.existsSync(), isFalse);
  });

  test('a save that fails does not throw into the caller', () async {
    // The parent "directory" is a file, so the write cannot succeed.
    final blocker = File('${dir.path}/blocked')..writeAsStringSync('x');
    final s = AppSettings(File('${blocker.path}/settings.json'));
    s.entrySort = EntrySort.title;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.entrySort, EntrySort.title);
  });

  group('tolerant parsing', () {
    Future<EntrySort> parse(Object? value) async {
      file.writeAsStringSync(jsonEncode({'sort': value}));
      return (await reopened()).entrySort;
    }

    test('every known name', () async {
      for (final v in EntrySort.values) {
        expect(await parse(v.name), v);
      }
    });

    test('anything else is the default', () async {
      expect(await parse('bogus'), EntrySort.recent);
      expect(await parse(''), EntrySort.recent);
      expect(await parse('Title'), EntrySort.recent, reason: 'exact names');
      expect(await parse('title '), EntrySort.recent);
      expect(await parse(null), EntrySort.recent);
      expect(await parse(2), EntrySort.recent);
      expect(await parse(true), EntrySort.recent);
      expect(await parse(['title']), EntrySort.recent);
      expect(await parse({'a': 1}), EntrySort.recent);
    });

    test('a file from before this setting existed', () async {
      file.writeAsStringSync(jsonEncode({'theme': 'light', 'autoLock': 300}));
      final s = await reopened();
      expect(s.entrySort, EntrySort.recent);
      expect(s.themeMode, ThemeMode.light);
      expect(s.autoLockSeconds, 300);
    });

    test('a damaged file gives the default', () async {
      file.writeAsStringSync('{ not json');
      expect((await reopened()).entrySort, EntrySort.recent);
      file.writeAsStringSync('[]');
      expect((await reopened()).entrySort, EntrySort.recent);
    });

    test('an unrelated bad value cannot hide a saved choice', () async {
      file.writeAsStringSync(
        jsonEncode({'sort': 'added', 'theme': 'not-a-theme'}),
      );
      expect((await reopened()).entrySort, EntrySort.added);
    });

    test('loading again after the file lost the key resets it', () async {
      final s = AppSettings(file);
      await s.update((s) => s.entrySort = EntrySort.title);
      file.writeAsStringSync(jsonEncode({'theme': 'dark'}));
      await s.load();
      expect(s.entrySort, EntrySort.recent);
    });
  });

  test('the other settings are saved next to it unchanged', () async {
    final s = AppSettings(file);
    await s.update((s) {
      s.entrySort = EntrySort.title;
      s.themeMode = ThemeMode.light;
      s.autoLockSeconds = 600;
      s.fetchIcons = false;
    });
    final back = await reopened();
    expect(back.entrySort, EntrySort.title);
    expect(back.themeMode, ThemeMode.light);
    expect(back.autoLockSeconds, 600);
    expect(back.fetchIcons, isFalse);
    // And a later, unrelated update keeps the sort choice.
    await back.update((s) => s.hibpEnabled = false);
    expect((await reopened()).entrySort, EntrySort.title);
  });

  test('EntrySort is available from the settings library', () {
    // The import above is only of settings.dart.
    expect(EntrySort.values, hasLength(3));
  });
}
