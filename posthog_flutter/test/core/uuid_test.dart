import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/uuid.dart';

void main() {
  group('generateUuidV7', () {
    test('produces the RFC 9562 version-7 layout', () {
      final uuid = generateUuidV7();

      expect(uuid, hasLength(36));
      // Version nibble 7, variant bits 10.
      expect(
          uuid,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('starts with the current Unix time in milliseconds', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final uuid = generateUuidV7();
      final after = DateTime.now().millisecondsSinceEpoch;

      final millis =
          int.parse(uuid.replaceAll('-', '').substring(0, 12), radix: 16);
      expect(millis, inInclusiveRange(before, after));
    });

    test('produces unique values', () {
      final uuids = List.generate(1000, (_) => generateUuidV7());

      expect(uuids.toSet(), hasLength(1000));
    });

    test('sorts lexicographically across milliseconds', () async {
      final earlier = generateUuidV7();
      // The version-7 prefix is a millisecond timestamp, so ordering only
      // shows up once the clock has actually ticked.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final later = generateUuidV7();

      expect(later.compareTo(earlier), greaterThan(0));
    });

    test('sorts lexicographically within a millisecond', () {
      final uuids = List.generate(10000, (_) => generateUuidV7());
      final timestamps = {for (final uuid in uuids) uuid.substring(0, 13)};

      expect(timestamps.length, lessThan(uuids.length),
          reason: 'the probe needs ids that share a millisecond');
      for (var i = 1; i < uuids.length; i++) {
        expect(uuids[i].compareTo(uuids[i - 1]), greaterThan(0),
            reason: '${uuids[i]} was generated after ${uuids[i - 1]}');
      }
    });
  });
}
