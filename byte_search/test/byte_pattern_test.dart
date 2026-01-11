import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';
import 'package:test/test.dart';

void main() {
  test('BytePattern finds match', () {
    final hay = Uint8List.fromList('hello world'.codeUnits);
    final pat = BytePattern.fromAscii('world');
    expect(pat.hasMatch(hay), isTrue);
    expect(pat.indexOf(hay), 6);
  });

  test('BytePattern rejects non-match', () {
    final hay = Uint8List.fromList('hello world'.codeUnits);
    final pat = BytePattern.fromAscii('zzz');
    expect(pat.hasMatch(hay), isFalse);
    expect(pat.indexOf(hay), -1);
  });

  test('BytePattern supports start/end', () {
    final hay = Uint8List.fromList('abc__abc'.codeUnits);
    final pat = BytePattern.fromAscii('abc');
    expect(pat.indexOf(hay, start: 0, end: 3), 0);
    expect(pat.indexOf(hay, start: 1), 5);
    expect(pat.indexOf(hay, start: 1, end: 5), -1);
  });

  test('Empty needle matches at start', () {
    final hay = Uint8List.fromList([1, 2, 3]);
    final pat = BytePattern(Uint8List(0));
    expect(pat.indexOf(hay, start: 2), 2);
  });
}