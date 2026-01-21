// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';

void main() {
  // Single-pattern example (your original).
  final givenTo = BytePattern.fromAscii(needle: ' was given to ');

  // Multi-pattern example (ordered phrases).
  final wonThe = BytePattern.fromAscii(needle: ' won the ');
  final rollOn = BytePattern.fromAscii(needle: ' roll on ');
  final withARoll = BytePattern.fromAscii(needle: ' with a roll of ');

  final orderedPhrases = <BytePattern>[wonThe, rollOn, withARoll];

  final bracket = ByteSet.single(']'.codeUnitAt(0));

  int messageStart(Uint8List line) {
    // App-specific: skip prefix up to ']'. We only scan a small prefix because
    // the timestamp bracket is expected early.
    final idx = line.indexOfAnyByte(bracket, end: line.length < 64 ? line.length : 64);
    if (idx == -1) return 0;

    int s = idx + 1;
    if (s < line.length && line[s] == ' '.codeUnitAt(0)) s++;
    return s;
  }

  bool interestingSingle(Uint8List line) {
    final start = messageStart(line);

    // Search only within the message body (zero-copy slice).
    final msg = line.subView(start);

    return givenTo.hasMatch(haystack: msg);
  }

  bool interestingOrdered(Uint8List line) {
    final start = messageStart(line);

    // Search only within the message body (zero-copy slice).
    final msg = line.subView(start);

    return msg.containsInOrder(orderedPhrases);
  }

  final lines = <String>[
    '[Mon Jan 05 17:00:27 2026] You say, \'hello\'',
    '[Mon Jan 05 17:01:10 2026] Some item was given to Ben.',
    '[Mon Jan 05 17:02:11 2026] Nothing to see here.',
    '[Mon Jan 05 17:03:44 2026] Ben won the Sword, roll on it with a roll of 94.',
    '[Mon Jan 05 17:04:01 2026] Ben won the Sword, with a roll of 94, roll on it.', // wrong order
    '[Mon Jan 05 17:05:12 2026] Ben won the Sword, roll on it with a roll of 94 and it was given to Ben.',
  ];

  for (final s in lines) {
    // In real usage, these bytes would typically come from a file or stream.
    // Here we convert strings to bytes to keep the example self-contained.
    final b = Uint8List.fromList(s.codeUnits);

    final single = interestingSingle(b);
    final ordered = interestingOrdered(b);

    // Show both checks side-by-side.
    final tag = single
        ? (ordered ? 'SINGLE+ORDERED' : 'SINGLE ONLY   ')
        : (ordered ? 'ORDERED ONLY  ' : '----          ');

    print('$tag  $s');
  }
}
