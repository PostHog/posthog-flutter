import 'dart:async';

import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_options.dart';
import 'package:posthog_flutter/src/screenshot/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/screenshot/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/screenshot/element_parsers/element_parser_factory.dart';
import 'package:posthog_flutter/src/screenshot/element_parsers/element_parsers_const.dart';
import 'package:posthog_flutter/src/screenshot/mask/element_data_factory.dart';
import 'package:posthog_flutter/src/screenshot/mask/element_object_parser.dart';
import 'package:posthog_flutter/src/screenshot/mask/root_element_provider.dart';
import 'package:posthog_flutter/src/screenshot/mask/widget_elements_decipher.dart';

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
      PostHogMaskController._privateConstructor(PostHogConfig().options.sessionReplayConfig!);

  Future<List<Rect>?> getCurrentScreenRects() async {
    final BuildContext? context = containerKey.currentContext;

    if (context == null) {
      return null;
    }
    final ElementData? widgetElementsTree = _widgetScraper.parseRenderTree(context);

    return _extractRects(widgetElementsTree);
  }

  List<Rect> _extractRects(ElementData? node, [bool isRoot = true]) {
    List<Rect> rects = [];

    if (!isRoot) {
      rects.add(node!.rect);
    }

    for (var child in node!.children!) {
      if (child.children == null) {
        rects.add(child.rect);
        continue;
      }
      if (child.children!.length > 1) {
        for (var grandChild in child.children!) {
          rects.add(grandChild.rect);
        }
      } else {
        rects.add(child.rect);
      }
    }

    return rects;
  }
}
