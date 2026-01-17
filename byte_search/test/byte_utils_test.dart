import 'dart:math';
import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';
import 'package:test/test.dart';

void main() {
  group('byte_utils', () {
    test('indexOfByte finds values (start/end)', () {
      final b = Uint8List.fromList([1, 2, 3, 2]);

      expect(indexOfByte(bytes: b, value: 2), 1);
      expect(indexOfByte(bytes: b, value: 2, start: 2), 3);
      expect(indexOfByte(bytes: b, value: 2, start: 2, end: 3), -1); // end excludes index 3
      expect(indexOfByte(bytes: b, value: 9), -1);
    });

    test('indexOfAnyByte respects start/end', () {
      final b = Uint8List.fromList([10, 11, 12, 13, 12]);
      final set = ByteSet([12]);

      expect(indexOfAnyByte(bytes: b, set: set), 2);
      expect(indexOfAnyByte(bytes: b, set: set, start: 3), 4);
      expect(indexOfAnyByte(bytes: b, set: set, start: 3, end: 4), -1);
    });

    test('startsWithBytes/endsWithBytes basic', () {
      final b = Uint8List.fromList([1, 2, 3, 4, 5]);

      expect(startsWithBytes(bytes: b, prefix: Uint8List.fromList([1, 2])), isTrue);
      expect(startsWithBytes(bytes: b, prefix: Uint8List.fromList([2, 3])), isFalse);

      expect(endsWithBytes(bytes: b, suffix: Uint8List.fromList([4, 5])), isTrue);
      expect(endsWithBytes(bytes: b, suffix: Uint8List.fromList([3, 5])), isFalse);
    });

    test('startsWithBytes/endsWithBytes slice support', () {
      final b = Uint8List.fromList([1, 2, 3, 4, 5]);

      expect(startsWithBytes(bytes: b, prefix: Uint8List.fromList([3, 4]), start: 2), isTrue);

      // end=3 => slice is [1,2,3]
      expect(endsWithBytes(bytes: b, suffix: Uint8List.fromList([2, 3]), end: 3), isTrue);
      expect(endsWithBytes(bytes: b, suffix: Uint8List.fromList([3]), end: 3), isTrue);
    });

    test('empty prefix/suffix always matches', () {
      final b = Uint8List.fromList([1, 2, 3]);

      expect(startsWithBytes(bytes: b, prefix: Uint8List(0)), isTrue);
      expect(endsWithBytes(bytes: b, suffix: Uint8List(0)), isTrue);
      expect(startsWithBytes(bytes: b, prefix: Uint8List(0), start: 2), isTrue);
      expect(endsWithBytes(bytes: b, suffix: Uint8List(0), end: 1), isTrue);
    });

    test('prefix/suffix longer than slice returns false', () {
      final b = Uint8List.fromList([1, 2, 3]);

      expect(startsWithBytes(bytes: b, prefix: Uint8List.fromList([1, 2, 3, 4])), isFalse);
      expect(endsWithBytes(bytes: b, suffix: Uint8List.fromList([0, 1, 2, 3])), isFalse);

      // Slice too short
      expect(startsWithBytes(bytes: b, prefix: Uint8List.fromList([2, 3]), start: 2), isFalse);
      expect(endsWithBytes(bytes: b, suffix: Uint8List.fromList([1, 2]), end: 1), isFalse);
    });
  });
  group('subBytes', () {
    test('returns correct view for basic range', () {
      final bytes = Uint8List.fromList('hello world'.codeUnits);

      final sub = subBytes(bytes: bytes, start: 6, end: 11);

      expect(String.fromCharCodes(sub), 'world');
      expect(sub.length, 5);
      expect(sub, Uint8List.fromList('world'.codeUnits));
    });

    test('end defaults to bytes.length', () {
      final bytes = Uint8List.fromList('abcdef'.codeUnits);

      final sub = subBytes(bytes: bytes, start: 2);

      expect(String.fromCharCodes(sub), 'cdef');
      expect(sub, Uint8List.fromList('cdef'.codeUnits));
    });

    test('start==end returns empty list', () {
      final bytes = Uint8List.fromList([1, 2, 3]);

      final sub = subBytes(bytes: bytes, start: 1, end: 1);

      expect(sub, isEmpty);
      expect(sub.length, 0);
    });

    test('returned list is a view (mutations reflect back)', () {
      final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);

      final sub = subBytes(bytes: bytes, start: 1, end: 4); // [20,30,40]
      sub[1] = 99; // modifies original at index 2

      expect(bytes, Uint8List.fromList([10, 20, 99, 40, 50]));
    });

    test('returned list is a view (mutating original reflects in view)', () {
      final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);

      final sub = subBytes(bytes: bytes, start: 1, end: 4); // [20,30,40]
      bytes[3] = 77; // modifies sub[2]

      expect(sub, Uint8List.fromList([20, 30, 77]));
    });

    test('throws RangeError when start is negative', () {
      final bytes = Uint8List.fromList([1, 2, 3]);

      expect(
            () => subBytes(bytes: bytes, start: -1, end: 2),
        throwsRangeError,
      );
    });

    test('throws RangeError when end is greater than length', () {
      final bytes = Uint8List.fromList([1, 2, 3]);

      expect(
            () => subBytes(bytes: bytes, start: 0, end: 4),
        throwsRangeError,
      );
    });

    test('throws RangeError when start > end', () {
      final bytes = Uint8List.fromList([1, 2, 3]);

      expect(
            () => subBytes(bytes: bytes, start: 2, end: 1),
        throwsRangeError,
      );
    });

    test('allows full-range view', () {
      final bytes = Uint8List.fromList([1, 2, 3]);

      final sub = subBytes(bytes: bytes, start: 0, end: bytes.length);

      // Should be equal content.
      expect(sub, bytes);

      // And still be a view: mutate and confirm original changes.
      sub[0] = 9;
      expect(bytes[0], 9);
    });
    test('subBytes randomized: equals bytes.sublist(start, end) content (seeded)', () {
      // Deterministic seed so CI is stable.
      final rng = Random(0x51B5B);

      for (int t = 0; t < 500; t++) {
        final len = rng.nextInt(256); // 0..255
        final bytes = Uint8List(len);
        for (int i = 0; i < len; i++) {
          bytes[i] = rng.nextInt(256);
        }

        // Choose a random valid range [start, end] where 0 <= start <= end <= len.
        final int a = rng.nextInt(len + 1);
        final int b = rng.nextInt(len + 1);
        final start = a < b ? a : b;
        final end = a < b ? b : a;

        final expected = bytes.sublist(start, end); // copies
        final actual = subBytes(bytes: bytes, start: start, end: end); // view

        // Compare contents (not identity/backing).
        expect(actual, expected, reason: 'trial=$t len=$len start=$start end=$end');

        // Optional: sanity check end-default path matches too.
        if (end == len) {
          final actualDefaultEnd = subBytes(bytes: bytes, start: start);
          expect(actualDefaultEnd, expected, reason: 'trial=$t defaultEnd');
        }

        // Also validate view semantics on a non-empty slice.
        if (start < end) {
          final view = subBytes(bytes: bytes, start: start, end: end);
          final old = bytes[start];
          view[0] = (old + 1) & 0xFF;
          expect(bytes[start], (old + 1) & 0xFF, reason: 'trial=$t view semantics');
        }
      }
    });
  });
}
