import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';
import 'package:test/test.dart';

void main() {
  test('indexOfByte finds values', () {
    final b = Uint8List.fromList([1, 2, 3, 2]);
    expect(indexOfByte(b, 2), 1);
    expect(indexOfByte(b, 2, start: 2), 3);
    expect(indexOfByte(b, 9), -1);
  });

  test('startsWithBytes/endsWithBytes', () {
    final b = Uint8List.fromList([1, 2, 3, 4, 5]);
    expect(startsWithBytes(b, Uint8List.fromList([1, 2])), isTrue);
    expect(startsWithBytes(b, Uint8List.fromList([2, 3])), isFalse);

    expect(endsWithBytes(b, Uint8List.fromList([4, 5])), isTrue);
    expect(endsWithBytes(b, Uint8List.fromList([3, 5])), isFalse);

    // slice
    expect(startsWithBytes(b, Uint8List.fromList([3, 4]), start: 2), isTrue);
    expect(endsWithBytes(b, Uint8List.fromList([2, 3]), end: 3), isTrue);
  });
}
