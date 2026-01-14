library;

import 'package:byte_search/byte_search.dart' show BytePattern, ByteSet;
/// High-performance byte searching utilities.
///
/// This package provides low-allocation primitives for searching and scanning
/// byte data without converting to `String`.
///
/// It is designed for performance-critical workloads such as log parsing,
/// binary protocol processing, and large file scanning.
///
/// The main building blocks are:
/// - [BytePattern]: A reusable compiled pattern for fast repeated searches.
/// - [ByteSet]: Constant-time membership checks for byte values (`0..255`).
/// - Byte utility functions for scanning, prefix/suffix checks, and set-based searches.
///
/// All APIs are allocation-free on the hot path and operate directly on
/// `Uint8List` data.
///
/// ## Example
/// ```dart
/// final pattern = BytePattern.fromAscii(needle: 'ERROR');
/// final index = pattern.indexOf(haystack: bytes);
/// if (index != -1) {
///   // match found
/// }
/// ```
export 'src/byte_pattern.dart';
export 'src/byte_set.dart';
export 'src/byte_utils.dart';