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
  static const String deliverMoney = ' told you, \'I will deliver the Money ';
  static const String asSoonAsPossible = " as soon as possible!'";

  static bool lineInteresting({required String line}) {
    int start = _afterTimestampStartString(line: line);
    if (_chatChannelName != null && line.contains(_chatChannelName!, start)) return true;
    if ((line.contains(wonThe, start) && line.contains(rollOn, start) && line.contains(withARoll, start))) return true;
    if (line.endsWith(dashesPeriod)) return true;
    if (line.contains(wasGivenTo, start)) return true;
    if (line.contains(wereGivenTo, start)) return true;
    if ((line.contains(handsYouTheMoney, start) && line.contains(thatWasSentFrom, start))) return true;
    if ((line.contains(deliverMoney, start) && line.contains(asSoonAsPossible, start))) return true;
    return false;
  }

  static bool isLootGivenLine({required String line}) {
    return (line.contains(wonThe) && line.contains(rollOn) && line.contains(withARoll)) ||
        line.contains(wasGivenTo) ||
        line.contains(wereGivenTo);
  }

  static bool isLootedLine({required String line}) {
    return line.endsWith(dashesPeriod) && (line.contains(youHaveLooted) || line.contains(hasLooted));
  }

  static int _afterTimestampStartString({required String line}) {
    // Typical EQ log line starts with '['
    if (line.isEmpty || line.codeUnitAt(0) != 0x5B /* '[' */ ) return 0;

    // Find the first ']' (0x5D). Timestamp is short; cap the scan to stay cheap.
    // 30 is plenty for "[Mon Nov 03 22:47:08 2025]"
    final int cap = line.length < 30 ? line.length : 30;

    for (int i = 1; i < cap; i++) {
      if (line.codeUnitAt(i) == 0x5D /* ']' */ ) {
        // If followed by a space, skip it too.
        final int next = i + 1;
        if (next < line.length && line.codeUnitAt(next) == 0x20 /* ' ' */ ) {
          return next + 1;
        }
        return next;
      }
    }

    return 0;
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
