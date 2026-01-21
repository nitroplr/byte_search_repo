import 'dart:typed_data';
import 'package:byte_search/byte_search.dart';
import 'package:demo/patterns/patterns.dart';

class BytePatterns {
  static BytePattern? _chatChannelNamePattern;

  /// Mirrors: Patterns.chatChannelName = '$value:' - user set field in production app
  /// patterns.dart setter should be used
  static void syncFromPatterns() {
    _chatChannelNamePattern = Patterns.chatChannelName == null
        ? null
        : BytePattern.fromAscii(needle: Patterns.chatChannelName!);
  }

  static BytePattern? get chatChannelNamePattern => _chatChannelNamePattern;

  // Precompiled byte patterns
  static final BytePattern wonThe = BytePattern.fromAscii(needle: Patterns.wonThe);
  static final BytePattern rollOn = BytePattern.fromAscii(needle: Patterns.rollOn);
  static final BytePattern withARoll = BytePattern.fromAscii(needle: Patterns.withARoll);
  static final BytePattern wasGivenTo = BytePattern.fromAscii(needle: Patterns.wasGivenTo);
  static final BytePattern wereGivenTo = BytePattern.fromAscii(needle: Patterns.wereGivenTo);
  static final BytePattern youHaveLooted = BytePattern.fromAscii(needle: Patterns.youHaveLooted);
  static final BytePattern hasLooted = BytePattern.fromAscii(needle: Patterns.hasLooted);

  // Suffix used by line.endsWith('.--')
  // Do a bytes suffix check (much faster than searching).
  static final Uint8List dashesPeriodBytes = Uint8List.fromList(Patterns.dashesPeriod.codeUnits);
  static final Uint8List dashes = Uint8List.fromList(Patterns.dashes.codeUnits);
  static final BytePattern handsYouTheMoney = BytePattern.fromAscii(needle: Patterns.handsYouTheMoney);
  static final BytePattern thatWasSentFrom = BytePattern.fromAscii(needle: Patterns.thatWasSentFrom);
  static final BytePattern deliverMoney = BytePattern.fromAscii(needle: Patterns.deliverMoney);
  static final BytePattern asSoonAsPossible = BytePattern.fromAscii(needle: Patterns.asSoonAsPossible);

  /// Byte equivalent of Patterns.lineInteresting.
  static bool lineInterestingBytes({required Uint8List bytes}) {
    // Skip timestamp prefix: "[Mon Nov 03 22:47:08 2025] "
    final int start = afterTimestampStart(bytes: bytes);
    if (isChatChannelLine(bytes: bytes, start: start)) return true;
    if (isLootGivenLine(bytes: bytes, start: start)) return true;
    if (isLootedLine(bytes: bytes, start: start)) return true;
    if (isPlatParcelReceived(bytes: bytes, start: start)) return true;
    if (isPlatParcelSent(bytes: bytes, start: start)) return true;
    return false;
  }

  static bool isChatChannelLine({required Uint8List bytes, int? start}) {
    if (_chatChannelNamePattern == null) return false;
    start = start ?? afterTimestampStart(bytes: bytes);
    if (_chatChannelNamePattern?.hasMatch(haystack: bytes, start: start) ?? false) return true;
    return false;
  }

  static bool isLootGivenLine({required Uint8List bytes, int? start}) {
    start = start ?? afterTimestampStart(bytes: bytes);
    // These three must appear in order.
    if (bytes.containsInOrder([wonThe, rollOn, withARoll], start)) return true;

    // These can appear anywhere.
    if (wasGivenTo.hasMatch(haystack: bytes, start: start)) return true;
    if (wereGivenTo.hasMatch(haystack: bytes, start: start)) return true;

    return false;
  }

  static bool isLootedLine({required Uint8List bytes, int? start}) {
    start = start ?? afterTimestampStart(bytes: bytes);
    return bytes.startsWithBytes(dashes, start: start) &&
        bytes.endsWithBytes(dashesPeriodBytes, start: start) &&
        (youHaveLooted.hasMatch(haystack: bytes, start: start) || hasLooted.hasMatch(haystack: bytes, start: start));
  }

  static bool isPlatParcelReceived({required Uint8List bytes, int? start}) {
    start = start ?? afterTimestampStart(bytes: bytes);
    return bytes.containsInOrder([handsYouTheMoney, thatWasSentFrom], start);
  }

  static bool isPlatParcelSent({required Uint8List bytes, int? start}) {
    start = start ?? afterTimestampStart(bytes: bytes);
    return bytes.containsInOrder([deliverMoney, asSoonAsPossible], start);
  }

  /// Returns the index immediately after "] " if present, else 0.
  /// This avoids scanning the timestamp for every pattern.
  static int afterTimestampStart({required Uint8List bytes}) {
    // Typical EQ log line starts with '['
    if (bytes.isEmpty || bytes[0] != 0x5B /* '[' */ ) return 0;

    // Find the first ']' (0x5D). Timestamp is short; cap the scan to stay cheap.
    // 30 is plenty for "[Mon Nov 03 22:47:08 2025]"
    final int cap = bytes.length < 30 ? bytes.length : 30;

    for (int i = 1; i < cap; i++) {
      if (bytes[i] == 0x5D /* ']' */ ) {
        // If followed by a space, skip it too.
        final int next = i + 1;
        if (next < bytes.length && bytes[next] == 0x20 /* ' ' */ ) return next + 1;
        return next;
      }
    }

    return 0;
  }
}
