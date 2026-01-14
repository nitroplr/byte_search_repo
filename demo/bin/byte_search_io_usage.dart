import 'dart:io';

import 'package:byte_search_io/byte_search_io.dart';
import 'package:demo/utility.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    //Usage: dart run demo/bin/byte_search_io_usage.dart demo\data\eqlog_Blastshadow_mischief.txt.gz
    stderr.writeln('Usage: dart run demo/bin/byte_search_io_usage.dart <path-to-log-or-gz>');
    exitCode = 64;
    return;
  }

  final File input = File(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('File not found: ${input.path}');
    exitCode = 66;
    return;
  }
  // could be with other utf8 file type, using .gz for the example file: final bytes = file.readAsBytesSync();
  // always be sure to delete the temp directory when done
  final (File file, Directory? directory) tuple = await ensureDecompressedToTempFile(file: input);
  final RandomAccessFile raf = await tuple.$1.open();

  try {
    print('Input: ${input.path}');
    print('Decompressed: ${tuple.$1.path}');
    print('Size: ${await raf.length()} bytes');

    final RecordReader recordReader = RecordReader();
    //I'm using DateTime in this case for binary search comparison, can be anything that is ordered in the file
    final BinarySearchFile<DateTime> bsf = BinarySearchFile<DateTime>(
      recordReader: recordReader,
      parseKey: (RecordSlice record) {
        return getLineTime(line: record.toStringUtf8());
      },
      compare: (a, b) => a.millisecondsSinceEpoch.compareTo(b.millisecondsSinceEpoch),
    );

    //if there is no record at the time, both offsets are the same
    int lowerNoRecordAt = await bsf.lowerBound(raf: raf, target: DateTime(2025, 11, 1, 0, 0));
    int upperNoRecordAt = await bsf.upperBound(raf: raf, target: DateTime(2025, 11, 1, 0, 0));
    print('lowerNoRecordAt: $lowerNoRecordAt upperNoRecordAt: $upperNoRecordAt');
    //[Mon Oct 20 21:22:22 2025] - there are many records with this time in the example log file
    final target = DateTime(2025, 10, 20, 21, 22, 22);
    int lowerManyRecordsAt = await bsf.lowerBound(raf: raf, target: target);
    int upperManyRecordsAt = await bsf.upperBound(raf: raf, target: target);
    //printing the 3 records before at and after the target
    print('upperManyRecordsAt: $upperManyRecordsAt');
    print(
      'before: ${(await recordReader.readRecordBeforeOffset(raf: raf, offset: upperManyRecordsAt))?.toStringUtf8()}',
    );
    print('at: ${(await recordReader.readRecordContainingOffset(raf, upperManyRecordsAt)).toStringUtf8()}');
    print('after: ${(await recordReader.readRecordAfterOffset(raf: raf, offset: upperManyRecordsAt))?.toStringUtf8()}');
    print('-----------------');
    //printing the 3 records before at and after the target
    print('lowerManyRecordsAt: $lowerManyRecordsAt');
    print(
      'before: ${(await recordReader.readRecordBeforeOffset(raf: raf, offset: lowerManyRecordsAt))?.toStringUtf8()}',
    );
    print('at: ${(await recordReader.readRecordContainingOffset(raf, lowerManyRecordsAt)).toStringUtf8()}');
    print('after: ${(await recordReader.readRecordAfterOffset(raf: raf, offset: lowerManyRecordsAt))?.toStringUtf8()}');
    print('-----------------');
    //add startOffset and endOffset to only parse a window of a file
    //the commented out lines would print every record with target's time

    //onChunkRecords validates chunking behavior and shows chunk boundaries do not skip lines
    //closeRafOnDone is false since we close it here
    //uncommenting below will print all records at target time
    final ChunkedFileReader chunker = ChunkedFileReader(closeRafOnDone: false);
    // ignore: unused_local_variable
    await for (final record in chunker.openRandomAccessFileRecords(
      raf: raf,
      recordReader: recordReader /*,
    startOffset: lowerManyRecordsAt,
    endOffsetExclusive: upperManyRecordsAt,*/,
      onChunkRecords: (int i, RecordSlice? first, RecordSlice? last) {
        print('Chunk $i');
        print('first: ${first?.toStringUtf8()}');
        print('last: ${last?.toStringUtf8()}');
      },
    )) {
      /*print(record.toStringUtf8());*/
    }
  } catch (e) {
    print(e);
  } finally {
    await raf.close();
    await tuple.$2?.delete(recursive: true);
  }
}
