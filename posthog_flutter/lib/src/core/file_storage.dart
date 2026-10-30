import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show SynchronousFuture, visibleForTesting;

import 'logger.dart';
import 'persistence.dart';
import 'queue_worker.dart';
import 'uuid.dart';

/// Client state and queue storage, persistent unless created in memory.
///
/// The persisted properties (identity, feature flags, consent, super
/// properties) live in one JSON snapshot, `posthog_data.json`. Every queued
/// event is a file of its own in `posthog_queue/`, or `posthog_ai_queue/`
/// for AI events, named after a UUIDv7 so that the names sort in queueing
/// order: queueing an event writes one small file and leaves the others
/// alone.
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
/// transient failure never replaces good persisted data. That instance stays
/// in memory after a read failure because it cannot safely merge later runtime
/// changes with a snapshot it never saw; a new instance retries the disk.
/// Files are replaced through a temporary file and a rename, without syncing
/// them to disk: a crash can lose the latest writes but never leaves a file
/// half-written. Queued events are written by a [QueueWorker] off the UI
/// isolate: an event is on disk once the call that queued it completes, and
/// one not awaited can be lost to a crash or `exit()` in the moments that
/// follow.
class FileStorage {
  /// A storage in [_directory]. Its queues give their file work to [worker],
  /// a background isolate by default.
  FileStorage(this._directory, {QueueWorker? worker})
      : _worker = worker ?? QueueWorker.defaultWorker();

  /// A storage that keeps everything in memory. Its queues still measure
  /// their events with [worker].
  FileStorage.memory({QueueWorker? worker})
      : this._memory(worker ?? QueueWorker.defaultWorker());

  FileStorage._memory(this._worker)
      : _directory = '',
        _cache = {},
        _role = _Role.secondary,
        _queue = FileEventQueue._memory(_worker),
        _aiQueue = FileEventQueue._memory(_worker);

  static const _dataFileName = 'posthog_data.json';
  static const _lockFileName = 'posthog.lock';
  static const _queueDirectoryName = 'posthog_queue';
  static const _aiQueueDirectoryName = 'posthog_ai_queue';

  /// The lock files held by storages of this isolate. A POSIX file lock
  /// belongs to the whole process and is released as soon as the process
  /// closes any handle to the file, so a second storage of the same directory
  /// must not even open it.
  static final Set<String> _heldLockPaths = {};

  final String _directory;
  final QueueWorker _worker;
  Map<String, Object?>? _cache;
  bool _readFailed = false;

  /// Values set after the snapshot could not be read. They are never written
  /// over the file, whose content is unknown, and remain this instance's state.
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
  FileEventQueue? _aiQueue;

  String _pathOf(String name) => '$_directory${Platform.pathSeparator}$name';

  String get _dataFilePath => _pathOf(_dataFileName);

  /// Whether this instance failed to read its snapshot.
  ///
  /// While degraded, persisted state (including consent) is unknown -
  /// consumers should treat it conservatively, e.g. consent checks fail
  /// closed.
  bool get isDegraded => _readAll() == null;

  /// The events waiting to be sent.
  FileEventQueue get queue => _queue ??= FileEventQueue._(
      _pathOf(_queueDirectoryName), () => logger, _worker,
      includeExisting: _open() == _Role.primary);

  /// The AI events waiting to be sent, apart from the other events.
  FileEventQueue get aiQueue => _aiQueue ??= FileEventQueue._(
      _pathOf(_aiQueueDirectoryName), () => logger, _worker,
      includeExisting: _open() == _Role.primary);

  /// Does the file work of the queues, and encodes their request bodies.
  QueueWorker get worker => _worker;

  /// Completes once both queues have no file work left, so that another
  /// storage of the directory finds every event this one queued, and none it
  /// removed.
  Future<void> get settled async {
    // Not Future.wait, which throws on the SynchronousFuture of an idle queue.
    await _queue?.settled;
    await _aiQueue?.settled;
  }

  /// Completes once the analytics events queued so far are on disk.
  Future<void> get written => _queue?._submitted ?? SynchronousFuture(null);

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

  /// Releases the directory lock once the queues have no file work left, so
  /// that another storage can write the snapshot and finds exactly the events
  /// still to send; this one stops writing it.
  void close() {
    _role = _Role.secondary;
    if ((_queue?._jobs.isEmpty ?? true) && (_aiQueue?._jobs.isEmpty ?? true)) {
      _releaseLock();
    } else {
      settled.whenComplete(_releaseLock).ignore();
    }
  }

  void _releaseLock() {
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

  /// Returns the store, or null after this instance failed to read it.
  Map<String, Object?>? _readAll() {
    if (_cache != null) return _cache;
    if (_readFailed) return null;
    final snapshot = _readSnapshot();
    if (snapshot == null) {
      _readFailed = true;
    } else {
      _cache = snapshot;
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
    } catch (_) {
      // Corrupt content (torn write, foreign data) will not heal on retry,
      // so the store resets instead of staying degraded forever.
      _resetLogger.warn('Resetting corrupt PostHog store.');
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
      writeAtomically(File(_dataFilePath), encoded);
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
///
/// The [QueueWorker] encodes, measures, writes, reads and deletes the files,
/// in the order the queue asks it to. An event takes its place in the queue
/// as soon as it is added, and counts in [byteCount] once the worker has
/// measured it.
class FileEventQueue {
  FileEventQueue._(this._directory, this._logger, this._worker,
      {required bool includeExisting})
      : _loadedIds = includeExisting ? null : [];

  FileEventQueue._memory(this._worker)
      : _directory = '',
        _logger = _noLogger,
        _loadedIds = [];

  static CoreLogger? _noLogger() => null;

  static const _extension = '.json';

  final String _directory;
  final CoreLogger? Function() _logger;
  final QueueWorker _worker;

  /// The queue, oldest first: the events found in the directory, read on
  /// first use, then the ones added here.
  List<String>? _loadedIds;

  /// Events whose file could not be written, or that a queue in memory
  /// keeps, so they can still be sent by this client.
  final Map<String, Map<String, Object?>> _unwritten = {};

  /// Events the worker is still measuring and writing. A peek leaves them
  /// for later: the worker can still drop one for its size.
  final Set<String> _writing = {};

  /// Events waiting for a free write, oldest first. Eviction can still cancel
  /// them, unlike a job the worker was given.
  final Map<String, _UnsentWrite> _unsent = {};

  /// The most writes the worker holds at once, so that captures outpacing it
  /// keep only the events the queue limits allow in memory.
  @visibleForTesting
  static const maxWritesInFlight = 8;

  var _writesInFlight = 0;

  /// The worker jobs not done yet.
  final Set<Future<void>> _jobs = {};

  /// The serialized size of each queued event, by id, and their total.
  final Map<String, int> _sizes = {};
  int _byteCount = 0;

  List<String> get _ids => _loadedIds ??= _load();

  String _pathOf(String id) =>
      '$_directory${Platform.pathSeparator}$id$_extension';

  List<String> _load() {
    try {
      return [
        for (final entity in Directory(_directory).listSync())
          if (entity is File && entity.path.endsWith(_extension))
            _track(_idOf(entity), _lengthOf(entity)),
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

  static int _lengthOf(File file) {
    try {
      return file.lengthSync();
    } on FileSystemException {
      return 0;
    }
  }

  String _track(String id, int size) {
    _sizes[id] = size;
    _byteCount += size;
    return id;
  }

  void _untrack(String id) => _byteCount -= _sizes.remove(id) ?? 0;

  static String _idOf(File file) {
    final name = file.uri.pathSegments.last;
    return name.substring(0, name.length - _extension.length);
  }

  Future<T> _job<T>(Future<T> job) {
    _jobs.add(job);
    job.whenComplete(() => _jobs.remove(job)).ignore();
    return job;
  }

  /// The number of queued events.
  int get length => _ids.length;

  /// The number of queued events the worker has measured. The others come
  /// after them, and can still be dropped for their size.
  int get measuredLength => _ids.length - _writing.length;

  /// The serialized size of the measured events, in bytes.
  int get byteCount {
    _ids; // Loads the queue, and the sizes, on first use.
    return _byteCount;
  }

  /// Completes once the worker has done every job the queue gave it so far:
  /// the added events are measured and written, the removed ones deleted.
  Future<void> get settled =>
      _jobs.isEmpty ? SynchronousFuture(null) : _settle();

  Future<void> get _submitted => _jobs.isEmpty
      ? SynchronousFuture(null)
      : Future.wait(_jobs.toList()).then((_) {});

  Future<void> _settle() async {
    // Jobs that finishing jobs start are waited for too.
    while (_jobs.isNotEmpty) {
      await Future.wait(_jobs.toList());
    }
  }

  /// Adds [event] at the end of the queue, and completes with what the
  /// worker did with it. With [maxBytes], an event whose serialized size is
  /// over it is removed again and not written.
  Future<QueueWriteResult> add(Map<String, Object?> event, {int? maxBytes}) {
    // Loaded before the new file exists, which would otherwise be listed
    // on top of being added.
    final ids = _ids;
    final id = generateUuidV7();
    ids.add(id);
    _writing.add(id);
    if (_writesInFlight >= maxWritesInFlight) {
      final unsent = _UnsentWrite(event, maxBytes);
      _unsent[id] = unsent;
      return _job(unsent.result.future);
    }
    return _job(_write(id, event, maxBytes));
  }

  Future<QueueWriteResult> _write(
    String id,
    Map<String, Object?> event,
    int? maxBytes,
  ) {
    _writesInFlight++;
    final path = _directory.isEmpty ? null : _pathOf(id);
    QueueWriteResult done(QueueWriteResult result) {
      _writesInFlight--;
      _writeNext();
      _writing.remove(id);
      if (result.tooLarge) {
        _ids.remove(id);
        return result;
      }
      // Removed while the worker wrote it: the deletion comes after.
      if (!_ids.contains(id)) return result;
      _track(id, result.bytes ?? 0);
      if (path == null) {
        _unwritten[id] = event;
      } else if (result.error case final error?) {
        _unwritten[id] = event;
        _logger()?.warn(
            'Failed to persist a queued event; it is kept in memory until it '
            'is sent:',
            error);
      }
      return result;
    }

    return _worker.write(path, event, maxBytes: maxBytes).then(
          done,
          onError: (Object e) =>
              done((bytes: null, tooLarge: false, error: '$e')),
        );
  }

  void _writeNext() {
    while (_writesInFlight < maxWritesInFlight && _unsent.isNotEmpty) {
      final id = _unsent.keys.first;
      final unsent = _unsent.remove(id)!;
      unsent.result.complete(_write(id, unsent.event, unsent.maxBytes));
    }
  }

  /// Returns up to [count] events from the front of the queue, oldest
  /// first, once the events added so far are written. Events added after
  /// the call are not waited for, so that sustained captures can't hold back
  /// the batch.
  ///
  /// With [maxBytes], the events also stay within that serialized size. Each
  /// event is checked before it is read, so one that does not fit is left
  /// for the next peek, and the first event always comes, alone when it is
  /// over the limit.
  Future<List<PostHogQueuedEvent>> peek(int count, {int? maxBytes}) =>
      _submitted.then((_) => _peekWritten(count, maxBytes));

  Future<List<PostHogQueuedEvent>> _peekWritten(
    int count,
    int? maxBytes, {
    Set<String> skipped = const {},
  }) {
    final selected = <String>[];
    var bytes = 0;
    for (final id in _ids) {
      if (skipped.contains(id)) continue;
      if (selected.length >= count || _writing.contains(id)) break;
      final size = _sizes[id] ?? 0;
      if (maxBytes != null && selected.isNotEmpty && bytes + size > maxBytes) {
        break;
      }
      selected.add(id);
      bytes += size;
    }
    final toRead = [
      for (final id in selected)
        if (!_unwritten.containsKey(id)) id,
    ];
    final read = toRead.isEmpty
        ? SynchronousFuture(const <QueueReadResult>[])
        : _job(_worker.read([for (final id in toRead) _pathOf(id)]));
    return read.then((read) {
      final events = _collect(selected, {
        for (var i = 0; i < toRead.length; i++) toRead[i]: read[i],
      });
      // An empty peek ends the flush, which must not leave the events behind
      // the unreadable ones unsent.
      return events.isEmpty && selected.isNotEmpty
          ? _peekWritten(count, maxBytes, skipped: {...skipped, ...selected})
          : events;
    });
  }

  /// The [selected] events still queued, from memory or from [read].
  List<PostHogQueuedEvent> _collect(
    List<String> selected,
    Map<String, QueueReadResult> read,
  ) {
    final events = <PostHogQueuedEvent>[];
    final gone = <String>{};
    final queued = _ids.toSet();
    for (final id in selected) {
      // Removed while the files were read.
      if (!queued.contains(id)) continue;
      final event = _unwritten[id];
      if (event != null) {
        events.add((id: id, event: event));
        continue;
      }
      final result = read[id]!;
      if (result.event case final event?) {
        events.add((id: id, event: event));
      } else if (result.gone) {
        // Sent by another client using the same directory, or unreadable
        // and deleted.
        if (result.error case final error?) {
          _logger()
              ?.warn('Deleted queued event $id, which cannot be read:', error);
        }
        gone.add(id);
      } else {
        _logger()?.warn('Skipping queued event $id for now:', result.error);
      }
    }
    if (gone.isNotEmpty) {
      _ids.removeWhere(gone.contains);
      gone.forEach(_untrack);
    }
    return events;
  }

  /// Removes the events with the given [ids]; unknown ids are ignored.
  void remove(Iterable<String> ids) {
    final removed = ids.toSet();
    _ids.removeWhere(removed.contains);
    _forget(removed);
  }

  /// Removes up to [count] events from the front of the queue.
  void removeOldest(int count) {
    final oldest = _ids.take(count).toList();
    _ids.removeRange(0, oldest.length);
    _forget(oldest);
  }

  /// Removes the oldest events still waiting to be written until at most
  /// [maxCount] wait. Returns how many were removed.
  ///
  /// Their size is unknown, so eviction by [removeOldestOver] can't reach
  /// them: this is what bounds a queue with a size limit on its events.
  int removeOldestUnsentOver(int maxCount) {
    final overflow = _unsent.length - maxCount;
    if (overflow <= 0) return 0;
    remove(_unsent.keys.take(overflow).toList());
    return overflow;
  }

  /// Removes the oldest events until the measured ones hold at most
  /// [maxBytes], always keeping the newest measured event. Returns how many
  /// were removed.
  int removeOldestOver(int maxBytes) {
    var total = byteCount;
    var count = 0;
    while (total > maxBytes && count < measuredLength - 1) {
      total -= _sizes[_ids[count]] ?? 0;
      count++;
    }
    removeOldest(count);
    return count;
  }

  void _forget(Iterable<String> ids) {
    final paths = <String>[];
    for (final id in ids) {
      _untrack(id);
      _writing.remove(id);
      if (_unsent.remove(id) case final unsent?) {
        unsent.result.complete((bytes: null, tooLarge: false, error: null));
      } else if (_unwritten.remove(id) == null && _directory.isNotEmpty) {
        paths.add(_pathOf(id));
      }
    }
    if (paths.isEmpty) return;
    _job(_worker.delete(paths)).then((errors) {
      for (final error in errors) {
        _logger()?.warn(
            'Failed to delete a queued event; it may be sent again:', error);
      }
    }).ignore();
  }
}

final class _UnsentWrite {
  _UnsentWrite(this.event, this.maxBytes);

  final Map<String, Object?> event;
  final int? maxBytes;
  final result = Completer<QueueWriteResult>();
}
