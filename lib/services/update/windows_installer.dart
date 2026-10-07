import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'update_installer.dart';

// ---------------------------------------------------------------------------
// Zip extraction
// ---------------------------------------------------------------------------

/// Limits that [SafeZipExtractor] enforces. The defaults fit a Flutter Windows
/// release folder (a few hundred files, well under 200 MB) with a wide margin
/// and stop a zip bomb long before it fills the disk. Tests use small values.
class ZipLimits {
  const ZipLimits({
    this.maxArchiveBytes = 400 * 1024 * 1024,
    this.maxEntries = 5000,
    this.maxFileBytes = 512 * 1024 * 1024,
    this.maxTotalBytes = 1024 * 1024 * 1024,
    this.maxPathLength = 200,
    this.maxDepth = 24,
    this.maxDirectoryBytes = 8 * 1024 * 1024,
  });

  /// Size of the zip file itself (the download is capped at the same value).
  final int maxArchiveBytes;

  /// Number of entries (files and folders).
  final int maxEntries;

  /// Uncompressed size of one file.
  final int maxFileBytes;

  /// Uncompressed size of all files together.
  final int maxTotalBytes;

  /// Length of one entry name (the path relative to the staging folder).
  final int maxPathLength;

  /// Number of path components of one entry.
  final int maxDepth;

  /// Size of the zip's central directory (the list of entries).
  final int maxDirectoryBytes;
}

/// Why [SafeZipExtractor] refused a zip. Only this value is kept: never an
/// entry name, a path or a library message.
enum ZipRejection {
  /// Not a zip file, or its end record is missing or damaged.
  notAZip,

  /// A feature the extractor does not support on purpose: encryption, zip64,
  /// several disks, or a compression method other than stored and deflate.
  unsupported,

  /// More entries than [ZipLimits.maxEntries].
  tooManyEntries,

  /// A size is over a cap ([ZipLimits.maxFileBytes], [ZipLimits.maxTotalBytes],
  /// [ZipLimits.maxArchiveBytes], [ZipLimits.maxDirectoryBytes]).
  tooLarge,

  /// An entry name that could write outside the staging folder or that Windows
  /// would read differently than it looks: absolute paths, drive letters,
  /// `..`, alternate data streams, device names, trailing dots and so on.
  unsafeName,

  /// Two entries that end up in the same place (also when they differ only in
  /// letter case), or a file and a folder with the same name.
  duplicate,

  /// A symbolic link, a Windows reparse point or another special file.
  linkEntry,

  /// The data does not match its headers: wrong CRC-32, wrong size (also a
  /// size that was understated to hide a bomb), overlapping entries, local
  /// header that disagrees with the directory, truncated data.
  corrupt,

  /// A file system operation failed (no space, no permission, target not
  /// empty).
  io,
}

/// Thrown by [SafeZipExtractor]. [toString] carries only the reason.
class ZipException implements Exception {
  const ZipException(this.reason);

  final ZipRejection reason;

  @override
  String toString() => 'ZipException(${reason.name})';
}

/// What an extraction produced.
class ZipExtraction {
  const ZipExtraction({
    required this.files,
    required this.directories,
    required this.totalBytes,
  });

  final int files;
  final int directories;

  /// Uncompressed size of all files.
  final int totalBytes;
}

/// Unpacks a zip into an empty directory without trusting anything in it.
///
/// Why not `package:archive`: its decoder inflates a whole entry into memory
/// and has no way to stop at a cap, so a bomb (a few kilobytes that inflate to
/// gigabytes) cannot be bounded with it. This reader parses the central
/// directory itself and streams each entry through `dart:io`'s zlib in small
/// chunks, so every cap is enforced while the bytes are produced.
///
/// The work happens in two phases. First every entry is checked and nothing is
/// written: names, sizes, counts, collisions, the local headers and the
/// layout of the data inside the file. Only then the files are written, each
/// one created with `exclusive` (never over an existing file), counted and
/// checksummed on the way, and checked against the size and CRC-32 of the
/// directory at the end.
///
/// Refused (see [ZipRejection]): absolute paths, backslash tricks, `..`,
/// drive letters and `:` (alternate data streams), Windows device names,
/// trailing dots and spaces, short-name aliases (`NAME~1`), control and
/// bidirectional characters, over-long names, symbolic links and Windows
/// reparse points, other special files, encrypted entries, zip64, multi-disk
/// archives, duplicate or case-colliding names, overlapping entries, a count
/// or size over the limits, and any entry whose real size differs from its
/// declared one.
///
/// The caller deletes [target] after a failure; a partial result may be there.
class SafeZipExtractor {
  const SafeZipExtractor({this.limits = const ZipLimits()});

  final ZipLimits limits;

  /// Extracts [zip] into [target], which must exist and be empty.
  Future<ZipExtraction> extract(File zip, Directory target) async {
    RandomAccessFile? input;
    try {
      await _requireEmptyDirectory(target);
      input = await zip.open();
      final length = await input.length();
      if (length > limits.maxArchiveBytes) {
        throw const ZipException(ZipRejection.tooLarge);
      }
      final directory = await _readDirectory(input, length);
      final entries = directory.entries;
      _checkNames(entries);
      await _locateData(input, directory);
      return await _write(input, entries, target);
    } on ZipException {
      rethrow;
    } on FileSystemException {
      throw const ZipException(ZipRejection.io);
    } on Object {
      // zlib reports damaged data with FormatException or its own error type.
      throw const ZipException(ZipRejection.corrupt);
    } finally {
      try {
        await input?.close();
      } on Object {
        // Nothing more to do.
      }
    }
  }

  // --- Entry names ---------------------------------------------------------

  static final RegExp _forbiddenChars = RegExp(
    r'[\u0000-\u001f\u007f-\u009f<>:"|?*\u202a-\u202e\u2066-\u2069]',
  );
  static final RegExp _shortNameAlias = RegExp(r'~[0-9]');
  static const Set<String> _reservedNames = {
    'con',
    'prn',
    'aux',
    'nul',
    'conin\$',
    'conout\$',
    'com1',
    'com2',
    'com3',
    'com4',
    'com5',
    'com6',
    'com7',
    'com8',
    'com9',
    'com\u00b9',
    'com\u00b2',
    'com\u00b3',
    'lpt1',
    'lpt2',
    'lpt3',
    'lpt4',
    'lpt5',
    'lpt6',
    'lpt7',
    'lpt8',
    'lpt9',
    'lpt\u00b9',
    'lpt\u00b2',
    'lpt\u00b3',
  };

  /// Checks one entry name as the extractor does and returns its path
  /// components (without a trailing empty one for folders). Throws
  /// [ZipException] with [ZipRejection.unsafeName] for anything that is not a
  /// plain relative path of ordinary file names.
  ///
  /// Backslashes count as separators (some Windows zip tools write them);
  /// they are turned into `/` before any other check.
  static List<String> checkName(
    String raw, {
    int maxPathLength = 200,
    int maxDepth = 24,
  }) {
    const unsafe = ZipException(ZipRejection.unsafeName);
    if (raw.isEmpty || raw.length > maxPathLength + 1) throw unsafe;
    final name = raw.replaceAll(r'\', '/');
    // Absolute path, UNC path (`//server/share`) or device path.
    if (name.startsWith('/')) throw unsafe;
    final parts = name.split('/');
    final isFolder = parts.length > 1 && parts.last.isEmpty;
    if (isFolder) parts.removeLast();
    if (parts.isEmpty || parts.length > maxDepth) throw unsafe;
    var pathLength = parts.length - 1;
    for (final part in parts) {
      pathLength += part.length;
      if (part.isEmpty || part == '.' || part == '..') throw unsafe;
      if (part.length > 255) throw unsafe;
      if (_forbiddenChars.hasMatch(part)) throw unsafe;
      // Windows drops trailing dots and spaces, so "a." would be "a".
      if (part.endsWith('.') || part.endsWith(' ') || part.startsWith(' ')) {
        throw unsafe;
      }
      if (_shortNameAlias.hasMatch(part)) throw unsafe;
      if (_isReservedDeviceName(part)) throw unsafe;
    }
    if (pathLength > maxPathLength) throw unsafe;
    return parts;
  }

  static bool _isReservedDeviceName(String part) {
    final dot = part.indexOf('.');
    final base = (dot >= 0 ? part.substring(0, dot) : part)
        .trimRight()
        .toLowerCase();
    return _reservedNames.contains(base);
  }

  void _checkNames(List<_Entry> entries) {
    final tree = _NameTree();
    var total = 0;
    var files = 0;
    for (final e in entries) {
      e.parts = checkName(
        e.name,
        maxPathLength: limits.maxPathLength,
        maxDepth: limits.maxDepth,
      );
      tree.add(e.parts, isFolder: e.isFolder);
      if (e.isFolder) continue;
      files++;
      total += e.uncompressedSize;
      if (total > limits.maxTotalBytes) {
        throw const ZipException(ZipRejection.tooLarge);
      }
    }
    if (files == 0) throw const ZipException(ZipRejection.corrupt);
  }

  // --- Central directory ---------------------------------------------------

  static const int _eocdSignature = 0x06054b50;
  static const int _zip64LocatorSignature = 0x07064b50;
  static const int _centralSignature = 0x02014b50;
  static const int _localSignature = 0x04034b50;

  Future<_Directory> _readDirectory(RandomAccessFile input, int length) async {
    if (length < 22) throw const ZipException(ZipRejection.notAZip);
    final tailLength = min(length, 22 + 0xffff);
    final tailStart = length - tailLength;
    final tail = await _readAt(input, tailStart, tailLength);
    final tailView = ByteData.sublistView(tail);

    // The end record is the last thing in the file: its comment must end
    // exactly at the end of the file.
    var at = -1;
    for (var i = tailLength - 22; i >= 0; i--) {
      if (tailView.getUint32(i, Endian.little) != _eocdSignature) continue;
      if (i + 22 + tailView.getUint16(i + 20, Endian.little) == tailLength) {
        at = i;
        break;
      }
    }
    if (at < 0) throw const ZipException(ZipRejection.notAZip);
    if (at >= 20 &&
        tailView.getUint32(at - 20, Endian.little) == _zip64LocatorSignature) {
      throw const ZipException(ZipRejection.unsupported);
    }
    final disk = tailView.getUint16(at + 4, Endian.little);
    final directoryDisk = tailView.getUint16(at + 6, Endian.little);
    final entriesOnDisk = tailView.getUint16(at + 8, Endian.little);
    final entryCount = tailView.getUint16(at + 10, Endian.little);
    final directorySize = tailView.getUint32(at + 12, Endian.little);
    final directoryOffset = tailView.getUint32(at + 16, Endian.little);
    if (disk != 0 || directoryDisk != 0 || entriesOnDisk != entryCount) {
      throw const ZipException(ZipRejection.unsupported);
    }
    if (entryCount == 0xffff ||
        directorySize == 0xffffffff ||
        directoryOffset == 0xffffffff) {
      throw const ZipException(ZipRejection.unsupported);
    }
    if (entryCount == 0) throw const ZipException(ZipRejection.corrupt);
    if (entryCount > limits.maxEntries) {
      throw const ZipException(ZipRejection.tooManyEntries);
    }
    if (directorySize > limits.maxDirectoryBytes) {
      throw const ZipException(ZipRejection.tooLarge);
    }
    final eocdPosition = tailStart + at;
    if (directoryOffset + directorySize > eocdPosition) {
      throw const ZipException(ZipRejection.corrupt);
    }

    final bytes = await _readAt(input, directoryOffset, directorySize);
    final view = ByteData.sublistView(bytes);
    final entries = <_Entry>[];
    var pos = 0;
    for (var n = 0; n < entryCount; n++) {
      if (pos + 46 > bytes.length ||
          view.getUint32(pos, Endian.little) != _centralSignature) {
        throw const ZipException(ZipRejection.corrupt);
      }
      final versionMadeBy = view.getUint16(pos + 4, Endian.little);
      final flags = view.getUint16(pos + 8, Endian.little);
      final method = view.getUint16(pos + 10, Endian.little);
      final crc = view.getUint32(pos + 16, Endian.little);
      final compressed = view.getUint32(pos + 20, Endian.little);
      final uncompressed = view.getUint32(pos + 24, Endian.little);
      final nameLength = view.getUint16(pos + 28, Endian.little);
      final extraLength = view.getUint16(pos + 30, Endian.little);
      final commentLength = view.getUint16(pos + 32, Endian.little);
      final diskStart = view.getUint16(pos + 34, Endian.little);
      final externalAttributes = view.getUint32(pos + 38, Endian.little);
      final localOffset = view.getUint32(pos + 42, Endian.little);
      final next = pos + 46 + nameLength + extraLength + commentLength;
      if (next > bytes.length) throw const ZipException(ZipRejection.corrupt);
      final nameBytes = Uint8List.sublistView(
        bytes,
        pos + 46,
        pos + 46 + nameLength,
      );
      pos = next;

      // 0x1 encrypted, 0x40 strong encryption, 0x2000 masked headers.
      if (flags & 0x2041 != 0) {
        throw const ZipException(ZipRejection.unsupported);
      }
      if (method != 0 && method != 8) {
        throw const ZipException(ZipRejection.unsupported);
      }
      if (diskStart != 0) throw const ZipException(ZipRejection.unsupported);
      if (compressed == 0xffffffff ||
          uncompressed == 0xffffffff ||
          localOffset == 0xffffffff) {
        throw const ZipException(ZipRejection.unsupported);
      }
      if (method == 0 && compressed != uncompressed) {
        throw const ZipException(ZipRejection.corrupt);
      }
      final fileType = _checkFileType(versionMadeBy >> 8, externalAttributes);

      final String name;
      try {
        name = utf8.decode(nameBytes);
      } on FormatException {
        throw const ZipException(ZipRejection.unsafeName);
      }
      final isFolder = name.endsWith('/') || name.endsWith(r'\');
      if (isFolder && uncompressed != 0) {
        throw const ZipException(ZipRejection.corrupt);
      }
      // The attributes and the name must agree on "folder".
      if ((fileType == 0x4000 && !isFolder) ||
          (fileType == 0x8000 && isFolder)) {
        throw const ZipException(ZipRejection.corrupt);
      }
      if (uncompressed > limits.maxFileBytes) {
        throw const ZipException(ZipRejection.tooLarge);
      }
      entries.add(
        _Entry(
          name: name,
          nameBytes: Uint8List.fromList(nameBytes),
          isFolder: isFolder,
          method: method,
          crc32: crc,
          compressedSize: compressed,
          uncompressedSize: uncompressed,
          localOffset: localOffset,
        ),
      );
    }
    if (pos != bytes.length) throw const ZipException(ZipRejection.corrupt);
    return _Directory(entries: entries, offset: directoryOffset);
  }

  /// Symbolic links, devices, FIFOs, sockets and Windows reparse points. Returns
  /// the Unix file type from the attributes (0 when the host did not set one).
  static int _checkFileType(int madeByHost, int externalAttributes) {
    var type = 0;
    // Unix hosts keep st_mode in the upper 16 bits.
    if (madeByHost == 3) {
      type = (externalAttributes >> 16) & 0xf000;
      if (type != 0 && type != 0x8000 && type != 0x4000) {
        throw const ZipException(ZipRejection.linkEntry);
      }
    }
    // FILE_ATTRIBUTE_REPARSE_POINT in the low word (FAT and NTFS hosts).
    if (madeByHost != 3 && (externalAttributes & 0x400) != 0) {
      throw const ZipException(ZipRejection.linkEntry);
    }
    return type;
  }

  // --- Local headers and data layout ---------------------------------------

  Future<void> _locateData(RandomAccessFile input, _Directory directory) async {
    final spans = <_Span>[];
    for (final e in directory.entries) {
      final header = await _readAt(input, e.localOffset, 30);
      final view = ByteData.sublistView(header);
      if (view.getUint32(0, Endian.little) != _localSignature) {
        throw const ZipException(ZipRejection.corrupt);
      }
      final method = view.getUint16(8, Endian.little);
      final nameLength = view.getUint16(26, Endian.little);
      final extraLength = view.getUint16(28, Endian.little);
      if (method != e.method || nameLength != e.nameBytes.length) {
        throw const ZipException(ZipRejection.corrupt);
      }
      final localName = await _readAt(input, e.localOffset + 30, nameLength);
      for (var i = 0; i < nameLength; i++) {
        if (localName[i] != e.nameBytes[i]) {
          throw const ZipException(ZipRejection.corrupt);
        }
      }
      e.dataStart = e.localOffset + 30 + nameLength + extraLength;
      final dataEnd = e.dataStart + e.compressedSize;
      if (dataEnd > directory.offset) {
        throw const ZipException(ZipRejection.corrupt);
      }
      spans.add(_Span(e.localOffset, dataEnd));
    }
    // No two entries may share bytes: that is how a few kilobytes are made to
    // look like many large files.
    spans.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < spans.length; i++) {
      if (spans[i].start < spans[i - 1].end) {
        throw const ZipException(ZipRejection.corrupt);
      }
    }
  }

  // --- Writing -------------------------------------------------------------

  static const int _storedChunk = 64 * 1024;

  // Small input chunks keep the output of one `add` bounded: deflate cannot
  // expand more than about 1000 to 1.
  static const int _deflateChunk = 8 * 1024;

  Future<void> _requireEmptyDirectory(Directory target) async {
    if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const ZipException(ZipRejection.io);
    }
    if (!await target.list(followLinks: false).isEmpty) {
      throw const ZipException(ZipRejection.io);
    }
  }

  Future<ZipExtraction> _write(
    RandomAccessFile input,
    List<_Entry> entries,
    Directory target,
  ) async {
    final made = <String>{target.path};
    var files = 0;
    var folders = 0;
    var bytes = 0;

    void ensureFolder(List<String> parts) {
      var path = target.path;
      for (final part in parts) {
        path = p.join(path, part);
        if (!made.add(path)) continue;
        final type = FileSystemEntity.typeSync(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          Directory(path).createSync();
        } else if (type != FileSystemEntityType.directory) {
          throw const ZipException(ZipRejection.linkEntry);
        }
      }
    }

    for (final e in entries) {
      if (e.isFolder) {
        ensureFolder(e.parts);
        folders++;
        continue;
      }
      ensureFolder(e.parts.sublist(0, e.parts.length - 1));
      final path = p.joinAll([target.path, ...e.parts]);
      if (!p.isWithin(target.path, path)) {
        throw const ZipException(ZipRejection.unsafeName);
      }
      final file = File(path);
      await file.create(exclusive: true);
      final out = await file.open(mode: FileMode.writeOnly);
      try {
        await _copyEntry(input, e, out);
      } finally {
        await out.close();
      }
      files++;
      bytes += e.uncompressedSize;
    }
    return ZipExtraction(files: files, directories: folders, totalBytes: bytes);
  }

  Future<void> _copyEntry(
    RandomAccessFile input,
    _Entry e,
    RandomAccessFile out,
  ) async {
    final sink = _EntrySink(limit: e.uncompressedSize);
    if (e.compressedSize == 0 && e.uncompressedSize == 0) {
      if (e.crc32 != 0) throw const ZipException(ZipRejection.corrupt);
      return;
    }
    final inflater = e.method == 8
        ? ZLibDecoder(raw: true).startChunkedConversion(sink)
        : null;
    final chunk = inflater == null ? _storedChunk : _deflateChunk;
    await input.setPosition(e.dataStart);
    var remaining = e.compressedSize;
    while (remaining > 0) {
      final data = await input.read(min(remaining, chunk));
      if (data.isEmpty) throw const ZipException(ZipRejection.corrupt);
      remaining -= data.length;
      if (inflater != null) {
        inflater.add(data);
      } else {
        sink.add(data);
      }
      await sink.drainTo(out);
    }
    inflater?.close();
    await sink.drainTo(out);
    if (sink.written != e.uncompressedSize || sink.crc32 != e.crc32) {
      throw const ZipException(ZipRejection.corrupt);
    }
  }

  static Future<Uint8List> _readAt(
    RandomAccessFile input,
    int position,
    int count,
  ) async {
    if (position < 0 || count < 0) {
      throw const ZipException(ZipRejection.corrupt);
    }
    final out = Uint8List(count);
    if (count == 0) return out;
    await input.setPosition(position);
    var got = 0;
    while (got < count) {
      final chunk = await input.read(count - got);
      if (chunk.isEmpty) throw const ZipException(ZipRejection.corrupt);
      out.setRange(got, got + chunk.length, chunk);
      got += chunk.length;
    }
    return out;
  }
}

class _Directory {
  _Directory({required this.entries, required this.offset});

  final List<_Entry> entries;

  /// Where the central directory starts; entry data must end before it.
  final int offset;
}

class _Entry {
  _Entry({
    required this.name,
    required this.nameBytes,
    required this.isFolder,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localOffset,
  });

  final String name;
  final Uint8List nameBytes;
  final bool isFolder;
  final int method;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localOffset;

  /// Set by the name check.
  List<String> parts = const [];

  /// Set when the local header has been read.
  int dataStart = 0;
}

class _Span {
  const _Span(this.start, this.end);

  final int start;
  final int end;
}

/// Tracks every path the zip would create, to catch duplicates, letter-case
/// collisions and a file that is also used as a folder.
class _NameTree {
  /// Lower-case path -> the spelling that was seen first.
  final Map<String, String> _spelling = {};

  /// Lower-case path -> true for a folder, false for a file.
  final Map<String, bool> _isFolder = {};

  void add(List<String> parts, {required bool isFolder}) {
    for (var i = 1; i <= parts.length; i++) {
      final last = i == parts.length;
      final prefix = parts.sublist(0, i);
      final key = prefix.map((s) => s.toLowerCase()).join('/');
      final spelling = prefix.join('/');
      final seen = _spelling[key];
      if (seen != null && seen != spelling) {
        throw const ZipException(ZipRejection.duplicate);
      }
      _spelling[key] = spelling;
      final folderHere = !last || isFolder;
      final known = _isFolder[key];
      if (known != null && (known != folderHere || !folderHere)) {
        throw const ZipException(ZipRejection.duplicate);
      }
      _isFolder[key] = folderHere;
    }
  }
}

/// Receives what the inflater (or the stored copy) produces: counts it, checks
/// it against the declared size right away, and keeps the CRC-32. The bytes
/// are held only until [drainTo] writes them, once per input chunk.
class _EntrySink implements Sink<List<int>> {
  _EntrySink({required this.limit});

  final int limit;
  final List<Uint8List> _pending = [];

  int written = 0;
  int _crc = 0xffffffff;

  int get crc32 => _crc ^ 0xffffffff;

  @override
  void add(List<int> data) {
    if (data.isEmpty) return;
    written += data.length;
    // More than the directory says: stop before the bytes are kept.
    if (written > limit) throw const ZipException(ZipRejection.corrupt);
    final chunk = data is Uint8List ? data : Uint8List.fromList(data);
    _crc = _updateCrc(_crc, chunk);
    _pending.add(chunk);
  }

  @override
  void close() {}

  Future<void> drainTo(RandomAccessFile out) async {
    if (_pending.isEmpty) return;
    final chunks = List<Uint8List>.of(_pending);
    _pending.clear();
    for (final c in chunks) {
      await out.writeFrom(c);
    }
  }

  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }

  static int _updateCrc(int crc, Uint8List data) {
    var c = crc;
    for (var i = 0; i < data.length; i++) {
      c = _table[(c ^ data[i]) & 0xff] ^ (c >> 8);
    }
    return c;
  }
}

// ---------------------------------------------------------------------------
// Installer
// ---------------------------------------------------------------------------

/// Why [WindowsUpdateInstaller.install] did not hand over to the swap script.
/// Only these values are ever kept: never a path or a system message.
enum WindowsInstallError {
  /// The install folder is a network (UNC) or device path, the drive root, or
  /// the program is not an `.exe` this installer can replace.
  unsupportedLocation,

  /// The install folder cannot be written (Program Files, a read-only share,
  /// Controlled folder access). The release page is the way out.
  notWritable,

  /// The zip is not acceptable, see [WindowsUpdateInstaller.lastZipRejection].
  badPackage,

  /// The zip unpacked fine but is not a release of this program: no `.exe` of
  /// the same name, no `flutter_windows.dll`, no `data` folder, links in the
  /// tree, or a size that makes no sense.
  badLayout,

  /// The vault could not be locked, so nothing was started.
  prepareExitFailed,

  /// The helper script could not be written or PowerShell could not be
  /// started.
  helperUnavailable,

  /// PowerShell started but the script did not report back in time (a group
  /// policy or a security product blocked it), or reported a problem. The app
  /// keeps running and nothing was changed.
  helperNotReady,

  /// Anything else.
  internal,
}

/// What the swap script reported on its last run, read at the next start.
enum WindowsUpdateHelperResult {
  /// No log, or one this version cannot read.
  none,

  /// The new version was copied and started.
  succeeded,

  /// The swap failed and the old files were put back; the old version runs.
  rolledBack,

  /// The swap failed and putting the old files back failed too. The program
  /// may be damaged; downloading the release again fixes it.
  rollbackFailed,

  /// The script stopped before changing anything (the old version runs).
  aborted,
}

/// Starts a program. Same shape as [Process.start]; tests pass a fake.
typedef WindowsProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  ProcessStartMode mode,
});

/// Installs an update on Windows: unpacks the verified zip, then hands over to a
/// small PowerShell script that waits for this process to exit, copies the new
/// files over the install folder and starts the new version.
///
/// The app is a plain folder (exe, dlls, `data/`) that the user unzipped
/// somewhere writable, so no installer is involved. Steps, in this order (the
/// order is part of the contract with `UpdateInstaller`):
///
/// 1. The install folder is the folder of the running exe. A network path, a
///    drive root or a folder that cannot be written (a probe file is created
///    and deleted) ends here with nothing started: [InstallOutcome.failed]
///    with [lastError] `unsupportedLocation` or `notWritable`.
/// 2. The zip is unpacked by [SafeZipExtractor] into a new `stage` folder next
///    to it (the controller's private folder), then the tree is checked: the
///    same exe file name as the running program (starts with `MZ`), `data/` and
///    `flutter_windows.dll`, no links, a sane size. A zip that holds the
///    release inside one top folder is accepted.
/// 3. `apply_update.ps1` (see `tool/windows_update_helper/`) is written next
///    to it.
/// 4. `prepareExit` locks the vault. After this point nothing can fail without
///    the user unlocking again.
/// 5. PowerShell is started detached with the arguments as a list (never a
///    command line string). The script checks its arguments and the staged
///    files, then writes `ready` into the private folder; if it never does
///    (execution policy, antivirus), the helper is stopped, nothing was
///    changed and [InstallOutcome.failed] is returned with the app still
///    running.
/// 6. `exit(0)`. The script waits for this process and for any other program
///    that runs from the install folder, backs up the files it will overwrite,
///    copies, verifies, starts the new exe and cleans up; on a failure it puts
///    the old files back and starts the old exe.
///
/// Nothing is logged here. The script writes a log without paths to the temp
/// folder; [readHelperResult] reads its last line at the next start.
class WindowsUpdateInstaller implements UpdateInstaller {
  WindowsUpdateInstaller({
    String? executablePath,
    int? processId,
    bool? isWindows,
    WindowsProcessStarter? startProcess,
    void Function(int code)? exitProcess,
    Map<String, String>? environment,
    Directory? logDirectory,
    Random? random,
    this.extractor = const SafeZipExtractor(),
    this.minTotalBytes = defaultMinTotalBytes,
    this.requirePeHeader = true,
    this.readyTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(milliseconds: 100),
  }) : _executablePath = executablePath ?? Platform.resolvedExecutable,
       _processId = processId ?? pid,
       _isWindows = isWindows ?? Platform.isWindows,
       _startProcess = startProcess ?? _defaultStarter,
       _exit = exitProcess ?? exit,
       _environment = environment ?? Platform.environment,
       _logDirectory = logDirectory ?? Directory.systemTemp,
       _random = random ?? Random.secure();

  /// A release folder is far bigger (the engine dll alone is tens of MB).
  static const int defaultMinTotalBytes = 1024 * 1024;

  /// The script's file name, next to the zip.
  static const String scriptFileName = 'apply_update.ps1';

  /// Name of the log the script writes in the temp folder.
  static const String helperLogFileName = 'update-helper.log';

  final SafeZipExtractor extractor;

  /// Smaller totals are refused as "not a release".
  final int minTotalBytes;

  /// Require the `MZ` header on the staged exe. Off only in tests that stage
  /// synthetic files.
  final bool requirePeHeader;

  /// How long to wait for the script's `ready` file.
  final Duration readyTimeout;

  /// How often to look for it.
  final Duration pollInterval;

  final String _executablePath;
  final int _processId;
  final bool _isWindows;
  final WindowsProcessStarter _startProcess;
  final void Function(int code) _exit;
  final Map<String, String> _environment;
  final Directory _logDirectory;
  final Random _random;

  bool _busy = false;
  WindowsInstallError? _lastError;
  ZipRejection? _lastZipRejection;

  /// Why the last [install] returned [InstallOutcome.failed]; null after a
  /// call that did not fail.
  WindowsInstallError? get lastError => _lastError;

  /// The zip problem behind [WindowsInstallError.badPackage].
  ZipRejection? get lastZipRejection => _lastZipRejection;

  @override
  Future<InstallOutcome> install(
    File package, {
    required Future<void> Function() prepareExit,
  }) async {
    if (!_isWindows) return InstallOutcome.unsupported;
    // A second call must not disturb the first one's state.
    if (_busy) return InstallOutcome.failed;
    _busy = true;
    _lastError = null;
    _lastZipRejection = null;
    // The controller's private folder for this update; the package is in it.
    final work = package.parent;
    final stage = Directory(p.join(work.path, 'stage'));
    final script = File(p.join(work.path, scriptFileName));
    final ready = File(p.join(work.path, 'ready'));
    final backup = Directory(p.join(work.path, 'backup'));
    var handedOver = false;
    Process? helper;
    try {
      final location = _locateInstallFolder();
      await _probeWritable(location.directory);
      // Looked up before anything is unpacked or the vault is locked: with no
      // system PowerShell the app just keeps running as it was.
      final powerShell = _powerShellExecutable();

      final payload = await _unpack(package, stage);

      await script.writeAsBytes(ascii.encode(windowsApplyUpdateScript));

      try {
        await prepareExit();
      } on Object {
        throw const _Failed(WindowsInstallError.prepareExitFailed);
      }

      final log = File(p.join(_logDirectory.path, helperLogFileName));
      await _deleteQuietly(ready);
      final args = buildArguments(
        scriptPath: script.path,
        installDir: location.directory.path,
        stagingDir: payload.path,
        exeName: location.exeName,
        processId: _processId,
        backupDir: backup.path,
        readyFile: ready.path,
        logFile: log.path,
      );
      try {
        helper = await _startProcess(
          powerShell,
          args,
          // Not the private folder (the next start deletes it, and a running
          // program's current folder cannot be deleted) and not the install
          // folder (it would stay in use).
          workingDirectory: _logDirectory.path,
          mode: ProcessStartMode.detached,
        );
      } on Object {
        throw const _Failed(WindowsInstallError.helperUnavailable);
      }

      if (!await _helperIsReady(ready)) {
        throw const _Failed(WindowsInstallError.helperNotReady);
      }

      handedOver = true;
      _exit(0);
      // Only reached when `exit` is replaced (tests).
      return InstallOutcome.started;
    } on _Failed catch (e) {
      return _fail(e.error);
    } on Object {
      return _fail(WindowsInstallError.internal);
    } finally {
      _busy = false;
      if (!handedOver) {
        _stopQuietly(helper);
        await _deleteQuietly(stage);
        await _deleteQuietly(backup);
        await _deleteQuietly(script);
        await _deleteQuietly(ready);
      }
    }
  }

  /// The argument list for PowerShell. Every value is its own list element and
  /// reaches the script as one parameter value: there is no command line
  /// string, so spaces, quotes, `&`, `;`, `$` and non-ASCII letters in a path
  /// cannot change what runs. (A path never ends in a backslash here, which
  /// would be misread as an escaped quote.)
  static List<String> buildArguments({
    required String scriptPath,
    required String installDir,
    required String stagingDir,
    required String exeName,
    required int processId,
    required String backupDir,
    required String readyFile,
    required String logFile,
  }) => [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    scriptPath,
    '-InstallDir',
    installDir,
    '-StagingDir',
    stagingDir,
    '-ExeName',
    exeName,
    '-ProcessId',
    processId.toString(),
    '-BackupDir',
    backupDir,
    '-ReadyFile',
    readyFile,
    '-LogFile',
    logFile,
  ];

  /// What the swap script reported on its last run, from the log it leaves in
  /// the temp folder. Call it once at start-up (it deletes the log unless
  /// [deleteLog] is false): after [WindowsUpdateHelperResult.rolledBack],
  /// [WindowsUpdateHelperResult.rollbackFailed] or
  /// [WindowsUpdateHelperResult.aborted] the user should be told that the
  /// update did not happen. Never throws.
  static Future<WindowsUpdateHelperResult> readHelperResult({
    Directory? logDirectory,
    bool deleteLog = true,
  }) async {
    final file = File(
      p.join((logDirectory ?? Directory.systemTemp).path, helperLogFileName),
    );
    try {
      if (!await file.exists()) return WindowsUpdateHelperResult.none;
      if (await file.length() > 64 * 1024) {
        return WindowsUpdateHelperResult.none;
      }
      final lines = await file.readAsLines();
      var result = WindowsUpdateHelperResult.none;
      for (final line in lines.reversed) {
        final at = line.indexOf(' RESULT ');
        if (at < 0) continue;
        final token = line.substring(at + 8).trim();
        if (token == 'success') {
          result = WindowsUpdateHelperResult.succeeded;
        } else if (token.startsWith('rolled-back')) {
          result = WindowsUpdateHelperResult.rolledBack;
        } else if (token.startsWith('rollback-failed')) {
          result = WindowsUpdateHelperResult.rollbackFailed;
        } else if (token.startsWith('aborted')) {
          result = WindowsUpdateHelperResult.aborted;
        }
        break;
      }
      if (deleteLog) await file.delete();
      return result;
    } on Object {
      return WindowsUpdateHelperResult.none;
    }
  }

  // --- Steps ---------------------------------------------------------------

  _Location _locateInstallFolder() {
    final exe = _executablePath;
    // \\server\share, \\?\C:\..., \\.\... and the forward-slash spellings.
    if (exe.startsWith(r'\\') || exe.startsWith('//')) {
      throw const _Failed(WindowsInstallError.unsupportedLocation);
    }
    final name = p.basename(exe);
    final dir = p.dirname(exe);
    if (!p.isAbsolute(exe) ||
        !name.toLowerCase().endsWith('.exe') ||
        name.length <= 4 ||
        p.dirname(dir) == dir) {
      throw const _Failed(WindowsInstallError.unsupportedLocation);
    }
    return _Location(Directory(dir), name);
  }

  /// Creates and deletes a file in [dir]: the cheapest honest test of "can the
  /// swap script write here". Nothing is changed when it fails.
  Future<void> _probeWritable(Directory dir) async {
    final probe = File(p.join(dir.path, '.update-probe-${_randomHex(8)}'));
    try {
      await probe.create(exclusive: true);
      await probe.writeAsBytes(const [0]);
      await probe.delete();
    } on Object {
      await _deleteQuietly(probe);
      throw const _Failed(WindowsInstallError.notWritable);
    }
  }

  /// Unpacks [package] into the new folder [stage] and returns the folder that
  /// holds the release (the stage itself, or its only subfolder).
  Future<Directory> _unpack(File package, Directory stage) async {
    if (FileSystemEntity.typeSync(stage.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const _Failed(WindowsInstallError.internal);
    }
    try {
      await stage.create();
    } on Object {
      throw const _Failed(WindowsInstallError.internal);
    }
    final ZipExtraction extraction;
    try {
      extraction = await extractor.extract(package, stage);
    } on ZipException catch (e) {
      _lastZipRejection = e.reason;
      throw const _Failed(WindowsInstallError.badPackage);
    } on Object {
      throw const _Failed(WindowsInstallError.badPackage);
    }
    if (extraction.totalBytes < minTotalBytes) {
      throw const _Failed(WindowsInstallError.badLayout);
    }
    final payload = await _findPayload(stage);
    await _checkLayout(payload, stage);
    return payload;
  }

  Future<Directory> _findPayload(Directory stage) async {
    final exeName = p.basename(_executablePath).toLowerCase();
    final top = await stage.list(followLinks: false).toList();
    bool hasExe(List<FileSystemEntity> entries) => entries.any(
      (e) => e is File && p.basename(e.path).toLowerCase() == exeName,
    );
    if (hasExe(top)) return stage;
    // The release folder zipped as a folder: `Release/<exe>`.
    if (top.length == 1 && top.single is Directory) {
      final inner = Directory(top.single.path);
      if (hasExe(await inner.list(followLinks: false).toList())) return inner;
    }
    throw const _Failed(WindowsInstallError.badLayout);
  }

  Future<void> _checkLayout(Directory payload, Directory stage) async {
    const bad = _Failed(WindowsInstallError.badLayout);
    final exeName = p.basename(_executablePath).toLowerCase();
    File? exe;
    var engine = false;
    var data = false;
    await for (final e in payload.list(followLinks: false)) {
      final name = p.basename(e.path).toLowerCase();
      if (e is File && name == exeName) exe = e;
      if (e is File && name == 'flutter_windows.dll') engine = true;
      if (e is Directory && name == 'data') data = true;
    }
    if (exe == null || !engine || !data) throw bad;
    if (requirePeHeader) {
      final input = await exe.open();
      try {
        final head = await input.read(2);
        if (head.length != 2 || head[0] != 0x4d || head[1] != 0x5a) throw bad;
      } finally {
        await input.close();
      }
    }
    // Nothing but plain files and folders (the extractor never makes links;
    // this is the second look, in case something else wrote here meanwhile).
    await for (final e in stage.list(recursive: true, followLinks: false)) {
      final type = FileSystemEntity.typeSync(e.path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.directory) {
        throw bad;
      }
    }
  }

  /// Waits for the script to write `ready`. False when it says `abort`, when
  /// the time is up, or when the file never shows up.
  Future<bool> _helperIsReady(File ready) async {
    final clock = Stopwatch()..start();
    while (true) {
      try {
        if (await ready.exists()) {
          final text = await ready.readAsString();
          if (text == 'ready') return true;
          if (text.startsWith('abort')) return false;
        }
      } on Object {
        // Being written right now; look again.
      }
      if (clock.elapsed >= readyTimeout) return false;
      await Future<void>.delayed(pollInterval);
    }
  }

  /// `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`, always as a
  /// full path. There is deliberately no fallback to the bare name: Windows
  /// looks for a bare `powershell.exe` in the application's own folder first,
  /// and that folder is writable by the user, so a planted file there would
  /// run with `-ExecutionPolicy Bypass`. Without the system file the update is
  /// refused and nothing changes ([WindowsInstallError.helperUnavailable]).
  String _powerShellExecutable() {
    final root = _environment['SystemRoot'] ?? _environment['windir'];
    if (root != null && root.isNotEmpty) {
      final candidate = p.join(
        root,
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      );
      try {
        if (File(candidate).existsSync()) return candidate;
      } on Object {
        // Treated like a missing file, just below.
      }
    }
    throw const _Failed(WindowsInstallError.helperUnavailable);
  }

  static Future<Process> _defaultStarter(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) => Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: mode,
  );

  // --- Helpers -------------------------------------------------------------

  InstallOutcome _fail(WindowsInstallError error) {
    _lastError = error;
    return _outcomeFor(error);
  }

  /// The outcome the controller sees. `InstallOutcome` has no value for "the
  /// install folder cannot be written" yet; when it gets one (the UI then
  /// explains and opens the release page), map `notWritable` and
  /// `unsupportedLocation` to it here. Until then the UI can read [lastError].
  InstallOutcome _outcomeFor(WindowsInstallError error) =>
      InstallOutcome.failed;

  String _randomHex(int bytes) => List<int>.generate(
    bytes,
    (_) => _random.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  void _stopQuietly(Process? process) {
    try {
      process?.kill();
    } on Object {
      // Already gone.
    }
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (entity is Directory) {
        if (await entity.exists()) await entity.delete(recursive: true);
      } else if (await entity.exists()) {
        await entity.delete();
      }
    } on Object {
      // The controller deletes the whole private folder afterwards.
    }
  }
}

class _Location {
  const _Location(this.directory, this.exeName);

  final Directory directory;
  final String exeName;
}

/// Internal: a failure with the reason to keep.
class _Failed implements Exception {
  const _Failed(this.error);

  final WindowsInstallError error;
}

// ---------------------------------------------------------------------------
// The swap script
// ---------------------------------------------------------------------------

// BEGIN apply_update.ps1 (generated by tool/windows_update_helper/embed_script.py)
/// The swap script, byte for byte the file
/// `tool/windows_update_helper/apply_update.ps1` (a test checks this).
const String windowsApplyUpdateScript = r'''
<#
  apply_update.ps1 - swaps the files of an installed app for a verified update.

  The app starts this script DETACHED (arguments as a list, never through a
  command string), then exits. Everything here runs on the user's own machine,
  with the user's own rights, and touches nothing outside the install folder
  and the two private folders the app created for this run. No network.

  Source of truth: this file. lib/services/update/windows_installer.dart holds a
  byte-identical copy (a test checks it; tool/windows_update_helper/embed_script.py
  refreshes it). Keep this file ASCII only and compatible with Windows
  PowerShell 5.1 (no ternary, no ?., no &&, no [type]::new).

  Order of work:
    1. Check the arguments and the staged files; take a per-folder lock. Any
       problem ends here with NOTHING changed and the app still running (the
       app waits for the ReadyFile before it exits).
    2. Write the ReadyFile, then wait for the app (ProcessId) and for every
       other program that runs from the install folder to exit.
    3. Back up the files the update will overwrite, copy the new files over the
       install folder (no deletes, no purge), verify size and SHA-256.
    4. On any failure after step 3 started: put the backed up files back.
    5. Start the app again (the new one after success, the old one after a
       failed swap), remove the staging and backup folders, write the log.

  The log (LogFile) holds step names, counts and exit codes only. It never holds
  a path, a user name or any secret. The last line is "RESULT <token>".

  Exit codes: 0 updated, 2 bad arguments, 3 another update is running,
  10 the app did not exit in time, 11 staged files or install folder not as
  expected, 12 the app took its go-ahead back (ReadyFile gone or changed),
  20 swap failed and was rolled back, 21 swap failed and the rollback failed
  too, 30 unexpected error.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $true)][string]$StagingDir,
    [Parameter(Mandatory = $true)][string]$ExeName,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$BackupDir,
    [string]$ReadyFile = '',
    [string]$LogFile = '',
    [int]$WaitSeconds = 60
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:LogPath = ''
$script:Robocopy = 'robocopy.exe'

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    if ([string]::IsNullOrEmpty($script:LogPath)) { return }
    try {
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
        $line = $stamp + ' ' + $Message + [System.Environment]::NewLine
        [System.IO.File]::AppendAllText($script:LogPath, $line)
    } catch {
        # The log is a courtesy; never let it break the update.
    }
}

# Exception type and HRESULT only: the message text can carry paths.
function Get-ErrorTag {
    param($ErrorRecord)
    try {
        $e = $ErrorRecord.Exception
        return ('{0} 0x{1:X8}' -f $e.GetType().Name, $e.HResult)
    } catch {
        return 'unknown'
    }
}

# An expected failure: a code for the exit status and a fixed tag for the log.
function New-UpdateError {
    param([int]$Code, [string]$Tag)
    $e = New-Object -TypeName System.InvalidOperationException -ArgumentList ('update:' + $Tag)
    $e.Data['code'] = $Code
    return $e
}

function Test-LocalAbsolutePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    # UNC paths and device paths (\\server\share, \\?\C:\, \\.\pipe).
    if ($Path.StartsWith('\\') -or $Path.StartsWith('//')) { return $false }
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return ($Path -match '^[A-Za-z]:[\\/]')
    }
    return $Path.StartsWith('/')
}

function Get-NormalizedDirectory {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Test-IsRoot {
    param([string]$FullPath)
    return ([System.IO.Path]::GetPathRoot($FullPath).Length -ge $FullPath.Length)
}

# True when $Child is the same folder as $Parent or lies inside it.
function Test-SameOrInside {
    param([string]$Child, [string]$Parent)
    $sep = [string][System.IO.Path]::DirectorySeparatorChar
    $c = $Child.TrimEnd($sep) + $sep
    $p = $Parent.TrimEnd($sep) + $sep
    return $c.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-FileSha256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        return [System.BitConverter]::ToString($sha.ComputeHash($stream))
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

# Runs a script block, retrying a few times (antivirus scanners and search
# indexers keep files open for a moment).
function Invoke-WithRetry {
    param([scriptblock]$Action, [int]$Attempts = 5, [int]$DelayMs = 1000)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            & $Action | Out-Null
            return
        } catch {
            if ($i -ge $Attempts) { throw }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}

# Every file below $Root as a relative path (no leading separator).
function Get-RelativeFiles {
    param([string]$Root)
    $prefix = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $result = New-Object -TypeName 'System.Collections.Generic.List[string]'
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)) {
        if (-not $f.FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw (New-UpdateError 11 'unexpected-file-location')
        }
        $result.Add($f.FullName.Substring($prefix.Length))
    }
    return , $result
}

# Process ids (other than ours) whose program file lies in the install folder.
function Get-InstallDirProcessIds {
    $found = New-Object -TypeName 'System.Collections.Generic.List[int]'
    foreach ($proc in @(Get-Process)) {
        if ($proc.Id -eq $PID) { continue }
        $path = $null
        try { $path = $proc.Path } catch { $path = $null }
        if (-not [string]::IsNullOrEmpty($path)) {
            if (Test-SameOrInside -Child $path -Parent $script:InstallFull) { $found.Add($proc.Id) }
        }
    }
    return , $found
}

# Waits for the app (ProcessId) to exit. A process id can be reused: when it
# now belongs to a program with another name, the app is already gone. An error
# while looking at the process means it went away under our hands (it is
# exiting right now, which is the normal case), so it ends the wait too; the
# check for other programs from the install folder is the safety net.
function Wait-ForApp {
    param([string]$Exe, [int]$Id, [DateTime]$Deadline)
    $exeBase = [System.IO.Path]::GetFileNameWithoutExtension($Exe)
    while ($true) {
        $app = Get-Process -Id $Id -ErrorAction SilentlyContinue
        if ($null -eq $app) { return }
        try {
            $name = $app.ProcessName
            if (($name -ine $exeBase) -and ($name -ine $Exe)) { return }
            if ($app.HasExited) { return }
        } catch {
            return
        }
        if ([DateTime]::UtcNow -ge $Deadline) { throw (New-UpdateError 10 'app-did-not-exit') }
        Start-Sleep -Milliseconds 250
    }
}

function Invoke-Robocopy {
    param([string]$Source, [string]$Destination, [int]$Attempts = 3)
    $code = 16
    for ($i = 1; $i -le $Attempts; $i++) {
        # /E subfolders, /IS /IT also files that look unchanged, /XJ no junctions.
        # No purge or mirror option is used: nothing in the destination is ever
        # deleted.
        & $script:Robocopy $Source $Destination /E /IS /IT /R:2 /W:1 /XJ /NP /NFL /NDL /NJH /NJS | Out-Null
        $code = $global:LASTEXITCODE
        # 0..7 are success codes (nothing copied, copied, extra files, ...).
        if ($code -lt 8) { return $code }
        Write-Log ('robocopy attempt {0} failed with code {1}' -f $i, $code)
        if ($i -lt $Attempts) { Start-Sleep -Seconds 2 }
    }
    return $code
}

# What an update needs: the program, the engine and the data folder in the
# staging folder, and the program in the install folder.
function Test-Layout {
    param([string]$Staging, [string]$Install, [string]$Exe)
    if (-not (Test-Path -LiteralPath (Join-Path $Staging $Exe) -PathType Leaf)) { throw (New-UpdateError 11 'staged-exe-missing') }
    if (-not (Test-Path -LiteralPath (Join-Path $Staging 'flutter_windows.dll') -PathType Leaf)) { throw (New-UpdateError 11 'staged-engine-missing') }
    if (-not (Test-Path -LiteralPath (Join-Path $Staging 'data') -PathType Container)) { throw (New-UpdateError 11 'staged-data-missing') }
    if (-not (Test-Path -LiteralPath (Join-Path $Install $Exe) -PathType Leaf)) { throw (New-UpdateError 11 'installed-exe-missing') }
}

# Plain CreateProcess through .NET: the path is used as given (Start-Process
# treats square brackets in a path as a wildcard in some versions).
function Start-App {
    param([string]$ExePath)
    $info = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $info.FileName = $ExePath
    $info.WorkingDirectory = $script:InstallFull
    $info.UseShellExecute = $false
    [void][System.Diagnostics.Process]::Start($info)
}

function Write-ReadyFile {
    param([string]$Content)
    if ([string]::IsNullOrEmpty($ReadyFile)) { return }
    try { [System.IO.File]::WriteAllText($ReadyFile, $Content) } catch { }
}

# The app deletes the ReadyFile when it gives up on this update (it saw no
# go-ahead in time, or it is not going to exit). A script that was just slow
# must not then swap files behind the back of a user who is still working.
function Assert-NotCancelled {
    if ([string]::IsNullOrEmpty($ReadyFile)) { return }
    $text = $null
    try { $text = [System.IO.File]::ReadAllText($ReadyFile) } catch { $text = $null }
    if ($text -ne 'ready') { throw (New-UpdateError 12 'cancelled') }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$exitCode = 30
$result = 'unexpected-error'
$phase = 'validate'     # validate -> waiting -> swap
$touched = $false       # true once a file in the install folder may have changed
$relaunch = $false
$mutex = $null
$haveLock = $false
$script:InstallFull = ''
$stagingFull = ''
$backupFull = ''

try {
    if ([string]::IsNullOrEmpty($LogFile)) {
        $LogFile = Join-Path ([System.IO.Path]::GetTempPath()) 'update-helper.log'
    }
    $script:LogPath = $LogFile
    try { [System.IO.File]::WriteAllText($script:LogPath, '') } catch { $script:LogPath = '' }
    Write-Log 'start'

    # --- 1. arguments ------------------------------------------------------
    foreach ($candidate in @($InstallDir, $StagingDir, $BackupDir)) {
        if (-not (Test-LocalAbsolutePath $candidate)) { throw (New-UpdateError 2 'path-not-local') }
    }
    if ($ProcessId -le 0) { throw (New-UpdateError 2 'bad-process-id') }
    if ($WaitSeconds -lt 1 -or $WaitSeconds -gt 600) { throw (New-UpdateError 2 'bad-wait') }
    if ([string]::IsNullOrEmpty($ExeName) -or
        [System.IO.Path]::GetFileName($ExeName) -ne $ExeName -or
        -not $ExeName.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase) -or
        $ExeName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw (New-UpdateError 2 'bad-exe-name')
    }

    $script:InstallFull = Get-NormalizedDirectory $InstallDir
    $stagingFull = Get-NormalizedDirectory $StagingDir
    $backupFull = Get-NormalizedDirectory $BackupDir
    foreach ($candidate in @($script:InstallFull, $stagingFull, $backupFull)) {
        if (Test-IsRoot $candidate) { throw (New-UpdateError 2 'path-is-root') }
    }
    # None of the three may contain or equal another: a mistake here could make
    # the clean-up delete the installed app.
    $dirs = @($script:InstallFull, $stagingFull, $backupFull)
    for ($a = 0; $a -lt $dirs.Count; $a++) {
        for ($b = 0; $b -lt $dirs.Count; $b++) {
            if ($a -ne $b -and (Test-SameOrInside -Child $dirs[$a] -Parent $dirs[$b])) {
                throw (New-UpdateError 2 'paths-overlap')
            }
        }
    }

    # --- single update per install folder ---------------------------------
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($script:InstallFull.ToLowerInvariant())
    $nameHash = [System.BitConverter]::ToString($sha.ComputeHash($nameBytes)).Replace('-', '').Substring(0, 32)
    $sha.Dispose()
    $mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, ('Local\update-helper-' + $nameHash)
    try {
        $haveLock = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $haveLock = $true
    }
    if (-not $haveLock) { throw (New-UpdateError 3 'another-update-running') }

    # --- 2. staged files and install folder, before anything is touched ----
    Test-Layout -Staging $stagingFull -Install $script:InstallFull -Exe $ExeName
    if (Test-Path -LiteralPath $backupFull) {
        # A leftover backup could be restored over newer files. Refuse it.
        if ((Test-Path -LiteralPath $backupFull -PathType Leaf) -or @(Get-ChildItem -LiteralPath $backupFull -Force).Count -gt 0) {
            throw (New-UpdateError 11 'backup-folder-not-empty')
        }
    }
    $stagedFiles = Get-RelativeFiles $stagingFull
    if ($stagedFiles.Count -lt 3) { throw (New-UpdateError 11 'staged-too-few-files') }
    if ($env:SystemRoot) {
        $candidatePath = Join-Path (Join-Path $env:SystemRoot 'System32') 'robocopy.exe'
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) { $script:Robocopy = $candidatePath }
    }
    Write-Log ('checked {0} staged files' -f $stagedFiles.Count)

    # --- 3. tell the app it may exit, then wait for it ---------------------
    Write-ReadyFile 'ready'
    $phase = 'waiting'
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)

    Wait-ForApp -Exe $ExeName -Id $ProcessId -Deadline $deadline
    Write-Log 'app exited'
    # Other windows of the app (a second instance) keep their files locked.
    while ($true) {
        $others = Get-InstallDirProcessIds
        if ($others.Count -eq 0) { break }
        if ([DateTime]::UtcNow -ge $deadline) { throw (New-UpdateError 10 'another-instance-running') }
        Start-Sleep -Milliseconds 500
    }
    Assert-NotCancelled
    # Handles of the exited process and of antivirus scans need a moment.
    Start-Sleep -Milliseconds 700

    # --- 4. swap -----------------------------------------------------------
    $phase = 'swap'
    Test-Layout -Staging $stagingFull -Install $script:InstallFull -Exe $ExeName

    # Back up only the files the update will overwrite. (A full copy of the
    # install folder could be gigabytes when the app sits in Downloads.)
    $backedUp = 0
    foreach ($rel in $stagedFiles) {
        $target = Join-Path $script:InstallFull $rel
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $copyTo = Join-Path $backupFull $rel
            $copyToDir = [System.IO.Path]::GetDirectoryName($copyTo)
            [void][System.IO.Directory]::CreateDirectory($copyToDir)
            Invoke-WithRetry { [System.IO.File]::Copy($target, $copyTo, $true) }
            $backedUp++
        }
    }
    [void][System.IO.Directory]::CreateDirectory($backupFull)
    Write-Log ('backed up {0} files' -f $backedUp)

    $touched = $true
    # A read-only attribute would make the overwrite fail.
    foreach ($rel in $stagedFiles) {
        $target = Join-Path $script:InstallFull $rel
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $attrs = [int][System.IO.File]::GetAttributes($target)
            if (($attrs -band 1) -ne 0) {
                [System.IO.File]::SetAttributes($target, [System.IO.FileAttributes]($attrs -band (-bnot 1)))
            }
        }
    }

    $copyCode = Invoke-Robocopy -Source $stagingFull -Destination $script:InstallFull
    if ($copyCode -ge 8) { throw (New-UpdateError 20 'copy-failed') }
    Write-Log ('copied, robocopy code {0}' -f $copyCode)

    foreach ($rel in $stagedFiles) {
        $source = Join-Path $stagingFull $rel
        $target = Join-Path $script:InstallFull $rel
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw (New-UpdateError 20 'verify-missing') }
        if ((Get-Item -LiteralPath $source -Force).Length -ne (Get-Item -LiteralPath $target -Force).Length) { throw (New-UpdateError 20 'verify-size') }
        if ((Get-FileSha256 $source) -ne (Get-FileSha256 $target)) { throw (New-UpdateError 20 'verify-hash') }
    }
    Write-Log ('verified {0} files' -f $stagedFiles.Count)

    $exitCode = 0
    $result = 'success'
    $relaunch = $true
} catch {
    $failure = $_.Exception
    $tag = Get-ErrorTag $_
    $code = 30
    if ($failure.Message.StartsWith('update:')) {
        $tag = $failure.Message.Substring(7)
        $code = [int]$failure.Data['code']
    }
    $exitCode = $code
    $result = 'aborted ' + $tag
    Write-Log ('failed in phase {0}: {1}' -f $phase, $tag)

    if ($phase -eq 'validate') {
        # The app is still running and nothing was changed. Tell it so.
        Write-ReadyFile ('abort ' + $tag)
    } elseif ($phase -eq 'waiting') {
        # Nothing was changed. An instance that is still running stays as it is;
        # otherwise the user gets the app back.
        $relaunch = ($tag -ne 'app-did-not-exit' -and $tag -ne 'another-instance-running' -and $tag -ne 'cancelled')
    } else {
        $relaunch = $true
        if ($touched) {
            Write-Log 'rolling back'
            try {
                $restoreCode = 0
                if (Test-Path -LiteralPath $backupFull -PathType Container) {
                    $restoreCode = Invoke-Robocopy -Source $backupFull -Destination $script:InstallFull
                }
                if ($restoreCode -ge 8) { throw 'restore failed' }
                $exitCode = 20
                $result = 'rolled-back ' + $tag
                Write-Log 'rolled back'
            } catch {
                $exitCode = 21
                $result = 'rollback-failed ' + $tag
                Write-Log ('rollback failed: ' + (Get-ErrorTag $_))
            }
        }
    }
} finally {
    try {
        if ($relaunch -and $script:InstallFull -ne '') {
            $exeToStart = Join-Path $script:InstallFull $ExeName
            $running = $false
            try { $running = ((Get-InstallDirProcessIds).Count -gt 0) } catch { $running = $false }
            if ((Test-Path -LiteralPath $exeToStart -PathType Leaf) -and -not $running) {
                Write-Log 'starting the app'
                Start-App $exeToStart
            }
        }
    } catch {
        Write-Log ('start failed: ' + (Get-ErrorTag $_))
    }

    if ($exitCode -eq 0) {
        # The update is in place; the staging and backup folders are not needed.
        foreach ($folder in @($stagingFull, $backupFull)) {
            try {
                if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) {
                    Remove-Item -LiteralPath $folder -Recurse -Force
                }
            } catch {
                Write-Log ('clean-up failed: ' + (Get-ErrorTag $_))
            }
        }
    }

    if ($haveLock -and $null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $mutex) { $mutex.Dispose() }
    Write-Log ('RESULT ' + $result)
}

exit $exitCode
''';
// END apply_update.ps1
