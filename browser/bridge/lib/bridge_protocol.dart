import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// What the app and the browser helper (browser/bridge/bin/khazna_bridge.dart) share. Plain
// Dart only: the helper is compiled on its own, without Flutter.
//
//   browser extension --native messaging--> khazna_bridge.exe
//                     --loopback TCP-->     the app (BrowserBridgeServer)
//
// Both links carry the same frames: a 4-byte little-endian length, then that
// many bytes of UTF-8 JSON (Chrome's native messaging format). The helper only
// adds one frame of its own at the start ({"t": "bridge", "token": ...}) and
// otherwise copies bytes both ways.

/// The native messaging host name the extension connects to.
const nativeHostName = 'app.khazna.bridge';

/// The extension's id. Fixed by the public key in extension/manifest.json, so
/// an unpacked copy loaded from any folder has the same id.
const extensionId = 'hanpnpoopbcidkdgeknbinmkhlkfmecf';

/// The only origin allowed to start the helper.
const extensionOrigin = 'chrome-extension://$extensionId/';

/// File name of the helper next to the app's exe.
const bridgeExeName = 'khazna_bridge.exe';

/// The largest frame either side accepts. Chrome refuses a message over 1 MiB
/// from a host; the app's answers are a few KiB.
const maxFrameBytes = 1024 * 1024;

/// Where the running app says how to reach it, and where the native messaging
/// manifest lives: `%LOCALAPPDATA%\Hisn\Browser` (only this user can read
/// it). `KHAZNA_BRIDGE_DIR` replaces it, for tests.
Directory? bridgeDirectory([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final override = env['KHAZNA_BRIDGE_DIR'];
  if (override != null && override.isNotEmpty) return Directory(override);
  final local = env['LOCALAPPDATA'];
  if (local == null || local.isEmpty) return null;
  return Directory(
    '$local${Platform.pathSeparator}Hisn'
    '${Platform.pathSeparator}Browser',
  );
}

/// The file in [bridgeDirectory] that the running app writes:
/// `{"v": 1, "port": <int>, "token": "<64 hex>", "pid": <int>}`.
File endpointFile(Directory dir) =>
    File('${dir.path}${Platform.pathSeparator}endpoint.json');

/// How to reach the running app, read from [endpointFile].
class BridgeEndpoint {
  const BridgeEndpoint({required this.port, required this.token, this.pid});

  final int port;
  final String token;
  final int? pid;

  Map<String, Object?> toJson() => {
    'v': 1,
    'port': port,
    'token': token,
    'pid': ?pid,
  };

  /// Null for anything that is not a version 1 endpoint.
  static BridgeEndpoint? tryParse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['v'] != 1) return null;
      final port = j['port'];
      final token = j['token'];
      if (port is! int || port <= 0 || port > 65535) return null;
      if (token is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
        return null;
      }
      final pid = j['pid'];
      return BridgeEndpoint(
        port: port,
        token: token,
        pid: pid is int ? pid : null,
      );
    } on FormatException {
      return null;
    }
  }
}

/// [message] as one frame.
Uint8List encodeFrame(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode(message));
  if (body.length > maxFrameBytes) {
    throw const FrameException('frame_too_large');
  }
  final out = Uint8List(4 + body.length);
  ByteData.sublistView(out).setUint32(0, body.length, Endian.little);
  out.setRange(4, out.length, body);
  return out;
}

/// A frame that is too large, or that is not a JSON object.
class FrameException implements Exception {
  const FrameException(this.code);

  final String code;

  @override
  String toString() => 'FrameException($code)';
}

/// Splits a byte stream into frames. Throws [FrameException] for a frame over
/// [maxBytes] (before reading it) or one that is not a JSON object; the
/// stream cannot be trusted after that.
class FrameDecoder {
  FrameDecoder({this.maxBytes = maxFrameBytes});

  final int maxBytes;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// The frames completed by [chunk], in order.
  List<Map<String, Object?>> add(List<int> chunk) {
    _buffer
      ..add(_pending)
      ..add(chunk);
    var data = _buffer.takeBytes();
    final out = <Map<String, Object?>>[];
    var pos = 0;
    while (data.length - pos >= 4) {
      final len = ByteData.sublistView(
        data,
        pos,
        pos + 4,
      ).getUint32(0, Endian.little);
      if (len > maxBytes) throw const FrameException('frame_too_large');
      if (data.length - pos - 4 < len) break;
      final body = Uint8List.sublistView(data, pos + 4, pos + 4 + len);
      pos += 4 + len;
      final Object? j;
      try {
        j = jsonDecode(utf8.decode(body));
      } on FormatException {
        throw const FrameException('bad_json');
      }
      if (j is! Map<String, Object?>) {
        throw const FrameException('not_an_object');
      }
      out.add(j);
    }
    data = Uint8List.sublistView(data, pos);
    _pending = Uint8List.fromList(data);
    return out;
  }
}

/// A short code both the extension and the app show while pairing, so the
/// user can see they are pairing the browser they think: six digits from the
/// SHA-256 of the extension's key (the extension computes the same).
String pairingCode(List<int> keySha256) {
  final n = (keySha256[0] << 16) | (keySha256[1] << 8) | keySha256[2];
  final s = (n % 1000000).toString().padLeft(6, '0');
  return '${s.substring(0, 3)} ${s.substring(3)}';
}
