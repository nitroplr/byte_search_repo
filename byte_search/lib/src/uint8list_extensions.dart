import 'dart:typed_data';

import '../byte_search.dart';
import '_range_check.dart';

/// Extension methods on [Uint8List] providing high-performance, allocation-free
/// byte-search and scanning utilities.
///
/// These helpers are designed for low-level parsing and log scanning where
/// converting to `String` would be expensive or lossy. All methods operate
/// directly on the underlying byte buffer and avoid allocations on the hot path.
///
/// The APIs generally follow these conventions:
/// - Searches operate on the range `[start, end)` (start inclusive, end exclusive).
/// - If `end` is omitted, the buffer’s full length is used.
/// - Methods return `-1` when no match is found.
/// - Inputs that are not already bytes (like the value passed to `indexOfByte`) are masked to the low 8 bits (& 0xFF).
///
/// This extension pairs with:
/// - [BytePattern] for compiled multi-byte searches
/// - [ByteSet] for constant-time membership tests
extension ByteSearchU8 on Uint8List {
  /// Returns the index of the first occurrence of [value] in this buffer.
  ///
  /// Searches the range `[start, end)` (start inclusive, end exclusive).
  /// If [end] is omitted, the search continues to `length`.
  ///
  /// Only the low 8 bits of [value] are used (`value & 0xFF`).
  ///
  /// Returns `-1` if the byte does not occur in the given range.
  ///
  /// ## Example
  /// ```dart
  /// final bytes = Uint8List.fromList([1, 2, 3, 2]);
  /// final i = bytes.indexOfByte(2); // 1
  /// ```
  ///
  /// ## Parameters
  /// - [value]: The byte value to search for. Only the low 8 bits are used.
  /// - [start]: Start index (inclusive). Defaults to 0.
  /// - [end]: End index (exclusive). Defaults to `length`.
  ///
  /// ## Performance
  /// Runs in `O(end - start)` time and does not allocate.
  ///
  /// ## Throws
  /// - [RangeError] in debug mode if [start]/[end] are out of bounds or `start > end`
  @pragma('vm:prefer-inline')
  int indexOfByte(int value, {int start = 0, int? end}) {
    final int e = end ?? length;
    checkRange(start, e, length);

    final int v = value & 0xFF;
    for (int i = start; i < e; i++) {
      if (this[i] == v) return i;
    }
    return -1;
  }

  /// Returns the index of the first byte in this buffer that is contained in [set].
  ///
  /// Searches the range `[start, end)` (start inclusive, end exclusive).
  /// If [end] is omitted, the search continues to `length`.
  ///
  /// Returns `-1` if no byte from [set] occurs in the given range.
  ///
  /// ## Example
  /// ```dart
  /// final set = ByteSet.fromAsciiChars('\n\r');
  /// final bytes = Uint8List.fromList('a\r\nb'.codeUnits);
  /// final i = bytes.indexOfAnyByte(set); // 1
  /// ```
  ///
  /// ## Parameters
  /// - [set]: The set of bytes to look for.
  /// - [start]: Start index (inclusive). Defaults to 0.
  /// - [end]: End index (exclusive). Defaults to `length`.
  ///
  /// ## Performance
  /// Runs in `O(end - start)` time and does not allocate.
  ///
  /// ## Throws
  /// - [RangeError] in debug mode if [start]/[end] are out of bounds or `start > end`
  @pragma('vm:prefer-inline')
  int indexOfAnyByte(ByteSet set, {int start = 0, int? end}) {
    final int e = end ?? length;
    checkRange(start, e, length);

    for (int i = start; i < e; i++) {
      if (set.contains(this[i])) return i;
    }
    return -1;
  }

  /// Returns the index of the first byte in this buffer that is **not** contained
  /// in [set].
  ///
  /// Searches the range `[start, end)` (start inclusive, end exclusive).
  /// If [end] is omitted, the search continues to `length`.
  ///
  /// Returns `-1` if every byte in the range is contained in [set].
  ///
  /// This is useful for skipping over an “allowed” run, such as ASCII digits,
  /// whitespace, or other delimiters.
  ///
  /// ## Parameters
  /// - [set]: The set of bytes considered “allowed”.
  /// - [start]: Start index (inclusive). Defaults to 0.
  /// - [end]: End index (exclusive). Defaults to `length`.
  ///
  /// ## Performance
  /// Runs in `O(end - start)` time and does not allocate.
  ///
  /// ## Throws
  /// - [RangeError] in debug mode if [start]/[end] are out of bounds or `start > end`
  @pragma('vm:prefer-inline')
  int indexOfByteNotIn(ByteSet set, {int start = 0, int? end}) {
    final int e = end ?? length;
    checkRange(start, e, length);

    for (int i = start; i < e; i++) {
      if (!set.contains(this[i])) return i;
    }
    return -1;
  }

  /// Returns whether this buffer starts with [prefix] within the range
  /// `[start, end)`.
  ///
  /// This checks whether the *range slice* `sublist(start, end)` begins with
  /// [prefix]. If [end] is omitted, `length` is used.
  ///
  /// Special cases:
  /// - If [prefix] is empty, returns `true`.
  /// - If the range length is shorter than `prefix.length`, returns `false`.
  ///
  /// ## Example
  /// ```dart
  /// final b = Uint8List.fromList([10, 20, 30, 40]);
  /// final ok = b.startsWithBytes(Uint8List.fromList([10, 20]));
  /// ```
  ///
  /// ## Parameters
  /// - [prefix]: The byte sequence to match at the start of the range.
  /// - [start]: Start index (inclusive). Defaults to 0.
  /// - [end]: End index (exclusive). Defaults to `length`.
  ///
  /// ## Performance
  /// Runs in `O(prefix.length)` time and does not allocate.
  ///
  /// ## Throws
  /// - [RangeError] in debug mode if [start]/[end] are out of bounds or `start > end`
  @pragma('vm:prefer-inline')
  bool startsWithBytes(Uint8List prefix, {int start = 0, int? end}) {
    final int e = end ?? length;
    checkRange(start, e, length);

    final int m = prefix.length;
    if (m == 0) return true;
    if (e - start < m) return false;

    for (int i = 0; i < m; i++) {
      if (this[start + i] != prefix[i]) return false;
    }
    return true;
  }

  /// Returns whether this buffer ends with [suffix] within the range
  /// [start] (inclusive) to [end] (exclusive).
  ///
  /// This checks whether the *range slice* `sublist(start, end)` ends with
  /// [suffix]. If [end] is omitted, `length` is used.
  ///
  /// Special cases:
  /// - If [suffix] is empty, returns `true`.
  /// - If the range length is shorter than `suffix.length`, returns `false`.
  ///
  /// ## Example
  /// ```dart
  /// final b = Uint8List.fromList([10, 20, 30, 40]);
  /// final ok = b.endsWithBytes(Uint8List.fromList([30, 40]));
  /// ```
  ///
  /// ## Parameters
  /// - [suffix]: The byte sequence to match at the end of the range.
  /// - [start]: Start index (inclusive). Defaults to 0.
  /// - [end]: End index (exclusive). Defaults to `length`.
  ///
  /// ## Performance
  /// Runs in `O(suffix.length)` time and does not allocate.
  ///
  /// ## Throws
  /// - [RangeError] in debug mode if [start]/[end] are out of bounds or `start > end`
  @pragma('vm:prefer-inline')
  bool endsWithBytes(Uint8List suffix, {int start = 0, int? end}) {
    final int e = end ?? length;
    checkRange(start, e, length);

    final int m = suffix.length;
    if (m == 0) return true;

    final int n = e - start;
    if (n < m) return false;

    final int s = e - m;
    for (int i = 0; i < m; i++) {
      if (this[s + i] != suffix[i]) return false;
    }
    return true;
  }

  /// Returns whether all [patterns] occur in this buffer in the given order.
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
  /// - Empty patterns are allowed. A [BytePattern] with `length == 0` matches at
  ///   the current position and does not advance the search.
  ///
  /// ## Example
  /// ```dart
  /// final wonThe = BytePattern.fromAscii(needle: ' won the ');
  /// final rollOn = BytePattern.fromAscii(needle: ' roll on ');
  /// final withARoll = BytePattern.fromAscii(needle: ' with a roll of ');
  ///
  /// final pats = [wonThe, rollOn, withARoll];
  ///
  /// final ok = bytes.containsInOrder(pats, messageStart);
  /// ```
  ///
  /// ## Performance
  /// Worst-case `O(k * n)` where `k = patterns.length` and `n` is the searched
  /// range. Does not allocate on the hot path. In practice this is fast when
  /// patterns are selective and mismatches are common.
  ///
  /// ## Throws
  /// - [RangeError] in debug mode if [start] is out of bounds
  @pragma('vm:prefer-inline')
  bool containsInOrder(Iterable<BytePattern> patterns, [int start = 0]) {
    checkRange(start, start, length); // validates start in [0, length]

    int i = start;
    for (final p in patterns) {
      if (p.length == 0) continue;
      final int hit = p.indexOf(haystack: this, start: i);
      if (hit == -1) return false;
      i = hit + p.length;
    }
    return true;
  }

  /// Returns a view of this buffer from [start] (inclusive) to [end] (exclusive).
  ///
  /// The returned list is a **view** into the same underlying buffer (no copy).
  /// Mutating the returned view will mutate the original buffer as well.
  ///
  /// If [end] is omitted, `length` is used.
  ///
  /// Special cases:
  /// - If `start == end`, returns an empty `Uint8List`.
  ///
  /// Throws [RangeError] if `start` or `end` are out of bounds, or if `start > end`
  /// (same behavior as [Uint8List.sublistView]).
  ///
  /// ## Example
  /// ```dart
  /// final bytes = Uint8List.fromList('hello world'.codeUnits);
  /// final sub = bytes.subView(6, 11); // "world"
  /// ```
  ///
  /// ## Parameters
  /// - [start]: Start index (inclusive).
  /// - [end]: End index (exclusive). Defaults to `length`.
  ///
  /// ## Performance
  /// Runs in `O(1)` time and does not allocate a new backing buffer.
  ///
  /// ## Throws
  /// - [RangeError] in debug mode if [start]/[end] are out of bounds or `start > end`
  @pragma('vm:prefer-inline')
  Uint8List subView(int start, [int? end]) {
    final int e = end ?? length;
    checkRange(start, e, length);
    return Uint8List.sublistView(this, start, e);
  }
}
