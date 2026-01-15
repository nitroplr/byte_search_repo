import 'dart:io';
import 'dart:typed_data';

import 'package:byte_search_io/src/record_reader.dart';

/// A chunk of bytes read from a file, with absolute positioning information.
///
/// A [ByteChunk] represents a contiguous region of file data that was read in
/// one iteration of a chunking stream.
///
/// ## Offsets
/// - [fileOffset] is the absolute byte offset in the file where [bytes] begins.
/// - The chunk covers the range `[fileOffset, fileOffset + bytes.length)`.
///
/// ## Overlap
/// When overlap is enabled, chunks after the first may include a prefix
/// that repeats up to the configured overlap count from the previous chunk’s tail.
/// In that case, [fileOffset] points to the start of the overlapped prefix.
///
/// ## End-of-stream
/// [isLast] indicates whether this is the final chunk for the requested range.
class ByteChunk {
  /// The bytes for this chunk (may include an overlap prefix depending on usage).
  final Uint8List bytes;

  /// Absolute file offset where [bytes] begins.
  final int fileOffset;

  /// Whether this is the final chunk in the stream for the requested range.
  final bool isLast;

  /// Creates a [ByteChunk] with its bytes, absolute [fileOffset], and [isLast] marker.
  const ByteChunk({required this.bytes, required this.fileOffset, required this.isLast});

  @override
  String toString() => 'ByteChunk(offset=$fileOffset, len=${bytes.length}, last=$isLast)';
}

/// Reads a file as a stream of byte chunks using a [RandomAccessFile].
///
/// This reader is a low-allocation building block for:
/// - large file scanning (pattern search, delimiter search)
/// - record-aware parsing (via [openRandomAccessFileRecords])
/// - file-range processing (via [openRandomAccessFileRange])
///
/// ## Example
/// ```dart
/// final reader = ChunkedFileReader();
/// await for (final chunk in reader.openPath(path: 'log.txt', chunkSize: 1 << 20)) {
///   // process chunk.bytes (absolute position = chunk.fileOffset)
/// }
/// ```
///
/// ## Chunk model
/// - `chunkSize` is the number of *new bytes* read from disk per iteration.
/// - `overlap` optionally prepends up to `overlap` bytes from the end of the
///   previous chunk to the front of the next chunk.
///
/// When overlap is enabled, consumers should account for repeated bytes in the
/// overlapped prefix (e.g., avoid double-processing by tracking an effective
/// “fresh” range).
///
/// ## File position side-effects
/// Methods on this class reposition the provided [RandomAccessFile] via
/// `setPosition` during reading.
///
/// ## Resource ownership
/// If [closeRafOnDone] is `true`, methods that accept a [RandomAccessFile]
/// will close it when the stream completes.
///
/// Note: [openRandomAccessFileRange] uses its own `closeOnDone` parameter.
class ChunkedFileReader {
  /// Whether to close the underlying [RandomAccessFile] when a stream completes.
  ///
  /// This applies to methods that accept an existing [RandomAccessFile].
  /// For path-based methods, the file is also closed by the time the stream
  /// completes (either by the delegated method when [closeRafOnDone] is `true`,
  /// or by the path method itself when it is `false`).
  final bool closeRafOnDone;

  /// Creates a [ChunkedFileReader].
  ///
  /// ## Parameters
  /// - [closeRafOnDone]: Whether to close an owned/provided [RandomAccessFile]
  ///   when streaming completes. Defaults to `true`.
  const ChunkedFileReader({this.closeRafOnDone = true});

  /// Opens [path] and streams the file as [ByteChunk]s.
  ///
  /// The file is opened in read mode and streamed from the beginning.
  ///
  /// ## Parameters
  /// - [path]: Path to the file to read.
  /// - [chunkSize]: Number of new bytes read per iteration. Must be > 0.
  /// - [overlap]: Number of bytes to repeat from the previous chunk’s tail.
  ///   Must be >= 0. Defaults to 0.
  ///
  /// ## Throws
  /// - [ArgumentError] if [chunkSize] <= 0 or [overlap] < 0.
  ///
  /// ## Resource ownership
  /// This method opens the file. If [closeRafOnDone] is `true`, the delegated
  /// stream ([openRandomAccessFile]) will close it. Otherwise, this method closes
  /// it after the stream completes.
  Stream<ByteChunk> openPath({required String path, required int chunkSize, int overlap = 0}) async* {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
    }
    if (overlap < 0) {
      throw ArgumentError.value(overlap, 'overlap', 'must be >= 0');
    }
    final raf = await File(path).open(mode: FileMode.read);
    yield* openRandomAccessFile(raf: raf, chunkSize: chunkSize, overlap: overlap);

    // We opened raf here, so we must ensure it gets closed.
    // If closeRafOnDone is true, openRandomAccessFile() will close it in its finally.
    // Otherwise, we close it here.
    if (!closeRafOnDone) {
      await raf.close();
    }
  }

  /// Streams an already-open [RandomAccessFile] as [ByteChunk]s.
  ///
  /// The file position is set to 0 before reading.
  ///
  /// ## Parameters
  /// - [raf]: Open file handle. The reader will call `setPosition`.
  /// - [chunkSize]: Number of new bytes read per iteration. Must be > 0.
  /// - [overlap]: Number of bytes to repeat from the previous chunk’s tail.
  ///   Must be >= 0. Defaults to 0.
  ///
  /// ## Throws
  /// - [ArgumentError] if [chunkSize] <= 0 or [overlap] < 0.
  ///
  /// ## Resource ownership
  /// If [closeRafOnDone] is `true`, [raf] is closed when the stream completes.
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

  /// Streams a file subrange as [ByteChunk]s for `[startOffset, endOffsetExclusive)`.
  ///
  /// This is similar to [openRandomAccessFile] but limits I/O to a smaller region.
  /// This is commonly used for “search within a time window” after a binary search
  /// has identified approximate boundaries.
  ///
  /// ## Overlap
  /// Range streaming currently requires [overlap] to be `0` to avoid ambiguous
  /// double-processing at boundaries.
  ///
  /// ## Parameters
  /// - [raf]: Open file handle. The reader will call `setPosition`.
  /// - [chunkSize]: Number of bytes read per iteration. Must be > 0.
  /// - [startOffset]: Start offset (inclusive). Must be >= 0.
  /// - [endOffsetExclusive]: End offset (exclusive). Must be >= [startOffset].
  /// - [closeOnDone]: Whether to close [raf] when finished. Defaults to `true`.
  ///
  /// Offsets beyond EOF are clamped to the file length. If the clamped range is
  /// empty, the stream yields nothing.
  ///
  /// ## Throws
  /// - [ArgumentError] if [chunkSize] <= 0, [startOffset] < 0, or
  ///   [endOffsetExclusive] < [startOffset].
  /// - [ArgumentError] if [overlap] is not `0` (not supported for range reads).
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

  /// Opens [path] and streams delimiter-separated records (for example, lines).
  ///
  /// This is record-aware and does **not** require overlap. It will not split
  /// records across yielded items; records that span chunk boundaries are handled
  /// via an internal carry buffer.
  ///
  /// ## Parameters
  /// - [path]: Path to the file to read.
  /// - [recordReader]: Configuration for delimiter, scan limits, and CRLF trimming.
  /// - [chunkSize]: Chunk size **in bytes** used for underlying range reads. Defaults to 4 MiB.
  /// - [startOffset]: Start offset for the stream. Defaults to 0.
  /// - [endOffsetExclusive]: Optional end offset (exclusive). Defaults to EOF.
  /// - [maxRecordBytes]: Maximum allowed record length before throwing. Defaults to 256 KiB.
  /// - [onChunkRecords]: Optional callback invoked per chunk with the first/last
  ///   record yielded from that chunk.
  ///
  /// ## Throws
  /// - [StateError] if a record exceeds [maxRecordBytes].
  ///
  /// ## Resource ownership
  /// This method opens the file. If [closeRafOnDone] is `true`, the delegated
  /// stream ([openRandomAccessFileRecords]) will close it. Otherwise, this method
  /// closes it after the stream completes.
  Stream<RecordSlice> openPathRecords({
    required String path,
    required RecordReader recordReader,
    int chunkSize = 1 << 22, // 4 MiB
    int startOffset = 0,
    int maxRecordBytes = 1 << 18, // 256 KiB
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
      // We opened raf here. openRandomAccessFileRecords() won't close it
      // when closeRafOnDone is false, so close it here.
      if (!closeRafOnDone) {
        await raf.close();
      }
    }
  }

  /// Streams delimiter-separated records (for example, lines) from an open [RandomAccessFile].
  ///
  /// This method:
  /// - reads the requested byte range in chunks (no overlap required)
  /// - allocates per yielded record (to return an owned byte buffer)
  /// - uses a carry buffer to join records that cross chunk boundaries
  /// - yields [RecordSlice] instances with absolute offsets
  ///
  /// If [RecordReader.trimCarriageReturn] is `true`, a trailing `\r` is removed
  /// before the delimiter (CRLF handling).
  ///
  /// ## Parameters
  /// - [raf]: Open file handle. The reader will call `setPosition`.
  /// - [recordReader]: Delimiter and CRLF configuration for record splitting.
  /// - [chunkSize]: Chunk size **in bytes** used for underlying range reads. Defaults to 4 MiB.
  /// - [startOffset]: Start offset for the stream. Defaults to 0.
  /// - [endOffsetExclusive]: Optional end offset (exclusive). Defaults to EOF.
  /// - [maxRecordBytes]: Maximum allowed record length before throwing.
  /// - [onChunkRecords]: Optional callback invoked per chunk with the first/last
  ///   record yielded from that chunk.
  ///
  /// ## Range semantics
  /// If streaming a strict subrange (non-EOF end), the final record may be
  /// returned with [RecordSlice.endTruncated] set to `true` if the record would
  /// continue past [endOffsetExclusive].
  ///
  /// ## Throws
  /// - [ArgumentError] if [chunkSize] <= 0, or if the start/end range is invalid.
  /// - [StateError] if a record exceeds [maxRecordBytes].
  ///
  /// ## Resource ownership
  /// If [closeRafOnDone] is `true` for this [ChunkedFileReader], [raf] is closed
  /// when the stream completes.
  Stream<RecordSlice> openRandomAccessFileRecords({
    required RandomAccessFile raf,
    required RecordReader recordReader,
    int chunkSize = 1 << 22, // 4 MiB
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

      await for (final ByteChunk chunk in openRandomAccessFileRange(
        raf: raf,
        chunkSize: chunkSize,
        overlap: 0,
        startOffset: start,
        endOffsetExclusive: endClamped,
        closeOnDone: false,
      )) {
        firstInChunk = null;
        // Combine carry + fresh bytes
        final Uint8List data;
        final int dataOffset;
        if (carry.isEmpty) {
          data = chunk.bytes;
          dataOffset = chunk.fileOffset;
        } else {
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

        // Remainder becomes the new carry.
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

      // End of range/file: emit trailing partial record if present.
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
