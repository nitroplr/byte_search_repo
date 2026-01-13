import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';
import 'package:demo/patterns/byte_patterns.dart';
import 'package:demo/patterns/patterns.dart';
import 'package:demo/utility.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    //Usage: dart run demo/bin/byte_search_bench.dart demo\data\eqlog_Blastshadow_mischief.txt.gz
    stderr.writeln('Usage: dart run demo/bin/byte_search_bench.dart <path-to-log-or-gz>');
    exitCode = 64;
    return;
  }

  final File file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${file.path}');
    exitCode = 66;
    return;
  }
  // could be with raw .txt file: final bytes = file.readAsBytesSync();
  final Uint8List bytes = readFileAutoDecompress(file);
  print('File: ${file.path}');
  print('Size: ${bytes.length} bytes');

  // Warmup (helps JIT)
  final Stopwatch a = Stopwatch()..start();
  _runByteSearch(bytes);
  a.stop();
  print('byte search warm up: ${a.elapsedMilliseconds}');

  final Stopwatch b = Stopwatch()..start();
  _runStringContains(bytes);
  b.stop();
  print('string contains warm up: ${b.elapsedMilliseconds}');
  //_debugMismatch(bytes);

  const runs = 5;

  final List<int> byteTimes = [];
  final List<int> strTimes = [];

  int byteHits = 0;
  int strHits = 0;
  int totalLines = 0;

  for (int r = 0; r < runs; r++) {
    final Stopwatch a = Stopwatch()..start();
    final BenchResult resultByteSearch = _runByteSearch(bytes);
    a.stop();

    final Stopwatch b = Stopwatch()..start();
    final BenchResult resultStringSearch = _runStringContains(bytes);
    b.stop();
    print('byte time: ${a.elapsedMilliseconds} string time ${b.elapsedMilliseconds}');
    byteTimes.add(a.elapsedMilliseconds);
    strTimes.add(b.elapsedMilliseconds);

    // keep values live so optimizer can't throw work away
    byteHits = resultByteSearch.hits;
    strHits = resultStringSearch.hits;
    if (resultByteSearch.totalLines != resultStringSearch.totalLines) {
      print('WARNING: line count mismatch.');
    }
    totalLines = resultByteSearch.totalLines;
  }

  print('');
  print('Lines: $totalLines');
  print('Interesting (byte_search): $byteHits');
  print('Interesting (String.contains): $strHits');

  print('');
  print('byte_search ms: $byteTimes  (avg ${_avg(byteTimes)} ms)');
  print('contains   ms: $strTimes   (avg ${_avg(strTimes)} ms)');

  final avgB = _avg(byteTimes);
  final avgS = _avg(strTimes);
  if (avgB > 0) {
    final speedup = avgS / avgB;
    print('');
    print('Speedup: ${speedup.toStringAsFixed(2)}x (contains / byte_search)');
  }

  // If these differ, it indicates an edge case worth investigating.
  if (byteHits != strHits) {
    print('');
    print('WARNING: hit counts differ. This usually means encoding or message-start parsing differs.');
  }
}

double _avg(List<int> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

class BenchResult {
  final int totalLines;
  final int hits;

  BenchResult(this.totalLines, this.hits);
}

void _debugMismatch(Uint8List fileBytes) {
  int start = 0;
  int lineNo = 0;
  final n = fileBytes.length;

  while (start < n) {
    int end = indexOfByte(bytes:fileBytes,value:  10 /*\n*/, start: start);
    if (end == -1) end = n;
    lineNo++;


    final lineBytes = Uint8List.sublistView(fileBytes, start, end);
    final interestingBytes = BytePatterns.lineInterestingBytes(bytes: lineBytes);
    final line = utf8.decode(lineBytes, allowMalformed: true);

    int msgStartStr = line.indexOf('] ');
    msgStartStr = (msgStartStr != -1) ? msgStartStr + 2 : 0;
    final msg = (msgStartStr == 0) ? line : line.substring(msgStartStr);

    final interestingStr = Patterns.lineInteresting(line: msg);

    if (interestingBytes != interestingStr) {
      print('Mismatch on line $lineNo');
      print('  msgStartStr=$msgStartStr');
      print('  interestingBytes=$interestingBytes interestingStr=$interestingStr');
      print('  line preview: ${line.length > 220 ? line.substring(0, 220) : line}');
      break;
    }

    start = end + 1;
  }
}

/// Your byte-level scan: no decoding, no per-line string allocation.
/// IMPORTANT: This uses the SAME logical structure/order as the String.contains baseline.
BenchResult _runByteSearch(Uint8List fileBytes) {
  int hits = 0;
  int lines = 0;

  int start = 0;
  final int n = fileBytes.length;

  while (start < n) {
    int end = indexOfByte(bytes:fileBytes,value:  10 /* \n */, start: start); // LF
    if (end == -1) end = n;

    lines++;

    final Uint8List lineBytes = Uint8List.sublistView(fileBytes, start, end);

    // SAME boolean expression + SAME short-circuit order as String baseline
    final bool interesting = BytePatterns.lineInterestingBytes(bytes: lineBytes);

    if (interesting) hits++;

    start = end + 1;
  }

  return BenchResult(lines, hits);
}

/// Baseline: decode each line and use String.contains.
/// IMPORTANT: Uses the same message-start rule and the same boolean structure/order as bytes.
BenchResult _runStringContains(Uint8List fileBytes) {
  int hits = 0;
  int lines = 0;

  int start = 0;
  final int n = fileBytes.length;

  while (start < n) {
    int end = indexOfByte(bytes:fileBytes,value:  10 /* \n */, start: start);
    if (end == -1) end = n;

    final Uint8List lineBytes = Uint8List.sublistView(fileBytes, start, end);
    lines++;

    // Decode per line (this is the expensive baseline)
    final String line = utf8.decode(lineBytes, allowMalformed: true);

    // SAME message start logic: find "] " and search after it
    int msgStart = line.indexOf('] ');
    if (msgStart != -1) {
      msgStart += 2;
    } else {
      msgStart = 0;
    }
    final String msg = (msgStart == 0) ? line : line.substring(msgStart);

    // SAME boolean expression + SAME short-circuit order as byte side
    final bool interesting = Patterns.lineInteresting(line: msg);

    if (interesting) hits++;

    start = end + 1;
  }

  return BenchResult(lines, hits);
}
