import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:demo/patterns/patterns.dart';

Uint8List readFileAutoDecompress(File file) {
  final Uint8List raw = file.readAsBytesSync();

  // gzip magic header: 1F 8B
  final bool isGzip = raw.length >= 2 && raw[0] == 0x1F && raw[1] == 0x8B;

  if (!isGzip) {
    return raw;
  }

  final List<int> decoded = gzip.decode(raw);
  return Uint8List.fromList(decoded);
}

/// Returns a file that is safe to binary-search with RandomAccessFile.
/// - If [file] is NOT gzipped, returns [file].
/// - If [file] IS gzipped, decompresses it to a temp file and returns a [file] and [Directory]
/// - MUST DELETE THE LARGE TEST DIRECTORY WHEN DONE.
///
/// This avoids loading the whole file into memory and enables true random access.
Future<(File, Directory?)> ensureDecompressedToTempFile({required File file}) async {
  // Quick gzip check: read first 2 bytes (magic header 1F 8B)
  final raf = await file.open();
  try {
    final len = await raf.length();
    if (len < 2) return (file, null);

    await raf.setPosition(0);
    final b0 = await raf.readByte();
    final b1 = await raf.readByte();
    final isGzip = (b0 == 0x1F && b1 == 0x8B);
    if (!isGzip) return (file, null);
  } finally {
    await raf.close();
  }

  // Create a temp output file next to system temp
  final tempDir = await Directory.systemTemp.createTemp('byte_search_io_');
  final baseName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'input.gz';
  final outName = baseName.endsWith('.gz')
      ? baseName.substring(0, baseName.length - 3)
      : '$baseName.decompressed';

  final outFile = File('${tempDir.path}${Platform.pathSeparator}$outName');

  // Stream-decompress gzip to disk (no full file in RAM)
  final input = file.openRead(); // Stream<List<int>>
  final output = outFile.openWrite(); // IOSink

  try {
    // dart:io automatically provides gzip decoder via .transform(gzip.decoder)
    await input.transform(gzip.decoder).pipe(output);
  } finally {
    await output.close();
  }

  return (outFile, tempDir);
}

DateTime? getLineTime({required String line}) {
  //[Mon Sep 29 23:06:56 2025]
  String lineTime = line.substring(1, line.indexOf(']'));
  //try without regex because regex is very slow
  try {
    final String time = lineTime.substring(lineTime.indexOf(':') - 2, lineTime.lastIndexOf(':') + 3);
    final String year = lineTime.substring(lineTime.length - 4);
    final String month = Patterns.months[lineTime.substring(4, 7)]!;
    final String day = lineTime.substring(8, 10);
    return DateTime.parse('$year-$month-$day $time');
  } catch (e) {
    log('line time error: $lineTime\n${e.toString()}');
  }
  try {
    final String time = lineTime.substring(lineTime.indexOf(RegExp(r'\d\d:')), lineTime.indexOf(RegExp(r' \d\d\d\d')));
    final String year = lineTime.substring(lineTime.indexOf(RegExp(r'\d\d\d\d')));
    final String month = Patterns.months[lineTime.substring(4, 7)]!;
    final String day = lineTime.substring(8, 10);
    return DateTime.parse('$year-$month-$day $time');
  } catch (e) {
    log('other line time error: $lineTime\n${e.toString()}');
  }
  return null;
}
