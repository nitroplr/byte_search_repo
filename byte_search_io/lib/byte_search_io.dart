library;
/// File-backed adapters and utilities for the `byte_search` ecosystem.
///
/// `byte_search_io` complements `package:byte_search` by adding **disk-backed**
/// helpers that work efficiently with very large files via `dart:io`
/// (`RandomAccessFile`).
///
/// This library requires `dart:io` and is not available on the web.
///
/// Most users will interact with this package in one of two ways:
///
/// - **Stream file bytes in chunks** for scanning / pattern matching.
/// - **Work with delimiter-separated records** (typically lines) and/or
///   **binary search** a sorted file by a parsed key (e.g., timestamps).
///
/// ## What this library provides
///
/// ### 1) Chunked file reading
/// Use `ChunkedFileReader` to stream a file (or a subrange of a file) as
/// `ByteChunk` objects. Each chunk includes:
/// - the bytes read
/// - the absolute file offset those bytes correspond to
/// - an `isLast` flag for end-of-stream handling
///
/// This is ideal for:
/// - scanning multi-GB logs without loading them into memory
/// - avoiding `readAsBytes()` style full-file allocations
///
/// ### 2) Record (delimiter) extraction
/// Use `RecordReader` when you need to treat the file as a sequence of
/// delimiter-separated records (e.g., newline-delimited text).
///
/// You can:
/// - read the record that contains an arbitrary byte offset
/// - read the previous/next record relative to an offset
///
/// Records are returned as `RecordSlice` containing:
/// - absolute start/end offsets
/// - bytes of the record (delimiter excluded)
/// - truncation flags when scan limits are hit
///
/// ### 3) Generic binary search over sorted record files
/// Use `BinarySearchFile` to perform `lowerBound` / `upperBound` style searches
/// over a delimiter-separated file that is **sorted by some monotonic key**.
/// For example, a log file whose records begin with timestamps.
///
/// `BinarySearchFile` returns **file offsets aligned to record starts**, which
/// you can then feed into `ChunkedFileReader.openRandomAccessFileRange` or
/// `ChunkedFileReader.openRandomAccessFileRecords` to scan only the relevant
/// portion of the file.
///
/// ## Relationship to `package:byte_search`
///
/// This package focuses on **I/O and file navigation**. It re-exports
/// `package:byte_search/byte_search.dart` so that consumers can import a single
/// library when doing file-backed scanning plus byte-pattern searching:
///
/// ```dart
/// import 'package:byte_search_io/byte_search_io.dart';
/// ```
///
/// That import gives you:
/// - file-backed readers (this package)
/// - byte-search patterns/utilities (the core `byte_search` package) `BytePattern`, `ByteSet`, and `Uint8List` extensions
///
/// ## Notes on side effects and resource ownership
///
/// Many APIs here accept a `RandomAccessFile` and will call `setPosition(...)`
/// during operation. Unless documented otherwise, **callers own the RAF** and
/// must decide when to close it.
///
/// In `ChunkedFileReader`, closure behavior is configurable via
/// `ChunkedFileReader(closeRafOnDone: ...)`.
export 'src/chunked_file_reader.dart';
export 'src/binary_search_file.dart';
export 'src/record_reader.dart';

// Convenience re-export: lets consumers use one import for both IO utilities
// and the core byte_search types (BytePattern, etc.).
export 'package:byte_search/byte_search.dart';
