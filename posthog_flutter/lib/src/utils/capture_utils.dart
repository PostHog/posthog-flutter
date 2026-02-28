/// Result of extracting user properties from capture properties.
class ExtractedCaptureProperties {
  /// The properties map with $set and $set_once removed.
  final Map<String, Object>? properties;

  /// Merged user properties from $set in properties and userProperties parameter.
  final Map<String, Object>? userProperties;

  /// Merged user properties from $set_once in properties and userPropertiesSetOnce parameter.
  final Map<String, Object>? userPropertiesSetOnce;

  ExtractedCaptureProperties({
    this.properties,
    this.userProperties,
    this.userPropertiesSetOnce,
  });
}

/// Utility class for capture-related operations.
class CaptureUtils {
  /// Extracts $set and $set_once from properties for backward compatibility,
  /// merges them with the new userProperties and userPropertiesSetOnce parameters,
  /// and returns the cleaned properties along with the merged user properties.
  ///
  /// New parameters (userProperties, userPropertiesSetOnce) take precedence
  /// over legacy $set and $set_once in properties.
  static ExtractedCaptureProperties extractUserProperties({
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) {
    // Create a mutable copy of properties to extract $set and $set_once
    final propertiesCopy =
        properties != null ? Map<String, Object>.from(properties) : null;

    // Extract $set and $set_once from properties for backward compatibility
    Map<String, Object>? legacyUserProperties;
    Map<String, Object>? legacyUserPropertiesSetOnce;

    if (propertiesCopy != null) {
      if (propertiesCopy['\$set'] is Map<String, Object>) {
        legacyUserProperties =
            Map<String, Object>.from(propertiesCopy['\$set'] as Map);
        propertiesCopy.remove('\$set');
      }
      if (propertiesCopy['\$set_once'] is Map<String, Object>) {
        legacyUserPropertiesSetOnce =
            Map<String, Object>.from(propertiesCopy['\$set_once'] as Map);
        propertiesCopy.remove('\$set_once');
      }
    }

    // Merge legacy properties with new parameters (new parameters take precedence)
    final mergedUserProperties = <String, Object>{
      ...?legacyUserProperties,
      ...?userProperties,
    };
    final mergedUserPropertiesSetOnce = <String, Object>{
      ...?legacyUserPropertiesSetOnce,
      ...?userPropertiesSetOnce,
    };

    return ExtractedCaptureProperties(
      properties: propertiesCopy,
      userProperties:
          mergedUserProperties.isNotEmpty ? mergedUserProperties : null,
      userPropertiesSetOnce: mergedUserPropertiesSetOnce.isNotEmpty
          ? mergedUserPropertiesSetOnce
          : null,
    );
  }
}
