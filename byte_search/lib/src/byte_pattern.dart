import 'dart:typed_data';

/// A precompiled byte-search pattern optimized for high-reject workloads.
///
/// `BytePattern` is designed for repeated searches of the same *needle* across
/// many *haystacks*. It precomputes a Boyer–Moore–Horspool-style shift table and
/// uses fast-reject guards on the first/last byte to minimize comparisons.
///
/// This is a good fit when:
/// - you search many times (e.g. millions of scans),
/// - matches are relatively rare (high reject rate),
/// - needles are short-to-medium length,
/// - you want predictable performance with minimal allocations.
///
/// The compiled pattern is immutable and can be reused across searches.
///
/// ## Example
/// ```dart
/// final pat = BytePattern.fromAscii(needle: 'ERROR');
/// final i = pat.indexOf(haystack: bytes);
/// if (i != -1) { ... }
/// ```
///
/// ## Empty pattern behavior
/// If the needle is empty (`length == 0`), [indexOf] returns the provided `start`
/// value and [hasMatch] returns `true`.
///
/// See also:
/// - `ByteSet` for constant-time membership checks when scanning.
class BytePattern {
  final Uint8List _pat;
  final int _m;
  final int _last;
  final int _firstByte;
  final int _lastByte;
  final Uint16List _shift;

  /// The length of the needle (pattern) in bytes.
  ///
  /// This is the number of bytes that must match contiguously in a haystack for
  /// a match to be reported.
  int get length => _m;

  /// Creates a compiled matcher from the raw byte [needle].
  ///
  /// The [needle] bytes are used as-is (no normalization). The matcher precomputes
  /// an internal shift table so that subsequent searches can skip ahead quickly.
  ///
  /// ## Parameters
  /// - [needle]: The byte sequence to search for.
  ///
  /// ## Empty pattern behavior
  /// If `needle.isEmpty`, [indexOf] returns the provided `start` value and
  /// [hasMatch] returns `true`.
  ///
  /// ## Performance
  /// Construction runs in `O(needle.length + 256)` time and allocates a small
  /// fixed-size table (256 entries).
  BytePattern(Uint8List needle)
      : _pat = needle,
        _m = needle.length,
        _last = needle.length - 1,
        _firstByte = needle.isEmpty ? 0 : needle[0],
        _lastByte = needle.isEmpty ? 0 : needle[needle.length - 1],
        _shift = Uint16List(256) {
    final int m = needle.length;
    for (int i = 0; i < 256; i++) {
      _shift[i] = m;
    }
    for (int i = 0; i < m - 1; i++) {
      _shift[needle[i]] = (m - 1 - i);
    }
  }

  /// Creates a compiled matcher from an ASCII string with minimal overhead.
  ///
  /// This converts [needle] to bytes by taking each UTF-16 code unit as a byte and keeping
  /// only the low 8 bits (`codeUnit & 0xFF`). This is fast and avoids charset
  /// handling, but it also means non-ASCII characters will be truncated.
  ///
  /// Use this when you know the needle is ASCII (or when truncation is acceptable).
  ///
  /// ## Parameters
  /// - [needle]: The string to convert to bytes (each code unit truncated to a byte).
  ///
  /// ## Performance
  /// Runs in `O(needle.length)` time and allocates one `Uint8List` of the same
  /// length as the string's code units, plus the matcher’s internal tables.
  factory BytePattern.fromAscii({required String needle}) {
    final units = needle.codeUnits;
    final bytes = Uint8List(units.length);
    for (int i = 0; i < units.length; i++) {
      bytes[i] = units[i] & 0xFF;
    }
    return BytePattern(bytes);
  }

  /// Returns whether this pattern occurs in [haystack] within `[start, end)`.
  ///
  /// This is equivalent to:
  /// ```dart
  /// indexOf(haystack: haystack, start: start, end: end) != -1
  /// ```
  ///
  /// ## Parameters
  /// - [haystack]: The byte buffer to search.
  /// - [start]: Start index (inclusive) for the search. Defaults to 0.
  /// - [end]: End index (exclusive) for the search. Defaults to `haystack.length`.
  ///
  /// ## Returns
  /// `true` if a match exists in the range; otherwise `false`.
  ///
  /// ## Performance
  /// Typically sublinear on random data due to skipping; worst-case linear in the
  /// searched range. Does not allocate.
  @pragma('vm:prefer-inline')
  bool hasMatch({required Uint8List haystack, int start = 0, int? end}) =>
      indexOf(haystack: haystack, start: start, end: end) != -1;

  /// Returns the index of the first occurrence of this pattern in [haystack].
  ///
  /// Searches the range `[start, end)` (start inclusive, end exclusive).
  ///
  /// ## Parameters
  /// - [haystack]: The byte buffer to search.
  /// - [start]: Start index (inclusive) for the search. Defaults to 0.
  /// - [end]: End index (exclusive) for the search. Defaults to `haystack.length`.
  ///
  /// ## Returns
  /// The start index of the first match, or `-1` if no match exists in the range.
  ///
  /// ## Empty pattern behavior
  /// If `length == 0`, returns [start].
  ///
  /// ## Performance
  /// Typically sublinear on random data due to skipping; worst-case linear in the
  /// searched range. Does not allocate.
  int indexOf({required Uint8List haystack, int start = 0, int? end}) {
    final int m = _m;
    if (m == 0) return start;

    final int e = end ?? haystack.length;
    final int n = e - start;
    if (n < m) return -1;

    int i = start;
    final int maxI = e - m;

    while (i <= maxI) {
      final int lastPos = i + _last;
      final int hbLast = haystack[lastPos];

      if (hbLast == _lastByte && haystack[i] == _firstByte) {
        int j = _last - 1;
        while (j >= 1 && haystack[i + j] == _pat[j]) {
          j--;
        }
        if (j < 1) return i;
      }

      i += _shift[hbLast];
    }
    return -1;
  }
}
