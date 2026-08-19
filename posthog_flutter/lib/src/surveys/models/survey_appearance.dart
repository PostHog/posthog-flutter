import 'dart:math' show sqrt;

import 'package:flutter/material.dart';

import '../../util/logging.dart';
import 'posthog_display_survey_appearance.dart';

/// Appearance configuration for survey widgets
@immutable
class SurveyAppearance {
  const SurveyAppearance({
    this.backgroundColor = Colors.white,
    this.submitButtonColor = Colors.black,
    this.submitButtonText = 'Submit',
    this.submitButtonTextColor = Colors.white,
    this.descriptionTextColor = Colors.black,
    this.questionTextColor = Colors.black,
    this.closeButtonColor = Colors.black,
    this.ratingButtonColor = const Color(0xFFEEEEEE),
    this.ratingButtonActiveColor = Colors.black,
    this.ratingButtonSelectedTextColor = Colors.white,
    this.ratingButtonUnselectedTextColor = const Color(0x80000000),
    this.displayThankYouMessage = true,
    this.thankYouMessageHeader = 'Thank you for your feedback!',
    this.thankYouMessageDescription,
    this.thankYouMessageCloseButtonText = 'Close',
    this.borderColor = const Color(0xFFBDBDBD),
    this.inputBackgroundColor = Colors.white,
    this.inputTextColor = Colors.black,
    this.inputPlaceholderColor = const Color(0xFF757575),
    this.choiceButtonBorderColor = Colors.black,
    this.choiceButtonTextColor = Colors.black,
  });

  final Color backgroundColor;
  final Color submitButtonColor;
  final String submitButtonText;
  final Color submitButtonTextColor;
  final Color descriptionTextColor;
  final Color questionTextColor;
  final Color closeButtonColor;
  final Color ratingButtonColor;
  final Color ratingButtonActiveColor;
  final Color ratingButtonSelectedTextColor;
  final Color ratingButtonUnselectedTextColor;
  final bool displayThankYouMessage;
  final String thankYouMessageHeader;
  final String? thankYouMessageDescription;
  final String thankYouMessageCloseButtonText;
  final Color borderColor;
  final Color inputBackgroundColor;
  final Color inputTextColor;
  final Color inputPlaceholderColor;
  final Color choiceButtonBorderColor;
  final Color choiceButtonTextColor;

  /// Creates a [SurveyAppearance] from a [PostHogDisplaySurveyAppearance].
  ///
  /// The server appearance sets the text and thank-you content. Colors come
  /// from the server appearance, or are derived from it for contrast. When
  /// [override] is supplied, its color fields replace the derived palette. Use
  /// it to theme a survey for the device brightness, which the server CSS
  /// values (`var(...)`, `light-dark(...)`) cannot express on Flutter.
  static SurveyAppearance fromPostHog(
    PostHogDisplaySurveyAppearance? appearance, {
    SurveyAppearance? override,
  }) {
    final o = override;

    final backgroundColor = o?.backgroundColor ??
        _colorFromHex(appearance?.backgroundColor) ??
        Colors.white;
    final submitButtonColor = o?.submitButtonColor ??
        _colorFromHex(appearance?.submitButtonColor) ??
        Colors.black;
    final ratingButtonColor = o?.ratingButtonColor ??
        _colorFromHex(appearance?.ratingButtonColor) ??
        const Color(0xFFEEEEEE);
    final ratingButtonActiveColor = o?.ratingButtonActiveColor ??
        _colorFromHex(appearance?.ratingButtonActiveColor) ??
        Colors.black;

    // Input background: use override, or slight adjustment for high luminance backgrounds
    final inputBackgroundColor = o?.inputBackgroundColor ??
        _colorFromHex(appearance?.inputBackground) ??
        (backgroundColor.computeLuminance() > 0.95
            ? const Color(0xFFF8F8F8)
            : backgroundColor);

    // Primary text color: use textColor override if provided, otherwise auto-contrast
    final primaryTextColor = o?.questionTextColor ??
        _colorFromHex(appearance?.textColor) ??
        _getContrastingTextColor(backgroundColor);

    // Input text color: use override if provided, otherwise auto-contrast from input background
    final inputTextColor = o?.inputTextColor ??
        _colorFromHex(appearance?.inputTextColor) ??
        _getContrastingTextColor(inputBackgroundColor);

    return SurveyAppearance(
      backgroundColor: backgroundColor,
      submitButtonColor: submitButtonColor,
      submitButtonText: appearance?.submitButtonText ?? 'Submit',
      submitButtonTextColor: o?.submitButtonTextColor ??
          _colorFromHex(appearance?.submitButtonTextColor) ??
          _getContrastingTextColor(submitButtonColor),
      descriptionTextColor: o?.descriptionTextColor ??
          _colorFromHex(appearance?.descriptionTextColor) ??
          primaryTextColor,
      questionTextColor: primaryTextColor,
      closeButtonColor: o?.closeButtonColor ?? primaryTextColor,
      ratingButtonColor: ratingButtonColor,
      ratingButtonActiveColor: ratingButtonActiveColor,
      ratingButtonSelectedTextColor: o?.ratingButtonSelectedTextColor ??
          _getContrastingTextColor(ratingButtonActiveColor),
      ratingButtonUnselectedTextColor:
          o?.ratingButtonUnselectedTextColor ?? inputTextColor.withAlpha(128),
      displayThankYouMessage: appearance?.displayThankYouMessage ?? true,
      thankYouMessageHeader:
          appearance?.thankYouMessageHeader ?? 'Thank you for your feedback!',
      thankYouMessageDescription: appearance?.thankYouMessageDescription,
      thankYouMessageCloseButtonText:
          appearance?.thankYouMessageCloseButtonText ?? 'Close',
      borderColor: o?.borderColor ??
          _colorFromHex(appearance?.borderColor) ??
          const Color(0xFFBDBDBD),
      inputBackgroundColor: inputBackgroundColor,
      inputTextColor: inputTextColor,
      inputPlaceholderColor:
          o?.inputPlaceholderColor ?? inputTextColor.withAlpha(153),
      choiceButtonBorderColor: o?.choiceButtonBorderColor ?? primaryTextColor,
      choiceButtonTextColor: o?.choiceButtonTextColor ?? primaryTextColor,
    );
  }

  /// Returns black or white text color based on the perceived brightness of the background.
  /// Uses the HSP (Highly Sensitive Perceived) color model for perceived brightness.
  /// This matches the algorithm used in posthog-js.
  static Color _getContrastingTextColor(Color color) {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    // HSP equation for perceived brightness
    final hsp = sqrt(0.299 * (r * r) + 0.587 * (g * g) + 0.114 * (b * b));
    // Using 127.5 as threshold (same as JS)
    return hsp > 127.5 ? Colors.black : Colors.white;
  }

  /// Parses a CSS color value into a [Color].
  ///
  /// Accepts a hex string (3, 6, or 8 digits), one of the 140 CSS color names,
  /// or an `rgb()`, `rgba()`, `hsl()`, or `hsla()` function. Returns `null` for
  /// an empty value, and logs a debug warning for a non-empty value it cannot
  /// read. Flutter cannot resolve `var(...)`, `light-dark(...)`, or `calc(...)`;
  /// use `PostHogConfig.surveyAppearanceConfig` to theme the survey instead.
  static Color? _colorFromHex(String? colorString) {
    if (colorString == null || colorString.isEmpty) return null;

    final value = colorString.trim();
    final lower = value.toLowerCase();

    final Color? color;
    if (lower.startsWith('rgb')) {
      color = _colorFromRgb(value);
    } else if (lower.startsWith('hsl')) {
      color = _colorFromHsl(value);
    } else {
      color = _colorFromHexOrName(value);
    }

    if (color == null) {
      printIfDebug(
        '[PostHog] Could not parse survey color "$colorString"; using the '
        'default. Flutter accepts hex, a CSS color name, rgb(), rgba(), '
        'hsl(), or hsla(), but cannot resolve var(), light-dark(), or calc(). '
        'Set PostHogConfig.surveyAppearanceConfig to theme the survey.',
      );
    }
    return color;
  }

  static Color? _colorFromHexOrName(String value) {
    // First check if we can map from CSS color
    final cssHexString = _cssToHexDictionary[value.toUpperCase()] ?? value;

    // Sanitize by removing any leading '#' character and uppercase for consistency
    var hex = cssHexString.replaceFirst('#', '').toUpperCase();

    // Handle different hex formats
    if (hex.length == 3) {
      // Convert #RGB to #RRGGBB
      hex = hex.split('').map((c) => '$c$c').join('');
    }
    if (hex.length == 6) {
      // Add full opacity if no alpha
      hex = 'FF$hex';
    }

    if (hex.length != 8) return null;
    final argb = int.tryParse('0x$hex');
    return argb == null ? null : Color(argb);
  }

  /// Parses `rgb()` and `rgba()`. Channels accept 0-255 numbers or percentages;
  /// alpha accepts a 0-1 number or a percentage.
  static Color? _colorFromRgb(String value) {
    final args = _cssArgs(value);
    if (args.length < 3 || args.length > 4) return null;

    final r = _channel(args[0]);
    final g = _channel(args[1]);
    final b = _channel(args[2]);
    final a = args.length == 4 ? _alphaFraction(args[3]) : 1.0;
    if (r == null || g == null || b == null || a == null) return null;

    return Color.fromRGBO(r, g, b, a);
  }

  /// Parses `hsl()` and `hsla()`. Hue accepts an optional `deg` unit;
  /// saturation and lightness are percentages; alpha accepts a 0-1 number or a
  /// percentage.
  static Color? _colorFromHsl(String value) {
    final args = _cssArgs(value);
    if (args.length < 3 || args.length > 4) return null;

    final h = _hue(args[0]);
    final s = _percent(args[1]);
    final l = _percent(args[2]);
    final a = args.length == 4 ? _alphaFraction(args[3]) : 1.0;
    if (h == null || s == null || l == null || a == null) return null;

    return HSLColor.fromAHSL(a, h, s, l).toColor();
  }

  /// Splits the arguments of a CSS function on commas, slashes, and whitespace,
  /// so both the comma and the space-separated syntaxes work.
  static List<String> _cssArgs(String value) {
    final open = value.indexOf('(');
    final close = value.lastIndexOf(')');
    if (open == -1 || close <= open) return const [];
    return value
        .substring(open + 1, close)
        .split(RegExp(r'[,\s/]+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  static int? _channel(String token) {
    if (token.endsWith('%')) {
      final pct = double.tryParse(token.substring(0, token.length - 1));
      if (pct == null) return null;
      return (pct / 100 * 255).round().clamp(0, 255);
    }
    final value = double.tryParse(token);
    if (value == null) return null;
    return value.round().clamp(0, 255);
  }

  static double? _alphaFraction(String token) {
    if (token.endsWith('%')) {
      final pct = double.tryParse(token.substring(0, token.length - 1));
      if (pct == null) return null;
      return (pct / 100).clamp(0.0, 1.0);
    }
    final value = double.tryParse(token);
    if (value == null) return null;
    return value.clamp(0.0, 1.0);
  }

  static double? _hue(String token) {
    final cleaned =
        token.endsWith('deg') ? token.substring(0, token.length - 3) : token;
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return value % 360;
  }

  static double? _percent(String token) {
    final cleaned =
        token.endsWith('%') ? token.substring(0, token.length - 1) : token;
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return (value / 100).clamp(0.0, 1.0);
  }

  /// CSS color names to hex values mapping
  static const _cssToHexDictionary = {
    'CLEAR': '00000000',
    'TRANSPARENT': '00000000',
    'ALICEBLUE': 'F0F8FF',
    'ANTIQUEWHITE': 'FAEBD7',
    'AQUA': '00FFFF',
    'AQUAMARINE': '7FFFD4',
    'AZURE': 'F0FFFF',
    'BEIGE': 'F5F5DC',
    'BISQUE': 'FFE4C4',
    'BLACK': '000000',
    'BLUE': '0000FF',
    'BLUEVIOLET': '8A2BE2',
    'BROWN': 'A52A2A',
    'BURLYWOOD': 'DEB887',
    'CADETBLUE': '5F9EA0',
    'CHARTREUSE': '7FFF00',
    'CHOCOLATE': 'D2691E',
    'CORAL': 'FF7F50',
    'CORNFLOWERBLUE': '6495ED',
    'CRIMSON': 'DC143C',
    'CYAN': '00FFFF',
    'DARKBLUE': '00008B',
    'DARKCYAN': '008B8B',
    'DARKGOLDENROD': 'B8860B',
    'DARKGRAY': 'A9A9A9',
    'DARKGREEN': '006400',
    'DARKKHAKI': 'BDB76B',
    'DARKMAGENTA': '8B008B',
    'DARKOLIVEGREEN': '556B2F',
    'DARKORANGE': 'FF8C00',
    'DARKORCHID': '9932CC',
    'DARKRED': '8B0000',
    'DARKSALMON': 'E9967A',
    'DARKSEAGREEN': '8FBC8F',
    'DARKSLATEBLUE': '483D8B',
    'DARKSLATEGRAY': '2F4F4F',
    'DARKTURQUOISE': '00CED1',
    'DARKVIOLET': '9400D3',
    'DEEPPINK': 'FF1493',
    'DEEPSKYBLUE': '00BFFF',
    'DIMGRAY': '696969',
    'DODGERBLUE': '1E90FF',
    'FIREBRICK': 'B22222',
    'FORESTGREEN': '228B22',
    'FUCHSIA': 'FF00FF',
    'GAINSBORO': 'DCDCDC',
    'GHOSTWHITE': 'F8F8FF',
    'GOLD': 'FFD700',
    'GOLDENROD': 'DAA520',
    'GRAY': '808080',
    'GREEN': '008000',
    'GREENYELLOW': 'ADFF2F',
    'HONEYDEW': 'F0FFF0',
    'HOTPINK': 'FF69B4',
    'INDIANRED': 'CD5C5C',
    'INDIGO': '4B0082',
    'IVORY': 'FFFFF0',
    'KHAKI': 'F0E68C',
    'LAVENDER': 'E6E6FA',
    'LAVENDERBLUSH': 'FFF0F5',
    'LAWNGREEN': '7CFC00',
    'LEMONCHIFFON': 'FFFACD',
    'LIGHTBLUE': 'ADD8E6',
    'LIGHTCORAL': 'F08080',
    'LIGHTCYAN': 'E0FFFF',
    'LIGHTGRAY': 'D3D3D3',
    'LIGHTGREEN': '90EE90',
    'LIGHTPINK': 'FFB6C1',
    'LIGHTSALMON': 'FFA07A',
    'LIGHTSEAGREEN': '20B2AA',
    'LIGHTSKYBLUE': '87CEFA',
    'LIGHTSLATEGRAY': '778899',
    'LIGHTSTEELBLUE': 'B0C4DE',
    'LIGHTYELLOW': 'FFFFE0',
    'LIME': '00FF00',
    'LIMEGREEN': '32CD32',
    'LINEN': 'FAF0E6',
    'MAGENTA': 'FF00FF',
    'MAROON': '800000',
    'MEDIUMAQUAMARINE': '66CDAA',
    'MEDIUMBLUE': '0000CD',
    'MEDIUMORCHID': 'BA55D3',
    'MEDIUMPURPLE': '9370DB',
    'MEDIUMSEAGREEN': '3CB371',
    'MEDIUMSLATEBLUE': '7B68EE',
    'MEDIUMSPRINGGREEN': '00FA9A',
    'MEDIUMTURQUOISE': '48D1CC',
    'MEDIUMVIOLETRED': 'C71585',
    'MIDNIGHTBLUE': '191970',
    'MINTCREAM': 'F5FFFA',
    'MISTYROSE': 'FFE4E1',
    'MOCCASIN': 'FFE4B5',
    'NAVAJOWHITE': 'FFDEAD',
    'NAVY': '000080',
    'OLDLACE': 'FDF5E6',
    'OLIVE': '808000',
    'OLIVEDRAB': '6B8E23',
    'ORANGE': 'FFA500',
    'ORANGERED': 'FF4500',
    'ORCHID': 'DA70D6',
    'PALEGOLDENROD': 'EEE8AA',
    'PALEGREEN': '98FB98',
    'PALETURQUOISE': 'AFEEEE',
    'PALEVIOLETRED': 'DB7093',
    'PAPAYAWHIP': 'FFEFD5',
    'PEACHPUFF': 'FFDAB9',
    'PERU': 'CD853F',
    'PINK': 'FFC0CB',
    'PLUM': 'DDA0DD',
    'POWDERBLUE': 'B0E0E6',
    'PURPLE': '800080',
    'RED': 'FF0000',
    'ROSYBROWN': 'BC8F8F',
    'ROYALBLUE': '4169E1',
    'SADDLEBROWN': '8B4513',
    'SALMON': 'FA8072',
    'SANDYBROWN': 'F4A460',
    'SEAGREEN': '2E8B57',
    'SEASHELL': 'FFF5EE',
    'SIENNA': 'A0522D',
    'SILVER': 'C0C0C0',
    'SKYBLUE': '87CEEB',
    'SLATEBLUE': '6A5ACD',
    'SLATEGRAY': '708090',
    'SNOW': 'FFFAFA',
    'SPRINGGREEN': '00FF7F',
    'STEELBLUE': '4682B4',
    'TAN': 'D2B48C',
    'TEAL': '008080',
    'THISTLE': 'D8BFD8',
    'TOMATO': 'FF6347',
    'TURQUOISE': '40E0D0',
    'VIOLET': 'EE82EE',
    'WHEAT': 'F5DEB3',
    'WHITE': 'FFFFFF',
    'WHITESMOKE': 'F5F5F5',
    'YELLOW': 'FFFF00',
    'YELLOWGREEN': '9ACD32',
  };

  /// Default appearance
  static const defaultAppearance = SurveyAppearance();
}
