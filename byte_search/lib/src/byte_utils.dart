import 'dart:typed_data';

import '../byte_search.dart';

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

/// Returns whether all [patterns] occur in [bytes] in the given order.
///
/// This is a convenience for “phrase A then phrase B then phrase C” checks
/// without allocating or converting to `String`.
///
/// The search starts at [start]. Each subsequent pattern must occur after the
/// previous match. The next search begins at the end of the previous match
/// (matches cannot overlap).
///
/// Special cases:
/// - If [patterns] is empty, returns `true`.
/// - Empty patterns are allowed. A `BytePattern` with `length == 0` matches at
///   the current position and does not advance the search.
///
/// ## Example
/// ```dart
/// final wonThe = BytePattern.fromAscii(needle: ' won the ');
/// final rollOn = BytePattern.fromAscii(needle: ' roll on ');
/// final withARoll = BytePattern.fromAscii(needle: ' with a roll of ');
///
/// final List<BytePattern> pats = [wonThe, rollOn, withARoll];
///
/// final ok = containsInOrder(
///   bytes: Uint8List.fromList(line.codeUnits),
///   patterns: pats,
///   start: messageStart,
/// );
/// ```
///
/// ## Performance
/// Worst-case `O(k * n)` where `k = patterns.length` and `n` is the searched
/// range. Does not allocate on the hot path. In practice this is fast when
/// patterns are selective and mismatches are common.
@pragma('vm:prefer-inline')
bool containsInOrder({required Uint8List bytes, required List<BytePattern> patterns, int start = 0}) {
  int i = start;
  for (final p in patterns) {
    final int hit = p.indexOf(haystack: bytes, start: i);
    if (hit == -1) return false;
    // Move start forward so the next phrase must occur after this one.
    i = hit + p.length;
  }
  return true;
}

/// This provides [start] to [end] (exclusive) slicing for bytes,
/// returned as a view (no copy).
/// If you need an owned copy, use `Uint8List.fromList(subBytes(...))`.
///
/// The returned list is a **view** into the same underlying buffer (no copy).
/// Mutating the returned view will mutate the original [bytes] as well.
///
/// If [end] is omitted, `bytes.length` is used.
///
/// Special cases:
/// - If `start == end`, returns an empty `Uint8List`.
///
/// Throws [RangeError] if `start` or `end` are out of bounds, or if `start > end`
/// (same behavior as `Uint8List.sublistView`).
///
/// ## Example
/// ```dart
/// final bytes = Uint8List.fromList('hello world'.codeUnits);
/// final sub = subBytes(bytes: bytes, start: 6, end: 11);
/// // sub is the bytes for "world"
/// ```
///
/// ## Parameters
/// - [bytes]: The source data.
/// - [start]: Start index (inclusive).
/// - [end]: End index (exclusive). Defaults to `bytes.length`.
///
/// ## Performance
/// Runs in `O(1)` time and does not allocate a new backing buffer.
@pragma('vm:prefer-inline')
Uint8List subBytes({required Uint8List bytes, required int start, int? end}) {
  if (start == (end ?? bytes.length)) return Uint8List(0);
  return Uint8List.sublistView(bytes, start, end);
}