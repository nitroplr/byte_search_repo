import 'dart:io';

import 'package:byte_search_io/byte_search_io.dart';
import 'package:demo/patterns/byte_patterns.dart';
import 'package:demo/utility.dart';

//Usage: dart run demo/bin/real_world_usage.dart
Future<void> main() async {
  final File file = File('demo/data/eqlog_Blastshadow_mischief.txt.gz');
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${file.path}');
    exitCode = 66;
    return;
  }
  final (File file, Directory? directory) tuple = await ensureDecompressedToTempFile(file: file);
  final RandomAccessFile raf = await tuple.$1.open();

  try {
    //[Mon Oct 20 20:45:34 2025] dummy start time ~1/3 through file
    final DateTime start = DateTime(2025, 10, 20, 20, 45, 34);
    //[Mon Oct 27 21:21:54 2025] dummy end time ~2/3 through file
    final DateTime end = DateTime(2025, 10, 27, 21, 21, 54);

    final RecordReader recordReader = RecordReader();
    final BinarySearchFile<DateTime> bsf = BinarySearchFile<DateTime>(
      recordReader: recordReader,
      parseKey: (RecordSlice record) {
        return getLineTime(line: record.toStringUtf8());
      },
      compare: (a, b) => a.millisecondsSinceEpoch.compareTo(b.millisecondsSinceEpoch),
    );

    int lowerBound = await bsf.lowerBound(raf: raf, target: start);
    int upperBound = await bsf.upperBound(raf: raf, target: end);

    // use the chunker to avoid loading the whole file into memory
    final ChunkedFileReader chunker = ChunkedFileReader(closeRafOnDone: false);
    // stream the records between the bounds with the chunker
    final Stream<RecordSlice> recordStream = chunker.openRandomAccessFileRecords(
      raf: raf,
      recordReader: recordReader /*,
      startOffset: lowerBound,
      endOffsetExclusive: upperBound,*/,
    );

    await for (final RecordSlice record in recordStream) {
      //filter out the majority of uninteresting lines
      if (BytePatterns.lineInterestingBytes(bytes: record.bytes)) {
        if (BytePatterns.isLootedLine(bytes: record.bytes)) {

        }
      }
    }
  } catch (e) {
    print(e);
  } finally {
    await raf.close();
    await tuple.$2?.delete(recursive: true);
  }
}
