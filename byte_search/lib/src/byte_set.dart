import 'dart:typed_data';

/// A compiled set of byte values (`0..255`) with constant-time membership checks.
///
/// `ByteSet` is intended for high-throughput scanning where you frequently need
/// to ask “is this byte one of these?” without allocating or doing linear search.
///
/// Internally, this uses a 256-entry lookup table where membership is `O(1)`.
///
/// Instances of [ByteSet] are immutable and safe to reuse.
///
/// ## Example
/// ```dart
/// final vowels = ByteSet('aeiou'.codeUnits);
/// final b = 'k'.codeUnitAt(0);
/// if (vowels.contains(b)) { ... }
/// ```
///
/// ## Performance
/// - Construction: `O(n)` for `n` input values.
/// - Membership checks: `O(1)` time, no allocations.
class ByteSet {
  final Uint8List _table;

  ByteSet._(this._table);

  /// Creates a [ByteSet] from an iterable of values.
  ///
  /// Each element in [bytes] is treated as a byte by masking to the low 8 bits
  /// (`b & 0xFF`) and added to the set. Duplicate values are allowed and have no
  /// additional effect.
  ///
  /// ## Parameters
  /// - [bytes]: Values to include in the set; only the low 8 bits are used.
  ///
  /// ## Performance
  /// Runs in `O(n)` time and allocates one 256-byte table.
  factory ByteSet(Iterable<int> bytes) {
    final t = Uint8List(256);
    for (final b in bytes) {
      t[b & 0xFF] = 1;
    }
    return ByteSet._(t);
  }

  /// Creates a [ByteSet] containing exactly one byte value.
  ///
  /// The provided [byte] is masked to the low 8 bits (`byte & 0xFF`).
  ///
  /// ## Parameters
  /// - [byte]: The single value to include; only the low 8 bits are used.
  ///
  /// ## Performance
  /// Runs in `O(1)` time and allocates one 256-byte table.
  factory ByteSet.single(int byte) {
    final t = Uint8List(256);
    t[byte & 0xFF] = 1;
    return ByteSet._(t);
  }

  /// Creates a [ByteSet] from ASCII characters in [chars].
  ///
  /// Each UTF-16 code unit in [chars] is treated as a byte by keeping only the
  /// low 8 bits (`codeUnit & 0xFF`). This is fast, but non-ASCII characters are
  /// truncated.
  ///
  /// This is convenient for delimiter sets, e.g. whitespace:
  /// ```dart
  /// final ws = ByteSet.fromAsciiChars('\n\r\t ');
  /// ```
  ///
  /// ## Parameters
  /// - [chars]: Characters to include; each code unit is truncated to a byte.
  ///
  /// ## Performance
  /// Runs in `O(chars.length)` time and allocates one 256-byte table.
  factory ByteSet.fromAsciiChars(String chars) {
    final t = Uint8List(256);
    for (final c in chars.codeUnits) {
      t[c & 0xFF] = 1;
    }
    return ByteSet._(t);
  }

  /// Returns `true` if [byte] is a member of this set.
  ///
  /// Only the low 8 bits of [byte] are used (`byte & 0xFF`).
  ///
  /// ## Parameters
  /// - [byte]: Value to check; only the low 8 bits are used.
  ///
  /// ## Performance
  /// Runs in `O(1)` time and does not allocate.
  @pragma('vm:prefer-inline')
  bool contains(int byte) => _table[byte & 0xFF] != 0;

  /// Returns a new [ByteSet] that is the complement of this set.
  ///
  /// The returned set contains exactly the byte values in `0..255` that this set
  /// does **not** contain.
  ///
  /// ## Performance
  /// Runs in `O(256)` time and allocates one new 256-byte table.
  ByteSet inverted() {
    final t = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      t[i] = _table[i] == 0 ? 1 : 0;
    }
    return ByteSet._(t);
  }
}
