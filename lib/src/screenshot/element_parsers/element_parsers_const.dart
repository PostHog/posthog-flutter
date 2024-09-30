import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/screenshot/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/screenshot/element_parsers/element_parser_factory.dart';

class ElementParsersConst {
  final ElementParserFactory _factory;
  final Map<String, ElementParser> parsersMap = {};

  ElementParsersConst(this._factory) {
    registerElementParser<RenderImage>();
    registerElementParser<RenderParagraph>();
    registerElementParser<RenderTransform>();
  }

  void registerElementParser<T>() {
    parsersMap[getRuntimeType<T>()] = _factory.createElementParser(T);
  }

  ElementParser? getParserForType(Type type) {
    return parsersMap[getRuntimeTypeForType(type)];
  }

  static String getRuntimeType<T>() => T.toString();

  static String getRuntimeTypeForType(Type type) => type.toString();
}
