import 'dart:math';
import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';
import 'package:test/test.dart';

Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  group('BytePattern', () {
    test('finds match and returns correct index', () {
      final hay = _ascii('hello world');
      final pat = BytePattern.fromAscii(needle:'world');

      expect(pat.hasMatch(haystack:hay), isTrue);
      expect(pat.indexOf(haystack:hay), 6);
    });

    test('rejects non-match', () {
      final hay = _ascii('hello world');
      final pat = BytePattern.fromAscii(needle:'zzz');

      expect(pat.hasMatch(haystack:hay), isFalse);
      expect(pat.indexOf(haystack:hay), -1);
    });

    test('supports start/end slicing', () {
      final hay = _ascii('abc__abc');
      final pat = BytePattern.fromAscii(needle:'abc');

      expect(pat.indexOf(haystack:hay, start: 0, end: 3), 0); // only first "abc"
      expect(pat.indexOf(haystack:hay, start: 1), 5);         // skips first
      expect(pat.indexOf(haystack:hay, start: 1, end: 5), -1);// excludes second
    });

    test('length getter matches needle length', () {
      final pat1 = BytePattern.fromAscii(needle:'world');
      expect(pat1.length, 5);

      final pat2 = BytePattern(_ascii(''));
      expect(pat2.length, 0);
    });

    test('empty needle matches at start (returns start)', () {
      final hay = Uint8List.fromList([1, 2, 3]);
      final pat = BytePattern(Uint8List(0));

      expect(pat.indexOf(haystack:hay, start: 0), 0);
      expect(pat.indexOf(haystack:hay, start: 2), 2);
      expect(pat.hasMatch(haystack:hay, start: 2), isTrue);
    });

    test('returns -1 when remaining slice is shorter than needle', () {
      final hay = _ascii('abc');
      final pat = BytePattern.fromAscii(needle:'abcd');

      expect(pat.indexOf(haystack:hay), -1);
      expect(pat.hasMatch(haystack:hay), isFalse);
    });

    test('can find overlapping occurrences using repeated indexOf', () {
      final hay = _ascii('aaaaa');
      final pat = BytePattern.fromAscii(needle:'aa');

      final hits = <int>[];
      for (int i = 0;;) {
        final pos = pat.indexOf(haystack:hay, start: i);
        if (pos == -1) break;
        hits.add(pos);
        i = pos + 1; // allow overlaps
      }

      expect(hits, [0, 1, 2, 3]);
    });
  });

  int naiveIndexOf(Uint8List hay, Uint8List needle, {required int start, required int end}) {
    if (start < 0) start = 0;
    if (end > hay.length) end = hay.length;
    if (end < start) end = start;

    final int n = needle.length;
    if (n == 0) return start <= end ? start : -1;

    final int lastStart = end - n;
    if (lastStart < start) return -1;

    for (int i = start; i <= lastStart; i++) {
      bool ok = true;
      for (int j = 0; j < n; j++) {
        if (hay[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  Uint8List randBytes(Random rng, int len) {
    final b = Uint8List(len);
    for (int i = 0; i < len; i++) {
      b[i] = rng.nextInt(256);
    }
    return b;
  }

  test('randomized: indexOf matches naive implementation (seeded)', () {
    // Deterministic seed so CI is stable.
    final rng = Random(0xC0FFEE);

    for (int t = 0; t < 300; t++) {
      final hayLen = rng.nextInt(256); // 0..255
      final needleLen = rng.nextInt(32); // 0..31

      final hay = randBytes(rng, hayLen);
      final needle = randBytes(rng, needleLen);

      final pat = BytePattern(needle);

      // Pick a random start/end window within [0..hayLen]
      final int a = rng.nextInt(hayLen + 1);
      final int b = rng.nextInt(hayLen + 1);
      final start = a < b ? a : b;
      final end = a < b ? b : a;

      final expected = naiveIndexOf(hay, needle, start: start, end: end);
      final actual = pat.indexOf(haystack:hay, start: start, end: end);

      if (expected != actual) {
        fail(
          'Mismatch on trial $t: hayLen=$hayLen needleLen=$needleLen start=$start end=$end '
              'expected=$expected actual=$actual',
        );
      }

      // Also validate hasMatch aligns with indexOf.
      final has = pat.hasMatch(haystack:hay, start: start, end: end);
      expect(has, expected != -1);
    }
  });

  test('indexOf throws RangeError for invalid range (debug only)', () {
    final hay = _ascii('hello');
    final pat = BytePattern.fromAscii(needle: 'he');

    expect(() => pat.indexOf(haystack: hay, start: -1), throwsRangeError);
    expect(() => pat.indexOf(haystack: hay, end: 999), throwsRangeError);
    expect(() => pat.indexOf(haystack: hay, start: 4, end: 3), throwsRangeError);
  });

}
