import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run demo/bin/bench.dart demo\data\eqlog_Blastshadow_mischief.txt.gz');
    exitCode = 64;
    return;
  }

  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${file.path}');
    exitCode = 66;
    return;
  }
  Uint8List readFileAutoDecompress(File file) {
    final raw = file.readAsBytesSync();

    // gzip magic header: 1F 8B
    final bool isGzip = raw.length >= 2 && raw[0] == 0x1F && raw[1] == 0x8B;

    if (!isGzip) {
      return raw;
    }

    final decoded = gzip.decode(raw);
    return Uint8List.fromList(decoded);
  }
  // could be with raw .txt file: final bytes = file.readAsBytesSync();
  final bytes = readFileAutoDecompress(file);
  print('File: ${file.path}');
  print('Size: ${bytes.length} bytes');

  // Precompile byte patterns
  final pWon = BytePattern.fromAscii(' won the ');
  final pRollOn = BytePattern.fromAscii(' roll on ');
  final pWithARoll = BytePattern.fromAscii(' with a roll of ');
  final pWasGivenTo = BytePattern.fromAscii(' was given to ');
  final pWereGivenTo = BytePattern.fromAscii(' were given to ');
  final pHandsYouTheMoney = BytePattern.fromAscii(' hands you the Money (');
  final pThatWasSentFrom = BytePattern.fromAscii(' that was sent from ');
  final pDeliverMoney = BytePattern.fromAscii(" told you, 'I will deliver the Money ");
  final pAsSoonAsPossible = BytePattern.fromAscii(" as soon as possible!'");

  // Warmup (helps JIT)
  _runByteSearch(
    bytes,
    pWon: pWon,
    pRollOn: pRollOn,
    pWithARoll: pWithARoll,
    pWasGivenTo: pWasGivenTo,
    pWereGivenTo: pWereGivenTo,
    pHandsYouTheMoney: pHandsYouTheMoney,
    pThatWasSentFrom: pThatWasSentFrom,
    pDeliverMoney: pDeliverMoney,
    pAsSoonAsPossible: pAsSoonAsPossible,
  );
  _runStringContains(bytes);

  const runs = 5;

  final byteTimes = <int>[];
  final strTimes = <int>[];

  int byteHits = 0;
  int strHits = 0;
  int totalLines = 0;

  for (int r = 0; r < runs; r++) {
    final b = Stopwatch()..start();
    final resB = _runByteSearch(
      bytes,
      pWon: pWon,
      pRollOn: pRollOn,
      pWithARoll: pWithARoll,
      pWasGivenTo: pWasGivenTo,
      pWereGivenTo: pWereGivenTo,
      pHandsYouTheMoney: pHandsYouTheMoney,
      pThatWasSentFrom: pThatWasSentFrom,
      pDeliverMoney: pDeliverMoney,
      pAsSoonAsPossible: pAsSoonAsPossible,
    );
    b.stop();

    final s = Stopwatch()..start();
    final resS = _runStringContains(bytes);
    s.stop();

    byteTimes.add(b.elapsedMilliseconds);
    strTimes.add(s.elapsedMilliseconds);

    // keep values live so optimizer can't throw work away
    byteHits = resB.hits;
    strHits = resS.hits;
    totalLines = resB.totalLines;
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

/// Finds start of the "message" portion of an EQ log line.
/// Scans only the first [cap] bytes for "] "
/// Returns an absolute index into [fileBytes] (>= lineStart and <= lineEnd).
int _findEqLogMessageStartBytes(Uint8List fileBytes, int lineStart, int lineEnd, {int cap = 64}) {
  final lim = (lineStart + cap < lineEnd) ? (lineStart + cap) : lineEnd;

  for (int i = lineStart; i < lim; i++) {
    if (fileBytes[i] == 93 /* ']' */) {
      int s = i + 1;
      if (s < lineEnd && fileBytes[s] == 32 /* space */) s++;
      return s;
    }
  }
  return lineStart;
}

/// Your byte-level scan: no decoding, no per-line string allocation.
/// IMPORTANT: This uses the SAME logical structure/order as the String.contains baseline.
BenchResult _runByteSearch(
    Uint8List fileBytes, {
      required BytePattern pWon,
      required BytePattern pRollOn,
      required BytePattern pWithARoll,
      required BytePattern pWasGivenTo,
      required BytePattern pWereGivenTo,
      required BytePattern pHandsYouTheMoney,
      required BytePattern pThatWasSentFrom,
      required BytePattern pDeliverMoney,
      required BytePattern pAsSoonAsPossible,
    }) {
  int hits = 0;
  int lines = 0;

  int start = 0;
  final n = fileBytes.length;

  while (start < n) {
    int end = indexOfByte(fileBytes, 10 /* \n */, start: start); // LF
    if (end == -1) end = n;

    lines++;

    final msgStart = _findEqLogMessageStartBytes(fileBytes, start, end);

    // SAME boolean expression + SAME short-circuit order as String baseline
    final bool interesting =
    // (wonThe && rollOn && withARoll)
    (pWon.hasMatch(fileBytes, start: msgStart, end: end) &&
        pRollOn.hasMatch(fileBytes, start: msgStart, end: end) &&
        pWithARoll.hasMatch(fileBytes, start: msgStart, end: end)) ||
        // was given / were given
        pWasGivenTo.hasMatch(fileBytes, start: msgStart, end: end) ||
        pWereGivenTo.hasMatch(fileBytes, start: msgStart, end: end) ||
        // (handsYouTheMoney && thatWasSentFrom)
        (pHandsYouTheMoney.hasMatch(fileBytes, start: msgStart, end: end) &&
            pThatWasSentFrom.hasMatch(fileBytes, start: msgStart, end: end)) ||
        // (deliverMoney && asSoonAsPossible)
        (pDeliverMoney.hasMatch(fileBytes, start: msgStart, end: end) &&
            pAsSoonAsPossible.hasMatch(fileBytes, start: msgStart, end: end));

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
  final n = fileBytes.length;

  while (start < n) {
    int end = indexOfByte(fileBytes, 10 /* \n */, start: start);
    if (end == -1) end = n;

    final lineBytes = Uint8List.sublistView(fileBytes, start, end);
    lines++;

    // Decode per line (this is the expensive baseline)
    final line = utf8.decode(lineBytes, allowMalformed: true);

    // SAME message start logic: find "] " and search after it
    int msgStart = line.indexOf('] ');
    if (msgStart != -1) {
      msgStart += 2;
    } else {
      msgStart = 0;
    }
    final msg = (msgStart == 0) ? line : line.substring(msgStart);

    // SAME boolean expression + SAME short-circuit order as byte side
    final bool interesting =
        (msg.contains(' won the ') && msg.contains(' roll on ') && msg.contains(' with a roll of ')) ||
            msg.contains(' was given to ') ||
            msg.contains(' were given to ') ||
            (msg.contains(' hands you the Money (') && msg.contains(' that was sent from ')) ||
            (msg.contains(" told you, 'I will deliver the Money ") && msg.contains(" as soon as possible!'"));

    if (interesting) hits++;

    start = end + 1;
  }

  return BenchResult(lines, hits);
}
