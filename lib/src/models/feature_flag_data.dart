// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/foundation.dart';

class FeatureFlagData {
  final bool isEnabled;
  final String? variant;
  final Map<String, dynamic>? data;

  FeatureFlagData({
    required this.isEnabled,
    this.variant,
    this.data,
  });

  FeatureFlagData copyWith({
    bool? isEnabled,
    String? variant,
    Map<String, dynamic>? data,
  }) {
    return FeatureFlagData(
      isEnabled: isEnabled ?? this.isEnabled,
      variant: variant ?? this.variant,
      data: data ?? this.data,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'isEnabled': isEnabled,
      'variant': variant,
      'data': data,
    };
  }

  factory FeatureFlagData.fromMap(Map<String, dynamic> map) {
    return FeatureFlagData(
      isEnabled: map['isEnabled'] as bool,
      variant: map['variant'] != null ? map['variant'] as String : null,
      data: map['data'] != null
          ? Map<String, dynamic>.from((map['data'] as Map<String, dynamic>))
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory FeatureFlagData.fromJson(String source) =>
      FeatureFlagData.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'FeatureFlagData(isEnabled: $isEnabled, variant: $variant, data: $data)';

  @override
  bool operator ==(covariant FeatureFlagData other) {
    if (identical(this, other)) return true;

    return other.isEnabled == isEnabled &&
        other.variant == variant &&
        mapEquals(other.data, data);
  }

  @override
  int get hashCode => isEnabled.hashCode ^ variant.hashCode ^ data.hashCode;
}
