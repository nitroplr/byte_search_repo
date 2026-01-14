// ignore_for_file: avoid_print

import 'dart:io';

import 'package:byte_search_io/byte_search_io.dart';

Future<void> main() async {
  final tuple = await _createTempLogFile(lines: [
    '[Mon Jan 05 17:00:27 2026] You say, \'hello\'',
    '[Mon Jan 05 17:01:10 2026] Some item was given to Ben.',
    '[Mon Jan 05 17:02:11 2026] Some item was given to Isla.',
    '[Mon Jan 05 17:03:11 2026] Nothing to see here.',
  ]);

  final raf = await tuple.file.open(mode: FileMode.read);

  // Uses '\n' delimiter by default; trims '\r' if present.
  final recordReader = RecordReader();

  // Keep ownership of raf so we can close it ourselves.
  final chunked = ChunkedFileReader(closeRafOnDone: false);

  // Re-exported from byte_search:
  final givenTo = BytePattern.fromAscii(needle: ' was given to ');

  try {
    print('Streaming records from: ${tuple.file.path}');
    await for (final rec in chunked.openRandomAccessFileRecords(
      raf: raf,
      recordReader: recordReader,
      chunkSize: 64, // force multiple chunks even on tiny files
    )) {
      // rec.bytes is the record without '\n' (and optionally without '\r').
      if (givenTo.hasMatch(haystack: rec.bytes)) {
        print('MATCH @ [${rec.startOffset}, ${rec.endOffsetExclusive}): ${rec.toStringUtf8(allowMalformed: true)}');
      }
    }
  } finally {
    await raf.close();
    await tuple.dir.delete(recursive: true);
  }
}

Future<({File file, Directory dir})> _createTempLogFile({required List<String> lines}) async {
  final dir = await Directory.systemTemp.createTemp('byte_search_io_example_');
  final file = File('${dir.path}/log.txt');

  final contents = lines.map((s) => '$s\n').join();
  await file.writeAsString(contents);

  return (file: file, dir: dir);
}
