import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultsnap/services/update/update_installer.dart';
import 'package:vaultsnap/services/update/windows_installer.dart';

// ---------------------------------------------------------------------------
// A tiny zip writer, independent of the code under test, that can also write
// broken and hostile archives.
// ---------------------------------------------------------------------------

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final b in data) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}

class ZEntry {
  ZEntry(
    this.name,
    this.data, {
    this.method = 8,
    this.flags = 0,
    this.madeBy = 20,
    this.attributes = 0,
    this.descriptor = false,
    this.crc,
    this.declaredSize,
    this.rawCompressed,
    this.rawName,
    this.localName,
    this.localOffset,
    this.compressedOverride,
  });

  /// A folder entry.
  ZEntry.folder(String name) : this(name.endsWith('/') ? name : '$name/', []);

  final String name;
  final List<int> data;
  final int method;
  final int flags;

  /// `host << 8 | version`; host 3 is Unix, 0 is DOS/FAT, 10 is NTFS.
  final int madeBy;
  final int attributes;

  /// Write sizes and CRC after the data (flag bit 3), zero them in the local
  /// header, as streaming zip writers do.
  final bool descriptor;

  /// Lies in the central directory.
  final int? crc;
  final int? declaredSize;
  final int? compressedOverride;

  /// Replaces the compressed bytes (to write damaged streams).
  final List<int>? rawCompressed;

  /// Replaces the name bytes of the central / local header.
  final List<int>? rawName;
  final List<int>? localName;

  /// Points the central directory at another entry's local header.
  final int? localOffset;
}

Uint8List buildZip(
  List<ZEntry> entries, {
  List<int> comment = const [],
  List<int> trailing = const [],
  int? declaredCount,
  int diskNumber = 0,
  int? directoryOffsetOverride,
  bool zip64Locator = false,
}) {
  final out = BytesBuilder();
  final offsets = <int>[];
  final compressedSizes = <int>[];
  void u16(BytesBuilder b, int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);

  for (final e in entries) {
    final nameBytes = e.rawName ?? utf8.encode(e.name);
    final localNameBytes = e.localName ?? nameBytes;
    final compressed =
        e.rawCompressed ??
        (e.method == 8
            ? (e.data.isEmpty
                  ? <int>[]
                  : ZLibEncoder(raw: true).convert(e.data))
            : e.data);
    offsets.add(out.length);
    compressedSizes.add(compressed.length);
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, e.flags | (e.descriptor ? 8 : 0));
    u16(out, e.method);
    u16(out, 0);
    u16(out, 0x21);
    u32(out, e.descriptor ? 0 : _crc32(e.data));
    u32(out, e.descriptor ? 0 : compressed.length);
    u32(out, e.descriptor ? 0 : e.data.length);
    u16(out, localNameBytes.length);
    u16(out, 0);
    out.add(localNameBytes);
    out.add(compressed);
    if (e.descriptor) {
      u32(out, 0x08074b50);
      u32(out, _crc32(e.data));
      u32(out, compressed.length);
      u32(out, e.data.length);
    }
  }

  final directoryStart = out.length;
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final nameBytes = e.rawName ?? utf8.encode(e.name);
    u32(out, 0x02014b50);
    u16(out, e.madeBy);
    u16(out, 20);
    u16(out, e.flags | (e.descriptor ? 8 : 0));
    u16(out, e.method);
    u16(out, 0);
    u16(out, 0x21);
    u32(out, e.crc ?? _crc32(e.data));
    u32(out, e.compressedOverride ?? compressedSizes[i]);
    u32(out, e.declaredSize ?? e.data.length);
    u16(out, nameBytes.length);
    u16(out, 0);
    u16(out, 0);
    u16(out, 0);
    u16(out, 0);
    u32(out, e.attributes);
    u32(out, e.localOffset ?? offsets[i]);
    out.add(nameBytes);
  }
  final directoryEnd = out.length;
  if (zip64Locator) {
    u32(out, 0x07064b50);
    u32(out, 0);
    out.add(List<int>.filled(8, 0));
    u32(out, 1);
  }
  u32(out, 0x06054b50);
  u16(out, diskNumber);
  u16(out, 0);
  u16(out, declaredCount ?? entries.length);
  u16(out, declaredCount ?? entries.length);
  u32(out, directoryEnd - directoryStart);
  u32(out, directoryOffsetOverride ?? directoryStart);
  u16(out, comment.length);
  out.add(comment);
  out.add(trailing);
  return out.toBytes();
}

/// A stored local file record (header and data), as it would sit in a zip.
List<int> _localRecord(String name, List<int> data) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  u32(0x04034b50);
  u16(20);
  u16(0);
  u16(0);
  u16(0);
  u16(0x21);
  u32(_crc32(data));
  u32(data.length);
  u32(data.length);
  u16(utf8.encode(name).length);
  u16(0);
  b.add(utf8.encode(name));
  b.add(data);
  return b.toBytes();
}

/// File attributes of a Unix symlink / FIFO / regular file as zip writers put
/// them (`st_mode << 16`).
int unixMode(int mode) => mode << 16;

const int unixHost = 3 << 8;

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

/// The files of a Flutter Windows release folder, small.
List<ZEntry> releaseEntries({
  String exe = 'app.exe',
  String? prefix,
  bool engine = true,
  bool data = true,
  List<int>? exeBytes,
  String version = 'NEW',
}) {
  String n(String s) => prefix == null ? s : '$prefix/$s';
  return [
    ZEntry(n(exe), exeBytes ?? [0x4d, 0x5a, ...utf8.encode('exe-$version')]),
    if (engine) ZEntry(n('flutter_windows.dll'), bytesOf('engine-$version')),
    if (data) ...[
      ZEntry.folder(n('data')),
      ZEntry(n('data/app.so'), bytesOf('aot-$version' * 50)),
      ZEntry(n('data/icudtl.dat'), bytesOf('icu')),
      ZEntry.folder(n('data/flutter_assets')),
      ZEntry(n('data/flutter_assets/a.bin'), bytesOf('asset-$version')),
    ],
  ];
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeProcess implements Process {
  FakeProcess(this.pid);

  @override
  final int pid;

  bool killed = false;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();
}

class StartCall {
  StartCall(this.executable, this.arguments, this.workingDirectory, this.mode);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final ProcessStartMode mode;

  /// The value after `-Name`.
  String arg(String name) => arguments[arguments.indexOf(name) + 1];
}

// ---------------------------------------------------------------------------

/// Where a PowerShell 7 lives, or null.
final String? pwsh = () {
  try {
    final r = Process.runSync('pwsh', [
      '-NoProfile',
      '-Command',
      r'$PSVersionTable.PSVersion.Major',
    ]);
    if (r.exitCode == 0) return 'pwsh';
  } on Object {
    // Not installed.
  }
  return null;
}();

void main() {
  late Directory tmp;
  late Directory work;
  late Directory out;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('windows_installer_test_');
    work = Directory(p.join(tmp.path, 'work'))..createSync();
    out = Directory(p.join(work.path, 'out'))..createSync();
    // Something next to the staging folder that must never be touched.
    File(p.join(tmp.path, 'canary.txt')).writeAsStringSync('canary');
    File(p.join(work.path, 'canary.txt')).writeAsStringSync('canary');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  File writeZip(Uint8List bytes, [String name = 'package.zip']) {
    final f = File(p.join(work.path, name));
    f.writeAsBytesSync(bytes);
    return f;
  }

  /// Every file and folder under [tmp] outside [out].
  Set<String> outside() => tmp
      .listSync(recursive: true, followLinks: false)
      .map((e) => e.path)
      .where(
        (path) =>
            !p.isWithin(out.path, path) &&
            path != out.path &&
            path != p.join(work.path, 'package.zip'),
      )
      .toSet();

  Set<String> inside() => out
      .listSync(recursive: true, followLinks: false)
      .map((e) => p.relative(e.path, from: out.path))
      .toSet();

  Future<ZipExtraction> extract(
    Uint8List zip, {
    ZipLimits limits = const ZipLimits(),
  }) => SafeZipExtractor(limits: limits).extract(writeZip(zip), out);

  Future<void> expectRejected(
    Uint8List zip,
    ZipRejection reason, {
    ZipLimits limits = const ZipLimits(),
  }) async {
    final before = outside();
    await expectLater(
      extract(zip, limits: limits),
      throwsA(isA<ZipException>().having((e) => e.reason, 'reason', reason)),
    );
    // Nothing escaped the staging folder.
    expect(outside(), before);
  }

  /// The extractor insists on an empty target, and a failed run may leave a
  /// partial result there (the caller deletes it): start the next one clean.
  void emptyOut() {
    for (final e in out.listSync(followLinks: false)) {
      e.deleteSync(recursive: true);
    }
  }

  // =========================================================================
  group('SafeZipExtractor: valid archives', () {
    test('stored and deflated files, folders, empty files, unicode', () async {
      final big = List<int>.generate(300000, (i) => (i * 7 + i ~/ 13) & 0xff);
      final zip = buildZip([
        ZEntry('a.txt', bytesOf('hello')),
        ZEntry('stored.bin', big, method: 0),
        ZEntry('deflated.bin', big),
        ZEntry('empty.txt', []),
        ZEntry('empty-stored.txt', [], method: 0),
        ZEntry.folder('dir'),
        ZEntry('dir/sub/deep.txt', bytesOf('deep')),
        ZEntry.folder('empty-dir'),
        ZEntry('caf\u00e9 \u0627\u0644/x y.txt', bytesOf('unicode')),
      ]);

      final result = await extract(zip);

      expect(result.files, 7);
      expect(result.directories, 2);
      expect(result.totalBytes, 5 + 300000 * 2 + 4 + 7);
      expect(File(p.join(out.path, 'a.txt')).readAsStringSync(), 'hello');
      expect(File(p.join(out.path, 'stored.bin')).readAsBytesSync(), big);
      expect(File(p.join(out.path, 'deflated.bin')).readAsBytesSync(), big);
      expect(File(p.join(out.path, 'empty.txt')).lengthSync(), 0);
      expect(File(p.join(out.path, 'empty-stored.txt')).lengthSync(), 0);
      expect(
        File(p.join(out.path, 'dir', 'sub', 'deep.txt')).readAsStringSync(),
        'deep',
      );
      expect(Directory(p.join(out.path, 'empty-dir')).existsSync(), isTrue);
      expect(
        File(p.join(out.path, 'caf\u00e9 \u0627\u0644', 'x y.txt'))
            .readAsStringSync(),
        'unicode',
      );
    });

    test('a data descriptor after the data (streaming writers)', () async {
      final zip = buildZip([
        ZEntry('one.txt', bytesOf('first' * 100), descriptor: true),
        ZEntry('two.bin', bytesOf('second'), method: 0, descriptor: true),
      ]);

      await extract(zip);

      expect(
        File(p.join(out.path, 'one.txt')).readAsStringSync(),
        'first' * 100,
      );
      expect(File(p.join(out.path, 'two.bin')).readAsStringSync(), 'second');
    });

    test('backslash separators are read as folders', () async {
      final zip = buildZip([
        ZEntry(r'data\flutter_assets\a.bin', [1, 2, 3]),
      ]);

      await extract(zip);

      expect(
        File(p.join(out.path, 'data', 'flutter_assets', 'a.bin'))
            .readAsBytesSync(),
        [1, 2, 3],
      );
    });

    test('a folder entry listed twice, and after its files, is fine', () async {
      final zip = buildZip([
        ZEntry.folder('d'),
        ZEntry('d/x.txt', [1]),
        ZEntry.folder('d'),
      ]);

      final result = await extract(zip);

      expect(result.files, 1);
      expect(inside(), {'d', p.join('d', 'x.txt')});
    });

    test('Unix and NTFS hosts with ordinary attributes', () async {
      final zip = buildZip([
        ZEntry('a', [1], madeBy: unixHost | 20, attributes: unixMode(0x81a4)),
        ZEntry(
          'b',
          [2],
          madeBy: 10 << 8 | 45,
          attributes: 0x20, // archive bit
        ),
        ZEntry('c/', [], madeBy: unixHost | 20, attributes: unixMode(0x41ed)),
      ]);

      final result = await extract(zip);

      expect(result.files, 2);
    });

    test('archives written by Python zipfile (plain and streaming)', () async {
      for (final b64 in [_pythonPlainZip, _pythonStreamingZip]) {
        out.deleteSync(recursive: true);
        out.createSync();

        final result = await extract(base64.decode(b64));

        expect(result.files, 4);
        expect(result.directories, 1);
        expect(File(p.join(out.path, 'app.exe')).readAsBytesSync().take(2), [
          0x4d,
          0x5a,
        ]);
        expect(
          File(p.join(out.path, 'data', 'hello.txt')).readAsStringSync(),
          'hello hello hello hello hello hello\n' * 20,
        );
        expect(
          File(p.join(out.path, 'data', 'caf\u00e9 \u0627\u0644.txt'))
              .readAsStringSync(),
          'unicode',
        );
        expect(
          File(p.join(out.path, 'stored.bin')).readAsBytesSync(),
          List<int>.generate(256, (i) => i),
        );
      }
    });
  });

  // =========================================================================
  group('SafeZipExtractor.checkName', () {
    List<String> ok(String name) => SafeZipExtractor.checkName(name);

    void rejected(String name, {int maxPathLength = 200, int maxDepth = 24}) {
      expect(
        () => SafeZipExtractor.checkName(
          name,
          maxPathLength: maxPathLength,
          maxDepth: maxDepth,
        ),
        throwsA(
          isA<ZipException>().having(
            (e) => e.reason,
            'reason',
            ZipRejection.unsafeName,
          ),
        ),
        reason: 'name ${jsonEncode(name)} must be refused',
      );
    }

    test('plain relative names pass', () {
      expect(ok('a.txt'), ['a.txt']);
      expect(ok('data/flutter_assets/a.bin'), [
        'data',
        'flutter_assets',
        'a.bin',
      ]);
      expect(ok('data/'), ['data']);
      expect(ok(r'data\flutter_assets\'), ['data', 'flutter_assets']);
      expect(ok('caf\u00e9/\u0627\u0644.txt'), [
        'caf\u00e9',
        '\u0627\u0644.txt',
      ]);
      expect(ok('a b/c d.txt'), ['a b', 'c d.txt']);
      expect(ok('.hidden'), ['.hidden']);
      expect(ok('v1.2.3/lib-x_y.dll'), ['v1.2.3', 'lib-x_y.dll']);
      // Device names are only reserved as a whole base name.
      expect(ok('console.txt'), ['console.txt']);
      expect(ok('auxiliary/nullable'), ['auxiliary', 'nullable']);
      expect(ok('com10.txt'), ['com10.txt']);
    });

    test('parent folders (zip slip)', () {
      for (final n in [
        '../evil.txt',
        '..',
        'a/../../evil',
        'a/b/../../../evil',
        r'..\evil.txt',
        r'a\..\..\evil.txt',
        'a/..',
        '../',
        '..\\',
        'a/../b',
      ]) {
        rejected(n);
      }
    });

    test('absolute, UNC and device paths', () {
      for (final n in [
        '/etc/passwd',
        r'\Windows\x',
        '//server/share/x',
        r'\\server\share\x',
        r'\\?\C:\x',
        r'\\.\pipe\x',
        '/',
      ]) {
        rejected(n);
      }
    });

    test('drive letters and alternate data streams', () {
      for (final n in [
        'C:/x',
        'C:x',
        r'c:\windows\system32\x.dll',
        'a/C:/x',
        'a.txt:stream',
        'a.txt::\$DATA',
        'dir:name/file',
        'x:',
      ]) {
        rejected(n);
      }
    });

    test('empty, dot and doubled separators', () {
      for (final n in ['', '.', './a', 'a/./b', 'a//b', 'a/', '//', r'a\\b']) {
        if (n == 'a/') {
          expect(ok(n), ['a']);
        } else {
          rejected(n);
        }
      }
    });

    test('Windows device names, with and without extension', () {
      for (final n in [
        'con',
        'CON',
        'con.txt',
        'dir/NUL',
        'dir/nul.dll',
        'Aux.x.y',
        'prn',
        'COM1',
        'com9.log',
        'LPT1',
        'lpt9.txt',
        'conin\$',
        'CONOUT\$',
        'com\u00b9',
        'lpt\u00b2.txt',
        'con .txt',
      ]) {
        rejected(n);
      }
    });

    test('trailing and leading dots and spaces, short-name aliases', () {
      for (final n in [
        'a.',
        'a ',
        ' a',
        'dir./x',
        'dir /x',
        'a...',
        'PROGRA~1',
        'x/FLUTTE~1/y.dll',
        'name~2.txt',
      ]) {
        rejected(n);
      }
    });

    test('characters Windows does not allow, controls and bidi marks', () {
      for (final n in [
        'a<b',
        'a>b',
        'a|b',
        'a?b',
        'a*b',
        'a"b',
        'a\u0000b',
        'a\u0001b',
        'a\nb',
        'a\tb',
        'a\u007fb',
        'a\u0085b',
        'evil\u202etxt.exe',
        '\u2066a',
      ]) {
        rejected(n);
      }
    });

    test('length and depth limits', () {
      rejected('a' * 256);
      rejected('a/' * 30 + 'b');
      rejected('d/' * 5 + 'x' * 60, maxPathLength: 40);
      expect(ok('a/' * 23 + 'b').length, 24);
    });
  });

  // =========================================================================
  group('SafeZipExtractor: hostile archives', () {
    test('zip slip through the real extraction, nothing escapes', () async {
      for (final name in [
        '../escape.txt',
        r'..\escape.txt',
        'a/../../escape.txt',
        '/abs/escape.txt',
        r'C:\escape.txt',
        'C:escape.txt',
        r'\\server\share\escape.txt',
      ]) {
        final zip = buildZip([
          ZEntry('good.txt', bytesOf('good')),
          ZEntry(name, bytesOf('evil')),
        ]);

        await expectRejected(zip, ZipRejection.unsafeName);

        // The names are checked before the first file is written.
        expect(inside(), isEmpty, reason: 'nothing written for $name');
        expect(File(p.join(work.path, 'escape.txt')).existsSync(), isFalse);
        expect(File(p.join(tmp.path, 'escape.txt')).existsSync(), isFalse);
      }
    });

    test('names that are not valid UTF-8', () async {
      final zip = buildZip([
        ZEntry('placeholder', [1], rawName: [0x61, 0xff, 0xfe, 0x62]),
      ]);

      await expectRejected(zip, ZipRejection.unsafeName);
    });

    test('duplicates: same name, other case, file versus folder', () async {
      await expectRejected(
        buildZip([
          ZEntry('a.txt', [1]),
          ZEntry('a.txt', [2]),
        ]),
        ZipRejection.duplicate,
      );
      await expectRejected(
        buildZip([
          ZEntry('Data/x.txt', [1]),
          ZEntry('data/X.TXT', [2]),
        ]),
        ZipRejection.duplicate,
      );
      await expectRejected(
        buildZip([
          ZEntry('A.txt', [1]),
          ZEntry('a.txt', [2]),
        ]),
        ZipRejection.duplicate,
      );
      // A file and a folder of the same name, in both orders.
      await expectRejected(
        buildZip([
          ZEntry('a', [1]),
          ZEntry('a/b.txt', [2]),
        ]),
        ZipRejection.duplicate,
      );
      await expectRejected(
        buildZip([
          ZEntry('a/b.txt', [2]),
          ZEntry('a', [1]),
        ]),
        ZipRejection.duplicate,
      );
      await expectRejected(
        buildZip([
          ZEntry.folder('a'),
          ZEntry('a', [1]),
        ]),
        ZipRejection.duplicate,
      );
      // Same folder spelled in two cases.
      await expectRejected(
        buildZip([
          ZEntry('Data/x.txt', [1]),
          ZEntry('data/y.txt', [2]),
        ]),
        ZipRejection.duplicate,
      );
      // Backslash and slash spellings of one path.
      await expectRejected(
        buildZip([
          ZEntry('d/x', [1]),
          ZEntry(r'd\x', [2]),
        ]),
        ZipRejection.duplicate,
      );
    });

    test('symbolic links and special files', () async {
      for (final mode in [0xa1ff, 0x1180, 0x2180, 0x6180, 0xc180]) {
        final zip = buildZip([
          ZEntry('good.txt', [1]),
          ZEntry(
            'link',
            bytesOf('/etc/passwd'),
            madeBy: unixHost | 20,
            attributes: unixMode(mode),
          ),
        ]);
        await expectRejected(zip, ZipRejection.linkEntry);
      }
    });

    test('Windows reparse points (junctions, symlinks)', () async {
      for (final host in [0, 10]) {
        final zip = buildZip([
          ZEntry(
            'junction/',
            [],
            madeBy: host << 8 | 20,
            attributes: 0x10 | 0x400,
          ),
        ]);
        await expectRejected(zip, ZipRejection.linkEntry);
      }
    });

    test(
      'a folder that claims to be a file, and the other way round',
      () async {
        await expectRejected(
          buildZip([
            ZEntry(
              'd',
              [],
              madeBy: unixHost | 20,
              attributes: unixMode(0x41ed),
            ),
          ]),
          ZipRejection.corrupt,
        );
        await expectRejected(
          buildZip([
            ZEntry(
              'f/',
              [],
              madeBy: unixHost | 20,
              attributes: unixMode(0x81a4),
            ),
          ]),
          ZipRejection.corrupt,
        );
      },
    );

    test('encrypted entries, other methods, zip64, several disks', () async {
      await expectRejected(
        buildZip([
          ZEntry('a', [1], flags: 1),
        ]),
        ZipRejection.unsupported,
      );
      await expectRejected(
        buildZip([
          ZEntry('a', [1], flags: 0x40),
        ]),
        ZipRejection.unsupported,
      );
      await expectRejected(
        buildZip([
          ZEntry('a', [1], method: 12, rawCompressed: [1, 2, 3]),
        ]),
        ZipRejection.unsupported,
      );
      await expectRejected(
        buildZip([
          ZEntry('a', [1], method: 99, rawCompressed: [1]),
        ]),
        ZipRejection.unsupported,
      );
      await expectRejected(
        buildZip([
          ZEntry('a', [1], compressedOverride: 0xffffffff),
        ]),
        ZipRejection.unsupported,
      );
      await expectRejected(
        buildZip([
          ZEntry('a', [1], declaredSize: 0xffffffff),
        ]),
        ZipRejection.unsupported,
      );
      await expectRejected(
        buildZip([
          ZEntry('a', [1]),
        ], zip64Locator: true),
        ZipRejection.unsupported,
      );
      await expectRejected(
        buildZip([
          ZEntry('a', [1]),
        ], diskNumber: 1),
        ZipRejection.unsupported,
      );
    });

    test('not a zip at all', () async {
      await expectRejected(Uint8List(0), ZipRejection.notAZip);
      await expectRejected(bytesOf('hello'), ZipRejection.notAZip);
      await expectRejected(
        Uint8List.fromList(List<int>.generate(5000, (i) => i * 31 & 0xff)),
        ZipRejection.notAZip,
      );
      final good = buildZip([
        ZEntry('a', [1, 2, 3]),
      ]);
      // Cut off: the end record is gone.
      await expectRejected(
        Uint8List.sublistView(good, 0, good.length - 10),
        ZipRejection.notAZip,
      );
      // Data after the end record: its comment would not end at the file end.
      await expectRejected(
        buildZip(
          [
            ZEntry('a', [1]),
          ],
          trailing: [1, 2, 3],
        ),
        ZipRejection.notAZip,
      );
    });

    test('an empty archive', () async {
      await expectRejected(buildZip([]), ZipRejection.corrupt);
    });

    test('only folders and no file', () async {
      await expectRejected(
        buildZip([ZEntry.folder('a'), ZEntry.folder('b')]),
        ZipRejection.corrupt,
      );
    });
  });

  // =========================================================================
  group('SafeZipExtractor: bombs and lies about sizes', () {
    const small = ZipLimits(
      maxFileBytes: 1000000,
      maxTotalBytes: 2000000,
      maxEntries: 20,
      maxArchiveBytes: 50000,
    );

    test('honest but huge file: refused from the directory', () async {
      // 5 MB of zeros deflate to a few KB.
      final zeros = Uint8List(5 * 1000 * 1000);
      final zip = buildZip([ZEntry('zeros.bin', zeros)]);
      expect(zip.length, lessThan(20000));

      await expectRejected(zip, ZipRejection.tooLarge, limits: small);

      expect(inside(), isEmpty);
    });

    test('many files that add up to more than the total cap', () async {
      final block = Uint8List(900000);
      final zip = buildZip([
        for (var i = 0; i < 4; i++) ZEntry('f$i.bin', block),
      ]);

      await expectRejected(zip, ZipRejection.tooLarge, limits: small);

      expect(inside(), isEmpty);
    });

    test(
      'understated size: the real data is cut off at the declared size',
      () async {
        // The directory says 100 bytes, the deflate stream holds 5 MB.
        final zeros = Uint8List(5 * 1000 * 1000);
        final zip = buildZip([ZEntry('zeros.bin', zeros, declaredSize: 100)]);

        await expectRejected(zip, ZipRejection.corrupt);

        // No more than the declared 100 bytes ever reached the disk.
        final written = File(p.join(out.path, 'zeros.bin'));
        expect(written.lengthSync(), lessThanOrEqualTo(100));
      },
    );

    test('understated size on a stored entry', () async {
      final zip = buildZip([
        ZEntry(
          'a.bin',
          Uint8List(100000),
          method: 0,
          declaredSize: 10,
          compressedOverride: 10,
        ),
      ]);

      await expectRejected(zip, ZipRejection.corrupt);
    });

    test('overstated size', () async {
      await expectRejected(
        buildZip([ZEntry('a.bin', Uint8List(1000), declaredSize: 5000)]),
        ZipRejection.corrupt,
      );
    });

    test('too many entries', () async {
      final zip = buildZip([
        for (var i = 0; i < 21; i++) ZEntry('f$i', [i]),
      ]);

      await expectRejected(zip, ZipRejection.tooManyEntries, limits: small);

      // The count in the end record is enough; the entries are not even read.
      await expectRejected(
        buildZip([
          ZEntry('a', [1]),
        ], declaredCount: 3000),
        ZipRejection.tooManyEntries,
        limits: small,
      );
    });

    test('archive larger than its cap', () async {
      final noise = Uint8List.fromList(
        List<int>.generate(60000, (i) => (i * 2654435761) >> 7 & 0xff),
      );
      final zip = buildZip([ZEntry('noise.bin', noise, method: 0)]);

      await expectRejected(zip, ZipRejection.tooLarge, limits: small);
    });

    test('overlapping entries (an entry hidden inside another)', () async {
      // The data of `a.bin` is itself a complete local record for `b.txt`,
      // and the directory points `b.txt` into it.
      final hidden = _localRecord('b.txt', bytesOf('hidden'));
      final zip = buildZip([
        ZEntry('a.bin', hidden, method: 0),
        ZEntry('b.txt', bytesOf('hidden'), method: 0, localOffset: 30 + 5),
      ]);

      await expectRejected(zip, ZipRejection.corrupt);
    });

    test('two entries sharing one local header', () async {
      final zip = buildZip([
        ZEntry('big.bin', Uint8List(800000)),
        ZEntry('copy.bin', [0], localOffset: 0),
      ]);

      // The names in the local header and in the directory must agree.
      await expectRejected(zip, ZipRejection.corrupt);
    });

    test('compressed size that runs past the directory', () async {
      await expectRejected(
        buildZip([
          ZEntry('a', [1, 2, 3], compressedOverride: 5000),
        ]),
        ZipRejection.corrupt,
      );
    });

    test('central directory at an offset outside the file', () async {
      await expectRejected(
        buildZip([
          ZEntry('a', [1]),
        ], directoryOffsetOverride: 100000),
        ZipRejection.corrupt,
      );
    });
  });

  // =========================================================================
  group('SafeZipExtractor: damaged archives', () {
    test('wrong CRC-32', () async {
      await expectRejected(
        buildZip([ZEntry('a.txt', bytesOf('hello'), crc: 0x12345678)]),
        ZipRejection.corrupt,
      );
      emptyOut();
      await expectRejected(
        buildZip([ZEntry('a.txt', bytesOf('hello'), method: 0, crc: 1)]),
        ZipRejection.corrupt,
      );
    });

    test('data flipped after compression', () async {
      final data = bytesOf('hello hello hello hello hello hello');
      final compressed = ZLibEncoder(raw: true).convert(data);
      final broken = List<int>.of(compressed)..[2] ^= 0xff;

      await expectRejected(
        buildZip([ZEntry('a.txt', data, rawCompressed: broken)]),
        ZipRejection.corrupt,
      );
    });

    test('deflate stream cut short', () async {
      final data = Uint8List.fromList(
        List<int>.generate(20000, (i) => (i * 17 + i ~/ 5) & 0xff),
      );
      final compressed = ZLibEncoder(raw: true).convert(data);
      final cut = compressed.sublist(0, compressed.length ~/ 2);

      await expectRejected(
        buildZip([ZEntry('a.bin', data, rawCompressed: cut)]),
        ZipRejection.corrupt,
      );
    });

    test('garbage instead of a deflate stream', () async {
      await expectRejected(
        buildZip([
          ZEntry(
            'a.bin',
            bytesOf('x' * 100),
            rawCompressed: List<int>.filled(40, 0xff),
          ),
        ]),
        ZipRejection.corrupt,
      );
    });

    test('local header disagrees with the directory', () async {
      await expectRejected(
        buildZip([
          ZEntry('good.txt', [1], localName: utf8.encode('evil.txt')),
        ]),
        ZipRejection.corrupt,
      );
      await expectRejected(
        buildZip([
          ZEntry('good.txt', [1], localName: utf8.encode('good.txt!')),
        ]),
        ZipRejection.corrupt,
      );
    });

    test(
      'an entry whose local header is not where the directory says',
      () async {
        await expectRejected(
          buildZip([
            ZEntry('a', [1, 2, 3]),
            ZEntry('b', [4], localOffset: 7),
          ]),
          ZipRejection.corrupt,
        );
      },
    );

    test('the target must be an empty folder', () async {
      File(p.join(out.path, 'old.txt')).writeAsStringSync('x');
      final zip = buildZip([
        ZEntry('a', [1]),
      ]);

      await expectLater(
        extract(zip),
        throwsA(
          isA<ZipException>().having(
            (e) => e.reason,
            'reason',
            ZipRejection.io,
          ),
        ),
      );
      expect(File(p.join(out.path, 'old.txt')).readAsStringSync(), 'x');
      expect(File(p.join(out.path, 'a')).existsSync(), isFalse);
    });

    test('the target must exist', () async {
      final zip = writeZip(
        buildZip([
          ZEntry('a', [1]),
        ]),
      );

      await expectLater(
        const SafeZipExtractor().extract(
          zip,
          Directory(p.join(work.path, 'missing')),
        ),
        throwsA(
          isA<ZipException>().having(
            (e) => e.reason,
            'reason',
            ZipRejection.io,
          ),
        ),
      );
    });

    test('a missing zip file is an io error, not a crash', () async {
      await expectLater(
        const SafeZipExtractor().extract(
          File(p.join(work.path, 'missing.zip')),
          out,
        ),
        throwsA(
          isA<ZipException>().having(
            (e) => e.reason,
            'reason',
            ZipRejection.io,
          ),
        ),
      );
    });

    test('exceptions carry the reason only', () {
      const e = ZipException(ZipRejection.unsafeName);
      expect(e.toString(), 'ZipException(unsafeName)');
    });
  });

  // =========================================================================
  group('WindowsUpdateInstaller', () {
    late Directory installDir;
    late Directory logDir;
    late File exe;
    late List<String> events;
    late List<StartCall> starts;
    late FakeProcess helper;

    /// The `powershell.exe` of the fake system folder every installer sees
    /// unless a test passes its own environment.
    late File systemPowerShell;

    /// What the fake PowerShell does when started: by default it plays a
    /// script that checks its arguments and writes `ready`.
    late FutureOr<void> Function(StartCall call) onStart;

    /// Replaces the starter when set (to throw).
    Object? startError;

    setUp(() {
      systemPowerShell = File(
        p.join(
          tmp.path,
          'SysRoot',
          'System32',
          'WindowsPowerShell',
          'v1.0',
          'powershell.exe',
        ),
      )..createSync(recursive: true);
      installDir = Directory(p.join(tmp.path, 'My App'))..createSync();
      exe = File(p.join(installDir.path, 'app.exe'))
        ..writeAsBytesSync([0x4d, 0x5a, 1, 2, 3]);
      logDir = Directory(p.join(tmp.path, 'temp'))..createSync();
      events = [];
      starts = [];
      helper = FakeProcess(31337);
      startError = null;
      onStart = (call) =>
          File(call.arg('-ReadyFile')).writeAsStringSync('ready');
    });

    WindowsUpdateInstaller makeInstaller({
      String? executablePath,
      bool isWindows = true,
      Map<String, String>? environment,
      int minTotalBytes = 10,
      bool requirePeHeader = true,
      SafeZipExtractor extractor = const SafeZipExtractor(),
      Duration readyTimeout = const Duration(milliseconds: 600),
    }) => WindowsUpdateInstaller(
      executablePath: executablePath ?? exe.path,
      processId: 4242,
      isWindows: isWindows,
      environment: environment ?? {'SystemRoot': p.join(tmp.path, 'SysRoot')},
      logDirectory: logDir,
      extractor: extractor,
      minTotalBytes: minTotalBytes,
      requirePeHeader: requirePeHeader,
      readyTimeout: readyTimeout,
      pollInterval: const Duration(milliseconds: 5),
      startProcess:
          (
            executable,
            arguments, {
            String? workingDirectory,
            ProcessStartMode mode = ProcessStartMode.normal,
          }) async {
            events.add('start');
            final call = StartCall(
              executable,
              List.of(arguments),
              workingDirectory,
              mode,
            );
            starts.add(call);
            final error = startError;
            if (error != null) throw error;
            await onStart(call);
            return helper;
          },
      exitProcess: (code) => events.add('exit:$code'),
    );

    Future<void> prepareExit() async => events.add('prepareExit');

    File releaseZip([List<ZEntry>? entries]) =>
        writeZip(buildZip(entries ?? releaseEntries()));

    Future<InstallOutcome> run(
      WindowsUpdateInstaller installer, [
      File? package,
    ]) => installer.install(package ?? releaseZip(), prepareExit: prepareExit);

    /// The folders and files the installer may leave next to the package.
    List<String> leftovers() =>
        work
            .listSync()
            .map((e) => p.basename(e.path))
            .where((n) => n != 'package.zip' && n != 'out' && n != 'canary.txt')
            .toList()
          ..sort();

    group('happy path', () {
      test('unpacks, locks the vault, starts the script, exits', () async {
        final installer = makeInstaller();

        final outcome = await run(installer);

        expect(outcome, InstallOutcome.started);
        expect(installer.lastError, isNull);
        // The order is the contract: lock the vault, then hand over, then go.
        expect(events, ['prepareExit', 'start', 'exit:0']);
        expect(starts, hasLength(1));
        final call = starts.single;
        expect(call.mode, ProcessStartMode.detached);
        expect(call.executable, systemPowerShell.path);
        expect(call.workingDirectory, logDir.path);
        expect(call.arguments, [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          p.join(work.path, 'apply_update.ps1'),
          '-InstallDir',
          installDir.path,
          '-StagingDir',
          p.join(work.path, 'stage'),
          '-ExeName',
          'app.exe',
          '-ProcessId',
          '4242',
          '-BackupDir',
          p.join(work.path, 'backup'),
          '-ReadyFile',
          p.join(work.path, 'ready'),
          '-LogFile',
          p.join(logDir.path, 'update-helper.log'),
        ]);
        // Everything the script needs is in place and stays there.
        final stage = Directory(p.join(work.path, 'stage'));
        expect(File(p.join(stage.path, 'app.exe')).existsSync(), isTrue);
        expect(
          File(p.join(stage.path, 'flutter_windows.dll')).existsSync(),
          isTrue,
        );
        expect(Directory(p.join(stage.path, 'data')).existsSync(), isTrue);
        expect(
          File(p.join(work.path, 'apply_update.ps1')).readAsStringSync(),
          windowsApplyUpdateScript,
        );
        // The package is left to the controller.
        expect(File(p.join(work.path, 'package.zip')).existsSync(), isTrue);
        // The probe file is gone and the install folder is untouched.
        expect(installDir.listSync().map((e) => p.basename(e.path)), [
          'app.exe',
        ]);
        expect(exe.readAsBytesSync(), [0x4d, 0x5a, 1, 2, 3]);
      });

      test('a release zipped as one top folder is accepted', () async {
        final installer = makeInstaller();

        final outcome = await run(
          installer,
          releaseZip(releaseEntries(prefix: 'Release')),
        );

        expect(outcome, InstallOutcome.started);
        // The script gets the folder that holds the exe.
        expect(
          starts.single.arg('-StagingDir'),
          p.join(work.path, 'stage', 'Release'),
        );
        expect(
          File(p.join(starts.single.arg('-StagingDir'), 'app.exe'))
              .existsSync(),
          isTrue,
        );
      });

      test('the exe name matches without regard to letter case', () async {
        final installer = makeInstaller();

        final outcome = await run(
          installer,
          releaseZip(releaseEntries(exe: 'APP.EXE')),
        );

        expect(outcome, InstallOutcome.started);
        // The script is given the installed spelling.
        expect(starts.single.arg('-ExeName'), 'app.exe');
      });

      test('paths with spaces, quotes, & ; \$ and non-ASCII stay one argument each', () async {
        final odd = Directory(
          p.join(tmp.path, "Mein App \u00e9\u0627 & ;\$x 'q' (1) [b]"),
        )..createSync();
        final oddExe = File(p.join(odd.path, 'My Prog \$1.exe'))
          ..writeAsBytesSync([0x4d, 0x5a]);
        final installer = makeInstaller(executablePath: oddExe.path);

        final outcome = await run(
          installer,
          releaseZip(releaseEntries(exe: 'My Prog \$1.exe')),
        );

        expect(outcome, InstallOutcome.started);
        final args = starts.single.arguments;
        expect(args[args.indexOf('-InstallDir') + 1], odd.path);
        expect(args[args.indexOf('-ExeName') + 1], 'My Prog \$1.exe');
        // No element is ever glued to another or quoted by us.
        for (final a in args) {
          expect(a.startsWith('"'), isFalse);
          expect(a.endsWith(r'\'), isFalse);
        }
        expect(
          args.where((a) => a == odd.path),
          hasLength(1),
          reason: 'one list element, not part of a command string',
        );
      });

      test('uses the system PowerShell when it is there', () async {
        final root = Directory(p.join(tmp.path, 'Windows'))..createSync();
        final ps = File(
          p.join(
            root.path,
            'System32',
            'WindowsPowerShell',
            'v1.0',
            'powershell.exe',
          ),
        )..createSync(recursive: true);
        final installer = makeInstaller(environment: {'SystemRoot': root.path});

        await run(installer);

        expect(starts.single.executable, ps.path);
      });

      test('uses windir when SystemRoot is not set', () async {
        final installer = makeInstaller(
          environment: {'windir': p.join(tmp.path, 'SysRoot')},
        );

        await run(installer);

        expect(starts.single.executable, systemPowerShell.path);
      });

      // A bare `powershell.exe` would be looked up in the app's own folder
      // first, which the user can write to: no fallback to it, ever.
      final noSystemPowerShell = <String, Map<String, String> Function()>{
        'the system folder has no PowerShell': () => {
          'SystemRoot': p.join(tmp.path, 'nowhere'),
        },
        'SystemRoot and windir are not set': () => {},
        'SystemRoot is empty': () => {'SystemRoot': ''},
      };
      for (final entry in noSystemPowerShell.entries) {
        test('refused without touching anything when ${entry.key}', () async {
          // The planted file a bare name would have found.
          File(p.join(installDir.path, 'powershell.exe')).writeAsBytesSync([1]);
          final installer = makeInstaller(environment: entry.value());

          final outcome = await run(installer);

          expect(outcome, InstallOutcome.failed);
          expect(installer.lastError, WindowsInstallError.helperUnavailable);
          // Nothing started, and the vault was not locked for nothing.
          expect(events, isEmpty);
          expect(starts, isEmpty);
          expect(leftovers(), isEmpty);
          expect(File(p.join(work.path, 'package.zip')).existsSync(), isTrue);
        });
      }

      test('the script waits for the right process id', () async {
        final installer = WindowsUpdateInstaller(
          executablePath: exe.path,
          isWindows: true,
          environment: {'SystemRoot': p.join(tmp.path, 'SysRoot')},
          logDirectory: logDir,
          minTotalBytes: 10,
          pollInterval: const Duration(milliseconds: 5),
          startProcess:
              (
                executable,
                arguments, {
                String? workingDirectory,
                ProcessStartMode mode = ProcessStartMode.normal,
              }) async {
                starts.add(
                  StartCall(executable, arguments, workingDirectory, mode),
                );
                File(starts.last.arg('-ReadyFile')).writeAsStringSync('ready');
                return helper;
              },
          exitProcess: (code) {},
        );

        await run(installer);

        // The default is this very process.
        expect(starts.single.arg('-ProcessId'), pid.toString());
      });
    });

    group('refusals before anything happens', () {
      test('not on Windows', () async {
        final installer = makeInstaller(isWindows: false);

        final outcome = await run(installer);

        expect(outcome, InstallOutcome.unsupported);
        expect(events, isEmpty);
        expect(leftovers(), isEmpty);
      });

      test('a network (UNC) install folder', () async {
        for (final path in [
          r'\\server\share\App\app.exe',
          '//server/share/App/app.exe',
          r'\\?\C:\Apps\app.exe',
        ]) {
          final installer = makeInstaller(executablePath: path);

          final outcome = await run(installer);

          expect(outcome, InstallOutcome.failed);
          expect(installer.lastError, WindowsInstallError.unsupportedLocation);
          expect(events, isEmpty, reason: 'no lock, no process');
        }
        expect(leftovers(), isEmpty);
      });

      test('a program that is not an exe, or a drive root', () async {
        for (final path in [
          p.join(installDir.path, 'app'),
          p.join(installDir.path, '.exe'),
          'app.exe',
          '/app.exe',
        ]) {
          final installer = makeInstaller(executablePath: path);

          final outcome = await run(installer);

          expect(outcome, InstallOutcome.failed);
          expect(installer.lastError, WindowsInstallError.unsupportedLocation);
          expect(events, isEmpty);
        }
      });

      test('an install folder that cannot be written', () async {
        // The folder is gone, which fails the same way a read-only one does
        // (permission bits do not stop the superuser in test environments).
        final gone = p.join(tmp.path, 'Program Files', 'App', 'app.exe');
        final installer = makeInstaller(executablePath: gone);

        final outcome = await run(installer);

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, WindowsInstallError.notWritable);
        expect(events, isEmpty, reason: 'the vault is not locked for nothing');
        expect(leftovers(), isEmpty, reason: 'nothing was unpacked either');
      });

      test('the probe file is removed again', () async {
        await run(makeInstaller());

        expect(installDir.listSync().map((e) => p.basename(e.path)), [
          'app.exe',
        ]);
      });

      test('a second call while one is running', () async {
        final gate = Completer<void>();
        onStart = (call) async {
          await gate.future;
          File(call.arg('-ReadyFile')).writeAsStringSync('ready');
        };
        final installer = makeInstaller(
          readyTimeout: const Duration(seconds: 5),
        );

        final first = run(installer);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final second = await installer.install(
          releaseZip(),
          prepareExit: prepareExit,
        );
        gate.complete();
        await first;

        expect(second, InstallOutcome.failed);
        expect(events.where((e) => e == 'start'), hasLength(1));
      });
    });

    group('a package that is not acceptable', () {
      test('not a zip', () async {
        final installer = makeInstaller();

        final outcome = await run(installer, writeZip(bytesOf('not a zip')));

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, WindowsInstallError.badPackage);
        expect(installer.lastZipRejection, ZipRejection.notAZip);
        expect(events, isEmpty, reason: 'the vault stays unlocked');
        expect(leftovers(), isEmpty);
        expect(File(p.join(work.path, 'package.zip')).existsSync(), isTrue);
      });

      test('a zip with a zip-slip name', () async {
        final installer = makeInstaller();

        final outcome = await run(
          installer,
          releaseZip([
            ...releaseEntries(),
            ZEntry('../escape.txt', [1]),
          ]),
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastZipRejection, ZipRejection.unsafeName);
        expect(events, isEmpty);
        expect(File(p.join(tmp.path, 'escape.txt')).existsSync(), isFalse);
        expect(File(p.join(work.path, 'escape.txt')).existsSync(), isFalse);
        expect(leftovers(), isEmpty);
      });

      test('a zip with a symbolic link', () async {
        final installer = makeInstaller();

        final outcome = await run(
          installer,
          releaseZip([
            ...releaseEntries(),
            ZEntry(
              'data/link',
              bytesOf('/etc'),
              madeBy: unixHost | 20,
              attributes: unixMode(0xa1ff),
            ),
          ]),
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastZipRejection, ZipRejection.linkEntry);
        expect(events, isEmpty);
      });

      test('a damaged zip leaves nothing behind', () async {
        final installer = makeInstaller();

        final outcome = await run(
          installer,
          releaseZip([
            ...releaseEntries(),
            ZEntry('data/late.bin', bytesOf('x' * 100), crc: 5),
          ]),
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastZipRejection, ZipRejection.corrupt);
        // The files written before the bad one are removed with the stage.
        expect(leftovers(), isEmpty);
        expect(events, isEmpty);
      });

      test('a bomb is refused by the installer limits', () async {
        final installer = makeInstaller(
          extractor: const SafeZipExtractor(
            limits: ZipLimits(maxFileBytes: 100000),
          ),
        );

        final outcome = await run(
          installer,
          releaseZip([
            ...releaseEntries(),
            ZEntry('data/zeros.bin', Uint8List(5 * 1000 * 1000)),
          ]),
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastZipRejection, ZipRejection.tooLarge);
        expect(leftovers(), isEmpty);
      });

      test('the exe is missing, or named differently', () async {
        for (final entries in [
          releaseEntries(exe: 'other.exe'),
          releaseEntries(exe: 'app.exe.bak'),
          releaseEntries(prefix: 'a/b'),
        ]) {
          final installer = makeInstaller();

          final outcome = await run(installer, releaseZip(entries));

          expect(outcome, InstallOutcome.failed);
          expect(installer.lastError, WindowsInstallError.badLayout);
          expect(events, isEmpty);
          expect(leftovers(), isEmpty);
        }
      });

      test('no engine dll, no data folder', () async {
        for (final entries in [
          releaseEntries(engine: false),
          releaseEntries(data: false),
        ]) {
          final installer = makeInstaller();

          final outcome = await run(installer, releaseZip(entries));

          expect(outcome, InstallOutcome.failed);
          expect(installer.lastError, WindowsInstallError.badLayout);
          expect(leftovers(), isEmpty);
        }
      });

      test('an exe that is not a Windows program', () async {
        final installer = makeInstaller();

        final outcome = await run(
          installer,
          releaseZip(releaseEntries(exeBytes: bytesOf('#!/bin/sh'))),
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, WindowsInstallError.badLayout);
      });

      test('the header check can be switched off for tests', () async {
        final installer = makeInstaller(requirePeHeader: false);

        final outcome = await run(
          installer,
          releaseZip(releaseEntries(exeBytes: bytesOf('plain'))),
        );

        expect(outcome, InstallOutcome.started);
      });

      test('a total size that is not a release', () async {
        final installer = makeInstaller(minTotalBytes: 1024 * 1024);

        final outcome = await run(installer);

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, WindowsInstallError.badLayout);
        expect(events, isEmpty);
      });

      test(
        'a link inside the staging folder is refused',
        skip: Platform.isWindows ? 'creating links needs special rights' : null,
        () async {
          // Something other than the extractor drops a link into the stage.
          final installer = makeInstaller(
            extractor: _PlantingExtractor((stage) {
              Link(p.join(stage.path, 'data', 'sneaky')).createSync('/etc');
            }),
          );

          final outcome = await run(installer);

          expect(outcome, InstallOutcome.failed);
          expect(installer.lastError, WindowsInstallError.badLayout);
          expect(events, isEmpty);
          expect(leftovers(), isEmpty);
          expect(
            Link(p.join(work.path, 'stage', 'data', 'sneaky')).existsSync(),
            isFalse,
          );
        },
      );
    });

    group('hand-over', () {
      test('a vault that cannot be locked: nothing is started', () async {
        final installer = makeInstaller();

        final outcome = await installer.install(
          releaseZip(),
          prepareExit: () async {
            events.add('prepareExit');
            throw StateError('secret text that must not surface');
          },
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, WindowsInstallError.prepareExitFailed);
        expect(events, ['prepareExit']);
        expect(starts, isEmpty);
        expect(leftovers(), isEmpty);
      });

      test('PowerShell cannot be started', () async {
        startError = const ProcessException('powershell.exe', [], 'nope', 2);
        final installer = makeInstaller();

        final outcome = await run(installer);

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, WindowsInstallError.helperUnavailable);
        expect(events, ['prepareExit', 'start']);
        expect(leftovers(), isEmpty, reason: 'script and stage are removed');
        expect(File(p.join(work.path, 'package.zip')).existsSync(), isTrue);
      });

      test('the script never reports back (policy, antivirus)', () async {
        onStart = (call) {};
        final installer = makeInstaller();

        final outcome = await run(installer);

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, WindowsInstallError.helperNotReady);
        // The app keeps running: no exit, and the helper is stopped.
        expect(events, ['prepareExit', 'start']);
        expect(helper.killed, isTrue);
        expect(leftovers(), isEmpty);
      });

      test('the script finds a problem and says so at once', () async {
        onStart = (call) =>
            File(call.arg('-ReadyFile'))
                .writeAsStringSync('abort staged-exe-missing');
        final installer = makeInstaller(
          readyTimeout: const Duration(seconds: 30),
        );
        final watch = Stopwatch()..start();

        final outcome = await run(installer);

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, WindowsInstallError.helperNotReady);
        expect(
          watch.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason: 'not the whole timeout',
        );
        expect(events, ['prepareExit', 'start']);
        expect(helper.killed, isTrue);
      });

      test('a ready file that is still being written is not enough', () async {
        onStart = (call) {
          final f = File(call.arg('-ReadyFile'))..writeAsStringSync('rea');
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 60),
              () => f.writeAsStringSync('ready'),
            ),
          );
        };
        final installer = makeInstaller();

        final outcome = await run(installer);

        expect(outcome, InstallOutcome.started);
      });

      test('a stale ready file from an earlier run does not count', () async {
        File(p.join(work.path, 'ready')).writeAsStringSync('ready');
        onStart = (call) {};
        final installer = makeInstaller();

        final outcome = await run(installer);

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, WindowsInstallError.helperNotReady);
      });

      test('the controller can retry after a failure', () async {
        onStart = (call) {};
        final installer = makeInstaller();
        await run(installer);
        expect(installer.lastError, WindowsInstallError.helperNotReady);

        onStart = (call) =>
            File(call.arg('-ReadyFile')).writeAsStringSync('ready');
        final outcome = await run(installer);

        expect(outcome, InstallOutcome.started);
        expect(installer.lastError, isNull);
      });

      test('errors never carry text from the system', () async {
        startError = StateError('C:\\Users\\private\\secret');
        final installer = makeInstaller();

        await run(installer);

        expect(installer.lastError.toString(), isNot(contains('private')));
        expect(installer.lastError, WindowsInstallError.helperUnavailable);
      });
    });

    group('readHelperResult', () {
      File log() => File(p.join(logDir.path, 'update-helper.log'));

      Future<WindowsUpdateHelperResult> read({bool deleteLog = true}) =>
          WindowsUpdateInstaller.readHelperResult(
            logDirectory: logDir,
            deleteLog: deleteLog,
          );

      test('no log', () async {
        expect(await read(), WindowsUpdateHelperResult.none);
      });

      test('every result token, and the log is consumed', () async {
        const lines = {
          'RESULT success': WindowsUpdateHelperResult.succeeded,
          'RESULT rolled-back copy-failed':
              WindowsUpdateHelperResult.rolledBack,
          'RESULT rollback-failed verify-hash':
              WindowsUpdateHelperResult.rollbackFailed,
          'RESULT aborted app-did-not-exit': WindowsUpdateHelperResult.aborted,
          'RESULT something-new': WindowsUpdateHelperResult.none,
        };
        for (final entry in lines.entries) {
          log().writeAsStringSync(
            '2026-10-07 09:00:00 start\n'
            '2026-10-07 09:00:01 ${entry.key}\n',
          );

          expect(await read(), entry.value, reason: entry.key);
          expect(log().existsSync(), isFalse, reason: 'shown once');
        }
      });

      test('can leave the log in place', () async {
        log().writeAsStringSync('2026-10-07 09:00:01 RESULT success\n');

        expect(
          await read(deleteLog: false),
          WindowsUpdateHelperResult.succeeded,
        );

        expect(log().existsSync(), isTrue);
      });

      test('a log that is cut off or oversized is ignored', () async {
        log().writeAsStringSync('2026-10-07 09:00:00 start\n');
        expect(await read(), WindowsUpdateHelperResult.none);

        log().writeAsStringSync('x' * (70 * 1024));
        expect(await read(), WindowsUpdateHelperResult.none);
      });
    });
  });

  // =========================================================================
  group('the swap script', () {
    late String script;

    setUp(() {
      script = File('tool/windows_update_helper/apply_update.ps1')
          .readAsStringSync();
    });

    test('the copy inside windows_installer.dart is identical', () {
      expect(
        windowsApplyUpdateScript,
        script,
        reason:
            'run: python3 tool/windows_update_helper/embed_script.py '
            '(it rewrites the constant from the .ps1 file)',
      );
    });

    test(
      'ASCII only, LF line ends (PowerShell 5.1 reads ANSI without BOM)',
      () {
        final bytes = File('tool/windows_update_helper/apply_update.ps1')
            .readAsBytesSync();
        expect(bytes.where((b) => b > 127 || b == 13), isEmpty);
        expect(bytes.last, 10);
        expect(script.contains("'''"), isFalse);
      },
    );

    test('safe habits', () {
      expect(script, contains('Set-StrictMode -Version 2.0'));
      expect(script, contains(r"$ErrorActionPreference = 'Stop'"));
      // No evaluation of strings, no network, no downloads.
      final lower = script.toLowerCase();
      for (final banned in [
        'invoke-expression',
        'iex ',
        'invoke-webrequest',
        'invoke-restmethod',
        'webclient',
        'start-bitstransfer',
        'curl',
        'wget',
        'system.net',
        'downloadstring',
        'downloadfile',
        'add-type',
        'encodedcommand',
        'frombase64',
      ]) {
        expect(lower.contains(banned), isFalse, reason: banned);
      }
    });

    test('copies without deleting anything of the user', () {
      expect(script, contains('/E /IS /IT /R:2 /W:1'));
      for (final banned in ['/PURGE', '/MIR', '/MOV', '/MOVE', '/XO /PURGE']) {
        expect(script.contains(banned), isFalse, reason: banned);
      }
      // The only deletion is the clean-up of the two private folders after a
      // successful update.
      expect(
        RegExp('Remove-Item').allMatches(script).length,
        1,
        reason: 'one clean-up site',
      );
      expect(
        script,
        contains(r'Remove-Item -LiteralPath $folder -Recurse -Force'),
      );
      expect(
        script,
        contains(r'foreach ($folder in @($stagingFull, $backupFull))'),
      );
      expect(script.contains('[System.IO.File]::Delete'), isFalse);
      expect(script.contains('[System.IO.Directory]::Delete'), isFalse);
    });

    test('takes exactly the parameters the installer passes', () {
      final names = RegExp(r'\[(?:string|int)\]\$(\w+)')
          .allMatches(script.substring(0, script.indexOf('Set-StrictMode')))
          .map((m) => m.group(1)!)
          .toSet();
      final args = WindowsUpdateInstaller.buildArguments(
        scriptPath: 's',
        installDir: 'i',
        stagingDir: 'g',
        exeName: 'e',
        processId: 1,
        backupDir: 'b',
        readyFile: 'r',
        logFile: 'l',
      );
      final passed = args
          .where((a) => a.startsWith('-') && a.length > 2)
          .map((a) => a.substring(1))
          .toSet();
      // The first group of flags belongs to PowerShell itself.
      const powerShellFlags = {
        'NoProfile',
        'NonInteractive',
        'ExecutionPolicy',
        'WindowStyle',
        'File',
      };
      expect(passed.difference(powerShellFlags), {
        'InstallDir',
        'StagingDir',
        'ExeName',
        'ProcessId',
        'BackupDir',
        'ReadyFile',
        'LogFile',
      });
      expect(
        names,
        containsAll(passed.difference(powerShellFlags)),
        reason: 'every passed parameter is declared by the script',
      );
    });
  });

  // =========================================================================
  group(
    'the swap script under PowerShell 7',
    skip: pwsh == null ? 'pwsh is not installed' : null,
    () {
      test('parses, and uses nothing that Windows PowerShell 5.1 lacks', () {
        final checker = File(p.join(tmp.path, 'check.ps1'))
          ..writeAsStringSync(_astCheck);

        final r = Process.runSync(pwsh!, [
          '-NoProfile',
          '-NonInteractive',
          '-File',
          checker.path,
          p.absolute('tool/windows_update_helper/apply_update.ps1'),
        ]);

        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        final lines = r.stdout
            .toString()
            .trim()
            .split('\n')
            .map((l) => l.trim());
        expect(lines, containsAll(['parse errors: 0', 'newer syntax: 0']));
      });
    },
  );

  group(
    'the swap script run against a fake install',
    skip: pwsh == null
        ? 'pwsh is not installed'
        : Platform.isWindows
        ? 'uses a stand-in for robocopy (a shell script)'
        : null,
    () {
      late Directory bin;
      late Directory base;
      late String sleepPath;

      setUp(() {
        base = Directory(p.join(tmp.path, 'e2e'))..createSync();
        bin = Directory(p.join(base.path, 'bin'))..createSync();
        // Stand-in for robocopy. First FAKE_ROBOCOPY_FAILS calls copy one file
        // and fail with 8; every later call copies everything and returns 1.
        final shim = File(p.join(bin.path, 'robocopy.exe'))
          ..writeAsStringSync(r'''#!/bin/sh
counter="$FAKE_ROBOCOPY_COUNTER"
n=0
[ -f "$counter" ] && n=$(cat "$counter")
n=$((n+1))
echo $n > "$counter"
if [ "$n" -le "${FAKE_ROBOCOPY_FAILS:-0}" ]; then
  f=$(cd "$1" && find . -type f | sort | head -n 1)
  mkdir -p "$(dirname "$2/$f")"
  cp "$1/$f" "$2/$f"
  exit 8
fi
cp -R "$1"/. "$2"/ && exit 1
exit 16
''');
        Process.runSync('chmod', ['+x', shim.path]);
        sleepPath = [
          '/bin/sleep',
          '/usr/bin/sleep',
        ].firstWhere((f) => File(f).existsSync(), orElse: () => '');
      });

      /// An install or staging folder; `app.exe` is a script that records
      /// which version was started.
      Directory tree(String path, String version, File launchLog) {
        final dir = Directory(path)..createSync(recursive: true);
        final appExe = File(p.join(dir.path, 'app.exe'))
          ..writeAsStringSync(
            '#!/bin/sh\necho "$version" >> "${launchLog.path}"\n',
          );
        Process.runSync('chmod', ['+x', appExe.path]);
        File(p.join(dir.path, 'flutter_windows.dll'))
            .writeAsStringSync('engine-$version');
        Directory(p.join(dir.path, 'data', 'flutter_assets'))
            .createSync(recursive: true);
        File(p.join(dir.path, 'data', 'app.so'))
            .writeAsStringSync('aot-$version');
        File(p.join(dir.path, 'data', 'flutter_assets', 'a.bin'))
            .writeAsStringSync('asset-$version');
        return dir;
      }

      Future<_E2eResult> runScript({
        String installName = 'My App \u00e9 & \$x [b] (1)',
        int fails = 0,
        bool dropStagedExe = false,
        int waitSeconds = 30,
        Future<int> Function(Directory install)? startHostApp,
        void Function(Directory install)? prepareInstall,
      }) async {
        final launches = File(p.join(base.path, 'launches.log'));
        final install = tree(p.join(base.path, installName), 'OLD', launches);
        final stage = tree(p.join(base.path, 'w', 'stage'), 'NEW', launches);
        final backup = Directory(p.join(base.path, 'w', 'backup'));
        final ready = File(p.join(base.path, 'w', 'ready'));
        final log = File(p.join(base.path, 'update-helper.log'));
        if (dropStagedExe) File(p.join(stage.path, 'app.exe')).deleteSync();
        prepareInstall?.call(install);

        final hostPid = startHostApp != null
            ? await startHostApp(install)
            : await (() async {
                final done = await Process.start('true', []);
                await done.exitCode;
                return done.pid;
              })();

        final r = await Process.run(
          pwsh!,
          [
            '-NoProfile',
            '-NonInteractive',
            '-File',
            p.absolute('tool/windows_update_helper/apply_update.ps1'),
            '-InstallDir',
            install.path,
            '-StagingDir',
            stage.path,
            '-ExeName',
            'app.exe',
            '-ProcessId',
            '$hostPid',
            '-BackupDir',
            backup.path,
            '-ReadyFile',
            ready.path,
            '-LogFile',
            log.path,
            '-WaitSeconds',
            '$waitSeconds',
          ],
          environment: {
            'PATH': '${bin.path}:${Platform.environment['PATH']}',
            'FAKE_ROBOCOPY_COUNTER': p.join(base.path, 'counter'),
            'FAKE_ROBOCOPY_FAILS': '$fails',
            'DOTNET_SYSTEM_GLOBALIZATION_INVARIANT': '1',
          },
        );
        // The relaunched app is a shell script that appends one line.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return _E2eResult(
          exitCode: r.exitCode,
          output: '${r.stdout}${r.stderr}',
          install: install,
          stage: stage,
          backup: backup,
          ready: ready,
          log: log,
          launches: launches,
        );
      }

      String read(Directory dir, String rel) =>
          File(p.join(dir.path, rel)).readAsStringSync();

      test(
        'updates, keeps the user\'s own files, starts the new version',
        () async {
          final r = await runScript(
            prepareInstall: (install) {
              File(p.join(install.path, 'my notes.txt'))
                  .writeAsStringSync('mine');
              File(p.join(install.path, 'data', 'old_only.dat'))
                  .writeAsStringSync('o');
            },
          );

          expect(r.exitCode, 0, reason: r.output);
          expect(read(r.install, 'data/app.so'), 'aot-NEW');
          expect(read(r.install, 'flutter_windows.dll'), 'engine-NEW');
          expect(read(r.install, 'data/flutter_assets/a.bin'), 'asset-NEW');
          expect(read(r.install, 'my notes.txt'), 'mine');
          expect(read(r.install, 'data/old_only.dat'), 'o');
          expect(r.launches.readAsLinesSync(), ['NEW']);
          expect(r.stage.existsSync(), isFalse);
          expect(r.backup.existsSync(), isFalse);
          expect(r.ready.readAsStringSync(), 'ready');
          final logText = r.log.readAsStringSync();
          expect(logText, contains('RESULT success'));
          // The log has no path in it.
          expect(logText, isNot(contains(r.install.path)));
          expect(logText, isNot(contains('My App')));
          expect(
            await WindowsUpdateInstaller.readHelperResult(
              logDirectory: r.log.parent,
            ),
            WindowsUpdateHelperResult.succeeded,
          );
        },
      );

      test('a failed copy is rolled back and the old version starts', () async {
        final r = await runScript(fails: 3);

        expect(r.exitCode, 20, reason: r.output);
        expect(read(r.install, 'data/app.so'), 'aot-OLD');
        expect(read(r.install, 'flutter_windows.dll'), 'engine-OLD');
        expect(read(r.install, 'app.exe'), contains('OLD'));
        expect(r.launches.readAsLinesSync(), ['OLD']);
        expect(
          await WindowsUpdateInstaller.readHelperResult(
            logDirectory: r.log.parent,
          ),
          WindowsUpdateHelperResult.rolledBack,
        );
      });

      test('a copy that fails once is retried', () async {
        final r = await runScript(fails: 1);

        expect(r.exitCode, 0, reason: r.output);
        expect(read(r.install, 'data/app.so'), 'aot-NEW');
        expect(r.launches.readAsLinesSync(), ['NEW']);
      });

      test(
        'a staging folder without the exe changes nothing and says so',
        () async {
          final r = await runScript(dropStagedExe: true);

          expect(r.exitCode, 11, reason: r.output);
          expect(r.ready.readAsStringSync(), startsWith('abort'));
          expect(read(r.install, 'data/app.so'), 'aot-OLD');
          expect(
            r.launches.existsSync(),
            isFalse,
            reason: 'app was never closed',
          );
          expect(
            await WindowsUpdateInstaller.readHelperResult(
              logDirectory: r.log.parent,
            ),
            WindowsUpdateHelperResult.aborted,
          );
        },
      );

      test('waits for the app to exit first', () async {
        if (sleepPath.isEmpty) return;
        late Process app;
        final r = await runScript(
          startHostApp: (install) async {
            // A running program with the app's name, from the install folder.
            final copy = File(p.join(base.path, 'host', 'app.exe'));
            copy.parent.createSync(recursive: true);
            File(sleepPath).copySync(copy.path);
            app = await Process.start(copy.path, ['3']);
            unawaited(app.exitCode);
            return app.pid;
          },
        );

        expect(r.exitCode, 0, reason: r.output);
        expect(read(r.install, 'data/app.so'), 'aot-NEW');
      });

      test(
        'does nothing when the app has taken its go-ahead back meanwhile',
        () async {
          if (sleepPath.isEmpty) return;
          final goAhead = File(p.join(base.path, 'w', 'ready'));
          final r = await runScript(
            startHostApp: (install) async {
              final copy = File(p.join(base.path, 'host', 'app.exe'));
              copy.parent.createSync(recursive: true);
              File(sleepPath).copySync(copy.path);
              final app = await Process.start(copy.path, ['120']);
              unawaited(app.exitCode);
              // The installer gave up: it deletes the ready file once the
              // script has written it, and the app then ends by itself later.
              unawaited(() async {
                for (var i = 0; i < 800 && !goAhead.existsSync(); i++) {
                  await Future<void>.delayed(const Duration(milliseconds: 25));
                }
                goAhead.deleteSync();
                await Future<void>.delayed(const Duration(milliseconds: 300));
                app.kill();
              }());
              return app.pid;
            },
          );

          expect(r.exitCode, 12, reason: r.output);
          expect(read(r.install, 'data/app.so'), 'aot-OLD');
          expect(read(r.install, 'flutter_windows.dll'), 'engine-OLD');
          expect(r.backup.existsSync(), isFalse, reason: 'nothing was copied');
          expect(
            r.launches.existsSync(),
            isFalse,
            reason: 'no program is started behind the user\'s back',
          );
          expect(
            r.log.readAsStringSync(),
            contains('RESULT aborted cancelled'),
          );
        },
      );

      test(
        'gives up when the app does not exit, and leaves everything alone',
        () async {
          if (sleepPath.isEmpty) return;
          late Process app;
          final r = await runScript(
            waitSeconds: 2,
            startHostApp: (install) async {
              final copy = File(p.join(base.path, 'host', 'app.exe'));
              copy.parent.createSync(recursive: true);
              File(sleepPath).copySync(copy.path);
              app = await Process.start(copy.path, ['30']);
              unawaited(app.exitCode);
              return app.pid;
            },
          );
          app.kill();

          expect(r.exitCode, 10, reason: r.output);
          expect(read(r.install, 'data/app.so'), 'aot-OLD');
          // A program is still running: no second copy is started.
          expect(r.launches.existsSync(), isFalse);
        },
      );

      test(
        'refuses a network path and a staging folder inside the install',
        () async {
          final launches = File(p.join(base.path, 'launches.log'));
          final install = tree(p.join(base.path, 'inst'), 'OLD', launches);
          tree(p.join(base.path, 'w', 'stage'), 'NEW', launches);
          Future<int> code(String installDir, String stagingDir) async {
            final r = await Process.run(
              pwsh!,
              [
                '-NoProfile',
                '-NonInteractive',
                '-File',
                p.absolute('tool/windows_update_helper/apply_update.ps1'),
                '-InstallDir',
                installDir,
                '-StagingDir',
                stagingDir,
                '-ExeName',
                'app.exe',
                '-ProcessId',
                '1',
                '-BackupDir',
                p.join(base.path, 'w', 'backup'),
                '-LogFile',
                p.join(base.path, 'x.log'),
              ],
              environment: {
                'PATH': '${bin.path}:${Platform.environment['PATH']}',
                'DOTNET_SYSTEM_GLOBALIZATION_INVARIANT': '1',
              },
            );
            return r.exitCode;
          }

          expect(
            await code(r'\\server\share\app', p.join(base.path, 'w', 'stage')),
            2,
          );
          expect(await code(install.path, p.join(install.path, 'data')), 2);
          expect(await code(install.path, install.path), 2);
          expect(read(install, 'data/app.so'), 'aot-OLD');
        },
      );
    },
  );
}

class _E2eResult {
  _E2eResult({
    required this.exitCode,
    required this.output,
    required this.install,
    required this.stage,
    required this.backup,
    required this.ready,
    required this.log,
    required this.launches,
  });

  final int exitCode;
  final String output;
  final Directory install;
  final Directory stage;
  final Directory backup;
  final File ready;
  final File log;
  final File launches;
}

/// Writes the files a zip would, then plants one more thing.
class _PlantingExtractor extends SafeZipExtractor {
  const _PlantingExtractor(this.plant);

  final void Function(Directory stage) plant;

  @override
  Future<ZipExtraction> extract(File zip, Directory target) async {
    final result = await super.extract(zip, target);
    plant(target);
    return result;
  }
}

/// PowerShell that reports parse errors and syntax newer than Windows
/// PowerShell 5.1 (ternary, pipeline chains, null-conditional access, `::new`).
const String _astCheck = r'''
param([string]$Path)
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
'parse errors: ' + @($errors).Count
$newer = 0
$names = @('TernaryExpressionAst', 'PipelineChainAst', 'NullConditionalMemberAccessAst', 'NullConditionalIndexExpressionAst')
$nodes = $ast.FindAll({ param($n) $names -contains $n.GetType().Name }, $true)
$newer += @($nodes).Count
$kinds = @('QuestionQuestion', 'QuestionQuestionEquals', 'QuestionDot', 'QuestionLBracket', 'AndAnd', 'OrOr')
$newer += @($tokens | Where-Object { $kinds -contains [string]$_.Kind }).Count
$calls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'new' }, $true)
$newer += @($calls).Count
'newer syntax: ' + $newer
''';

const String _pythonPlainZip =
    'UEsDBBQAAAAIAHdOR11XdX6MBwAAAGYAAAAHAAAAYXBwLmV4ZfONYqADAABQSwMEFAAAAAgAd05HXQAAAAACAAAAAAAAAAUAAABkYXRhLwMAUEsDBBQAAAAIAHdOR11Q2yqrFQAAANACAAAOAAAAZGF0YS9oZWxsby50eHTLSM3JyVfIwEdy4ZUdVTOqZhCpAQBQSwMEFAAACAAAAAAhAGC0sdMHAAAABwAAABMAAABkYXRhL2NhZsOpINin2YQudHh0dW5pY29kZVBLAwQUAAAAAAAAACEAc4wFKQABAAAAAQAACgAAAHN0b3JlZC5iaW4AAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8wMTIzNDU2Nzg5Ojs8PT4/QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl9gYWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXp7fH1+f4CBgoOEhYaHiImKi4yNjo+QkZKTlJWWl5iZmpucnZ6foKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vr/AwcLDxMXGx8jJysvMzc7P0NHS09TV1tfY2drb3N3e3+Dh4uPk5ebn6Onq6+zt7u/w8fLz9PX29/j5+vv8/f7/UEsBAhQDFAAAAAgAd05HXVd1fowHAAAAZgAAAAcAAAAAAAAAAAAAAIABAAAAAGFwcC5leGVQSwECFAMUAAAACAB3TkddAAAAAAIAAAAAAAAABQAAAAAAAAAAABAA/UEsAAAAZGF0YS9QSwECFAMUAAAACAB3TkddUNsqqxUAAADQAgAADgAAAAAAAAAAAAAAgAFRAAAAZGF0YS9oZWxsby50eHRQSwECFAMUAAAIAAAAACEAYLSx0wcAAAAHAAAAEwAAAAAAAAAAAAAAgAGSAAAAZGF0YS9jYWbDqSDYp9mELnR4dFBLAQIUAxQAAAAAAAAAIQBzjAUpAAEAAAABAAAKAAAAAAAAAAAAAACAAcoAAABzdG9yZWQuYmluUEsFBgAAAAAFAAUAHQEAAPIBAAAAAA==';

const String _pythonStreamingZip =
    'UEsDBBQACAAIAHdOR10AAAAAAAAAAAAAAAAHAAAAYXBwLmV4ZfONYqADAABQSwcIV3V+jAcAAABmAAAAUEsDBBQACAAIAHdOR10AAAAAAAAAAAAAAAAFAAAAZGF0YS8DAFBLBwgAAAAAAgAAAAAAAABQSwMEFAAIAAgAd05HXQAAAAAAAAAAAAAAAA4AAABkYXRhL2hlbGxvLnR4dMtIzcnJV8jAR3LhlR1VM6pmEKkBAFBLBwhQ2yqrFQAAANACAABQSwMEFAAICAAAAAAhAAAAAAAAAAAAAAAAABMAAABkYXRhL2NhZsOpINin2YQudHh0dW5pY29kZVBLBwhgtLHTBwAAAAcAAABQSwMEFAAIAAAAAAAhAAAAAAAAAAAAAAAAAAoAAABzdG9yZWQuYmluAAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/1BLBwhzjAUpAAEAAAABAABQSwECFAMUAAgACAB3TkddV3V+jAcAAABmAAAABwAAAAAAAAAAAAAAgAEAAAAAYXBwLmV4ZVBLAQIUAxQACAAIAHdOR10AAAAAAgAAAAAAAAAFAAAAAAAAAAAAEAD9QTwAAABkYXRhL1BLAQIUAxQACAAIAHdOR11Q2yqrFQAAANACAAAOAAAAAAAAAAAAAACAAXEAAABkYXRhL2hlbGxvLnR4dFBLAQIUAxQACAgAAAAAIQBgtLHTBwAAAAcAAAATAAAAAAAAAAAAAACAAcIAAABkYXRhL2NhZsOpINin2YQudHh0UEsBAhQDFAAIAAAAAAAhAHOMBSkAAQAAAAEAAAoAAAAAAAAAAAAAAIABCgEAAHN0b3JlZC5iaW5QSwUGAAAAAAUABQAdAQAAQgIAAAAA';
