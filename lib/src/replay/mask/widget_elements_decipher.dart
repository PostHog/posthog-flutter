import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data_factory.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_object_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/root_element_provider.dart';

class WidgetElementsDecipher {
  late ElementData _rootElementData;

  final ElementDataFactory _elementDataFactory;
  final ElementObjectParser _elementObjectParser;
  final RootElementProvider _rootElementProvider;

  WidgetElementsDecipher({
    required ElementDataFactory elementDataFactory,
    required ElementObjectParser elementObjectParser,
    required RootElementProvider rootElementProvider,
  })  : _elementDataFactory = elementDataFactory,
        _elementObjectParser = elementObjectParser,
        _rootElementProvider = rootElementProvider;

  ElementData? parseRenderTree(
    BuildContext context,
  ) {
    final rootElement = _rootElementProvider.getRootElement(context);
    if (rootElement == null) return null;

    final rootElementData =
        _elementDataFactory.createFromElement(rootElement, "Root");
    if (rootElementData == null) return null;

    _rootElementData = rootElementData;

    _parseAllElements(
      _rootElementData,
      rootElement,
    );

    return _rootElementData;
  }

  void _parseAllElements(
    ElementData activeElementData,
    Element element,
  ) {
    ElementData? newElementData =
        _elementObjectParser.relateRenderObject(activeElementData, element);

    element.debugVisitOnstageChildren((childElement) {
      _parseAllElements(
        newElementData ?? activeElementData,
        childElement,
      );
    });
  }
}
