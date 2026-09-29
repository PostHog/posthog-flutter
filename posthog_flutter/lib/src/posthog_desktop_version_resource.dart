import 'dart:ffi';

/// Reads the version resource of a Windows executable: the VERSIONINFO block
/// a Flutter app declares in `windows/runner/Runner.rc`.
///
/// Only dart:ffi is used, so the plugin does not add package:ffi or
/// package:win32 to the dependencies of every app for three API calls.
class WindowsVersionResource {
  /// The `ProductName` and `ProductVersion` strings of [executable], null
  /// where the resource does not carry them.
  ///
  /// Throws when the Windows API cannot be loaded.
  static ({String? productName, String? productVersion}) read(
    String executable,
  ) {
    final memory = _NativeMemory();
    try {
      final path = memory.utf16(executable);
      final size = _getFileVersionInfoSize(path, memory.allocate<Uint32>(4));
      if (size == 0) return _none;
      final block = memory.allocate<Void>(size);
      if (_getFileVersionInfo(path, 0, size, block) == 0) return _none;

      final value = memory.allocate<Pointer<Void>>(sizeOf<Pointer<Void>>());
      final length = memory.allocate<Uint32>(4);
      bool query(String subBlock) =>
          _verQueryValue(block, memory.utf16(subBlock), value, length) != 0 &&
          length.value > 0;

      // The strings are stored per language and code page, which the runner
      // template declares once: 0x0409 and 1252 name the table "040904e4".
      if (!query(r'\VarFileInfo\Translation') || length.value < 4) {
        return _none;
      }
      final translation = value.value.cast<Uint16>();
      final table = '\\StringFileInfo\\'
          '${_hex4(translation[0])}${_hex4(translation[1])}';

      String? string(String name) {
        if (!query('$table\\$name')) return null;
        final chars = value.value.cast<Uint16>().asTypedList(length.value);
        final end = chars.indexOf(0);
        final result = String.fromCharCodes(chars, 0, end < 0 ? null : end);
        return result.isEmpty ? null : result;
      }

      return (
        productName: string('ProductName'),
        productVersion: string('ProductVersion'),
      );
    } finally {
      memory.releaseAll();
    }
  }

  static const ({String? productName, String? productVersion}) _none =
      (productName: null, productVersion: null);

  static String _hex4(int value) => value.toRadixString(16).padLeft(4, '0');
}

/// Native memory for [WindowsVersionResource.read], released all at once.
class _NativeMemory {
  final _allocations = <Pointer<Void>>[];

  Pointer<T> allocate<T extends NativeType>(int byteCount) {
    final pointer = _coTaskMemAlloc(byteCount);
    if (pointer.address == 0) {
      throw StateError('Could not allocate $byteCount bytes');
    }
    _allocations.add(pointer);
    return pointer.cast();
  }

  /// A NUL-terminated copy of [value] in UTF-16, the encoding of the Windows
  /// API.
  Pointer<Uint16> utf16(String value) {
    final units = value.codeUnits;
    final pointer = allocate<Uint16>((units.length + 1) * 2);
    pointer.asTypedList(units.length + 1)
      ..setAll(0, units)
      ..last = 0;
    return pointer;
  }

  void releaseAll() {
    _allocations
      ..forEach(_coTaskMemFree)
      ..clear();
  }
}

// The API set resolves to the system implementation, never to a version.dll
// placed next to the executable.
final _versionApi = DynamicLibrary.open('api-ms-win-core-version-l1-1-0.dll');

final _getFileVersionInfoSize = _versionApi.lookupFunction<
    Uint32 Function(Pointer<Uint16> filename, Pointer<Uint32> handle),
    int Function(
      Pointer<Uint16> filename,
      Pointer<Uint32> handle,
    )>('GetFileVersionInfoSizeW');

final _getFileVersionInfo = _versionApi.lookupFunction<
    Int32 Function(
      Pointer<Uint16> filename,
      Uint32 handle,
      Uint32 length,
      Pointer<Void> data,
    ),
    int Function(
      Pointer<Uint16> filename,
      int handle,
      int length,
      Pointer<Void> data,
    )>('GetFileVersionInfoW');

final _verQueryValue = _versionApi.lookupFunction<
    Int32 Function(
      Pointer<Void> block,
      Pointer<Uint16> subBlock,
      Pointer<Pointer<Void>> buffer,
      Pointer<Uint32> length,
    ),
    int Function(
      Pointer<Void> block,
      Pointer<Uint16> subBlock,
      Pointer<Pointer<Void>> buffer,
      Pointer<Uint32> length,
    )>('VerQueryValueW');

final _ole32 = DynamicLibrary.open('ole32.dll');

final _coTaskMemAlloc = _ole32.lookupFunction<Pointer<Void> Function(Size size),
    Pointer<Void> Function(int size)>('CoTaskMemAlloc');

final _coTaskMemFree = _ole32.lookupFunction<Void Function(Pointer<Void> block),
    void Function(Pointer<Void> block)>('CoTaskMemFree');
