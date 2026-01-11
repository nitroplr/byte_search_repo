import 'dart:typed_data';

/// A compiled set of bytes (0..255) with O(1) membership checks.
///
/// Optimized for scanning many short byte arrays with many rejects.
class ByteSet {
  final Uint8List _table;

  ByteSet._(this._table);

  /// Build from an iterable of byte values (only low 8 bits are used).
  factory ByteSet(Iterable<int> bytes) {
    final t = Uint8List(256);
    for (final b in bytes) {
      t[b & 0xFF] = 1;
    }
    return ByteSet._(t);
  }

  /// Build from a single byte.
  factory ByteSet.single(int byte) {
    final t = Uint8List(256);
    t[byte & 0xFF] = 1;
    return ByteSet._(t);
  }

  /// Build from ASCII characters in [chars] (each code unit is treated as a byte).
  ///
  /// Example:
  /// `ByteSet.fromAsciiChars(']\\n\\r\\t ')`
  factory ByteSet.fromAsciiChars(String chars) {
    final t = Uint8List(256);
    for (final c in chars.codeUnits) {
      t[c & 0xFF] = 1;
    }
    return ByteSet._(t);
  }

  /// Returns true if [byte] is in the set.
  @pragma('vm:prefer-inline')
  bool contains(int byte) => _table[byte & 0xFF] != 0;

  /// Returns a new ByteSet that is the complement of this set.
  ByteSet inverted() {
    final t = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      t[i] = _table[i] == 0 ? 1 : 0;
    }
    return ByteSet._(t);
  }
}
