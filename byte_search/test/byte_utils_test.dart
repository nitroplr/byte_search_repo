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
}
