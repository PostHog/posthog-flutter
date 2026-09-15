import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

void main(List<String> arguments) {
  final snapshot = File(arguments[0]);
  final packageRoot = Directory(arguments[1]).absolute.uri;
  final data = jsonDecode(snapshot.readAsStringSync()) as Map<String, dynamic>;
  annotateExperimentalAccessors(
    data,
    (path) => File.fromUri(packageRoot.resolve(path)).readAsStringSync(),
  );
  snapshot.writeAsStringSync(jsonEncode(data));
}

/// dart_apitool 0.23.2 reads annotations from synthetic fields, which omit
/// annotations declared on explicit accessors. Merge the class accessor
/// annotations into the generated property metadata.
void annotateExperimentalAccessors(
  Map<String, dynamic> snapshot,
  String Function(String path) readSource,
) {
  final sources = <String, Map<String, Set<String>>>{};
  final packageApi = snapshot['packageApi'] as Map<String, dynamic>;
  final interfaces = (packageApi['interfaceDeclarations'] as List)
      .cast<Map<String, dynamic>>();
  for (final interface in interfaces) {
    final fields =
        (interface['fieldDeclarations'] as List).cast<Map<String, dynamic>>();
    if (fields.isEmpty) continue;
    final path = interface['relativePath'] as String;
    final accessors = sources.putIfAbsent(
      path,
      () => _experimentalAccessors(readSource(path)),
    )[interface['name']];
    if (accessors == null) continue;
    for (final field in fields) {
      if (accessors.contains(field['name'])) {
        field['isExperimental'] = true;
      }
    }
  }
}

Map<String, Set<String>> _experimentalAccessors(String source) {
  final unit = parseString(content: source).unit;
  return {
    for (final declaration in unit.declarations.whereType<ClassDeclaration>())
      if (declaration.body case BlockClassBody body)
        declaration.namePart.typeName.lexeme: {
          for (final member in body.members.whereType<MethodDeclaration>())
            if ((member.isGetter || member.isSetter) &&
                member.metadata.any(
                    (annotation) => annotation.name.name == 'experimental'))
              member.name.lexeme,
        },
  };
}
