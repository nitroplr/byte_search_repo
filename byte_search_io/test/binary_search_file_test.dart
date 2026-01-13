import 'dart:io';

import 'package:test/test.dart';
import 'package:byte_search_io/byte_search_io.dart';

typedef _TempTextBody = Future<void> Function(File file);

Future<void> _withTempTextFile({required String name, required String contents, required _TempTextBody body}) async {
  final dir = await Directory.systemTemp.createTemp('byte_search_io_bs_');
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

BinarySearchFile<int> _intKeySearch(RecordReader reader) {
  return BinarySearchFile<int>(
    recordReader: reader,
    parseKey: (rec) {
      final s = String.fromCharCodes(rec.bytes);
      final space = s.indexOf(' ');
      final head = (space == -1) ? s : s.substring(0, space);
      return int.tryParse(head);
    },
    compare: (a, b) => a.compareTo(b),
  );
}

void main() {
  group('BinarySearchFile', () {
    test('lowerBound/upperBound over integer keys (LF)', () async {
      await _withTempTextFile(
        name: 'nums.txt',
        contents: '10 hello\n20 world\n20 again\n35 end\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final bs = _intKeySearch(reader);

            final lb20 = await bs.lowerBound(raf: raf,target: 20);
            final recLb20 = await reader.readRecordContainingOffset(raf, lb20);
            expect(String.fromCharCodes(recLb20.bytes), '20 world');

            final ub20 = await bs.upperBound(raf:raf,target: 20);
            final recUb20 = await reader.readRecordContainingOffset(raf, ub20);
            expect(String.fromCharCodes(recUb20.bytes), '35 end');

            final lb5 = await bs.lowerBound(raf: raf,target: 5);
            final recLb5 = await reader.readRecordContainingOffset(raf, lb5);
            expect(String.fromCharCodes(recLb5.bytes), '10 hello');

            final ub100 = await bs.upperBound(raf:raf,target: 100);
            expect(ub100, await raf.length());
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('handles CRLF and missing trailing newline', () async {
      await _withTempTextFile(
        name: 'crlf.txt',
        contents: '1 a\r\n2 b\r\n3 c', // no final newline
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(trimCarriageReturn: true);
            final bs = _intKeySearch(reader);

            final lb2 = await bs.lowerBound(raf: raf,target: 2);
            final rec2 = await reader.readRecordContainingOffset(raf, lb2);
            expect(String.fromCharCodes(rec2.bytes), '2 b');

            final ub2 = await bs.upperBound(raf:raf,target: 2);
            final rec3 = await reader.readRecordContainingOffset(raf, ub2);
            expect(String.fromCharCodes(rec3.bytes), '3 c');

            final ub3 = await bs.upperBound(raf:raf,target: 3);
            expect(ub3, await raf.length());
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('skips unparseable records (e.g. header lines)', () async {
      await _withTempTextFile(
        name: 'header.txt',
        contents: '# header not parseable\n10 a\n20 b\n30 c\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final bs = _intKeySearch(reader);

            final lb20 = await bs.lowerBound(raf: raf,target: 20);
            final rec = await reader.readRecordContainingOffset(raf, lb20);
            expect(String.fromCharCodes(rec.bytes), '20 b');
          } finally {
            await raf.close();
          }
        },
      );
    });

    // ✅ Extra test #1: all records unparseable => terminates and returns EOF
    test('all records unparseable terminates and returns EOF', () async {
      await _withTempTextFile(
        name: 'all_bad.txt',
        contents: '#\n#\n#\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final bs = BinarySearchFile<int>(
              recordReader: reader,
              parseKey: (_) => null, // everything unparseable
              compare: (a, b) => a.compareTo(b),
            );

            final lb = await bs.lowerBound(raf: raf,target: 123);
            expect(lb, await raf.length());
          } finally {
            await raf.close();
          }
        },
      );
    });

    // ✅ Extra test #2: regression guard for delimiter-collapse / normalization
    test('does not hang when mid lands on delimiter-heavy positions', () async {
      // Tiny file where mid is very likely to land on delimiters.
      await _withTempTextFile(
        name: 'delims.txt',
        contents: '1 a\r\n2 b\r\n3 c\r\n4 d\r\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(trimCarriageReturn: true);
            final bs = _intKeySearch(reader);

            final lb3 = await bs.lowerBound(raf: raf,target: 3);
            final rec3 = await reader.readRecordContainingOffset(raf, lb3);
            expect(String.fromCharCodes(rec3.bytes), '3 c');

            final ub3 = await bs.upperBound(raf:raf,target: 3);
            final rec4 = await reader.readRecordContainingOffset(raf, ub3);
            expect(String.fromCharCodes(rec4.bytes), '4 d');
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('keys at extremes and out-of-range targets', () async {
      await _withTempTextFile(
        name: 'extremes.txt',
        contents: '10 a\n20 b\n30 c\n',
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader(trimCarriageReturn: true);
            final bs = _intKeySearch(reader);
            final text = await file.readAsString();

            final lbBelow = await bs.lowerBound(raf: raf,target: 5);
            expect(lbBelow, 0);

            final lbMin = await bs.lowerBound(raf: raf,target: 10);
            expect(lbMin, 0);

            final ubMin = await bs.upperBound(raf:raf,target: 10);
            expect(ubMin, text.indexOf('20 '));

            final ubMax = await bs.upperBound(raf:raf,target: 30);
            expect(ubMax, text.length);

            final lbAbove = await bs.lowerBound(raf: raf,target: 999);
            expect(lbAbove, text.length);
          } finally {
            await raf.close();
          }
        },
      );
    });

    test('BinarySearchFile tolerates unparseable junk without hanging', () async {
      final contents = List<String>.generate(500, (i) => 'junk $i').join('\n');

      await _withTempTextFile(
        name: 'all_junk.txt',
        contents: contents,
        body: (file) async {
          final raf = await file.open(mode: FileMode.read);
          try {
            final reader = RecordReader();
            final bs = _intKeySearch(reader);

            final lb = await bs.lowerBound(raf: raf,target: 42);
            final ub = await bs.upperBound(raf:raf,target: 42);

            final len = await raf.length();
            expect(lb, inInclusiveRange(0, len));
            expect(ub, inInclusiveRange(0, len));
          } finally {
            await raf.close();
          }
        },
      );
    });
  });
}
