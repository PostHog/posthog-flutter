import 'dart:ffi';
import 'dart:io';

import 'util/logging.dart';

/// The local IANA time zone, such as `Europe/Berlin`.
class DesktopTimeZone {
  /// Reads `TZ`, then the system time zone. Returns null if neither identifies
  /// one.
  static String? read(Map<String, String> environment) {
    final fromVariable = fromTzVariable(environment['TZ']);
    if (fromVariable != null) return fromVariable;
    if (Platform.isWindows) {
      try {
        return _WindowsTimeZone.read();
      } catch (e) {
        printIfDebug('[PostHog] Could not read the Windows time zone: $e');
        return null;
      }
    }
    return _readLinux();
  }

  /// `/etc/localtime` is usually a link into the zoneinfo directory. Where
  /// it is a copy, as in many containers, Debian-based systems still name
  /// the zone in `/etc/timezone`.
  static String? _readLinux() {
    try {
      final zone = fromZoneInfoPath(
        File('/etc/localtime').resolveSymbolicLinksSync(),
      );
      if (zone != null) return zone;
    } on FileSystemException {
      // No /etc/localtime: /etc/timezone may still name the zone.
    }
    try {
      return fromTimezoneFile(File('/etc/timezone').readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  /// The zone named by the contents of an `/etc/timezone` file, such as
  /// `Europe/Berlin` followed by a line break.
  static String? fromTimezoneFile(String contents) =>
      _zoneName(contents.trim());

  /// The zone a `TZ` value names: a zone name, optionally after a `:`, or
  /// the path of a file in a zoneinfo directory.
  ///
  /// Null for a POSIX rule such as `CET-1CEST,M3.5.0,M10.5.0/3`, which names
  /// no zone.
  static String? fromTzVariable(String? value) {
    if (value == null) return null;
    final tz = value.startsWith(':') ? value.substring(1) : value;
    return tz.startsWith('/') ? fromZoneInfoPath(tz) : _zoneName(tz);
  }

  /// The zone of a file in a zoneinfo directory, such as
  /// `/usr/share/zoneinfo/Europe/Berlin`.
  static String? fromZoneInfoPath(String path) {
    const directory = '/zoneinfo/';
    final index = path.indexOf(directory);
    if (index < 0) return null;
    return _zoneName(path.substring(index + directory.length));
  }

  static String? _zoneName(String value) {
    // Copies of the database that differ in leap seconds, not in zone names.
    final zone = value.replaceFirst(RegExp('^(posix|right)/'), '');
    return _zoneNamePattern.hasMatch(zone) ? zone : null;
  }

  /// Zone names use no digits, which would make them read as POSIX rules,
  /// except for the fixed offsets (`Etc/GMT+10`) and four legacy zones.
  static final _zoneNamePattern = RegExp(
    r'^([A-Za-z][A-Za-z._+-]*(/[A-Za-z._+-]+)*|(Etc/)?GMT[+-]?\d{1,2}|'
    r'EST5EDT|CST6CDT|MST7MDT|PST8PDT)$',
  );
}

abstract final class _WindowsTimeZone {
  static String? read() {
    const capacity = 256;
    final memory = _allocate(capacity * 2 + sizeOf<Int32>());
    if (memory.address == 0) return null;
    try {
      final result = memory.cast<Uint16>();
      final directoryLength = _getSystemDirectory(result, capacity);
      if (directoryLength == 0 || directoryLength >= capacity) return null;
      final directory =
          String.fromCharCodes(result.asTypedList(directoryLength));
      // System ICU maintains Windows/IANA mappings, unlike a static table.
      // https://learn.microsoft.com/windows/win32/intl/international-components-for-unicode--icu-
      final getDefaultTimeZone = DynamicLibrary.open('$directory\\icu.dll')
          .lookupFunction<
              Int32 Function(Pointer<Uint16>, Int32, Pointer<Int32>),
              int Function(Pointer<Uint16>, int, Pointer<Int32>)>(
        'ucal_getDefaultTimeZone',
      );
      final status = (memory.cast<Uint8>() + capacity * 2).cast<Int32>();
      status.value = 0;
      final length = getDefaultTimeZone(result, capacity, status);
      if (status.value > 0 || length <= 0 || length >= capacity) return null;
      final zone = String.fromCharCodes(result.asTypedList(length));
      return zone == 'Etc/Unknown' ? null : zone;
    } finally {
      _free(memory);
    }
  }

  static final _getSystemDirectory = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<Uint32 Function(Pointer<Uint16>, Uint32),
          int Function(Pointer<Uint16>, int)>('GetSystemDirectoryW');
  static final _ole32 = DynamicLibrary.open('ole32.dll');
  static final _allocate = _ole32.lookupFunction<Pointer<Void> Function(IntPtr),
      Pointer<Void> Function(int)>('CoTaskMemAlloc');
  static final _free = _ole32.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('CoTaskMemFree');
}
