import 'dart:io';

import 'record_reader.dart';

/// Performs a binary search over a delimiter-separated **sorted** file.
///
/// This utility assumes the file is logically a sequence of delimiter-separated
/// records (for example, newline-separated lines), and that each record has a
/// key that is monotonic non-decreasing across the file (for records where [parseKey] returns a non-null key).
///
/// You provide:
/// - [parseKey] to extract a key from a [RecordSlice]
/// - [compare] to compare keys
///
/// The search returns **file offsets** (byte positions) that point to the
/// **start of a record**.
///
/// ## Example
/// ```dart
/// final raf = await File('sorted.log').open(mode: FileMode.read);
/// final bs = BinarySearchFile<DateTime>(
///   recordReader: RecordReader(delimiter: 0x0A /* '\n' */),
///   parseKey: (rec) {
///     // parse from rec.bytes (return null if the record has no parseable key)
///     return tryParseDateTime(rec.bytes);
///   },
///   compare: (a, b) => a.compareTo(b),
/// );
///
/// final start = await bs.lowerBound(raf: raf, target: someStartTime);
/// final end = await bs.upperBound(raf: raf, target: someEndTime);
/// // Now you can scan [start, end) using your range/chunk readers.
/// await raf.close();
/// ```
///
/// ## Unparseable records
/// If [parseKey] returns `null` at the probed record, the search will step
/// forward up to [maxSkipForwardUnparseable] records to find a parseable key.
/// If none is found within the next N records, the algorithm forces progress to the right to avoid
/// getting stuck.
///
/// ## File position side-effects
/// This class repositions the provided [RandomAccessFile] via `setPosition`
/// during searching.
///
/// ## Resource ownership
/// Methods on this class **do not** close [RandomAccessFile]. The caller owns
/// the file handle.
///
/// ## Throws
/// May rethrow I/O errors from [RandomAccessFile] operations or from
/// [RecordReader].
class BinarySearchFile<K> {
  /// Reads records (delimiter-separated) and provides record boundaries.
  final RecordReader recordReader;

  /// Parses a key from a record. Return `null` if the record is unparseable.
  final K? Function(RecordSlice record) parseKey;

  /// Comparator for keys: returns `< 0`, `0`, or `> 0` like `Comparable.compareTo`.
  final int Function(K a, K b) compare;

  /// Max forward steps to find a parseable key when we land on an unparseable record.
  final int maxSkipForwardUnparseable;

  /// Creates a [BinarySearchFile].
  ///
  /// ## Parameters
  /// - [recordReader]: Used to locate record boundaries around probed offsets.
  /// - [parseKey]: Extracts a key from a record (return `null` if unparseable).
  /// - [compare]: Compares keys.
  /// - [maxSkipForwardUnparseable]: When [parseKey] returns `null`, the search
  ///   will step forward up to this many records trying to find a parseable key.
  const BinarySearchFile({
    required this.recordReader,
    required this.parseKey,
    required this.compare,
    this.maxSkipForwardUnparseable = 64,
  });

  /// Returns the file offset of the **first record** whose key is `>= [target]`.
  ///
  /// If all keys are `< target`, returns EOF (the file length).
  ///
  /// The returned offset is normalized to a record start offset.
  Future<int> lowerBound({required RandomAccessFile raf, required K target}) async {
    return _bound(raf: raf, target: target, isUpper: false);
  }

  /// Returns the file offset of the **first record** whose key is `> [target]`.
  ///
  /// If no keys are `> target`, returns EOF (the file length).
  ///
  /// The returned offset is normalized to a record start offset.
  Future<int> upperBound({required RandomAccessFile raf, required K target}) async {
    return _bound(raf: raf, target: target, isUpper: true);
  }

  Future<int> _bound({required RandomAccessFile raf, required K target, required bool isUpper}) async {
    final int len = await raf.length();
    if (len == 0) return 0;

    int lo = 0;
    int hi = len;

    while (lo < hi) {
      final int mid = lo + ((hi - lo) >> 1);

      // Snap to a real record around mid.
      RecordSlice rec = await recordReader.readRecordContainingOffset(raf, mid, fileLength: len);

      // Try to parse a key; if null, step forward a bit.
      K? key = parseKey(rec);
      int skips = 0;
      while (key == null && skips < maxSkipForwardUnparseable) {
        skips++;

        final int nextOffset = _nextRecordOffset(rec: rec, fileLen: len);
        if (nextOffset >= len) break;

        rec = await recordReader.readRecordContainingOffset(raf, nextOffset, fileLength: len);
        key = parseKey(rec);
      }

      if (key == null) {
        // Can't parse anything nearby; force progress to the right.
        final int nextOffset = _nextRecordOffset(rec: rec, fileLen: len);
        if (nextOffset <= lo) {
          lo = (lo + 1) < hi ? (lo + 1) : hi;
        } else {
          lo = nextOffset < hi ? nextOffset : hi;
        }
        continue;
      }

      final int cmp = compare(key, target);

      // lowerBound: goLeft if key >= target
      // upperBound: goLeft if key > target
      final bool goLeft = isUpper ? (cmp > 0) : (cmp >= 0);

      if (goLeft) {
        final int recStart = rec.startOffset;

        // Tighten: answer is at or before recStart.
        int newHi = recStart < hi ? recStart : hi;

        // Progress fix: if recStart doesn't shrink hi and mid < hi, shrink to mid.
        // We'll normalize the final answer to a record start at the end.
        if (newHi == hi && mid < hi) {
          newHi = mid;
        }

        hi = newHi;
      } else {
        // Answer is after this record.
        final int nextOffset = _nextRecordOffset(rec: rec, fileLen: len);
        if (nextOffset > lo) {
          lo = nextOffset;
        } else {
          lo = (lo + 1) <= hi ? (lo + 1) : hi;
        }
      }
    }

    // Normalize: if we land inside a record (or on a delimiter), return the record start.
    return _normalizeToRecordStart(raf: raf, offset: lo, fileLen: len);
  }

  int _nextRecordOffset({required RecordSlice rec, required int fileLen}) {
    int next = rec.endOffsetExclusive;
    if (rec.foundTerminator) next += 1;
    if (next > fileLen) next = fileLen;
    return next;
  }

  Future<int> _normalizeToRecordStart({
    required RandomAccessFile raf,
    required int offset,
    required int fileLen,
  }) async {
    if (offset >= fileLen) return fileLen;
    final rec = await recordReader.readRecordContainingOffset(raf, offset, fileLength: fileLen);
    return rec.startOffset;
  }
}
