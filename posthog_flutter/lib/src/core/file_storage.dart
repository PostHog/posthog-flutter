import 'dart:convert';
import 'dart:io';

import 'logger.dart';
import 'persistence.dart';
import 'uuid.dart';

/// File-based storage.
///
/// The persisted properties (identity, feature flags, consent, super
/// properties) live in one JSON snapshot, `posthog_data.json`. Every queued
/// event is a file of its own in `posthog_queue/`, named after a UUIDv7 so
/// that the names sort in queueing order: queueing an event writes one small
/// file and leaves the others alone.
///
/// One storage at a time writes the snapshot of a directory: the first to
/// use it locks `posthog.lock` until it is closed. Another storage on the
/// same directory, such as a second instance of the app, reads the snapshot
/// once and keeps its own changes to it in memory, so it cannot overwrite the
/// identity and consent of the first. Those changes, an opt-out included,
/// do not survive a restart. Its events still go to queue files, so none is
/// lost. A client handles only the events it queued itself and, when it
/// holds the lock, those it found when it started: it deletes them once they
/// are sent, or when the queue is full.
///
/// The lock is an operating system file lock: on network file systems it
/// may not hold, and within one process it only tells apart storages of the
/// same isolate.
///
/// Storage never throws into the host app. While the snapshot cannot be
/// read, the store reports [isDegraded] and keeps writes in memory only, so a
/// transient failure never replaces good persisted data; once the file can
/// be read again, its content wins. Files are replaced through a temporary
/// file and a rename, without syncing them to disk: a crash can lose the
/// latest writes but never leaves a file half-written.
class FileStorage {
  FileStorage(this._directory);

  static const _dataFileName = 'posthog_data.json';
  static const _lockFileName = 'posthog.lock';
  static const _queueDirectoryName = 'posthog_queue';

  /// The lock files held by storages of this isolate. A POSIX file lock
  /// belongs to the whole process and is released as soon as the process
  /// closes any handle to the file, so a second storage of the same directory
  /// must not even open it.
  static final Set<String> _heldLockPaths = {};

  final String _directory;
  Map<String, Object?>? _cache;

  /// Values set while the snapshot cannot be read. They are never written
  /// over the file, whose content is unknown, and give way to it once it can
  /// be read.
  final Map<String, Object?> _unpersisted = {};

  // Losing the whole snapshot (ids, consent) matters enough to log outside
  // debug mode, so this does not go through [logger].
  static final CoreLogger _resetLogger = CoreLogger(_logAlways);
  static void _logAlways(void Function() log) => log();

  /// Receives what the storage reports, write failures included, since
  /// nothing is thrown into the host app. A PostHog client created with this
  /// storage attaches its own logger, so reports show up in its debug output.
  CoreLogger? logger;

  _Role? _role;
  RandomAccessFile? _lock;
  String? _lockPath;
  FileEventQueue? _queue;

  String _pathOf(String name) => '$_directory${Platform.pathSeparator}$name';

  String get _dataFilePath => _pathOf(_dataFileName);

  /// Whether the snapshot is currently unreadable.
  ///
  /// While degraded, persisted state (including consent) is unknown -
  /// consumers should treat it conservatively, e.g. consent checks fail
  /// closed.
  bool get isDegraded => _readAll() == null;

  /// The events waiting to be sent.
  FileEventQueue get queue =>
      _queue ??= FileEventQueue._(_pathOf(_queueDirectoryName), () => logger,
          includeExisting: _open() == _Role.primary);

  /// Decides, on first use, whether this storage writes the snapshot.
  _Role _open() {
    final role = _role;
    if (role != null) return role;
    if (_acquireLock()) return _role = _Role.primary;
    logger?.info('Another PostHog client uses $_directory: changes to the '
        'stored identity and consent stay in memory; events are queued there '
        'as usual.');
    return _role = _Role.secondary;
  }

  /// Locks the directory. Returns false when another storage holds the
  /// lock, true otherwise: also when locking is not possible, which leaves
  /// the directory to this storage as if it had no lock.
  bool _acquireLock() {
    final String lockPath;
    try {
      final directory = Directory(_directory)..createSync(recursive: true);
      // Resolved, so that two spellings of one directory share their key.
      lockPath = '${directory.resolveSymbolicLinksSync()}'
          '${Platform.pathSeparator}$_lockFileName';
    } on FileSystemException catch (e) {
      logger?.warn('Cannot lock the PostHog storage directory:', e);
      return true;
    }
    if (_heldLockPaths.contains(lockPath)) return false;

    RandomAccessFile? lock;
    try {
      lock = File(lockPath).openSync(mode: FileMode.append);
      lock.lockSync(FileLock.exclusive);
    } on FileSystemException catch (e) {
      // Only a lock refused on an opened file can mean another holder.
      final refused = lock != null && _isLockedElsewhere(e);
      lock?.closeSync();
      lock = null;
      if (refused) return false;
      logger?.warn('Cannot lock the PostHog storage directory:', e);
    }
    _lock = lock;
    _lockPath = lockPath;
    _heldLockPaths.add(lockPath);
    return true;
  }

  /// Whether a failed attempt to take the lock means that another process
  /// holds it, rather than a file system without file locks.
  static bool _isLockedElsewhere(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (Platform.isWindows) return code == 33; // ERROR_LOCK_VIOLATION
    return code == 11 || code == 13; // EAGAIN or EACCES on Linux
  }

  /// Releases the directory lock, so that another storage can write the
  /// snapshot; this one stops writing it.
  void close() {
    _role = _Role.secondary;
    final lockPath = _lockPath;
    if (lockPath != null) _heldLockPaths.remove(lockPath);
    _lockPath = null;
    try {
      // Closing the file releases the lock.
      _lock?.closeSync();
    } on FileSystemException catch (e) {
      logger?.warn('Failed to release the PostHog storage lock:', e);
    }
    _lock = null;
  }

  /// Returns the store, or null while the disk is unreadable.
  Map<String, Object?>? _readAll() {
    if (_cache != null) return _cache;
    final snapshot = _cache = _readSnapshot();
    if (snapshot != null && _unpersisted.isNotEmpty) {
      logger?.warn('The PostHog storage file can be read again; values set '
          'while it could not be read give way to the stored ones.');
      _unpersisted.clear();
    }
    return snapshot;
  }

  Map<String, Object?>? _readSnapshot() {
    final List<int> bytes;
    try {
      bytes = File(_dataFilePath).readAsBytesSync();
    } on PathNotFoundException {
      // No file yet. Detected via the read exception, not existsSync(),
      // which also reports false on access-denied.
      return {};
    } catch (_) {
      // Transient IO failure: the on-disk state is unknown.
      return null;
    }

    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    } catch (e) {
      // Corrupt content (torn write, foreign data) will not heal on retry,
      // so the store resets instead of staying degraded forever.
      _resetLogger.warn('Resetting unreadable posthog store:', e);
      return {};
    }
  }

  /// Returns the value stored under [key], or null when the key is absent
  /// or the stored value is not a [T].
  T? getProperty<T>(PostHogPersistedProperty key) {
    final value = (_readAll() ?? _unpersisted)[key.key];
    return value is T ? value : null;
  }

  /// Stores [value] under [key]; null removes the entry. A value that cannot
  /// be JSON-encoded is dropped.
  void setProperty<T>(PostHogPersistedProperty key, T? value) {
    final data = _readAll();
    if (data == null) {
      // Unknown disk state: the file must not be overwritten. Consent is
      // protected separately - consumers fail closed on isDegraded.
      logger?.warn('The PostHog storage file cannot be read, keeping '
          '"${key.key}" in memory only.');
      _put(_unpersisted, key.key, value);
      return;
    }

    final hadKey = data.containsKey(key.key);
    final previous = data[key.key];
    _put(data, key.key, value);
    if (_open() != _Role.primary) return;

    final String encoded;
    try {
      encoded = jsonEncode(data);
    } catch (e) {
      // A non-encodable value would fail every snapshot write from now on;
      // drop it and restore the cache.
      logger?.warn(
          'Dropping a value for "${key.key}" that cannot be '
          'JSON-encoded:',
          e);
      if (hadKey) {
        data[key.key] = previous;
      } else {
        data.remove(key.key);
      }
      return;
    }
    _writeSnapshot(encoded);
  }

  static void _put(Map<String, Object?> data, String key, Object? value) {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  void _writeSnapshot(String encoded) {
    try {
      _writeAtomically(File(_dataFilePath), encoded);
    } catch (e) {
      // Best effort: the cache keeps the new value, the next successful
      // write persists the whole snapshot.
      logger?.warn(
          'Failed to persist the PostHog state; it is kept in '
          'memory until the next successful write:',
          e);
    }
  }
}

enum _Role {
  /// Holds the directory lock: writes the snapshot, and sends the events
  /// found in the directory as well as its own.
  primary,

  /// Another storage holds the lock, or this one released it: keeps
  /// snapshot changes in memory, and sends only its own events.
  secondary,
}

/// An event in a [FileEventQueue] and the id the queue keeps it under.
typedef PostHogQueuedEvent = ({String id, Map<String, Object?> event});

/// The first-in, first-out queue of a [FileStorage]: the events waiting to be
/// sent, one JSON file per event, named after the event's queue id. The order
/// is kept in memory, read once from the directory.
///
/// Events are JSON-encodable maps; the client makes them so before adding
/// them. The client removes an event by its id once it is delivered, so an
/// event added while a batch is in flight is never removed with it.
class FileEventQueue {
  FileEventQueue._(this._directory, this._logger,
      {required bool includeExisting})
      : _loadedIds = includeExisting ? null : [];

  static const _extension = '.json';

  final String _directory;
  final CoreLogger? Function() _logger;

  /// The queue, oldest first: the events found in the directory, read on
  /// first use, then the ones added here.
  List<String>? _loadedIds;

  /// Events whose file could not be written, so they can still be sent by
  /// this client.
  final Map<String, Map<String, Object?>> _unwritten = {};

  List<String> get _ids => _loadedIds ??= _load();

  String _pathOf(String id) =>
      '$_directory${Platform.pathSeparator}$id$_extension';

  List<String> _load() {
    try {
      return [
        for (final entity in Directory(_directory).listSync())
          if (entity is File && entity.path.endsWith(_extension)) _idOf(entity),
      ]..sort();
    } on PathNotFoundException {
      return [];
    } on FileSystemException catch (e) {
      _logger()?.warn(
          'Could not list the queued events; they stay on disk for a '
          'later run:',
          e);
      return [];
    }
  }

  static String _idOf(File file) {
    final name = file.uri.pathSegments.last;
    return name.substring(0, name.length - _extension.length);
  }

  /// The number of queued events.
  int get length => _ids.length;

  /// Adds [event] at the end of the queue.
  void add(Map<String, Object?> event) {
    // Loaded before the new file exists, which would otherwise be listed
    // on top of being added.
    final ids = _ids;
    final id = generateUuidV7();
    ids.add(id);
    try {
      _writeAtomically(File(_pathOf(id)), jsonEncode(event));
    } catch (e) {
      _unwritten[id] = event;
      _logger()?.warn(
          'Failed to persist a queued event; it is kept in memory until it '
          'is sent:',
          e);
    }
  }

  /// Returns up to [count] events from the front of the queue, oldest
  /// first.
  List<PostHogQueuedEvent> peek(int count) {
    final events = <PostHogQueuedEvent>[];
    final gone = <String>{};
    for (final id in _ids) {
      if (events.length >= count) break;
      final event = _unwritten[id] ?? _read(id, gone);
      if (event != null) events.add((id: id, event: event));
    }
    if (gone.isNotEmpty) _ids.removeWhere(gone.contains);
    return events;
  }

  /// Reads the event queued as [id], or returns null. An event that is gone
  /// for good (sent by another client, or unreadable and so deleted) is also
  /// added to [gone]; one that cannot be read right now stays queued.
  Map<String, Object?>? _read(String id, Set<String> gone) {
    final file = File(_pathOf(id));
    try {
      final event = jsonDecode(utf8.decode(file.readAsBytesSync()));
      if (event is Map<String, Object?>) return event;
      throw const FormatException('Not a JSON object');
    } on PathNotFoundException {
      // Sent by another client using the same directory.
      gone.add(id);
    } on FormatException catch (e) {
      _logger()?.warn('Deleting queued event $id, which cannot be read:', e);
      gone.add(id);
      _delete(file);
    } on FileSystemException catch (e) {
      _logger()?.warn('Skipping queued event $id for now:', e);
    }
    return null;
  }

  /// Removes the events with the given [ids]; unknown ids are ignored.
  void remove(Iterable<String> ids) {
    final removed = ids.toSet();
    _ids.removeWhere(removed.contains);
    removed.forEach(_forget);
  }

  /// Removes up to [count] events from the front of the queue.
  void removeOldest(int count) {
    final oldest = _ids.take(count).toList();
    _ids.removeRange(0, oldest.length);
    oldest.forEach(_forget);
  }

  void _forget(String id) {
    if (_unwritten.remove(id) == null) _delete(File(_pathOf(id)));
  }

  void _delete(File file) {
    try {
      file.deleteSync();
    } on PathNotFoundException {
      // Already deleted by another client using the same directory.
    } on FileSystemException catch (e) {
      _logger()
          ?.warn('Failed to delete a queued event; it may be sent again:', e);
    }
  }
}

/// Replaces [file] with [contents] through a temporary file and a rename, so
/// the file never exists half-written. Creates the directory when missing.
void _writeAtomically(File file, String contents) {
  final tmp = File('${file.path}.tmp');
  try {
    tmp.writeAsStringSync(contents);
  } on PathNotFoundException {
    tmp.parent.createSync(recursive: true);
    tmp.writeAsStringSync(contents);
  }
  tmp.renameSync(file.path);
}
