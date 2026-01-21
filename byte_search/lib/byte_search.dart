library;

/// High-performance byte searching utilities.
///
/// This package provides low-allocation primitives for searching and scanning
/// byte data without converting to `String`.
///
/// It is designed for performance-critical workloads such as log parsing,
/// binary protocol processing, and large file scanning.
///
/// The main building blocks are:
/// - `BytePattern`: A reusable compiled pattern for fast repeated searches.
/// - `ByteSet`: Constant-time membership checks for byte values (`0..255`).
/// - `Uint8List` extensions for scanning, prefix/suffix checks, and set-based searches.
///
/// All APIs are allocation-free on the hot path and operate directly on
/// `Uint8List` data.
///
/// See also:
/// - `package:byte_search_io/byte_search_io.dart` for disk-backed file scanning,
///   record extraction, and binary search over large, sorted files.
///
/// ## Example
/// ```dart
/// final pattern = BytePattern.fromAscii(needle: 'ERROR');
/// final index = pattern.indexOf(haystack: bytes);
/// if (index != -1) {
///   // match found
/// }
/// ```
///
/// ## Extension example
/// ```dart
/// final ws = ByteSet.fromAsciiChars(' \t');
/// final i = bytes.indexOfByteNotIn(ws);
/// if (i != -1 && bytes.startsWithBytes(Uint8List.fromList('['.codeUnits), start: i)) {
///   // looks like a bracketed prefix
/// }
/// ```
export 'src/byte_pattern.dart';
export 'src/byte_set.dart';
export 'src/uint8list_extensions.dart';
