import 'dart:io';
import 'dart:typed_data';

import 'package:byte_search_io/src/record_reader.dart';

/// A chunk of bytes read from a file.
///
/// [fileOffset] is the absolute byte offset in the file where [bytes] begins.
///
/// When [overlap] is used, chunks after the first will include up to [overlap]
/// bytes from the end of the previous chunk as a prefix.
class ByteChunk {
  final Uint8List bytes;
  final int fileOffset;
  final bool isLast;

  const ByteChunk({required this.bytes, required this.fileOffset, required this.isLast});

  @override
  String toString() => 'ByteChunk(offset=$fileOffset, len=${bytes.length}, last=$isLast)';
}

/// Reads a file in chunks using a [RandomAccessFile].
///
/// - [chunkSize] is the number of *new bytes* read from disk per iteration.
/// - [overlap] prepends up to [overlap] bytes from the previous chunk's tail.
/// - [fileOffset] is the absolute file position of `bytes[0]`.
class ChunkedFileReader {
  /// If true, closes the underlying [RandomAccessFile] when the stream completes.
  final bool closeRafOnDone;

  const ChunkedFileReader({this.closeRafOnDone = true});

  /// Creates a chunk stream from a file path.
  Stream<ByteChunk> openPath({required String path, required int chunkSize, int overlap = 0}) async* {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
    }
    if (overlap < 0) {
      throw ArgumentError.value(overlap, 'overlap', 'must be >= 0');
    }
    final raf = await File(path).open(mode: FileMode.read);
    yield* openRandomAccessFile(raf: raf, chunkSize: chunkSize, overlap: overlap);

    ///close since we own the raf
    if (!closeRafOnDone) {
      await raf.close();
    }
  }

  /// Creates a chunk stream from an already-open [RandomAccessFile].
  ///
  /// The file position is set to 0 before reading.
  Stream<ByteChunk> openRandomAccessFile({
    required RandomAccessFile raf,
    required int chunkSize,
    int overlap = 0,
  }) async* {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
    }
    if (overlap < 0) {
      throw ArgumentError.value(overlap, 'overlap', 'must be >= 0');
    }

    await raf.setPosition(0);
    final int fileLen = await raf.length();

    // Bytes from the end of the previous "fresh" read (at most [overlap] long).
    Uint8List carry = Uint8List(0);

    // Absolute file offset where the next disk read begins.
    int diskOffset = 0;

    // Reusable read buffer (we copy out the read portion before yielding).
    final readBuf = Uint8List(chunkSize);

    try {
      while (diskOffset < fileLen) {
        final int readCount = await raf.readInto(readBuf, 0, chunkSize);
        if (readCount == 0) break;

        final int freshStart = diskOffset;
        diskOffset += readCount;

        // Correct "last chunk" detection even when fileLen is an exact multiple of chunkSize.
        final bool isLast = diskOffset >= fileLen;

        // Copy out the exact bytes read so we never yield a buffer that can be overwritten.
        final Uint8List fresh = Uint8List.fromList(readBuf.sublist(0, readCount));

        Uint8List out;
        int outOffset;

        if (overlap == 0 || carry.isEmpty) {
          out = fresh;
          outOffset = freshStart;
        } else {
          out = Uint8List(carry.length + fresh.length);
          out.setRange(0, carry.length, carry);
          out.setRange(carry.length, out.length, fresh);

          // Carry bytes came from immediately before freshStart.
          outOffset = freshStart - carry.length;
        }

        yield ByteChunk(bytes: out, fileOffset: outOffset, isLast: isLast);

        // Update carry for next iteration from the end of the *fresh* bytes.
        if (overlap > 0) {
          final int keep = overlap <= fresh.length ? overlap : fresh.length;
          carry = Uint8List.sublistView(fresh, fresh.length - keep, fresh.length);
        } else {
          carry = Uint8List(0);
        }
      }
    } finally {
      if (closeRafOnDone) {
        await raf.close();
      }
    }
  }

  /// Creates a chunk stream for a byte range [startOffset, endOffsetExclusive).
  ///
  /// This is similar to [openRandomAccessFile] but lets you limit IO to a smaller region.
  /// No overlap is added by default; callers that implement their own record/line carry
  /// generally do not need overlap.
  ///
  /// If [closeOnDone] is true (default), this method will close [raf] when finished.
  Stream<ByteChunk> openRandomAccessFileRange({
    required RandomAccessFile raf,
    required int chunkSize,
    int overlap = 0,
    required int startOffset,
    required int endOffsetExclusive,
    bool closeOnDone = true,
  }) async* {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
    }
    if (overlap != 0) {
      // Range reading with overlap can be added later if needed.
      // For now, require 0 to avoid double-processing without extra metadata.
      throw ArgumentError.value(overlap, 'overlap', 'must be 0 for range reads');
    }
    if (startOffset < 0) {
      throw ArgumentError.value(startOffset, 'startOffset', 'must be >= 0');
    }
    if (endOffsetExclusive < startOffset) {
      throw ArgumentError.value(endOffsetExclusive, 'endOffsetExclusive', 'must be >= startOffset');
    }

    try {
      final int fileLen = await raf.length();
      final int start = startOffset > fileLen ? fileLen : startOffset;
      final int end = endOffsetExclusive > fileLen ? fileLen : endOffsetExclusive;
      if (start == end) return;

      await raf.setPosition(start);

      final Uint8List readBuf = Uint8List(chunkSize);
      int diskOffset = start;

      while (diskOffset < end) {
        final int toRead = (end - diskOffset) < chunkSize ? (end - diskOffset) : chunkSize;
        final int readCount = await raf.readInto(readBuf, 0, toRead);
        if (readCount == 0) break;

        final int chunkOffset = diskOffset;
        diskOffset += readCount;

        final bool isLast = diskOffset >= end;

        // Copy out exact bytes read.
        final Uint8List out = Uint8List.fromList(readBuf.sublist(0, readCount));

        yield ByteChunk(bytes: out, fileOffset: chunkOffset, isLast: isLast);
      }
    } finally {
      if (closeOnDone) {
        await raf.close();
      }
    }
  }

  /// Streams delimiter-separated records (e.g., lines) from a file path.
  ///
  /// This is record-aware and does NOT require overlap. It will not split records
  /// across yielded items.
  Stream<RecordSlice> openPathRecords({
    required String path,
    required RecordReader recordReader,
    int chunkSize = 1 << 22, // 4 mb
    int startOffset = 0,
    int maxRecordBytes = 1 << 18, // 1/4 mb
    int? endOffsetExclusive,
    void Function(int chunkIndex, RecordSlice? first, RecordSlice? last)? onChunkRecords,
  }) async* {
    final raf = await File(path).open(mode: FileMode.read);
    try {
      yield* openRandomAccessFileRecords(
        raf: raf,
        chunkSize: chunkSize,
        recordReader: recordReader,
        startOffset: startOffset,
        endOffsetExclusive: endOffsetExclusive,
        maxRecordBytes: maxRecordBytes,
        onChunkRecords: onChunkRecords,
      );
    } finally {
      ///close since we own the raf
      if (!closeRafOnDone) {
        await raf.close();
      }
    }
  }

  /// Streams delimiter-separated records (e.g., lines) from an open [RandomAccessFile].
  ///
  /// - Uses a carry buffer to handle records that cross chunk boundaries.
  /// - Yields [RecordSlice] with absolute [startOffset]/[endOffsetExclusive].
  /// - If [recordReader.trimCarriageReturn] is true, trims trailing '\r' before '\n'.
  ///
  /// If [closeRafOnDone] is true for this [ChunkedFileReader], [raf] is closed when done.
  Stream<RecordSlice> openRandomAccessFileRecords({
    required RandomAccessFile raf,
    required RecordReader recordReader,
    int chunkSize = 1 << 22, // 4 mb
    int startOffset = 0,
    int maxRecordBytes = 1 << 18,
    int? endOffsetExclusive,
    void Function(int chunkIndex, RecordSlice? first, RecordSlice? last)? onChunkRecords,
  }) async* {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
    }

    final int fileLen = await raf.length();
    final int start = startOffset < 0 ? 0 : (startOffset > fileLen ? fileLen : startOffset);
    final int end = (endOffsetExclusive ?? fileLen);
    final int endClamped = end < 0 ? 0 : (end > fileLen ? fileLen : end);

    if (start > endClamped) {
      throw ArgumentError('startOffset ($start) must be <= endOffsetExclusive ($endClamped)');
    }

    // Determine whether the first record is truncated relative to the true record start.
    bool firstRecordStartTruncated = false;
    if (start > 0) {
      await raf.setPosition(start - 1);
      final int prev = await raf.readByte();
      firstRecordStartTruncated = prev != recordReader.delimiter;
    }

    // Carry is the partial record tail from the previous chunk.
    Uint8List carry = Uint8List(0);
    int carryOffset = start; // absolute file offset where carry[0] belongs

    // Helper to enforce a sane max record length.
    void checkCarrySize() {
      if (carry.length > maxRecordBytes) {
        throw StateError(
          'Record exceeds maxRecordBytes ($maxRecordBytes). '
          'Increase maxRecordBytes or adjust RecordReader limits.',
        );
      }
    }

    int chunkIndex = 0;
    try {
      RecordSlice? firstInChunk;
      RecordSlice? lastInChunk;
      // Reuse your existing chunk-range reader (no overlap needed).
      await for (final ByteChunk chunk in openRandomAccessFileRange(
        raf: raf,
        chunkSize: chunkSize,
        overlap: 0,
        startOffset: start,
        endOffsetExclusive: endClamped,
        closeOnDone: false, // we manage closing here using this.closeOnDone
      )) {
        firstInChunk = null;
        // Combine carry + fresh bytes
        final Uint8List data;
        final int dataOffset;
        if (carry.isEmpty) {
          data = chunk.bytes;
          dataOffset = chunk.fileOffset;
        } else {
          // carryOffset should always match chunk.fileOffset - carry.length in this design
          data = Uint8List(carry.length + chunk.bytes.length);
          data.setRange(0, carry.length, carry);
          data.setRange(carry.length, data.length, chunk.bytes);
          dataOffset = carryOffset;
        }

        // Split into records by delimiter.
        final int delim = recordReader.delimiter;
        int recordStartIndex = 0;

        for (int i = 0; i < data.length; i++) {
          if (data[i] != delim) continue;

          // Record bytes are [recordStartIndex, i) (delimiter excluded)
          int endIndexExclusive = i;

          // Trim CR if configured and present
          if (recordReader.trimCarriageReturn &&
              endIndexExclusive > recordStartIndex &&
              data[endIndexExclusive - 1] == 0x0D /* '\r' */ ) {
            endIndexExclusive -= 1;
          }

          final int absStart = dataOffset + recordStartIndex;
          final int absEnd = dataOffset + endIndexExclusive;

          final Uint8List recordBytes = (endIndexExclusive == recordStartIndex)
              ? Uint8List(0)
              : Uint8List.fromList(data.sublist(recordStartIndex, endIndexExclusive));

          final RecordSlice slice = RecordSlice(
            startOffset: absStart,
            endOffsetExclusive: absEnd,
            bytes: recordBytes,
            foundTerminator: true,
            startTruncated: firstRecordStartTruncated && (absStart == start),
            endTruncated: false,
          );
          firstInChunk ??= slice;
          lastInChunk = slice;
          yield slice;

          // Next record begins after the delimiter byte.
          recordStartIndex = i + 1;

          // After the first yielded record, we no longer special-case truncation.
          if (firstRecordStartTruncated) {
            // Only the very first record can be "startTruncated" due to range start.
            firstRecordStartTruncated = false;
          }
        }

        // Whatever remains after the last delimiter becomes the new carry.
        if (recordStartIndex >= data.length) {
          carry = Uint8List(0);
          carryOffset = dataOffset + data.length;
        } else {
          carry = Uint8List.fromList(data.sublist(recordStartIndex));
          carryOffset = dataOffset + recordStartIndex;
          checkCarrySize();
        }
        if (!chunk.isLast) {
          onChunkRecords?.call(chunkIndex, firstInChunk, lastInChunk);
        }
        chunkIndex++;
      }

      // End of range/file
      if (carry.isNotEmpty) {
        final int absStart = carryOffset;
        final int absEnd = carryOffset + carry.length;

        final bool isEof = (endClamped == fileLen);
        final bool endTruncated = !isEof; // range ended, record may continue

        final RecordSlice slice = RecordSlice(
          startOffset: absStart,
          endOffsetExclusive: absEnd,
          bytes: carry,
          foundTerminator: false,
          // no delimiter found in the remaining bytes
          startTruncated: firstRecordStartTruncated && (absStart == start),
          endTruncated: endTruncated,
        );
        lastInChunk = slice;
        yield slice;
      }
      onChunkRecords?.call(chunkIndex, firstInChunk, lastInChunk);
    } finally {
      if (closeRafOnDone) {
        await raf.close();
      }
    }
  }
}
