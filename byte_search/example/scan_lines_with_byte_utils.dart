// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';

void main() {
  final whitespace = ByteSet.fromAsciiChars(' \t');
  final lbracket = Uint8List.fromList('['.codeUnits);
  final rbracket = Uint8List.fromList(']'.codeUnits);

  Uint8List ascii(String s) => Uint8List.fromList(s.codeUnits);

  // A tiny “parser” example:
  // - Skip leading spaces/tabs
  // - Check for a timestamp-style prefix like "[Mon ...]"
  // - Verify the line ends with '.' (just to demo endsWithBytes)
  bool looksLikeLogLine(Uint8List line) {
    final start = line.indexOfByteNotIn(whitespace);
    if (start == -1) return false;

    // Must start with '[' after trimming leading whitespace.
    if (!line.startsWithBytes(lbracket, start: start)) return false;

    // Must contain a ']' somewhere soon-ish (not a full parser, just an example).
    final close = line.indexOfByte(']'.codeUnitAt(0), start: start, end: line.length);
    if (close == -1) return false;

    // Demonstrate suffix check: ends with '.' (common in some messages).
    return line.endsWithBytes(ascii('.'));
  }

  final samples = <String>[
    '   [Mon Jan 05 17:00:27 2026] Hello there.',
    '\t[Mon Jan 05 17:01:10 2026] Another line.',
    'No bracket prefix.',
    ' [Mon Jan 05 17:01:10 2026] Missing period',
  ];

  for (final s in samples) {
    // In real usage, these bytes would typically come from a file or stream.
    // Here we convert strings to bytes to keep the example self-contained.
    final b = ascii(s);
    print('${looksLikeLogLine(b) ? 'OK  ' : 'BAD '}  $s');
  }

  // Just to show rbracket exists / how you'd build prefixes/suffixes:
  print('Example prefixes: ${String.fromCharCodes(lbracket)} ... ${String.fromCharCodes(rbracket)}');
}
