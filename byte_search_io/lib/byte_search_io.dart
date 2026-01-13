/// File-backed adapters and utilities for the `byte_search` package.
///
/// Provides:
/// - Chunked RandomAccessFile reading
/// - Generic binary search over ordered records
/// - Delimiter-based record extraction
library;

export 'src/chunked_file_reader.dart';
export 'src/binary_search_file.dart';
export 'src/record_reader.dart';
export 'package:byte_search/byte_search.dart';