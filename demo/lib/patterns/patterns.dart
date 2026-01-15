import 'byte_patterns.dart';

class Patterns {
  static String? _chatChannelName;

  /// user set field in production app
  static set chatChannelName(String? value) {
    _chatChannelName = value == null ? null : '$value:';
    BytePatterns.syncFromPatterns();
  }

  static String? get chatChannelName => _chatChannelName;

  static const String wonThe = ' won the ';
  static const String rollOn = ' roll on ';
  static const String withARoll = ' with a roll of ';
  static const String wasGivenTo = ' was given to ';
  static const String wereGivenTo = ' were given to ';
  static const String youHaveLooted = '--You have looted ';
  static const String hasLooted = ' has looted ';
  static const String dashes = '--';
  static const String dashesPeriod = '.--';
  static const String handsYouTheMoney = ' hands you the Money (';
  static const String thatWasSentFrom = ' that was sent from ';
  static const String deliverMoney = " told you, 'I will deliver the Money ";
  static const String asSoonAsPossible = " as soon as possible!'";

  static bool lineInteresting({required String line}) {
    // Skip timestamp prefix: "[Mon Nov 03 22:47:08 2025] "
    final int start = _afterTimestampStartString(line: line);
    if (isChatChannelLine(line: line, start: start)) return true;
    if (isLootGivenLine(line: line, start: start)) return true;
    if (isLootedLine(line: line, start: start)) return true;
    if (isPlatParcelReceived(line: line, start: start)) return true;
    if (isPlatParcelSent(line: line, start: start)) return true;
    return false;
  }

  static bool isChatChannelLine({required String line, int? start}) {
    if (_chatChannelName == null) return false;
    start = start ?? _afterTimestampStartString(line: line);
    if (line.contains(_chatChannelName!, start)) return true;
    return false;
  }

  static bool isLootGivenLine({required String line, int? start}) {
    start = start ?? _afterTimestampStartString(line: line);
    // These three must appear in order.
    if (_containsInOrder(s: line, needles: [wonThe, rollOn, withARoll], start: start)) return true;

    // These can appear anywhere.
    if (line.contains(wasGivenTo, start)) return true;
    if (line.contains(wereGivenTo, start)) return true;

    return false;
  }

  static bool isLootedLine({required String line, int? start}) {
    start = start ?? _afterTimestampStartString(line: line);
    return line.startsWith(dashes, start) &&
        line.endsWith(dashesPeriod) &&
        (line.contains(youHaveLooted, start) || line.contains(hasLooted, start));
  }

  static bool isPlatParcelReceived({required String line, int? start}) {
    start = start ?? _afterTimestampStartString(line: line);
    return _containsInOrder(s: line, needles: [handsYouTheMoney, thatWasSentFrom], start: start);
  }

  static bool isPlatParcelSent({required String line, int? start}) {
    start = start ?? _afterTimestampStartString(line: line);
    return _containsInOrder(s: line, needles: [deliverMoney, asSoonAsPossible], start: start);
  }

  static int _afterTimestampStartString({required String line}) {
    // Typical EQ log line starts with '['
    if (line.isEmpty || line.codeUnitAt(0) != 0x5B /* '[' */) return 0;

    // Find the first ']' (0x5D). Timestamp is short; cap the scan to stay cheap.
    // 30 is plenty for "[Mon Nov 03 22:47:08 2025]"
    final int cap = line.length < 30 ? line.length : 30;

    for (int i = 1; i < cap; i++) {
      if (line.codeUnitAt(i) == 0x5D /* ']' */) {
        // If followed by a space, skip it too.
        final int next = i + 1;
        if (next < line.length && line.codeUnitAt(next) == 0x20 /* ' ' */) {
          return next + 1;
        }
        return next;
      }
    }

    return 0;
  }

  static bool _containsInOrder({required String s, required List<String> needles, int start = 0}) {
    int i = start;
    for (final n in needles) {
      final int hit = s.indexOf(n, i);
      if (hit == -1) return false;
      // Move start forward so the next phrase must occur after this one.
      i = hit + n.length;
    }
    return true;
  }

  static const Map<String, String> months = {
    'Jan': '01',
    'Feb': '02',
    'Mar': '03',
    'Apr': '04',
    'May': '05',
    'Jun': '06',
    'Jul': '07',
    'Aug': '08',
    'Sep': '09',
    'Oct': '10',
    'Nov': '11',
    'Dec': '12',
  };
}