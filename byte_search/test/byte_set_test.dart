import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';
import 'package:test/test.dart';

void main() {
  test('ByteSet.contains works', () {
    final set = ByteSet([0, 1, 2, 255, 256, -1]);
    expect(set.contains(0), isTrue);
    expect(set.contains(1), isTrue);
    expect(set.contains(2), isTrue);
    expect(set.contains(255), isTrue);
    expect(set.contains(256), isTrue); // 256 -> 0
    expect(set.contains(-1), isTrue);  // -1 -> 255
    expect(set.contains(3), isFalse);
  });

  test('ByteSet.inverted works', () {
    final set = ByteSet([1, 2, 3]);
    final inv = set.inverted();
    expect(inv.contains(1), isFalse);
    expect(inv.contains(2), isFalse);
    expect(inv.contains(3), isFalse);
    expect(inv.contains(0), isTrue);
    expect(inv.contains(255), isTrue);
  });

  test('indexOfAnyByte uses ByteSet', () {
    final bytes = Uint8List.fromList([10, 11, 12, 13]);
    final set = ByteSet([12, 99]);
    expect(indexOfAnyByte(bytes, set), 2);
    expect(indexOfAnyByte(bytes, set, start: 3), -1);
  });
}