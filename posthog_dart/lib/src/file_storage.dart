import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'persistence.dart';
import 'storage.dart';

/// File-based storage implementation.
///
/// Stores all persisted properties as a single JSON file on disk.
/// This is not available on web platforms since it uses `dart:io`.
///
/// For Flutter apps, pass the directory from `path_provider`'s
/// `getApplicationDocumentsDirectory()` or `getApplicationSupportDirectory()`.
///
/// Example:
/// ```dart
/// final dir = await getApplicationSupportDirectory();
/// final storage = FileStorage(dir.path);
/// ```
class FileStorage implements PostHogStorage {
  final String _directoryPath;
  Map<String, Object?>? _cache;
  static const _fileName = 'posthog_data.json';

  FileStorage(this._directoryPath);

  String get _filePath => p.join(_directoryPath, _fileName);

  Map<String, Object?> _readAll() {
    if (_cache != null) return _cache!;

    final file = File(_filePath);
    if (!file.existsSync()) {
      _cache = {};
      return _cache!;
    }

    try {
      final content = file.readAsStringSync();
      _cache = jsonDecode(content) as Map<String, Object?>;
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  void _writeAll() {
    final file = File(_filePath);
    final dir = Directory(_directoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    file.writeAsStringSync(jsonEncode(_cache ?? {}));
  }

  @override
  T? getProperty<T>(PostHogPersistedProperty key) {
    final data = _readAll();
    return data[key.key] as T?;
  }

  @override
  void setProperty<T>(PostHogPersistedProperty key, T? value) {
    final data = _readAll();
    if (value == null) {
      data.remove(key.key);
    } else {
      data[key.key] = value;
    }
    _writeAll();
  }

  /// Clears the in-memory cache, forcing next read from disk.
  void clearCache() {
    _cache = null;
  }
}
