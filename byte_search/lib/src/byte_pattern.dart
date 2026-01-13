

import 'dart:typed_data';

/// A Horspool-based byte matcher optimized for high-reject workloads.
///
/// Uses a Boyer–Moore–Horspool-style bad-character shift table with
/// additional fast-reject guards to minimize work when matches are rare.
///
/// Designed for:
/// - short haystacks
/// - precompiled patterns
/// - millions of searches with few matches
class BytePattern {
  final Uint8List _pat;
  final int _m;
  final int _last;
  final int _firstByte;
  final int _lastByte;
  final Uint16List _shift;
  /// Length of the pattern in bytes.
  int get length => _m;

  /// Create a matcher from raw byte pattern.
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

  /// Creates a matcher from an ASCII string with zero extra allocations.
  ///
  /// Each code unit is truncated to a byte (0..255).
  factory BytePattern.fromAscii({required String needle}) {
    final units = needle.codeUnits;
    final bytes = Uint8List(units.length);
    for (int i = 0; i < units.length; i++) {
      bytes[i] = units[i] & 0xFF;
    }
    return BytePattern(bytes);
  }

  /// Returns true if the pattern occurs in [haystack] within [start]..[end).
  @pragma('vm:prefer-inline')
  bool hasMatch({required Uint8List haystack, int start = 0, int? end}) =>
      indexOf(haystack: haystack, start: start, end: end) != -1;

  /// Returns the index of the first match or -1 if not found.
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
