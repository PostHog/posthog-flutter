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
                  'stable'
                ])
                  {'name': name, 'isExperimental': false},
                {'name': 'plainField', 'isExperimental': true},
              ],
            },
            {
              'name': 'OtherConfig',
              'relativePath': 'lib/config.dart',
              'fieldDeclarations': [
                {'name': 'paired', 'isExperimental': false},
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
}

class OtherConfig {
  int get paired => 1;
  set paired(int value) {}
}
''';

  test('experimental accessors are recorded as experimental properties', () {
    final api = snapshot();
    final reads = <String>[];
    annotateExperimentalAccessors(api, (path) {
      reads.add(path);
      return source;
    });

    final packageApi = api['packageApi'] as Map<String, dynamic>;
    final interfaces = (packageApi['interfaceDeclarations'] as List)
        .cast<Map<String, dynamic>>();
    final fields = (interfaces.first['fieldDeclarations'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      {for (final field in fields) field['name']: field['isExperimental']},
      {
        'getterOnly': true,
        'setterOnly': true,
        'paired': true,
        'stable': false,
        'plainField': true,
      },
    );
    expect(interfaces.last['fieldDeclarations'], [
      {'name': 'paired', 'isExperimental': false},
    ]);
    expect(reads, ['lib/config.dart']);
  });

  test('removing accessor annotations leaves regenerated properties stable',
      () {
    final api = snapshot();
    annotateExperimentalAccessors(
        api, (_) => source.replaceAll('@experimental', ''));

    final packageApi = api['packageApi'] as Map<String, dynamic>;
    final interfaces = (packageApi['interfaceDeclarations'] as List)
        .cast<Map<String, dynamic>>();
    final fields = (interfaces.first['fieldDeclarations'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      fields
          .where((field) => field['name'] != 'plainField')
          .every((field) => field['isExperimental'] == false),
      isTrue,
    );
  });
}
