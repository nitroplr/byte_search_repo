import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:byte_search_io/src/chunked_file_reader.dart';
import 'package:byte_search_io/src/record_reader.dart';

void main() {
  group('ChunkedFileReader.openRandomAccessFile (chunks)', () {
    test('reads file in fixed fresh chunk sizes with correct offsets and isLast', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_test_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/a.bin');
      final bytes = Uint8List.fromList(List<int>.generate(26, (i) => 'a'.codeUnitAt(0) + i)); // a..z
      await file.writeAsBytes(bytes);

      final raf = await file.open(mode: FileMode.read);
      final reader = const ChunkedFileReader(closeRafOnDone: true);

      final chunks = await reader.openRandomAccessFile(raf: raf, chunkSize: 10, overlap: 0).toList();

      expect(chunks.length, 3);

      expect(chunks[0].fileOffset, 0);
      expect(chunks[0].bytes, bytes.sublist(0, 10));
      expect(chunks[0].isLast, isFalse);

      expect(chunks[1].fileOffset, 10);
      expect(chunks[1].bytes, bytes.sublist(10, 20));
      expect(chunks[1].isLast, isFalse);

      expect(chunks[2].fileOffset, 20);
      expect(chunks[2].bytes, bytes.sublist(20, 26));
      expect(chunks[2].isLast, isTrue);

      // closeRafOnDone == true => raf should be closed now.
      expect(() async => raf.length(), throwsA(isA<FileSystemException>()));
    });

    test('isLast is correct when file length is an exact multiple of chunkSize', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_test_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/b.bin');
      final bytes = Uint8List.fromList(List<int>.generate(20, (i) => i));
      await file.writeAsBytes(bytes);

      final raf = await file.open(mode: FileMode.read);
      final reader = const ChunkedFileReader(closeRafOnDone: true);

      final chunks = await reader.openRandomAccessFile(raf: raf, chunkSize: 10).toList();
      expect(chunks.length, 2);
      expect(chunks[0].isLast, isFalse);
      expect(chunks[1].isLast, isTrue);
    });

    test('overlap prefixes next chunk with tail of previous fresh bytes', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_test_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/c.bin');
      final bytes = Uint8List.fromList(List<int>.generate(26, (i) => 'a'.codeUnitAt(0) + i)); // a..z
      await file.writeAsBytes(bytes);

      final raf = await file.open(mode: FileMode.read);
      final reader = const ChunkedFileReader(closeRafOnDone: true);

      final chunks =
      await reader.openRandomAccessFile(raf: raf, chunkSize: 10, overlap: 3).toList();

      expect(chunks.length, 3);

      // First chunk: just fresh
      expect(chunks[0].fileOffset, 0);
      expect(chunks[0].bytes, bytes.sublist(0, 10));

      // Second chunk: last 3 of previous fresh + next 10 fresh
      expect(chunks[1].fileOffset, 10 - 3);
      expect(chunks[1].bytes, bytes.sublist(7, 20));

      // Third chunk: last 3 of previous fresh + remaining 6
      expect(chunks[2].fileOffset, 20 - 3);
      expect(chunks[2].bytes, bytes.sublist(17, 26));
      expect(chunks[2].isLast, isTrue);
    });

    test('closeRafOnDone=false does not close provided raf', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_test_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/d.bin');
      await file.writeAsBytes(Uint8List.fromList(List<int>.generate(5, (i) => i)));

      final raf = await file.open(mode: FileMode.read);
      final reader = const ChunkedFileReader(closeRafOnDone: false);

      final chunks = await reader.openRandomAccessFile(raf: raf, chunkSize: 2).toList();
      expect(chunks, isNotEmpty);

      // Should still be open.
      expect(await raf.length(), 5);
      await raf.close();
    });
  });

  group('ChunkedFileReader.openRandomAccessFileRange (ranges)', () {
    test('reads only the requested range with correct offsets and isLast', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_test_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/range.bin');
      final bytes = Uint8List.fromList(List<int>.generate(50, (i) => i));
      await file.writeAsBytes(bytes);

      final raf = await file.open(mode: FileMode.read);
      final reader = const ChunkedFileReader(closeRafOnDone: true);

      final start = 10;
      final end = 35;
      final chunks = await reader
          .openRandomAccessFileRange(
        raf: raf,
        chunkSize: 8,
        startOffset: start,
        endOffsetExclusive: end,
        overlap: 0,
        closeOnDone: true,
      )
          .toList();

      // Validate offsets
      expect(chunks.first.fileOffset, start);
      expect(chunks.last.isLast, isTrue);

      // Validate data concatenation equals exact range bytes.
      final joined = Uint8List.fromList(chunks.expand((c) => c.bytes).toList());
      expect(joined, bytes.sublist(start, end));
    });

    test('range reader rejects overlap != 0', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_test_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/range2.bin');
      await file.writeAsBytes(Uint8List.fromList(List<int>.generate(10, (i) => i)));

      final raf = await file.open(mode: FileMode.read);
      final reader = const ChunkedFileReader();

      expect(
            () => reader.openRandomAccessFileRange(
          raf: raf,
          chunkSize: 4,
          overlap: 1,
          startOffset: 0,
          endOffsetExclusive: 10,
        ).toList(),
        throwsA(isA<ArgumentError>()),
      );

      await raf.close();
    });
  });

  group('ChunkedFileReader.openPathRecords / openRandomAccessFileRecords (records)', () {
    RecordReader rr({bool trimCR = true}) => RecordReader(delimiter: 0x0A, trimCarriageReturn: trimCR);

    Future<File> writeTextFile(Directory dir, String name, String content) async {
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(Uint8List.fromList(content.codeUnits));
      return file;
    }

    test('yields newline-delimited records with correct bytes and foundTerminator', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_records_');
      addTearDown(() => dir.delete(recursive: true));

      final file = await writeTextFile(dir, 'lines.txt', 'a\nbb\nccc\n');

      final reader = const ChunkedFileReader();
      final slices = await reader.openPathRecords(
        path: file.path,
        recordReader: rr(),
        chunkSize: 4, // force multiple reads
      ).toList();

      expect(slices.map((s) => s.toStringUtf8()).toList(), ['a', 'bb', 'ccc']);
      expect(slices.every((s) => s.foundTerminator), isTrue);
      expect(slices.every((s) => s.startTruncated == false), isTrue);
      expect(slices.every((s) => s.endTruncated == false), isTrue);
    });

    test('trims CR when trimCarriageReturn=true', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_records_');
      addTearDown(() => dir.delete(recursive: true));

      final file = await writeTextFile(dir, 'crlf.txt', 'a\r\nb\r\n');

      final reader = const ChunkedFileReader();
      final slices = await reader.openPathRecords(
        path: file.path,
        recordReader: rr(trimCR: true),
        chunkSize: 3,
      ).toList();

      expect(slices.map((s) => s.toStringUtf8()).toList(), ['a', 'b']);
    });

    test('does NOT trim CR when trimCarriageReturn=false', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_records_');
      addTearDown(() => dir.delete(recursive: true));

      final file = await writeTextFile(dir, 'crlf_no_trim.txt', 'a\r\nb\r\n');

      final reader = const ChunkedFileReader();
      final slices = await reader.openPathRecords(
        path: file.path,
        recordReader: rr(trimCR: false),
        chunkSize: 3,
      ).toList();

      expect(slices.map((s) => s.toStringUtf8()).toList(), ['a\r', 'b\r']);
    });

    test('startOffset inside a record yields startTruncated=true and begins at startOffset', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_records_');
      addTearDown(() => dir.delete(recursive: true));

      // bytes: "aa\nbb\ncc\n"
      final file = await writeTextFile(dir, 'trunc_start.txt', 'aa\nbb\ncc\n');

      final reader = const ChunkedFileReader();
      final slices = await reader.openPathRecords(
        path: file.path,
        recordReader: rr(),
        chunkSize: 4,
        startOffset: 4, // inside "bb" (second 'b')
      ).toList();

      // First record begins at offset 4 and is missing the first 'b'
      expect(slices.first.startOffset, 4);
      expect(slices.first.toStringUtf8(), 'b');
      expect(slices.first.startTruncated, isTrue);
    });

    test('endOffsetExclusive inside a record yields final slice endTruncated=true & foundTerminator=false', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_records_');
      addTearDown(() => dir.delete(recursive: true));

      final content = 'aa\nbb\ncc\n';
      final file = await writeTextFile(dir, 'trunc_end.txt', content);
      final totalLen = content.codeUnits.length;

      // Cut inside the final "cc\n" record: endOffsetExclusive excludes the last 2 bytes.
      final endOffsetExclusive = totalLen - 2;

      final reader = const ChunkedFileReader();
      final slices = await reader.openPathRecords(
        path: file.path,
        recordReader: rr(),
        chunkSize: 4,
        endOffsetExclusive: endOffsetExclusive,
      ).toList();

      final last = slices.last;
      expect(last.foundTerminator, isFalse);
      expect(last.endTruncated, isTrue);
    });

    test('onChunkRecords last callback includes final unterminated record (no trailing newline)', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_records_');
      addTearDown(() => dir.delete(recursive: true));

      final file = await writeTextFile(dir, 'unterminated_last.txt', 'a\nb\nc');

      final reader = const ChunkedFileReader();

      final callbacks = <({int idx, String? first, String? last, bool? lastTerminated})>[];

      final slices = await reader.openPathRecords(
        path: file.path,
        recordReader: rr(),
        chunkSize: 2,
        onChunkRecords: (idx, first, last) {
          callbacks.add((
          idx: idx,
          first: first?.toStringUtf8(),
          last: last?.toStringUtf8(),
          lastTerminated: last?.foundTerminator,
          ));
        },
      ).toList();

      expect(slices.map((s) => s.toStringUtf8()).toList(), ['a', 'b', 'c']);
      expect(slices.last.foundTerminator, isFalse);

      // Last callback should report last == 'c' (unterminated).
      expect(callbacks, isNotEmpty);
      final lastCb = callbacks.last;
      expect(lastCb.last, 'c');
      expect(lastCb.lastTerminated, isFalse);
    });

    test('records remain contiguous across chunk boundaries (no missing record between callbacks)', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_records_');
      addTearDown(() => dir.delete(recursive: true));

      // Crafted to force boundary splits with small chunkSize.
      final file = await writeTextFile(dir, 'boundary.txt', '1111\n22222\n333333\n4444\n');

      final reader = const ChunkedFileReader();

      final cbPairs = <({RecordSlice? first, RecordSlice? last})>[];

      final slices = await reader.openPathRecords(
        path: file.path,
        recordReader: rr(),
        chunkSize: 5,
        onChunkRecords: (idx, first, last) {
          cbPairs.add((first: first, last: last));
        },
      ).toList();

      // Sanity: all records
      expect(slices.map((s) => s.toStringUtf8()).toList(), ['1111', '22222', '333333', '4444']);

      // Check contiguity between callbacks: if both adjacent have last/first,
      // next.first must start exactly after prev.last (accounting for '\n' delimiter).
      for (int i = 0; i + 1 < cbPairs.length; i++) {
        final prevLast = cbPairs[i].last;
        final nextFirst = cbPairs[i + 1].first;
        if (prevLast == null || nextFirst == null) continue;

        // For '\n' delimiter, next record starts at prev.end + 1
        expect(nextFirst.startOffset, prevLast.endOffsetExclusive + 1);
      }
    });

    test('throws if a record exceeds maxRecordBytes', () async {
      final dir = await Directory.systemTemp.createTemp('chunk_reader_records_');
      addTearDown(() => dir.delete(recursive: true));

      // Single huge record with no newline until the end.
      final big = 'x' * 200;
      final file = await writeTextFile(dir, 'too_big.txt', '$big\n');

      final reader = const ChunkedFileReader();

      expect(
            () => reader.openPathRecords(
          path: file.path,
          recordReader: rr(),
          chunkSize: 32,
          maxRecordBytes: 64,
        ).toList(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
