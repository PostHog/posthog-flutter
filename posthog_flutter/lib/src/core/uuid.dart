import 'dart:math';
import 'dart:typed_data';

/// Generates a UUID version 7 (RFC 9562): a millisecond Unix timestamp
/// followed by random bits.
///
/// The ids generated in one isolate sort lexically in the order they were
/// generated, also within one millisecond and when the wall clock steps
/// back: the random bits then continue as a counter (RFC 9562, section 6.2,
/// method 2). Queue file names rely on this order.
String generateUuidV7() => _generator.next();

final _generator = _UuidV7Generator();

class _UuidV7Generator {
  final _random = Random.secure();

  /// The 74 bits between the timestamp and the end of the id that are not
  /// version or variant bits, big-endian.
  final _counter = Uint8List(10);

  /// The bits of counter byte [i] that are part of the counter: bytes 0 and
  /// 2 share the id's bytes with the version and the variant.
  static int _counterMask(int i) =>
      switch (i) { 0 => 0x0f, 2 => 0x3f, _ => 0xff };

  int _millis = -1;

  String next() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > _millis) {
      _millis = now;
      _reseed();
    } else if (!_increment()) {
      // All 74 bits used up within one millisecond: move to the next one.
      _millis++;
      _reseed();
    }
    return _format();
  }

  void _reseed() {
    for (var i = 0; i < _counter.length; i++) {
      _counter[i] = _random.nextInt(256) & _counterMask(i);
    }
  }

  /// Adds one to the counter. Returns false when it wraps around to zero.
  bool _increment() {
    for (var i = _counter.length - 1; i >= 0; i--) {
      _counter[i] = (_counter[i] + 1) & _counterMask(i);
      if (_counter[i] != 0) return true;
    }
    return false;
  }

  String _format() {
    final bytes = Uint8List(16);
    var millis = _millis;
    for (var i = 5; i >= 0; i--) {
      bytes[i] = millis % 256;
      millis ~/= 256;
    }
    bytes[6] = 0x70 | _counter[0]; // version 7
    bytes[7] = _counter[1];
    bytes[8] = 0x80 | _counter[2]; // variant 10xx
    bytes.setRange(9, 16, _counter, 3);

    final hex = [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
