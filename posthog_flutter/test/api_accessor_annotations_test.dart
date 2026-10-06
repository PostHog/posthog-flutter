import 'package:flutter_test/flutter_test.dart';

import '../../scripts/annotate-api-dart.dart';

void main() {
  Map<String, dynamic> snapshot() => {
        'packageApi': {
          'interfaceDeclarations': [
            {
              'name': 'Config',
              'relativePath': 'lib/config.dart',
              'fieldDeclarations': [
                for (final name in [
                  'getterOnly',
                  'setterOnly',
                  'paired',
                  'stable',
                  'deprecatedGetter',
                  'deprecatedSetter',
                ])
                  {
                    'name': name,
                    'isExperimental': false,
                    'isDeprecated': false
                  },
                {
                  'name': 'plainField',
                  'isExperimental': true,
                  'isDeprecated': false
                },
              ],
            },
            {
              'name': 'OtherConfig',
              'relativePath': 'lib/config.dart',
              'fieldDeclarations': [
                {
                  'name': 'paired',
                  'isExperimental': false,
                  'isDeprecated': false
                },
              ],
            },
          ],
        },
      };

  const source = '''
import 'package:meta/meta.dart';

class Config {
  @experimental
  int get getterOnly => 1;

  @experimental
  set setterOnly(int value) {}

  int get paired => 1;
  @experimental
  set paired(int value) {}

  // @experimental is not an annotation on this property.
  int get stable => 1;
  set stable(int value) {}

  @experimental
  int plainField = 1;

  @Deprecated('Use paired instead.')
  int get deprecatedGetter => 1;
  @Deprecated('Use paired instead.')
  set deprecatedGetter(int value) {}

  int get deprecatedSetter => 1;
  @deprecated
  set deprecatedSetter(int value) {}
}

class OtherConfig {
  int get paired => 1;
  set paired(int value) {}
}
''';

  test('accessor annotations are recorded on their properties', () {
    final api = snapshot();
    final reads = <String>[];
    annotateAccessors(api, (path) {
      reads.add(path);
      return source;
    });

    final packageApi = api['packageApi'] as Map<String, dynamic>;
    final interfaces = (packageApi['interfaceDeclarations'] as List)
        .cast<Map<String, dynamic>>();
    final fields = (interfaces.first['fieldDeclarations'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      {
        for (final field in fields)
          field['name']: (field['isExperimental'], field['isDeprecated'])
      },
      {
        'getterOnly': (true, false),
        'setterOnly': (true, false),
        'paired': (true, false),
        'stable': (false, false),
        'deprecatedGetter': (false, true),
        'deprecatedSetter': (false, true),
        'plainField': (true, false),
      },
    );
    expect(interfaces.last['fieldDeclarations'], [
      {'name': 'paired', 'isExperimental': false, 'isDeprecated': false},
    ]);
    expect(reads, ['lib/config.dart']);
  });

  test('removing accessor annotations leaves regenerated properties stable',
      () {
    final api = snapshot();
    annotateAccessors(
      api,
      (_) => source
          .replaceAll('@experimental', '')
          .replaceAll(RegExp(r"@Deprecated\('[^']*'\)"), '')
          .replaceAll('@deprecated', ''),
    );

    final packageApi = api['packageApi'] as Map<String, dynamic>;
    final interfaces = (packageApi['interfaceDeclarations'] as List)
        .cast<Map<String, dynamic>>();
    final fields = (interfaces.first['fieldDeclarations'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      fields.where((field) => field['name'] != 'plainField').every((field) =>
          field['isExperimental'] == false && field['isDeprecated'] == false),
      isTrue,
    );
  });
}
