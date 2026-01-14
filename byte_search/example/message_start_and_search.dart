// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';

void main() {
  final pattern = BytePattern.fromAscii(needle: ' was given to ');
  final bracket = ByteSet.single(']'.codeUnitAt(0));

  int messageStart(Uint8List line) {
    // App-specific: skip prefix up to ']'. We only scan a small prefix because
    // the timestamp bracket is expected early.
    final idx = indexOfAnyByte(
      bytes: line,
      set: bracket,
      end: line.length < 64 ? line.length : 64,
    );
    if (idx == -1) return 0;

    int s = idx + 1;
    if (s < line.length && line[s] == ' '.codeUnitAt(0)) s++;
    return s;
  }

  bool interesting(Uint8List line) {
    final start = messageStart(line);
    return pattern.hasMatch(haystack: line, start: start);
  }

  final lines = <String>[
    '[Mon Jan 05 17:00:27 2026] You say, \'hello\'',
    '[Mon Jan 05 17:01:10 2026] Some item was given to Ben.',
    '[Mon Jan 05 17:02:11 2026] Nothing to see here.',
  ];

  for (final s in lines) {
    // In real usage, these bytes would typically come from a file or stream.
    // Here we convert strings to bytes to keep the example self-contained.
    final b = Uint8List.fromList(s.codeUnits);
    print('${interesting(b) ? 'MATCH' : '---- '}  $s');
  }
}