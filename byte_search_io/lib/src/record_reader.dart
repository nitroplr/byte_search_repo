import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Result of extracting a delimiter-separated record (e.g., a line) from a file.
class RecordSlice {
  /// Absolute file offset where the record begins.
  final int startOffset;

  /// Absolute file offset one past the last byte of the record
  /// (this does NOT include the delimiter).
  final int endOffsetExclusive;

  /// Record bytes (delimiter removed).
  final Uint8List bytes;

  /// True if we found the delimiter that ends the record.
  /// False means we hit EOF or a scan limit without seeing the delimiter.
  final bool foundTerminator;

  /// True if the record start could not be found within the backward scan limit.
  /// In that case, [startOffset] will be the earliest scanned offset (or 0).
  final bool startTruncated;

  /// True if the record end could not be found within the forward scan limit.
  /// In that case, [endOffsetExclusive] will be the scan limit (or EOF).
  final bool endTruncated;

  const RecordSlice({
    required this.startOffset,
    required this.endOffsetExclusive,
    required this.bytes,
    required this.foundTerminator,
    required this.startTruncated,
    required this.endTruncated,
  });

  int get length => endOffsetExclusive - startOffset;

  @override
  String toString() =>
      'RecordSlice(start=$startOffset, end=$endOffsetExclusive, len=$length, '
      'foundTerminator=$foundTerminator, startTruncated=$startTruncated, endTruncated=$endTruncated)';

  /// Decode this record as a String.
  /// Defaults to UTF-8 (appropriate for text logs).
  String toStringUtf8({bool allowMalformed = false}) {
    return utf8.decode(bytes, allowMalformed: allowMalformed);
  }
}

/// Reads delimiter-separated records (like lines) from a [RandomAccessFile]
/// by scanning around an arbitrary byte offset.
///
/// This is the backbone for "binary search timestamps in a file":
/// you jump to a mid offset, then use this to pull the *record containing* it.
class RecordReader {
  /// Delimiter byte (default is '\n').
  final int delimiter;

  /// Max bytes to scan backward to find the start delimiter.
  final int maxBackwardScanBytes;

  /// Max bytes to scan forward to find the ending delimiter.
  final int maxForwardScanBytes;

  /// Block size used when scanning.
  final int scanBlockSize;

  /// If true, trims a trailing '\r' (useful for CRLF).
  final bool trimCarriageReturn;

  const RecordReader({
    this.delimiter = 0x0A, // '\n'
    this.maxBackwardScanBytes = 256 * 1024,
    this.maxForwardScanBytes = 256 * 1024,
    this.scanBlockSize = 16 * 1024,
    this.trimCarriageReturn = true,
  });

  /// Reads the record containing [offset] (0 <= offset <= fileLen).
  ///
  /// If [offset] points at a delimiter, the returned record is the one *after*
  /// that delimiter (i.e., the next record).
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

    // If offset points at the delimiter, we *usually* interpret that as
    // "next record" (i.e., delimiter belongs to the previous record).
    //
    // However, for consecutive delimiters (empty records), advancing would
    // skip the empty record. Example: "\n\n".
    // If `offset` is on the *second* delimiter and the previous byte is also
    // a delimiter, do NOT advance so the empty record can be returned.
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

    // Fast-path: if we are positioned immediately after a delimiter, the record
    // must start at clampedOffset.
    _StartResult? fastStart;
    if (clampedOffset > 0) {
      await raf.setPosition(clampedOffset - 1);
      final int prev = await raf.readByte();
      if (prev == delimiter) {
        fastStart = _StartResult(start: clampedOffset, truncated: false);
      }
    }

    // If clampedOffset is exactly 0, start is 0. Otherwise scan backward from clampedOffset - 1.
    final int backwardAnchor = clampedOffset == 0 ? 0 : (clampedOffset - 1);

    final _StartResult startRes = fastStart ?? await _findRecordStart(raf: raf, from: backwardAnchor, fileLen: len);

    final _EndResult endRes = await _findRecordEnd(raf: raf, from: clampedOffset, fileLength: len);

    int start = startRes.start;
    int endExclusive = endRes.endExclusive;

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

  /// Returns the record immediately before the record containing [offset].
  ///
  /// This works whether [offset] is inside a record, equals a record's
  /// [RecordSlice.startOffset], or equals a record's [RecordSlice.endOffsetExclusive].
  ///
  /// Returns null if there is no previous record (or if the start is truncated and
  /// the true previous boundary is unknown).
  Future<RecordSlice?> readRecordBeforeOffset({
    required RandomAccessFile raf,
    required int offset,
    int? fileLength,
  }) async {
    return _readNeighborRecord(raf: raf, offset: offset, direction: -1, fileLength: fileLength);
  }

  /// Returns the record immediately after the record containing [offset].
  ///
  /// This works whether [offset] is inside a record, equals a record's
  /// [RecordSlice.startOffset], or equals a record's [RecordSlice.endOffsetExclusive].
  ///
  /// Returns null if there is no next record (or if the end is truncated and the
  /// true next boundary is unknown).
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
      // If we couldn't reliably find the true start (scan limit), we can't
      // guarantee what the previous record is.
      if (cur.startTruncated) return null;

      // Beginning of file: no previous record.
      if (cur.startOffset == 0) return null;

      // Special-case: empty first record when the file begins with a delimiter.
      // Example: "\nabc\n" -> first record is empty at [0,0], second starts at 1.
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

      // Use an offset that is guaranteed to be inside the previous record
      // (or on its delimiter, in the case of empty records).
      final int probe = cur.startOffset - 2;
      return readRecordContainingOffset(raf, probe, fileLength: len);
    } else {
      // If we couldn't reliably find the true end (scan limit), we can't
      // guarantee what the next record is.
      if (cur.endTruncated) return null;

      // If we didn't actually find a delimiter for this record, it runs to EOF,
      // so there is no next record.
      if (!cur.foundTerminator) return null;

      // Find the delimiter byte that terminates the current record.
      // Reuse the same forward-scan logic as readRecordContainingOffset,
      // which also correctly handles CRLF trimming.
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

      // Search backwards within [0, n).
      final int idx = _lastIndexOfByte(data: buf, byte: delimiter, start: n - 1);
      if (idx != -1) {
        // Record starts after delimiter.
        return _StartResult(start: readStart + idx + 1, truncated: false);
      }

      if (readStart == scanMin) {
        // We reached scan limit (or file start).
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
      // At EOF: end is EOF.
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
        // EOF
        return _EndResult(endExclusive: fileLength, foundDelimiter: false, truncated: false);
      }

      final int idx = _indexOfByte(data: buf, byte: delimiter, length: n);
      if (idx != -1) {
        // End is before delimiter.
        return _EndResult(endExclusive: pos + idx, foundDelimiter: true, truncated: false);
      }

      pos += n;
    }

    // Hit scanMax without finding delimiter.
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
