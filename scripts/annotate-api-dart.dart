import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

void main(List<String> arguments) {
  final snapshot = File(arguments[0]);
  final packageRoot = Directory(arguments[1]).absolute.uri;
  final data = jsonDecode(snapshot.readAsStringSync()) as Map<String, dynamic>;
  annotateAccessors(
    data,
    (path) => File.fromUri(packageRoot.resolve(path)).readAsStringSync(),
  );
  snapshot.writeAsStringSync(jsonEncode(data));
}

/// dart_apitool 0.23.2 reads annotations from synthetic fields, which omit
/// annotations declared on explicit accessors. Merge the class accessor
/// annotations into the generated property metadata.
void annotateAccessors(
  Map<String, dynamic> snapshot,
  String Function(String path) readSource,
) {
  final sources = <String, Map<String, Map<String, Set<String>>>>{};
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
      () => _accessorFlags(readSource(path)),
    )[interface['name']];
    if (accessors == null) continue;
    for (final field in fields) {
      for (final flag in accessors[field['name']] ?? const <String>{}) {
        field[flag] = true;
      }
    }
  }
}

const _annotationFlags = {
  'experimental': 'isExperimental',
  'Deprecated': 'isDeprecated',
  'deprecated': 'isDeprecated',
};

Map<String, Map<String, Set<String>>> _accessorFlags(String source) {
  final unit = parseString(content: source).unit;
  final result = <String, Map<String, Set<String>>>{};
  for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
    if (declaration.body case BlockClassBody body) {
      final accessors = result[declaration.namePart.typeName.lexeme] =
          <String, Set<String>>{};
      for (final member in body.members.whereType<MethodDeclaration>()) {
        if (!member.isGetter && !member.isSetter) continue;
        for (final annotation in member.metadata) {
          final flag = _annotationFlags[annotation.name.name];
          if (flag == null) continue;
          accessors.putIfAbsent(member.name.lexeme, () => {}).add(flag);
        }
      }
    }
  }
  return result;
}
