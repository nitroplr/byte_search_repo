// ignore_for_file: avoid_print

import 'dart:io';

import 'package:byte_search_io/byte_search_io.dart';

Future<void> main() async {
  final tuple = await _createTempLogFile(lines: [
    '[Mon Jan 05 17:00:27 2026] You say, \'hello\'',
    '[Mon Jan 05 17:01:10 2026] Some item was given to Ben.',
    '[Mon Jan 05 17:02:11 2026] Nothing to see here.',
  ]);

  final raf = await tuple.file.open(mode: FileMode.read);
  try {
    final reader = RecordReader(); // newline-delimited by default

    // Choose an offset somewhere inside the second line.
    final int offset = 10 + '[Mon Jan 05 17:00:27 2026] You say, \'hello\''.length;

    final rec = await reader.readRecordContainingOffset(raf, offset);

    print('File: ${tuple.file.path}');
    print('Offset: $offset');
    print('Record start: ${rec.startOffset}');
    print('Record end: ${rec.endOffsetExclusive}');
    print('Record: ${rec.toStringUtf8(allowMalformed: true)}');
  } finally {
    await raf.close();
    await tuple.dir.delete(recursive: true);
  }
}

Future<({File file, Directory dir})> _createTempLogFile({required List<String> lines}) async {
  final dir = await Directory.systemTemp.createTemp('byte_search_io_example_');
  final file = File('${dir.path}/log.txt');

  // Ensure newline-delimited.
  final contents = lines.map((s) => '$s\n').join();
  await file.writeAsString(contents);

  return (file: file, dir: dir);
}