import 'package:flutter/widgets.dart';

class RootElementProvider {
  Element? getRootElement(BuildContext context) {
    Element? rootElement;
    if (ModalRoute.of(context)?.isActive ?? false) {
      Navigator.of(context, rootNavigator: true)
          .context
          .visitChildElements((element) {
        rootElement = element;
      });
    } else {
      context.visitChildElements((element) {
        rootElement = element;
      });
    }
    return rootElement;
  }
}
