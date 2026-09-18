import 'dart:ui' show TextRange;

import 'package:flutter/widgets.dart' show Widget;

/// What session replay masks inside one text node.
///
/// A [PostHogTextMaskPolicy] returns one of these for every plain `Text`,
/// `RichText`, and non-sensitive text input that a replay frame captures.
/// Ranges are character offsets into the node's rendered string, exactly as
/// it was passed to the policy. Build one with the named constructors, or
/// match on the four subtypes.
sealed class PostHogTextMask {
  const PostHogTextMask._();

  /// Mask the whole node.
  const factory PostHogTextMask.all() = PostHogTextMaskAll;

  /// Leave the whole node visible.
  const factory PostHogTextMask.none() = PostHogTextMaskNone;

  /// Mask only [ranges]; the rest of the node stays visible.
  ///
  /// An empty [ranges] masks nothing.
  const factory PostHogTextMask.only(Iterable<TextRange> ranges) =
      PostHogTextMaskOnly;

  /// Mask the whole node except [ranges].
  ///
  /// An empty [ranges] masks the whole node.
  const factory PostHogTextMask.except(Iterable<TextRange> ranges) =
      PostHogTextMaskExcept;
}

/// [PostHogTextMask.all]: the whole node is masked.
final class PostHogTextMaskAll extends PostHogTextMask {
  /// Creates a decision that masks the whole node.
  const PostHogTextMaskAll() : super._();
}

/// [PostHogTextMask.none]: the whole node stays visible.
final class PostHogTextMaskNone extends PostHogTextMask {
  /// Creates a decision that leaves the whole node visible.
  const PostHogTextMaskNone() : super._();
}

/// [PostHogTextMask.only]: only [ranges] are masked.
final class PostHogTextMaskOnly extends PostHogTextMask {
  /// Creates a decision that masks only [ranges].
  const PostHogTextMaskOnly(this.ranges) : super._();

  /// The character ranges to mask.
  final Iterable<TextRange> ranges;
}

/// [PostHogTextMask.except]: everything but [ranges] is masked.
final class PostHogTextMaskExcept extends PostHogTextMask {
  /// Creates a decision that masks everything except [ranges].
  const PostHogTextMaskExcept(this.ranges) : super._();

  /// The character ranges to leave visible.
  final Iterable<TextRange> ranges;
}

/// Decides what to mask in a text node, given its rendered string and the
/// widget that produced it.
///
/// Set one on `PostHogSessionReplayConfig.textMaskPolicy`. [widget] is the
/// `RichText` or `EditableText` that actually produced the render object —
/// not the outer `Text`/`TextField` an app writes, which Flutter composes
/// away — so inspect its style, its `InlineSpan`, or (for inputs)
/// properties like `obscureText` and `readOnly` to decide by more than the
/// string. It is called on the UI thread for every captured text node, so
/// keep it fast and free of side effects. Throwing masks the whole node.
typedef PostHogTextMaskPolicy = PostHogTextMask Function(
  String text,
  Widget widget,
);

/// Ready-made [PostHogTextMaskPolicy] implementations.
abstract final class PostHogTextMaskPolicies {
  /// Masks every run of digits and leaves the surrounding words visible.
  ///
  /// A run may contain grouping punctuation (`,` `.` `-`) and spaces between
  /// its digits, so a formatted amount or card number is one mask:
  /// `₦2,450,000.00` and `4111 1111 1111 1111` are each masked in full, and
  /// in `Order 2 of 5` only the `2` and the `5` are.
  static PostHogTextMaskPolicy digits() => redact(_digitRun);

  /// Masks every match of [pattern] and leaves the rest of the node visible.
  ///
  /// ```dart
  /// // Hide anything that looks like an email address.
  /// PostHogTextMaskPolicies.redact(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'))
  /// ```
  static PostHogTextMaskPolicy redact(RegExp pattern) =>
      (text, widget) => PostHogTextMask.only(_matches(pattern, text));

  /// Masks the whole node except the matches of [pattern].
  ///
  /// ```dart
  /// // Keep currency codes readable inside otherwise masked amounts.
  /// PostHogTextMaskPolicies.reveal(RegExp(r'\b(NGN|USD|GBP)\b'))
  /// ```
  static PostHogTextMaskPolicy reveal(RegExp pattern) =>
      (text, widget) => PostHogTextMask.except(_matches(pattern, text));

  static final RegExp _digitRun = RegExp(r'\d[\d.,\- ]*\d|\d');

  static Iterable<TextRange> _matches(RegExp pattern, String text) => pattern
      .allMatches(text)
      .map((match) => TextRange(start: match.start, end: match.end));
}
