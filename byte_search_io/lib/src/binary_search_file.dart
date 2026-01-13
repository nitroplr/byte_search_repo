import 'dart:io';

import 'record_reader.dart';

/// A generic binary search helper over a delimiter-separated, *sorted* file.
///
/// Assumes keys are monotonic non-decreasing across records.
class BinarySearchFile<K> {
  final RecordReader recordReader;

  /// Parses a key from a record. Return null if unparseable.
  final K? Function(RecordSlice record) parseKey;

  /// Comparator for keys.
  final int Function(K a, K b) compare;

  /// Max forward steps to find a parseable key when we land on an unparsable record.
  final int maxSkipForwardUnparseable;

  const BinarySearchFile({
    required this.recordReader,
    required this.parseKey,
    required this.compare,
    this.maxSkipForwardUnparseable = 64,
  });

  /// Returns the file offset of the first record whose key is >= [target].
  /// If all keys are < target, returns EOF (file length).
  Future<int> lowerBound({required RandomAccessFile raf, required K target}) async {
    return _bound(raf: raf, target: target, isUpper: false);
  }

  /// Returns the file offset of the first record whose key is > [target].
  /// If no keys are > target, returns EOF (file length).
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

        // Normal tightening:
        // answer is at or before recStart
        int newHi = recStart < hi ? recStart : hi;

        // **Critical progress fix**:
        // If recStart == hi (no change) and mid < hi, move hi to mid.
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

    // Normalize: if we land on a delimiter or inside a record,
    // return the actual record start (RecordReader already handles delimiter->next record).
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
