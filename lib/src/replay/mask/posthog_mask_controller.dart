import 'dart:async';

import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser_factory.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parsers_const.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data_factory.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_object_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/root_element_provider.dart';
import 'package:posthog_flutter/src/replay/mask/widget_elements_decipher.dart';

class PostHogMaskController {
  late final Map<String, ElementParser> parsers;

  final GlobalKey containerKey = GlobalKey();

  final WidgetElementsDecipher _widgetScraper;

  PostHogMaskController._privateConstructor(PostHogSessionReplayConfig config)
      : _widgetScraper = WidgetElementsDecipher(
          elementDataFactory: ElementDataFactory(),
          elementObjectParser: ElementObjectParser(),
          rootElementProvider: RootElementProvider(),
        ) {
    parsers = ElementParsersConst(DefaultElementParserFactory(), config).parsersMap;
  }

  static final PostHogMaskController instance =
      PostHogMaskController._privateConstructor(Posthog().config!.postHogSessionReplayConfig);

  Future<List<Rect>?> getCurrentScreenRects() async {
    final BuildContext? context = containerKey.currentContext;

    if (context == null) {
      return null;
    }
    final ElementData? widgetElementsTree = _widgetScraper.parseRenderTree(context);

    return widgetElementsTree?.extractRects();
  }
}
