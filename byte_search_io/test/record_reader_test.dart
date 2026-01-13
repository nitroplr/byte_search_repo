import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:byte_search_io/byte_search_io.dart';

typedef _TempTextBody = Future<void> Function(File file);

Future<void> _withTempTextFile({required String name, required String contents, required _TempTextBody body}) async {
  final dir = await Directory.systemTemp.createTemp('byte_search_io_rr_');
  final file = File('${dir.path}/$name');
  try {
    await file.writeAsString(contents, flush: true);
    await body(file);
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

void main() {
  group('RecordReader', () {
    test('reads the line containing an offset (LF)', () async {
      await _withTempTextFile(
        name: 'a.txt',
        contents: 'aaa\nbbb\nccc\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final text = await file.readAsString();
            final rec = await reader.readRecordContainingOffset(raf, text.indexOf('bbb') + 1);

            expect(String.fromCharCodes(rec.bytes), 'bbb');
            expect(rec.foundTerminator, isTrue);
            expect(rec.startTruncated, isFalse);
            expect(rec.endTruncated, isFalse);
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('offset at delimiter returns next record', () async {
      await _withTempTextFile(
        name: 'b.txt',
        contents: '111\n222\n333\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final text = await file.readAsString();
            final newlineAfter111 = text.indexOf('\n');

            final rec = await reader.readRecordContainingOffset(raf, newlineAfter111);
            expect(String.fromCharCodes(rec.bytes), '222');
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('handles last line without newline (foundTerminator=false)', () async {
      await _withTempTextFile(
        name: 'c.txt',
        contents: 'x\ny\nlast',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final text = await file.readAsString();

            final rec = await reader.readRecordContainingOffset(raf, text.length); // EOF
            expect(String.fromCharCodes(rec.bytes), 'last');
            expect(rec.foundTerminator, isFalse);
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('trims CR for CRLF lines', () async {
      await _withTempTextFile(
        name: 'd.txt',
        contents: 'a\r\nb\r\nc\r\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(trimCarriageReturn: true);
            final text = await file.readAsString();

            final rec = await reader.readRecordContainingOffset(raf, text.indexOf('b'));
            expect(String.fromCharCodes(rec.bytes), 'b');
            expect(rec.foundTerminator, isTrue);
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('startTruncated when backward scan limit too small', () async {
      final huge = 'A' * 2000;
      await _withTempTextFile(
        name: 'e.txt',
        contents: '$huge\ntail\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(maxBackwardScanBytes: 64, scanBlockSize: 64);

            final rec = await reader.readRecordContainingOffset(raf, 1500);
            expect(rec.startTruncated, isTrue);
            expect(rec.bytes.isNotEmpty, isTrue);
          } finally {
            await raf.close();
          }
        },
      );
    });

    // ✅ Extra test #1: EOF on CRLF without trailing newline trims CR
    test('EOF on CRLF without trailing newline returns last record trimmed', () async {
      await _withTempTextFile(
        name: 'f.txt',
        contents: 'a\r\nb\r\nc', // no final '\n'
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(trimCarriageReturn: true);
            final text = await file.readAsString();

            final rec = await reader.readRecordContainingOffset(raf, text.length);
            expect(String.fromCharCodes(rec.bytes), 'c');
            expect(rec.foundTerminator, isFalse);
          } finally {
            await raf.close();
          }
        },
      );
    });

    // ✅ Extra test #2: leading delimiter + consecutive delimiters (empty records)
    test('handles leading delimiter and consecutive delimiters', () async {
      await _withTempTextFile(
        name: 'g.txt',
        contents: '\nA\n\nB\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();

            // offset at 0 is a delimiter => should return next record "A"
            final recA = await reader.readRecordContainingOffset(raf, 0);
            expect(String.fromCharCodes(recA.bytes), 'A');

            // Now verify the empty record between the consecutive delimiters "\n\n"
            final text = await file.readAsString();
            final idxDouble = text.indexOf('\n\n');
            expect(idxDouble, isNot(-1));

            // The empty record is between those two delimiters.
            // Put the offset exactly at the second delimiter; by semantics, that means "next record",
            // so to get the empty record, we read "containing offset" just *after* the first delimiter.
            final recEmpty = await reader.readRecordContainingOffset(raf, idxDouble + 1);
            expect(String.fromCharCodes(recEmpty.bytes), '');

            // And sanity-check that the next record after the empty one is "B"
            final recB = await reader.readRecordContainingOffset(raf, idxDouble + 2);
            expect(String.fromCharCodes(recB.bytes), 'B');
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('RecordReader endTruncated when forward scan limit too small', () async {
      final huge = 'A' * 2000;

      await _withTempTextFile(
        name: 'end_trunc.txt',
        contents: '$huge\nTAIL\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            const offset = 10;
            const maxForward = 64;

            final reader = RecordReader(maxForwardScanBytes: maxForward, scanBlockSize: 64);

            final rec = await reader.readRecordContainingOffset(raf, offset);

            expect(rec.endTruncated, isTrue);
            expect(rec.foundTerminator, isFalse);

            // Forward truncation is computed from the requested offset.
            expect(rec.endOffsetExclusive, offset + maxForward);

            // No prior delimiter, so record starts at 0.
            expect(rec.startOffset, 0);

            // Bytes cover [startOffset, endOffsetExclusive).
            expect(rec.bytes.length, rec.endOffsetExclusive - rec.startOffset);
            expect(rec.bytes.length, offset + maxForward); // 74
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('empty file returns empty slice', () async {
      await _withTempTextFile(
        name: 'empty.txt',
        contents: '',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final rec = await reader.readRecordContainingOffset(raf, 0);
            expect(rec.bytes, isEmpty);
            expect(rec.foundTerminator, isFalse);
            expect(rec.startTruncated, isFalse);
            expect(rec.endTruncated, isFalse);
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('offset beyond EOF clamps to EOF', () async {
      await _withTempTextFile(
        name: 'clamp.txt',
        contents: 'x\ny\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final rec = await reader.readRecordContainingOffset(raf, 999999);
            // At EOF and file ends with '\n' => last record is empty with current logic.
            expect(String.fromCharCodes(rec.bytes), '');
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('file ending with delimiter returns empty last record at EOF', () async {
      await _withTempTextFile(
        name: 'last_empty.txt',
        contents: 'A\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final text = await file.readAsString();

            final rec = await reader.readRecordContainingOffset(raf, text.length);
            expect(String.fromCharCodes(rec.bytes), '');
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('trimCarriageReturn=false keeps CR', () async {
      await _withTempTextFile(
        name: 'no_trim.txt',
        contents: 'a\r\nb\r\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(trimCarriageReturn: false);
            final text = await file.readAsString();

            final rec = await reader.readRecordContainingOffset(raf, text.indexOf('b'));
            expect(String.fromCharCodes(rec.bytes), 'b\r');
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('custom delimiter works', () async {
      await _withTempTextFile(
        name: 'pipe.txt',
        contents: 'A|BB||CCC|',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(delimiter: '|'.codeUnitAt(0), trimCarriageReturn: false);

            final rec1 = await reader.readRecordContainingOffset(raf, 0);
            expect(String.fromCharCodes(rec1.bytes), 'A');

            final recEmpty = await reader.readRecordContainingOffset(raf, 'A|BB|'.length); // points at second '|'
            expect(String.fromCharCodes(recEmpty.bytes), '');

            final rec3 = await reader.readRecordContainingOffset(raf, 'A|BB||'.length);
            expect(String.fromCharCodes(rec3.bytes), 'CCC');
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('empty file (len == 0) returns empty slice shape', () async {
      await _withTempTextFile(
        name: 'empty.txt',
        contents: '',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final rec = await reader.readRecordContainingOffset(raf, 0);

            expect(rec.bytes, isEmpty);
            expect(rec.foundTerminator, isFalse);
            expect(rec.startOffset, 0);
            expect(rec.endOffsetExclusive, 0);
            expect(rec.startTruncated, isFalse);
            expect(rec.endTruncated, isFalse);
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('offset > EOF clamps to EOF', () async {
      await _withTempTextFile(
        name: 'clamp.txt',
        contents: 'x\ny\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final len = await raf.length();

            final rec = await reader.readRecordContainingOffset(raf, 999999);

            expect(rec.startOffset, len);
            expect(rec.endOffsetExclusive, len);
            // By design: trailing delimiter => empty record at EOF.
            expect(String.fromCharCodes(rec.bytes), '');
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('trimCarriageReturn: false keeps trailing CR in CRLF', () async {
      await _withTempTextFile(
        name: 'no_trim.txt',
        contents: 'a\r\nb\r\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(trimCarriageReturn: false);
            final text = await file.readAsString();

            final rec = await reader.readRecordContainingOffset(raf, text.indexOf('b'));
            expect(String.fromCharCodes(rec.bytes), 'b\r');
            expect(rec.foundTerminator, isTrue);
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('custom delimiter works (non-\\n)', () async {
      await _withTempTextFile(
        name: 'pipe.txt',
        contents: 'A|BB||CCC|',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(delimiter: '|'.codeUnitAt(0), trimCarriageReturn: false);

            final recA = await reader.readRecordContainingOffset(raf, 0);
            expect(String.fromCharCodes(recA.bytes), 'A');

            final text = await file.readAsString();
            final idxDouble = text.indexOf('||');
            expect(idxDouble, isNot(-1));

            // Offset just after the first '|' yields the empty record between '||'.
            final recEmpty = await reader.readRecordContainingOffset(raf, idxDouble + 1);
            expect(String.fromCharCodes(recEmpty.bytes), '');

            final recCCC = await reader.readRecordContainingOffset(raf, idxDouble + 2);
            expect(String.fromCharCodes(recCCC.bytes), 'CCC');
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('RecordReader fuzz: matches in-memory reference for many random offsets', () async {
      const seed = 1337;
      final rnd = Random(seed);

      // Generate random text with lots of newline delimiters, including consecutive and leading.
      const length = 2500;
      const delimiter = '\n';
      final sb = StringBuffer();

      for (int i = 0; i < length; i++) {
        // Bias toward delimiters so we get many edge cases.
        final roll = rnd.nextInt(100);
        if (roll < 18) {
          sb.write(delimiter);
        } else {
          // Printable ASCII letters/spaces.
          final v = rnd.nextInt(28);
          if (v == 0) {
            sb.write(' ');
          } else {
            sb.writeCharCode('A'.codeUnitAt(0) + (v - 1));
          }
        }
      }

      // Force a few known tricky cases:
      // - leading delimiter
      // - consecutive delimiters
      final contents = '\n\n${sb.toString()}\n\n';

      String referenceSlice(String s, int offset) {
        final len = s.length;
        int clamped = offset < 0 ? 0 : (offset > len ? len : offset);

        // Delimiter-on-offset semantics:
        // - Usually "next record" (advance by 1).
        // - But if previous char is also delimiter, do NOT advance (empty record between consecutive delimiters).
        if (clamped < len && s.codeUnitAt(clamped) == delimiter.codeUnitAt(0)) {
          bool shouldAdvance = true;

          if (clamped > 0 && s.codeUnitAt(clamped - 1) == delimiter.codeUnitAt(0)) {
            shouldAdvance = false;
          }
          if (clamped == 0) {
            shouldAdvance = true; // leading delimiter => next record
          }

          if (shouldAdvance) {
            clamped++;
            if (clamped > len) clamped = len;
          }
        }

        // Find record start (exclusive after the previous delimiter).
        final int start;
        if (clamped == 0) {
          start = 0;
        } else {
          final prevDelim = s.lastIndexOf(delimiter, clamped - 1);
          start = prevDelim == -1 ? 0 : prevDelim + 1;
        }

        // Find record end (at next delimiter, or EOF).
        final nextDelim = s.indexOf(delimiter, clamped);
        final end = nextDelim == -1 ? len : nextDelim;

        return s.substring(start, end);
      }

      await _withTempTextFile(
        name: 'record_reader_fuzz.txt',
        contents: contents,
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(
              delimiter: delimiter.codeUnitAt(0),
              trimCarriageReturn: true,
            );

            final len = await raf.length();
            expect(len, contents.length);

            // Include a bunch of random offsets plus key edges.
            final offsets = <int>[
              0,
              1,
              2,
              contents.length - 1,
              contents.length,
            ];

            for (int i = 0; i < 800; i++) {
              offsets.add(rnd.nextInt(contents.length + 1)); // inclusive of EOF
            }

            for (final offset in offsets) {
              final expected = referenceSlice(contents, offset);

              final rec = await reader.readRecordContainingOffset(raf, offset);
              final actual = String.fromCharCodes(rec.bytes);

              // Content match
              expect(actual, expected);

              // Offset bookkeeping match (derived from the same reference logic)
              // Re-derive start/end in terms of offsets to validate startOffset/endOffsetExclusive.
              final clampedOffset = offset > contents.length ? contents.length : offset;
              int effective = clampedOffset;

              if (effective < contents.length && contents.codeUnitAt(effective) == delimiter.codeUnitAt(0)) {
                bool shouldAdvance = true;
                if (effective > 0 && contents.codeUnitAt(effective - 1) == delimiter.codeUnitAt(0)) {
                  shouldAdvance = false;
                }
                if (effective == 0) shouldAdvance = true;
                if (shouldAdvance) {
                  effective++;
                  if (effective > contents.length) effective = contents.length;
                }
              }

              final int start;
              if (effective == 0) {
                start = 0;
              } else {
                final prevDelim = contents.lastIndexOf(delimiter, effective - 1);
                start = prevDelim == -1 ? 0 : prevDelim + 1;
              }

              final nextDelim = contents.indexOf(delimiter, effective);
              final end = nextDelim == -1 ? contents.length : nextDelim;

              expect(rec.startOffset, start);
              expect(rec.endOffsetExclusive, end);
            }
          } finally {
            await raf.close();
          }
        },
      );
    });
  });
}
