import 'dart:typed_data';

import 'byte_set.dart';

/// Returns the index of the first occurrence of [value] in [bytes].
///
/// Searches the range `[start, end)` (start inclusive, end exclusive).
/// If [end] is omitted, the search continues to `bytes.length`.
///
/// Only the low 8 bits of [value] are used (`value & 0xFF`).
///
/// Returns `-1` if the byte does not occur in the given range.
///
/// ## Example
/// ```dart
/// final bytes = Uint8List.fromList([1, 2, 3, 2]);
/// final i = indexOfByte(bytes: bytes, value: 2); // 1
/// ```
///
/// ## Parameters
/// - [bytes]: The haystack to search.
/// - [value]: The byte value to search for. Only the low 8 bits are used.
/// - [start]: Start index (inclusive). Defaults to 0.
/// - [end]: End index (exclusive). Defaults to `bytes.length`.
///
/// ## Performance
/// Runs in `O(end - start)` time and does not allocate.
@pragma('vm:prefer-inline')
int indexOfByte({required Uint8List bytes, required int value, int start = 0, int? end}) {
  final int e = end ?? bytes.length;
  final int v = value & 0xFF;
  for (int i = start; i < e; i++) {
    if (bytes[i] == v) return i;
  }
  return -1;
}

/// Returns the index of the first byte in [bytes] that is contained in [set].
///
/// Searches the range `[start, end)` (start inclusive, end exclusive).
/// If [end] is omitted, the search continues to `bytes.length`.
///
/// Returns `-1` if no byte from [set] occurs in the given range.
///
/// ## Example
/// ```dart
/// final set = ByteSet.fromAsciiChars('\n\r');
/// final bytes = Uint8List.fromList('a\r\nb'.codeUnits);
/// final i = indexOfAnyByte(bytes: bytes, set: set); // 1
/// ```
///
/// ## Parameters
/// - [bytes]: The haystack to scan.
/// - [set]: The set of bytes to look for.
/// - [start]: Start index (inclusive). Defaults to 0.
/// - [end]: End index (exclusive). Defaults to `bytes.length`.
///
/// ## Performance
/// Runs in `O(end - start)` time and does not allocate.
@pragma('vm:prefer-inline')
int indexOfAnyByte({required Uint8List bytes, required ByteSet set, int start = 0, int? end}) {
  final int e = end ?? bytes.length;
  for (int i = start; i < e; i++) {
    if (set.contains(bytes[i])) return i;
  }
  return -1;
}

/// Returns the index of the first byte in [bytes] that is **not** contained in [set].
///
/// Searches the range `[start, end)` (start inclusive, end exclusive).
/// If [end] is omitted, the search continues to `bytes.length`.
///
/// Returns `-1` if every byte in the range is contained in [set].
///
/// This is useful for skipping over an “allowed” run, such as ASCII digits,
/// whitespace, or other delimiters.
///
/// ## Parameters
/// - [bytes]: The haystack to scan.
/// - [set]: The set of bytes considered “allowed”.
/// - [start]: Start index (inclusive). Defaults to 0.
/// - [end]: End index (exclusive). Defaults to `bytes.length`.
///
/// ## Performance
/// Runs in `O(end - start)` time and does not allocate.
@pragma('vm:prefer-inline')
int indexOfByteNotIn({required Uint8List bytes, required ByteSet set, int start = 0, int? end}) {
  final int e = end ?? bytes.length;
  for (int i = start; i < e; i++) {
    if (!set.contains(bytes[i])) return i;
  }
  return -1;
}

/// Returns whether [bytes] starts with [prefix] within the range `[start, end)`.
///
/// This checks whether the *range slice* `bytes.sublist(start, end)` begins with
/// [prefix]. If [end] is omitted, `bytes.length` is used.
///
/// Special cases:
/// - If [prefix] is empty, returns `true`.
/// - If the range length is shorter than `prefix.length`, returns `false`.
///
/// ## Example
/// ```dart
/// final b = Uint8List.fromList([10, 20, 30, 40]);
/// startsWithBytes(bytes: b, prefix: Uint8List.fromList([10, 20])); // true
/// ```
///
/// ## Parameters
/// - [bytes]: The data to test.
/// - [prefix]: The byte sequence to match at the start of the range.
/// - [start]: Start index (inclusive) of the range to consider. Defaults to 0.
/// - [end]: End index (exclusive) of the range to consider. Defaults to `bytes.length`.
///
/// ## Performance
/// Runs in `O(prefix.length)` time and does not allocate.
@pragma('vm:prefer-inline')
bool startsWithBytes({
  required Uint8List bytes,
  required Uint8List prefix,
  int start = 0,
  int? end,
}) {
  final int e = end ?? bytes.length;
  if (prefix.isEmpty) return true;
  if (e - start < prefix.length) return false;

  for (int i = 0; i < prefix.length; i++) {
    if (bytes[start + i] != prefix[i]) return false;
  }
  return true;
}

/// Returns whether [bytes] ends with [suffix] within the range `[start, end)`.
///
/// This checks whether the *range slice* `bytes.sublist(start, end)` ends with
/// [suffix]. If [end] is omitted, `bytes.length` is used.
///
/// Special cases:
/// - If [suffix] is empty, returns `true`.
/// - If the range length is shorter than `suffix.length`, returns `false`.
///
/// ## Example
/// ```dart
/// final b = Uint8List.fromList([10, 20, 30, 40]);
/// endsWithBytes(bytes: b, suffix: Uint8List.fromList([30, 40])); // true
/// endsWithBytes(bytes: b, suffix: Uint8List.fromList([20, 40])); // false
/// ```
///
/// ## Parameters
/// - [bytes]: The data to test.
/// - [suffix]: The byte sequence to match at the end of the range.
/// - [start]: Start index (inclusive) of the range to consider. Defaults to 0.
/// - [end]: End index (exclusive) of the range to consider. Defaults to `bytes.length`.
///
/// ## Performance
/// Runs in `O(suffix.length)` time and does not allocate.
@pragma('vm:prefer-inline')
bool endsWithBytes({
  required Uint8List bytes,
  required Uint8List suffix,
  int start = 0,
  int? end,
}) {
  final int e = end ?? bytes.length;
  if (suffix.isEmpty) return true;
  final int n = e - start;
  if (n < suffix.length) return false;

  final int s = e - suffix.length;
  for (int i = 0; i < suffix.length; i++) {
    if (bytes[s + i] != suffix[i]) return false;
  }
  return true;
}
