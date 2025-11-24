import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/utils/property_normalizer.dart';

void main() {
  group('PropertyNormalizer', () {
    test('normalizes supported types correctly', () {
      final properties = <String, Object?>{
        'null_value': null,
        'bool_value': true,
        'int_value': 42,
        'double_value': 3.14,
        'string_value': 'hello',
      };

      final result = PropertyNormalizer.normalize(properties);

      // Null values are filtered out by the normalizer
      final expected = <String, Object?>{
        'bool_value': true,
        'int_value': 42,
        'double_value': 3.14,
        'string_value': 'hello',
      };

      expect(result, equals(expected));
    });

    test('converts unsupported types to strings', () {
      final customObject = DateTime(2023, 1, 1);
      final properties = <String, Object?>{
        'custom_object': customObject,
        'symbol': #test,
      };

      final result = PropertyNormalizer.normalize(properties);

      expect(result['custom_object'], equals(customObject.toString()));
      expect(result['symbol'], equals('Symbol("test")'));
    });

    test('normalizes multidimensional lists', () {
      final properties = <String, Object?>{
        'simple_list': [1, 2, 3],
        'mixed_list': [1, 'hello', true],
        '2d_list': [
          [1, 2],
          ['a', 'b']
        ],
      };

      final result = PropertyNormalizer.normalize(properties);

      expect(result['simple_list'], equals([1, 2, 3]));
      final mixedList = result['mixed_list'] as List;
      expect(mixedList[0], equals(1));
      expect(mixedList[1], equals('hello'));
      expect(mixedList[2], equals(true));
      expect(
          result['2d_list'],
          equals([
            [1, 2],
            ['a', 'b']
          ]));
    });

    test('normalizes nested maps', () {
      final properties = <String, Object?>{
        'nested_map': {
          'inner_string': 'value',
          'inner_number': 123,
          'deeply_nested': {
            'level2': {
              'level3': 'deep_value',
              1: 'deep_value',
            },
          },
        },
      };

      final result = PropertyNormalizer.normalize(properties);

      final nestedMap = result['nested_map'] as Map<String, dynamic>;
      expect(nestedMap['inner_string'], equals('value'));
      expect(nestedMap['inner_number'], equals(123));

      final deeplyNested = nestedMap['deeply_nested'] as Map<String, dynamic>;
      final level2 = deeplyNested['level2'] as Map<String, dynamic>;
      expect(level2['level3'], equals('deep_value'));
      expect(level2['1'], equals('deep_value'));
    });

    test('handles maps with non-string keys', () {
      final properties = {
        'map_with_int_keys': {
          1: 'one',
          2: 'two',
        },
      };

      final result = PropertyNormalizer.normalize(properties);

      final normalizedMap = result['map_with_int_keys'] as Map<String, dynamic>;
      expect(normalizedMap['1'], equals('one')); // Key converted to string
      expect(normalizedMap['2'], equals('two')); // Key converted to string
    });
  });
}
