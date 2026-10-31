import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:meta/meta.dart';

import 'logger.dart';

/// What [QueueWorker.write] did with an event: its serialized size in
/// bytes, null when it cannot be encoded; whether it was over the size limit
/// and so not written; and the error that kept its file from being written.
typedef QueueWriteResult = ({int? bytes, bool tooLarge, String? error});

/// A queued event read back by [QueueWorker.read]: the event, or null with
/// the reason. A file that is [gone] was sent by another client, or could
/// not be decoded and was deleted; any other [error] may pass.
typedef QueueReadResult = ({
  Map<String, Object?>? event,
  bool gone,
  String? error,
});

/// A request body as it is sent: its [payload], gzipped or not as [gzipped]
/// says, and its UTF-8 [length] before compression.
typedef EncodedBody = ({Uint8List payload, int length, bool gzipped});

/// Does the queue work that grows with the size of the events away from the
/// app's UI isolate: encoding events to JSON and measuring them, writing,
/// reading and deleting their files, and encoding and compressing request
/// bodies. An 8 MiB AI event takes tens of milliseconds to encode and write,
/// and over a hundred to compress, which would drop frames.
///
/// Jobs run one at a time, in the order they were submitted, so a file is
/// deleted only after it is written and read only once it is complete.
abstract class QueueWorker {
  /// The worker of every queue in this isolate: a background isolate,
  /// started on first use.
  static QueueWorker get shared => _shared ??= _IsolateQueueWorker();
  static QueueWorker? _shared;

  /// The worker a storage uses when it is not given one. Tests that drive
  /// time with fake timers set it to [QueueWorker.inline].
  static QueueWorker Function() defaultWorker = () => shared;

  /// A worker that runs every job right away on the calling isolate, and
  /// returns its result as a [SynchronousFuture], so that a queue using it
  /// behaves as if it did its file work itself. Tests that drive time with
  /// fake timers use it: messages from another isolate never arrive inside a
  /// fake zone.
  factory QueueWorker.inline() = _InlineQueueWorker;

  /// A background isolate worker of its own, for tests.
  @visibleForTesting
  factory QueueWorker.isolate() = _IsolateQueueWorker;

  /// Encodes [event] and writes it to the file at [path], replacing it
  /// atomically. Without a [path] the event is only measured. With
  /// [maxBytes], an event whose serialized size is over it is not written.
  Future<QueueWriteResult> write(
    String? path,
    Map<String, Object?> event, {
    int? maxBytes,
  });

  /// Reads and decodes the events at [paths], in order.
  Future<List<QueueReadResult>> read(List<String> paths);

  /// Deletes the files at [paths] and returns the errors of the ones that
  /// could not be deleted. A file that is already gone is not an error.
  Future<List<String>> delete(List<String> paths);

  /// Encodes [body] to JSON and compresses it with gzip when [gzip] is set.
  Future<EncodedBody> encodeBody(Object? body, {required bool gzip});

  /// Told when the jobs move back to the calling isolate. The worker is
  /// shared, so this is the logger of the client created last, while it is
  /// open.
  CoreLogger? logger;

  /// Whether the jobs run on another isolate.
  @visibleForTesting
  bool get runsInBackground;

  /// Stops the background isolate, as if it crashed. Its unanswered jobs,
  /// and every later one, then run on the calling isolate.
  @visibleForTesting
  void kill();
}

/// Replaces [file] with [contents] through a temporary file and a rename, so
/// the file never exists half-written. Creates the directory when missing.
void writeAtomically(File file, String contents) {
  final tmp = File('${file.path}.tmp');
  try {
    tmp.writeAsStringSync(contents);
  } on PathNotFoundException {
    tmp.parent.createSync(recursive: true);
    tmp.writeAsStringSync(contents);
  }
  tmp.renameSync(file.path);
}

sealed class _Job {
  const _Job();

  Object? run();
}

final class _Write extends _Job {
  const _Write(this.path, this.event, this.maxBytes);

  final String? path;
  final Map<String, Object?> event;
  final int? maxBytes;

  @override
  QueueWriteResult run() {
    final String json;
    try {
      json = jsonEncode(event);
    } catch (e) {
      return (bytes: null, tooLarge: false, error: '$e');
    }
    final bytes = utf8.encode(json).length;
    final maxBytes = this.maxBytes;
    if (maxBytes != null && bytes > maxBytes) {
      return (bytes: bytes, tooLarge: true, error: null);
    }
    final path = this.path;
    if (path == null) return (bytes: bytes, tooLarge: false, error: null);
    try {
      writeAtomically(File(path), json);
    } catch (e) {
      return (bytes: bytes, tooLarge: false, error: '$e');
    }
    return (bytes: bytes, tooLarge: false, error: null);
  }
}

final class _Read extends _Job {
  const _Read(this.paths);

  final List<String> paths;

  @override
  List<QueueReadResult> run() => [for (final path in paths) _readOne(path)];

  static QueueReadResult _readOne(String path) {
    final file = File(path);
    try {
      final event = jsonDecode(utf8.decode(file.readAsBytesSync()));
      if (event is Map<String, Object?>) {
        return (event: event, gone: false, error: null);
      }
      throw const FormatException('Not a JSON object');
    } on PathNotFoundException {
      return (event: null, gone: true, error: null);
    } on FormatException catch (e) {
      try {
        file.deleteSync();
      } on FileSystemException {
        // Read again, and deleted again, by a later run.
      }
      return (event: null, gone: true, error: '$e');
    } on FileSystemException catch (e) {
      return (event: null, gone: false, error: '$e');
    }
  }
}

final class _Delete extends _Job {
  const _Delete(this.paths);

  final List<String> paths;

  @override
  List<String> run() {
    final errors = <String>[];
    for (final path in paths) {
      try {
        File(path).deleteSync();
      } on PathNotFoundException {
        // Already deleted by another client using the same directory.
      } on FileSystemException catch (e) {
        errors.add('$e');
      }
    }
    return errors;
  }
}

final class _EncodeBody extends _Job {
  const _EncodeBody(this.body, this.compress);

  final Object? body;
  final bool compress;

  @override
  EncodedBody run() {
    final bytes = utf8.encode(jsonEncode(body));
    return (
      payload: compress ? Uint8List.fromList(gzip.encode(bytes)) : bytes,
      length: bytes.length,
      gzipped: compress,
    );
  }
}

/// Turns the [QueueWorker] calls into jobs for [submit].
abstract class _JobRunner implements QueueWorker {
  @override
  CoreLogger? logger;

  Future<Object?> submit(_Job job);

  Future<T> _submit<T>(_Job job) => submit(job).then((result) => result as T);

  @override
  Future<QueueWriteResult> write(
    String? path,
    Map<String, Object?> event, {
    int? maxBytes,
  }) =>
      _submit(_Write(path, event, maxBytes));

  @override
  Future<List<QueueReadResult>> read(List<String> paths) =>
      _submit(_Read(paths));

  @override
  Future<List<String>> delete(List<String> paths) => _submit(_Delete(paths));

  @override
  Future<EncodedBody> encodeBody(Object? body, {required bool gzip}) =>
      _submit(_EncodeBody(body, gzip));
}

final class _InlineQueueWorker extends _JobRunner {
  @override
  void kill() {}

  @override
  Future<Object?> submit(_Job job) {
    try {
      return SynchronousFuture(job.run());
    } catch (e, s) {
      return Future.error(e, s);
    }
  }

  @override
  bool get runsInBackground => false;
}

/// Runs the jobs on a background isolate of the same isolate group, so
/// the strings of an event go there without being copied. Falls
/// back to the calling isolate for good when the isolate cannot be started
/// or exits, running again the jobs it had not answered: every job can run
/// twice without harm.
final class _IsolateQueueWorker extends _JobRunner {
  _IsolateQueueWorker() {
    _results
      ..handler = _onResult
      ..keepIsolateAlive = false;
  }

  final _results = RawReceivePort(null, 'PostHog queue results');
  final _pending = <int, ({_Job job, Completer<Object?> completer})>{};
  var _nextId = 0;
  Future<SendPort?>? _port;
  Isolate? _isolate;
  var _inline = false;

  @override
  bool get runsInBackground => !_inline;

  @override
  void kill() => _isolate?.kill(priority: Isolate.immediate);

  @override
  Future<Object?> submit(_Job job) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = (job: job, completer: completer);
    // Unanswered jobs keep the app's isolate alive, so a command-line app
    // doesn't exit with events half-written; an idle worker doesn't.
    _results.keepIsolateAlive = true;
    // Chained on one future, so the jobs reach the worker in order, also
    // while it starts.
    (_port ??= _start()).then((port) {
      if (port == null) {
        _runInline(id);
      } else {
        port.send((id, job));
      }
    });
    return completer.future;
  }

  Future<SendPort?> _start() async {
    final ready = Completer<SendPort?>();
    _onReady = ready.complete;
    final exit = RawReceivePort(null, 'PostHog queue exit')
      ..keepIsolateAlive = false;
    exit.handler = (_) {
      exit.close();
      _fallBack();
      if (!ready.isCompleted) ready.complete(null);
    };
    try {
      _isolate = await Isolate.spawn(_workerMain, _results.sendPort,
          debugName: 'PostHog queue', onExit: exit.sendPort);
    } catch (e) {
      logger?.warn(
          'Cannot start the background isolate, the queue work runs on the '
          'UI isolate:',
          e);
      exit.close();
      _inline = true;
      return null;
    }
    return ready.future;
  }

  void Function(SendPort)? _onReady;

  void _onResult(Object? message) {
    if (message is SendPort) {
      _onReady?.call(message);
      _onReady = null;
      return;
    }
    final (id, ok, value) = message! as (int, bool, Object?);
    final pending = _pending.remove(id);
    if (_pending.isEmpty) _results.keepIsolateAlive = false;
    if (pending == null) return;
    if (ok) {
      pending.completer.complete(
          value is TransferableTypedData ? _materialize(value) : value);
    } else {
      pending.completer.completeError(value!);
    }
  }

  /// Rebuilds the body the worker sent back without copying its bytes.
  static EncodedBody _materialize(TransferableTypedData payload) {
    final bytes = payload.materialize();
    final header = bytes.asByteData(0, 5);
    return (
      payload: bytes.asUint8List(5),
      length: header.getUint32(0),
      gzipped: header.getUint8(4) == 1,
    );
  }

  void _fallBack() {
    logger?.warn('The background isolate stopped, the queue work runs on the '
        'UI isolate.');
    _inline = true;
    _port = Future.value(null);
    for (final id in _pending.keys.toList()..sort()) {
      _runInline(id);
    }
  }

  void _runInline(int id) {
    final pending = _pending.remove(id);
    if (_pending.isEmpty) _results.keepIsolateAlive = false;
    if (pending == null) return;
    try {
      pending.completer.complete(pending.job.run());
    } catch (e, s) {
      pending.completer.completeError(e, s);
    }
  }

  static void _workerMain(SendPort results) {
    final jobs = RawReceivePort(null, 'PostHog queue jobs');
    jobs.handler = (Object? message) {
      final (id, job) = message! as (int, _Job);
      try {
        final result = job.run();
        results.send((
          id,
          true,
          result is EncodedBody ? _transferable(result) : result,
        ));
      } catch (e) {
        results.send((id, false, '$e'));
      }
    };
    results.send(jobs.sendPort);
  }

  /// [body] as one transferable buffer: its length before compression in
  /// 4 bytes, whether it is gzipped in 1, then its payload.
  static TransferableTypedData _transferable(EncodedBody body) {
    final header = ByteData(5)
      ..setUint32(0, body.length)
      ..setUint8(4, body.gzipped ? 1 : 0);
    return TransferableTypedData.fromList([header, body.payload]);
  }
}
