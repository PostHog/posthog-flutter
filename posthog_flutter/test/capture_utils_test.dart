import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/utils/capture_utils.dart';

void main() {
  group('CaptureUtils.extractUserProperties', () {
    test('returns null values when all inputs are null', () {
      final result = CaptureUtils.extractUserProperties(
        properties: null,
        userProperties: null,
        userPropertiesSetOnce: null,
      );

      expect(result.properties, isNull);
      expect(result.userProperties, isNull);
      expect(result.userPropertiesSetOnce, isNull);
    });

    test('passes through properties without \$set or \$set_once', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {'event_key': 'event_value', 'count': 42},
        userProperties: null,
        userPropertiesSetOnce: null,
      );

      expect(result.properties, {'event_key': 'event_value', 'count': 42});
      expect(result.userProperties, isNull);
      expect(result.userPropertiesSetOnce, isNull);
    });

    test('passes through userProperties and userPropertiesSetOnce', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {'event_key': 'event_value'},
        userProperties: {'name': 'John'},
        userPropertiesSetOnce: {'created_at': '2024-01-01'},
      );

      expect(result.properties, {'event_key': 'event_value'});
      expect(result.userProperties, {'name': 'John'});
      expect(result.userPropertiesSetOnce, {'created_at': '2024-01-01'});
    });

    test('extracts \$set from properties for backward compatibility', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          '\$set': {'name': 'John', 'plan': 'premium'},
        },
        userProperties: null,
        userPropertiesSetOnce: null,
      );

      expect(result.properties, {'event_key': 'event_value'});
      expect(result.userProperties, {'name': 'John', 'plan': 'premium'});
      expect(result.userPropertiesSetOnce, isNull);
    });

    test('extracts \$set_once from properties for backward compatibility', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          '\$set_once': {'created_at': '2024-01-01'},
        },
        userProperties: null,
        userPropertiesSetOnce: null,
      );

      expect(result.properties, {'event_key': 'event_value'});
      expect(result.userProperties, isNull);
      expect(result.userPropertiesSetOnce, {'created_at': '2024-01-01'});
    });

    test('extracts both \$set and \$set_once from properties', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          '\$set': {'name': 'John'},
          '\$set_once': {'created_at': '2024-01-01'},
        },
        userProperties: null,
        userPropertiesSetOnce: null,
      );

      expect(result.properties, {'event_key': 'event_value'});
      expect(result.userProperties, {'name': 'John'});
      expect(result.userPropertiesSetOnce, {'created_at': '2024-01-01'});
    });

    test('merges legacy \$set with userProperties', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          '\$set': {'name': 'John', 'city': 'NYC'},
        },
        userProperties: {'plan': 'premium'},
        userPropertiesSetOnce: null,
      );

      expect(result.properties, {'event_key': 'event_value'});
      expect(result.userProperties, {
        'name': 'John',
        'city': 'NYC',
        'plan': 'premium',
      });
      expect(result.userPropertiesSetOnce, isNull);
    });

    test('merges legacy \$set_once with userPropertiesSetOnce', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          '\$set_once': {'created_at': '2024-01-01'},
        },
        userProperties: null,
        userPropertiesSetOnce: {'first_login': '2024-01-02'},
      );

      expect(result.properties, {'event_key': 'event_value'});
      expect(result.userProperties, isNull);
      expect(result.userPropertiesSetOnce, {
        'created_at': '2024-01-01',
        'first_login': '2024-01-02',
      });
    });

    test('new parameters take precedence over legacy \$set values', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          '\$set': {'name': 'John', 'plan': 'free'},
        },
        userProperties: {'plan': 'premium'}, // should override 'free'
        userPropertiesSetOnce: null,
      );

      expect(result.properties, {'event_key': 'event_value'});
      expect(result.userProperties, {
        'name': 'John',
        'plan': 'premium', // new value takes precedence
      });
      expect(result.userPropertiesSetOnce, isNull);
    });

    test('new parameters take precedence over legacy \$set_once values', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          '\$set_once': {'created_at': '2024-01-01', 'source': 'web'},
        },
        userProperties: null,
        userPropertiesSetOnce: {'source': 'mobile'}, // should override 'web'
      );

      expect(result.properties, {'event_key': 'event_value'});
      expect(result.userProperties, isNull);
      expect(result.userPropertiesSetOnce, {
        'created_at': '2024-01-01',
        'source': 'mobile', // new value takes precedence
      });
    });

    test('handles empty properties map', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {},
        userProperties: {'name': 'John'},
        userPropertiesSetOnce: null,
      );

      expect(result.properties, {});
      expect(result.userProperties, {'name': 'John'});
      expect(result.userPropertiesSetOnce, isNull);
    });

    test('ignores \$set if not a Map', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          '\$set': 'not a map',
        },
        userProperties: null,
        userPropertiesSetOnce: null,
      );

      expect(result.properties, {
        'event_key': 'event_value',
        '\$set': 'not a map', // kept as-is since it's not a Map
      });
      expect(result.userProperties, isNull);
      expect(result.userPropertiesSetOnce, isNull);
    });

    test('ignores \$set_once if not a Map', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          '\$set_once': 123,
        },
        userProperties: null,
        userPropertiesSetOnce: null,
      );

      expect(result.properties, {
        'event_key': 'event_value',
        '\$set_once': 123, // kept as-is since it's not a Map
      });
      expect(result.userProperties, isNull);
      expect(result.userPropertiesSetOnce, isNull);
    });

    test('does not modify the original properties map', () {
      final originalProperties = {
        'event_key': 'event_value',
        '\$set': {'name': 'John'},
      };

      CaptureUtils.extractUserProperties(
        properties: originalProperties,
        userProperties: null,
        userPropertiesSetOnce: null,
      );

      // Original map should remain unchanged
      expect(originalProperties, {
        'event_key': 'event_value',
        '\$set': {'name': 'John'},
      });
    });

    test('handles complex merge scenario', () {
      final result = CaptureUtils.extractUserProperties(
        properties: {
          'event_key': 'event_value',
          'other_key': 123,
          '\$set': {'a': 1, 'b': 2, 'c': 3},
          '\$set_once': {'x': 'old_x', 'y': 'old_y'},
        },
        userProperties: {'b': 20, 'd': 4}, // b overrides, d is new
        userPropertiesSetOnce: {
          'x': 'new_x',
          'z': 'new_z'
        }, // x overrides, z is new
      );

      expect(result.properties, {
        'event_key': 'event_value',
        'other_key': 123,
      });
      expect(result.userProperties, {
        'a': 1,
        'b': 20, // overridden
        'c': 3,
        'd': 4, // new
      });
      expect(result.userPropertiesSetOnce, {
        'x': 'new_x', // overridden
        'y': 'old_y',
        'z': 'new_z', // new
      });
    });
  });
}
