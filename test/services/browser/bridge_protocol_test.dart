import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazna_bridge/bridge_protocol.dart';

void main() {
  group('frames', () {
    test('round trip, split anywhere, several per chunk', () {
      final a = encodeFrame({'t': 'hello', 'n': 1});
      final b = encodeFrame({'t': 'list', 'url': 'https://example.test/é'});
      final all = Uint8List.fromList([...a, ...b]);
      for (var cut = 0; cut <= all.length; cut++) {
        final d = FrameDecoder();
        final got = [...d.add(all.sublist(0, cut)), ...d.add(all.sublist(cut))];
        expect(got, [
          {'t': 'hello', 'n': 1},
          {'t': 'list', 'url': 'https://example.test/é'},
        ], reason: 'cut at $cut');
      }
    });

    test('the length is little-endian, like native messaging on x86', () {
      final f = encodeFrame({'a': 1});
      final body = utf8.encode('{"a":1}');
      expect(f.sublist(0, 4), [body.length, 0, 0, 0]);
      expect(f.sublist(4), body);
    });

    test('a frame over the limit is refused before it is read', () {
      final d = FrameDecoder(maxBytes: 16);
      final header = Uint8List(4);
      ByteData.sublistView(header).setUint32(0, 17, Endian.little);
      expect(() => d.add(header), throwsA(isA<FrameException>()));
    });

    test('not JSON, or not an object, is refused', () {
      Uint8List frame(String text) {
        final body = utf8.encode(text);
        final out = Uint8List(4 + body.length);
        ByteData.sublistView(out).setUint32(0, body.length, Endian.little);
        out.setRange(4, out.length, body);
        return out;
      }

      expect(
        () => FrameDecoder().add(frame('{oops')),
        throwsA(isA<FrameException>()),
      );
      expect(
        () => FrameDecoder().add(frame('[1,2]')),
        throwsA(isA<FrameException>()),
      );
    });
  });

  test('endpoint: only a well-formed version 1 file is read', () {
    const token =
        '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
    final ok = BridgeEndpoint.tryParse(
      jsonEncode({'v': 1, 'port': 5000, 'token': token, 'pid': 7}),
    );
    expect(ok?.port, 5000);
    expect(ok?.token, token);
    expect(ok?.pid, 7);
    for (final bad in [
      '',
      'nope',
      '[]',
      jsonEncode({'v': 2, 'port': 5000, 'token': token}),
      jsonEncode({'v': 1, 'port': 0, 'token': token}),
      jsonEncode({'v': 1, 'port': 70000, 'token': token}),
      jsonEncode({'v': 1, 'port': 5000, 'token': 'short'}),
      jsonEncode({'v': 1, 'port': 5000, 'token': token.toUpperCase()}),
    ]) {
      expect(BridgeEndpoint.tryParse(bad), isNull, reason: bad);
    }
  });

  test('the bridge folder', () {
    expect(bridgeDirectory({'KHAZNA_BRIDGE_DIR': '/x/y'})?.path, '/x/y');
    expect(bridgeDirectory({'LOCALAPPDATA': 'C:/L'})?.path, contains('Hisn'));
    expect(bridgeDirectory(const {}), isNull);
  });

  test(
    'pairing code: six digits from the key hash (the extension matches)',
    () {
      final digest = sha256.convert(List.filled(32, 7)).bytes;
      final code = pairingCode(digest);
      expect(code, matches(RegExp(r'^\d{3} \d{3}$')));
      final n = ((digest[0] << 16) | (digest[1] << 8) | digest[2]) % 1000000;
      expect(code.replaceAll(' ', ''), n.toString().padLeft(6, '0'));
      expect(pairingCode([0, 0, 1]), '000 001');
    },
  );
}
