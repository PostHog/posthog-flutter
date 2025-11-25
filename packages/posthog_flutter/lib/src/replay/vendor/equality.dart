// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Adapted from https://github.com/dart-lang/core/blob/7f9f597e64fa52faebd3c0a2214f61a7b081174d/pkgs/collection/lib/src/equality.dart#L164

// ignore_for_file: library_private_types_in_public_api

const int _hashMask = 0x7fffffff;

/// A generic equality relation on objects.
abstract class _Equality<E> {
  const factory _Equality() = _DefaultEquality<E>;

  /// Compare two elements for being equal.
  ///
  /// This should be a proper equality relation.
  bool equals(E e1, E e2);

  /// Get a hashcode of an element.
  ///
  /// The hashcode should be compatible with [equals], so that if
  /// `equals(a, b)` then `hash(a) == hash(b)`.
  int hash(E e);

  /// Test whether an object is a valid argument to [equals] and [hash].
  ///
  /// Some implementations may be restricted to only work on specific types
  /// of objects.
  bool isValidKey(Object? o);
}

/// Equality of objects that compares only the natural equality of the objects.
///
/// This equality uses the objects' own [Object.==] and [Object.hashCode] for
/// the equality.
///
/// Note that [equals] and [hash] take `Object`s rather than `E`s. This allows
/// `E` to be inferred as `Null` in const contexts where `E` wouldn't be a
/// compile-time constant, while still allowing the class to be used at runtime.
class _DefaultEquality<E> implements _Equality<E> {
  const _DefaultEquality();
  @override
  bool equals(Object? e1, Object? e2) => e1 == e2;
  @override
  int hash(Object? e) => e.hashCode;
  @override
  bool isValidKey(Object? o) => true;
}

/// Equality on lists.
///
/// Two lists are equal if they have the same length and their elements
/// at each index are equal.
///
/// This is effectively the same as [IterableEquality] except that it
/// accesses elements by index instead of through iteration.
///
/// The [equals] and [hash] methods accepts `null` values,
/// even if the [isValidKey] returns `false` for `null`.
/// The [hash] of `null` is `null.hashCode`.
class PHListEquality<E> implements _Equality<List<E>> {
  final _Equality<E> _elementEquality;
  const PHListEquality(
      [_Equality<E> elementEquality = const _DefaultEquality<Never>()])
      : _elementEquality = elementEquality;

  @override
  bool equals(List<E>? list1, List<E>? list2) {
    if (identical(list1, list2)) return true;
    if (list1 == null || list2 == null) return false;
    var length = list1.length;
    if (length != list2.length) return false;
    for (var i = 0; i < length; i++) {
      if (!_elementEquality.equals(list1[i], list2[i])) return false;
    }
    return true;
  }

  @override
  int hash(List<E>? list) {
    if (list == null) return null.hashCode;
    // Jenkins's one-at-a-time hash function.
    // This code is almost identical to the one in IterableEquality, except
    // that it uses indexing instead of iterating to get the elements.
    var hash = 0;
    for (var i = 0; i < list.length; i++) {
      var c = _elementEquality.hash(list[i]);
      hash = (hash + c) & _hashMask;
      hash = (hash + (hash << 10)) & _hashMask;
      hash ^= hash >> 6;
    }
    hash = (hash + (hash << 3)) & _hashMask;
    hash ^= hash >> 11;
    hash = (hash + (hash << 15)) & _hashMask;
    return hash;
  }

  @override
  bool isValidKey(Object? o) => o is List<E>;
}
