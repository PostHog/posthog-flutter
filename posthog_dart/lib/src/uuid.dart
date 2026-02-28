import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generates a UUIDv7 string.
String generateUuidV7() => _uuid.v7();
