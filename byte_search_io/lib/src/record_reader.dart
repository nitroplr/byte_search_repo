import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A delimiter-separated record extracted from a file.
///
/// A record is defined as the bytes between two delimiter occurrences (or file
/// boundaries). The delimiter itself is **not** included in [bytes] or
/// [endOffsetExclusive].
///
/// This type is returned by [RecordReader] methods and is suitable for
/// higher-level parsing (e.g. decoding log lines, extracting timestamps, etc.).
class RecordSlice {
  /// Absolute file offset where the record begins (inclusive).
  final int startOffset;

  /// Absolute file offset one past the last byte of the record (exclusive).
  ///
  /// This does **not** include the delimiter byte that terminates the record.
  /// For example, for a newline-delimited file, this is the offset of `\n`.
  final int endOffsetExclusive;

  /// The record bytes with the delimiter removed.
  ///
  /// If [RecordReader.trimCarriageReturn] was enabled, the returned bytes may
  /// also have a trailing `\r` removed (CRLF handling).
  final Uint8List bytes;

  /// Whether a terminating delimiter was found for this record.
  ///
  /// If `true`, a delimiter was encountered within the forward scan limit.
  /// If `false`, the record ended due to reaching EOF or the scan limit.
  final bool foundTerminator;

  /// Whether the true start of the record could not be determined.
  ///
  /// If `true`, the backward scan hit [RecordReader.maxBackwardScanBytes]
  /// before finding a delimiter (or the file start). In this case, [startOffset]
  /// is the earliest scanned offset (or `0`).
  final bool startTruncated;

  /// Whether the true end of the record could not be determined.
  ///
  /// If `true`, the forward scan hit [RecordReader.maxForwardScanBytes]
  /// before finding a delimiter (or EOF). In this case, [endOffsetExclusive]
  /// is the scan limit (or EOF).
  final bool endTruncated;

  /// Creates a record slice with absolute offsets and extracted bytes.
  const RecordSlice({
    required this.startOffset,
    required this.endOffsetExclusive,
    required this.bytes,
    required this.foundTerminator,
    required this.startTruncated,
    required this.endTruncated,
  });

  /// The record length in bytes (`endOffsetExclusive - startOffset`).
  ///
  /// This matches [RecordSlice.bytes].length for slices produced by [RecordReader].
  int get length => endOffsetExclusive - startOffset;

  @override
  String toString() =>
      'RecordSlice(start=$startOffset, end=$endOffsetExclusive, len=$length, '
      'foundTerminator=$foundTerminator, startTruncated=$startTruncated, endTruncated=$endTruncated)';

  /// Decodes [bytes] into a [String] using UTF-8.
  ///
  /// This is convenient for text logs that are UTF-8 encoded.
  ///
  /// ## Parameters
  /// - [allowMalformed]: If `true`, replaces malformed sequences with U+FFFD
  ///   instead of throwing. Defaults to `false`.
  ///
  /// ## Returns
  /// The decoded string representation of the record bytes.
  String toStringUtf8({bool allowMalformed = false}) {
    return utf8.decode(bytes, allowMalformed: allowMalformed);
  }
}

/// Reads delimiter-separated records (such as lines) from a [RandomAccessFile]
/// by scanning around an arbitrary byte offset.
///
/// This is useful for workflows like "binary search within a large log file":
/// you jump to an approximate position, then use this reader to extract the
/// *record containing* that offset (or the next record if positioned on a
/// delimiter).
///
/// ## Example
/// ```dart
/// final raf = await File('log.txt').open();
/// final reader = RecordReader();
/// final rec = await reader.readRecordContainingOffset(raf, 1 << 20);
/// print(rec.toStringUtf8());
/// await raf.close();
/// ```
///
/// ## Record definition
/// - A record is the bytes between delimiters (or file boundaries).
/// - The delimiter byte itself is not included in the record.
/// - If [trimCarriageReturn] is enabled, a trailing `\r` is removed from the
///   extracted record bytes (useful for CRLF).
///
/// ## Scan limits
/// To avoid unbounded work on very large records, this reader only scans up to:
/// - [maxBackwardScanBytes] bytes backward to locate the record start
/// - [maxForwardScanBytes] bytes forward to locate the record end
///
/// If a limit is hit, [RecordSlice.startTruncated] or [RecordSlice.endTruncated]
/// will be `true` and neighbor navigation may return `null`.
class RecordReader {
  /// Delimiter byte used to separate records.
  ///
  /// Defaults to `\n` (0x0A), which is appropriate for newline-delimited text.
  final int delimiter;

  /// Maximum number of bytes to scan backward to find the delimiter that starts
  /// the record.
  ///
  /// If this limit is hit before a delimiter (or file start) is found, the
  /// returned [RecordSlice.startTruncated] is `true`.
  final int maxBackwardScanBytes;

  /// Maximum number of bytes to scan forward to find the delimiter that ends
  /// the record.
  ///
  /// If this limit is hit before a delimiter (or EOF) is found, the returned
  /// [RecordSlice.endTruncated] is `true`.
  final int maxForwardScanBytes;

  /// Block size used when scanning forward/backward.
  ///
  /// Larger values reduce syscall overhead but can increase temporary memory use.
  final int scanBlockSize;

  /// Whether to trim a trailing `\r` from extracted record bytes.
  ///
  /// This is useful when reading CRLF text files where records end with `\r\n`.
  final bool trimCarriageReturn;

  /// Creates a [RecordReader] configured for delimiter-separated records.
  ///
  /// ## Parameters
  /// - [delimiter]: Delimiter byte separating records. Defaults to `\n` (0x0A).
  /// - [maxBackwardScanBytes]: Max backward scan. Defaults to 256 KiB.
  /// - [maxForwardScanBytes]: Max forward scan. Defaults to 256 KiB.
  /// - [scanBlockSize]: Scan block size. Defaults to 16 KiB.
  /// - [trimCarriageReturn]: Whether to remove trailing `\r`. Defaults to `true`.
  const RecordReader({
    this.delimiter = 0x0A, // '\n'
    this.maxBackwardScanBytes = 256 * 1024,
    this.maxForwardScanBytes = 256 * 1024,
    this.scanBlockSize = 16 * 1024,
    this.trimCarriageReturn = true,
  });

  /// Reads the record that contains [offset].
  ///
  /// Searches for the record boundaries by scanning:
  /// - backward (up to [maxBackwardScanBytes]) to find the start delimiter
  /// - forward (up to [maxForwardScanBytes]) to find the end delimiter
  ///
  /// If [offset] points at a delimiter byte, the returned record is the one
  /// **after** that delimiter (i.e. the next record). An exception is made for
  /// consecutive delimiters (empty records), where the empty record should not
  /// be skipped.
  ///
  /// ## Parameters
  /// - [raf]: The file handle to read from. The reader will call `setPosition`.
  /// Note: Methods on this reader reposition the underlying [RandomAccessFile].
  /// - [offset]: Absolute byte offset in the file. Values greater than the file
  ///   length are clamped to EOF.
  /// - [fileLength]: Optional known file length to avoid calling `raf.length()`.
  ///
  /// ## Returns
  /// A [RecordSlice] representing the extracted record. If the file is empty,
  /// returns an empty record with `foundTerminator == false`.
  ///
  /// ## Throws
  /// - [ArgumentError] if [offset] is negative.
  Future<RecordSlice> readRecordContainingOffset(RandomAccessFile raf, int offset, {int? fileLength}) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must be >= 0');
    }

    final int len = fileLength ?? await raf.length();
    if (len == 0) {
      return RecordSlice(
        startOffset: 0,
        endOffsetExclusive: 0,
        bytes: Uint8List(0),
        foundTerminator: false,
        startTruncated: false,
        endTruncated: false,
      );
    }

    int clampedOffset = offset > len ? len : offset;

    // If offset points at the delimiter, interpret as "next record", except
    // for consecutive delimiters (empty records), where advancing would skip.
    if (clampedOffset < len) {
      await raf.setPosition(clampedOffset);
      final int b = await raf.readByte();
      if (b == delimiter) {
        bool shouldAdvance = true;

        if (clampedOffset > 0) {
          await raf.setPosition(clampedOffset - 1);
          final int prev = await raf.readByte();
          if (prev == delimiter) {
            shouldAdvance = false;
          }
        }

        // For the file-start delimiter, treat as "next record".
        if (clampedOffset == 0) {
          shouldAdvance = true;
        }

        if (shouldAdvance) {
          clampedOffset++;
          if (clampedOffset > len) clampedOffset = len;
        }
      }
    }

    // Fast-path: if positioned immediately after a delimiter, record starts here.
    _StartResult? fastStart;
    if (clampedOffset > 0) {
      await raf.setPosition(clampedOffset - 1);
      final int prev = await raf.readByte();
      if (prev == delimiter) {
        fastStart = _StartResult(start: clampedOffset, truncated: false);
      }
    }

    // If clampedOffset is 0, start is 0. Otherwise scan backward from clampedOffset - 1.
    final int backwardAnchor = clampedOffset == 0 ? 0 : (clampedOffset - 1);

    final _StartResult startRes = fastStart ?? await _findRecordStart(raf: raf, from: backwardAnchor, fileLen: len);

    final _EndResult endRes = await _findRecordEnd(raf: raf, from: clampedOffset, fileLength: len);

    int start = startRes.start;
    final int endExclusive = endRes.endExclusive;

    if (endExclusive < start) {
      start = endExclusive;
    }

    final Uint8List recordBytes = await _readRange(raf: raf, start: start, endExclusive: endExclusive);

    Uint8List finalBytes = recordBytes;
    int finalEndExclusive = endExclusive;

    if (trimCarriageReturn && finalBytes.isNotEmpty && finalBytes.last == 0x0D) {
      finalBytes = Uint8List.sublistView(finalBytes, 0, finalBytes.length - 1);
      finalEndExclusive = endExclusive - 1;
    }

    return RecordSlice(
      startOffset: start,
      endOffsetExclusive: finalEndExclusive,
      bytes: finalBytes,
      foundTerminator: endRes.foundDelimiter,
      startTruncated: startRes.truncated,
      endTruncated: endRes.truncated,
    );
  }

  /// Reads the record immediately before the record containing [offset].
  ///
  /// This works whether [offset] is:
  /// - inside a record
  /// - equal to a record's [RecordSlice.startOffset]
  /// - equal to a record's [RecordSlice.endOffsetExclusive]
  ///
  /// Returns `null` if there is no previous record, or if the current record’s
  /// start is truncated (meaning the true previous boundary is unknown).
  ///
  /// ## Parameters
  /// - [raf]: The file handle to read from.
  /// - [offset]: Absolute byte offset within the file.
  /// - [fileLength]: Optional known file length to avoid calling `raf.length()`.
  Future<RecordSlice?> readRecordBeforeOffset({
    required RandomAccessFile raf,
    required int offset,
    int? fileLength,
  }) async {
    return _readNeighborRecord(raf: raf, offset: offset, direction: -1, fileLength: fileLength);
  }

  /// Reads the record immediately after the record containing [offset].
  ///
  /// This works whether [offset] is:
  /// - inside a record
  /// - equal to a record's [RecordSlice.startOffset]
  /// - equal to a record's [RecordSlice.endOffsetExclusive]
  ///
  /// Returns `null` if there is no next record, if the current record’s end is
  /// truncated (meaning the true next boundary is unknown), or if the current
  /// record runs to EOF (no terminating delimiter).
  ///
  /// ## Parameters
  /// - [raf]: The file handle to read from.
  /// - [offset]: Absolute byte offset within the file.
  /// - [fileLength]: Optional known file length to avoid calling `raf.length()`.
  Future<RecordSlice?> readRecordAfterOffset({
    required RandomAccessFile raf,
    required int offset,
    int? fileLength,
  }) async {
    return _readNeighborRecord(raf: raf, offset: offset, direction: 1, fileLength: fileLength);
  }

  // -------------------------
  // Internal helpers
  // -------------------------

  Future<RecordSlice?> _readNeighborRecord({
    required RandomAccessFile raf,
    required int offset,
    required int direction,
    int? fileLength,
  }) async {
    if (direction != -1 && direction != 1) {
      throw ArgumentError.value(direction, 'direction', 'must be -1 (before) or 1 (after)');
    }

    final int len = fileLength ?? await raf.length();
    if (len == 0) return null;

    final RecordSlice cur = await readRecordContainingOffset(raf, offset, fileLength: len);

    if (direction == -1) {
      if (cur.startTruncated) return null;
      if (cur.startOffset == 0) return null;

      // Special-case: empty first record when the file begins with a delimiter.
      if (cur.startOffset == 1) {
        await raf.setPosition(0);
        final int b0 = await raf.readByte();
        if (b0 == delimiter) {
          return RecordSlice(
            startOffset: 0,
            endOffsetExclusive: 0,
            bytes: Uint8List(0),
            foundTerminator: true,
            startTruncated: false,
            endTruncated: false,
          );
        }
        return null;
      }

      final int probe = cur.startOffset - 2;
      return readRecordContainingOffset(raf, probe, fileLength: len);
    } else {
      if (cur.endTruncated) return null;
      if (!cur.foundTerminator) return null;

      final _EndResult endRes = await _findRecordEnd(raf: raf, from: cur.endOffsetExclusive, fileLength: len);
      if (!endRes.foundDelimiter) return null;

      final int delimiterPos = endRes.endExclusive; // position of delimiter byte
      return readRecordContainingOffset(raf, delimiterPos, fileLength: len);
    }
  }

  Future<Uint8List> _readRange({required RandomAccessFile raf, required int start, required int endExclusive}) async {
    if (endExclusive <= start) return Uint8List(0);

    final int length = endExclusive - start;
    final Uint8List out = Uint8List(length);

    await raf.setPosition(start);

    int written = 0;
    while (written < length) {
      final int n = await raf.readInto(out, written, length);
      if (n == 0) break;
      written += n;
    }

    if (written == length) return out;
    return Uint8List.sublistView(out, 0, written);
  }

  Future<_StartResult> _findRecordStart({
    required RandomAccessFile raf,
    required int from,
    required int fileLen,
  }) async {
    if (from <= 0) return const _StartResult(start: 0, truncated: false);

    final int scanMin = (from - maxBackwardScanBytes) > 0 ? (from - maxBackwardScanBytes) : 0;

    final Uint8List buf = Uint8List(scanBlockSize);

    int pos = from;
    while (true) {
      final int blockStart = (pos - scanBlockSize + 1);
      final int readStart = blockStart > scanMin ? blockStart : scanMin;
      final int readLen = (pos - readStart + 1);

      await raf.setPosition(readStart);
      final int n = await raf.readInto(buf, 0, readLen);
      if (n <= 0) break;

      final int idx = _lastIndexOfByte(data: buf, byte: delimiter, start: n - 1);
      if (idx != -1) {
        return _StartResult(start: readStart + idx + 1, truncated: false);
      }

      if (readStart == scanMin) {
        final bool truncated = scanMin != 0;
        return _StartResult(start: scanMin == 0 ? 0 : scanMin, truncated: truncated);
      }

      pos = readStart - 1;
      if (pos <= 0) return const _StartResult(start: 0, truncated: false);
    }

    return const _StartResult(start: 0, truncated: false);
  }

  Future<_EndResult> _findRecordEnd({required RandomAccessFile raf, required int from, required int fileLength}) async {
    if (from >= fileLength) {
      return _EndResult(endExclusive: fileLength, foundDelimiter: false, truncated: false);
    }

    final int scanMax = (from + maxForwardScanBytes) < fileLength ? (from + maxForwardScanBytes) : fileLength;

    final Uint8List buf = Uint8List(scanBlockSize);

    int pos = from;

    while (pos < scanMax) {
      final int remaining = scanMax - pos;
      final int toRead = remaining < scanBlockSize ? remaining : scanBlockSize;

      await raf.setPosition(pos);
      final int n = await raf.readInto(buf, 0, toRead);
      if (n <= 0) {
        return _EndResult(endExclusive: fileLength, foundDelimiter: false, truncated: false);
      }

      final int idx = _indexOfByte(data: buf, byte: delimiter, length: n);
      if (idx != -1) {
        // End is before delimiter.
        return _EndResult(endExclusive: pos + idx, foundDelimiter: true, truncated: false);
      }

      pos += n;
    }


    final bool truncated = scanMax != fileLength;
    return _EndResult(endExclusive: scanMax, foundDelimiter: false, truncated: truncated);
  }

  static int _indexOfByte({required Uint8List data, required int byte, required int length}) {
    for (int i = 0; i < length; i++) {
      if (data[i] == byte) return i;
    }
    return -1;
  }

  static int _lastIndexOfByte({required Uint8List data, required int byte, required int start}) {
    for (int i = start; i >= 0; i--) {
      if (data[i] == byte) return i;
    }
    return -1;
  }
}

class _StartResult {
  final int start;
  final bool truncated;

  const _StartResult({required this.start, required this.truncated});
}

class _EndResult {
  final int endExclusive;
  final bool foundDelimiter;
  final bool truncated;

  const _EndResult({required this.endExclusive, required this.foundDelimiter, required this.truncated});
}
