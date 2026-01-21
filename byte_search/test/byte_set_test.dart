import 'package:byte_search/byte_search.dart';
import 'package:test/test.dart';

void main() {
  group('ByteSet', () {
    test('contains clamps to low 8 bits', () {
      final set = ByteSet([0, 1, 2, 255, 256, -1]);

      expect(set.contains(0), isTrue);
      expect(set.contains(1), isTrue);
      expect(set.contains(2), isTrue);
      expect(set.contains(255), isTrue);

      // 256 -> 0, -1 -> 255
      expect(set.contains(256), isTrue);
      expect(set.contains(-1), isTrue);

      expect(set.contains(3), isFalse);
    });

    test('single contains only that byte (with low-8-bit clamp)', () {
      final s = ByteSet.single(256); // => 0
      expect(s.contains(0), isTrue);
      expect(s.contains(1), isFalse);
      expect(s.contains(255), isFalse);
    });

    test('fromAsciiChars builds a set from characters', () {
      final s = ByteSet.fromAsciiChars(']\n\r\t ');

      expect(s.contains(']'.codeUnitAt(0)), isTrue);
      expect(s.contains('\n'.codeUnitAt(0)), isTrue);
      expect(s.contains('\r'.codeUnitAt(0)), isTrue);
      expect(s.contains('\t'.codeUnitAt(0)), isTrue);
      expect(s.contains(' '.codeUnitAt(0)), isTrue);

      expect(s.contains('A'.codeUnitAt(0)), isFalse);
    });

    test('inverted is complement and double-invert returns original', () {
      final set = ByteSet([1, 2, 3]);
      final inv = set.inverted();

      expect(inv.contains(1), isFalse);
      expect(inv.contains(2), isFalse);
      expect(inv.contains(3), isFalse);
      expect(inv.contains(0), isTrue);
      expect(inv.contains(255), isTrue);

      final roundTrip = inv.inverted();
      expect(roundTrip.contains(1), isTrue);
      expect(roundTrip.contains(2), isTrue);
      expect(roundTrip.contains(3), isTrue);
      expect(roundTrip.contains(0), isFalse);
    });
  });
}
