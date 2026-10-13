import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_desktop_time_zone.dart';

void main() {
  group('DesktopTimeZone.read', () {
    test('reads the zone TZ names', () {
      expect(DesktopTimeZone.read({'TZ': 'Europe/Berlin'}), 'Europe/Berlin');
    });

    test('reads /etc/localtime when TZ names no zone', () {
      expect(
        DesktopTimeZone.read({'TZ': 'CET-1CEST,M3.5.0,M10.5.0/3'}),
        DesktopTimeZone.read(const {}),
      );
    }, testOn: '!windows');

    test('Windows reads the system IANA time zone', () {
      final zone = DesktopTimeZone.read(const {});
      expect(zone, isNotNull);
      expect(zone, isNot('Etc/Unknown'));
      expect(DesktopTimeZone.fromTzVariable(zone), zone);
    }, testOn: 'windows');
  });

  group('DesktopTimeZone.fromTzVariable', () {
    const zoneByValue = <String, String>{
      'Europe/Berlin': 'Europe/Berlin',
      ':Europe/Berlin': 'Europe/Berlin',
      'America/Argentina/Buenos_Aires': 'America/Argentina/Buenos_Aires',
      'America/Port-au-Prince': 'America/Port-au-Prince',
      'UTC': 'UTC',
      'Etc/GMT+10': 'Etc/GMT+10',
      'GMT0': 'GMT0',
      'EST5EDT': 'EST5EDT',
      'posix/Asia/Tokyo': 'Asia/Tokyo',
      ':/usr/share/zoneinfo/Asia/Tokyo': 'Asia/Tokyo',
    };

    zoneByValue.forEach((value, zone) {
      test('reads $zone from "$value"', () {
        expect(DesktopTimeZone.fromTzVariable(value), zone);
      });
    });

    const noZone = <String>[
      '',
      'CET-1CEST,M3.5.0,M10.5.0/3',
      'JST-9',
      '<+03>-3',
      ':/etc/localtime',
    ];

    for (final value in noZone) {
      test('reads no zone from "$value"', () {
        expect(DesktopTimeZone.fromTzVariable(value), isNull);
      });
    }

    test('reads no zone without the variable', () {
      expect(DesktopTimeZone.fromTzVariable(null), isNull);
    });
  });

  group('DesktopTimeZone.fromTimezoneFile', () {
    test('reads the zone the file names', () {
      expect(
          DesktopTimeZone.fromTimezoneFile('Europe/Berlin\n'), 'Europe/Berlin');
      expect(DesktopTimeZone.fromTimezoneFile(' Etc/UTC '), 'Etc/UTC');
    });

    test('reads no zone from an empty file or a POSIX rule', () {
      expect(DesktopTimeZone.fromTimezoneFile(''), isNull);
      expect(DesktopTimeZone.fromTimezoneFile('JST-9\n'), isNull);
    });
  });

  group('DesktopTimeZone.fromZoneInfoPath', () {
    test('reads the zone after the zoneinfo directory', () {
      expect(
        DesktopTimeZone.fromZoneInfoPath('/usr/share/zoneinfo/Europe/Berlin'),
        'Europe/Berlin',
      );
      expect(
        DesktopTimeZone.fromZoneInfoPath(
          '/nix/store/abc-tzdata-2024a/share/zoneinfo/Etc/UTC',
        ),
        'Etc/UTC',
      );
    });

    test('reads no zone from a file outside a zoneinfo directory', () {
      expect(DesktopTimeZone.fromZoneInfoPath('/etc/localtime'), isNull);
    });
  });
}
