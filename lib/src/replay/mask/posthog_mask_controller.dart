import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser_factory.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parsers_const.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data_factory.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_object_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/root_element_provider.dart';
import 'package:posthog_flutter/src/replay/mask/widget_elements_decipher.dart';
import 'package:posthog_flutter/src/util/logging.dart';

class PostHogMaskController {
  late final Map<String, ElementParser> parsers;

  final GlobalKey containerKey = GlobalKey();

  final WidgetElementsDecipher _widgetScraper;

  PostHogMaskController._privateConstructor(PostHogSessionReplayConfig? config)
      : _widgetScraper = WidgetElementsDecipher(
          elementDataFactory: ElementDataFactory(),
          elementObjectParser: ElementObjectParser(),
          rootElementProvider: RootElementProvider(),
        ) {
    parsers =
        ElementParsersConst(DefaultElementParserFactory(), config).parsersMap;
  }

  static final PostHogMaskController instance =
      PostHogMaskController._privateConstructor(
          Posthog().config?.sessionReplayConfig);

  /// Extracts a flattened list of [ElementData] objects representing the
  /// renderable elements in the widget tree.
  ///
  /// This method traverses the tree of [ElementData] objects and returns a
  /// list of elements that have no children or only one child.
  ///
  /// The method is designed to extract the elements that are directly
  /// renderable on the screen.
  ///
  /// **Returns:**
  ///   - `List<ElementData>`: A list of [ElementData] objects representing the
  ///     renderable elements.
  ///
  List<ElementData>? getCurrentWidgetsElements() {
    final context = containerKey.currentContext;

    if (context == null) {
      printIfDebug('Error: containerKey.currentContext is null.');
      return null;
    }

    try {
      final widgetElementsTree = _widgetScraper.parseRenderTree(context);

      if (widgetElementsTree == null) {
        printIfDebug('Error: widgetElementsTree is null after parsing.');
        return null;
      }

      return widgetElementsTree.extractRects();
    } catch (e) {
      printIfDebug(
          'Error during render tree parsing or rectangle extraction: $e');
      return null;
    }
  }

  List<Rect>? getPostHogWidgetWrapperElements() {
    final context = containerKey.currentContext;

    if (context == null) {
      printIfDebug('Error: containerKey.currentContext is null.');
      return null;
    }

    try {
      final widgetElementsTree = _widgetScraper.parseRenderTree(context);

      if (widgetElementsTree == null) {
        printIfDebug('Error: widgetElementsTree is null after parsing.');
        return null;
      }

      return widgetElementsTree.extractMaskWidgetRects();
    } catch (e) {
      printIfDebug(
          'Error during render tree parsing or rectangle extraction: $e');
      return null;
    }
  }
}
