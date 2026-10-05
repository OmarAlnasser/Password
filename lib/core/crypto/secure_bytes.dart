import 'dart:typed_data';

/// Overwrites [bytes] with zeros.
///
/// Dart has no guaranteed memory wiping: the GC may already have copied the
/// buffer. We still zero every temporary buffer that held secret material so
/// that the window in which it is readable is as small as we can make it.
/// Long-lived keys never live in Dart buffers at all; they are kept in
/// libsodium secure memory (see `SecureKey`).
void wipe(Uint8List? bytes) {
  if (bytes == null) return;
  bytes.fillRange(0, bytes.length, 0);
}

/// Concatenates byte arrays into a new buffer.
Uint8List concatBytes(List<Uint8List> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final p in parts) {
    out.setRange(offset, offset + p.length, p);
    offset += p.length;
  }
  return out;
}
