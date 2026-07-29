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
  Map<String, ElementParser> parsers;

  final GlobalKey containerKey = GlobalKey();

  final WidgetElementsDecipher _widgetScraper;

  PostHogMaskController._privateConstructor(PostHogSessionReplayConfig? config)
      : parsers = _buildParsers(config),
        _widgetScraper = WidgetElementsDecipher(
          elementDataFactory: ElementDataFactory(),
          elementObjectParser: ElementObjectParser(),
          rootElementProvider: RootElementProvider(),
        );

  static Map<String, ElementParser> _buildParsers(
    PostHogSessionReplayConfig? config,
  ) {
    return ElementParsersConst(
      DefaultElementParserFactory(),
      config,
    ).parsersMap;
  }

  /// Rebuilds the parser map for [config]. The singleton captures the config
  /// present at first access, which a later `setup()` with different masking
  /// flags would otherwise never update.
  void refreshParsers(PostHogSessionReplayConfig? config) {
    parsers = _buildParsers(config);
  }

  static final PostHogMaskController instance =
      PostHogMaskController._privateConstructor(
    Posthog().config?.sessionReplayConfig,
  );

  /// Extracts a flattened list of [ElementData] objects for every element in
  /// the widget tree that matched a masking rule, at any depth.
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
        'Error during render tree parsing or rectangle extraction: $e',
      );
      return null;
    }
  }

  /// Single-walk variant used by web canvas masking: one [parseRenderTree]
  /// producing both the explicit-mask set and (optionally) the full text/image
  /// set, instead of two separate walks. Returns null when the tree can't be
  /// walked (no [PostHogWidget] mounted, or parsing failed) so callers can
  /// fail closed.
  List<ElementData>? getMaskElements({required bool includeAllWidgets}) {
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

      return [
        ...widgetElementsTree.extractMaskWidgetRects(),
        if (includeAllWidgets) ...widgetElementsTree.extractRects(),
      ];
    } catch (e) {
      printIfDebug(
        'Error during render tree parsing or rectangle extraction: $e',
      );
      return null;
    }
  }

  List<ElementData>? getPostHogWidgetWrapperElements() {
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
        'Error during render tree parsing or rectangle extraction: $e',
      );
      return null;
    }
  }
}
