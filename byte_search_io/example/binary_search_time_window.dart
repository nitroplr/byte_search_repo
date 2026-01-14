// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:byte_search_io/byte_search_io.dart';

Future<void> main() async {
  final tuple = await _createSortedTempLogFile();
  final raf = await tuple.file.open(mode: FileMode.read);

  final recordReader = RecordReader(delimiter: 0x0A /* '\n' */);

  final bs = BinarySearchFile<DateTime>(
    recordReader: recordReader,
    parseKey: (rec) => _tryParseBracketedTime(rec.bytes),
    compare: (a, b) => a.compareTo(b),
  );

  // Choose a window that matches some of the generated lines.
  final startTime = DateTime(2026, 1, 1, 0, 2, 0);
  final endTime = DateTime(2026, 1, 1, 0, 4, 0);

  try {
    final startOffset = await bs.lowerBound(raf: raf, target: startTime);
    final endOffset = await bs.upperBound(raf: raf, target: endTime);

    print('File: ${tuple.file.path}');
    print('Window: [$startTime, $endTime)');
    print('Offsets: [$startOffset, $endOffset)');

    final chunked = ChunkedFileReader(closeRafOnDone: false);

    print('--- Records in window ---');
    await for (final rec in chunked.openRandomAccessFileRecords(
      raf: raf,
      recordReader: recordReader,
      startOffset: startOffset,
      endOffsetExclusive: endOffset,
      chunkSize: 1 << 16, // 64 KiB
    )) {
      final t = _tryParseBracketedTime(rec.bytes);
      // In a real log, you might skip unparseable records; this example emits only parseable ones.
      if (t != null && !t.isBefore(startTime) && t.isBefore(endTime)) {
        print(rec.toStringUtf8(allowMalformed: true));
      }
    }
  } finally {
    await raf.close();
    await tuple.dir.delete(recursive: true);
  }
}

/// Parses timestamps like:
///   [2026-01-01 00:03:00] message...
///
/// Returns null if the record doesn't match the expected prefix.
///
/// Note: This is an example parser. For real logs, implement parsing for your format.
DateTime? _tryParseBracketedTime(Uint8List bytes) {
  // Fast/cheap checks to avoid decoding the whole line:
  if (bytes.isEmpty || bytes[0] != '['.codeUnitAt(0)) return null;

  // Find closing bracket.
  int close = -1;
  for (int i = 1; i < bytes.length; i++) {
    if (bytes[i] == ']'.codeUnitAt(0)) {
      close = i;
      break;
    }
  }
  if (close == -1) return null;

  final inside = String.fromCharCodes(bytes.sublist(1, close));
  // Expected: "YYYY-MM-DD HH:MM:SS"
  // Example:  "2026-01-01 00:03:00"
  try {
    final year = int.parse(inside.substring(0, 4));
    final month = int.parse(inside.substring(5, 7));
    final day = int.parse(inside.substring(8, 10));
    final hour = int.parse(inside.substring(11, 13));
    final minute = int.parse(inside.substring(14, 16));
    final second = int.parse(inside.substring(17, 19));
    return DateTime(year, month, day, hour, minute, second);
  } catch (_) {
    return null;
  }
}

Future<({File file, Directory dir})> _createSortedTempLogFile() async {
  final dir = await Directory.systemTemp.createTemp('byte_search_io_example_');
  final file = File('${dir.path}/sorted.log');

  // Generate monotonic timestamps (sorted by time).
  final base = DateTime(2026, 1, 1, 0, 0, 0);
  final lines = <String>[
    '${_fmt(base.add(const Duration(minutes: 0)))} boot',
    '${_fmt(base.add(const Duration(minutes: 1)))} init',
    '${_fmt(base.add(const Duration(minutes: 2)))} start',
    '${_fmt(base.add(const Duration(minutes: 3)))} doing work',
    '${_fmt(base.add(const Duration(minutes: 4)))} still working',
    '${_fmt(base.add(const Duration(minutes: 5)))} done',
  ];

  await file.writeAsString(lines.map((l) => '$l\n').join());
  return (file: file, dir: dir);
}

String _fmt(DateTime t) {
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '[${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}]';
}
